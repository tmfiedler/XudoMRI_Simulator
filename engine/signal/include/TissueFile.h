#ifndef TISSUEFILE_H
#define TISSUEFILE_H

#include <iosfwd>
#include <map>
#include <string>

#include "Nucleus.h"
#include "TissType.h"

bool readTissuePropertyFile(const std::string & fileName,
	const NucleusProperties & expectedNucleus,
	std::map<int, TissType> & tissueMap,
	std::ostream & messages);

#endif /* TISSUEFILE_H */
