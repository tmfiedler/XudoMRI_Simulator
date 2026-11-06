#ifndef NUTATE_NUCLEUS_DEFINITIONS_H
#define NUTATE_NUCLEUS_DEFINITIONS_H

#include <string>
#include <vector>

enum RelaxationModel
{
	relax_monoexponential,
	relax_biexponential
};

namespace nutate
{
	// Shared input data. Spin supplies the thermal I(I+1) factor; only the
	// selected relaxation model determines implemented Bloch pool dynamics.
	struct NucleusDefinition
	{
		std::string name;
		double gammaHzPerT;
		double spin;
		RelaxationModel relaxationModel;
		float shortT2Weight;
		float longT2Weight;
	};

	struct NucleusConfig
	{
		double sampleTemperatureK;
		std::string defaultNucleus;
		std::vector<NucleusDefinition> nuclei;
	};

	NucleusConfig readNucleusConfig(const std::string & fileName);
	std::string nucleusConfigPath();
	const NucleusConfig & nucleusConfig();
	const std::vector<NucleusDefinition> & nucleusDefinitions();
	const NucleusDefinition * findNucleusDefinition(const std::string & id);
	std::string supportedNucleusNames();
}

#endif
