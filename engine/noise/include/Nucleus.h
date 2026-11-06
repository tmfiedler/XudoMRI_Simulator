/*=========================================================================

  Program:   NutateNoise
  Module:    Nucleus.h
  Language:  C++

 =========================================================================*/
#ifndef NUCLEUS_H
#define NUCLEUS_H

#include <string>
#include "../../common/NucleusDefinitions.h"

class NucleusProperties
{
public:
	std::string name;
	RelaxationModel relaxationModel;
};

bool getNucleusProperties(const std::string & name, NucleusProperties & properties);

#endif /* NUCLEUS_H */
