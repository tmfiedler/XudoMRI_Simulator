function flipAngleDeg = flipAngleFromB1(targetB1MicroTesla,pulseAreaSeconds,gammaRadPerTPerS)
%FLIPANGLEFROMB1 Convert B1+ in microtesla to the nominal flip angle in degrees.

if isnan(targetB1MicroTesla) || isnan(pulseAreaSeconds)
    flipAngleDeg = NaN;
    return;
end

flipAngleDeg = gammaRadPerTPerS * pulseAreaSeconds * abs(targetB1MicroTesla) * 1e-6 * 180 / pi;
end
