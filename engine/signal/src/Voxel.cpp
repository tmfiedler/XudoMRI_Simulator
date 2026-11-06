/*=========================================================================

  Program:   NutateSignal
  Module:    $RCSfile: Voxel.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 19:52:34 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include"Voxel.h"
#include<iostream>

//#define SIMPLE_MODE
#define z_MODE
//#define COMPLEX_MODE

#define AdvancedRF

// ------------------------------------------------------------------------------

Voxel::Voxel()
{
	magn =0;		// magnetization vector
	magnShort = 0;
	magnLong = 0;
	magn0 = 0;		// magnetization (z-direction) at equilibrium
	beff = 0;		// b-effective

	// derivative of magnetization in 3 directions and frequency direction
	dxMagn = 0;
	dyMagn = 0;
	dzMagn = 0;
	dwMagn = 0;
	dxMagnShort = 0; dxMagnLong = 0;
	dyMagnShort = 0; dyMagnLong = 0;
	dzMagnShort = 0; dzMagnLong = 0;
	dwMagnShort = 0; dwMagnLong = 0;
	
	// derivative of Phi in 3 directions and frequency direction
	dxPhi = 0;
	dyPhi = 0;
	dzPhi = 0;
	dwPhi = 0;
	// Geometry construction is nucleus-independent. Execution installs the
	// selected definition before setting/evolving any magnetization state.
	gammaRadPerTPerS = 0.0f;
	relaxationModel = relax_monoexponential;
	shortT2Weight = 1.0f;
	longT2Weight = 0.0f;
}

// ------------------------------------------------------------------------------

Voxel::~Voxel()
{
	bInfo.b1Mins.clear();
	bInfo.b1Plus.clear();
}

void Voxel::setNucleus(const NucleusProperties & nucleus)
{
	gammaRadPerTPerS = nucleus.gammaRadPerTPerS;
	relaxationModel = nucleus.relaxationModel;
	shortT2Weight = nucleus.shortT2Weight;
	longT2Weight = nucleus.longT2Weight;
}

void Voxel::syncCombinedState()
{
	magn = magnShort + magnLong;
	dxMagn = dxMagnShort + dxMagnLong;
	dyMagn = dyMagnShort + dyMagnLong;
	dzMagn = dzMagnShort + dzMagnLong;
	dwMagn = dwMagnShort + dwMagnLong;
}

void Voxel::setMagn(const Vect3D<float> & magnToSet)
{
	magnShort = magnToSet;
	magnShort *= shortT2Weight;
	magnLong = magnToSet;
	magnLong *= longT2Weight;
	syncCombinedState();
}

void Voxel::setMagn(float x, float y)
{
	// Used by ideal crushing: preserve the independently evolved Mz values.
	magnShort.x = x * shortT2Weight;
	magnShort.y = y * shortT2Weight;
	magnLong.x = x * longT2Weight;
	magnLong.y = y * longT2Weight;
	syncCombinedState();
}

void Voxel::setDxMagn(float x, float y, float z)
{
	Vect3D<float> value; value.x = x; value.y = y; value.z = z;
	dxMagnShort = value * shortT2Weight;
	dxMagnLong = value * longT2Weight;
	syncCombinedState();
}

void Voxel::setDyMagn(float x, float y, float z)
{
	Vect3D<float> value; value.x = x; value.y = y; value.z = z;
	dyMagnShort = value * shortT2Weight;
	dyMagnLong = value * longT2Weight;
	syncCombinedState();
}

void Voxel::setDzMagn(float x, float y, float z)
{
	Vect3D<float> value; value.x = x; value.y = y; value.z = z;
	dzMagnShort = value * shortT2Weight;
	dzMagnLong = value * longT2Weight;
	syncCombinedState();
}

void Voxel::setDwMagn(float x, float y, float z)
{
	Vect3D<float> value; value.x = x; value.y = y; value.z = z;
	dwMagnShort = value * shortT2Weight;
	dwMagnLong = value * longT2Weight;
	syncCombinedState();
}

bool Voxel::setTiss(const std::map<int, TissType> & tissMap) 
{
	TissType tissType;
	std::map<int, TissType>::const_iterator itr;
	itr = tissMap.find(geomInfo.id);
	if ( itr != tissMap.end() )
	{
		tissType = itr->second;

		assert(tissType.t1 >= 0.0 && tissType.t2s >= 0.0 && tissType.t2l >= 0.0 && tissType.concentrationMolPerL >= 0.0);

		tissInfo.t1 = tissType.t1;
		tissInfo.t2s = tissType.t2s;
		tissInfo.t2l = tissType.t2l;
		tissInfo.concentrationMolPerL = tissType.concentrationMolPerL;
		tissInfo.sigmaChem = tissType.sigmaChem;

		return true;
	}
	else
	{
		std::cout<< "Fatal Error:Tissue Id=" << geomInfo.id << " cannot be found in Tissue Type File." << std::endl;
		return false;
	}
}

// ------------------------------------------------------------------------------

bool Voxel::setDelB0(float delB0, const Vect3D<float> & devDelB0, float b0Tesla)
{
	// all multiplications below by 1x10^(-6) are done to convert from parts-per-million(ppm)
	bInfo.devDelB0.x = (float) (0.000001 * devDelB0.x * b0Tesla);
	bInfo.devDelB0.y = (float) (0.000001 * devDelB0.y * b0Tesla);
	bInfo.devDelB0.z = (float) (0.000001 * devDelB0.z * b0Tesla);
	bInfo.delB0 = (float) (0.000001 * (delB0 - tissInfo.sigmaChem) * b0Tesla);
	return true;
}

// ------------------------------------------------------------------------------

bool Voxel::setDelB0(float delB0, const Vect3D<float> & devDelB0, float b0Tesla, Vect3D<float> offset, Vect3D<float> voxelWidthMeters)
{
	// all multiplications below by 1x10^(-6) are done to convert from parts-per-million(ppm)
	bInfo.devDelB0.x = (float) (0.000001 * devDelB0.x * b0Tesla);
	bInfo.devDelB0.y = (float) (0.000001 * devDelB0.y * b0Tesla);
	bInfo.devDelB0.z = (float) (0.000001 * devDelB0.z * b0Tesla);
	bInfo.delB0 = (float) (0.000001 * (delB0 - tissInfo.sigmaChem) * b0Tesla
		+ bInfo.devDelB0.x * offset.x * voxelWidthMeters.x + bInfo.devDelB0.y * offset.y * voxelWidthMeters.y + bInfo.devDelB0.z * offset.z * voxelWidthMeters.z);
	return true;
}

// ------------------------------------------------------------------------------

bool Voxel::setDelGradX(float delGradX)
{
	bInfo.delGradX = delGradX;
	return true;
}

bool Voxel::setDelGradY(float delGradY)
{
	bInfo.delGradY = delGradY;
	return true;
}

bool Voxel::setDelGradZ(float delGradZ)
{
	bInfo.delGradZ = delGradZ;
	return true;
}

// ------------------------------------------------------------------------------

bool Voxel::setB1Plus(const std::vector<std::complex<float> > & b1Plus)
{
	// the 'b1Plus' vector's index indicates the number of the coil causing the B1+ distribution
	for (unsigned int n=0; n<b1Plus.size(); n++)
	{
		bInfo.b1Plus.push_back(b1Plus[n]);
	}
	return true;
}

// ------------------------------------------------------------------------------

bool Voxel::setB1Mins(const std::vector<std::complex<float> > & b1Mins) // [Coil]
{
	// the 'b1Mins' vector's index indicates the number of the coil causing the B1- distribution
	for (unsigned int n=0; n<b1Mins.size(); n++)
	{
		bInfo.b1Mins.push_back(b1Mins[n]);
	}
	return true;
}

// ------------------------------------------------------------------------------

// RF weights multiply the complex B1+ map in tesla.
// The longitudinal effective field includes carrier offsets converted from Hz,
// delta B0 in tesla, and position times the perturbed gradient in T/m.
// Positions and isochromat offsets use voxel indices; widths are metres.
bool Voxel::calculateEffectiveField(const std::vector<std::complex<float> > & rf,
	const std::vector<float> & carrierHz, const Vect3D<float> & gradientTeslaPerMeter,
	const std::vector<std::complex<float> > & aveB1Plus,
	const Vect3D<float> & voxelWidthMeters, const Vect3D<float> & isochromatOffsetVoxels)
{
	(void)aveB1Plus;
	// Field initialization validates this invariant once; retain the assertion here
	// so debug builds also guard direct Voxel use.
	assert(rf.size() == bInfo.b1Plus.size());

	std::complex<double> temp;
	temp = std::complex<double> (0,0);
	beff = 0;

	for (unsigned int n = 0; n < rf.size(); n++) // for each rf coil
	{
		if (rf[n] != std::complex<float> (0,0))
		{
#ifdef AdvancedRF
			temp += (std::complex<double>) ((rf[n] * bInfo.b1Plus[n]) / (std::complex<float>((float)1.0,0)));
#endif
#ifndef AdvancedRF
			temp += (std::complex<double>) (rf[n] * bInfo.b1Plus[n] / aveB1Plus[n]); // this will cause problem for paralellism with inhomogeneous B1+.
#endif
		}
		beff.z -= carrierHz[n] / ((float)rf.size())/(gammaRadPerTPerS /(float)2/PI); // Normally the Multi-transmit sequence generated are designed each with a target frequency offset for slice selection, therefore should divide by number of TX coils here.
	}

	beff.x = (float) real(temp);
	beff.y = (float) imag(temp);
	beff.z += (float)(bInfo.delB0 + 
		voxelWidthMeters.x * (geomInfo.pos.x + isochromatOffsetVoxels.x) * (1.0 + bInfo.delGradX) * gradientTeslaPerMeter.x +
		voxelWidthMeters.y * (geomInfo.pos.y + isochromatOffsetVoxels.y) * (1.0 + bInfo.delGradY) * gradientTeslaPerMeter.y +
		voxelWidthMeters.z * (geomInfo.pos.z + isochromatOffsetVoxels.z) * (1.0 + bInfo.delGradZ) * gradientTeslaPerMeter.z);
	return true;
}

// ------------------------------------------------------------------------------
void Voxel::advancePoolDerivatives(const Vect3D<float> & poolMagn,
	Vect3D<float> & poolDxMagn, Vect3D<float> & poolDyMagn,
	Vect3D<float> & poolDzMagn, Vect3D<float> & poolDwMagn,
	const Vect3D<float> & gradientTeslaPerMeter, float durationSeconds, float relaxXY, float relaxZ)
{
	float thetaRF, thetaZ;
	thetaRF = (float) (gammaRadPerTPerS * durationSeconds * beff.getTransNorm()); // durationSeconds in s.
	thetaZ = (float) (-gammaRadPerTPerS * durationSeconds * beff.z); // Time in s.
	const float sinThetaZ = (float) sin(thetaZ);
	const float cosThetaZ = (float) cos(thetaZ);
	const float rotatedMagnX = -sinThetaZ * poolMagn.x + cosThetaZ * poolMagn.y;
	const float rotatedMagnY = -cosThetaZ * poolMagn.x - sinThetaZ * poolMagn.y;
	const float gradTermX = durationSeconds*gammaRadPerTPerS*(gradientTeslaPerMeter.x*((float)1.0+bInfo.delGradX)+bInfo.devDelB0.x);
	const float gradTermY = durationSeconds*gammaRadPerTPerS*(gradientTeslaPerMeter.y*((float)1.0+bInfo.delGradY)+bInfo.devDelB0.y);
	const float gradTermZ = durationSeconds*gammaRadPerTPerS*(gradientTeslaPerMeter.z*((float)1.0+bInfo.delGradZ)+bInfo.devDelB0.z);
	Vect3D<float> tempBeffTrans;
	tempBeffTrans.x = beff.x; tempBeffTrans.y = beff.y; tempBeffTrans.z = 0;
	Vect3D<float> tempDxMagn, tempDyMagn, tempDzMagn, tempDwMagn;

	tempDxMagn.x = gradTermX * rotatedMagnX + cosThetaZ * poolDxMagn.x + sinThetaZ * poolDxMagn.y;
	tempDxMagn.y = gradTermX * rotatedMagnY - sinThetaZ * poolDxMagn.x + cosThetaZ * poolDxMagn.y;
	tempDxMagn.z = poolDxMagn.z;
	rotate(tempDxMagn, tempBeffTrans, thetaRF);
	tempDxMagn.x = tempDxMagn.x * relaxXY;
	tempDxMagn.y = tempDxMagn.y * relaxXY;
	tempDxMagn.z = tempDxMagn.z * relaxZ;

	tempDyMagn.x = gradTermY * rotatedMagnX + cosThetaZ * poolDyMagn.x + sinThetaZ * poolDyMagn.y;
	tempDyMagn.y = gradTermY * rotatedMagnY - sinThetaZ * poolDyMagn.x + cosThetaZ * poolDyMagn.y;
	tempDyMagn.z = poolDyMagn.z;
	rotate(tempDyMagn, tempBeffTrans, thetaRF);
	tempDyMagn.x = tempDyMagn.x * relaxXY;
	tempDyMagn.y = tempDyMagn.y * relaxXY;
	tempDyMagn.z = tempDyMagn.z * relaxZ;

	tempDzMagn.x = gradTermZ * rotatedMagnX + cosThetaZ * poolDzMagn.x + sinThetaZ * poolDzMagn.y;
	tempDzMagn.y = gradTermZ * rotatedMagnY - sinThetaZ * poolDzMagn.x + cosThetaZ * poolDzMagn.y;
	tempDzMagn.z = poolDzMagn.z;
	rotate(tempDzMagn, tempBeffTrans, thetaRF);
	tempDzMagn.x = tempDzMagn.x * relaxXY;
	tempDzMagn.y = tempDzMagn.y * relaxXY;
	tempDzMagn.z = tempDzMagn.z * relaxZ;

	tempDwMagn.x = durationSeconds * rotatedMagnX + cosThetaZ * poolDwMagn.x + sinThetaZ * poolDwMagn.y;
	tempDwMagn.y = durationSeconds * rotatedMagnY - sinThetaZ * poolDwMagn.x + cosThetaZ * poolDwMagn.y;
	tempDwMagn.z = poolDwMagn.z;
	rotate(tempDwMagn, tempBeffTrans, thetaRF);
	tempDwMagn.x = tempDwMagn.x * relaxXY;
	tempDwMagn.y = tempDwMagn.y * relaxXY;
	tempDwMagn.z = tempDwMagn.z * relaxZ;

	poolDxMagn = tempDxMagn;
	poolDyMagn = tempDyMagn;
	poolDzMagn = tempDzMagn;
	poolDwMagn = tempDwMagn;
}

void Voxel::advanceMagnetizationDerivatives(const Vect3D<float> & gradientTeslaPerMeter, float durationSeconds)
{
	const float relaxZ = (float) exp(-durationSeconds/tissInfo.t1);
	const float relaxShort = (float) exp(-durationSeconds/tissInfo.t2s);
	advancePoolDerivatives(magnShort, dxMagnShort, dyMagnShort, dzMagnShort, dwMagnShort,
		gradientTeslaPerMeter, durationSeconds, relaxShort, relaxZ);

	if (relaxationModel == relax_biexponential)
	{
		const float relaxLong = (float) exp(-durationSeconds/tissInfo.t2l);
		advancePoolDerivatives(magnLong, dxMagnLong, dyMagnLong, dzMagnLong, dwMagnLong,
			gradientTeslaPerMeter, durationSeconds, relaxLong, relaxZ);
	}

	syncCombinedState();
}

// ------------------------------------------------------------------------------

void Voxel::rotateMagnetization(float durationSeconds)
{
	float theta;
	theta = (float) (gammaRadPerTPerS * durationSeconds * beff.getNorm()); // Time in s.
	rotate(magnShort, beff, theta);
	if (relaxationModel == relax_biexponential)
	{
		rotate(magnLong, beff, theta);
	}
	syncCombinedState();
}

// ------------------------------------------------------------------------------

void Voxel::relaxMagnetization(float durationSeconds)
{
	// Each pool recovers toward its own equilibrium Mz, with shared T1.
	const float expT2s = (float) exp((-durationSeconds)/tissInfo.t2s);
	const float relaxZ = (float) exp((-durationSeconds)/tissInfo.t1);
	magnShort.x *= expT2s;
	magnShort.y *= expT2s;
	magnShort.z = magn0 * shortT2Weight - (magn0 * shortT2Weight - magnShort.z) * relaxZ;

	if (relaxationModel == relax_biexponential)
	{
		const float expT2l = (float) exp((-durationSeconds)/tissInfo.t2l);
		magnLong.x *= expT2l;
		magnLong.y *= expT2l;
		magnLong.z = magn0 * longT2Weight - (magn0 * longT2Weight - magnLong.z) * relaxZ;
	}

	syncCombinedState();
}

// ------------------------------------------------------------------------------

bool Voxel::evolveMagnetization(const Vect3D<float> & gradientTeslaPerMeter, float durationSeconds)
{
	// Derivatives use the interval-start pool state, before rotation and relaxation.
	// Keep this order aligned with CUDA evolveMagnetizationRFOn/RFOff.
#ifdef COMPLEX_MODE
	advanceMagnetizationDerivatives(gradientTeslaPerMeter, durationSeconds);
#endif
#ifdef z_MODE
	advanceMagnetizationDerivatives(gradientTeslaPerMeter, durationSeconds);
#endif

	if (!(beff == 0))
	{
		rotateMagnetization(durationSeconds);
	}
	relaxMagnetization(durationSeconds);

	return true;
}

// ------------------------------------------------------------------------------

std::complex<float> Voxel::receiveSignalContribution(unsigned int coilIndex, const Vect3D<float> & voxelWidthMeters, float b0Tesla, const Vect3D<unsigned short int> & numIso)
{
	// Public z_MODE uses x/y sinc averaging and explicit z isochromat subdivision.
	// Alternative compile-time paths remain for scientific comparison. Public
	// builds use z_MODE; see TODO.md before changing these equations.
#ifdef SIMPLE_MODE
	return ( std::complex<float> (magn.x,magn.y) * conj(bInfo.b1Mins[coilIndex]) * gammaRadPerTPerS * (b0Tesla+bInfo.delB0)
		* (voxelWidthMeters.x/((float)numIso.x)) * (voxelWidthMeters.y/((float)numIso.y)) * (voxelWidthMeters.z/((float)numIso.z)) );
#endif

#ifdef z_MODE
	return ( std::complex<float> (magn.x,magn.y) * conj(bInfo.b1Mins[coilIndex]) * gammaRadPerTPerS * (b0Tesla+bInfo.delB0)
		* (voxelWidthMeters.x/((float)numIso.x)) * (voxelWidthMeters.y/((float)numIso.y)) * (voxelWidthMeters.z/((float)numIso.z))
		* sinc(voxelWidthMeters.x/((float)numIso.x)*dxPhi/(float)2)
		* sinc(voxelWidthMeters.y/((float)numIso.y)*dyPhi/(float)2));
#endif

#ifdef COMPLEX_MODE
	return ( std::complex<float> (magn.x,magn.y) * conj(bInfo.b1Mins[coilIndex]) * gammaRadPerTPerS * (b0Tesla+bInfo.delB0)
		* (voxelWidthMeters.x/((float)numIso.x)) * (voxelWidthMeters.y/((float)numIso.y)) * (voxelWidthMeters.z/((float)numIso.z))
		* sinc(voxelWidthMeters.x/((float)numIso.x)*dxPhi/(float)2)
		* sinc(voxelWidthMeters.y/((float)numIso.y)*dyPhi/(float)2)
		* sinc(voxelWidthMeters.z/((float)numIso.z)*dzPhi/(float)2));
#endif
}

// ------------------------------------------------------------------------------

void Voxel::calculatePhaseDerivatives()
{
	if (magn.x == 0 && magn.y == 0)
	{
		dxPhi = 0;
		dyPhi = 0;
		dzPhi = 0;
		dwPhi = 0;
	}
	else
	{
		const float transNorm2 = magn.getTransNorm2();
		dxPhi = ( magn.x*dxMagn.y - magn.y*dxMagn.x ) / transNorm2;
		dyPhi = ( magn.x*dyMagn.y - magn.y*dyMagn.x ) / transNorm2;
		dzPhi = ( magn.x*dzMagn.y - magn.y*dzMagn.x ) / transNorm2;
		dwPhi = ( magn.x*dwMagn.y - magn.y*dwMagn.x ) / transNorm2;
	}
}
