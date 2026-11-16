/*=========================================================================

  Program:   NutateNoise
  Module:    $RCSfile: CmdInterp.h,v $
  Language:  C++
  Date:      $Date: 2009/12/09 20:53:31 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#ifndef CMDINTERP_H
#define CMDINTERP_H

#include <cstdint>
#include <string>
#include <vector>

#include "Vect3D.h"
	
// Parses the noise engine's exact-case Key=value command-line interface.
// CmdValues stores effective values (including defaults), while CmdFlags records
// which values were supplied explicitly.
#include "ModelInputs.h"

class CmdInterp
{
private:
	// class CmdValues holds file names for kNoise, tissue, geometry, and sequence files
	// as well as all E1 Minus file names as given in the command line input . It also
	// holds the min, max, and width values passed in via the command line.
	class CmdValues
	{
	public:
		std::string kNoise;

		std::vector<std::string> e1Mins;

		Vect3D<float> min, max;
		Vect3D<float> wid;

		std::string tiss;
		std::string geom;
		std::string seqn;
		std::string nucleus;

		unsigned short int NEX; // Independent noise-set count; defaults to 1.
		std::uint64_t noiseSeed;
	} cmdValues;

	// class CmdFlags is full of boolean values that are initialized to false. These
	// flags become true only when their corresponding value has been read from the
	// command line.
	class CmdFlags
	{
	public:
		bool kNoise;

		bool e1Mins;

		Vect3D<bool> min, max;
		Vect3D<bool> wid;

		bool tiss;
		bool geom;
		bool seqn;
		bool nucleus;

		bool NEX;
		bool noiseSeed;
	} cmdFlags;

	// Verify required input filenames before any file loader is constructed.
	nutate::ModelInputs modelInputs;
	bool checkFileNames();	

public:
	CmdInterp();

	bool interpCmd(int argc, char *argv[]);

	const CmdValues & getCmdValues() const { return cmdValues; }
	const CmdFlags & getCmdFlags() const { return cmdFlags; }
};

#endif /* CMDINTERP_H */
