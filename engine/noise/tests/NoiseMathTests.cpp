#include "Functions.h"

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

typedef std::vector<std::vector<std::complex<double> > > ComplexMatrix;

namespace
{
	bool closeEnough(const std::complex<double> & actual,
		const std::complex<double> & expected, double tolerance)
	{
		return std::abs(actual - expected) <= tolerance;
	}

	bool checkFactor(const ComplexMatrix & covariance)
	{
		ComplexMatrix factor;
		std::string error;
		if (!factorHermitianPositiveSemidefinite(covariance, factor, error))
		{
			std::cerr << "Factorization failed: " << error << std::endl;
			return false;
		}
		for (std::size_t i = 0; i < covariance.size(); ++i)
		{
			for (std::size_t j = 0; j < covariance.size(); ++j)
			{
				std::complex<double> reconstructed(0.0, 0.0);
				for (std::size_t k = 0; k < covariance.size(); ++k)
				{
					reconstructed += factor[i][k] * std::conj(factor[j][k]);
				}
				if (!closeEnough(reconstructed, covariance[i][j], 1.0e-10))
				{
					std::cerr << "Factor reconstruction mismatch at [" << i
						<< "][" << j << "]" << std::endl;
					return false;
				}
			}
		}
		return true;
	}

	bool checkStatistics(const ComplexMatrix & covariance, unsigned int sampleCount)
	{
		ComplexMatrix factor;
		std::string error;
		if (!factorHermitianPositiveSemidefinite(covariance, factor, error))
		{
			std::cerr << "Statistical factorization failed: " << error << std::endl;
			return false;
		}

		const std::size_t size = covariance.size();
		ComplexMatrix measured(size,
			std::vector<std::complex<double> >(size, std::complex<double>(0.0, 0.0)));
		ComplexMatrix pseudoCovariance(size,
			std::vector<std::complex<double> >(size, std::complex<double>(0.0, 0.0)));
		std::vector<std::complex<double> > mean(size, std::complex<double>(0.0, 0.0));
		std::vector<std::complex<double> > z(size);
		std::vector<std::complex<double> > noise(size);
		ComplexGaussianGenerator randomNoise(123456u);

		for (unsigned int sample = 0; sample < sampleCount; ++sample)
		{
			for (std::size_t j = 0; j < size; ++j)
			{
				z[j] = randomNoise.next();
			}
			for (std::size_t i = 0; i < size; ++i)
			{
				noise[i] = std::complex<double>(0.0, 0.0);
				for (std::size_t j = 0; j < size; ++j)
				{
					noise[i] += factor[i][j] * z[j];
				}
				mean[i] += noise[i];
			}
			for (std::size_t i = 0; i < size; ++i)
			{
				for (std::size_t j = 0; j < size; ++j)
				{
					measured[i][j] += noise[i] * std::conj(noise[j]);
					pseudoCovariance[i][j] += noise[i] * noise[j];
				}
			}
		}

		double scale = 0.0;
		for (std::size_t i = 0; i < size; ++i)
		{
			mean[i] /= static_cast<double>(sampleCount);
			scale = std::max(scale, std::abs(covariance[i][i]));
			for (std::size_t j = 0; j < size; ++j)
			{
				measured[i][j] /= static_cast<double>(sampleCount);
				pseudoCovariance[i][j] /= static_cast<double>(sampleCount);
			}
		}

		const double covarianceTolerance = scale * 0.012;
		const double meanTolerance = std::sqrt(scale / sampleCount) * 5.0;
		for (std::size_t i = 0; i < size; ++i)
		{
			if (std::abs(mean[i]) > meanTolerance)
			{
				std::cerr << "Nonzero sample mean at coil " << i << std::endl;
				return false;
			}
			for (std::size_t j = 0; j < size; ++j)
			{
				if (!closeEnough(measured[i][j], covariance[i][j], covarianceTolerance))
				{
					std::cerr << "Empirical covariance mismatch at [" << i
						<< "][" << j << "]: measured " << measured[i][j]
						<< ", expected " << covariance[i][j] << std::endl;
					return false;
				}
				if (std::abs(pseudoCovariance[i][j]) > covarianceTolerance)
				{
					std::cerr << "Noise is not circular complex Gaussian at [" << i
						<< "][" << j << "]: pseudo-covariance "
						<< pseudoCovariance[i][j] << std::endl;
					return false;
				}
			}
		}
		return true;
	}

	bool checkReproducibility()
	{
		ComplexGaussianGenerator first(987654321u);
		ComplexGaussianGenerator second(987654321u);
		ComplexGaussianGenerator different(987654322u);
		bool differentSeedDiverged = false;
		for (unsigned int sample = 0; sample < 1000u; ++sample)
		{
			const std::complex<double> firstValue = first.next();
			if (firstValue != second.next())
			{
				std::cerr << "Equal noise seeds did not reproduce the same samples." << std::endl;
				return false;
			}
			if (firstValue != different.next())
			{
				differentSeedDiverged = true;
			}
		}
		if (!differentSeedDiverged)
		{
			std::cerr << "Different noise seeds produced an identical stream." << std::endl;
			return false;
		}
		return true;
	}
}

int main()
{
	ComplexMatrix realCovariance(2, std::vector<std::complex<double> >(2));
	realCovariance[0][0] = 4.0;
	realCovariance[0][1] = 1.0;
	realCovariance[1][0] = 1.0;
	realCovariance[1][1] = 9.0;

	ComplexMatrix complexCovariance(2, std::vector<std::complex<double> >(2));
	complexCovariance[0][0] = 4.0;
	complexCovariance[0][1] = std::complex<double>(1.0, 0.75);
	complexCovariance[1][0] = std::conj(complexCovariance[0][1]);
	complexCovariance[1][1] = 9.0;

	ComplexMatrix semidefiniteCovariance(2, std::vector<std::complex<double> >(2));
	semidefiniteCovariance[0][0] = 1.0;
	semidefiniteCovariance[0][1] = std::complex<double>(0.0, 1.0);
	semidefiniteCovariance[1][0] = std::conj(semidefiniteCovariance[0][1]);
	semidefiniteCovariance[1][1] = 1.0;

	if (!checkFactor(realCovariance) ||
		!checkFactor(complexCovariance) ||
		!checkFactor(semidefiniteCovariance) ||
		!checkStatistics(complexCovariance, 400000u) ||
		!checkReproducibility())
	{
		return EXIT_FAILURE;
	}

	std::cout << "NutateNoise covariance tests passed." << std::endl;
	return EXIT_SUCCESS;
}
