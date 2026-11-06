/*=========================================================================


  Program:   NutateNoise
  Module:    $RCSfile: Execution.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 20:53:31 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include "Execution.h"
#include "Functions.h"
#include "Vect3D.h"

#include <cassert>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <sstream>

#include "../../common/ThermalMagnetization.h"

// ------------------------------------------------------------------------------

Execution::Execution(CmdInterp & cmdInterp)
{
	initFlag = 1;

	GeomIn geomIn(cmdInterp);
	initFlag = initFlag && geomIn.geomFlag;

	TissIn tissIn(cmdInterp);
	initFlag = initFlag && tissIn.tissFlag;

	SeqnIn seqnIn(cmdInterp);
	initFlag = initFlag && seqnIn.seqnFlag;
	if (!seqnIn.seqnFlag) return;

	E1MinsIn e1MinsIn(cmdInterp, geomIn.getGeomHeader().geomList,
		geomIn.getGeomHeader().totNumVox);
	initFlag = initFlag && e1MinsIn.e1MinsFlag;

	initFlag = initFlag && initPhantomInfo(cmdInterp, seqnIn, geomIn);
	initFlag = initFlag && initPhantomSeqn(seqnIn);
	initFlag = initFlag && initPhantomGeom(geomIn);
	initFlag = initFlag && initPhantomTiss(tissIn);

	initFlag = initFlag && initPhantomE1Mins(e1MinsIn);
	initFlag = initFlag && initPhantomKNoise();

#ifdef DEBUG
	cout<<initFlag<<endl;
#endif
}

Execution::~Execution()
{
	for (unsigned int i = 0; i < noiseInfo.aMat.size(); i++)
	{
		noiseInfo.aMat[i].clear();
	}
	noiseInfo.aMat.clear();
	for (unsigned int i = 0; i < noiseInfo.rMat.size(); i++)
	{
		noiseInfo.rMat[i].clear();
	}
	noiseInfo.rMat.clear();

	sequence.time.clear();
	sequence.acq.clear();
	phantom.clear();

	for (unsigned int i = 0; i < kNoise.size(); i++)
	{
		kNoise[i].clear();
	}
	kNoise.clear();

}

// ------------------------------------------------------------------------------

bool Execution::initPhantomInfo(CmdInterp & cmdInterp, SeqnIn & seqnIn, GeomIn & geomIn)
{
	info.numRx = seqnIn.getSeqnHeader().numRx;

	info.totNumVox = geomIn.getGeomHeader().totNumVox;

	info.wid = geomIn.getGeomHeader().wid;

	info.nex = cmdInterp.getCmdValues().NEX;

	return true;
}

// ------------------------------------------------------------------------------

bool Execution::initPhantomSeqn(const SeqnIn & seqnIn)
{
	sequence.time = seqnIn.getTime();
	sequence.dwell = seqnIn.getDwell();
	sequence.acq = seqnIn.getAcq();
	return true;
}

// ------------------------------------------------------------------------------

bool Execution::initPhantomGeom(const GeomIn & geomIn)
{
	phantom = geomIn.getGeomData();
	return true;
}

// ------------------------------------------------------------------------------

bool Execution::initPhantomTiss(const TissIn & tissIn)
{
	const std::map<int, TissType> & tissueMap = tissIn.getTissMap();
	std::set<int> missingIds;
	for (unsigned int i=0; i<phantom.size(); i++)
	{
		if (tissueMap.find(phantom[i].geomInfo.id) == tissueMap.end())
		{
			missingIds.insert(phantom[i].geomInfo.id);
		}
	}
	if (!missingIds.empty())
	{
		std::cout << "Fatal Error: Undefined tissue IDs in selected geometry:";
		for (int id : missingIds) std::cout << ' ' << id;
		std::cout << ". Every selected ID must have an entry in Tissue Type File.\n";
		return false;
	}

	for (unsigned int i=0; i<phantom.size(); i++)
	{
		if (!phantom[i].setTiss(tissueMap)) return false;
	}
	return true;
}

// ------------------------------------------------------------------------------

bool Execution::initPhantomE1Mins(const E1MinsIn & e1MinsIn)
{
	std::vector<Vect3D<std::complex<float> > > temp;
	Vect3D<std::complex<float> > defaultE1Mins;
	defaultE1Mins.x = std::complex<float>(1,0);
	defaultE1Mins.y = std::complex<float>(1,0);
	defaultE1Mins.z = std::complex<float>(1,0);

	std::vector<std::vector< Vect3D<std::complex<float> > > > tempE1MinsData;
	tempE1MinsData = e1MinsIn.getE1MinsData();

	for (unsigned int i=0; i<tempE1MinsData.size(); i++)
	{
		if (phantom.size() != tempE1MinsData[i].size())
		{
			std::cout << "Fatal Error: E1- Field data from " << e1MinsIn.fName[i] << " does not match the geometry data!";
			std::cout << "Check the header and data length in" << e1MinsIn.fName[i] << std::endl;
			printf("Execution terminated, press enter to exit.\n");
			std::cin.get();
			return false;
		}
	}

	if ((unsigned short int)tempE1MinsData.size() > info.numRx)
	{
		printf("Fatal Error: More E1- files from commandline input than needed in sequence file!\n");
		printf("Execution terminated, press enter to exit.\n");
		std::cin.get();
		return false;
	}

	for (unsigned int j=0; j<phantom.size(); j++)
	{
		temp.clear();
		for (unsigned int i=0; i<tempE1MinsData.size(); i++)
		{
			temp.push_back(tempE1MinsData[i][j]);
		}

		// Missing trailing receiver maps use the historical homogeneous field.
		// Supplied maps always occupy the leading receiver indices.
		for (unsigned int n=0; n<(info.numRx - tempE1MinsData.size()); n++)
		{
			temp.push_back(defaultE1Mins);
		}

		phantom[j].setE1Mins(temp);
	}
	return true;
}

// ------------------------------------------------------------------------------

bool Execution::initPhantomKNoise()
{
	typedef std::vector<std::complex<double> > ComplexRow;
	const std::complex<double> zero(0.0, 0.0);
	noiseInfo.rMat.assign(info.numRx, ComplexRow(info.numRx, zero));
	noiseInfo.aMat.assign(info.numRx, ComplexRow(info.numRx, zero));

	// Cao et al., MRM 72:237-247 (2014), Eq. 11:
	// Phi_ij = voxelVolume * sum_n sigma_n E_n,i dot conjugate(E_n,j).
	for (unsigned short int i = 0; i < info.numRx; ++i)
	{
		for (unsigned short int j = i; j < info.numRx; ++j)
		{
			std::complex<double> overlap(0.0, 0.0);
			for (unsigned int k = 0; k < phantom.size(); ++k)
			{
				const Vect3D<std::complex<float> > & fieldI = phantom[k].eInfo.e1Mins[i];
				const Vect3D<std::complex<float> > & fieldJ = phantom[k].eInfo.e1Mins[j];
				const std::complex<double> dotProduct =
					std::complex<double>(fieldI.x) * std::conj(std::complex<double>(fieldJ.x)) +
					std::complex<double>(fieldI.y) * std::conj(std::complex<double>(fieldJ.y)) +
					std::complex<double>(fieldI.z) * std::conj(std::complex<double>(fieldJ.z));
				overlap += static_cast<double>(phantom[k].tissInfo.sigmaCon) * dotProduct;
			}
			noiseInfo.rMat[i][j] = overlap;
			noiseInfo.rMat[j][i] = std::conj(overlap);
		}
	}

	const double voxelVolume = static_cast<double>(info.wid.x) *
		static_cast<double>(info.wid.y) * static_cast<double>(info.wid.z);
	for (unsigned short int i = 0; i < info.numRx; ++i)
	{
		for (unsigned short int j = 0; j < info.numRx; ++j)
		{
			noiseInfo.rMat[i][j] *= voxelVolume;
		}
	}

	// Eq. 12 requires a whole-matrix square-root factor. A lower-triangular
	// factor L is statistically equivalent when L*L^H = 4*k*T*Phi. ADC
	// bandwidth remains applied per sample in main.cpp as 1/timeStep.
	std::vector<std::vector<std::complex<double> > > thermalCovariance = noiseInfo.rMat;
	// Cao eq. 12: covariance scales with k*T; ADC bandwidth is applied below
	// by the existing acquisition path. Signal and noise use one sample T.
	const double thermalScale = 4.0 * nutate::boltzmannJoulePerKelvin *
		nutate::nucleusConfig().sampleTemperatureK;
	for (unsigned short int i = 0; i < info.numRx; ++i)
	{
		for (unsigned short int j = 0; j < info.numRx; ++j)
		{
			thermalCovariance[i][j] *= thermalScale;
		}
	}

	std::string factorError;
	if (!factorHermitianPositiveSemidefinite(thermalCovariance,
		noiseInfo.aMat, factorError))
	{
		std::cout << "Fatal Error: Unable to factor the receive-noise covariance matrix: "
			<< factorError << std::endl;
		return false;
	}
	return true;
}

// ------------------------------------------------------------------------------

bool Execution::expPhantomKNoise(CmdInterp & cmdInterp)
{
	assert(!kNoise.empty());

	size_t ptr;
	std::vector<std::vector<std::string> > expFName;
	std::string tempFName;
	std::stringstream tempSS;

	expFName.resize(info.nex);
    std::cout << "nex: " << info.nex << std::endl;
	for (unsigned int k=0; k<info.nex; k++)
	{
		expFName[k].clear();
		for (unsigned int n=1; n<=info.numRx; n++)
		{
			tempFName.clear();
			tempFName = cmdInterp.getCmdValues().kNoise;
			tempSS << n;

			ptr = tempFName.rfind(".");
			if (ptr != std::string::npos)	// insert or append the coil number
			{
				tempFName.insert(ptr, tempSS.str());
			}
			else
			{
				tempSS << ".bin";
				tempFName.append(tempSS.str());
			}
			tempSS.str("");

			std::string str1 ("\\noiseSet");
			tempSS << (k+1);
			ptr = tempFName.rfind("\\");
			str1 = str1.append(tempSS.str()); str1 = str1.append("\\");
			if (ptr != std::string::npos)	// insert the nex number and folder name
			{
				tempFName.replace(ptr,1,str1);
			}
			tempSS.str("");

			expFName[k].push_back(tempFName);

		}

		assert(expFName[k].size() == kNoise[k].size());

		std::fstream fHandle;
		
		for (unsigned int i=0; i<expFName[k].size(); i++)
		{
            std::filesystem::path filePath(expFName[k][i]);
            std::filesystem::create_directories(filePath.parent_path());
			fHandle.open(expFName[k][i].c_str(), std::ios::out | std::ios::binary);

			if (fHandle.fail())
			{
				std::cout << "\n\"" << expFName[k][i] << "\" failed to open!\n";
				printf("Execution terminated, press enter to exit.\n");
				std::cin.get();
				return false;
			}

			// kNoiseData______________________________________________________________
			for (unsigned int m=0; m<kNoise[k][i].size(); m++)
			{
				fHandle.write(reinterpret_cast<char*>(&kNoise[k][i][m]), sizeof(kNoise[k][i][m]));	
			}

			fHandle.close();
		}
	}
	return true;
}

// ------------------------------------------------------------------------------
