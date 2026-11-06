/*=========================================================================

  Program:   NutateSignal
  Module:    $RCSfile: TissType.h,v $
  Language:  C++
  Date:      $Date: 2009/12/09 18:54:15 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#ifndef TISSTYPE_H
#define TISSTYPE_H

// class TissType holds the properties of each tissue. It is linked to a tissue ID
// via a map.
class TissType
{
public:
	// T1, T2, isotope concentration (mol/L), Chemical Shift
	float t1, t2s, t2l, concentrationMolPerL, sigmaChem;
};

#endif /* TISSTYPE_H */
