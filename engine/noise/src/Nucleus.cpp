#include "Nucleus.h"

bool getNucleusProperties(const std::string & name, NucleusProperties & properties)
{
	const auto * definition = nutate::findNucleusDefinition(name);
	if (!definition) return false;

	// Noise needs tissue identity/model agreement, not Bloch/RF parameters.
	properties.name = definition->name;
	properties.relaxationModel = definition->relaxationModel;
	return true;
}
