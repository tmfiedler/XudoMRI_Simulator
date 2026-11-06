/*=========================================================================

  Program:   NutateSignal
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
#include "Nucleus.h"

#define PI (float) 3.14159265358979323846264338327950288419716939937510

// Per-sample state for the signal simulation. A voxel combines geometry and
// tissue properties with position-dependent B1, off-resonance, and gradient
// perturbations. Its magnetization and derivative state evolve as each sequence
// step is applied; receiveSignalContribution() evaluates one receiver contribution.
class Voxel
{
private:
	// class TissInfo holds the tissue properties of the voxel.
	class TissInfo
	{
	public:
		float t1, t2s, t2l, concentrationMolPerL, sigmaChem, sigmaCon, rhoMass; // sigmaCon & rhoMass don't need unit conversion.
	};

	// class GeomInfo holds the x, y, and z position, and the tissue ID number
	class GeomInfo
	{
	public:	
		Vect3D<float> pos;
		unsigned int id;
	};

	// class BInfo holds the B1+ and B1- information for each coil in the simulation
	class BInfo
	{
	public:
		std::vector<std::complex<float> > b1Plus, b1Mins; // [Coil]

		float delB0;
		Vect3D<float> devDelB0;
		
		float delGradX, delGradY, delGradZ;
	};

	// Biexponential relaxation is represented by two complete spin pools.
	// The total values retain the existing signal/phase interface and are
	// synchronized sums of the short- and long-T2 pool states.
	Vect3D<float> magn;		// total magnetization = short pool + long pool
	Vect3D<float> magnShort;
	Vect3D<float> magnLong;
	float magn0;			// total equilibrium magnetization (z-direction)
	Vect3D<float> beff;		// b-effective

	// derivative of magnetization in 3 directions and frequency direction
	Vect3D<float> dxMagn;
	Vect3D<float> dyMagn;
	Vect3D<float> dzMagn;
	Vect3D<float> dwMagn;
	Vect3D<float> dxMagnShort, dxMagnLong;
	Vect3D<float> dyMagnShort, dyMagnLong;
	Vect3D<float> dzMagnShort, dzMagnLong;
	Vect3D<float> dwMagnShort, dwMagnLong;
	
	// derivative of Phi in 3 directions and frequency direction
	float dxPhi;
	float dyPhi;
	float dzPhi;
	float dwPhi; 
	float gammaRadPerTPerS;
	RelaxationModel relaxationModel;
	float shortT2Weight;
	float longT2Weight;

	void syncCombinedState();
	void advancePoolDerivatives(const Vect3D<float> & poolMagn,
		Vect3D<float> & poolDxMagn, Vect3D<float> & poolDyMagn,
		Vect3D<float> & poolDzMagn, Vect3D<float> & poolDwMagn,
		const Vect3D<float> & gradientTeslaPerMeter, float durationSeconds, float relaxXY, float relaxZ);

public:
	Voxel();
	~Voxel();

	GeomInfo geomInfo;
	TissInfo tissInfo;
	BInfo bInfo;

	void setMagn(const Vect3D<float> & magnToSet);
	void setMagn(float x, float y);
	Vect3D<float> getMagn(){ return magn; };

	void setDxMagn(float x, float y, float z);
	void setDyMagn(float x, float y, float z);
	void setDzMagn(float x, float y, float z);
	void setDwMagn(float x, float y, float z);

	void setDxPhi(float value) { dxPhi = value; };
	void setDyPhi(float value) { dyPhi = value; };
	void setDzPhi(float value) { dzPhi = value; };
	void setDwPhi(float value) { dwPhi = value; };

	void advanceMagnetizationDerivatives(const Vect3D<float> & gradientTeslaPerMeter, float durationSeconds);
	// Calculate phase derivatives from the combined pool magnetization at observation.
	void calculatePhaseDerivatives();

	void setMagn0(float m0){ magn0 = m0; };
	float getMagn0(){ return magn0; };
	void setNucleus(const NucleusProperties & nucleus);

	bool setTiss(const std::map<int, TissType> & tissMap);
	bool setB1Plus(const std::vector<std::complex<float> > & b1Plus);
	bool setB1Mins(const std::vector<std::complex<float> > & b1Mins);

	bool setDelB0(float delB0, const Vect3D<float> & devDelB0, float b0Tesla);
	bool setDelB0(float delB0, const Vect3D<float> & devDelB0, float b0Tesla, Vect3D<float> offset, Vect3D<float> voxelWidthMeters);

	bool setDelGradX(float gX);
	bool setDelGradY(float gY);
	bool setDelGradZ(float gZ);

	void initBeff() { beff = 0; };

	Vect3D<float> getBeff(){ return beff; };

	// RF weights multiply the complex B1+ map in tesla.
	// The longitudinal effective field includes carrier offsets converted from Hz,
	// delta B0 in tesla, and position times the perturbed gradient in T/m.
	// Positions and isochromat offsets use voxel indices; widths are metres.
	bool calculateEffectiveField(const std::vector<std::complex<float> > & rf,
		const std::vector<float> & carrierHz, const Vect3D<float> & gradientTeslaPerMeter,
		const std::vector<std::complex<float> > & aveB1Plus,
		const Vect3D<float> & voxelWidthMeters, const Vect3D<float> & isochromatOffsetVoxels);

	void rotateMagnetization(float durationSeconds); // Rotate each magnetization pool about B_eff.
	void relaxMagnetization(float durationSeconds); // Apply longitudinal and transverse relaxation.
	bool evolveMagnetization(const Vect3D<float> & gradientTeslaPerMeter, float durationSeconds); // Advance derivatives, then rotate and relax each pool over durationSeconds.

	// Evaluate the current state for one Rx using conjugated B1- and subvoxel volume.
	std::complex<float> receiveSignalContribution(unsigned int coilIndex, const Vect3D<float> & voxelWidthMeters, float b0Tesla, const Vect3D<unsigned short int> & numIso);

};  /* class Voxel*/

#endif /* VOXEL_H */

