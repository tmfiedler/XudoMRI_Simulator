/*=========================================================================

  Program:   NutateNoise
  Module:    $RCSfile: CmdInterp.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 18:54:15 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include "CmdInterp.h"
#include "Nucleus.h"

#include <cerrno>
#include <cstdlib>
#include <exception>
#include <fstream>
#include <iostream>
#include <limits>
#include <map>

namespace
{
	enum StringValue
	{
		cmd_xMin,
		cmd_xMax,
		cmd_yMin,
		cmd_yMax,
		cmd_zMin,
		cmd_zMax,
		cmd_xWid,
		cmd_yWid,
		cmd_zWid,
		cmd_tiss,
		cmd_geom,
		cmd_e1Mins,
		cmd_kNoise,
		cmd_seqn,
		cmd_NEX,
		cmd_nucleus,
		cmd_noiseSeed,
	};

	const std::map<std::string, StringValue> & commandMap()
	{
		static const std::map<std::string, StringValue> commands = {
			{"xMin", cmd_xMin},
			{"xMax", cmd_xMax},
			{"yMin", cmd_yMin},
			{"yMax", cmd_yMax},
			{"zMin", cmd_zMin},
			{"zMax", cmd_zMax},
			{"xWid", cmd_xWid},
			{"yWid", cmd_yWid},
			{"zWid", cmd_zWid},
			{"TissueTypeFile", cmd_tiss},
			{"GeometryFile", cmd_geom},
			{"E1MinsFile", cmd_e1Mins},
			{"KNoiseFile", cmd_kNoise},
			{"SequenceFile", cmd_seqn},
			{"NEX", cmd_NEX},
			{"Nucleus", cmd_nucleus},
			{"NoiseSeed", cmd_noiseSeed},
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
	cmdValues.e1Mins.clear();
	cmdValues.kNoise = "kNoise.bin";

	cmdValues.tiss.clear();
	cmdValues.geom.clear();
	cmdValues.seqn.clear();
	cmdValues.nucleus = nutate::nucleusConfig().defaultNucleus;
	cmdValues.noiseSeed = 0;
	cmdValues.NEX = 1;

	cmdValues.min = 0;	cmdValues.max = 0;
	cmdValues.wid= 0;

	// Set all default flags (false = no cmd input).

	cmdFlags.kNoise = false;
	cmdFlags.e1Mins = false;
	cmdFlags.tiss = false;
	cmdFlags.geom = false;
	cmdFlags.seqn = false;
	cmdFlags.nucleus = false;
	cmdFlags.min = false;	cmdFlags.max = false;
	cmdFlags.wid = false;

	cmdFlags.NEX = false;
	cmdFlags.noiseSeed = false;
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
			std::cout << "Correct errors and restart simulation.\nPress enter to quit." << std::endl;
			std::cin.get();
			return false;
		}

		const std::map<std::string, StringValue>::const_iterator command = commands.find(option);
		if (command == commands.end())
		{
			std::cout << "\nError: command line option not recognized: \"" << argv[count] << "\"" << std::endl;
			std::cout << "Correct errors and restart simulation.\nPress enter to quit." << std::endl;
			std::cin.get();
			return false;
		}

		switch (command->second)
		{
		// find the matching value and assign command line parameters where appropriate
		case cmd_xMin:
			cmdValues.min.x = (float)strtol(parameter.c_str(), NULL, 0);
			cmdFlags.min.x = true;
			break;

		case cmd_xMax:
			cmdValues.max.x = (float)strtol(parameter.c_str(), NULL, 0);
			cmdFlags.max.x = true;
			break;

		case cmd_yMin:
			cmdValues.min.y = (float)strtol(parameter.c_str(), NULL, 0);
			cmdFlags.min.y = true;
			break;

		case cmd_yMax:
			cmdValues.max.y = (float)strtol(parameter.c_str(), NULL, 0);
			cmdFlags.max.y = true;
			break;

		case cmd_zMin:
			cmdValues.min.z = (float)strtol(parameter.c_str(), NULL, 0);
			cmdFlags.min.z = true;
			break;

		case cmd_zMax:
			cmdValues.max.z = (float)strtol(parameter.c_str(), NULL, 0);
			cmdFlags.max.z = true;
			break;

		case cmd_xWid:
			cmdValues.wid.x = (float)strtod(parameter.c_str(), NULL);
			cmdFlags.wid.x = true;
			break;

		case cmd_yWid:
			cmdValues.wid.y = (float)strtod(parameter.c_str(), NULL);
			cmdFlags.wid.y = true;
			break;

		case cmd_zWid:
			cmdValues.wid.z = (float)strtod(parameter.c_str(), NULL);
			cmdFlags.wid.z = true;
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

		case cmd_e1Mins:
			cmdValues.e1Mins.push_back(parameter);
			cmdFlags.e1Mins = true;
			break;

		case cmd_kNoise:
			cmdValues.kNoise = parameter;
			cmdFlags.kNoise = true;
			break;

		case cmd_NEX:
		{
			char* end = nullptr;
			errno = 0;
			const long nex = std::strtol(parameter.c_str(), &end, 0);
			if (errno == ERANGE || end == parameter.c_str() || *end != '\0' ||
				nex <= 0 || nex > std::numeric_limits<unsigned short int>::max())
			{
				std::cout << "\nError: NEX must be a whole integer from 1 to "
					<< std::numeric_limits<unsigned short int>::max() << ".\n";
				return false;
			}
			cmdValues.NEX = static_cast<unsigned short int>(nex);
			cmdFlags.NEX = true;
			break;
		}

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

		case cmd_noiseSeed:
		{
			std::size_t parsedCharacters = 0;
			try
			{
				if (parameter.empty() || parameter[0] == '-')
				{
					throw std::invalid_argument("negative or empty seed");
				}
				cmdValues.noiseSeed = std::stoull(parameter, &parsedCharacters, 10);
			}
			catch (const std::exception &)
			{
				std::cout << "\nError: NoiseSeed must be an unsigned 64-bit integer.\n";
				return false;
			}
			if (parsedCharacters != parameter.size())
			{
				std::cout << "\nError: NoiseSeed must contain digits only.\n";
				return false;
			}
			cmdFlags.noiseSeed = true;
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
} /* bool CmdInterp::interpCmd(int argc, char *argv[]) */

// ------------------------------------------------------------------------------

bool CmdInterp::checkFileNames()
{
	std::fstream fHandle;
	std::string str;

	// ****************************************************************
	// make sure geometry file exists
	str = cmdValues.geom;
	fHandle.open(str.c_str(), std::ios::in | std::ios::binary);
	if (fHandle.fail()) 
	{
		fHandle.close();
		std::cout << "\nError opening geometry file!\n";
		std::cout << "Verify file: " << str << " exists.\n";
		std::cout << "Press enter to quit.";
		std::cin.get();
		return false;
	}
	fHandle.close();

	// ****************************************************************
	// make sure tissue file exists
	str = cmdValues.tiss;
	fHandle.open(str.c_str(), std::ios::in | std::ios::binary);
	if (fHandle.fail()) 
	{
		fHandle.close();
		std::cout << "\nError opening tissue file!\n";
		std::cout << "Verify file: " << str << " exists.\n";
		std::cout << "Press enter to quit.";
		std::cin.get();
		return false;
	}
	fHandle.close();

	// ****************************************************************
	// make sure sequence file exists
	str = cmdValues.seqn;
	fHandle.open(str.c_str(), std::ios::in | std::ios::binary);
	if (fHandle.fail()) 
	{
		fHandle.close();
		std::cout << "\nError opening sequence file!\n";
		std::cout << "Verify file: " << str << " exists.\n";
		std::cout << "Press enter to quit.";
		std::cin.get();
		return false;
	}
	fHandle.close();

	return true;
}

// ------------------------------------------------------------------------------
