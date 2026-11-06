/*=========================================================================

  Program:   NutateSignal
  Module:    Nucleus.h
  Language:  C++

=========================================================================*/
#ifndef NUCLEUS_H
#define NUCLEUS_H

#include <string>
#include "../../common/NucleusDefinitions.h"

const float NUTATE_PI = 3.14159265358979323846264338327950288419716939937510f;

class NucleusProperties
{
public:
	std::string name;
	float gammaHzPerT;
	float gammaRadPerTPerS;
	RelaxationModel relaxationModel;
	float shortT2Weight;
	float longT2Weight;
	double equilibriumPerTeslaPerMolPerL; // A/m/T per mol/L of isotope nuclei
};

bool getNucleusProperties(const std::string & name, NucleusProperties & properties);
float defaultB1Plus90Deg1Ms(float gammaRadPerTPerS);

#endif /* NUCLEUS_H */
