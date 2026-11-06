function [output] = padTo(input, target_dim, value)
%PADTO Summary of this function goes here
% equally to both ends. Preserves class(A).
if nargin < 3
    value = 53;
end
if numel(target_dim) ~= 3
    error('target_dim must be a 1x3 vector');
end

sz = size(input);
% If A has fewer than 3 dims, extend sz to 3
if numel(sz) < 3, sz(end+1:3) = 1; end

diffs = target_dim - sz;
if any(diffs < 0)
    error('targetSize must be >= size(A) in every dimension');
end

pre  = floor(diffs/2);        % amount to pad before
post = diffs - pre;          % amount to pad after

% create target array filled with fillValue (preserve class)
clazz = class(input);
output = repmat(cast(value, clazz), target_dim);

% compute index ranges where original A will be copied
r1 = (1:sz(1)) + pre(1);
c1 = (1:sz(2)) + pre(2);
p1 = (1:sz(3)) + pre(3);

output(r1, c1, p1) = input;
end
