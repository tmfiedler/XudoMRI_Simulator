function transitionMs = parseRadialTransitionMs(text)
%PARSERADIALTRANSITIONMS Read the optional DA-3DPR transition time in ms.
    if isempty(strtrim(text))
        transitionMs = [];
        return;
    end
    transitionMs = str2double(text);
    if contains(text,',') || ~isreal(transitionMs) || ~isfinite(transitionMs) || transitionMs < 0
        error('DA_3DPR:InvalidTransition','t0 must be a nonnegative number in ms, or blank for automatic timing.');
    end
end
