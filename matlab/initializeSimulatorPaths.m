function initializeSimulatorPaths(preserveBinPrecedence)
%INITIALIZESIMULATORPATHS Add the current simulator source folders for this session.
% Does not change the current folder or save the MATLAB path.
% Setup passes true to retain its existing appended Bin search precedence.
if nargin == 0, preserveBinPrecedence = false; end
matlabRoot = fileparts(mfilename('fullpath'));
binRoot = fullfile(matlabRoot,'Bin');
binFolders = {binRoot, fullfile(binRoot,'jobs'), fullfile(binRoot,'gui'), ...
    fullfile(binRoot,'inputs'), fullfile(binRoot,'nucleus'), fullfile(binRoot,'reconstruction')};
if preserveBinPrecedence
    path(path,strjoin(binFolders,pathsep));
else
    addpath(binFolders{:});
end
addpath(matlabRoot,fullfile(matlabRoot,'Sequences'), ...
    fullfile(matlabRoot,'Bin','sequence'));
end
