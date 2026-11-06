function output = flipdim(inputArray, dim)
%FLIPDIM Compatibility shim for legacy MATLAB code.
%   Modern MATLAB uses FLIP; this wrapper keeps legacy GUIDE-era code working.

if nargin < 2 || isempty(dim)
    dim = find(size(inputArray) ~= 1, 1);
    if isempty(dim)
        dim = 1;
    end
end

output = flip(inputArray, dim);
end
