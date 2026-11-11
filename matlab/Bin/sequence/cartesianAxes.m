function axesXYZ = cartesianAxes(orientation,swapInPlane)
%CARTESIANAXES Model axes for [FE PE SS] in axial, sagittal or coronal.
    axesByOrientation = [1 2 3; 3 2 1; 3 1 2];
    axesXYZ = axesByOrientation(orientation,:);
    if swapInPlane
        axesXYZ = axesXYZ([2 1 3]);
    end
end
