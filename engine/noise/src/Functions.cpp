/*=========================================================================

  Program:   NutateNoise
  Module:    $RCSfile: Functions.cpp,v $
  Language:  C++
  Date:      $Date: 2009/12/09 18:54:15 $

  Copyright (c) The Pennsylvania State University. All rights reserved.

=========================================================================*/
#include "Functions.h"

#include <algorithm>
#include <chrono>
#include <complex>
#include <limits>
#include <random>
#include <sstream>
#include <vector>

// ------------------------------------------------------------------------------

ComplexGaussianGenerator::ComplexGaussianGenerator(std::uint64_t seed)
	: engine(seed), normalDistribution(0.0, 1.0)
{
}

std::complex<double> ComplexGaussianGenerator::next()
{
	const double inverseSqrtTwo = 0.70710678118654752440;
	return std::complex<double>(normalDistribution(engine) * inverseSqrtTwo,
		normalDistribution(engine) * inverseSqrtTwo);
}

std::uint64_t generateNoiseSeed()
{
	std::uint64_t seed = static_cast<std::uint64_t>(
		std::chrono::high_resolution_clock::now().time_since_epoch().count());
	try
	{
		std::random_device entropy;
		seed ^= static_cast<std::uint64_t>(entropy()) << 32;
		seed ^= static_cast<std::uint64_t>(entropy());
	}
	catch (...)
	{
		// The high-resolution clock still supplies a changing fallback seed on
		// platforms where std::random_device is unavailable.
	}
	return seed;
}

// ------------------------------------------------------------------------------

bool factorHermitianPositiveSemidefinite(
	const std::vector<std::vector<std::complex<double> > > & covariance,
	std::vector<std::vector<std::complex<double> > > & factor,
	std::string & errorMessage)
{
	typedef std::vector<std::complex<double> > ComplexRow;
	const std::size_t size = covariance.size();
	errorMessage.clear();
	factor.assign(size, ComplexRow(size, std::complex<double>(0.0, 0.0)));

	if (size == 0)
	{
		errorMessage = "noise covariance matrix is empty";
		return false;
	}

	double matrixScale = 0.0;
	for (std::size_t i = 0; i < size; ++i)
	{
		if (covariance[i].size() != size)
		{
			errorMessage = "noise covariance matrix is not square";
			return false;
		}
		for (std::size_t j = 0; j < size; ++j)
		{
			if (!std::isfinite(covariance[i][j].real()) ||
				!std::isfinite(covariance[i][j].imag()))
			{
				errorMessage = "noise covariance matrix contains a non-finite value";
				return false;
			}
			matrixScale = std::max(matrixScale, std::abs(covariance[i][j]));
		}
	}

	if (matrixScale == 0.0)
	{
		return true;
	}

	const double tolerance = std::max(matrixScale * 1.0e-10,
		std::numeric_limits<double>::denorm_min() * 1024.0);
	const double pivotTolerance = std::sqrt(tolerance);

	for (std::size_t i = 0; i < size; ++i)
	{
		for (std::size_t j = 0; j < size; ++j)
		{
			if (std::abs(covariance[i][j] - std::conj(covariance[j][i])) > tolerance)
			{
				std::ostringstream message;
				message << "noise covariance matrix is not Hermitian at ["
					<< i << "][" << j << "]";
				errorMessage = message.str();
				return false;
			}
		}
	}

	for (std::size_t i = 0; i < size; ++i)
	{
		for (std::size_t j = 0; j <= i; ++j)
		{
			std::complex<double> residual = covariance[i][j];
			for (std::size_t k = 0; k < j; ++k)
			{
				residual -= factor[i][k] * std::conj(factor[j][k]);
			}

			if (i == j)
			{
				if (std::abs(residual.imag()) > tolerance)
				{
					errorMessage = "noise covariance diagonal is not real";
					return false;
				}
				double diagonal = residual.real();
				if (diagonal < -tolerance)
				{
					std::ostringstream message;
					message << "noise covariance matrix is not positive semidefinite; negative pivot at coil "
						<< (i + 1);
					errorMessage = message.str();
					return false;
				}
				if (diagonal < 0.0)
				{
					diagonal = 0.0;
				}
				factor[i][i] = std::complex<double>(std::sqrt(diagonal), 0.0);
			}
			else if (factor[j][j].real() > pivotTolerance)
			{
				factor[i][j] = residual / factor[j][j].real();
			}
			else if (std::abs(residual) > tolerance)
			{
				errorMessage = "noise covariance matrix is numerically singular and cannot be factorized";
				return false;
			}
		}
	}

	double maximumError = 0.0;
	for (std::size_t i = 0; i < size; ++i)
	{
		for (std::size_t j = 0; j < size; ++j)
		{
			std::complex<double> reconstructed(0.0, 0.0);
			for (std::size_t k = 0; k < size; ++k)
			{
				reconstructed += factor[i][k] * std::conj(factor[j][k]);
			}
			maximumError = std::max(maximumError,
				std::abs(reconstructed - covariance[i][j]));
		}
	}
	if (maximumError > matrixScale * 1.0e-8)
	{
		errorMessage = "noise covariance factor failed its reconstruction check";
		return false;
	}

	return true;
}
