/*=========================================================================

  Program:   NutateNoise
  Module:    $RCSfile: Voxel.h,v $
  Language:  C++
  Date:      $Date: 2009/12/09 19:52:34 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#ifndef VOXEL_H
#define VOXEL_H

#include<complex>
#include<vector>
#include<cassert>
#include<map>

#include "Vect3D.h"
#include "TissType.h"
#include "Functions.h"

// Per-geometry-sample inputs used by the receive-noise covariance integral.
// Each voxel resolves its tissue conductivity from the geometry ID and stores
// one complex E1- vector for every receive coil.
class Voxel
{
private:
	class TissInfo
	{
	public:
		float sigmaCon; // Conductivity copied from the tissue map, in S/m.
	};

	// class GeomInfo holds the x, y, and z position, and the tissue ID number
	class GeomInfo
	{
	public:	
		Vect3D<float> pos;
		unsigned int id;
	};

	class EInfo
	{
	public:
		std::vector<Vect3D<std::complex<float> > > e1Mins; // [Coil]
	};

public:
	GeomInfo geomInfo;
	TissInfo tissInfo;
	EInfo eInfo;

	~Voxel();

	// setTiss is a lookup function that assigns tissue properties to the voxel via a tissue map
	bool setTiss(const std::map<int, TissType> & tissMap);
	bool setE1Mins(const std::vector<Vect3D<std::complex<float> > > & e1Mins);

};  /* class Voxel */

#endif /* VOXEL_H */

