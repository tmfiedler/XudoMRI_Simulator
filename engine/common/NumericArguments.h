#ifndef NUTATE_NUMERIC_ARGUMENTS_H
#define NUTATE_NUMERIC_ARGUMENTS_H

#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <string>

namespace nutate
{
    inline bool numericArgumentError(const std::string& key, const char* requirement)
    {
        std::cerr << "Error: " << key << " " << requirement << ".\n";
        return false;
    }

    // Keep strtod's numeric syntax, but never accept an empty/partial conversion,
    // nonfinite value, overflow, or a nonzero value rounded to zero in float.
    inline bool finiteFloatArgument(const std::string& text, const std::string& key, float& value)
    {
        char* end = nullptr;
        errno = 0;
        const double parsed = std::strtod(text.c_str(), &end);
        if (errno == ERANGE || end == text.c_str() || *end != '\0' ||
            !std::isfinite(parsed) || std::abs(parsed) > std::numeric_limits<float>::max())
            return numericArgumentError(key, "must be a finite float-representable number");
        const float stored = static_cast<float>(parsed);
        if (parsed != 0 && stored == 0)
            return numericArgumentError(key, "must not underflow engine precision");
        value = stored;
        return true;
    }

    inline bool positiveWidthArgument(const std::string& text, const std::string& key, float& value)
    {
        if (!finiteFloatArgument(text, key, value)) return false;
        if (value <= 0 || value / 1000.0f == 0)
            return numericArgumentError(key, "must remain positive after conversion from mm to metres");
        return true;
    }

    inline bool positiveCountArgument(const std::string& text, const std::string& key,
        unsigned short& value)
    {
        // Validate in double before narrowing: 65535.0001 must not become 65535.
        char* end = nullptr;
        errno = 0;
        const double parsed = std::strtod(text.c_str(), &end);
        if (errno == ERANGE || end == text.c_str() || *end != '\0' ||
            !std::isfinite(parsed) || parsed < 1 ||
            parsed > std::numeric_limits<unsigned short>::max() || parsed != std::floor(parsed))
            return numericArgumentError(key, "must be a whole integer from 1 to 65535");
        value = static_cast<unsigned short>(parsed);
        return true;
    }

    inline bool indexArgument(const std::string& text, const std::string& key, float& value)
    {
        // Preserve the existing signed, base-0 (decimal/octal/hex) index syntax.
        char* end = nullptr;
        errno = 0;
        const long long parsed = std::strtoll(text.c_str(), &end, 0);
        if (errno == ERANGE || end == text.c_str() || *end != '\0' ||
            parsed < std::numeric_limits<int>::min() || parsed > std::numeric_limits<int>::max())
            return numericArgumentError(key, "must be a signed 32-bit integer index");
        const float stored = static_cast<float>(parsed);
        if (static_cast<double>(stored) != static_cast<double>(parsed))
            return numericArgumentError(key, "must be exactly representable in engine float storage");
        value = stored;
        return true;
    }
}

#endif
