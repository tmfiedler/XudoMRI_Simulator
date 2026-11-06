function tissue = readTissuePropertyFile(fileName, expectedNucleus)
%READTISSUEPROPERTYFILE Read V1 tissue concentration and model-specific times.
% Concentration_mol_per_L counts isotope nuclei per litre of sample volume.
% Relaxation model and pool fractions come from config/nuclei.yaml.
if nargin < 2, expectedNucleus = ''; end
lines = regexp(fileread(fileName),'\r\n|\n|\r','split');
metadata = regexp(strtrim(stripBom(lines{1})), ...
    '^TISSUE_PROPERTIES_V1\s+Nucleus=(\S+)\s*$','tokens','once');
must(~isempty(metadata),'InvalidMetadata', ...
    'Expected TISSUE_PROPERTIES_V1 Nucleus=<id> and concentration in mol/L.');
definition = getNucleusDefinition(metadata{1});
nucleus = definition.name;
must(isempty(expectedNucleus) || strcmp(nucleus,char(expectedNucleus)), ...
    'NucleusMismatch','Tissue nucleus does not match the selected nucleus.');
must(numel(lines) >= 2,'MissingHeader','V1 metadata must be followed by a header row.');
header = splitFields(lines{2});
names = lower(string(header));
must(numel(unique(names)) == numel(names),'DuplicateHeader','Duplicate tissue column name.');
twoPools = strcmp(definition.relaxationModel,'independent_two_pool_bloch');
required = {'ID','T1_ms','Concentration_mol_per_L','chemical_shift_ppm', ...
    'conductivity_S_per_m','mass_density_kg_per_m3','tissue_name'};
if twoPools
    required = [required {'T2s_ms','T2l_ms'}];
    must(~any(names == "t2_ms"),'RelaxationColumns','Two-pool model requires T2s_ms and T2l_ms.');
else
    required = [required {'T2_ms'}];
    must(~any(ismember(names,["t2s_ms","t2l_ms"])), ...
        'RelaxationColumns','Single-pool model requires T2_ms.');
end
must(all(ismember(lower(string(required)),names)), ...
    'MissingColumn','Required concentration, relaxation or tissue-property column is missing.');
columns = cellfun(@(name) find(strcmpi(name,header),1),required);
data = [];
tissueNames = {};
for lineNumber = 3:numel(lines)
    row = splitFields(lines{lineNumber});
    if isempty(row), continue; end
    must(numel(row) == numel(header),'FieldCount', ...
        sprintf('Row %d field count differs from header; tissue names cannot contain spaces.',lineNumber));
    values = zeros(1,numel(required)-1);
    must(~isempty(regexp(row{columns(1)},'^[+-]?[0-9]+$','once')), ...
        'InvalidID','ID must be a signed 32-bit integer.');
    numericColumns = columns([1:6 8:end]);
    numericNames = required([1:6 8:end]);
    for index = 1:numel(numericColumns)
        text = row{numericColumns(index)};
        % Decimal finite values only, shared with the native reader.
        must(~isempty(regexp(text,'^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$','once')), ...
            'InvalidNumber',sprintf('%s at row %d must be a finite decimal number.',numericNames{index},lineNumber));
        values(index) = str2double(text);
        must(isfinite(values(index)) && isfinite(single(values(index))) && ...
            (values(index) == 0 || single(values(index)) ~= 0), ...
            'InvalidNumber',sprintf('Nonfinite/out-of-range value at row %d.',lineNumber));
    end
    % Numeric order: ID,T1,concentration,shift,conductivity,mass density,T2(s/l).
    must(values(1) == fix(values(1)) && values(1) >= -2147483648 && values(1) <= 2147483647, ...
        'InvalidID','ID must be a signed 32-bit integer.');
    must(isempty(data) || ~any(data(:,1) == values(1)),'DuplicateID','Duplicate tissue ID.');
    must(all(values([2:3 5:end]) >= 0),'NegativeValue','Tissue properties must be nonnegative except chemical shift.');
    must(values(3) == 0 || all(values([2 7:end]) > 0), ...
        'NonpositiveRelaxation','Relaxation times must be positive when concentration is nonzero.');
    times=values([2 7:end]);
    must(all(times == 0 | single(single(times)/single(1000)) > 0), ...
        'RelaxationRange','Nonzero relaxation times must remain positive in engine seconds.');
    if twoPools
        must(values(7) <= values(8),'InvalidT2Order','T2s_ms cannot exceed T2l_ms.');
    end
    data(end+1,:) = values; %#ok<AGROW>
    tissueNames{end+1,1} = row{columns(7)}; %#ok<AGROW>
end
must(~isempty(data),'NoData','No tissue data rows.');
tissue.nucleus = nucleus;
tissue.tissueName = tissueNames;
tissue.concentrationMolPerL = data(:,3);
if twoPools
    tissue.displayLabels = {'ID','T1','T2s','T2l','Conc. (mol/L)', ...
        'Chemical Shift','Conductivity','Mass Density'};
    order = [1 2 7 8 3 4 5 6];
else
    tissue.displayLabels = {'ID','T1','T2','Conc. (mol/L)', ...
        'Chemical Shift','Conductivity','Mass Density'};
    order = [1 2 7 3 4 5 6];
end
tissue.displayValues = arrayfun(@(index) data(:,index),order,'UniformOutput',false);
end

function fields = splitFields(line)
line = strtrim(char(line));
if isempty(line), fields = {}; else, fields = regexp(line,'\s+','split'); end
end

function value = stripBom(value)
if ~isempty(value) && double(value(1)) == 65279, value(1) = []; end
end

function must(condition,id,message)
if ~condition, error(['readTissuePropertyFile:' id],'%s',message); end
end
