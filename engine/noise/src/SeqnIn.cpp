/*=========================================================================

  Program:   NutateNoise
  Module:    $RCSfile: SeqnIn.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 20:53:31 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include "SeqnIn.h"
#include "../../SequenceFile.h"
#include<utility>
#include<fstream>
#include<iostream>

// ------------------------------------------------------------------------------

// NOTE -- This method should have the 'const' qualifier, but it can't because 
// "cmdInterp.getCmdValues().seqn" accesses a public data value instead of 
// using a method to return the value.
SeqnIn::SeqnIn(CmdInterp & cmdInterp)
{
	fName = cmdInterp.getCmdValues().seqn;
	seqnFlag = readSeqnData();
}

SeqnIn::~SeqnIn()
{
	time.clear();
	acq.clear();
}

// ------------------------------------------------------------------------------

bool SeqnIn::readSeqnData()
{
    std::cout << "Reading Sequence data... ";
    SequenceFile::Data data;
    std::string error;
    if (!SequenceFile::read(fName, false, data, error))
    {
        std::cout << "\nSequence error in \"" << fName << "\": " << error << '\n';
        return false;
    }
    seqnHeader.totNumData = data.count;
    seqnHeader.numRx = data.rx;
    time = std::move(data.time);
    dwell = std::move(data.dwell);
    acq = std::move(data.acq);

    std::cout << "Finished!\n";
    return true;
}
