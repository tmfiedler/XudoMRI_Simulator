/*=========================================================================

  Program:   NutateNoise
  Module:    $RCSfile: Execution.h,v $
  Language:  C++
  Date:      $Date: 2009/12/09 20:53:31 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#ifndef EXECUTION_H
#define EXECUTION_H

#include "Voxel.h"
#include "Vect3D.h"
#include "GeomIn.h"
#include "TissIn.h"
#include "E1MinsIn.h"
#include "SeqnIn.h"

// class Execution is the calling routine for all file read-in processes. The default constructor of Execution
// calls default constructors of all classes designed to handle file input. After the files have been read, the
// Execution class will hold all of the information necessary for all calculations to take place.
class Execution
{
public:
	// class Info will hold general information about the run
	class Info
	{
	public:
		unsigned int nex;
		unsigned int totNumVox; // total number of voxels
		unsigned short int numRx; // number of receive coils
		Vect3D<float> wid; // voxel width
	};

	// Receive overlap and covariance-factor matrices, indexed [receiver][receiver].
	class NoiseInfo
	{
	public:
		std::vector<std::vector<std::complex<double> > > rMat; // Conductivity-weighted E-field overlap Phi.
		std::vector<std::vector<std::complex<double> > > aMat; // Factor A where A*A^H is the thermal covariance.
	};

	class Sequence
	{
	public:
		std::vector<float> time;
		std::vector<float> dwell;
		std::vector<int> acq;
	};

private:
	Info info;
	std::vector<Voxel> phantom; // 'phantom' is a vector of voxels that holds the sample geometry
	Sequence sequence;
	NoiseInfo noiseInfo;

	std::vector<std::vector<std::vector<std::complex<float> > > > kNoise; // [NEX][Rx][FOV*FOV]

	// these are functions to initialize the receiving data structures
	bool initPhantomInfo(CmdInterp & cmdInterp, SeqnIn & seqnIn, GeomIn & geomIn);
	bool initPhantomSeqn(const SeqnIn & seqnIn);
	bool initPhantomGeom(const GeomIn & geomIn);
	bool initPhantomTiss(const TissIn & tissIn);

	bool initPhantomE1Mins(const E1MinsIn & e1MinsIn);

	bool initPhantomKNoise();

public:

	bool initFlag;

	// The Execution constructor will call each of the file input routines, putting all of the required data
	// for the simulation in the appropriate locations.
	Execution(CmdInterp & cmdInterp);
	~Execution();

	// expPhantomKNoise() writes the completed noise files. The file names will be modified to indicate coil number.
	bool expPhantomKNoise(CmdInterp & cmdInterp);

	// 'get' functions
	Info & getInfo(){ return info; }; // NOTE: Using '&' increases performance, but 'const' can't be used.
	Sequence & getSequence(){ return sequence; };  // NOTE: Using '&' increases performance, but 'const' can't be used.
	NoiseInfo & getNoiseInfo(){ return noiseInfo; }; // NOTE: Using '&' increases performance, but 'const' can't be used.

	void setKNoise(const std::vector<std::vector<std::vector<std::complex<float> > > > & kNoiseData) { kNoise = kNoiseData; };
};

#endif /* EXECUTION_H */
