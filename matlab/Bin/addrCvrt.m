function [pathName,fileName] = addrCvrt(str)
    if iscell(str) ~= 1
        [pathName,fileName] = splitPath(str);
    else
        fileName = cell(size(str));
        pathName = cell(size(str));
        for m = 1:numel(str)
            [pathName{m},fileName{m}] = splitPath(str{m});
        end
    end
end

function [pathName,fileName] = splitPath(str)
    if isstring(str)
        str = char(str);
    end

    if isempty(str)
        pathName = '';
        fileName = '';
        return;
    end

    n = find(str=='\' | str=='/',1,'last');

    if isempty(n)
        pathName = '';
        fileName = str;
        return;
    end

    pathName = str(1:n);
    fileName = str(n+1:length(str));
end
