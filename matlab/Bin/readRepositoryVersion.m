function version = readRepositoryVersion(versionFile)
%READREPOSITORYVERSION Read the shared YYYY.X calendar-version identifier.
%   Accept one identifier with an optional LF or CRLF line ending. Reject
%   prefixes, suffixes, whitespace, additional lines, and leading zeros in X.
raw = fileread(versionFile);
pattern = '^([1-9][0-9]{3}[.](0|[1-9][0-9]*))(\r?\n)?$';
[~,last] = regexp(raw,pattern,'once');
if isempty(last) || last ~= numel(raw)
    error('BlochSimulator:InvalidVersion', ...
        'VERSION must contain exactly YYYY.X (for example 2026.0), without a v prefix, suffix, whitespace, or leading zeros in X.');
end
parts = regexp(raw,pattern,'tokens','once');
version = parts{1};
end
