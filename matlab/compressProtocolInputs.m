function compressProtocolInputs(protocolFile)
%COMPRESSPROTOCOLINPUTS Replace a protocol's raw geometry and coil maps with gzip files.
% With no argument, select a .prot file and confirm the replacement.
% Passing a .prot path performs the replacement directly.
initializeSimulatorPaths;
interactive = nargin == 0;
if interactive
    protocolRoot = fullfile(fileparts(fileparts(mfilename('fullpath'))),'protocols');
    [name,folder] = uigetfile({'*.prot','XudoMRI protocol (*.prot)'}, ...
        'Select a protocol',fullfile(protocolRoot,'*.prot'));
    if isequal(name,0), return; end
    protocolFile = fullfile(folder,name);
end
protocolDir = fileparts(char(protocolFile));
if isempty(protocolDir), protocolDir = pwd; end
protocol = readSetupProtocol(protocolFile);
modelEntries = {protocol.geometryFilename()};
maps = {protocol.b1PlusFiles(),protocol.b1MinusFiles(), ...
    protocol.e1PlusFiles(),protocol.e1MinusFiles()};
other = {protocol.tissueFilename(),protocol.sequenceFilename(), ...
    protocol.deltaB0Filename(),protocol.gxFilename(),protocol.gyFilename(),protocol.gzFilename()};
for group = 1:numel(maps)
    entries = maps{group};
    if ischar(entries), entries = {entries}; end
    modelEntries = [modelEntries; entries(:)]; %#ok<AGROW>
end
% The CST reformatter can generate E maps before Setup assigns them to a coil.
localFields = dir(fullfile(protocolDir,'E_*.efld*'));
for idx = 1:numel(localFields)
    field = localFields(idx);
    if ~field.isdir && ~isempty(regexpi(field.name,'^E_[0-9]+\.efld(\.gz)?$','once'))
        modelEntries{end+1,1} = fullfile(field.folder,field.name); %#ok<AGROW>
    end
end
targets = resolveInputs(modelEntries,protocolDir,true);
allInputs = unique([targets; resolveInputs(other,protocolDir,false)],'stable');
before = sum(cellfun(@fileBytes,allInputs));
after = before;
fprintf('Total protocol input size before: %s\n',formatSize(before));

rawFiles = targets(~endsWith(targets,'.gz','IgnoreCase',true));
if interactive && ~isempty(rawFiles)
    confirmation = questdlg(sprintf(['Replace up to %d raw geometry and coil map files with verified gzip copies?\n' ...
        'Other protocols may reference the same files.'],numel(rawFiles)), ...
        'Compress Protocol Inputs','Compress','Cancel','Cancel');
    if ~strcmp(confirmation,'Compress'), return; end
end
for idx = 1:numel(rawFiles)
    source = rawFiles{idx};
    [~,name,extension] = fileparts(source);
    if ~any(strcmpi(extension,{'.smpl','.bfld','.efld'}))
        warning('Skipping unsupported input type: %s',source);
        continue;
    end
    fallback = fullfile(protocolDir,[name,extension]);
    if isfile(fallback)
        [ok,info] = fileattrib(fallback);
        if ~ok || (ispc && ~strcmpi(info.Name,source)) || (~ispc && ~strcmp(info.Name,source))
            warning('Keeping raw file because the protocol folder has another file with the same name: %s',source);
            continue;
        end
    end
    try
        after = after - compressInput(source);
    catch compressionError
        warning('Could not replace %s: %s',source,compressionError.message);
    end
end

fprintf('Total protocol input size after:  %s\n',formatSize(after));
fprintf('Space saved:                     %s',formatSize(before-after));
if before > 0
    fprintf(' (%.1f%%)',100*(before-after)/before);
end
fprintf('\n');
if after > 0
    fprintf('Overall compression ratio (before:after): %.2f:1\n',before/after);
else
    fprintf('Overall compression ratio: unavailable (no input bytes).\n');
end
end

function paths = resolveInputs(entries,protocolDir,allowGzip)
paths = {};
for idx = 1:numel(entries)
    entry = entries{idx};
    if isempty(entry), continue; end
    if allowGzip
        [folder,name] = resolveProtocolPath(entry,protocolDir);
        source = fullfile(folder,name);
    else
        source = entry;
        if ~isfile(source)
            [~,name,ext] = fileparts(entry);
            source = fullfile(protocolDir,[name,ext]);
        end
    end
    if ~isfile(source)
        error('Protocol input file not found: %s',entry);
    end
    [ok,info] = fileattrib(source);
    if ~ok, error('Could not resolve input: %s',source); end
    paths{end+1,1} = info.Name; %#ok<AGROW>
end
paths = unique(paths,'stable');
end

function saved = compressInput(source)
saved = 0;
destination = [source,'.gz'];
if isfile(destination)
    warning('Keeping raw file because a gzip sibling already exists: %s',source);
    return;
end
folder = fileparts(source);
stage = tempname(folder);
[created,message] = mkdir(stage);
if ~created, error('Could not create staging folder: %s',message); end
stageCleanup = onCleanup(@() rmdir(stage,'s')); %#ok<NASGU>
originalSize = fileBytes(source);
archives = gzip(source,stage);
compressedSize = fileBytes(archives{1});
if compressedSize >= originalSize
    fprintf('Kept raw file (gzip would not save space): %s\n',source);
    return;
end
[expanded,expandedCleanup] = expandModelInput(archives{1}); %#ok<NASGU>
if ~sameBytes(source,expanded)
    error('Gzip verification did not reproduce the original bytes.');
end
% Install without overwriting a sibling that appeared during compression.
stagedFile = java.io.File(archives{1});
destinationFile = java.io.File(destination);
java.nio.file.Files.copy(stagedFile.toPath(),destinationFile.toPath(), ...
    javaArray('java.nio.file.CopyOption',0));
delete(source);
if isfile(source)
    delete(destination);
    error('Could not remove the original file.');
end
saved = originalSize-compressedSize;
fprintf('Compressed %s\n',source);
end

function matched = sameBytes(first,second)
left = fopen(first,'rb');
if left < 0, error('Could not read %s',first); end
closeLeft = onCleanup(@() fclose(left)); %#ok<NASGU>
right = fopen(second,'rb');
if right < 0, error('Could not read %s',second); end
closeRight = onCleanup(@() fclose(right)); %#ok<NASGU>
chunkSize = 1024*1024;
matched = false;
while true
    a = fread(left,chunkSize,'*uint8');
    b = fread(right,chunkSize,'*uint8');
    if ~isequal(a,b), return; end
    if numel(a) < chunkSize
        matched = feof(left) && feof(right) && isempty(ferror(left)) && isempty(ferror(right));
        return;
    end
end
end

function bytes = fileBytes(filename)
info = dir(filename);
if isempty(info) || info.isdir, error('Could not measure input: %s',filename); end
bytes = info.bytes;
end

function description = formatSize(bytes)
description = sprintf('%.2f MiB (%.0f bytes)',bytes/2^20,bytes);
end
