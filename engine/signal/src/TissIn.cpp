#include "TissIn.h"
#include "TissueFile.h"

#include <iostream>

TissIn::TissIn(CmdInterp & cmdInterp)
{
	fName = cmdInterp.getCmdValues().tiss;
	if (!getNucleusProperties(cmdInterp.getCmdValues().nucleus, nucleus))
	{
		std::cout << "\nUnsupported Nucleus value \"" << cmdInterp.getCmdValues().nucleus << "\".\n";
		tissFlag = false;
		return;
	}
	tissFlag = readTissData();
}

bool TissIn::readTissData()
{
	std::cout << "Reading Tissue Type data...";
	if (!readTissuePropertyFile(fName, nucleus, tissMap, std::cout))
	{
		return false;
	}
	std::cout << "Finished!\n";
	return true;
}
