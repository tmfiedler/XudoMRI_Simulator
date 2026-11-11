function [center,width] = fovBox(info,displayInfo,orientation)
%FOVBOX Return the prescribed center and full width in model voxel units.
    center = [info.ctrX + info.setX, info.ctrY + info.setY, info.ctrZ + info.setZ];
    spacing = [info.widX, info.widY, info.widZ];
    fov = info.FOV([1 min(2,numel(info.FOV))]);
    if usesRadial3DWorkflow(displayInfo.ActiveSequenceName)
        width = max(fov) ./ spacing;
        return;
    end
    axesXYZ = cartesianAxes(orientation,displayInfo.SwapInPlane);
    width(axesXYZ) = [fov(:).', info.sliceTH];
    width = width ./ spacing;
    if ~displayInfo.SliceSelect
        sliceAxis = axesXYZ(3);
        low = [displayInfo.minX, displayInfo.minY, displayInfo.minZ];
        high = [displayInfo.maxX, displayInfo.maxY, displayInfo.maxZ];
        center(sliceAxis) = (low(sliceAxis) + high(sliceAxis))/2;
        width(sliceAxis) = high(sliceAxis) - low(sliceAxis) + 1;
    end
end
