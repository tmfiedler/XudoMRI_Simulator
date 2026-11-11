function displayImagesCore(hImages,inputInfo,displayInfo,selectView,geoData)

% Pixel centers are one-based; voxel j occupies [j-0.5,j+0.5].

    tempBool = isfield(displayInfo,'HideFOVOverlay') && displayInfo.HideFOVOverlay;
    [center,width] = fovBox(inputInfo,displayInfo,selectView);
    axialIndex = clampIndex(inputInfo.currentZ+displayInfo.geoDeltaZ, size(geoData,3));
    sagittalIndex = clampIndex(inputInfo.currentX+displayInfo.geoDeltaX, size(geoData,1));
    coronalIndex = clampIndex(inputInfo.currentY+displayInfo.geoDeltaY, size(geoData,2));

    axialSlice = padWithZeros(squeeze(geoData(:, :, axialIndex)), [displayInfo.padAxial_X, displayInfo.padAxial_Y]);
    sagittalSlice = padWithZeros(squeeze(geoData(sagittalIndex, :, :)), [displayInfo.padSagittal_Y, displayInfo.padSagittal_Z]);
    coronalSlice = padWithZeros(squeeze(geoData(:, coronalIndex, :)), [displayInfo.padCoronal_X, displayInfo.padCoronal_Z]);

    switch displayInfo.Scale
        case 1 % Linear
            imageMatrixA = rot90(axialSlice); % for XY
            imageMatrixS = rot90(sagittalSlice); % for YZ
            imageMatrixC = rot90(coronalSlice); % for XZ
        case 2 % Log
            imageMatrixA = log(max(rot90(axialSlice), realmin('double'))); % for XY
            imageMatrixS = log(max(rot90(sagittalSlice), realmin('double'))); % for YZ
            imageMatrixC = log(max(rot90(coronalSlice), realmin('double'))); % for XZ
    end

    % Reverse rows using each actual padded raster, including non-square grids.
    % These local lengths affect overlays only; input padding/data stay unchanged.
    displayInfo.imageLengthXY = size(imageMatrixA,1);
    displayInfo.imageLengthYZ = size(imageMatrixS,1);
    displayInfo.imageLengthXZ = size(imageMatrixC,1);

    center = center + [displayInfo.geoDeltaX, displayInfo.geoDeltaY, displayInfo.geoDeltaZ];
    axialFOV = [center(1)+displayInfo.padAxial_X-width(1)/2, ...
        displayInfo.imageLengthXY-center(2)-displayInfo.padAxial_Y+1-width(2)/2, width([1 2])];
    sagittalFOV = [center(2)+displayInfo.padSagittal_Y-width(2)/2, ...
        displayInfo.imageLengthYZ-center(3)-displayInfo.padSagittal_Z+1-width(3)/2, width([2 3])];
    coronalFOV = [center(1)+displayInfo.padCoronal_X-width(1)/2, ...
        displayInfo.imageLengthXZ-center(3)-displayInfo.padCoronal_Z+1-width(3)/2, width([1 3])];

    renderSlice(hImages.hAxlImage, imageMatrixA);
    renderSlice(hImages.hSagImage, imageMatrixS);
    renderSlice(hImages.hCrlImage, imageMatrixC);

    hImages.Axial.volume = rectangle('Parent',hImages.hAxlImage,'position',...
        [inputInfo.minX+displayInfo.geoDeltaX+displayInfo.padAxial_X-.5,...
        displayInfo.imageLengthXY-(inputInfo.maxY+displayInfo.geoDeltaY+displayInfo.padAxial_Y)+.5,...
        inputInfo.maxX-inputInfo.minX+1, inputInfo.maxY-inputInfo.minY+1],...
        'EdgeColor','r');
    hImages.Axial.center = rectangle('Parent',hImages.hAxlImage,'position',...
        [inputInfo.ctrX+displayInfo.geoDeltaX+displayInfo.padAxial_X-3/2,...
        displayInfo.imageLengthXY-(inputInfo.ctrY+displayInfo.geoDeltaY+displayInfo.padAxial_Y)+1-3/2,...
        3, 3],'EdgeColor','y','FaceColor','y');

    hImages.Axial.slice = createFOVOverlay(hImages.hAxlImage,tempBool,...
        axialFOV);

    hImages.Sagittal.volume = rectangle('Parent',hImages.hSagImage,'position',...
        [inputInfo.minY+displayInfo.geoDeltaY+displayInfo.padSagittal_Y-.5,...
        displayInfo.imageLengthYZ-(inputInfo.maxZ+displayInfo.geoDeltaZ+displayInfo.padSagittal_Z)+.5,...
        inputInfo.maxY-inputInfo.minY+1, inputInfo.maxZ-inputInfo.minZ+1],...
        'EdgeColor','r');
    hImages.Sagittal.center = rectangle('Parent',hImages.hSagImage,'position',...
        [inputInfo.ctrY+displayInfo.geoDeltaY+displayInfo.padSagittal_Y-3/2,...
        displayInfo.imageLengthYZ-(inputInfo.ctrZ+displayInfo.geoDeltaZ+displayInfo.padSagittal_Z)+1-3/2,...
        3, 3],'EdgeColor','y','FaceColor','y');

    hImages.Sagittal.slice = createFOVOverlay(hImages.hSagImage,tempBool,...
        sagittalFOV);

    hImages.Coronal.volume = rectangle('Parent',hImages.hCrlImage,'position',...
        [inputInfo.minX+displayInfo.geoDeltaX+displayInfo.padCoronal_X-.5,...
        displayInfo.imageLengthXZ-(inputInfo.maxZ+displayInfo.geoDeltaZ+displayInfo.padCoronal_Z)+.5,...
        inputInfo.maxX-inputInfo.minX+1, inputInfo.maxZ-inputInfo.minZ+1],...
        'EdgeColor','r');
    hImages.Coronal.center = rectangle('Parent',hImages.hCrlImage,'position',...
        [inputInfo.ctrX+displayInfo.geoDeltaX+displayInfo.padCoronal_X-3/2,...
        displayInfo.imageLengthXZ-(inputInfo.ctrZ+displayInfo.geoDeltaZ+displayInfo.padCoronal_Z)+1-3/2,...
        3, 3],'EdgeColor','y','FaceColor','y');

    hImages.Coronal.slice = createFOVOverlay(hImages.hCrlImage,tempBool,...
        coronalFOV);
end

function hOverlay = createFOVOverlay(axisHandle,hideOverlay,position)
    if hideOverlay
        hOverlay = rectangle('Parent',axisHandle,'Visible','off');
    else
        hOverlay = rectangle('Parent',axisHandle,'position',position,'EdgeColor','g');
    end
end

function renderSlice(ax, imageMatrix)
    cla(ax);
    imagesc(ax, imageMatrix);
    axis(ax, 'image');
    axis(ax, 'off');
    colormap(ax, gray);
end

function index = clampIndex(index, maxIndex)
    index = round(index);
    index = min(max(index, 1), maxIndex);
end

function paddedMatrix = padWithZeros(inputMatrix, padSize)
    inputSize = size(inputMatrix);
    paddedMatrix = zeros(inputSize + 2 .* padSize);
    rowIndex = (1:inputSize(1)) + padSize(1);
    colIndex = (1:inputSize(2)) + padSize(2);
    paddedMatrix(rowIndex, colIndex) = inputMatrix;
end
