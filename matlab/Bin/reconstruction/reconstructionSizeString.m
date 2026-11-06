function dims = reconstructionSizeString(value)
%RECONSTRUCTIONSIZESTRING Format array dimensions for reconstruction logs.
    dimsVector = size(value);
    dimsParts = arrayfun(@num2str,dimsVector,'UniformOutput',false);
    dims = ['[',strjoin(dimsParts,' x '),']'];
end
