function profiles = readScannerProfiles()
%READSCANNERPROFILES Load the named gradient limits used by Setup.
matlabRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if ~any(contains(javaclasspath('-dynamic'),'snakeyaml-2.3.jar'))
    javaaddpath(fullfile(matlabRoot,'third_party','snakeyaml','snakeyaml-2.3.jar'));
end
options = javaObject('org.yaml.snakeyaml.LoaderOptions');
options.setAllowDuplicateKeys(false);
constructor = javaObject('org.yaml.snakeyaml.constructor.SafeConstructor',options);
parser = javaObject('org.yaml.snakeyaml.Yaml',constructor);
entries = parser.load(fileread(fullfile(fileparts(matlabRoot),'config','scanner.yaml')));
assert(isa(entries,'java.util.Map'),'scanner.yaml must map profile names to gradient limits.');
profiles = struct('name',{},'limits',{});
iterator = entries.entrySet().iterator();
keys = {'max_gradient_mT_per_m','max_slew_T_per_m_per_s','gradient_raster_us'};
while iterator.hasNext()
    entry = iterator.next();
    name = entry.getKey();
    limits = entry.getValue();
    assert(ischar(name) && ~isempty(name) && strcmp(name,strtrim(name)) && ...
        ~strcmpi(name,'None') && isempty(regexp(name,'[\r\n:|]','once')), ...
        'Invalid scanner profile name.');
    assert(isa(limits,'java.util.Map') && limits.size() == numel(keys), ...
        'Scanner profile %s must specify all three gradient limits.',name);
    values = zeros(1,numel(keys));
    for k = 1:numel(keys)
        value = limits.get(keys{k});
        validateattributes(value,{'numeric'},{'scalar','real','finite','positive'}, ...
            mfilename,keys{k});
        values(k) = value;
    end
    profiles(end+1) = struct('name',name,'limits',values); %#ok<AGROW>
end
end
