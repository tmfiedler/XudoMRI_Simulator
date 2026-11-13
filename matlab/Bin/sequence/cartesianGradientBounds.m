function [maxBandwidth,minRFDuration] = cartesianGradientBounds(fovMm,sliceThicknessM,enabled,gammaHz,maxGradient)
%CARTESIANGRADIENTBOUNDS Readout bandwidth (kHz) and RF duration (ms) limits.
maxBandwidth = Inf;
minRFDuration = 0;
if enabled.fe
    maxBandwidth = gammaHz*fovMm*maxGradient/1e9;
end
if enabled.ss
    minRFDuration = 4e6/(gammaHz*sliceThicknessM*maxGradient);
end
end
