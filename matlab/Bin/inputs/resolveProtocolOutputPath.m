function [pathName,fileName] = resolveProtocolOutputPath(str, protocolDir)
    [~,fileName] = addrCvrt(str);
    if isempty(fileName)
        pathName = '';
        return;
    end

    pathName = protocolDir;
end
