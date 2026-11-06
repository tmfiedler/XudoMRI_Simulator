function config = readNucleusConfig(fileName)
%READNUCLEUSCONFIG Read the shared YAML registry with explicit schema checks.
% Uses SnakeYAML's node parser, not object construction or implicit numeric
% conversion. MATLAB and C++ therefore apply the same decimal field syntax.
if nargin == 0
    matlabRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    fileName = fullfile(fileparts(matlabRoot),'config','nuclei.yaml');
end
try
    ensureParser();
    options = javaObject('org.yaml.snakeyaml.LoaderOptions');
    constructor = javaObject('org.yaml.snakeyaml.constructor.SafeConstructor',options);
    parser = javaObject('org.yaml.snakeyaml.Yaml',constructor);
    documents = parser.composeAll(javaObject('java.io.StringReader',fileread(fileName)));
    iterator = documents.iterator();
    must(iterator.hasNext(),'Expected one YAML document.');
    root = mapping(iterator.next(),{'sample_temperature_K','default_nucleus','nuclei'}, ...
        {'sample_temperature_K','default_nucleus','nuclei'},'configuration');
    must(~iterator.hasNext(),'Expected one YAML document.');
    config.sampleTemperatureK = number(root.sample_temperature_K,'sample_temperature_K');
    must(config.sampleTemperatureK > 0,'sample_temperature_K must be positive.');
    config.defaultNucleus = scalar(root.default_nucleus,'default_nucleus');
    must(isa(root.nuclei,'org.yaml.snakeyaml.nodes.SequenceNode'),'nuclei must be a list.');
    nodes = root.nuclei.getValue();
    must(nodes.size() > 0,'nuclei must be a nonempty list.');
    definitions = struct('name',{},'gammaHzPerT',{},'gammaRadPerTPerS',{}, ...
        'spin',{},'relaxationModel',{},'shortT2Weight',{},'longT2Weight',{});
    for index = 1:nodes.size()
        entry = mapping(nodes.get(index-1),{'id','gamma_Hz_per_T','spin','relaxation'}, ...
            {'id','gamma_Hz_per_T','spin','relaxation'},'nucleus');
        d.name = scalar(entry.id,'id');
        must(~isempty(regexp(d.name,'^[A-Za-z0-9][A-Za-z0-9_-]*$','once')), ...
            'id must contain only letters, digits, underscore or hyphen.');
        must(isempty(definitions) || ~any(strcmp(d.name,{definitions.name})), ...
            ['Duplicate nucleus id ' d.name '.']);
        d.gammaHzPerT = number(entry.gamma_Hz_per_T,[d.name '.gamma_Hz_per_T']);
        must(single(d.gammaHzPerT) > 0 && isfinite(single(d.gammaHzPerT*2*pi)), ...
            'Only positive finite float-representable gamma is supported.');
        d.gammaRadPerTPerS = d.gammaHzPerT * 2 * pi;
        d.spin = number(entry.spin,[d.name '.spin']);
        must(d.spin > 0 && isfinite(2*d.spin) && 2*d.spin == fix(2*d.spin), ...
            'Spin must be a positive integer or half-integer.');
        relaxation = mapping(entry.relaxation,{'model','short_pool_fraction'}, ...
            {'model'},[d.name '.relaxation']);
        d.relaxationModel = scalar(relaxation.model,[d.name '.relaxation.model']);
        if strcmp(d.relaxationModel,'single_pool_bloch')
            must(~isfield(relaxation,'short_pool_fraction'),'Single pool has no pool fraction.');
            d.shortT2Weight = 1;
            d.longT2Weight = 0;
        else
            must(strcmp(d.relaxationModel,'independent_two_pool_bloch'), ...
                ['Unsupported relaxation model ' d.relaxationModel '.']);
            must(isfield(relaxation,'short_pool_fraction'),'Missing short_pool_fraction.');
            fraction = number(relaxation.short_pool_fraction,[d.name '.short_pool_fraction']);
            must(fraction > 0 && fraction < 1,'short_pool_fraction must be between zero and one.');
            d.shortT2Weight = fraction;
            d.longT2Weight = 1 - fraction;
            must(single(d.shortT2Weight) > 0 && single(d.longT2Weight) > 0, ...
                'Both pool fractions must remain positive in engine precision.');
        end
        definitions(index) = d; %#ok<AGROW>
    end
    config.nuclei = definitions;
    must(any(strcmp(config.defaultNucleus,{definitions.name})), ...
        'default_nucleus must name an existing exact nucleus ID.');
catch exception
    wrapped = MException('readNucleusConfig:InvalidConfig', ...
        'Nucleus configuration %s: %s',fileName,exception.message);
    throw(addCause(wrapped,exception));
end
end

function ensureParser()
persistent loaded
if isempty(loaded)
    matlabRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    parserJar = fullfile(matlabRoot,'third_party','snakeyaml','snakeyaml-2.3.jar');
    javaaddpath(parserJar);
    loaded = true;
end
end

function result = mapping(node,allowed,required,context)
must(isa(node,'org.yaml.snakeyaml.nodes.MappingNode'),[context ' must be a mapping.']);
tuples = node.getValue();
result = struct();
for index = 1:tuples.size()
    tuple = tuples.get(index-1);
    key = scalar(tuple.getKeyNode(),[context ' key']);
    must(any(strcmp(key,allowed)),[context ': unknown field ' key '.']);
    must(~isfield(result,key),[context ': duplicate field ' key '.']);
    result.(key) = tuple.getValueNode();
end
must(all(isfield(result,required)),[context ': missing required field.']);
end

function value = scalar(node,context)
must(isa(node,'org.yaml.snakeyaml.nodes.ScalarNode'),[context ' must be a scalar.']);
value = char(node.getValue());
end

function value = number(node,context)
text = scalar(node,context);
must(~isempty(regexp(text,'^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$','once')), ...
    [context ' must be a finite decimal number.']);
value = str2double(text);
must(isfinite(value),[context ' must be finite.']);
end

function must(condition,message)
if ~condition, error('readNucleusConfig:Schema','%s',message); end
end
