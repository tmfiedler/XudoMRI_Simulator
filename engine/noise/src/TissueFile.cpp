#include "TissueFile.h"
#include "../../common/TissueProperties.h"

bool readNoiseTissuePropertyFile(const std::string & fileName,
    const NucleusProperties & expectedNucleus,
    std::map<int, TissType> & tissueMap, std::ostream & messages)
{
    std::map<int, nutate::TissueProperties> rows;
    if (!nutate::readTissueProperties(fileName, expectedNucleus.name, rows, messages, nutate::nucleusConfig())) return false;
    std::map<int, TissType> parsed;
    for (const auto & row : rows)
    {
        TissType t;
        t.sigmaCon = row.second.conductivitySiemensPerM;
        parsed.emplace(row.first, t);
    }
    tissueMap.swap(parsed);
    return true;
}
