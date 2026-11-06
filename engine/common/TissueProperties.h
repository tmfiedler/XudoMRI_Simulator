#ifndef NUTATE_TISSUE_PROPERTIES_H
#define NUTATE_TISSUE_PROPERTIES_H

#include "NucleusDefinitions.h"
#include <map>
#include <ostream>

namespace nutate
{
    struct TissueProperties
    {
        float t1Seconds, t2ShortSeconds, t2LongSeconds;
        float concentrationMolPerL, chemicalShiftPpm, conductivitySiemensPerM;
    };

    // One unit/model contract for signal and noise; each engine projects only
    // the fields it needs. Tissue names and mass density are validated here.
    bool readTissueProperties(const std::string & fileName, const std::string & nucleusId,
        std::map<int, TissueProperties> & tissues, std::ostream & messages,
        const NucleusConfig & config);
}
#endif
