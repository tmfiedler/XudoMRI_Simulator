/*=========================================================================

  Program:   Nutate (This file is identical for SAR and Signal calcuation)
  Module:    $RCSfile: B1PlusIn.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 20:53:31 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include"B1PlusIn.h"
#include "InputSentinels.h"
#include<cassert>
#include<cmath>
#include<fstream>
#include<iostream>

// ------------------------------------------------------------------------------

// NOTE -- This method should have the 'const' qualifier, but it can't because 
// "cmdInterp.getCmdValues().b1Plus" accesses a public data value instead of 
// using a method to return the value.
B1PlusIn::B1PlusIn(CmdInterp & cmdInterp, std::vector<unsigned int> & geomList,
	unsigned int geometryVoxelCount)
{
	fName.clear();
	b1PlusHeader.totNumVox.clear();
	b1PlusData.clear();
	expectedVoxelCount = geometryVoxelCount;

	if (cmdInterp.getCmdFlags().b1Plus == true) // if B1 Filenames were provided
	{
		fName = cmdInterp.getCmdValues().b1Plus;
		b1PlusFlag = readB1PlusHeader() && readB1PlusData(geomList);
	}
	else
	{
		fName.assign(1, SignalInput::MissingFieldFile);
		b1PlusFlag = true;
	}
}

B1PlusIn::~B1PlusIn()
{
	b1PlusHeader.totNumVox.clear();
	for (unsigned int i = 0; i < b1PlusData.size(); i++)
	{
		b1PlusData[i].clear();
	}
	b1PlusData.clear();
	fName.clear();
}

// ------------------------------------------------------------------------------

bool B1PlusIn::readB1PlusHeader()
{
	std::fstream fHandle;
	float buff;
	const std::streamoff headerBytes = static_cast<std::streamoff>(sizeof(float));
	const std::streamoff recordBytes = static_cast<std::streamoff>(2 * sizeof(float));
	
	for (unsigned int i=0; i<fName.size(); i++)
	{
		fHandle.open(fName[i].c_str(), std::ios::in | std::ios::binary);
	
		if (fHandle.fail())
		{
			std::cout << "\n\"" << fName[i] << "\" failed to open!\n";
			printf("Execution terminated, press enter to exit.\n");
			std::cin.get();
			return false;
		}

		fHandle.seekg(0, std::ios::end);
		const std::streamoff fileBytes = fHandle.tellg();
		if (fileBytes < headerBytes || ((fileBytes - headerBytes) % recordBytes) != 0)
		{
			std::cout << "\nFatal Error: B1+ file \"" << fName[i]
				<< "\" does not contain a 4-byte header followed by complete 8-byte voxel records.\n";
			return false;
		}
		const std::streamoff payloadVoxelCount = (fileBytes - headerBytes) / recordBytes;
		if (payloadVoxelCount != static_cast<std::streamoff>(expectedVoxelCount))
		{
			std::cout << "\nFatal Error: B1+ file \"" << fName[i] << "\" contains "
				<< payloadVoxelCount << " voxel records, but the geometry contains "
				<< expectedVoxelCount << ".\n";
			return false;
		}

		fHandle.seekg(0, std::ios::beg);
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		if (!fHandle)
		{
			std::cout << "\nFatal Error: Unable to read the B1+ header from \"" << fName[i] << "\".\n";
			return false;
		}
		if (static_cast<double>(buff) != static_cast<double>(expectedVoxelCount))
		{
			std::cout << "\nWarning: B1+ legacy float32 header reports " << buff
				<< " voxels, but the payload contains " << expectedVoxelCount
				<< ". Using the payload-derived count.\n";
		}
		b1PlusHeader.totNumVox.push_back(expectedVoxelCount);

		fHandle.close();
	}
	
	return true;
}

// ------------------------------------------------------------------------------

bool B1PlusIn::readB1PlusData(std::vector<unsigned int> & geomList)
{
	printf("Reading B1+ data...");

	std::fstream fHandle;

	float record[2];
	std::vector<std::complex<float > > tempB1Plus;

	for (unsigned int i=0; i<fName.size(); i++) // for each B1+ file
	{
		fHandle.open(fName[i].c_str(), std::ios::in | std::ios::binary);
		
		if (fHandle.fail())
		{
			std::cout << "\n\"" << fName[i] << "\" failed to open!\n";
			printf("Execution terminated, press enter to exit.\n");
			std::cin.get();
			return false;
		}

		tempB1Plus.clear();
		for (unsigned int j = 0; j < geomList.size(); j++)
		{
			const std::streamoff recordOffset = static_cast<std::streamoff>(sizeof(float)) +
				static_cast<std::streamoff>(geomList[j]) * static_cast<std::streamoff>(2 * sizeof(float));
			fHandle.seekg(recordOffset, std::ios::beg); // seek to the appropriate location in the B1+ file
												// 4 is the size of a float, 2 because there are two data points for
												// each voxel, and + 1 because we must skip the header info

			// B1PlusData_________________________________________________
			fHandle.read(reinterpret_cast<char*>(record), sizeof(record));
			if (!fHandle)
			{
				std::cout << "\nFatal Error: Unable to read B1+ voxel " << geomList[j]
					<< " from \"" << fName[i] << "\".\n";
				return false;
			}
			if (!std::isfinite(record[0]) || !std::isfinite(record[1]))
			{
				std::cerr << "Fatal Error: Nonfinite B1+ value in \"" << fName[i]
					<< "\", voxel record " << (geomList[j] + 1) << ".\n";
				return false;
			}
			tempB1Plus.push_back(std::complex<float> (record[0], record[1]));
		}

		b1PlusData.push_back(tempB1Plus);
		fHandle.close();
	}

	printf("Finished!\n");

	return true;
}

// ------------------------------------------------------------------------------
