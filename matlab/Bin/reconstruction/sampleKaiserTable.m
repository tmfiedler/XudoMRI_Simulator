function weights = sampleKaiserTable(distance,kernelTable)
%SAMPLEKAISERTABLE Interpolate the kernel table within its closed support.
    distance = abs(distance);
    weights = zeros(size(distance));
    mask = distance <= kernelTable.halfWidth;
    if any(mask(:))
        tableValues = kernelTable.value(:);
        samplePos = distance(mask) / kernelTable.halfWidth * (numel(kernelTable.value) - 1) + 1;
        lowerIdx = floor(samplePos);
        upperIdx = min(lowerIdx + 1,numel(kernelTable.value));
        frac = samplePos - lowerIdx;
        weights(mask) = tableValues(lowerIdx) .* (1 - frac) + tableValues(upperIdx) .* frac;
    end
end
