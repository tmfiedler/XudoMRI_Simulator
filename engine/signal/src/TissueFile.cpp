#include "TissueFile.h"
#include "../../common/TissueProperties.h"

bool readTissuePropertyFile(const std::string & fileName,
    const NucleusProperties & expectedNucleus,
    std::map<int, TissType> & tissueMap, std::ostream & messages)
{
    std::map<int, nutate::TissueProperties> rows;
    if (!nutate::readTissueProperties(fileName, expectedNucleus.name, rows, messages, nutate::nucleusConfig())) return false;
    std::map<int, TissType> parsed;
    for (const auto & row : rows)
    {
        TissType t;
        t.t1 = row.second.t1Seconds;
        t.t2s = row.second.t2ShortSeconds;
        t.t2l = row.second.t2LongSeconds;
        t.concentrationMolPerL = row.second.concentrationMolPerL;
        t.sigmaChem = row.second.chemicalShiftPpm;
        parsed.emplace(row.first, t);
    }
    tissueMap.swap(parsed);
    return true;
}
