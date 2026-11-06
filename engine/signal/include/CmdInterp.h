/*=========================================================================

  Program:   NutateSignal
  Module:    $RCSfile: CmdInterp.h,v $
  Language:  C++
  Date:      $Date: 2009/12/09 20:53:31 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#ifndef CMDINTERP_H
#define CMDINTERP_H

#include <string>
#include <vector>

#include "Vect3D.h"
	
// Parses the signal engine's exact-case Key=value command-line interface.
// CmdValues stores effective values (including defaults), while CmdFlags records
// which values were supplied explicitly.
class CmdInterp
{
private:
	// class CmdValues holds all information passed in via the command line. This includes
	// file names, Volume Of Interest (VOI) limits, and other data from the command line.
	class CmdValues
	{
	public:
		std::string kMap;
		std::string kSpace;

		unsigned short int thread;
		float b0;
		std::string delB0;
		std::vector<std::string> b1Plus;
		std::vector<std::string> b1Mins;

		std::string delGx;
		std::string delGy;
		std::string delGz;

		Vect3D<float> min, max;
		Vect3D<float> ctr;
		Vect3D<float> wid;

		std::string tiss;
		std::string geom;
		std::string seqn;
		std::string nucleus;

		unsigned short int numIso;
	} cmdValues;

	// class CmdFlags is full of boolean values that are initialized to false. These
	// flags become true only when their corresponding value has been read from the
	// command line.
	class CmdFlags
	{
	public:
		bool kMap;
		bool kSpace;

		bool thread;
		bool b0;
		bool delB0;
		bool b1Plus;
		bool b1Mins;

		Vect3D<bool> min, max;
		Vect3D<bool> wid;
		Vect3D<bool> ctr;

		bool delGx;
		bool delGy;
		bool delGz;

		bool tiss;
		bool geom;
		bool seqn;
		bool nucleus;

		bool numIso;

	} cmdFlags;

	// Verify required input filenames before any file loader is constructed.
	bool checkFileNames();

public:
	CmdInterp();
	~CmdInterp();

	bool interpCmd(int argc, char *argv[]);

	const CmdValues & getCmdValues() const { return cmdValues; }
	const CmdFlags & getCmdFlags() const { return cmdFlags; }
};

#endif /* CMDINTERP_H */
