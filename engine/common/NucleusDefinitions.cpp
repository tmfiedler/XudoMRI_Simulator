#include "NucleusDefinitions.h"
#include <yaml-cpp/yaml.h>
#include <cmath>
#include <fstream>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

namespace
{
    void require(bool valid, const std::string & message)
    {
        if (!valid) throw std::runtime_error(message);
    }

    void fields(const YAML::Node & node, const std::set<std::string> & allowed,
        const std::set<std::string> & required, const std::string & context)
    {
        require(node.IsMap(), context + " must be a mapping");
        std::set<std::string> seen;
        for (const auto & item : node)
        {
            require(item.first.IsScalar(), context + " has a non-scalar key");
            const auto key = item.first.Scalar();
            require(allowed.count(key) != 0, context + ": unknown field " + key);
            require(seen.insert(key).second, context + ": duplicate field " + key);
        }
        for (const auto & key : required)
            require(seen.count(key) != 0, context + ": missing field " + key);
    }

    std::string scalar(const YAML::Node & node, const std::string & context)
    {
        require(node.IsScalar(), context + " must be a scalar");
        return node.Scalar();
    }

    double number(const YAML::Node & node, const std::string & context)
    {
        const auto text = scalar(node, context);
        // Match MATLAB's decimal schema; no YAML implicit bool/date coercion.
        static const std::regex decimal("[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?");
        require(std::regex_match(text, decimal), context + " must be a finite decimal number");
        const double result = std::stod(text);
        require(std::isfinite(result), context + " must be finite");
        return result;
    }

    std::string parent(const std::string & path)
    {
        const auto separator = path.find_last_of("/\\");
        return separator == std::string::npos ? std::string() : path.substr(0, separator);
    }
}

namespace nutate
{
    NucleusConfig readNucleusConfig(const std::string & fileName)
    {
        try
        {
            const auto documents = YAML::LoadAllFromFile(fileName);
            require(documents.size() == 1, "expected one YAML document");
            const auto root = documents.front();
            fields(root, {"sample_temperature_K", "default_nucleus", "nuclei"},
                {"sample_temperature_K", "default_nucleus", "nuclei"}, "configuration");
            NucleusConfig config;
            config.sampleTemperatureK = number(root["sample_temperature_K"], "sample_temperature_K");
            require(config.sampleTemperatureK > 0, "sample_temperature_K must be positive");
            config.defaultNucleus = scalar(root["default_nucleus"], "default_nucleus");
            const auto nuclei = root["nuclei"];
            require(nuclei.IsSequence() && nuclei.size() > 0, "nuclei must be a nonempty list");
            std::set<std::string> ids;
            for (const auto & node : nuclei)
            {
                fields(node, {"id", "gamma_Hz_per_T", "spin", "relaxation"},
                    {"id", "gamma_Hz_per_T", "spin", "relaxation"}, "nucleus");
                NucleusDefinition d;
                d.name = scalar(node["id"], "id");
                require(std::regex_match(d.name, std::regex("[A-Za-z0-9][A-Za-z0-9_-]*")),
                    "id must contain only letters, digits, underscore or hyphen");
                require(ids.insert(d.name).second, "duplicate nucleus id " + d.name);
                d.gammaHzPerT = number(node["gamma_Hz_per_T"], d.name + ".gamma_Hz_per_T");
                require(static_cast<float>(d.gammaHzPerT) > 0 &&
                    std::isfinite(static_cast<float>(d.gammaHzPerT * 2.0 * 3.14159265358979323846)),
                    d.name + ": only positive finite float-representable gamma is supported");
                d.spin = number(node["spin"], d.name + ".spin");
                require(d.spin > 0 && std::isfinite(2*d.spin) && 2*d.spin == std::floor(2*d.spin),
                    d.name + ": spin must be a positive integer or half-integer");
                const auto relaxation = node["relaxation"];
                fields(relaxation, {"model", "short_pool_fraction"}, {"model"}, d.name + ".relaxation");
                const auto model = scalar(relaxation["model"], d.name + ".relaxation.model");
                if (model == "single_pool_bloch")
                {
                    require(!relaxation["short_pool_fraction"], d.name + ": single pool has no pool fraction");
                    d.relaxationModel = relax_monoexponential;
                    d.shortT2Weight = 1.0f;
                    d.longT2Weight = 0.0f;
                }
                else
                {
                    require(model == "independent_two_pool_bloch", d.name + ": unsupported relaxation model " + model);
                    const double fraction = number(relaxation["short_pool_fraction"], d.name + ".short_pool_fraction");
                    require(fraction > 0 && fraction < 1, d.name + ": short_pool_fraction must be between zero and one");
                    d.relaxationModel = relax_biexponential;
                    d.shortT2Weight = static_cast<float>(fraction);
                    d.longT2Weight = static_cast<float>(1.0 - fraction);
                    require(d.shortT2Weight > 0 && d.longT2Weight > 0,
                        d.name + ": both pool fractions must remain positive in engine precision");
                }
                config.nuclei.push_back(d);
            }
            require(ids.count(config.defaultNucleus) != 0,
                "default_nucleus must name an existing exact nucleus ID");
            return config;
        }
        catch (const std::exception & error)
        {
            throw std::runtime_error("Nucleus configuration " + fileName + ": " + error.what());
        }
    }

    std::string nucleusConfigPath()
    {
        char path[32768] = {};
#ifdef _WIN32
        const auto count = GetModuleFileNameA(nullptr, path, sizeof(path));
        require(count > 0 && count < sizeof(path), "Cannot locate executable for nucleus configuration");
#else
        const auto count = readlink("/proc/self/exe", path, sizeof(path)-1);
        require(count > 0, "Cannot locate executable for nucleus configuration");
#endif
        // Installed engine/bin and native build/test directories resolve the
        // nearest ancestor containing config/nuclei.yaml; never use pwd.
        for (auto directory = parent(path); !directory.empty(); directory = parent(directory))
        {
            const auto candidate = directory + "/config/nuclei.yaml";
            if (std::ifstream(candidate).good()) return candidate;
        }
        throw std::runtime_error("Cannot find config/nuclei.yaml above executable location " + std::string(path));
    }

    const NucleusConfig & nucleusConfig()
    {
        static const auto config = readNucleusConfig(nucleusConfigPath());
        return config;
    }

    const std::vector<NucleusDefinition> & nucleusDefinitions() { return nucleusConfig().nuclei; }

    const NucleusDefinition * findNucleusDefinition(const std::string & id)
    {
        for (const auto & d : nucleusDefinitions()) if (d.name == id) return &d;
        return nullptr;
    }

    std::string supportedNucleusNames()
    {
        std::ostringstream names;
        bool first = true;
        for (const auto & d : nucleusDefinitions()) { names << (first ? "" : ", ") << d.name; first = false; }
        return names.str();
    }
}
