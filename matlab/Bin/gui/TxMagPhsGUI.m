function [TxMagMat, TxPhsMat,TxRefB1,index] = TxMagPhsGUI(Tx,Mag,Phs,FA,RefB1)

    if nargin < 5 || isempty(RefB1)
        RefB1 = NaN;
    end

    confirmed = false;
    hGap = 2;
    dialogW = 320;
    buttonY = 15;
    refY = buttonY + 30;
    headerY = refY + 30 * (Tx + 1);
    dialogH = headerY + 35;
    magHandles = gobjects(Tx,1);
    phsHandles = gobjects(Tx,1);
    faHandles = gobjects(Tx,1);

    hTxMagPhsDlg = figure('Visible','on','MenuBar','none','Name','Tx Array',...
        'NumberTitle','off','Position',[100,30,dialogW,dialogH],'Resize','off',...
        'Toolbar','none','Color',[1,1,1],'WindowStyle','modal',...
        'CloseRequestFcn',@cancelSelection);
    movegui(hTxMagPhsDlg,'center');

    headerX = 65;
    uicontrol(hTxMagPhsDlg,'Style','text','String','Mag',...
        'Position',[headerX headerY 30 13],'BackgroundColor',[1,1,1]);
    uicontrol(hTxMagPhsDlg,'Style','text','String','Phs',...
        'Position',[headerX+30+hGap headerY 30 13],'BackgroundColor',[1,1,1]);
    uicontrol(hTxMagPhsDlg,'Style','text','String','RF FA',...
        'Position',[headerX+60+2*hGap headerY 30 13],'BackgroundColor',[1,1,1]);

    rowX = 10;
    for n = 1:Tx
        rowY = headerY - n * 30;
        uicontrol(hTxMagPhsDlg,'Style','text','String',['Coil',num2str(n)],...
            'Position',[rowX rowY 50 16],'BackgroundColor',[1,1,1]);

        magHandles(n) = uicontrol(hTxMagPhsDlg,'Style','edit',...
            'Position',[rowX+50+3*hGap rowY 30 19],...
            'String',num2str(Mag(n)),'BackgroundColor',[1,1,1],...
            'Callback',@(source,eventdata) updateMagnitude(n)); %#ok<INUSD>

        phsHandles(n) = uicontrol(hTxMagPhsDlg,'Style','edit',...
            'Position',[rowX+50+30+4*hGap rowY 30 19],...
            'String',num2str(Phs(n)),'BackgroundColor',[1,1,1],...
            'Callback',@(source,eventdata) updatePhase(n)); %#ok<INUSD>

        faHandles(n) = uicontrol(hTxMagPhsDlg,'Style','edit',...
            'Position',[rowX+50+60+5*hGap rowY 30 19],...
            'String',num2str(rem(Mag(n)*FA,360)),'Enable','inactive');
    end

    uicontrol(hTxMagPhsDlg,'Style','text','String','Shim B1+ (uT)',...
        'Position',[10 refY 85 16],'BackgroundColor',[1,1,1],...
        'HorizontalAlignment','left');
    refB1Handle = uicontrol(hTxMagPhsDlg,'Style','edit',...
        'Position',[100 refY 60 19],...
        'String',formatOptionalScalar(RefB1),'BackgroundColor',[1,1,1],...
        'TooltipString','B1+ in uT that was used to calculate this shim',...
        'Callback',@updateReferenceB1);

    uicontrol(hTxMagPhsDlg,'Style','pushButton','String','Import TXT',...
        'Position',[10 buttonY 70 19],...
        'TooltipString','Load a shim exported as abs/phase text rows',...
        'Callback',@importShim);
    uicontrol(hTxMagPhsDlg,'Style','pushButton','String','OK',...
        'Position',[125 buttonY 45 19],'Callback',@confirmSelection);
    uicontrol(hTxMagPhsDlg,'Style','pushButton','String','Cancel',...
        'Position',[175 buttonY 55 19],'Callback',@cancelSelection);

    uiwait(hTxMagPhsDlg);
    if confirmed
        TxMagMat = zeros(Tx,1);
        TxPhsMat = zeros(Tx,1);
        for n = 1:Tx
            TxMagMat(n) = str2double(get(magHandles(n),'String'));
            TxPhsMat(n) = str2double(get(phsHandles(n),'String'));
        end
        TxRefB1 = parseReferenceB1(get(refB1Handle,'String'));
        index = 1;
    else
        TxMagMat = Mag;
        TxPhsMat = Phs;
        TxRefB1 = RefB1;
        index = 0;
    end

    if isgraphics(hTxMagPhsDlg)
        delete(hTxMagPhsDlg);
    end

    function updateMagnitude(coilIndex)
        mag = str2double(get(magHandles(coilIndex),'String'));
        if isnan(mag) || ~isfinite(mag)
            mag = Mag(coilIndex);
            set(magHandles(coilIndex),'String',num2str(mag));
        elseif mag < 0
            mag = abs(mag);
            set(magHandles(coilIndex),'String',num2str(mag));
        end
        set(faHandles(coilIndex),'String',num2str(rem(FA*mag,360)));
    end

    function updatePhase(coilIndex)
        phs = str2double(get(phsHandles(coilIndex),'String'));
        if isnan(phs) || ~isfinite(phs)
            phs = Phs(coilIndex);
        end
        set(phsHandles(coilIndex),'String',num2str(rem(phs,360)));
    end

    function updateReferenceB1(source,eventdata) %#ok<INUSD>
        tempStr = strtrim(get(source,'String'));
        if isempty(tempStr)
            RefB1 = NaN;
            set(source,'String','');
            return;
        end

        temp = str2double(tempStr);
        if ~isnan(temp) && isfinite(temp) && temp > 0
            RefB1 = temp;
            set(source,'String',num2str(temp));
        else
            set(source,'String',formatOptionalScalar(RefB1));
        end
    end

    function importShim(source,eventdata) %#ok<INUSD>
        [fileName,pathName] = uigetfile({'*.txt','Text File (*.txt)';'*.*','All Files (*.*)'},...
            'OPEN: Shim Text File');
        if isequal(fileName,0)
            return;
        end

        try
            [shimMag, shimPhs] = readShimFile(fullfile(pathName,fileName));
            if numel(shimMag) ~= Tx
                error('The shim file contains %d channels, but this dialog expects %d.',numel(shimMag),Tx);
            end
            applyShim(shimMag,shimPhs);
        catch ME
            uiwait(errordlg(ME.message,'Import Shim','modal'));
        end
    end

    function applyShim(shimMag,shimPhs)
        shimMag = shimMag(:);
        shimPhs = shimPhs(:);
        for coilIndex = 1:Tx
            mag = shimMag(coilIndex);
            phs = shimPhs(coilIndex);
            set(magHandles(coilIndex),'String',num2str(mag));
            set(phsHandles(coilIndex),'String',num2str(phs));
            set(faHandles(coilIndex),'String',num2str(rem(FA*mag,360)));
        end
    end

    function [shimMag, shimPhs] = readShimFile(filePath)
        fid = fopen(filePath,'r');
        if fid == -1
            error('Could not open shim file: %s',filePath);
        end

        cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
        rows = zeros(0,2);
        lineNumber = 0;
        while true
            line = fgetl(fid);
            if ~ischar(line)
                break;
            end

            lineNumber = lineNumber + 1;
            line = strtrim(line);
            if isempty(line)
                continue;
            end
            if line(1) == '#' || line(1) == '%'
                continue;
            end

            values = sscanf(line,'%f');
            if numel(values) ~= 2
                error('Invalid shim format on line %d. Expected two numeric columns: abs phase_deg.',lineNumber);
            end

            rows(end+1,:) = values(:).'; %#ok<AGROW>
        end

        if isempty(rows)
            error('The selected shim file does not contain any shim values.');
        end

        shimMag = rows(:,1);
        shimPhs = rows(:,2);
    end

    function confirmSelection(source,eventdata) %#ok<INUSD>
        refB1 = parseReferenceB1(get(refB1Handle,'String'));
        if ~isempty(strtrim(get(refB1Handle,'String'))) && isnan(refB1)
            uiwait(errordlg('Shim B1+ must be blank or a positive numeric value.','Tx Array','modal'));
            return;
        end

        for coilIndex = 1:Tx
            mag = str2double(get(magHandles(coilIndex),'String'));
            phs = str2double(get(phsHandles(coilIndex),'String'));
            if isnan(mag) || ~isfinite(mag) || mag < 0 || isnan(phs) || ~isfinite(phs)
                uiwait(errordlg('Tx magnitude must be finite and nonnegative; phase must be finite.','Tx Array','modal'));
                return;
            end
            set(phsHandles(coilIndex),'String',num2str(rem(phs,360)));
        end

        confirmed = true;
        uiresume(hTxMagPhsDlg);
    end

    function cancelSelection(source,eventdata) %#ok<INUSD>
        confirmed = false;
        uiresume(hTxMagPhsDlg);
    end
end

function refB1 = parseReferenceB1(inputString)
    inputString = strtrim(inputString);
    if isempty(inputString)
        refB1 = NaN;
        return;
    end

    refB1 = str2double(inputString);
    if isnan(refB1) || ~isfinite(refB1) || refB1 <= 0
        refB1 = NaN;
    end
end

function outputString = formatOptionalScalar(value)
    if isempty(value) || isnan(value)
        outputString = '';
    else
        outputString = num2str(value);
    end
end
