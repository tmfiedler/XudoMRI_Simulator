function hFig = reco(varargin)
%RECO Open the Cartesian and 3D radial reconstruction viewer.
%   RECO opens an empty viewer for selecting simulator output.
%   HFIG = RECO('SignalFiles',files,'DataPath',folder) loads the named
%   .ksig files on launch and returns the viewer figure.

initializeSimulatorPaths;
if nargout
    hFig = reconstructionViewer(varargin{:});
else
    reconstructionViewer(varargin{:});
end
end
