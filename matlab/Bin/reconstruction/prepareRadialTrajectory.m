function [coords,dcf,info] = prepareRadialTrajectory(traj,gridSize,reconSize,fovMeters,logFcn)
%PREPARERADIALTRAJECTORY Convert cycles/m to grid coordinates and density weights.
    if nargin < 5
        logFcn = @(varargin) [];
    end
    if ~isnumeric(fovMeters) || numel(fovMeters) ~= 3 || ...
            any(~isfinite(fovMeters(:))) || any(fovMeters(:) <= 0)
        error('RAD_3D:InvalidFOV','Physical reconstruction FOV must have three finite positive metre values.');
    end
    fovMeters = reshape(fovMeters,1,3);
    logFcn('Preparing physical trajectory traj=%s gridSize=%d reconSize=%d FOV(m)=%s',...
        reconstructionSizeString(traj),gridSize,reconSize,mat2str(fovMeters));
    % Exported coordinates are absolute cycles/m; midpoint samples are not k=0.
    trajectoryFlat = reshape(traj,[],3);
    radius = sqrt(sum(traj.^2,3));
    maxRadius = max(radius(:));
    if maxRadius <= 0
        error('Trajectory radius is zero.');
    end

    coords = bsxfun(@times,trajectoryFlat,fovMeters) * (gridSize / reconSize);
    logFcn('Exported k-space origin=[0 0 0] maxRadius=%g trajectoryFlat=%s',...
        maxRadius,reconstructionSizeString(trajectoryFlat));

    radiusNorm = radius(:) / maxRadius;
    positiveRadius = radiusNorm(radiusNorm > 0);
    if isempty(positiveRadius)
        positiveRadius = 1;
    end
    minRadius = min(positiveRadius);
    dcf = max(radiusNorm,minRadius/2).^2;
    dcf = dcf ./ max(dcf);

    info.samplesPerSpoke = size(traj,1);
    info.numSpokes = size(traj,2);
    info.trajectoryCenter = [0 0 0];
    info.maxRadius = maxRadius;
    info.fovMeters = fovMeters;
    info.voxelSizeMeters = fovMeters / reconSize;
end
