function fovMeters = radialFOVMeters(protocolFOV)
%RADIALFOVMETERS Convert the RAD_3D protocol FOV in mm to three axes in m.
    if ~isnumeric(protocolFOV) || ~isvector(protocolFOV) || ...
            ~ismember(numel(protocolFOV),[1 2]) || ...
            any(~isfinite(protocolFOV(:))) || any(protocolFOV(:) <= 0)
        error('RAD_3D:InvalidFOV', ...
            'RAD_3D FOV must contain one or two finite positive millimetre values.');
    end
    % Match the isotropic RAD_3D generator's existing two-entry FOV contract.
    fovMeters = repmat(max([protocolFOV(:).' 1]) / 1000,1,3);
end
