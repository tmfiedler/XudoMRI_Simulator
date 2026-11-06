/*=========================================================================

  Program:   NutateSignal
  Module:    CudaBackend.cpp
  Language:  C++

=========================================================================*/

#include "CudaBackend.h"

#include <iostream>

#ifdef NUTATE_HAS_CUDA_BACKEND
int runSimulationCudaImpl(Execution & run, CmdInterp & cmdInterp);
#endif

bool cudaBackendAvailable()
{
#ifdef NUTATE_HAS_CUDA_BACKEND
	return true;
#else
	return false;
#endif
}

int runSimulationCuda(Execution & run, CmdInterp & cmdInterp)
{
#ifdef NUTATE_HAS_CUDA_BACKEND
	return runSimulationCudaImpl(run, cmdInterp);
#else
	(void)run;
	(void)cmdInterp;
	std::cout << "CUDA backend is not compiled into this executable. Falling back to the host implementation is recommended.\n";
	return EXIT_FAILURE;
#endif
}
