function [definition,defaultNucleus] = getNucleusDefinition(name)
%GETNUCLEUSDEFINITION Resolve an exact ID from config/nuclei.yaml.
% No argument returns definitions in GUI order. A changed file is read on the
% next call; reopening Setup refreshes its nucleus menu. No aliases/fallbacks.
% The second output is the configured default for omitted inputs.
persistent cachedText definitions cachedDefault
matlabRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
fileName = fullfile(fileparts(matlabRoot),'config','nuclei.yaml');
text = fileread(fileName);
if isempty(definitions) || ~strcmp(text,cachedText)
    config = readNucleusConfig(fileName);
    definitions = config.nuclei;
    cachedDefault = config.defaultNucleus;
    cachedText = text;
end
defaultNucleus = cachedDefault;
if nargin == 0
    definition = definitions;
    return;
end
index = find(strcmp(char(name),{definitions.name}),1);
if isempty(index)
    error('getNucleusDefinition:UnsupportedNucleus', ...
        'Unsupported nucleus "%s"; supported IDs are %s.',char(name),strjoin({definitions.name},', '));
end
definition = definitions(index);
end
