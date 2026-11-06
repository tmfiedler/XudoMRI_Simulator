/*=========================================================================

  Program:   NutateSignal
  Module:    $RCSfile: SeqnIn.h,v $
  Language:  C++
  Date:      $Date: 2009/12/09 20:53:31 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#ifndef SEQNIN_H
#define SEQNIN_H

#include<vector>
#include<complex>
#include<string>

#include "CmdInterp.h"

// Expands the loop-encoded sequence into one value per time step. The binary
// layout and event meanings are specified in docs/FILE_FORMATS.md.
class SeqnIn
{
private:
	class SeqnHeader
	{
	public:
		unsigned int totNumData = 0;
		unsigned short int numRx = 0, numTx = 0;
	} seqnHeader;

	std::vector<float> time;
	std::vector<float> sampleOffset, dwell;
	std::vector<int> acq;
	std::vector<std::vector<std::complex<float> > > rf; // [coil][timeIndex]
	std::vector<std::vector<float> > delFreq; // [coil][timeIndex]
	std::vector<float> gX, gY, gZ;

	// these functions are called by the class's default constructor
	bool readSeqnData();

public:

	bool seqnFlag;
	std::string fName;

	SeqnIn(CmdInterp & cmdInterp);
	~SeqnIn();
	
	// 'get' functions
	SeqnHeader & getSeqnHeader(){ return seqnHeader; }; // NOTE: Using '&' increases performance, but 'const' can't be used.
	const std::vector<float> & getTime() const { return time; };
	const std::vector<float> & getSampleOffset() const { return sampleOffset; };
	const std::vector<float> & getDwell() const { return dwell; };
	const std::vector<int> & getAcq() const { return acq; };
	const std::vector<std::vector<std::complex<float> > > & getRF() const { return rf; };
	const std::vector<std::vector<float> > & getDelFreq() const { return delFreq; };
	const std::vector<float> & getGx() const { return gX; }; 
	const std::vector<float> & getGy() const { return gY; };
	const std::vector<float> & getGz() const { return gZ; };
};

#endif /* SEQNFILEIN_H */
