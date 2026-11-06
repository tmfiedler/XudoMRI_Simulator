/*=========================================================================

  Program:   NutateNoise
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

// Validates the complete loop-encoded sequence, retaining only timing and
// acquisition flags. See docs/FILE_FORMATS.md for the layout.
class SeqnIn
{
private:
	class SeqnHeader
	{
	public:
		unsigned int totNumData = 0;
		unsigned short int numRx = 0;
	} seqnHeader;

	// Noise uses timing and acquisition windows only.
	std::vector<float> time;
	std::vector<float> dwell;
	std::vector<int> acq;

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
	const std::vector<float> & getDwell() const { return dwell; };
	const std::vector<int> & getAcq() const { return acq; };
};

#endif /* SEQNFILEIN_H */
