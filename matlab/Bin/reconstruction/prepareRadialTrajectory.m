function [coords,dcf,info,retained] = prepareRadialTrajectory(traj,gridSize,reconSize,fovMeters,logFcn)
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
    radius = sqrt(sum(trajectoryFlat.^2,2));
    if any(~isfinite(radius))
        error('RAD_3D:InvalidTrajectory','The trajectory contains nonfinite k-space radii.');
    end
    maxRadius = max(radius);
    if maxRadius <= 0
        error('Trajectory radius is zero.');
    end

    % A coarser output grid must reject frequencies outside its Nyquist band.
    % Use a spherical cutoff to keep the retained bandwidth isotropic.
    cutoff = reconSize / (2 * max(fovMeters));
    retained = radius <= cutoff;
    if maxRadius > cutoff
        trajectoryFlat = trajectoryFlat(retained,:);
        radius = radius(retained);
    end

    radiusNorm = radius / maxRadius;
    positiveRadius = radiusNorm(radiusNorm > 0);
    if isempty(positiveRadius)
        error('RAD_3D:EmptyReconstructionBand','The reconstruction matrix is too small to retain any nonzero k-space samples.');
    end
    minRadius = min(positiveRadius);
    dcf = max(radiusNorm,minRadius/2).^2;
    dcf = dcf ./ max(dcf);
    coords = bsxfun(@times,trajectoryFlat,fovMeters) * (gridSize / reconSize);
    logFcn('Exported k-space origin=[0 0 0] maxRadius=%g trajectoryFlat=%s',...
        maxRadius,reconstructionSizeString(trajectoryFlat));

    info.samplesPerSpoke = size(traj,1);
    info.numSpokes = size(traj,2);
    info.trajectoryCenter = [0 0 0];
    info.maxRadius = maxRadius;
    info.retainedMaxRadius = max(radius);
    info.retainedSampleCount = numel(radius);
    info.fovMeters = fovMeters;
    info.voxelSizeMeters = fovMeters / reconSize;
end
