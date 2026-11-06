/*=========================================================================

  Program:   NutateSignal
  Module:    $RCSfile: B1MinsIn.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 20:53:31 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include"B1MinsIn.h"
#include "InputSentinels.h"
#include<cassert>
#include<fstream>
#include<iostream>

// ------------------------------------------------------------------------------

// NOTE -- This method should have the 'const' qualifier, but it can't because 
// "cmdInterp.getCmdValues().b1Mins" accesses a public data value instead of 
// using a method to return the value.
B1MinsIn::B1MinsIn(CmdInterp & cmdInterp, std::vector<unsigned int> & geomList,
	unsigned int geometryVoxelCount)  
{
	fName.clear();
	b1MinsHeader.totNumVox.clear();
	b1MinsData.clear();
	expectedVoxelCount = geometryVoxelCount;

	if (cmdInterp.getCmdFlags().b1Mins == true)
	{
		fName = cmdInterp.getCmdValues().b1Mins;
		b1MinsFlag = readB1MinsHeader() && readB1MinsData(geomList);
	}
	else
	{
		fName.assign(1, SignalInput::MissingFieldFile);
		b1MinsFlag = true;
	}
}

B1MinsIn::~B1MinsIn()
{
	b1MinsHeader.totNumVox.clear();
	for (unsigned int i = 0; i < b1MinsData.size(); i++)
	{
		b1MinsData[i].clear();
	}
	b1MinsData.clear();
	fName.clear();
}

// ------------------------------------------------------------------------------

bool B1MinsIn::readB1MinsHeader()
{
	printf("Reading B1- data...");

	std::fstream fHandle;
	float buff;
	const std::streamoff headerBytes = static_cast<std::streamoff>(sizeof(float));
	const std::streamoff recordBytes = static_cast<std::streamoff>(2 * sizeof(float));
	
	for (unsigned int i=0; i<fName.size(); i++) // for each file name
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
			std::cout << "\nFatal Error: B1- file \"" << fName[i]
				<< "\" does not contain a 4-byte header followed by complete 8-byte voxel records.\n";
			return false;
		}
		const std::streamoff payloadVoxelCount = (fileBytes - headerBytes) / recordBytes;
		if (payloadVoxelCount != static_cast<std::streamoff>(expectedVoxelCount))
		{
			std::cout << "\nFatal Error: B1- file \"" << fName[i] << "\" contains "
				<< payloadVoxelCount << " voxel records, but the geometry contains "
				<< expectedVoxelCount << ".\n";
			return false;
		}

		fHandle.seekg(0, std::ios::beg);
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		if (!fHandle)
		{
			std::cout << "\nFatal Error: Unable to read the B1- header from \"" << fName[i] << "\".\n";
			return false;
		}
		if (static_cast<double>(buff) != static_cast<double>(expectedVoxelCount))
		{
			std::cout << "\nWarning: B1- legacy float32 header reports " << buff
				<< " voxels, but the payload contains " << expectedVoxelCount
				<< ". Using the payload-derived count.\n";
		}
		b1MinsHeader.totNumVox.push_back(expectedVoxelCount);

		fHandle.close();
	}

	printf("Finished!\n");

	return true;
}

// ------------------------------------------------------------------------------

bool B1MinsIn::readB1MinsData(std::vector<unsigned int> & geomList)
{
	std::fstream fHandle;

	float record[2];
	std::vector<std::complex<float > > tempB1Mins;

	for (unsigned int i=0; i<fName.size(); i++) // for each file name
	{
		fHandle.open(fName[i].c_str(), std::ios::in | std::ios::binary);
	
		// The header was validated earlier, but reopening can still fail if the file changed.
		if (fHandle.fail())
		{
			std::cout << "\n\"" << fName[i] << "\" failed to open!\n";
			printf("Execution terminated, press enter to exit.\n");
			std::cin.get();
			return false;
		}

		tempB1Mins.clear();
		for (unsigned int j = 0; j < geomList.size(); j++)
		{
			const std::streamoff recordOffset = static_cast<std::streamoff>(sizeof(float)) +
				static_cast<std::streamoff>(geomList[j]) * static_cast<std::streamoff>(2 * sizeof(float));
			fHandle.seekg(recordOffset, std::ios::beg); // move 'get' pointer to the data that goes with each particular voxel
																// 4 is for float size, 2 because there are two data points for each B1-Minus
																// file entry, and add 1 to skip the header information of the B1-Minus file.

			// B1MinsData_________________________________________________
			fHandle.read(reinterpret_cast<char*>(record), sizeof(record));
			if (!fHandle)
			{
				std::cout << "\nFatal Error: Unable to read B1- voxel " << geomList[j]
					<< " from \"" << fName[i] << "\".\n";
				return false;
			}
			tempB1Mins.push_back(std::complex<float> (record[0], record[1]));
		}

		b1MinsData.push_back(tempB1Mins);
		fHandle.close();
	}

	return true;
}

// ------------------------------------------------------------------------------
