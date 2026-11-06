/*=========================================================================

  Program:   NutateSignal
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
#include<cstdint>
#include<cstring>

namespace
{
    bool sameCarrier(float left, float right)
    {
        // GUI exports repeat one float32 carrier waveform for every Tx.
        // Require zero ULP difference, allowing only equivalent signed zeros.
        // Compare bits so host flush-to-zero cannot hide subnormal differences.
        std::uint32_t leftBits, rightBits;
        std::memcpy(&leftBits, &left, sizeof(leftBits));
        std::memcpy(&rightBits, &right, sizeof(rightBits));
        return leftBits == rightBits ||
            ((leftBits | rightBits) & 0x7fffffffu) == 0;
    }
}

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
	for (unsigned int i = 0; i < rf.size(); i++)
	{
		rf[i].clear();
	}
	rf.clear();
	for (unsigned int i = 0; i < delFreq.size(); i++)
	{
		delFreq[i].clear();
	}
	delFreq.clear();

	gX.clear();
	gY.clear();
	gZ.clear();
}

// ------------------------------------------------------------------------------

bool SeqnIn::readSeqnData()
{
    std::cout << "Reading Sequence data... ";
    SequenceFile::Data data;
    std::string error;
    if (!SequenceFile::read(fName, true, data, error))
    {
        std::cout << "\nSequence error in \"" << fName << "\": " << error << '\n';
        return false;
    }
    // Both backends use one rotating frame, including RF-off and muted Tx
    // entries. Different channel carriers cannot be represented by averaging.
    // Validate expanded timelines before initialization or scientific output.
    for (unsigned int coil = 1; coil < data.tx; ++coil)
    {
        for (unsigned int step = 0; step < data.count; ++step)
        {
            if (!sameCarrier(data.frequency[0][step], data.frequency[coil][step]))
            {
                std::cout << "\nSequence error in \"" << fName
                    << "\": transmitters must share the same frequency-offset waveform (Hz); channel "
                    << coil + 1 << " differs at step " << step + 1 << '\n';
                return false;
            }
        }
    }
    seqnHeader.totNumData = data.count;
    seqnHeader.numRx = data.rx;
    time = std::move(data.time);
    sampleOffset = std::move(data.sampleOffset);
    dwell = std::move(data.dwell);
    acq = std::move(data.acq);
    seqnHeader.numTx = data.tx;
    rf = std::move(data.rf);
    delFreq = std::move(data.frequency);
    gX = std::move(data.gx);
    gY = std::move(data.gy);
    gZ = std::move(data.gz);
    std::cout << "Finished!\n";
    return true;
}
