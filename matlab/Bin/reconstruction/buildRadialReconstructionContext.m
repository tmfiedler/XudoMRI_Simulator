function reconContext = buildRadialReconstructionContext(traj,reconSize,fovMeters,logFcn)
%BUILDRADIALRECONSTRUCTIONCONTEXT Prepare geometry and weights for radial gridding.
%   traj is [samples per spoke, spokes, 3] in cycles/m, reconSize is the
%   isotropic matrix size in voxels, and fovMeters is the three-axis FOV.
%   An optional logFcn receives diagnostic format strings and arguments.
    if nargin < 4
        logFcn = @(varargin) [];
    end
    oversampling = 2;
    kernelWidth = 4;
    beta = beattyKaiserBeta(kernelWidth,oversampling);
    gridSize = oversampling * reconSize;
    logFcn('Building reconstruction context traj=%s reconSize=%d gridSize=%d',...
        reconstructionSizeString(traj),reconSize,gridSize);

    [coords,dcf,info] = prepareRadialTrajectory(traj,gridSize,reconSize,fovMeters,logFcn);
    logFcn('Prepared coords=%s dcf=%s',reconstructionSizeString(coords),reconstructionSizeString(dcf));
    info.reconSize = reconSize;
    info.gridSize = gridSize;
    info.kernelWidth = kernelWidth;
    info.oversampling = oversampling;
    info.beta = beta;

    reconContext.coords = coords;
    reconContext.dcf = dcf;
    reconContext.info = info;
    reconContext.kernelWidth = kernelWidth;
    reconContext.gridSize = gridSize;
    reconContext.kernelTable = buildKaiserTable(kernelWidth,beta,4096);
    reconContext.deapod1D = buildDeapodizationVector(gridSize,kernelWidth,beta,logFcn);
    % Normalized deapodization leaves the kernel DC gain cubed.
    kernelDCGain = real(kaiserBesselFourier(0,kernelWidth,beta));
    reconContext.normalizationFactor = 1 / (kernelDCGain^3 * sum(dcf));
end

function beta = beattyKaiserBeta(kernelWidth,oversampling)
    beta = pi * sqrt((kernelWidth / oversampling * (oversampling - 0.5))^2 - 0.8);
end

function deapod1D = buildDeapodizationVector(gridSize,kernelWidth,beta,logFcn)
    logFcn('Building deapodization vector gridSize=%d kernelWidth=%d beta=%g',...
        gridSize,kernelWidth,beta);
    coord = ((0:(gridSize-1)) - floor(gridSize/2)) / gridSize;
    deapod1D = real(kaiserBesselFourier(coord,kernelWidth,beta));
    deapod1D = deapod1D ./ max(deapod1D);
    deapod1D(deapod1D < 1e-3) = 1e-3;
end

function value = kaiserBesselFourier(coord,kernelWidth,beta)
    rootArg = sqrt(complex(beta^2 - (pi * kernelWidth * coord).^2,0));
    value = kernelWidth / besseli(0,beta) .* sinh(rootArg) ./ rootArg;
    zeroMask = abs(rootArg) < 1e-12;
    if any(zeroMask(:))
        value(zeroMask) = kernelWidth / besseli(0,beta);
    end
end
