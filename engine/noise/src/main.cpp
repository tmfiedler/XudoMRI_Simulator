/*=========================================================================

  Program:   NutateNoise
  Module:    $RCSfile: main.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 21:18:18 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/

#include "Execution.h"

#include <cmath>
#include <complex>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <iostream>
#include <exception>
#include <vector>

#ifndef NUTATE_VERSION
#define NUTATE_VERSION "unknown"
#endif

int main(int argc, char *argv[])
{
	std::cout << "NutateNoise " << NUTATE_VERSION << std::endl;
	if (argc == 2 && std::strcmp(argv[1], "--version") == 0)
	{
		return EXIT_SUCCESS;
	}

	try
	{
	// Fail clearly on a missing or invalid registry before preparing a run.
	(void)nutate::nucleusConfig();
	CmdInterp cmdInterp;
	if (!(cmdInterp.interpCmd(argc, argv)))
	{
		return EXIT_FAILURE;
	}

	Execution run(cmdInterp);

	if (!(run.initFlag))
	{
		return EXIT_FAILURE;
	}

	// Local copies keep the sampling loop independent of the input objects.
	Execution::Info info = run.getInfo();
	std::vector<float> dwell = run.getSequence().dwell;
	std::vector<int> acq = run.getSequence().acq;

	const clock_t startTime = clock();

	const std::uint64_t noiseSeed = cmdInterp.getCmdFlags().noiseSeed
		? cmdInterp.getCmdValues().noiseSeed : generateNoiseSeed();
	ComplexGaussianGenerator randomNoise(noiseSeed);
	std::cout << "Noise seed: " << noiseSeed << std::endl;

	std::vector<std::vector<std::vector<std::complex<float> > > > kNoiseData; // [NEX][Coil][Acq]
	std::vector<std::vector<std::complex<float> > > tempKNoiseData; // [Coil][Acq]
	kNoiseData.resize(info.nex);
			
	std::vector<std::complex<double> > independentNoise(info.numRx);
	const std::vector<std::vector<std::complex<double> > > aMat = run.getNoiseInfo().aMat;

	const unsigned int tempSize = (unsigned int) acq.size();
	std::complex<double> temp;

	std::cout << "tempSize" << tempSize << std::endl;
	std::cout << "info.nex" << info.nex << std::endl;
	// Generate one complex noise value per coil and acquisition window.
	for (unsigned int nex = 0; nex < info.nex; nex++)
	{
		tempKNoiseData.clear();
		tempKNoiseData.resize(info.numRx);
		const float processIndicator = (float(nex) / float(info.nex)) * 100.0f;
		std::cout << "Calculating: " << processIndicator << "% done," << std::endl;

		for (unsigned int timeIndex = 0; timeIndex < tempSize; timeIndex++)
		{
			if (acq[timeIndex] == 1)
			{
				if (dwell[timeIndex] <= 0.0f)
				{
					std::cout << "Fatal Error: Acquisition timestep must be positive for noise bandwidth scaling." << std::endl;
					return EXIT_FAILURE;
				}

				// Cao et al. Eq. 12: multiply independent circular complex
				// Gaussian samples by the covariance factor. The existing
				// simulator convention applies BW = 1/original ADC dwell here.
				for (unsigned short int j = 0; j < info.numRx; j++)
				{
					independentNoise[j] = randomNoise.next();
				}
				for (unsigned short int i = 0; i < info.numRx; i++)
				{
					temp = std::complex<double>(0.0, 0.0);
					for (unsigned short int j = 0; j < info.numRx; j++)
					{
						temp += aMat[i][j] * independentNoise[j];
					}
					tempKNoiseData[i].push_back((std::complex<float>)
						(temp * std::sqrt((double)1 / (double)dwell[timeIndex])));
				}
			}
		}
		kNoiseData[nex] = tempKNoiseData;
	}
			
	const clock_t endTime = clock();
	const double elapsedSeconds = double(endTime - startTime) / double(CLOCKS_PER_SEC);
	printf("Simulation took %f seconds.\n", elapsedSeconds);

	run.setKNoise(kNoiseData);
	if (!run.expPhantomKNoise(cmdInterp))
	{
		return EXIT_FAILURE;
	}

	printf("Execution completed successfully, press enter to exit.\n");
	std::cin.get();
	
	return EXIT_SUCCESS;
	}
	catch (const std::exception & error)
	{
		std::cerr << "Fatal Error: " << error.what() << std::endl;
		return EXIT_FAILURE;
	}
}
