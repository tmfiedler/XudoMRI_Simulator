function [kEdge,directions,maxComponent] = radialReadoutGeometry(matrixSize,fov,adc)
%RADIALREADOUTGEOMETRY Nominal radial extent and Fibonacci-sphere directions.
if isfield(adc,'radialResolutionMm') && ~isempty(adc.radialResolutionMm)
    validateattributes(adc.radialResolutionMm,{'numeric'},{'scalar','real','finite','positive'});
    kEdge = 500/adc.radialResolutionMm;
else
    kEdge = matrixSize(1)*500/max([fov(:);1]);
end
count = matrixSize(end);
index = (0:count-1)';
z = -1+2*(index+0.5)/count;
r = sqrt(max(0,1-z.^2));
phi = index*(pi*(3-sqrt(5)));
directions = [r.*cos(phi),r.*sin(phi),z];
maxComponent = max(abs(directions),[],'all');
end
