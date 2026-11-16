function [] = reformatter(protocol_folder)
compressOutput = false; % Set to true to write gzip-compressed geometry and coil maps.
%REFORMATTER Reformat CST data for compatibility with simulation.
%   REFORMATTER() prompts for the destination protocol folder.
%   REFORMATTER(PROTOCOL_FOLDER) writes directly to an existing protocol
%   folder, allowing Setup to hand off a newly created study without asking
%   the user to select the same destination again.
matlabRoot = fileparts(mfilename('fullpath'));
repositoryRoot = fileparts(matlabRoot);
initializeSimulatorPaths;
tic

%% Select input and output location
if nargin >= 1 && ~isempty(protocol_folder)
    if ~(ischar(protocol_folder) || (isstring(protocol_folder) && isscalar(protocol_folder)))
        error('Protocol folder must be a character vector or string scalar.');
    end
    protocol_folder = char(protocol_folder);
    if exist(protocol_folder,'dir') ~= 7
        error('Protocol folder does not exist: %s',protocol_folder);
    end
end

CST_folder = uigetdir('./', 'CST Project Export Folder');
if isequal(CST_folder,0)
    disp('CST folder selection cancelled.');
    return;
end
if nargin < 1 || isempty(protocol_folder)
    protocol_folder = uigetdir(fullfile(repositoryRoot,'protocols'), 'Protocol Folder');
    if isequal(protocol_folder,0)
        disp('Protocol folder selection cancelled.');
        return;
    end
end
[material_name,material_path] = uigetfile( ...
    {'*.txt','Material Reference Files (*.txt)'}, ...
    'Select Material Reference File', matlabRoot);
if isequal(material_name,0)
    disp('Material reference file selection cancelled.');
    return;
end
material_file = fullfile(material_path,material_name);
material_reference = readMaterialReference(material_file);

%% Physical CST source and target grids
spacingData=load(fullfile(CST_folder,'B1_resolution.mat'));
bodyData=load(fullfile(CST_folder,'BodyTissue.mat'),'tissue_reformat');
files=dir(fullfile(CST_folder,'Workspace_*_import_data.mat'));
if isempty(files),error('No Workspace_*_import_data.mat file found in %s.',CST_folder);end
[~,order]=sort([files.datenum]);files=files(order);
if numel(files)>1,warning('Multiple workspace matches; loading the most recent: %s',files(end).name);end
mesh=load(fullfile(CST_folder,files(end).name),'nxyz_sub','xyzLines_sub','BodyMask_inds','NumPorts','ports');
mesh_size=double(mesh.nxyz_sub(:).');
if numel(mesh_size)~=3||any(mesh_size<2)||any(mesh_size~=fix(mesh_size))
 error('Workspace export contains invalid nxyz_sub: %s.',mat2str(mesh_size));
end
nodeLines=double(mesh.xyzLines_sub(:).');
if numel(nodeLines)~=sum(mesh_size),error('xyzLines_sub does not match nxyz_sub.');end
nodeAxes={nodeLines(1:mesh_size(1)),nodeLines(mesh_size(1)+(1:mesh_size(2))),nodeLines(sum(mesh_size(1:2))+(1:mesh_size(3)))};
for a=1:3,if any(~isfinite(nodeAxes{a}))||any(diff(nodeAxes{a})<=0),error('CST mesh axes must be finite and increasing.');end,end
% CST stores metres despite the historical B1_res_in_mm variable name.
resolution=[spacingData.B1_res_in_mm spacingData.B1_res_in_mm spacingData.slice_distance];
if any(~isfinite(resolution))||any(resolution<=0),error('Invalid B1 voxel spacing.');end
dimensions=[size(bodyData.tissue_reformat,1),size(bodyData.tissue_reformat,2),size(bodyData.tissue_reformat,3)];
if any(dimensions<1),error('BodyTissue.mat contains an empty target volume.');end
bodyIndices=double(mesh.BodyMask_inds);
cell_dimensions=mesh_size-1;
if size(bodyIndices,2)~=3||isempty(bodyIndices)||any(~isfinite(bodyIndices(:)))||any(bodyIndices(:)~=fix(bodyIndices(:)))||any(bodyIndices<1,'all')||any(bodyIndices>cell_dimensions,'all')
 error('BodyMask_inds must index cells of the CST submesh.');
end
% Reproduce the actual exporter XY query origin, including its half-step
% asymmetry. Its Z query is nominally uniform; z_reformat adds a reporting
% offset and must not be used as a spatial origin.
windowStart=min(bodyIndices,[],1)-2;windowStop=max(bodyIndices,[],1)+2;
if any(windowStart(1:2)<1)||any(windowStop(1:2)>mesh_size(1:2)),error('CST body-mask XY window exceeds the mesh.');end
xyMin=[nodeAxes{1}(windowStart(1)),nodeAxes{2}(windowStart(2))];
xyMax=[nodeAxes{1}(windowStop(1)),nodeAxes{2}(windowStop(2))];
xyOrigin=xyMin;shortAxis=1;if diff([xyMin(1),xyMax(1)])>=diff([xyMin(2),xyMax(2)]),shortAxis=2;end
xyOrigin(shortAxis)=xyMin(shortAxis)+(xyMax(shortAxis)-xyMin(shortAxis))/2-spacingData.B1_voxel_in_slice*resolution(shortAxis)/2;
targetAxes={xyOrigin(1)+(0:dimensions(1)-1)*resolution(1),xyOrigin(2)+(0:dimensions(2)-1)*resolution(2),nodeAxes{3}(1)+(0:dimensions(3)-1)*resolution(3)};
ports=double(mesh.ports(:).');num_ch=double(mesh.NumPorts);
if numel(ports)~=num_ch||any(ports<1)||any(ports~=fix(ports))||numel(unique(ports))~=num_ch,error('Invalid ordered CST ports.');end
hFiles=fieldComponentFiles(CST_folder,'h',ports,2);eFiles=fieldComponentFiles(CST_folder,'e',ports,3);

%% Preserve CST material matching, then sample categorical physical cells
kappaData=load(fullfile(CST_folder,'kappa.mat'));epsData=load(fullfile(CST_folder,'eps.mat'));rhoData=load(fullfile(CST_folder,'rho.mat'));
kappa=kappaData.kappa;epsilon=epsData.eps;rho=rhoData.rho;
air_ID=material_reference.airID;undefined_ID=material_reference.undefinedID;tissue_ref=material_reference.values;
voxel_count=prod(cell_dimensions);
validateMaterialArray(kappa,'kappa',voxel_count);validateMaterialArray(epsilon,'epsilon',voxel_count);validateMaterialArray(rho,'rho',voxel_count);
% GetPhysicalMatMatrix exports three component blocks; preserve the first
% block and the existing normalized closest-material rule.
kappa_values=double(kappa(1:voxel_count));epsilon_values=double(epsilon(1:voxel_count));rho_values=double(rho(1:voxel_count));
fprintf('Material reference: %s; %d materials, Air %d, Undefined %d\n',material_file,size(tissue_ref,1),air_ID,undefined_ID);
if isfinite(material_reference.filenameFrequencyMHz)&&isfinite(material_reference.frequencyMHz)&&abs(material_reference.filenameFrequencyMHz-material_reference.frequencyMHz)>1
 warning('Material filename/header frequencies differ. Verify the intended CST frequency.');
end
disp('(1/4) matching CST material cells...');
max_kappa = max(abs(tissue_ref(:,4)));
max_eps = max(abs(tissue_ref(:,2)));
max_rho = max(abs(tissue_ref(:,5)));
if max_kappa <= 0 || max_eps <= 0 || max_rho <= 0
    error(['Material reference must contain positive permittivity, conductivity, ' ...
        'and density scales for tissue matching.']);
end

tissue_ids = repmat(undefined_ID,voxel_count,1);
parfor v = 1:voxel_count
    kappa_value = kappa_values(v);
    epsilon_value = epsilon_values(v);
    rho_value = rho_values(v);

    % Classify zero mass density as Air before dielectric validity checks.
    if rho_value == 0
        tissue_ids(v) = air_ID;
    elseif ~isfinite(kappa_value) || ~isfinite(epsilon_value) || ...
            ~isfinite(rho_value) || kappa_value < 0 || ...
            epsilon_value < 0 || rho_value < 0
        tissue_ids(v) = undefined_ID;
    else
        cost = abs(tissue_ref(:,4) - kappa_value)/max_kappa + ...
            abs(tissue_ref(:,2) - epsilon_value)/max_eps + ...
            abs(tissue_ref(:,5) - rho_value)/max_rho;
        [~, closest_id] = min(cost);
        tissue_ids(v) = tissue_ref(closest_id, 1);
    end
end


geometry=sampleCstGrid(reshape(tissue_ids,cell_dimensions),nodeAxes,targetAxes,true,air_ID);
sourceBody=false(cell_dimensions);sourceBody(sub2ind(cell_dimensions,bodyIndices(:,1),bodyIndices(:,2),bodyIndices(:,3)))=true;
bodyMask=sampleCstGrid(sourceBody,nodeAxes,targetAxes,true,false);
clear kappaData epsData rhoData kappa epsilon rho kappa_values epsilon_values rho_values tissue_ids sourceBody bodyData mesh bodyIndices
% Choose ONE geometry-based crop, retain the historical one-index halo,
% and use exactly this crop and centre padding for every field component.
crop=cell(1,3);
for a=1:3,[first,last]=findIdxTissueStartStop(geometry,a,air_ID);crop{a}=first:last;end
cropStart=cellfun(@(v) v(1),crop);cropSize=cellfun(@numel,crop);
commonTranslation=floor((dimensions-cropSize)/2)-(cropStart-1);
fprintf('Target origin (m): %s; common index translation: %s\n',mat2str([targetAxes{1}(1),targetAxes{2}(1),targetAxes{3}(1)],12),mat2str(commonTranslation));
geometry=padTo(geometry(crop{:}),dimensions,air_ID);
num_rows=prod(dimensions);isocenter=round((1+dimensions)/2);
header=[num_rows,1,dimensions(1),1,dimensions(2),1,dimensions(3),isocenter,resolution*1000];
disp('(2/4) writing common-grid geometry.smpl...');
writeReformatterBinaryData(fullfile(protocol_folder,'geometry.smpl'),header,geometry,compressOutput);
clear geometry

%% Rebuild B1 on the same physical points, preserving algebra and amplitudes
for ch=1:num_ch
 hx=double(sampleCstGrid(readCstComponent(hFiles{ch,1},mesh_size),nodeAxes,targetAxes,false,0));
 hy=double(sampleCstGrid(readCstComponent(hFiles{ch,2},mesh_size),nodeAxes,targetAxes,false,0));
 b1p=2*pi*1e-7*(hx+1i*hy);b1m=2*pi*1e-7*conj(hx-1i*hy);
 fprintf('Undefined B1 samples before replacement: plus %d, minus %d\n',nnz(isnan(b1p)),nnz(isnan(b1m)));
 b1p(~bodyMask|isnan(b1p))=0;b1m(~bodyMask|isnan(b1m))=0;
 fprintf('(3/4) writing B1 channel %d (CST port %d)...\n',ch,ports(ch));
 writeReformatterBinaryData(fullfile(protocol_folder,sprintf('B1p_%d.bfld',ch)),num_rows,padTo(b1p(crop{:}),dimensions,0),compressOutput);
 writeReformatterBinaryData(fullfile(protocol_folder,sprintf('B1m_%d.bfld',ch)),num_rows,padTo(b1m(crop{:}),dimensions,0),compressOutput);
 clear hx hy b1p b1m
end
clear bodyMask

%% Receive E fields retain all represented geometry, not the B1 body mask
for ch=1:num_ch
 E_field=zeros([dimensions 6]);
 for component=1:3
  field=sampleCstGrid(readCstComponent(eFiles{ch,component},mesh_size),nodeAxes,targetAxes,false,0);
  E_field(:,:,:,2*component-1)=padTo(double(real(field(crop{:}))),dimensions,0);
  E_field(:,:,:,2*component)=padTo(double(imag(field(crop{:}))),dimensions,0);
 end
 fprintf('(4/4) writing E channel %d (CST port %d)...\n',ch,ports(ch));
 writeReformatterBinaryData(fullfile(protocol_folder,sprintf('E_%d.efld',ch)),num_rows,E_field,compressOutput);
 clear E_field field
end
fprintf('CST common-grid conversion complete. Took %.6f s\n',toc);
end

function paths=fieldComponentFiles(folder,kind,ports,numComponents)
files=dir(fullfile(folder,[kind 'field_*.mat']));paths=cell(numel(ports),numComponents);axes='xyz';
for j=1:numel(files)
 token=regexpi(files(j).name,['^' kind 'field_([xyz]).*?TxCh\s*(\d+)'],'tokens','once');
 if isempty(token),continue;end
 ch=find(ports==str2double(token{2}));component=find(axes==lower(token{1}));
 if isempty(ch)||component>numComponents,continue;end
 if ~isempty(paths{ch,component}),error('Duplicate %s-field component for CST port %d.',kind,ports(ch));end
 paths{ch,component}=fullfile(folder,files(j).name);
end
for ch=1:numel(ports),for a=1:numComponents
 if isempty(paths{ch,a}),error('CST export requires %sfield_%c for TxCh%d; export the raw H and E components before reformatting.',kind,axes(a),ports(ch));end
end,end
end

function data=readCstComponent(file,dimensions)
loaded=load(file);names=fieldnames(loaded);
if numel(names)~=1||~isnumeric(loaded.(names{1}))||numel(loaded.(names{1}))~=prod(dimensions)
 error('CST field sample count/type does not match nxyz_sub for %s.',file);
end
data=reshape(loaded.(names{1}),dimensions);
end

function materialReference = readMaterialReference(filePath)
    fid = fopen(filePath,'r');
    if fid == -1
        error('Could not open material reference file %s.',filePath);
    end
    fileCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    names = {};
    values = zeros(0,5);
    frequencyMHz = NaN;
    lineNumber = 0;
    while true
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end
        lineNumber = lineNumber + 1;
        trimmedLine = strtrim(line);
        if isempty(trimmedLine)
            continue;
        end

        frequencyToken = regexpi(trimmedLine, ...
            'Frequency:\s*([0-9]+(?:\.[0-9]+)?)\s*MHz','tokens','once');
        if ~isempty(frequencyToken)
            parsedFrequency = str2double(frequencyToken{1});
            if isfinite(parsedFrequency)
                frequencyMHz = parsedFrequency;
            end
        end

        if startsWith(trimmedLine,'//') || startsWith(trimmedLine,'###')
            continue;
        end

        fields = regexp(trimmedLine,'\t+','split');
        fields = fields(~cellfun(@isempty,fields));
        if numel(fields) < 6
            error(['Malformed material row at %s line %d. Expected tab-separated ' ...
                'name, ID, permittivity, permeability, conductivity, and density.'], ...
                filePath,lineNumber);
        end
        numericValues = cellfun(@str2double,fields(2:6));
        if any(~isfinite(numericValues))
            error('Invalid numeric material value at %s line %d.',filePath,lineNumber);
        end
        names{end+1,1} = strtrim(fields{1}); %#ok<AGROW>
        values(end+1,:) = numericValues; %#ok<AGROW>
    end

    if isempty(values)
        error('Material reference file %s contains no material rows.',filePath);
    end

    ids = values(:,1);
    if any(ids ~= round(ids)) || any(ids < 0) || any(ids > 255)
        error('Material IDs in %s must be unique integers from 0 through 255.',filePath);
    end
    if numel(unique(ids)) ~= numel(ids)
        error('Material reference file %s contains duplicate tissue IDs.',filePath);
    end

    airRows = find(strcmpi(names,'Air'));
    undefinedRows = find(strcmpi(names,'Undefined'));
    if numel(airRows) ~= 1 || values(airRows,1) ~= 53
        error('Material reference file %s must define Air exactly once with ID 53.',filePath);
    end
    if numel(undefinedRows) ~= 1 || values(undefinedRows,1) ~= 255
        error('Material reference file %s must define Undefined exactly once with ID 255.',filePath);
    end

    [~,baseName] = fileparts(filePath);
    filenameFrequencyToken = regexpi(baseName, ...
        '([0-9]+(?:\.[0-9]+)?)\s*MHz','tokens','once');
    filenameFrequencyMHz = NaN;
    if ~isempty(filenameFrequencyToken)
        filenameFrequencyMHz = str2double(filenameFrequencyToken{1});
    end

    materialReference = struct( ...
        'names',{names}, ...
        'values',values, ...
        'airID',values(airRows,1), ...
        'undefinedID',values(undefinedRows,1), ...
        'frequencyMHz',frequencyMHz, ...
        'filenameFrequencyMHz',filenameFrequencyMHz);
end

function validateMaterialArray(values,arrayName,voxelCount)
    valueCount = numel(values);
    if valueCount ~= voxelCount && valueCount ~= 3*voxelCount
        error(['%s.mat contains %d values, but the CST mesh requires either %d ' ...
            'scalar cell values or %d x/y/z component values.'], ...
            arrayName,valueCount,voxelCount,3*voxelCount);
    end
end

function writeReformatterBinaryData(outputFile, header, data, compressOutput)
    % Write the active CST output without a text intermediate. The header and
    % record order match the historical little-endian float32 files.
    [outputDir,baseName,extension] = fileparts(outputFile);
    if compressOutput && isfile(outputFile)
        error('Move the existing raw file before writing gzip output: %s',outputFile);
    end
    recordCount = header(1);
    if ~isnumeric(header) || any(~isfinite(header(:))) || ...
            recordCount < 1 || recordCount ~= floor(recordCount)
        error('Invalid binary header for %s.', outputFile);
    end
    switch lower(extension)
        case '.smpl'
            if numel(header) ~= 13 || numel(data) ~= recordCount
                error('Geometry header or record count mismatch for %s.', outputFile);
            end
            dimensions = [size(data,1), size(data,2), size(data,3)];
            % The former geometry.txt header printed spacing with nine
            % significant digits before conversion to float32.
            header(11:13) = round(header(11:13), 9, 'significant');
            recordWidth = 4;
        case '.bfld'
            if numel(header) ~= 1 || numel(data) ~= recordCount
                error('B1 header or record count mismatch for %s.', outputFile);
            end
            recordWidth = 2;
        case '.efld'
            if numel(header) ~= 1 || size(data,4) ~= 6 || ...
                    numel(data) ~= 6*recordCount
                error('E-field header or record count mismatch for %s.', outputFile);
            end
            fieldRows = reshape(data, [], 6);
            recordWidth = 6;
        otherwise
            error('Unsupported reformatter output type: %s.', extension);
    end

    temporaryFile = [tempname(outputDir), '.tmp'];
    outputID = fopen(temporaryFile, 'w', 'ieee-le');
    if outputID == -1
        error('Could not create binary file in %s.', outputDir);
    end
    outputCleanup = onCleanup(@() fclose(outputID));

    try
        if fwrite(outputID, header, 'single') ~= numel(header)
            error('Could not write binary header for %s.', outputFile);
        end
        chunkRecords = 250000;
        for first = 1:chunkRecords:recordCount
            last = min(first + chunkRecords - 1, recordCount);
            switch lower(extension)
                case '.smpl'
                    index = (first:last).';
                    plane = floor((index - 1) / dimensions(1));
                    x = mod(index - 1, dimensions(1)) + header(2);
                    y = mod(plane, dimensions(2)) + header(4);
                    z = floor(plane / dimensions(2)) + header(6);
                    rows = [x.'; y.'; z.'; reshape(data(index), 1, [])];
                case '.bfld'
                    values = data(first:last);
                    rows = [real(values(:)).'; imag(values(:)).'];
                    % Legacy text rows used %.6e (seven significant digits).
                    rows = round(rows, 7, 'significant');
                case '.efld'
                    rows = round(fieldRows(first:last,:).', 7, 'significant');
            end
            if any(~isfinite(rows(:))) || any(~isfinite(single(rows(:))))
                error('Non-finite or out-of-range binary data for %s.', outputFile);
            end
            if fwrite(outputID, rows, 'single') ~= recordWidth * (last-first+1)
                error('Could not write binary records for %s.', outputFile);
            end
        end
        clear outputCleanup; % Close before renaming on Windows.
        if compressOutput
            compressionDir = tempname(outputDir);
            [created,message] = mkdir(compressionDir);
            if ~created, error('Unable to create compression folder: %s',message); end
            compressionCleanup = onCleanup(@() rmdir(compressionDir,'s')); %#ok<NASGU>
            stagedRaw = fullfile(compressionDir,[baseName,extension]);
            [moved,message] = movefile(temporaryFile,stagedRaw);
            if ~moved, error('Unable to stage %s: %s',outputFile,message); end
            compressed = gzip(stagedRaw,compressionDir);
            temporaryFile = compressed{1};
            outputFile = [outputFile,'.gz'];
        end
        [moved, message] = movefile(temporaryFile, outputFile, 'f');
        if ~moved
            error('Could not finish %s: %s', outputFile, message);
        end
    catch problem
        clear outputCleanup;
        if exist(temporaryFile, 'file') == 2
            delete(temporaryFile);
        end
        rethrow(problem);
    end
end
