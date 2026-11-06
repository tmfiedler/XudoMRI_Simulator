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
    gridSize = reconContext.gridSize;
    kernelWidth = reconContext.kernelWidth;
    dcf = reconContext.dcf;
    coords = reconContext.coords;
    kernelTable = reconContext.kernelTable;
    deapod1D = reconContext.deapod1D;

    logFcn('Reconstructing with spokeData=%s coords=%s reconSize=%d gridSize=%d',...
        reconstructionSizeString(spokeData),reconstructionSizeString(coords),info.reconSize,gridSize);

    numCoils = size(spokeData,3);
    rssAccumulator = zeros(info.reconSize,info.reconSize,info.reconSize);
    somAccumulator = zeros(info.reconSize,info.reconSize,info.reconSize);
    complexAccumulator = complex(zeros(info.reconSize,info.reconSize,info.reconSize));
    kspaceAccumulator = complex(zeros(gridSize,gridSize,gridSize));

    for coil = 1:numCoils
        coilSamples = spokeData(:,:,coil);
        logFcn('Coil %d/%d coilSamples=%s dcf=%s',...
            coil,numCoils,reconstructionSizeString(coilSamples),reconstructionSizeString(dcf));
        coilGrid = adjointGridKaiserBessel(coilSamples(:) .* dcf(:),coords,gridSize,kernelWidth,kernelTable,logFcn);
        % The engine uses positive spatial phase; its adjoint uses the FFT sign.
        coilImage = fftshift(fftn(ifftshift(coilGrid)));
        coilImage = applyDeapodization(coilImage,deapod1D,logFcn) * reconContext.normalizationFactor;
        coilImage = cropCenteredVolume(coilImage,info.reconSize);
        logFcn('Coil %d grid=%s image=%s',coil,reconstructionSizeString(coilGrid),reconstructionSizeString(coilImage));

        rssAccumulator = rssAccumulator + abs(coilImage).^2;
        somAccumulator = somAccumulator + abs(coilImage);
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

function cropped = cropCenteredVolume(volume,targetSize)
    % Align the zero-position voxel for both even and odd target matrices.
    startIdx = floor(size(volume,1) / 2) - floor(targetSize / 2) + 1;
    stopIdx = startIdx + targetSize - 1;
    cropped = volume(startIdx:stopIdx,startIdx:stopIdx,startIdx:stopIdx);
end
