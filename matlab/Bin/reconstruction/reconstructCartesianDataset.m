function [recon,matSize] = reconstructCartesianDataset(signalData,protocol)
%RECONSTRUCTCARTESIANDATASET Reconstruct one Cartesian plane from coil data.
%   signalData is [readout samples * phase encodes, Rx coils] in acquisition
%   order. protocol supplies MatSize, SequenceType, SliceOrientation,
%   PEDirection and an optional phase vector in acquisition order.

    matSize = round(protocol.MatSize(:).');
    if numel(matSize) < 2 || any(matSize(1:2) <= 0)
        error('Protocol file does not define a valid Cartesian MatSize.');
    end
    matSize = matSize(1:2);
    expectedSamples = prod(matSize);
    if size(signalData,1) ~= expectedSamples
        error(['Selected Cartesian .ksig sample count does not match protocol MatSize. ',...
            'Expected ',num2str(expectedSamples),' samples.']);
    end

    geometry = getCartesianGeometry(protocol);
    if isfield(protocol,'FOVPhase')
        signalData = signalData .* protocol.FOVPhase;
    end

    numCoils = size(signalData,2);
    imageCoils = [];
    kspaceCoils = zeros(matSize(1),matSize(2),numCoils);
    for coilIdx = 1:numCoils
        kspaceData = reshape(signalData(:,coilIdx),matSize(1),matSize(2));
        kspaceData = restoreCartesianReadoutOrder(kspaceData,protocol.SequenceType);
        if geometry.reversePE
            kspaceData = fliplr(kspaceData);
        end
        imageData = fftshift(fft2(fftshift(kspaceData)));
        if strcmp(geometry.imageTransform,'rotateClockwise')
            imageData = rot90(imageData,-1);
        else
            imageData = fliplr(imageData);
        end
        if isempty(imageCoils)
            imageCoils = zeros(size(imageData,1),size(imageData,2),numCoils);
        end
        kspaceCoils(:,:,coilIdx) = kspaceData;
        imageCoils(:,:,coilIdx) = imageData;
    end

    volumeRSS = sqrt(sum(abs(imageCoils).^2,3));
    volumeSOM = sum(abs(imageCoils),3);
    volumeComplex = sum(imageCoils,3);
    kspaceMagnitude = sqrt(sum(abs(kspaceCoils).^2,3));

    recon.volumeRSS = single(embedCartesianImage(volumeRSS,geometry.orientation));
    recon.volumeSOM = single(embedCartesianImage(volumeSOM,geometry.orientation));
    recon.volumeComplex = embedCartesianImage(volumeComplex,geometry.orientation);
    recon.kspaceMagnitude = single(reshape(kspaceMagnitude,matSize(1),matSize(2),1));
    recon.info = struct('mode','Cartesian',...
        'matSize',matSize,'numCoils',numCoils,'reconSize',matSize(1),...
        'samplesPerSpoke',matSize(1),'numSpokes',matSize(2),...
        'sliceOrientation',geometry.orientation,'peDirection',protocol.PEDirection);
end

function kspaceData = restoreCartesianReadoutOrder(kspaceData,sequenceType)
    % The EPI frequency-encoding gradient reverses on every even echo, so those columns run
    % from positive to negative k-space and must be reversed before the
    % Cartesian FFT. Do this before any whole-matrix PE-direction reversal.
    if strcmpi(strtrim(sequenceType),'GRE_EPI')
        kspaceData(:,2:2:end) = flipud(kspaceData(:,2:2:end));
    end
end

function geometry = getCartesianGeometry(protocol)
    orientation = strtrim(protocol.SliceOrientation);
    peDirection = strtrim(protocol.PEDirection);

    geometry.orientation = orientation;
    geometry.reversePE = false;
    switch peDirection
        case 'A--P'
            peDirection = 'P--A';
            geometry.reversePE = true;
        case 'R--L'
            peDirection = 'L--R';
            geometry.reversePE = true;
        case 'H--F'
            peDirection = 'F--H';
            geometry.reversePE = true;
    end
    switch orientation
        case 'Axial'
            switch peDirection
                case 'P--A'
                    geometry.imageTransform = 'rotateClockwise';
                case 'L--R'
                    geometry.imageTransform = 'flipLeftRight';
                otherwise
                    error('Unsupported PE direction "%s" for axial Cartesian data.',peDirection);
            end

        case 'Sagittal'
            switch peDirection
                case 'P--A'
                    geometry.imageTransform = 'flipLeftRight';
                case 'F--H'
                    geometry.imageTransform = 'rotateClockwise';
                otherwise
                    error('Unsupported PE direction "%s" for sagittal Cartesian data.',peDirection);
            end

        case 'Coronal'
            switch peDirection
                case 'L--R'
                    geometry.imageTransform = 'flipLeftRight';
                case 'F--H'
                    geometry.imageTransform = 'rotateClockwise';
                otherwise
                    error('Unsupported PE direction "%s" for coronal Cartesian data.',peDirection);
            end

        otherwise
            error('Unsupported Cartesian slice orientation: %s',orientation);
    end
end

function volume = embedCartesianImage(imageData,orientation)
    % Undo the generic display rotation before placing the image in its plane.
    storedPlane = rot90(imageData,-1);
    switch orientation
        case 'Axial'
            volume = reshape(storedPlane,size(storedPlane,1),size(storedPlane,2),1);
        case 'Sagittal'
            volume = reshape(storedPlane,1,size(storedPlane,1),size(storedPlane,2));
        case 'Coronal'
            volume = reshape(storedPlane,size(storedPlane,1),1,size(storedPlane,2));
        otherwise
            error('Unsupported Cartesian slice orientation: %s',orientation);
    end
end
