function settings = readNoiseLoadingProtocol(lines)
%READNOISELOADINGPROTOCOL Read independent noise settings from the existing .prot.
% All three labels are required; Full may leave crop bounds and note blank.
settings = struct('Mode',valueAfter('Noise Loading Domain:'),'Bounds',[],'Note','');
bounds = valueAfter('Noise Crop Bounds:');
if ~isempty(bounds)
    settings.Bounds = sscanf(bounds,'%f').';
    validateattributes(settings.Bounds,{'numeric'}, ...
        {'real','finite','vector','numel',6,'integer'},mfilename,'Noise Crop Bounds');
end
settings.Note = valueAfter('Noise Crop Note:');
if strcmp(settings.Mode,'Cropped') && isempty(settings.Note)
    settings.Note = 'Explicit crop';
end
noiseLoadingArguments(settings); % Validate the selected mode/bounds before use.

    function value = valueAfter(label)
        index = find(strcmp(lines,label));
        if ~isscalar(index) || index == numel(lines)
            error('SetupProtocol:Field', ...
                'Protocol requires one "%s" label and its value line. Recreate older protocols in Setup.',label);
        end
        value = strtrim(lines{index+1});
    end
end
