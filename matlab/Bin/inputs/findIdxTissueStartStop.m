function [minIdx,maxIdx] = findIdxTissueStartStop(matrix, dim, value)
%FINDTISSUESTARTSTOP Find minimum and maximum coordinates of matrix with
%tissue
min_idx = 1;
max_idx = size(matrix, dim);

switch dim
case 1
    has_tissue = squeeze(any(any(matrix ~= value, 2), 3));
case 2
    has_tissue = squeeze(any(any(matrix ~= value, 1), 3));
case 3
    has_tissue = squeeze(any(any(matrix ~= value, 1), 2));
otherwise
    error('dim must be 1, 2, or 3');
end

first_tissue = find(has_tissue, 1, 'first');
if isempty(first_tissue)
    minIdx = min_idx;
    maxIdx = max_idx;
    return;
end
last_tissue = find(has_tissue, 1, 'last');

minIdx = first_tissue - 1;
if minIdx < min_idx
    minIdx = min_idx;
end

maxIdx = last_tissue + 1;
if maxIdx > max_idx
    maxIdx = max_idx;
end
