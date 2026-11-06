function targetB1MicroTesla = b1MicroTeslaFromFlipAngle(flipAngleDeg,pulseAreaSeconds,gammaRadPerTPerS)
%B1MICROTESLAFROMFLIPANGLE Convert a nominal flip angle to B1+ in microtesla.

denominator = gammaRadPerTPerS * pulseAreaSeconds * 1e-6 * 180 / pi;
if isnan(flipAngleDeg) || isnan(denominator) || denominator == 0
    targetB1MicroTesla = NaN;
    return;
end

targetB1MicroTesla = abs(flipAngleDeg) / denominator;
end
