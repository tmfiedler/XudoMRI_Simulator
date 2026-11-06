function [scaleFactor,effectiveB1MicroTesla,errorMessage] = resolveTxAmplitudeScale(desiredB1MicroTesla,shimB1MicroTesla)
%RESOLVETXAMPLITUDESCALE Scale a shim using numeric B1+ values in microtesla.
% A NaN desired value represents an unspecified target.

scaleFactor = 1;
effectiveB1MicroTesla = NaN;
errorMessage = '';

if isnan(desiredB1MicroTesla)
    if isfinite(shimB1MicroTesla) && shimB1MicroTesla > 0
        effectiveB1MicroTesla = shimB1MicroTesla;
    end
    return;
end

effectiveB1MicroTesla = desiredB1MicroTesla;
if desiredB1MicroTesla == 0
    scaleFactor = 0;
    return;
end

if ~isfinite(shimB1MicroTesla) || shimB1MicroTesla <= 0
    effectiveB1MicroTesla = NaN;
    errorMessage = 'Desired B1+ scaling requires a positive shim B1+ in the Tx Array dialog.';
    return;
end

scaleFactor = desiredB1MicroTesla / shimB1MicroTesla;
end
