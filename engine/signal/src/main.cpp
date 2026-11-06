/*=========================================================================

  Program:   NutateSignal
  Module:    $RCSfile: main.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 21:18:18 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/

#include "Execution.h"
#include "CmdInterp.h"
#include "SimulationRunner.h"

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <exception>

#ifndef NUTATE_VERSION
#define NUTATE_VERSION "unknown"
#endif

int main(int argc, char *argv[])
{
#if defined(NUTATE_SIGNAL_GPU_BINARY)
	const char* backend = "GPU";
#else
	const char* backend = "CPU";
#endif
	std::cout << "NutateSignal " << NUTATE_VERSION << " (" << backend << ")" << std::endl;
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
		// Sufficient error message given by error causing failure
		return (EXIT_FAILURE);
	}

	Execution run(cmdInterp);

	if (!(run.initFlag))
	{
		// Sufficient error message given by error causing failure
		return (EXIT_FAILURE);
	}

	return runSimulation(run, cmdInterp);
	}
	catch (const std::exception & error)
	{
		std::cerr << "Fatal Error: " << error.what() << std::endl;
		return EXIT_FAILURE;
	}
} /* int main(int argc, char *argv[]) */
