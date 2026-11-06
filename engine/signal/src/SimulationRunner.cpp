/*=========================================================================

  Program:   NutateSignal
  Module:    SimulationRunner.cpp
  Language:  C++

=========================================================================*/

#include "SimulationRunner.h"

#include "CudaBackend.h"

#include "CmdInterp.h"
#include "CpuPartition.h"
#include "Execution.h"
#include "Functions.h"

#ifdef USE_OpenMP
#include "omp.h"
#endif //USE_OpenMP

#include <cstdlib>
#include <iostream>
#include <stdio.h>
#include <algorithm>

#if defined(NUTATE_SIGNAL_CPU_BINARY)
static int runSimulationHost(Execution & run, CmdInterp & cmdInterp)
{
	// References keep the time-step loop readable without copying simulation
	// state or repeatedly traversing the Execution interface.
	// Interval durations are seconds, gradients T/m, and carrier offsets Hz.
	Execution::Info & info = run.getInfo();
	std::vector<Voxel> & phantom = run.getPhantom();
	Execution::Sequence & sequence = run.getSequence();
	std::vector<float> & intervalSeconds = sequence.time;
	std::vector<int> & acquisitionEvents = sequence.acq;
	std::vector<std::vector<std::complex<float> > > & rf = sequence.rf;
	std::vector<std::vector<float> > & delFreq = sequence.delFreq;
	std::vector<float> & gX = sequence.gX;
	std::vector<float> & gY = sequence.gY;
	std::vector<float> & gZ = sequence.gZ;

/*******************************************************************************/
	int workerCount = 1, workerIndex = 0;
#ifdef USE_OpenMP
	std::vector<std::vector<std::complex<float> > > * workerSignals = nullptr;
	omp_set_num_threads((int)info.thread);
	std::vector<std::vector<std::complex<float> > > signalSamples;
#endif //USE_OpenMP
/*******************************************************************************/

	std::vector<std::vector<std::complex<float> > > workerSamples; // [receiver][acquired sample] within this worker

	Vect3D<float> kCyclesPerMeter;
	kCyclesPerMeter = 0;
	std::vector<Vect3D<float> > trajectorySamples;

	std::vector<std::complex<float> > rfAtInterval;
	std::vector<float> carrierHzAtInterval;
	Vect3D<float> gradientTeslaPerMeter;
	gradientTeslaPerMeter = 0;
	unsigned int intervalCount = (unsigned int) intervalSeconds.size();
	ProgressReporter progress((std::uint64_t)phantom.size() * intervalCount);
	const unsigned int progressStride = std::max(1u,
		intervalCount / 1000u + (intervalCount % 1000u != 0u));
	unsigned int publishedSteps;
	std::complex<double> workerSignalSum;
	std::complex<double> combinedSignalSum;

	unsigned int intervalIndex;
	int coilIndex;
	std::size_t voxelIndex;
	std::size_t threadStartRange, threadEndRange;

#ifdef USE_OpenMP
#pragma omp parallel private(threadStartRange,threadEndRange,workerIndex,voxelIndex,coilIndex,rfAtInterval,gradientTeslaPerMeter,carrierHzAtInterval,workerSignalSum,intervalIndex,workerSamples,publishedSteps)
	{
#pragma omp single
		{
			workerCount = omp_get_num_threads();
			workerSignals = new std::vector<std::vector<std::complex<float> > > [workerCount];
		} // Implicit barrier publishes the actual team size and worker slots.
		workerIndex = omp_get_thread_num();
#endif //USE_OpenMP
		workerSamples.resize(info.numRx);
		const SignalCpuPartition::Range range = SignalCpuPartition::range(phantom.size(), workerIndex, workerCount);
		threadStartRange = range.begin;
		threadEndRange = range.end;
		publishedSteps = 0u;

		for (intervalIndex = 0; intervalIndex < intervalCount; intervalIndex++)
		{
			rfAtInterval.clear();
			carrierHzAtInterval.clear();
			for (coilIndex=0; coilIndex<info.numTx; coilIndex++)
			{
				// Gather the held RF values for this interval across transmitters.
				rfAtInterval.push_back(rf[coilIndex][intervalIndex]); // [coil][time] -> [coil]

				// The shared rotating-frame carrier is specified in Hz.
				carrierHzAtInterval.push_back(delFreq[coilIndex][intervalIndex]); // [coil][time] -> [coil]
			}

			// Nominal spatial gradient for this held-field interval, in T/m.
			gradientTeslaPerMeter.x = gX[intervalIndex];
			gradientTeslaPerMeter.y = gY[intervalIndex];
			gradientTeslaPerMeter.z = gZ[intervalIndex];

			if(acquisitionEvents[intervalIndex] == 1) // Original ADC midpoint, independent of field segmentation.
			{
				const float timeToSampleSeconds = sequence.sampleOffset[intervalIndex];
				const float timeAfterSampleSeconds = intervalSeconds[intervalIndex] - timeToSampleSeconds;
				// sampleOffset is relative to this field interval. Field segmentation
				// can place the ADC midpoint away from half this interval.

				// Evolve derivatives and magnetization to the original ADC observation.
				for (voxelIndex = threadStartRange; voxelIndex < threadEndRange; voxelIndex++) // thread specific
				{
					phantom[voxelIndex].calculateEffectiveField(rfAtInterval, carrierHzAtInterval,
						gradientTeslaPerMeter, info.aveB1Plus, info.wid,
						info.offSet[voxelIndex%(info.numIso.x*info.numIso.y*info.numIso.z)]);
					if (timeToSampleSeconds > 0.0f) phantom[voxelIndex].evolveMagnetization(gradientTeslaPerMeter, timeToSampleSeconds);
				}

				if (info.numRx > 1)
				{
					for (voxelIndex = threadStartRange; voxelIndex < threadEndRange; voxelIndex++) // thread specific
					{
						phantom[voxelIndex].calculatePhaseDerivatives();
					}
				}

				// Observe every receiver at the same state. Preserve double voxel sums
				// and the existing per-worker float storage.
				for (coilIndex=0; coilIndex < info.numRx; coilIndex++)
				{
					workerSignalSum = std::complex<double>(0,0);
					for (voxelIndex = threadStartRange; voxelIndex < threadEndRange; voxelIndex++) // thread specific
					{
						if (info.numRx == 1)
						{
							phantom[voxelIndex].calculatePhaseDerivatives();
						}
						workerSignalSum += (std::complex<double>) phantom[voxelIndex].receiveSignalContribution(coilIndex, info.wid, info.b0, info.numIso);
					}
					workerSamples[coilIndex].push_back((std::complex<float>)workerSignalSum);
				}

				// Evolve the remainder after all receiver contributions are observed.
				for (voxelIndex = threadStartRange; voxelIndex < threadEndRange; voxelIndex++) // thread specific
				{
					if (timeAfterSampleSeconds > 0.0f) phantom[voxelIndex].evolveMagnetization(gradientTeslaPerMeter, timeAfterSampleSeconds);
				}

				//-----------------------------------------------------------------------------------------------------------------//

				if (workerIndex == 0) // do only in thread 0
				{
					// Track nominal k in cycles/m using gamma in Hz/T, gradient T/m and time s.
					if (gradientTeslaPerMeter.x != 0)
					{
						kCyclesPerMeter.x += info.nucleus.gammaHzPerT * gradientTeslaPerMeter.x * timeToSampleSeconds;
					}
					if (gradientTeslaPerMeter.y != 0)
					{
						kCyclesPerMeter.y += info.nucleus.gammaHzPerT * gradientTeslaPerMeter.y * timeToSampleSeconds;
					}
					if (gradientTeslaPerMeter.z != 0)
					{
						kCyclesPerMeter.z += info.nucleus.gammaHzPerT * gradientTeslaPerMeter.z * timeToSampleSeconds;
					}

					trajectorySamples.push_back(kCyclesPerMeter);

					if (gradientTeslaPerMeter.x != 0)
					{
						kCyclesPerMeter.x += info.nucleus.gammaHzPerT * gradientTeslaPerMeter.x * timeAfterSampleSeconds;
					}
					if (gradientTeslaPerMeter.y != 0)
					{
						kCyclesPerMeter.y += info.nucleus.gammaHzPerT * gradientTeslaPerMeter.y * timeAfterSampleSeconds;
					}
					if (gradientTeslaPerMeter.z != 0)
					{
						kCyclesPerMeter.z += info.nucleus.gammaHzPerT * gradientTeslaPerMeter.z * timeAfterSampleSeconds;
					}
				}

				//-----------------------------------------------------------------------------------------------------------------//

			} /* ADC observation */
			else
			{
				// Evolve the full interval before applying its reset/crush event.
				for (voxelIndex = threadStartRange; voxelIndex < threadEndRange; voxelIndex++) // thread specific
				{
					phantom[voxelIndex].calculateEffectiveField(rfAtInterval, carrierHzAtInterval,
						gradientTeslaPerMeter, info.aveB1Plus, info.wid,
						info.offSet[voxelIndex%(info.numIso.x*info.numIso.y*info.numIso.z)]);
					phantom[voxelIndex].evolveMagnetization(gradientTeslaPerMeter, intervalSeconds[intervalIndex]);
				}

				switch (acquisitionEvents[intervalIndex])
				{
				case 0: // Continue the nominal gradient integral without observing a sample.
					if (workerIndex == 0) // do only in thread 0
					{
						// Equation used: dK = gammaBar * Gradient * dTime
						if (gradientTeslaPerMeter.x!=0)
						{
							kCyclesPerMeter.x += info.nucleus.gammaHzPerT * gradientTeslaPerMeter.x * intervalSeconds[intervalIndex];
						}
						if (gradientTeslaPerMeter.y!=0)
						{
							kCyclesPerMeter.y += info.nucleus.gammaHzPerT * gradientTeslaPerMeter.y * intervalSeconds[intervalIndex];
						}
						if (gradientTeslaPerMeter.z!=0)
						{
							kCyclesPerMeter.z += info.nucleus.gammaHzPerT * gradientTeslaPerMeter.z * intervalSeconds[intervalIndex];
						}
					}
					break ;

				case -2: // Clear transverse magnetization and derivatives; preserve pool Mz.
					for (voxelIndex = threadStartRange; voxelIndex < threadEndRange; voxelIndex++)
					{
						phantom[voxelIndex].setMagn(0,0);
						phantom[voxelIndex].setDxMagn(0,0,0);
						phantom[voxelIndex].setDyMagn(0,0,0);
						phantom[voxelIndex].setDzMagn(0,0,0);
						phantom[voxelIndex].setDwMagn(0,0,0);
						phantom[voxelIndex].calculatePhaseDerivatives();
					}
					// Ideal crushing also resets the tracked trajectory.
					/* fall through */
				case -1: // Reset trajectory bookkeeping while retaining the evolved spin state.
					if (workerIndex == 0) // do only in thread 0
					{
						kCyclesPerMeter = 0;
					}
					break;
				default:
					if (workerIndex == 0)
					{
						progress.finishLine();
					}
					std::cout << "WARNING: Error in sequence file: see time index #" << intervalIndex << std::endl;
					std::cout << "Value causing error is " << acquisitionEvents[intervalIndex] << std::endl;
					std::cout << "Sequence file only accepts values 1, 0, -1, and -2.\n";
					std::cout << "Press enter to continue simulation.\n";
					std::cin.get();
					break;

				} /* event handling */

			} /* interval without acquisition */

			const unsigned int completedSteps = intervalIndex + 1u;
			if (completedSteps - publishedSteps >= progressStride || completedSteps == intervalCount)
			{
				progress.addCompletedWork((std::uint64_t)(threadEndRange - threadStartRange)
					* (completedSteps - publishedSteps));
				publishedSteps = completedSteps;
			}

		} /* interval loop */

#ifdef USE_OpenMP
		workerSignals[workerIndex] = workerSamples;
	} /* parallel voxel evolution */
#endif
	// All worker intervals are complete before reducing and exporting signal.
	progress.complete();

#ifdef USE_OpenMP
	// The parallel region's implicit barrier completes all worker buffers before
	// this single owner sums float worker samples in worker order using double.
	signalSamples.resize(workerSignals[0].size());
	for (coilIndex=0; coilIndex<(int)workerSignals[0].size(); coilIndex++)
	{
		signalSamples[coilIndex].resize(workerSignals[0][coilIndex].size());
	}

	unsigned int sampleIndex;
	int worker;
	for(coilIndex=0; coilIndex<(int)signalSamples.size(); coilIndex++)
	{
		for(sampleIndex=0; sampleIndex<(unsigned int)workerSignals[0][coilIndex].size(); sampleIndex++) // acquired sample
		{
			combinedSignalSum = std::complex<double>(0,0);
			for(worker=0; worker<(int)workerCount; worker++) // thread
			{
				combinedSignalSum += (std::complex<double>) workerSignals[worker][coilIndex][sampleIndex];
			}
			signalSamples[coilIndex][sampleIndex] = (std::complex<float>) (combinedSignalSum);
		}
	}
#endif //USE_OpenMP

	progress.finishLine();
	double TheTime = progress.elapsedSeconds();
	printf ("ID %d used %f seconds.\n", workerIndex, TheTime);

	if(workerIndex == 0) // do only in thread 0
	{
#ifndef USE_OpenMP
		run.setKSpace(workerSamples);
#endif //USE_OpenMP
#ifdef USE_OpenMP
		run.setKSpace(signalSamples);
		delete [] workerSignals;
#endif //USE_OpenMP
		if (!run.expPhantomKSpace(cmdInterp)) return EXIT_FAILURE;

		run.setKMap(trajectorySamples);
		if (!run.expPhantomKMap(cmdInterp)) return EXIT_FAILURE;

		printf("Execution completed, press enter to exit.\n");
		std::cin.get();
	}

	return (EXIT_SUCCESS);
}
#endif

int runSimulation(Execution & run, CmdInterp & cmdInterp)
{
#if defined(NUTATE_SIGNAL_CPU_BINARY)
	std::cout << "Simulation backend: CPU (OpenMP host implementation).\n";
	return runSimulationHost(run, cmdInterp);
#elif defined(NUTATE_SIGNAL_GPU_BINARY)
	if (!cudaBackendAvailable())
	{
		std::cerr << "ERROR: NutateSignal_GPU was built without an available CUDA backend.\n";
		return EXIT_FAILURE;
	}

	std::cout << "Simulation backend: NVIDIA CUDA.\n";
	return runSimulationCuda(run, cmdInterp);
#else
#error "A NutateSignal CPU or GPU binary type must be selected by CMake."
#endif
}
