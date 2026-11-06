#include "TissueProperties.h"
#include <algorithm>
#include <cerrno>
#include <climits>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <limits>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>

namespace
{
    void require(bool valid, const std::string & message)
    {
        if (!valid) throw std::runtime_error(message);
    }

    std::vector<std::string> split(const std::string & line)
    {
        std::istringstream input(line);
        std::vector<std::string> tokens;
        for (std::string token; input >> token;) tokens.push_back(token);
        return tokens;
    }

    std::string lower(std::string value)
    {
        for (auto & c : value) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
        return value;
    }

    float numeric(const std::string & text, const std::string & name, bool nonnegative = true)
    {
        static const std::regex decimal("[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?");
        require(std::regex_match(text,decimal), name + " must be a finite decimal number");
        char * end = nullptr;
        errno = 0;
        const double number = std::strtod(text.c_str(), &end);
        const float value = static_cast<float>(number);
        require(end != text.c_str() && *end == '\0' && std::isfinite(number) &&
            std::isfinite(value) && (number == 0 || value != 0) &&
            (!nonnegative || number >= 0), name + " must be finite and representable in engine precision" +
            (nonnegative ? " and nonnegative" : ""));
        return value;
    }
}

namespace nutate
{
    bool readTissueProperties(const std::string & fileName, const std::string & nucleusId,
        std::map<int, TissueProperties> & tissues, std::ostream & messages,
        const NucleusConfig & config)
    {
        unsigned int lineNumber = 0;
        try
        {
            std::ifstream input(fileName);
            require(input.good(), "cannot open file");
            std::string line;
            require(static_cast<bool>(std::getline(input, line)), "missing V1 metadata");
            ++lineNumber;
            if (line.compare(0, 3, "\xEF\xBB\xBF") == 0) line.erase(0, 3);
            const auto metadata = split(line);
            require(metadata.size() == 2 && metadata[0] == "TISSUE_PROPERTIES_V1" &&
                metadata[1].compare(0, 8, "Nucleus=") == 0,
                "expected TISSUE_PROPERTIES_V1 Nucleus=<id> and concentration in mol/L");
            const auto fileId = metadata[1].substr(8);
            const NucleusDefinition * definition = nullptr;
            for (const auto & candidate : config.nuclei)
                if (candidate.name == fileId) definition = &candidate;
            require(definition != nullptr, "unknown nucleus id " + fileId);
            require(fileId == nucleusId, "file Nucleus=" + fileId + " does not match selected Nucleus=" + nucleusId);
            require(static_cast<bool>(std::getline(input, line)), "missing unit-bearing header row");
            ++lineNumber;
            const auto header = split(line);
            std::map<std::string, std::size_t> columns;
            for (std::size_t i = 0; i < header.size(); ++i)
                require(columns.emplace(lower(header[i]), i).second, "duplicate header " + header[i]);
            const bool twoPools = definition->relaxationModel == relax_biexponential;
            std::vector<std::string> required = {"id", "t1_ms", "concentration_mol_per_l",
                "chemical_shift_ppm", "conductivity_s_per_m", "mass_density_kg_per_m3", "tissue_name"};
            if (twoPools) { required.push_back("t2s_ms"); required.push_back("t2l_ms"); }
            else required.push_back("t2_ms");
            for (const auto & name : required) require(columns.count(name) != 0, "missing column " + name);
            require(twoPools ? columns.count("t2_ms") == 0 :
                columns.count("t2s_ms") == 0 && columns.count("t2l_ms") == 0,
                "relaxation columns must match the configured model");
            std::map<int, TissueProperties> parsed;
            while (std::getline(input, line))
            {
                ++lineNumber;
                const auto row = split(line);
                if (row.empty()) continue;
                require(row.size() == header.size(), "row/header field count differs; tissue names cannot contain spaces");
                const auto & idText = row[columns.at("id")];
                char * end = nullptr;
                errno = 0;
                const long id = std::strtol(idText.c_str(), &end, 10);
                require(end != idText.c_str() && *end == '\0' && errno == 0 && id >= INT_MIN && id <= INT_MAX,
                    "ID must be an integer");
                require(parsed.count(static_cast<int>(id)) == 0, "duplicate tissue ID " + idText);
                auto value = [&](const std::string & name, bool nonnegative = true)
                    { return numeric(row[columns.at(name)], name, nonnegative); };
                TissueProperties tissue;
                tissue.concentrationMolPerL = value("concentration_mol_per_l");
                const float t1 = value("t1_ms");
                const float t2s = value(twoPools ? "t2s_ms" : "t2_ms");
                const float t2l = twoPools ? value("t2l_ms") : t2s;
                require(tissue.concentrationMolPerL == 0 || (t1 > 0 && t2s > 0 && t2l > 0),
                    "relaxation times must be positive when concentration is nonzero");
                require(t2s <= t2l, "T2s_ms cannot exceed T2l_ms");
                tissue.t1Seconds = t1 / 1000.0f;
                tissue.t2ShortSeconds = t2s / 1000.0f;
                tissue.t2LongSeconds = t2l / 1000.0f;
                require((t1 == 0 || tissue.t1Seconds > 0) &&
                    (t2s == 0 || tissue.t2ShortSeconds > 0) &&
                    (t2l == 0 || tissue.t2LongSeconds > 0),
                    "nonzero relaxation times must remain positive in engine seconds");
                tissue.chemicalShiftPpm = value("chemical_shift_ppm", false);
                tissue.conductivitySiemensPerM = value("conductivity_s_per_m");
                value("mass_density_kg_per_m3");
                parsed.emplace(static_cast<int>(id), tissue);
            }
            require(!parsed.empty(), "no tissue data rows");
            tissues.swap(parsed);
            return true;
        }
        catch (const std::exception & error)
        {
            messages << "\nError reading tissue property file " << fileName << " at line " << lineNumber
                << ": " << error.what() << '\n';
            return false;
        }
    }
}
