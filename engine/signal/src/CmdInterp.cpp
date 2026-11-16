/*=========================================================================

  Program:   NutateSignal
  Module:    $RCSfile: CmdInterp.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 18:54:15 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include "CmdInterp.h"
#include "Nucleus.h"
#include "../../common/NumericArguments.h"

#include <cstring>
#include <fstream>
#include <iostream>
#include <map>

namespace
{
	enum StringValue
	{
		cmd_thread,
		cmd_b0,
		cmd_xMin,
		cmd_xMax,
		cmd_yMin,
		cmd_yMax,
		cmd_zMin,
		cmd_zMax,
		cmd_xCtr,
		cmd_yCtr,
		cmd_zCtr,
		cmd_xWid,
		cmd_yWid,
		cmd_zWid,
		cmd_tiss,
		cmd_geom,
		cmd_delB0,
		cmd_b1Plus,
		cmd_b1Mins,
		cmd_delGx,
		cmd_delGy,
		cmd_delGz,
		cmd_kSpace,
		cmd_kMap,
		cmd_seqn,
		cmd_numIso,
		cmd_nucleus,
	};

	const std::map<std::string, StringValue> & commandMap()
	{
		static const std::map<std::string, StringValue> commands = {
			{"Thread", cmd_thread},
			{"B0", cmd_b0},
			{"xMin", cmd_xMin},
			{"xMax", cmd_xMax},
			{"yMin", cmd_yMin},
			{"yMax", cmd_yMax},
			{"zMin", cmd_zMin},
			{"zMax", cmd_zMax},
			{"xCtr", cmd_xCtr},
			{"yCtr", cmd_yCtr},
			{"zCtr", cmd_zCtr},
			{"xWid", cmd_xWid},
			{"yWid", cmd_yWid},
			{"zWid", cmd_zWid},
			{"TissueTypeFile", cmd_tiss},
			{"GeometryFile", cmd_geom},
			{"DelB0File", cmd_delB0},
			{"B1PlusFile", cmd_b1Plus},
			{"B1MinsFile", cmd_b1Mins},
			{"DelGxFile", cmd_delGx},
			{"DelGyFile", cmd_delGy},
			{"DelGzFile", cmd_delGz},
			{"KSpaceFile", cmd_kSpace},
			{"KMapFile", cmd_kMap},
			{"SequenceFile", cmd_seqn},
			{"NumIso", cmd_numIso},
			{"Nucleus", cmd_nucleus},
		};
		return commands;
	}

	bool splitArgument(const char * argument, std::string & option, std::string & parameter)
	{
		const std::string text(argument);
		const std::string::size_type separator = text.find('=');
		if (separator == std::string::npos)
		{
			return false;
		}

		option = text.substr(0, separator);
		parameter = text.substr(separator + 1);
		return true;
	}
}

// ------------------------------------------------------------------------------

CmdInterp::CmdInterp()
{
	// Default constructor: Set all default values.
	cmdValues.b1Mins.clear();
	cmdValues.b1Plus.clear();
	
	cmdValues.delGx.clear();
	cmdValues.delGy.clear();
	cmdValues.delGz.clear();
	
	cmdValues.kMap = "kMap.bin";
	cmdValues.kSpace = "kSpace.bin";
	cmdValues.delB0.clear();
	cmdValues.tiss.clear();
	cmdValues.geom.clear();
	cmdValues.seqn.clear();
	cmdValues.nucleus = nutate::nucleusConfig().defaultNucleus;

	cmdValues.thread = 1;
	cmdValues.b0 = 3;
	cmdValues.min = 0;	cmdValues.max = 0;
	cmdValues.wid= 0;
	cmdValues.ctr = 0;

	cmdValues.numIso = 1;

	// Set default flags (false = no cmd input).

	cmdFlags.kMap = false;
	cmdFlags.kSpace = false;
	cmdFlags.delB0 = false;
	cmdFlags.b1Plus = false;
	cmdFlags.b1Mins = false;

	cmdFlags.delGx = false;
	cmdFlags.delGy = false;
	cmdFlags.delGz = false;

	cmdFlags.tiss = false;
	cmdFlags.geom = false;
	cmdFlags.seqn = false;
	cmdFlags.nucleus = false;

	cmdFlags.thread = false;
	cmdFlags.b0 = false;
	cmdFlags.min = false;	cmdFlags.max = false;
	cmdFlags.wid = false;
	cmdFlags.ctr = false;

	cmdFlags.numIso = false;
}

CmdInterp::~CmdInterp()
{
	cmdValues.b1Plus.clear();
	cmdValues.b1Mins.clear();
}

// ------------------------------------------------------------------------------

bool CmdInterp::interpCmd(int argc, char *argv[])
{

	const std::map<std::string, StringValue> & commands = commandMap();

	for (int count = 1; count < argc; count++)
	{
		std::string option;
		std::string parameter;
		if (!splitArgument(argv[count], option, parameter))
		{
			std::cout << "\nError: command line option not recognized: \"" << argv[count] << "\"" << std::endl;
			std::cout << "Correct errors and re-run.\nPress enter to quit." << std::endl;
			std::cin.get();
			return false;
		}

		const std::map<std::string, StringValue>::const_iterator command = commands.find(option);
		if (command == commands.end())
		{
			std::cout << "\nError: command line option not recognized: \"" << argv[count] << "\"" << std::endl;
			std::cout << "Correct errors and re-run.\nPress enter to quit." << std::endl;
			std::cin.get();
			return false;
		}

		switch (command->second)
		{
		// find the matching value and assign command line parameters where appropriate
		case cmd_thread:
			if (!nutate::positiveCountArgument(parameter, option, cmdValues.thread)) return false;
			cmdFlags.thread = true;
			break;

		case cmd_b0:
			if (!nutate::finiteFloatArgument(parameter, option, cmdValues.b0)) return false;
			cmdFlags.b0 = true;
			break;

		case cmd_xMin:
			if (!nutate::indexArgument(parameter, option, cmdValues.min.x)) return false;
			cmdFlags.min.x = true;
			break;

		case cmd_xMax:
			if (!nutate::indexArgument(parameter, option, cmdValues.max.x)) return false;
			cmdFlags.max.x = true;
			break;

		case cmd_yMin:
			if (!nutate::indexArgument(parameter, option, cmdValues.min.y)) return false;
			cmdFlags.min.y = true;
			break;

		case cmd_yMax:
			if (!nutate::indexArgument(parameter, option, cmdValues.max.y)) return false;
			cmdFlags.max.y = true;
			break;

		case cmd_zMin:
			if (!nutate::indexArgument(parameter, option, cmdValues.min.z)) return false;
			cmdFlags.min.z = true;
			break;

		case cmd_zMax:
			if (!nutate::indexArgument(parameter, option, cmdValues.max.z)) return false;
			cmdFlags.max.z = true;
			break;

		case cmd_xWid:
			if (!nutate::positiveWidthArgument(parameter, option, cmdValues.wid.x)) return false;
			cmdFlags.wid.x = true;
			break;

		case cmd_yWid:
			if (!nutate::positiveWidthArgument(parameter, option, cmdValues.wid.y)) return false;
			cmdFlags.wid.y = true;
			break;

		case cmd_zWid:
			if (!nutate::positiveWidthArgument(parameter, option, cmdValues.wid.z)) return false;
			cmdFlags.wid.z = true;
			break;

		case cmd_xCtr:
			if (!nutate::finiteFloatArgument(parameter, option, cmdValues.ctr.x)) return false;
			cmdFlags.ctr.x = true;
			break;

		case cmd_yCtr:
			if (!nutate::finiteFloatArgument(parameter, option, cmdValues.ctr.y)) return false;
			cmdFlags.ctr.y = true;
			break;

		case cmd_zCtr:
			if (!nutate::finiteFloatArgument(parameter, option, cmdValues.ctr.z)) return false;
			cmdFlags.ctr.z = true;
			break;

		case cmd_tiss:
			cmdValues.tiss = parameter;
			cmdFlags.tiss = true;
			break;

		case cmd_geom:
			cmdValues.geom = parameter;
			cmdFlags.geom = true;
			break;

		case cmd_seqn:
			cmdValues.seqn = parameter;
			cmdFlags.seqn = true;
			break;

		case cmd_delB0:
			cmdValues.delB0 = parameter;
			cmdFlags.delB0 = true;
			break;

		case cmd_b1Plus:
			cmdValues.b1Plus.push_back(parameter);
			cmdFlags.b1Plus = true;
			break;

		case cmd_b1Mins:
			cmdValues.b1Mins.push_back(parameter);
			cmdFlags.b1Mins = true;
			break;

		case cmd_delGx:
			cmdValues.delGx = parameter;
			cmdFlags.delGx = true;
			break;

		case cmd_delGy:
			cmdValues.delGy = parameter;
			cmdFlags.delGy = true;
			break;

		case cmd_delGz:
			cmdValues.delGz = parameter;
			cmdFlags.delGz = true;
			break;

		case cmd_kSpace:
			cmdValues.kSpace = parameter;
			cmdFlags.kSpace = true;
			break;

		case cmd_kMap:
			cmdValues.kMap = parameter;
			cmdFlags.kMap = true;
			break;

		case cmd_numIso: // Number of Isochromats in each direction.
			if (!nutate::positiveCountArgument(parameter, option, cmdValues.numIso)) return false;
			cmdFlags.numIso = true;
			break;

		case cmd_nucleus:
		{
			NucleusProperties properties;
			if (!getNucleusProperties(parameter, properties))
			{
				std::cout << "\nError: unsupported Nucleus value \"" << parameter << "\".\n";
				std::cout << "Supported IDs are " << nutate::supportedNucleusNames() << ".\n";
				std::cout << "Press enter to quit.\n";
				std::cin.get();
				return false;
			}
			cmdValues.nucleus = properties.name;
			cmdFlags.nucleus = true;
			break;
		}

		default:
			std::cout << "\nFATAL ERROR: Map value found that does not exist in switch statement.\n";
			std::cout << "Debug file CmdInterp.cpp, function CmdInterp(int arc, char *argv[]).\n";
			std::cout << "Problem argv input: " << argv[count] << "\nPress enter to quit.\n";
			std::cin.get();
			return false;
		} // switch (command->second)
	}

	return checkFileNames();
} /* bool CmdInterp(int argc, char *argv[]) */

// ------------------------------------------------------------------------------

bool CmdInterp::checkFileNames()
{
	std::fstream fHandle;
	std::string str;

	// Retain the legacy explicit NULL sentinel check.
	if ( !strcmp(cmdValues.tiss.c_str(), "NULL") || !strcmp(cmdValues.geom.c_str(), "NULL") || !strcmp(cmdValues.seqn.c_str(), "NULL") )
	{
		std::cout << "Error: Tissue type file, geometry file, and sequence file names must ALL be supplied\n";
		std::cout << "Press enter to quit.";
		std::cin.get();
		return false;
	}

	// ****************************************************************
	// make sure geometry file exist
	modelInputs.prepare(cmdValues.geom);
	modelInputs.prepare(cmdValues.b1Plus);
	modelInputs.prepare(cmdValues.b1Mins);
	str = cmdValues.geom;
	fHandle.open(str.c_str(), std::ios::in | std::ios::binary);
	if (fHandle.fail()) 
	{
		fHandle.close();
		std::cout << "\nError opening geometry file!\n";
		std::cout << "Verify file: " << str << " exists\n";
		std::cout << "Press enter to quit.";
		std::cin.get();
		return false;
	}
	fHandle.close();

	// ****************************************************************
	// make sure tissue file exist
	str = cmdValues.tiss;
	fHandle.open(str.c_str(), std::ios::in | std::ios::binary);
	if (fHandle.fail()) 
	{
		fHandle.close();
		std::cout << "\nError opening tissue file!\n";
		std::cout << "Verify file: " << str << " exists\n";
		std::cout << "Press enter to quit.";
		std::cin.get();
		return false;
	}
	fHandle.close();

	// ****************************************************************
	// make sure sequence file exist
	str = cmdValues.seqn;
	fHandle.open(str.c_str(), std::ios::in | std::ios::binary);
	if (fHandle.fail()) 
	{
		fHandle.close();
		std::cout << "\nError opening sequence file!\n";
		std::cout << "Verify file: " << str << " exists\n";
		std::cout << "Press enter to quit.";
		std::cin.get();
		return false;
	}
	fHandle.close();

	return true;
}

// ------------------------------------------------------------------------------
