function recon = reconstructRadialDataset(spokeData,reconContext,logFcn)
%RECONSTRUCTRADIALDATASET Reconstruct complex samples by spoke and Rx coil.
%   spokeData is [samples per spoke, spokes, coils] in trajectory order.
%   reconContext comes from buildRadialReconstructionContext. Output contains
%   RSS, sum of magnitudes, complex sum, k-space magnitude and grid metadata.
%   An optional logFcn receives diagnostic format strings and arguments.
    if nargin < 3
        logFcn = @(varargin) [];
    end
    info = reconContext.info;
    if size(spokeData,1) ~= info.samplesPerSpoke || size(spokeData,2) ~= info.numSpokes
        error('RAD_3D:SignalDimensions','Signal dimensions must match the radial trajectory.');
    end
    gridSize = reconContext.gridSize;
    kernelWidth = reconContext.kernelWidth;
    dcf = reconContext.dcf;
    coords = reconContext.coords;
    kernelTable = reconContext.kernelTable;
    bandLimited = numel(dcf) < numel(reconContext.retained);

    % Gather the centered FOV directly from the unshifted FFT output. The
    % deapodization vector uses centered indices, so crop it separately.
    imageOffsets = -floor(info.reconSize/2):ceil(info.reconSize/2)-1;
    fftIndices = mod(imageOffsets,gridSize) + 1;
    deapod1D = reconContext.deapod1D(floor(gridSize/2) + imageOffsets + 1);

    logFcn('Reconstructing with spokeData=%s coords=%s reconSize=%d gridSize=%d',...
        reconstructionSizeString(spokeData),reconstructionSizeString(coords),info.reconSize,gridSize);

    numCoils = size(spokeData,3);
    samplesByCoil = reshape(spokeData,[],numCoils);
    rssAccumulator = zeros(info.reconSize,info.reconSize,info.reconSize);
    somAccumulator = zeros(info.reconSize,info.reconSize,info.reconSize);
    complexAccumulator = complex(zeros(info.reconSize,info.reconSize,info.reconSize));
    kspaceAccumulator = complex(zeros(gridSize,gridSize,gridSize));

    for coil = 1:numCoils
        if bandLimited
            coilSamples = samplesByCoil(reconContext.retained,coil);
        else
            coilSamples = samplesByCoil(:,coil);
        end
        logFcn('Coil %d/%d coilSamples=%s dcf=%s',...
            coil,numCoils,reconstructionSizeString(coilSamples),reconstructionSizeString(dcf));
        weightedSamples = coilSamples .* dcf;
        coilGrid = adjointGridKaiserBessel(weightedSamples,coords,gridSize,kernelWidth,kernelTable,logFcn);
        % The engine uses positive spatial phase; its adjoint uses the FFT sign.
        coilImage = fftn(ifftshift(coilGrid));
        coilImage = coilImage(fftIndices,fftIndices,fftIndices);
        coilImage = applyDeapodization(coilImage,deapod1D,logFcn) * reconContext.normalizationFactor;
        logFcn('Coil %d grid=%s image=%s',coil,reconstructionSizeString(coilGrid),reconstructionSizeString(coilImage));

        magnitude = abs(coilImage);
        rssAccumulator = rssAccumulator + magnitude.^2;
        somAccumulator = somAccumulator + magnitude;
        complexAccumulator = complexAccumulator + coilImage;
        kspaceAccumulator = kspaceAccumulator + coilGrid;
    end

    recon.volumeRSS = single(sqrt(rssAccumulator));
    recon.volumeSOM = single(somAccumulator);
    recon.volumeComplex = single(complexAccumulator);
    recon.kspaceMagnitude = single(abs(kspaceAccumulator));
    recon.info = info;
end

function volume = applyDeapodization(volume,deapod1D,logFcn)
    logFcn('Applying deapodization volume=%s deapod1D=%s',...
        reconstructionSizeString(volume),reconstructionSizeString(deapod1D));
    volume = bsxfun(@rdivide,volume,reshape(deapod1D,[],1,1));
    volume = bsxfun(@rdivide,volume,reshape(deapod1D,1,[],1));
    volume = bsxfun(@rdivide,volume,reshape(deapod1D,1,1,[]));
end
