function [lobe,steps,values] = gradientAreaLobe(area,maxGradient,slew,raster)
%GRADIENTAREALOBE Design a zero-to-zero lobe in mT/m and ms.
rise = ceil(min(sqrt(abs(area)/slew),maxGradient/slew)/raster);
flat = 0;
peak = 0;
if rise > 0
    cap = min(maxGradient,slew*rise*raster);
    flat = max(0,ceil(abs(area)/(cap*raster)-rise));
    peak = area/((rise+flat)*raster);
end
lobe = struct('rise',rise,'flat',flat,'peak',peak,'duration',(2*rise+flat)*raster);
if nargout > 1
    ticks = repmat(raster,1,rise);
    up = peak*((1:rise)-0.5)/rise;
    steps = [ticks,flat*raster,ticks];
    values = [up,peak,fliplr(up)];
    keep = steps > 0;
    steps = steps(keep);
    values = values(keep);
end
end
