function grid = adjointGridKaiserBessel(samples,coords,gridSize,kernelWidth,kernelTable,logFcn)
%ADJOINTGRIDKAISERBESSEL Deposit weighted samples onto a periodic 3D grid.
    if nargin < 6
        logFcn = @(varargin) [];
    end
    logFcn('Adjoint gridding samples=%s coords=%s gridSize=%d kernelWidth=%d',...
        reconstructionSizeString(samples),reconstructionSizeString(coords),gridSize,kernelWidth);
    gridVector = complex(zeros(gridSize^3,1));
    halfWidth = kernelWidth / 2;

    gx = coords(:,1) + gridSize/2 + 1;
    gy = coords(:,2) + gridSize/2 + 1;
    gz = coords(:,3) + gridSize/2 + 1;

    % Closed support includes integer endpoints; the table mask rejects extra nodes.
    baseX = ceil(gx - halfWidth);
    baseY = ceil(gy - halfWidth);
    baseZ = ceil(gz - halfWidth);

    for ox = 0:floor(kernelWidth)
        ix = baseX + ox;
        wx = sampleKaiserTable(gx - ix,kernelTable);
        validX = wx > 0;
        if ~any(validX)
            continue;
        end

        for oy = 0:floor(kernelWidth)
            iy = baseY + oy;
            wy = sampleKaiserTable(gy - iy,kernelTable);
            validXY = validX & wy > 0;
            if ~any(validXY)
                continue;
            end

            wxy = wx .* wy;
            for oz = 0:floor(kernelWidth)
                iz = baseZ + oz;
                wz = sampleKaiserTable(gz - iz,kernelTable);
                valid = validXY & wz > 0;
                if ~any(valid)
                    continue;
                end

                idx = find(valid);
                % Kernel distances use unwrapped nodes; the DFT grid is periodic.
                wrappedX = mod(ix(idx)-1,gridSize) + 1;
                wrappedY = mod(iy(idx)-1,gridSize) + 1;
                wrappedZ = mod(iz(idx)-1,gridSize) + 1;
                lin = sub2ind([gridSize,gridSize,gridSize],wrappedX,wrappedY,wrappedZ);
                vals = samples(idx) .* wxy(idx) .* wz(idx);
                [linUnique,~,groupIdx] = unique(lin);
                gridVector(linUnique) = gridVector(linUnique) + accumarray(groupIdx,vals);
            end
        end
    end

    grid = reshape(gridVector,[gridSize,gridSize,gridSize]);
end
