function [pathName,fileName] = resolveProtocolPath(str, protocolDir)
    if iscell(str)
        [pathName,fileName] = addrCvrt(str);
        for idx = 1:numel(fileName)
            resolvedFile = resolveProtocolFile([pathName{idx},fileName{idx}], protocolDir);
            [pathName{idx},fileName{idx}] = addrCvrt(resolvedFile);
        end
        return;
    end

    [pathName,fileName] = addrCvrt(str);
    if isempty(fileName)
        return;
    end

    resolvedFile = resolveProtocolFile([pathName,fileName], protocolDir);
    [pathName,fileName] = addrCvrt(resolvedFile);
end

function resolvedFile = resolveProtocolFile(filePath, protocolDir)
    resolvedFile = normalizeDrivePath(strtrim(filePath));
    if ~isempty(resolvedFile) && exist(resolvedFile,'file') == 2
        return;
    end

    [~,fileBase,fileExt] = fileparts(resolvedFile);
    if ~isempty(fileBase)
        fallbackFile = normalizeDrivePath(fullfile(protocolDir,[fileBase,fileExt]));
        if exist(fallbackFile,'file') == 2
            resolvedFile = fallbackFile;
        elseif any(strcmpi(fileExt,{'.smpl','.bfld','.efld'}))
            if isfile([resolvedFile,'.gz'])
                resolvedFile = [resolvedFile,'.gz'];
            elseif isfile([fallbackFile,'.gz'])
                resolvedFile = [fallbackFile,'.gz'];
            end
        end
    end
end

function normalizedPath = normalizeDrivePath(filePath)
    normalizedPath = filePath;
    if numel(normalizedPath) >= 2 && normalizedPath(2) == ':'
        while contains(normalizedPath,'\\')
            normalizedPath = strrep(normalizedPath,'\\','\');
        end
    end
end
