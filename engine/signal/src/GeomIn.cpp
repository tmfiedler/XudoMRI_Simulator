/*=========================================================================

  Program:   NutateSignal
  Module:    $RCSfile: GeomIn.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 20:53:31 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include "GeomIn.h"
#include<cassert>
#include<cmath>
#include<fstream>
#include<iostream>
#include<limits>

/* ********************

1) A geometry file is written as:

Total # Voxels
xMin, xMax
yMin, yMax
zMin, zMax
ctrX, ctrY, ctrZ
widX, widY, widZ
----------
x y z id
...

2) CmdFlags is written as:

xMin
xMax
yMin
yMax
zMin
zMax
ctrX
ctrY
ctrZ
widX
widY
widZ

It is processed first from CmdInterp, and if it is false, 
it reads in default value from file.

3) GeomHeader is written as:

xMin
xMax
yMin
yMax
zMin
zMax
ctrX
ctrY
ctrZ
widX
widY
widZ

******************** */

// ------------------------------------------------------------------------------

// NOTE -- This method should have the 'const' qualifier, but it can't because 
// "cmdInterp.getCmdValues().geom" accesses a public data value instead of 
// using a method to return the value.
GeomIn::GeomIn(CmdInterp & cmdInterp)
{
	fName = cmdInterp.getCmdValues().geom;
	geomFlag = readGeomHeader(cmdInterp) && readGeomData();
	axisShift();
}

GeomIn::~GeomIn()
{
	geomHeader.geomList.clear();
	geomData.clear();
}

// ------------------------------------------------------------------------------

bool GeomIn::readGeomHeader(CmdInterp & cmdInterp)
{
	std::fstream fHandle;
	float buff;
	
	fHandle.open(fName.c_str(), std::ios::in | std::ios::binary);

	if (fHandle.fail())
	{
		std::cout << "\n\"" << fName << "\" failed to open!\n";
		printf("Execution terminated, press enter to exit.\n");
		std::cin.get();
		return false;
	}
	
	// Validate raw metadata before any float-to-integer cast or unit conversion.
	float header[13];
	fHandle.read(reinterpret_cast<char*>(header), sizeof(header));
	if (!fHandle)
	{
		std::cerr << "Fatal Error: Incomplete geometry header in \"" << fName << "\".\n";
		return false;
	}
	for (float value : header)
	{
		if (!std::isfinite(value))
		{
			std::cerr << "Fatal Error: Nonfinite geometry header in \"" << fName << "\".\n";
			return false;
		}
	}
	if (header[0] < 0)
	{
		std::cerr << "Fatal Error: Invalid geometry count in \"" << fName << "\".\n";
		return false;
	}
	fHandle.seekg(0, std::ios::beg);

	// GeomHeader_________________________________________________________
	
	// totNumVox_______________________________________________
	fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
	// The payload supplies the actual count; never narrow a rounded float32 header.
	geomHeader.totNumVox = 0;

	// Below, the procedure is to check for command line input of the value first. If command line input
	// was present, that value will be used to define the volume of interest (voxels to be input). We
	// assume that the command line values will be less than the file max/ greater than the file min. If
	// no information was specified in the command line, it is assumed that there will be no constraint.
	// In this case, we use the min and/or max value found in the header which indicates the highest or
	// lowest value found anywhere in the file.
	// xMin_______________________________________________________
	if (cmdInterp.getCmdFlags().min.x == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.min.x = (float) buff;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.min.x = cmdInterp.getCmdValues().min.x;
	}

	// xMax_______________________________________________________
	if (cmdInterp.getCmdFlags().max.x == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.max.x = (float) buff;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.max.x =  cmdInterp.getCmdValues().max.x;
	}

	// yMin_______________________________________________________
	if (cmdInterp.getCmdFlags().min.y == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.min.y = (float) buff;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.min.y =  cmdInterp.getCmdValues().min.y;
	}

	// yMax_______________________________________________________
	if (cmdInterp.getCmdFlags().max.y == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.max.y = (float) buff;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.max.y =  cmdInterp.getCmdValues().max.y;
	}

	// zMin_______________________________________________________
	if (cmdInterp.getCmdFlags().min.z == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.min.z = (float) buff;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.min.z =  cmdInterp.getCmdValues().min.z;
	}

	// zMax_______________________________________________________
	if (cmdInterp.getCmdFlags().max.z == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.max.z = (float) buff;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.max.z =  cmdInterp.getCmdValues().max.z;
	}

	// ctrX_______________________________________________________
	if (cmdInterp.getCmdFlags().ctr.x == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.ctr.x = (float) buff;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.ctr.x =  cmdInterp.getCmdValues().ctr.x;
	}

	// ctrY_______________________________________________________
	if (cmdInterp.getCmdFlags().ctr.y == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.ctr.y = (float) buff;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.ctr.y = cmdInterp.getCmdValues().ctr.y;
	}

	// ctrZ_______________________________________________________
	if (cmdInterp.getCmdFlags().ctr.z == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.ctr.z = (float) buff;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.ctr.z = cmdInterp.getCmdValues().ctr.z;
	}

	// The values in the file for voxel width are written in millimeters, but the units must
	// be changed by the engine to be in meters. This is the reason for division by 1000
	// in each of the operations below.
	// In a similar fashion to the min and max values above, command line input is taken if
	// it is present. Otherwise, the engine will default to the info in the file header.

	// widX_______________________________________________________
	if (cmdInterp.getCmdFlags().wid.x == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.wid.x = (float) buff/1000;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.wid.x = cmdInterp.getCmdValues().wid.x/1000;
	}

	// widY_______________________________________________________
	if (cmdInterp.getCmdFlags().wid.y == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.wid.y = (float) buff/1000;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.wid.y = cmdInterp.getCmdValues().wid.y/1000;
	}

	// widZ_______________________________________________________
	if (cmdInterp.getCmdFlags().wid.z == false)
	{
		fHandle.read(reinterpret_cast<char*>(&buff), sizeof(buff));
		geomHeader.wid.z = (float) buff/1000;
	}
	else
	{
		fHandle.seekg (4*1, std::ios::cur);
		geomHeader.wid.z = cmdInterp.getCmdValues().wid.z/1000;
	}
	
	// Check Point________________________________________________
	if (!(geomHeader.min <= geomHeader.max && (0 < geomHeader.wid.x) && (0 < geomHeader.wid.y) && (0 < geomHeader.wid.z)))
	{
		std::cout << "Error: Region of interest definition shows ROI_min > ROI_max.\nCheck command line and/or geometry file header.\n";
		std::cout << "Also check width settings. One or more of the voxel width settings may be less than or equal to zero.\n";
		std::cout << "Press enter to continue.\n";
		std::cin.get();
		return false;
	}
	
	fHandle.close();
	return true;
}

// ------------------------------------------------------------------------------

bool GeomIn::readGeomData()
{
	printf("Reading Geometry data... ");

	std::fstream fHandle;

	fHandle.open(fName.c_str(), std::ios::in | std::ios::binary);
	
	if (fHandle.fail())
	{
		std::cout << "\n\"" << fName << "\" failed to open!\n";
		printf("Execution terminated, press enter to exit.\n");
		std::cin.get();
		return false;
	}

	const std::streamoff headerBytes = static_cast<std::streamoff>(13 * sizeof(float));
	const std::streamoff voxelBytes = static_cast<std::streamoff>(4 * sizeof(float));
	fHandle.seekg(0, std::ios::end);
	const std::streamoff fileBytes = fHandle.tellg();
	if (fileBytes < headerBytes)
	{
		std::cout << "Error: Geometry file is smaller than its 52-byte header.\n";
		return false;
	}

	const std::streamoff payloadBytes = fileBytes - headerBytes;
	if ((payloadBytes % voxelBytes) != 0)
	{
		std::cout << "Error: Geometry payload size is not a whole number of 16-byte voxel records.\n";
		return false;
	}

	const std::streamoff payloadVoxelCount = payloadBytes / voxelBytes;
	if (payloadVoxelCount > static_cast<std::streamoff>(std::numeric_limits<unsigned int>::max()))
	{
		std::cout << "Error: Geometry contains more voxels than this engine can index.\n";
		return false;
	}

	float legacyHeaderCount;
	fHandle.seekg(0, std::ios::beg);
	fHandle.read(reinterpret_cast<char*>(&legacyHeaderCount), sizeof(legacyHeaderCount));
	if (!fHandle) return false;
	geomHeader.totNumVox = static_cast<unsigned int>(payloadVoxelCount);
	if (static_cast<double>(legacyHeaderCount) != static_cast<double>(geomHeader.totNumVox))
	{
		std::cout << "Warning: Legacy float32 geometry header reports " << legacyHeaderCount
			<< " voxels, but the file payload contains " << geomHeader.totNumVox
			<< ". Using the payload-derived count.\n";
	}

	// Skip GeomHeader and read every complete payload record.
	fHandle.seekg(headerBytes, std::ios::beg);

	// Geometry Data______________________________________________
	Voxel tempVoxel;

	unsigned int j = 0;
	unsigned int k = 0;

	while(j < geomHeader.totNumVox)
	{
		float record[4];
		fHandle.read(reinterpret_cast<char*>(record), sizeof(record));
		if (!fHandle)
		{
			std::cout << "\nError: Geometry payload ended before the derived voxel count was read.\n";
			return false;
		}
		for (float value : record)
		{
			if (!std::isfinite(value))
			{
				std::cerr << "Fatal Error: Nonfinite geometry value in \"" << fName
					<< "\", voxel record " << (j + 1) << ".\n";
				return false;
			}
		}
		if (record[3] != std::floor(record[3]) ||
			static_cast<double>(record[3]) < std::numeric_limits<int>::min() ||
			static_cast<double>(record[3]) > std::numeric_limits<int>::max())
		{
			std::cerr << "Fatal Error: Invalid tissue ID in \"" << fName
				<< "\", voxel record " << (j + 1) << ".\n";
			return false;
		}
		tempVoxel.geomInfo.pos.x = record[0];
		tempVoxel.geomInfo.pos.y = record[1];
		tempVoxel.geomInfo.pos.z = record[2];
		tempVoxel.geomInfo.id = static_cast<int>(record[3]);

		if (geomHeader.min <= tempVoxel.geomInfo.pos && tempVoxel.geomInfo.pos <= geomHeader.max) // if the voxel falls within the volume of interest
		{
			geomData.push_back(tempVoxel);
			k++;
			geomHeader.geomList.push_back(j);
		}
		j++;
	}

	printf("Finished!\n");

	std::cout << "Number of voxels in VOI [" << geomHeader.min.x << "," << geomHeader.max.x << "], [" << geomHeader.min.y 
		<< "," << geomHeader.max.y << "], [" << geomHeader.min.z << "," << geomHeader.max.z << "]: " << k <<std::endl;
	std::cout << "Number of all input voxels: " << geomHeader.totNumVox <<std::endl;

	fHandle.close();
	return true;
}

// ------------------------------------------------------------------------------

void GeomIn::axisShift()
{
	for (unsigned int i=0; i<geomData.size(); i++)
	{
		geomData[i].geomInfo.pos -= geomHeader.ctr;
	}
}

// ------------------------------------------------------------------------------
