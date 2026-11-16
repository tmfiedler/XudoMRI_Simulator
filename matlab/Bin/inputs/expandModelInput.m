function [rawPath, cleanup] = expandModelInput(source)
% Return a seekable local copy and a handle that owns its temporary folder.
    rawPath = source;
    cleanup = [];
    if ~endsWith(source,'.gz','IgnoreCase',true)
        if isfile(source) || ~isfile([source,'.gz'])
            return;
        end
        source = [source,'.gz'];
    end

    folder = tempname;
    [created,message] = mkdir(folder);
    if ~created
        error('Unable to create temporary folder for %s: %s',source,message);
    end
    cleanup = onCleanup(@() rmdir(folder,'s'));
    try
        files = gunzip(source,folder);
        if numel(files) ~= 1 || ~isfile(files{1})
            error('Expected a single expanded file.');
        end
        rawPath = files{1};
    catch inputError
        error('Unable to expand gzip input %s: %s',source,inputError.message);
    end
end
