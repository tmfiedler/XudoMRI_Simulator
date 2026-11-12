function resolutionMm = parseRadialResolutionMm(text)
%PARSERADIALRESOLUTIONMM Read a positive millimetre value or a blank field.
    if ischar(text)
        text = strtrim(text);
        if isempty(text)
            resolutionMm = [];
            return;
        end
        resolutionMm = str2double(text);
        if isreal(resolutionMm) && isfinite(resolutionMm) && resolutionMm > 0
            return;
        end
    end
    error('RAD_3D:InvalidResolution','Nominal acquisition resolution must be a positive number in mm, or blank.');
end
