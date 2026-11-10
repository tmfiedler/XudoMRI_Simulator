/*=========================================================================

  Program:   NutateNoise
  Module:    $RCSfile: E1MinsIn.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 20:53:31 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include"E1MinsIn.h"
#include<cassert>
#include<cmath>
#include<fstream>
#include<iostream>
#include<complex>

// ------------------------------------------------------------------------------

// NOTE -- This method should have the 'const' qualifier, but it can't because 
// "cmdInterp.getCmdValues().e1Mins" accesses a public data value instead of 
// using a method to return the value.
E1MinsIn::E1MinsIn(CmdInterp & cmdInterp, std::vector<unsigned int> & geomList,
	unsigned int geometryVoxelCount)
{
	fName.clear();
	e1MinsHeader.totNumVox.clear();
	e1MinsData.clear();
	expectedVoxelCount = geometryVoxelCount;

	if (cmdInterp.getCmdFlags().e1Mins == true)
	{
		fName = cmdInterp.getCmdValues().e1Mins;
		e1MinsFlag = readE1MinsHeader() && readE1MinsData(geomList);
	}
	else
	{
		fName.assign(1, "NULL");
		e1MinsFlag = true;
	}
}

// ------------------------------------------------------------------------------

E1MinsIn::~E1MinsIn()
{
	e1MinsHeader.totNumVox.clear();
	for (unsigned int i = 0; i < e1MinsData.size(); i++)
	{
		e1MinsData[i].clear();
	}
	e1MinsData.clear();
	fName.clear();
}

// ------------------------------------------------------------------------------

bool E1MinsIn::readE1MinsHeader()
{
	std::fstream fHandle;
	float buff;
	const std::streamoff headerBytes = static_cast<std::streamoff>(sizeof(float));
	const std::streamoff recordBytes = static_cast<std::streamoff>(6 * sizeof(float));
	
	// loop through each file to open the file and read its header information
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
			std::cout << "\nFatal Error: E1- file \"" << fName[i]
				<< "\" does not contain a 4-byte header followed by complete 24-byte voxel records.\n";
			return false;
		}
		const std::streamoff payloadVoxelCount = (fileBytes - headerBytes) / recordBytes;
		if (payloadVoxelCount != static_cast<std::streamoff>(expectedVoxelCount))
		{
			std::cout << "\nFatal Error: E1- file \"" << fName[i] << "\" contains "
				<< payloadVoxelCount << " voxel records, but the geometry contains "
				<< expectedVoxelCount << ".\n";
			return false;
		}

		fHandle.seekg(0, std::ios::beg);
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		if (!fHandle)
		{
			std::cout << "\nFatal Error: Unable to read the E1- header from \"" << fName[i] << "\".\n";
			return false;
		}
		if (static_cast<double>(buff) != static_cast<double>(expectedVoxelCount))
		{
			std::cout << "\nWarning: E1- legacy float32 header reports " << buff
				<< " voxels, but the payload contains " << expectedVoxelCount
				<< ". Using the payload-derived count.\n";
		}
		e1MinsHeader.totNumVox.push_back(expectedVoxelCount);

		fHandle.close();
	}

	return true;
}

// ------------------------------------------------------------------------------
bool E1MinsIn::readE1MinsData(std::vector<unsigned int> & geomList)
{
	printf("Reading E1- data...");

	std::fstream fHandle;

	float record[6];
	std::vector<Vect3D< std::complex<float> > > tempE1MinsData;

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

		tempE1MinsData.clear();
		Vect3D<std::complex<float> > Vect3DBuff;
		for (unsigned int j = 0; j < geomList.size(); j++)
		{
			// move the get pointer to the appropriate location in the E1 Minus file, which corresponds to a
			// particular voxel in the geometry file. Multiply by 4 because that is the size in bytes of a
			// float, and by 6 because there are six data points for each line (voxel) in the E1 Minus file.
			// geomList[n] holds the voxel's original position in the geometry file so that we can find the
			// associated info in other files.
			const std::streamoff recordOffset = static_cast<std::streamoff>(sizeof(float)) +
				static_cast<std::streamoff>(geomList[j]) * static_cast<std::streamoff>(6 * sizeof(float));
			fHandle.seekg(recordOffset, std::ios::beg);

			// E1MinsDataData_________________________________________________
			fHandle.read(reinterpret_cast<char*>(record), sizeof(record));
			if (!fHandle)
			{
				std::cout << "\nFatal Error: Unable to read E1- voxel " << geomList[j]
					<< " from \"" << fName[i] << "\".\n";
				return false;
			}
			for (float component : record)
			{
				if (!std::isfinite(component))
				{
					std::cerr << "Fatal Error: Nonfinite E1- value in \"" << fName[i]
						<< "\", voxel record " << (geomList[j] + 1) << ".\n";
					return false;
				}
			}
			Vect3DBuff.x = std::complex<float>(record[0], record[1]);
			Vect3DBuff.y = std::complex<float>(record[2], record[3]);
			Vect3DBuff.z = std::complex<float>(record[4], record[5]);

			tempE1MinsData.push_back(Vect3DBuff);
		}

		e1MinsData.push_back(tempE1MinsData);
		fHandle.close();
	} /* for (unsigned int i=0; i<fName.size(); i++) */

	printf("Finished!\n");

	return true;
}

// ------------------------------------------------------------------------------
