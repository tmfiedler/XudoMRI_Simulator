#ifndef NUTATE_THERMAL_MAGNETIZATION_H
#define NUTATE_THERMAL_MAGNETIZATION_H

#include "NucleusDefinitions.h"
#include <cmath>
#include <stdexcept>

namespace nutate
{
    // Exact SI constants. Gamma in Hz/T pairs with h; gamma in rad/s/T
    // would instead pair with hbar and gives the same physical expression.
    constexpr double avogadroPerMol = 6.02214076e23;
    constexpr double planckJouleSeconds = 6.62607015e-34;
    constexpr double boltzmannJoulePerKelvin = 1.380649e-23;

    inline double equilibriumPerTeslaPerMolPerL(const NucleusDefinition & nucleus,
        double temperatureK)
    {
        const double g = nucleus.gammaHzPerT;
        const double h = planckJouleSeconds;
        const double spin = nucleus.spin;
        const double coefficient = 1000.0 * avogadroPerMol * g * g * h * h *
            spin * (spin + 1.0) / (3.0 * boltzmannJoulePerKelvin * temperatureK);
        if (!(temperatureK > 0) || !std::isfinite(coefficient) || coefficient <= 0)
            throw std::runtime_error("Invalid thermal-equilibrium coefficient");
        return coefficient;
    }
}
#endif
