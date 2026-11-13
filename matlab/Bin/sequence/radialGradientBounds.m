function maxBandwidth = radialGradientBounds(sampleCount,kEdge,maxComponent,gammaHz,maxGradient)
%RADIALGRADIENTBOUNDS Maximum bandwidth in kHz for all spoke directions.
maxBandwidth = maxGradient*gammaHz*sampleCount/(1e6*kEdge*maxComponent);
end
