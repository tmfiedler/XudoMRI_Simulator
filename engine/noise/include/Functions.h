/*=========================================================================

  Program:   NutateNoise
  Module:    $RCSfile: Functions.h,v $
  Language:  C++
  Date:      $Date: 2009/12/09 18:54:15 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#ifndef FUNCTIONS_H
#define FUNCTIONS_H

#include <cstdint>
#include <complex>
#include <random>
#include <string>
#include <vector>

class ComplexGaussianGenerator
{
public:
	explicit ComplexGaussianGenerator(std::uint64_t seed);
	std::complex<double> next();

private:
	std::mt19937_64 engine;
	std::normal_distribution<double> normalDistribution;
};

// Create a nondeterministic default seed. Passing an explicit NoiseSeed on the
// command line bypasses this and makes a run reproducible with the same build.
std::uint64_t generateNoiseSeed();

// Compute a lower-triangular factor L for a Hermitian positive-semidefinite
// covariance matrix C such that L * L^H = C.
bool factorHermitianPositiveSemidefinite(
	const std::vector<std::vector<std::complex<double> > > & covariance,
	std::vector<std::vector<std::complex<double> > > & factor,
	std::string & errorMessage);

#endif /* FUNCTIONS_H */
