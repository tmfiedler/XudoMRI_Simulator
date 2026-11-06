function boundsArguments = noiseLoadingArguments(settings)
%NOISELOADINGARGUMENTS Bounds for the independent receive-noise domain.
% Full uses the native geometry header extent. Bounds are original voxel indices,
% ordered [xmin ymin zmin xmax ymax zmax], not millimetres or the signal origin.
switch settings.Mode
    case 'Full'
        boundsArguments = '';
    case 'Cropped'
        validateattributes(settings.Bounds,{'numeric'}, ...
            {'real','finite','vector','numel',6,'integer'},mfilename,'Bounds');
        bounds = reshape(settings.Bounds,1,6);
        if any(bounds(1:3) > bounds(4:6))
            error('NoiseLoading:Bounds','Noise minimum bounds must not exceed maximum bounds.');
        end
        boundsArguments = sprintf([' "xMin=%d" "yMin=%d" "zMin=%d"' ...
            ' "xMax=%d" "yMax=%d" "zMax=%d"'],bounds);
    otherwise
        error('NoiseLoading:Mode','Noise loading must be Full or Cropped.');
end
end
