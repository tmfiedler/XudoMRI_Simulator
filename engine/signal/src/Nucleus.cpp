#include "Nucleus.h"
#include "../../common/ThermalMagnetization.h"

bool getNucleusProperties(const std::string & name, NucleusProperties & properties)
{
	const auto * definition = nutate::findNucleusDefinition(name);
	if (!definition) return false;

	properties.name = definition->name;
	properties.gammaHzPerT = static_cast<float>(definition->gammaHzPerT);
	// Host/CUDA share this existing float conversion; MATLAB retains double pi.
	properties.gammaRadPerTPerS = properties.gammaHzPerT * 2.0f * NUTATE_PI;
	properties.relaxationModel = definition->relaxationModel;
	properties.shortT2Weight = definition->shortT2Weight;
	properties.longT2Weight = definition->longT2Weight;
	properties.equilibriumPerTeslaPerMolPerL = nutate::equilibriumPerTeslaPerMolPerL(
		*definition, nutate::nucleusConfig().sampleTemperatureK);
	return true;
}

float defaultB1Plus90Deg1Ms(float gammaRadPerTPerS)
{
	return NUTATE_PI / 2.0f / gammaRadPerTPerS / 0.001f;
}
