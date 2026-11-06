function [selectedFileName,selectedFileAddr,index] = TxFieldFileNameGUI(Tx,filePath,fileName,Mag,Phs,FA,placeholderText,fileFilter,dialogTitle)

    global fileAddr;

    confirmed = false;
    hGap = 2;
    dialogHeight = 15 + 30 * (2 + Tx);
    editHandles = gobjects(Tx,1);

    hTxFileNameDlg = figure('Visible','on','MenuBar','none','Name','Tx Array Setup',...
        'NumberTitle','off','Position',[100,30,320,dialogHeight],'Resize','off',...
        'Toolbar','none','Color',[1,1,1],'WindowStyle','modal',...
        'CloseRequestFcn',@cancelSelection);
    movegui(hTxFileNameDlg,'center');

    headerX = 215;
    headerY = 30 * (1.5 + Tx);
    uicontrol(hTxFileNameDlg,'Style','text','String','Mag',...
        'Position',[headerX headerY 30 13],'BackgroundColor',[1,1,1]);
    uicontrol(hTxFileNameDlg,'Style','text','String','Phs',...
        'Position',[headerX+30+hGap headerY 30 13],'BackgroundColor',[1,1,1]);
    uicontrol(hTxFileNameDlg,'Style','text','String','RF FA',...
        'Position',[headerX+60+2*hGap headerY 30 13],'BackgroundColor',[1,1,1]);

    buttonX = 190;
    okHandle = uicontrol(hTxFileNameDlg,'Style','pushButton','String','OK',...
        'Position',[buttonX headerY-(Tx+1)*30 60 19],'Callback',@confirmSelection,...
        'Enable','off');
    uicontrol(hTxFileNameDlg,'Style','pushButton','String','Cancel',...
        'Position',[buttonX+60 headerY-(Tx+1)*30 60 19],'Callback',@cancelSelection);

    rowX = 10;
    for n = 1:Tx
        rowY = headerY - n * 30;
        uicontrol(hTxFileNameDlg,'Style','pushButton','String',['Coil',num2str(n)],...
            'Position',[rowX rowY 50 19],'Callback',@(source,eventdata) browseFile(n)); %#ok<INUSD>

        editHandles(n) = uicontrol(hTxFileNameDlg,'Style','edit',...
            'Position',[rowX+50+hGap rowY 150 19],'Enable','inactive',...
            'BackgroundColor',[1,1,1]);

        selectedName = getSelectionValue(fileName,n);
        selectedPath = getSelectionValue(filePath,n);
        if isempty(selectedName)
            set(editHandles(n),'UserData','','String',placeholderText,'FontAngle','italic');
        else
            set(editHandles(n),'UserData',[selectedPath,selectedName],...
                'String',selectedName,'FontAngle','normal');
        end

        uicontrol(hTxFileNameDlg,'Style','edit',...
            'Position',[rowX+50+150+3*hGap rowY 30 19],...
            'String',num2str(Mag(n)),'Enable','inactive');
        uicontrol(hTxFileNameDlg,'Style','edit',...
            'Position',[rowX+50+150+30+4*hGap rowY 30 19],...
            'String',num2str(Phs(n)),'Enable','inactive');
        uicontrol(hTxFileNameDlg,'Style','edit',...
            'Position',[rowX+50+150+60+5*hGap rowY 30 19],...
            'String',num2str(rem(Mag(n)*FA,360)),'Enable','inactive');
    end

    updateOkState();

    uiwait(hTxFileNameDlg);

    if confirmed
        selectedFileName = cell(Tx,1);
        selectedFileAddr = cell(Tx,1);
        for n = 1:Tx
            selection = get(editHandles(n),'UserData');
            [selectedFileAddr{n},selectedFileName{n}] = addrCvrt(selection);
        end
        index = 1;
    else
        selectedFileName = fileName;
        selectedFileAddr = filePath;
        index = 0;
    end

    if isgraphics(hTxFileNameDlg)
        delete(hTxFileNameDlg);
    end

    function browseFile(coilIndex)
        startPath = fileAddr;
        if isempty(startPath)
            startPath = pwd;
        end

        [selectedName,selectedPath] = uigetfile(fileFilter,dialogTitle,startPath);
        if ~isequal(selectedName,0) && ~isequal(selectedPath,0)
            set(editHandles(coilIndex),'UserData',[selectedPath,selectedName],...
                'String',selectedName,'FontAngle','normal');
            fileAddr = selectedPath;
            updateOkState();
        end
    end

    function updateOkState()
        hasSelection = true;
        for idx = 1:Tx
            hasSelection = hasSelection && ~isempty(get(editHandles(idx),'UserData'));
        end

        if hasSelection
            set(okHandle,'Enable','on');
        else
            set(okHandle,'Enable','off');
        end
    end

    function confirmSelection(source,eventdata) %#ok<INUSD>
        confirmed = true;
        uiresume(hTxFileNameDlg);
    end

    function cancelSelection(source,eventdata) %#ok<INUSD>
        confirmed = false;
        uiresume(hTxFileNameDlg);
    end
end

function value = getSelectionValue(selectionData,index)
    if iscell(selectionData)
        if numel(selectionData) >= index
            value = selectionData{index};
        else
            value = '';
        end
    elseif index == 1
        value = selectionData;
    else
        value = '';
    end

    if isempty(value)
        value = '';
    end
end
