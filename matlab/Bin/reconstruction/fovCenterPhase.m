function phase = fovCenterPhase(trajectory,offset,spacingMm)
%FOVCENTERPHASE Recenter positive-phase signal using model-axis k in cycles/m.
    validateattributes(trajectory,{'numeric'},{'real','finite','ncols',3});
    validateattributes(spacingMm,{'numeric'},{'real','finite','positive','numel',3});
    displacement = offset(:).*spacingMm(:)/1000;
    validateattributes(displacement,{'numeric'},{'real','finite','numel',3});
    phase = exp(-2i*pi*(trajectory*displacement));
end
