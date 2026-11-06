/*=========================================================================

  Program:   NutateSignal
  Module:    CudaBackend.h
  Language:  C++

=========================================================================*/
#ifndef CUDA_BACKEND_H
#define CUDA_BACKEND_H

class Execution;
class CmdInterp;

bool cudaBackendAvailable();
int runSimulationCuda(Execution & run, CmdInterp & cmdInterp);

#endif /* CUDA_BACKEND_H */
