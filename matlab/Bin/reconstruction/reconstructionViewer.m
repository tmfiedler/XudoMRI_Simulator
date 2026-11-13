function varargout = reconstructionViewer(varargin)
%RECONSTRUCTIONVIEWER Reconstruct Cartesian and 3D radial simulator output.
%   This is the current backend opened by RECO. It resolves protocol and
%   trajectory sidecars, validates sample dimensions, reconstructs each Rx
%   channel, and combines channels for display. The 3D radial path is a
%   quick-look Kaiser-Bessel gridding method. See docs/SCIENTIFIC_METHODS.md.

    initialSelection = parseInitialSelection(varargin{:});
    hFig = createReconstructionFigure();
    if ~isempty(initialSelection)
        loadSelectedSignalData(hFig,initialSelection.SignalFiles,initialSelection.DataPath);
    end
    if nargout > 0
        varargout{1} = hFig;
    end
end

%% Launch arguments and figure construction

function initialSelection = parseInitialSelection(varargin)

    initialSelection = [];
    if isempty(varargin)
        return;
    end

    parser = inputParser;
    parser.addParameter('SignalFiles',{},@(value) ischar(value) || iscell(value));
    parser.addParameter('DataPath','',@(value) ischar(value) || isstring(value));
    parser.addParameter('NumRx',[],@(value) isempty(value) || isnumeric(value));
    parser.parse(varargin{:});

    signalFiles = parser.Results.SignalFiles;
    if ischar(signalFiles) || isstring(signalFiles)
        signalFiles = {char(signalFiles)};
    end
    if isempty(signalFiles) || isempty(parser.Results.DataPath)
        return;
    end

    initialSelection = struct('SignalFiles',{signalFiles},...
        'DataPath',char(parser.Results.DataPath),'NumRx',parser.Results.NumRx);
end

function hFig = createReconstructionFigure()

    hFig = figure('Name','Reconstruction','NumberTitle','off',...
        'MenuBar','none','Toolbar','figure','Color',[1 1 1],...
        'Position',[100 100 1400 920]);
    movegui(hFig,'center');

    hControl = uipanel('Parent',hFig,'Title','Controls','Units','normalized',...
        'Position',[0.02 0.03 0.25 0.94],'BackgroundColor',[1 1 1]);

    uicontrol(hControl,'Style','text','String','# Rx','Units','normalized',...
        'Position',[0.08 0.94 0.13 0.03],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.nRxEdit = uicontrol(hControl,'Style','edit','String','1',...
        'Units','normalized','Position',[0.22 0.93 0.16 0.05],...
        'BackgroundColor',[1 1 1],'Callback',@nRxCallback);

    handles.loadButton = uicontrol(hControl,'Style','pushbutton',...
        'String','Load K-space Data','Units','normalized',...
        'Position',[0.41 0.93 0.51 0.05],'Callback',@loadDataCallback);

    uicontrol(hControl,'Style','text','String','Display','Units','normalized',...
        'Position',[0.08 0.872 0.21 0.03],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.displayPopup = uicontrol(hControl,'Style','popupmenu',...
        'String',{'RSS Magnitude';'Sum Magnitude';'Coherent Magnitude';...
                   'Coherent Phase';'Coherent Real';'Coherent Imag'},...
        'Value',1,'Units','normalized','Position',[0.31 0.862 0.61 0.05],...
        'BackgroundColor',[1 1 1],'Callback',@displayModeCallback);

    handles.loadNoiseButton = uicontrol(hControl,'Style','pushbutton',...
        'String','Load Noise (.nois)','Units','normalized',...
        'Position',[0.08 0.79 0.46 0.05],'Enable','off',...
        'Callback',@loadNoiseCallback);

    uicontrol(hControl,'Style','text','String','Noise Scale','Units','normalized',...
        'Position',[0.57 0.80 0.22 0.03],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.noiseScaleEdit = uicontrol(hControl,'Style','edit','String','0',...
        'Units','normalized','Position',[0.80 0.79 0.12 0.05],...
        'BackgroundColor',[1 1 1],'Enable','off',...
        'Callback',@noiseScaleCallback);

    handles.infoText = uicontrol(hControl,'Style','text',...
        'String',{'No data loaded.'},'Units','normalized',...
        'Position',[0.08 0.597 0.84 0.177],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');

    handles.paramText = uicontrol(hControl,'Style','text',...
        'String',{'r^2 DCF, Kaiser-Bessel width 4, 2x oversampling'},...
        'Units','normalized','Position',[0.08 0.56 0.84 0.026],...
        'BackgroundColor',[1 1 1],'HorizontalAlignment','left');

    handles.statusText = uicontrol(hControl,'Style','text',...
        'String',{'Status: waiting for data'},'Units','normalized',...
        'Position',[0.08 0.518 0.84 0.032],'BackgroundColor',[1 1 1],...
        'ForegroundColor',[0.1 0.1 0.1],'HorizontalAlignment','left');

    uicontrol(hControl,'Style','text','String','Sagittal Slice','Units','normalized',...
        'Position',[0.08 0.474 0.40 0.034],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.xSlider = uicontrol(hControl,'Style','slider','Units','normalized',...
        'Position',[0.08 0.428 0.68 0.04],'Min',1,'Max',2,'Value',1,...
        'SliderStep',[1 1],'Enable','off','Tag','x',...
        'Callback',@sliceSliderCallback);
    handles.xValue = uicontrol(hControl,'Style','text','String','1','Units','normalized',...
        'Position',[0.80 0.428 0.12 0.04],'BackgroundColor',[1 1 1]);

    uicontrol(hControl,'Style','text','String','Coronal Slice','Units','normalized',...
        'Position',[0.08 0.386 0.40 0.034],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.ySlider = uicontrol(hControl,'Style','slider','Units','normalized',...
        'Position',[0.08 0.340 0.68 0.04],'Min',1,'Max',2,'Value',1,...
        'SliderStep',[1 1],'Enable','off','Tag','y',...
        'Callback',@sliceSliderCallback);
    handles.yValue = uicontrol(hControl,'Style','text','String','1','Units','normalized',...
        'Position',[0.80 0.340 0.12 0.04],'BackgroundColor',[1 1 1]);

    uicontrol(hControl,'Style','text','String','Axial Slice','Units','normalized',...
        'Position',[0.08 0.298 0.40 0.034],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.zSlider = uicontrol(hControl,'Style','slider','Units','normalized',...
        'Position',[0.08 0.252 0.68 0.04],'Min',1,'Max',2,'Value',1,...
        'SliderStep',[1 1],'Enable','off','Tag','z',...
        'Callback',@sliceSliderCallback);
    handles.zValue = uicontrol(hControl,'Style','text','String','1','Units','normalized',...
        'Position',[0.80 0.252 0.12 0.04],'BackgroundColor',[1 1 1]);

    uicontrol(hControl,'Style','text','String','Export View','Units','normalized',...
        'Position',[0.08 0.206 0.30 0.036],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.exportViewPopup = uicontrol(hControl,'Style','popupmenu',...
        'String',{'Axial';'Sagittal';'Coronal';'K-Space'},'Value',1,...
        'Units','normalized','Position',[0.08 0.152 0.48 0.05],...
        'BackgroundColor',[1 1 1],'Enable','off');
    handles.exportViewButton = uicontrol(hControl,'Style','pushbutton',...
        'String','Export View Port','Units','normalized',...
        'Position',[0.60 0.152 0.32 0.05],'Enable','off',...
        'Callback',@exportViewPortCallback);

    actionHeight = 0.05;
    labelHeight = 0.035;
    labelInset = (actionHeight-labelHeight)/2;
    trajectoryY = 0.084;
    bottomActionY = 0.014;
    handles.trajectoryButton = uicontrol(hControl,'Style','pushbutton',...
        'String','View Trajectory','Units','normalized',...
        'Position',[0.08 trajectoryY 0.42 actionHeight],'Enable','off',...
        'Callback',@viewTrajectoryCallback);

    uicontrol(hControl,'Style','text','String','Matrix','Units','normalized',...
        'Position',[0.52 trajectoryY+labelInset 0.18 labelHeight],'BackgroundColor',[1 1 1]);
    handles.reconMatrixEdit = uicontrol(hControl,'Style','edit',...
        'Units','normalized','Position',[0.72 trajectoryY 0.20 actionHeight],'BackgroundColor',[1 1 1],...
        'Enable','off','Tag','RadialReconstructionMatrix','Callback',@reconMatrixCallback,...
        'TooltipString','Voxels per axis for 3D radial data. Clear to restore the protocol default.');

    handles.snrMapButton = uicontrol(hControl,'Style','pushbutton',...
        'String','SNR Map','Units','normalized',...
        'Position',[0.08 bottomActionY 0.56 actionHeight],'Enable','off',...
        'TooltipString','Requires a second, different simulated .nois realization.',...
        'Callback',@snrMapCallback);
    handles.loggingCheckbox = uicontrol(hControl,'Style','checkbox',...
        'String','Log','Units','normalized',...
        'Position',[0.69 bottomActionY+labelInset 0.23 labelHeight],...
        'BackgroundColor',[1 1 1],...
        'Value',double(isRadialRecoLoggingEnabled()),...
        'Callback',@loggingToggleCallback);

    handles.axialAxes = axes('Parent',hFig,'Units','normalized',...
        'Position',[0.29 0.54 0.29 0.38]);
    handles.sagittalAxes = axes('Parent',hFig,'Units','normalized',...
        'Position',[0.63 0.54 0.29 0.38]);
    handles.coronalAxes = axes('Parent',hFig,'Units','normalized',...
        'Position',[0.29 0.08 0.29 0.38]);
    handles.kspaceAxes = axes('Parent',hFig,'Units','normalized',...
        'Position',[0.63 0.08 0.29 0.38]);

    initializeAxes(handles.axialAxes,'Axial');
    initializeAxes(handles.sagittalAxes,'Sagittal');
    initializeAxes(handles.coronalAxes,'Coronal');
    initializeAxes(handles.kspaceAxes,'K-Space');

    handles.busyOverlay = uipanel('Parent',hFig,'Units','normalized',...
        'Position',[0 0 1 1],'BackgroundColor',[0.94 0.94 0.94],...
        'BorderType','none','Visible','off');
    handles.busyPanel = uipanel('Parent',handles.busyOverlay,'Title','Please wait',...
        'Units','normalized','Position',[0.39 0.44 0.22 0.12],...
        'BackgroundColor',[1 1 1]);
    handles.busyText = uicontrol(handles.busyPanel,'Style','text','String','',...
        'Units','normalized','Position',[0.05 0.18 0.90 0.56],...
        'FontWeight','bold','HorizontalAlignment','center',...
        'BackgroundColor',[1 1 1]);

    state.handles = handles;
    state.defaultFigureName = get(hFig,'Name');
    state.busyDepth = 0;
    state.nRx = 1;
    state.loadedNRx = 1;
    state.displayMode = 1;
    state.dataLoaded = false;
    state.volumeRSS = [];
    state.volumeSOM = [];
    state.volumeComplex = [];
    state.kspaceMagnitude = [];
    state.trajectory = [];
    state.protocol = struct();
    state.reconInfo = struct();
    state.signalDataClean = [];
    state.cleanRecon = [];
    state.noiseData = [];
    state.noiseLoaded = false;
    state.noiseScale = 0;
    state.signalFiles = {};
    state.noiseFiles = {};
    state.dataPath = '';
    state.samplesPerSpoke = [];
    state.numSpokes = [];
    state.reconSize = [];
    state.defaultReconSize = [];
    state.reconContext = [];
    state.reconMode = '';
    state.cartesianMatSize = [];
    state.sliceIndex = [1 1 1];
    state.resetSliceIndex = false;
    state.loggingEnabled = isRadialRecoLoggingEnabled();

    guidata(hFig,state);
    refreshDisplay(hFig);
end

function initializeAxes(hAxes,titleStr)
    updateAxesImage(hAxes,zeros(64),titleStr);
end

%% Signal and noise loading callbacks

function loadDataCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);

    try
        logRadialReco('Load requested with #Rx = %d',state.nRx);
        setStatus(hFig,'Status: selecting raw data...');
        [selectedFiles,dataPath] = selectSignalFiles(state.nRx);
        if isempty(selectedFiles)
            logRadialReco('Data selection cancelled');
            setStatus(hFig,'Status: data selection cancelled');
            return;
        end
        loadSelectedSignalData(hFig,selectedFiles,dataPath);
    catch ME
        logRadialReco('ERROR: %s',ME.message);
        logException(ME);
        setStatus(hFig,'Status: reconstruction failed');
        errordlg(ME.message,'Reconstruction Error','modal');
    end
end

function loadSelectedSignalData(hFig,selectedFiles,dataPath)

    state = guidata(hFig);
    logRadialReco('Selected data path: %s',dataPath);
    logRadialReco('Selected signal files: %s',strjoin(selectedFiles,', '));

    if ~isempty(selectedFiles)
        state.nRx = numel(selectedFiles);
        if isfield(state,'handles') && isfield(state.handles,'nRxEdit') && ishghandle(state.handles.nRxEdit)
            set(state.handles.nRxEdit,'String',num2str(state.nRx));
        end
        guidata(hFig,state);
    end

    try
        dataFileName = fullfile(dataPath,selectedFiles{1});
        protFileName = resolveCompanionProtocolFileRadial(dataFileName,selectedFiles);
        logRadialReco('Resolved protocol file: %s',protFileName);

        if exist(protFileName,'file') ~= 2
            [protName,protPath,protIndex] = uigetfile('*.prot','OPEN: Protocol File',dataPath);
            if isequal(protIndex,0)
                logRadialReco('Protocol selection cancelled');
                setStatus(hFig,'Status: protocol selection cancelled');
                return;
            end
            protFileName = fullfile(protPath,protName);
            logRadialReco('User-selected protocol file: %s',protFileName);
        end

        beginBusyState(hFig,'Loading reconstruction data...');
        loadBusyCleanup = onCleanup(@() endBusyState(hFig)); %#ok<NASGU>
        setStatus(hFig,'Status: reading protocol...');
        updateBusyState(hFig,'Reading protocol...');
        protocol = parseRadialProtocolFile(protFileName);
        protocol.ProtocolFile = protFileName;
        logRadialReco('Protocol sequence=%s MatSize=%s FOV=%s NumRx=%d',...
            protocol.SequenceType,mat2str(protocol.MatSize),mat2str(protocol.FOV),protocol.NumRx);

        if state.nRx > protocol.NumRx
            error('Selected Rx channel count exceeds the protocol # Rx value.');
        end

        if numel(selectedFiles) == 1 && protocol.NumRx > 1
            selectedFiles = discoverNumberedSignalFiles(dataPath,selectedFiles{1},protocol.NumRx);
            state = guidata(hFig);
            state.nRx = numel(selectedFiles);
            if isfield(state,'handles') && isfield(state.handles,'nRxEdit') && ishghandle(state.handles.nRxEdit)
                set(state.handles.nRxEdit,'String',num2str(state.nRx));
            end
            guidata(hFig,state);
        end

        updateBusyState(hFig,'Loading K-space data...');
        signalData = loadSignalDataFiles(dataPath,selectedFiles);
        totalSamples = size(signalData,1);
        logRadialReco('Loaded signal data size: %s totalSamples=%d',reconstructionSizeString(signalData),totalSamples);

        radial = usesRadial3DWorkflow(protocol.SequenceType);
        offset = protocol.FOVOffset;
        if ~radial
            [~,orientation] = ismember(protocol.SliceOrientation,{'Axial','Sagittal','Coronal'});
            axesXYZ = cartesianAxes(orientation,false);
            offset(axesXYZ(3)) = 0;
        end

        if radial || any(offset)
            trajFileName = resolveCompanionTrajectoryFile(dataFileName,selectedFiles);
            if exist(trajFileName,'file') ~= 2
                [trajName,trajPath,trajIndex] = uigetfile('*.ktrj','OPEN: Trajectory File',dataPath);
                if isequal(trajIndex,0)
                    setStatus(hFig,'Status: trajectory selection cancelled');
                    return;
                end
                trajFileName = fullfile(trajPath,trajName);
            end
            protocol.TrajectoryFile = trajFileName;
            updateBusyState(hFig,'Loading trajectory data...');
            trajFlat = loadTrajectoryFile(trajFileName,totalSamples);
            if any(offset)
                protocol.FOVPhase = fovCenterPhase(trajFlat,offset,protocol.ModelSpacing);
            end
        end

        if ~radial
            loadCartesianReconstruction(hFig,protocol,signalData,dataPath,selectedFiles);
            return;
        end

        [samplesPerSpoke,numSpokes] = inferRadialDimensions(protocol,totalSamples);
        reconSize = samplesPerSpoke;
        if ~isempty(protocol.RadialResolutionMm)
            fovMeters = radialFOVMeters(protocol.FOV);
            reconSize = ceil(max(fovMeters) * 1000 / protocol.RadialResolutionMm);
        end
        logRadialReco('Inferred samplesPerSpoke=%d numSpokes=%d reconSize=%d',...
            samplesPerSpoke,numSpokes,reconSize);
        traj = reshapeTrajectoryData(trajFlat,samplesPerSpoke,numSpokes);
        logRadialReco('Reshaped trajectory size: %s',reconstructionSizeString(traj));

        warningText = validateCenterOutTrajectory(traj);
        if ~isempty(warningText)
            logRadialReco('Trajectory warning: %s',strrep(warningText,sprintf('\n'),' | '));
            warndlg(warningText,'Trajectory Warning','modal');
        end

        state = guidata(hFig);
        state.protocol = protocol;
        state.reconMode = 'radial';
        state.signalDataClean = signalData;
        state.cleanRecon = [];
        state.loadedNRx = size(signalData,2);
        state.noiseData = [];
        state.noiseLoaded = false;
        state.noiseScale = 0;
        state.signalFiles = selectedFiles;
        state.noiseFiles = {};
        state.dataPath = dataPath;
        state.samplesPerSpoke = samplesPerSpoke;
        state.numSpokes = numSpokes;
        state.reconSize = reconSize;
        state.defaultReconSize = reconSize;
        state.trajectory = traj;
        state.reconContext = [];
        state.cartesianMatSize = [];
        state.resetSliceIndex = true;
        guidata(hFig,state);
        updateBusyState(hFig,'Reconstructing 3D volume...');
        applyCurrentReconstruction(hFig,'Status: reconstructing 3D volume...');
        setStatus(hFig,'Status: reconstruction complete');
    end
end

function loadCartesianReconstruction(hFig,protocol,signalData,dataPath,selectedFiles)

    updateBusyState(hFig,'Reconstructing Cartesian data...');
    [recon,matSize] = reconstructCartesianDataset(signalData,protocol);

    state = guidata(hFig);
    state.protocol = protocol;
    state.reconMode = 'cartesian';
    state.signalDataClean = signalData;
    state.cleanRecon = recon;
    state.loadedNRx = size(signalData,2);
    state.noiseData = [];
    state.noiseLoaded = false;
    state.noiseScale = 0;
    state.signalFiles = selectedFiles;
    state.noiseFiles = {};
    state.dataPath = dataPath;
    state.samplesPerSpoke = [];
    state.numSpokes = [];
    state.reconSize = [];
    state.defaultReconSize = [];
    state.trajectory = [];
    state.reconContext = [];
    state.cartesianMatSize = matSize;
    state.reconInfo = recon.info;
    state.volumeRSS = recon.volumeRSS;
    state.volumeSOM = recon.volumeSOM;
    state.volumeComplex = recon.volumeComplex;
    state.kspaceMagnitude = recon.kspaceMagnitude;
    state.dataLoaded = true;
    state.sliceIndex = round((getVolumeDims(state.volumeRSS) + 1) / 2);
    state.sliceIndex = clampSliceIndex(state.sliceIndex,getVolumeDims(state.volumeRSS));
    state.resetSliceIndex = false;

    guidata(hFig,state);
    updateSliceControls(hFig);
    updateInfoText(hFig);
    updateDataControls(hFig);
    set(state.handles.exportViewPopup,'Enable','on');
    set(state.handles.exportViewButton,'Enable','on');
    set(state.handles.snrMapButton,'Enable','off');
    set(state.handles.trajectoryButton,'Enable','on');
    refreshDisplay(hFig);
    setStatus(hFig,'Status: Cartesian reconstruction complete');
end

%% Interactive controls

function nRxCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    value = str2double(get(source,'String'));
    if isnan(value) || value < 1
        value = 1;
    end
    state.nRx = max(1,round(value));
    set(source,'String',num2str(state.nRx));
    guidata(hFig,state);
end

function displayModeCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    state.displayMode = get(source,'Value');
    guidata(hFig,state);
    refreshDisplay(hFig);
end

function loggingToggleCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    state.loggingEnabled = get(source,'Value') ~= 0;
    guidata(hFig,state);
    setRadialRecoLoggingEnabled(state.loggingEnabled);
    if state.loggingEnabled
        setStatus(hFig,'Status: logging enabled');
    else
        setStatus(hFig,'Status: logging disabled');
    end
end

function sliceSliderCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    if ~state.dataLoaded
        return;
    end

    sliderValue = round(get(source,'Value'));
    switch get(source,'Tag')
        case 'x'
            state.sliceIndex(1) = sliderValue;
        case 'y'
            state.sliceIndex(2) = sliderValue;
        case 'z'
            state.sliceIndex(3) = sliderValue;
    end
    guidata(hFig,state);
    refreshDisplay(hFig);
end

function loadNoiseCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    if ~state.dataLoaded || isempty(state.signalDataClean)
        return;
    end

    try
        setStatus(hFig,'Status: selecting noise data...');
        [selectedFiles,dataPath] = selectNoiseFiles(state.loadedNRx,state.dataPath);
        if isempty(selectedFiles)
            logRadialReco('Noise selection cancelled');
            setStatus(hFig,'Status: noise selection cancelled');
            return;
        end

        logRadialReco('Selected noise files: %s',strjoin(selectedFiles,', '));
        beginBusyState(hFig,'Loading noise data...');
        noiseBusyCleanup = onCleanup(@() endBusyState(hFig)); %#ok<NASGU>
        updateBusyState(hFig,'Reading noise data...');
        noiseData = loadNoiseDataFiles(dataPath,selectedFiles,size(state.signalDataClean,1));

        if ~isequal(size(noiseData),size(state.signalDataClean))
            error('Selected .nois file dimensions do not match the loaded .ksig data.');
        end

        state = guidata(hFig);
        state.noiseData = noiseData;
        state.noiseLoaded = true;
        state.noiseScale = 1;
        state.noiseFiles = selectedFiles;
        guidata(hFig,state);

        updateDataControls(hFig);
        updateBusyState(hFig,'Reconstructing with noise...');
        applyCurrentReconstruction(hFig,'Status: reconstructing with noise...');
        setStatus(hFig,'Status: reconstruction complete (noise applied)');
    catch ME
        logRadialReco('ERROR loading noise: %s',ME.message);
        logException(ME);
        setStatus(hFig,'Status: noise load failed');
        errordlg(ME.message,'Noise Error','modal');
    end
end

function noiseScaleCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    if ~state.dataLoaded
        set(source,'String','0');
        return;
    end

    noiseScale = str2double(get(source,'String'));
    if isnan(noiseScale) || noiseScale < 0
        noiseScale = 0;
    end
    set(source,'String',num2str(noiseScale));

    if ~state.noiseLoaded
        state.noiseScale = 0;
        guidata(hFig,state);
        set(source,'String','0');
        setStatus(hFig,'Status: load a .nois file before applying noise');
        return;
    end

    if state.noiseScale == noiseScale
        return;
    end

    state.noiseScale = noiseScale;
    guidata(hFig,state);

    try
        applyCurrentReconstruction(hFig,'Status: updating reconstruction noise scale...');
        if noiseScale == 0
            setStatus(hFig,'Status: reconstruction complete (noise disabled)');
        else
            setStatus(hFig,sprintf('Status: reconstruction complete (noise scale = %g)',noiseScale));
        end
    catch ME
        logRadialReco('ERROR updating noise scale: %s',ME.message);
        logException(ME);
        setStatus(hFig,'Status: reconstruction failed');
        errordlg(ME.message,'Reconstruction Error','modal');
    end
end

function exportViewPortCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    if ~state.dataLoaded
        return;
    end

    viewIndex = get(state.handles.exportViewPopup,'Value');
    [sourceAxes,viewName] = getExportAxes(state.handles,viewIndex);
    exportAxesToFigure(sourceAxes,viewName);
    setStatus(hFig,['Status: exported ',viewName,' view']);
end

function snrMapCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    if ~state.dataLoaded
        return;
    end

    if ~state.noiseLoaded || isempty(state.noiseData)
        errordlg(['Load one .nois realization first. The SNR map uses the clean ',...
            'reconstruction plus two independent noisy reconstructions.'],...
            'SNR Map','modal');
        return;
    end

    if state.noiseScale <= 0
        errordlg('Noise Scale must be greater than zero to compute an SNR map.','SNR Map','modal');
        return;
    end

    try
        setStatus(hFig,'Status: select a second, different .nois realization...');
        warndlg(['Select a second, different set of simulated noise files for the SNR map.',...
            sprintf('\n\n'),...
            'Do not reuse the same .nois realization that is already loaded.'],...
            'SNR Map','modal');
        [selectedFiles,dataPath] = selectNoiseFiles(state.loadedNRx,state.dataPath);
        if isempty(selectedFiles)
            setStatus(hFig,'Status: second noise selection cancelled');
            return;
        end

        beginBusyState(hFig,'Building SNR map...');
        snrBusyCleanup = onCleanup(@() endBusyState(hFig)); %#ok<NASGU>
        updateBusyState(hFig,'Reading second noise realization...');
        secondNoiseData = loadNoiseDataFiles(dataPath,selectedFiles,size(state.signalDataClean,1));
        if ~isequal(size(secondNoiseData),size(state.signalDataClean))
            error('Selected second .nois realization does not match the loaded .ksig data.');
        end

        state = guidata(hFig);
        [state,reconContext] = getReconstructionContext(state);
        guidata(hFig,state);

        setStatus(hFig,'Status: reconstructing SNR map...');
        [state,cleanRecon] = getCleanReconstruction(state,reconContext);
        guidata(hFig,state);
        updateBusyState(hFig,'Reconstructing noisy realization 1...');
        noisyRecon1 = reconstructSignalDataset(state,...
            state.signalDataClean + state.noiseScale * state.noiseData,reconContext);
        updateBusyState(hFig,'Reconstructing noisy realization 2...');
        noisyRecon2 = reconstructSignalDataset(state,...
            state.signalDataClean + state.noiseScale * secondNoiseData,reconContext);

        updateBusyState(hFig,'Computing SNR map...');
        snrMap = computeSNRMap(cleanRecon.volumeRSS,...
            noisyRecon1.volumeRSS,noisyRecon2.volumeRSS);

        assignin('base','radialRecoSNRMap',snrMap);
        assignin('base','radialRecoSNRNoisy1',noisyRecon1.volumeRSS);
        assignin('base','radialRecoSNRNoisy2',noisyRecon2.volumeRSS);

        showSNRMapFigure(snrMap,state.sliceIndex);
        setStatus(hFig,'Status: SNR map ready');
    catch ME
        logRadialReco('ERROR building SNR map: %s',ME.message);
        logException(ME);
        setStatus(hFig,'Status: SNR map failed');
        errordlg(ME.message,'SNR Map Error','modal');
    end
end

function viewTrajectoryCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    if ~state.dataLoaded
        return;
    end

    try
        if strcmp(state.reconMode,'cartesian')
            fileName = state.protocol.TrajectoryFile;
            if ~isfile(fileName)
                signalFile = fullfile(state.dataPath,state.signalFiles{1});
                fileName = resolveCompanionTrajectoryFile(signalFile,state.signalFiles);
            end
            if ~isfile(fileName)
                [name,folder] = uigetfile('*.ktrj','OPEN: Trajectory File',state.dataPath);
                if isequal(name,0)
                    return;
                end
                fileName = fullfile(folder,name);
            end
            traj = loadTrajectoryFile(fileName,size(state.signalDataClean,1));
            plotCartesianTrajectoryFigure(traj,state.cartesianMatSize,state.reconInfo.sliceOrientation);
        elseif ~isempty(state.trajectory)
            plotTrajectoryFigure(state.trajectory,state.reconInfo);
        else
            return;
        end
        setStatus(hFig,'Status: opened trajectory viewer');
    catch ME
        logException(ME);
        errordlg(ME.message,'Trajectory Error','modal');
    end
end

function reconMatrixCallback(source,~)
    hFig = ancestor(source,'figure');
    previous = guidata(hFig);
    if ~previous.dataLoaded || ~strcmp(previous.reconMode,'radial') || previous.busyDepth > 0
        return;
    end
    try
        value = strtrim(get(source,'String'));
        reconSize = previous.defaultReconSize;
        if ~isempty(value)
            reconSize = str2double(value);
            validateattributes(reconSize,{'numeric'},{'scalar','real','finite','integer','positive'});
        end
        if reconSize == previous.reconSize
            set(source,'String',num2str(reconSize));
            return;
        end
        state = previous;
        state.reconSize = reconSize;
        state.reconContext = [];
        state.cleanRecon = [];
        state.resetSliceIndex = true;
        guidata(hFig,state);
        applyCurrentReconstruction(hFig,'Status: updating radial reconstruction matrix...');
        setStatus(hFig,'Status: reconstruction complete');
    catch ME
        guidata(hFig,previous);
        set(source,'String',num2str(previous.reconSize));
        setStatus(hFig,'Status: reconstruction matrix unchanged');
        errordlg(ME.message,'Radial Reconstruction Matrix');
    end
end

%% Reconstruction orchestration

function applyCurrentReconstruction(hFig,statusMessage)
    if nargin < 2 || isempty(statusMessage)
        statusMessage = 'Status: reconstructing 3D volume...';
    end

    state = guidata(hFig);
    if isempty(state.signalDataClean)
        error('No data is loaded for reconstruction.');
    end

    useCleanRecon = ~state.noiseLoaded || isempty(state.noiseData) || state.noiseScale == 0;

    beginBusyState(hFig,stripStatusPrefix(statusMessage));
    reconstructionBusyCleanup = onCleanup(@() endBusyState(hFig)); %#ok<NASGU>
    setStatus(hFig,statusMessage);
    updateBusyState(hFig,stripStatusPrefix(statusMessage));
    state = guidata(hFig);
    if strcmpi(state.reconMode,'cartesian')
        if useCleanRecon
            if isempty(state.cleanRecon)
                [recon,state.cartesianMatSize] = reconstructCartesianDataset(state.signalDataClean,state.protocol);
                state.cleanRecon = recon;
            else
                recon = state.cleanRecon;
            end
        else
            signalData = state.signalDataClean + state.noiseScale * state.noiseData;
            [recon,state.cartesianMatSize] = reconstructCartesianDataset(signalData,state.protocol);
        end

        state.reconInfo = recon.info;
        state.reconInfo.noiseScale = state.noiseScale;
        state.reconInfo.noiseLoaded = state.noiseLoaded;
        state.volumeRSS = recon.volumeRSS;
        state.volumeSOM = recon.volumeSOM;
        state.volumeComplex = recon.volumeComplex;
        state.kspaceMagnitude = recon.kspaceMagnitude;
        state.dataLoaded = true;
        state.sliceIndex = clampSliceIndex(state.sliceIndex,getVolumeDims(state.volumeRSS));
        guidata(hFig,state);
        updateSliceControls(hFig);
        updateInfoText(hFig);
        updateDataControls(hFig);
        set(state.handles.exportViewPopup,'Enable','on');
        set(state.handles.exportViewButton,'Enable','on');
        set(state.handles.snrMapButton,'Enable','off');
        set(state.handles.trajectoryButton,'Enable','on');
        refreshDisplay(hFig);
        return;
    end

    if isempty(state.trajectory)
        error('No radial trajectory is loaded for reconstruction.');
    end

    [state,reconContext] = getReconstructionContext(state);
    if useCleanRecon
        if isempty(state.cleanRecon)
            logRadialReco('Starting clean reconstruction noiseLoaded=%d noiseScale=%g signal=%s',...
                state.noiseLoaded,state.noiseScale,reconstructionSizeString(state.signalDataClean));
            [state,recon] = getCleanReconstruction(state,reconContext);
            logRadialReco('Reconstruction complete RSS=%s SOM=%s Complex=%s Kspace=%s',...
                reconstructionSizeString(recon.volumeRSS),reconstructionSizeString(recon.volumeSOM),...
                reconstructionSizeString(recon.volumeComplex),reconstructionSizeString(recon.kspaceMagnitude));
        else
            logRadialReco('Reusing cached clean reconstruction noiseLoaded=%d noiseScale=%g',...
                state.noiseLoaded,state.noiseScale);
            recon = state.cleanRecon;
        end
    else
        signalData = state.signalDataClean + state.noiseScale * state.noiseData;
        logRadialReco('Starting reconstruction noiseLoaded=%d noiseScale=%g signal=%s',...
            state.noiseLoaded,state.noiseScale,reconstructionSizeString(signalData));
        recon = reconstructSignalDataset(state,signalData,reconContext);
        logRadialReco('Reconstruction complete RSS=%s SOM=%s Complex=%s Kspace=%s',...
            reconstructionSizeString(recon.volumeRSS),reconstructionSizeString(recon.volumeSOM),...
            reconstructionSizeString(recon.volumeComplex),reconstructionSizeString(recon.kspaceMagnitude));
    end

    state.reconInfo = recon.info;
    state.reconInfo.noiseScale = state.noiseScale;
    state.reconInfo.noiseLoaded = state.noiseLoaded;
    state.volumeRSS = recon.volumeRSS;
    state.volumeSOM = recon.volumeSOM;
    state.volumeComplex = recon.volumeComplex;
    state.kspaceMagnitude = recon.kspaceMagnitude;
    state.dataLoaded = true;
    if isfield(state,'resetSliceIndex') && state.resetSliceIndex
        state.sliceIndex = round((getVolumeDims(state.volumeRSS) + 1) / 2);
    else
        state.sliceIndex = clampSliceIndex(state.sliceIndex,getVolumeDims(state.volumeRSS));
    end
    state.resetSliceIndex = false;

    guidata(hFig,state);
    updateSliceControls(hFig);
    updateInfoText(hFig);
    updateDataControls(hFig);
    set(state.handles.exportViewPopup,'Enable','on');
    set(state.handles.exportViewButton,'Enable','on');
    set(state.handles.snrMapButton,'Enable','on');
    set(state.handles.trajectoryButton,'Enable','on');
    refreshDisplay(hFig);
end

function [state,reconContext] = getReconstructionContext(state)
    if ~isempty(state.reconContext)
        reconContext = state.reconContext;
        return;
    end

    fovMeters = radialFOVMeters(state.protocol.FOV);
    reconContext = buildRadialReconstructionContext(state.trajectory,state.reconSize,fovMeters,@logRadialReco);
    state.reconContext = reconContext;
end

function [state,cleanRecon] = getCleanReconstruction(state,reconContext)
    if ~isempty(state.cleanRecon)
        cleanRecon = state.cleanRecon;
        return;
    end

    logRadialReco('Building cached clean reconstruction signal=%s',reconstructionSizeString(state.signalDataClean));
    cleanRecon = reconstructSignalDataset(state,state.signalDataClean,reconContext);
    state.cleanRecon = cleanRecon;
end

function recon = reconstructSignalDataset(state,signalData,reconContext)
    if nargin < 3 || isempty(reconContext)
        [~,reconContext] = getReconstructionContext(state);
    end

    if isfield(state.protocol,'FOVPhase')
        signalData = signalData .* state.protocol.FOVPhase;
    end
    spokeData = reshapeSignalData(signalData,state.samplesPerSpoke,state.numSpokes);
    logRadialReco('Reshaped spoke data size: %s',reconstructionSizeString(spokeData));
    recon = reconstructRadialDataset(spokeData,reconContext,@logRadialReco);
end

%% SNR analysis

function snrMap = computeSNRMap(cleanVolume,noisyVolume1,noisyVolume2)
    if ~isequal(size(cleanVolume),size(noisyVolume1),size(noisyVolume2))
        error('SNR map inputs must have matching dimensions.');
    end

    diffVolume = double(noisyVolume1) - double(noisyVolume2);
    diffVector = diffVolume(:);
    diffVector = diffVector(~isnan(diffVector));
    if isempty(diffVector)
        error('No valid voxels were found for the SNR calculation.');
    end

    % Use two independent noisy reconstructions to
    % estimate a single image-domain sigma, then divide the clean image by it.
    sigma = std(diffVector,0) / sqrt(2);
    if sigma <= 10 * eps
        error(['Estimated sigma is effectively zero. Select a second independent ',...
            '.nois realization instead of reusing the same noise data.']);
    end
    sigma = max(sigma,eps);
    snrMap = single(double(cleanVolume) ./ sigma);
end

function showSNRMapFigure(snrMap,sliceIndex)
    hFig = figure('Visible','on','MenuBar','none','Name','3D Radial SNR Map',...
        'NumberTitle','off','Position',[120 120 1180 760],'Color',[1 1 1],...
        'Toolbar','figure');
    movegui(hFig,'center');

    sliceIndex = clampSliceIndex(sliceIndex,size(snrMap));
    xIdx = sliceIndex(1);
    yIdx = sliceIndex(2);
    zIdx = sliceIndex(3);

    axialSlice = rot90(squeeze(snrMap(:,:,zIdx)));
    sagittalSlice = rot90(squeeze(snrMap(xIdx,:,:)));
    coronalSlice = rot90(squeeze(snrMap(:,yIdx,:)));

    hAxial = subplot(2,2,1,'Parent',hFig);
    axialTitle = sprintf('Axial SNR (z = %d)',zIdx);
    plotSNRMapSlice(hAxial,axialSlice,axialTitle);

    hSagittal = subplot(2,2,2,'Parent',hFig);
    sagittalTitle = sprintf('Sagittal SNR (x = %d)',xIdx);
    plotSNRMapSlice(hSagittal,sagittalSlice,sagittalTitle);

    hCoronal = subplot(2,2,3,'Parent',hFig);
    coronalTitle = sprintf('Coronal SNR (y = %d)',yIdx);
    plotSNRMapSlice(hCoronal,coronalSlice,coronalTitle);

    hInfo = subplot(2,2,4,'Parent',hFig);
    infoPos = get(hInfo,'Position');
    delete(hInfo);

    hPanel = uipanel('Parent',hFig,'Title','','Units','normalized',...
        'Position',infoPos,'BackgroundColor',[1 1 1]);

    uicontrol(hPanel,'Style','pushbutton',...
        'String',sprintf('Add Axial ROI (z = %d)',zIdx),...
        'Units','normalized','Position',[0.05 0.83 0.90 0.09],...
        'Callback',@(source,~) addSNRROIToViewer(source,'axial'));
    uicontrol(hPanel,'Style','pushbutton',...
        'String',sprintf('Add Sagittal ROI (x = %d)',xIdx),...
        'Units','normalized','Position',[0.05 0.71 0.90 0.09],...
        'Callback',@(source,~) addSNRROIToViewer(source,'sagittal'));
    uicontrol(hPanel,'Style','pushbutton',...
        'String',sprintf('Add Coronal ROI (y = %d)',yIdx),...
        'Units','normalized','Position',[0.05 0.59 0.90 0.09],...
        'Callback',@(source,~) addSNRROIToViewer(source,'coronal'));

    hResultList = uicontrol(hPanel,'Style','listbox',...
        'String',{'No ROI measurements yet.'},'Units','normalized',...
        'Position',[0.05 0.05 0.90 0.49],'BackgroundColor',[1 1 1],...
        'Max',2,'Min',0);

    viewerState.axes.axial = hAxial;
    viewerState.axes.sagittal = hSagittal;
    viewerState.axes.coronal = hCoronal;
    viewerState.slices.axial.data = axialSlice;
    viewerState.slices.axial.title = axialTitle;
    viewerState.slices.axial.label = sprintf('Axial z=%d',zIdx);
    viewerState.slices.sagittal.data = sagittalSlice;
    viewerState.slices.sagittal.title = sagittalTitle;
    viewerState.slices.sagittal.label = sprintf('Sagittal x=%d',xIdx);
    viewerState.slices.coronal.data = coronalSlice;
    viewerState.slices.coronal.title = coronalTitle;
    viewerState.slices.coronal.label = sprintf('Coronal y=%d',yIdx);
    viewerState.resultList = hResultList;
    viewerState.roiCount = 0;
    guidata(hFig,viewerState);
end

function plotSNRMapSlice(hAxes,snrSlice,titleStr)
    imagesc(hAxes,snrSlice);
    axis(hAxes,'image');
    colormap(hAxes,parula(256));
    colorbar(hAxes,'vert');
    title(hAxes,titleStr);
end

function addSNRROIToViewer(source,viewName)
    hFig = ancestor(source,'figure');
    viewerState = guidata(hFig);
    if ~isfield(viewerState.slices,viewName)
        return;
    end

    sliceInfo = viewerState.slices.(viewName);
    hAxes = viewerState.axes.(viewName);
    [meanSNR,voxelCount,wasCancelled] = measureSNRROI(hAxes,sliceInfo.data,sliceInfo.title);
    if wasCancelled
        return;
    end

    viewerState.roiCount = viewerState.roiCount + 1;
    resultLine = sprintf('ROI %d | %s | SNR = %.4f | N = %d',...
        viewerState.roiCount,sliceInfo.label,meanSNR,voxelCount);
    appendSNRROIResult(viewerState.resultList,resultLine);
    guidata(hFig,viewerState);
    logRadialReco('%s mean SNR = %.4f',sliceInfo.label,meanSNR);
end

function [meanSNR,voxelCount,wasCancelled] = measureSNRROI(hAxes,snrSlice,titleStr)
    meanSNR = NaN;
    voxelCount = 0;
    wasCancelled = true;

    if exist('impoly','file') == 2
        axes(hAxes); %#ok<LAXES>
        title(hAxes,['Draw polygon ROI (double-click to finish): ',titleStr]);
        cleanupObj = onCleanup(@() restoreAxesTitle(hAxes,titleStr)); %#ok<NASGU>
        hPoly = impoly(hAxes);
        position = wait(hPoly);
    elseif exist('drawpolygon','file') == 2
        title(hAxes,['Draw polygon ROI (double-click to finish): ',titleStr]);
        cleanupObj = onCleanup(@() restoreAxesTitle(hAxes,titleStr)); %#ok<NASGU>
        hPoly = drawpolygon('Parent',hAxes,'Color',[1 1 0],'LineWidth',1.5);
        position = wait(hPoly);
    else
        errordlg('ROI drawing requires impoly or drawpolygon.','SNR Map','modal');
        return;
    end

    if isempty(position)
        if isgraphics(hPoly) || (isobject(hPoly) && isvalid(hPoly))
            delete(hPoly);
        end
        return;
    end

    mask = createMask(hPoly);
    snrVals = double(snrSlice(mask));
    snrVals = snrVals(~isnan(snrVals));
    if isempty(snrVals)
        warndlg('Selected ROI does not contain valid SNR values.','SNR Map','modal');
        return;
    end

    meanSNR = mean(snrVals);
    voxelCount = numel(snrVals);
    wasCancelled = false;
end

function restoreAxesTitle(hAxes,titleStr)
    if isgraphics(hAxes)
        title(hAxes,titleStr);
    end
end

function appendSNRROIResult(hListBox,resultLine)
    resultLines = get(hListBox,'String');
    if ischar(resultLines)
        resultLines = cellstr(resultLines);
    end

    if isempty(resultLines) || (numel(resultLines) == 1 && strcmp(resultLines{1},'No ROI measurements yet.'))
        resultLines = {resultLine};
    else
        resultLines = [resultLines(:); {resultLine}];
    end

    set(hListBox,'String',resultLines,'Value',numel(resultLines));
end

%% Display and status management

function updateDataControls(hFig)
    state = guidata(hFig);
    handles = state.handles;
    hasNoise = state.dataLoaded && state.noiseLoaded;
    radial = state.dataLoaded && strcmpi(state.reconMode,'radial');
    set(handles.loadNoiseButton,'Enable',onOff(state.dataLoaded));
    set(handles.noiseScaleEdit,'String',num2str(state.noiseScale),'Enable',onOff(hasNoise));
    set(handles.snrMapButton,'Enable',onOff(hasNoise && radial));
    set(handles.reconMatrixEdit,'String',num2str(state.reconSize),'Enable',onOff(radial));
end

function sliceIndex = clampSliceIndex(sliceIndex,dims)
    if numel(dims) < 3
        dims(end+1:3) = 1;
    end
    dims = max(ones(size(dims)),dims);
    if numel(sliceIndex) ~= 3
        sliceIndex = round((dims + 1) / 2);
        return;
    end

    sliceIndex = [...
        min(max(1,round(sliceIndex(1))),dims(1)),...
        min(max(1,round(sliceIndex(2))),dims(2)),...
        min(max(1,round(sliceIndex(3))),dims(3))];
end

function dims = getVolumeDims(volume)
    dims = size(volume);
    if numel(dims) < 3
        dims(end+1:3) = 1;
    end
end

function [hAxes,viewName] = getExportAxes(handles,viewIndex)
    switch viewIndex
        case 1
            hAxes = handles.axialAxes;
            viewName = 'Axial';
        case 2
            hAxes = handles.sagittalAxes;
            viewName = 'Sagittal';
        case 3
            hAxes = handles.coronalAxes;
            viewName = 'Coronal';
        otherwise
            hAxes = handles.kspaceAxes;
            viewName = 'K-Space';
    end
end

function exportAxesToFigure(sourceAxes,viewName)
    imageHandle = findobj(sourceAxes,'-depth',1,'Type','image');
    if isempty(imageHandle)
        error(['No image was found in the ',lower(viewName),' view.']);
    end

    imageHandle = imageHandle(1);
    titleText = get(get(sourceAxes,'Title'),'String');
    if iscell(titleText)
        titleText = strjoin(titleText,' ');
    end

    hFig = figure('Name',[viewName,' View'],...
        'NumberTitle','off','Color',[1 1 1],'Toolbar','figure');
    hAxes = axes('Parent',hFig,'Position',[0.08 0.08 0.78 0.84]);
    imagesc(hAxes,get(imageHandle,'CData'));
    axis(hAxes,'image');
    set(hAxes,'CLim',get(sourceAxes,'CLim'));
    set(hAxes,'YDir',get(sourceAxes,'YDir'));
    colormap(hAxes,colormap(sourceAxes));
    title(hAxes,titleText);
    colorbar(hAxes,'vert');
end

function refreshDisplay(hFig)
    state = guidata(hFig);
    handles = state.handles;

    if ~state.dataLoaded
        initializeAxes(handles.axialAxes,'Axial');
        initializeAxes(handles.sagittalAxes,'Sagittal');
        initializeAxes(handles.coronalAxes,'Coronal');
        initializeAxes(handles.kspaceAxes,'K-Space');
        return;
    end

    xIdx = state.sliceIndex(1);
    yIdx = state.sliceIndex(2);
    zIdx = state.sliceIndex(3);

    [axialSlice,sagittalSlice,coronalSlice] = selectDisplaySlices(state,xIdx,yIdx,zIdx);

    updateAxesImage(handles.axialAxes,axialSlice,...
        sprintf('Axial (z = %d)',zIdx));
    updateAxesImage(handles.sagittalAxes,sagittalSlice,...
        sprintf('Sagittal (x = %d)',xIdx));
    updateAxesImage(handles.coronalAxes,coronalSlice,...
        sprintf('Coronal (y = %d)',yIdx));

    kspaceZ = mapImageSliceToKSpace(zIdx,size(state.volumeRSS,3),size(state.kspaceMagnitude,3));
    kspaceSlice = rot90(log1p(squeeze(state.kspaceMagnitude(:,:,kspaceZ))));
    updateAxesImage(handles.kspaceAxes,kspaceSlice,...
        sprintf('K-Space |k| (kz = %d)',kspaceZ));

    set(handles.xValue,'String',num2str(xIdx));
    set(handles.yValue,'String',num2str(yIdx));
    set(handles.zValue,'String',num2str(zIdx));
end

function updateAxesImage(hAxes,imageData,titleStr)
    hImages = findobj(hAxes,'-depth',1,'Type','image');
    if isempty(hImages)
        imagesc(hAxes,imageData);
    else
        if numel(hImages) > 1
            delete(hImages(2:end));
        end
        set(hImages(1),'CData',imageData);
        set(hAxes,'CLimMode','auto');
    end
    axis(hAxes,'image');
    axis(hAxes,'off');
    colormap(hAxes,gray(256));
    title(titleStr);
end

function [axialSlice,sagittalSlice,coronalSlice] = selectDisplaySlices(state,xIdx,yIdx,zIdx)
    switch state.displayMode
        case 1
            sourceVolume = state.volumeRSS;
            sliceTransform = [];
        case 2
            sourceVolume = state.volumeSOM;
            sliceTransform = [];
        case 3
            sourceVolume = state.volumeComplex;
            sliceTransform = @abs;
        case 4
            sourceVolume = state.volumeComplex;
            sliceTransform = @angle;
        case 5
            sourceVolume = state.volumeComplex;
            sliceTransform = @real;
        otherwise
            sourceVolume = state.volumeComplex;
            sliceTransform = @imag;
    end

    axialSlice = extractDisplaySlice(sourceVolume,3,zIdx,sliceTransform);
    sagittalSlice = extractDisplaySlice(sourceVolume,1,xIdx,sliceTransform);
    coronalSlice = extractDisplaySlice(sourceVolume,2,yIdx,sliceTransform);
end

function sliceData = extractDisplaySlice(volume,dimension,index,sliceTransform)
    switch dimension
        case 1
            sliceData = squeeze(volume(index,:,:));
        case 2
            sliceData = squeeze(volume(:,index,:));
        otherwise
            sliceData = squeeze(volume(:,:,index));
    end

    sliceData = rot90(sliceData);
    if ~isempty(sliceTransform)
        sliceData = sliceTransform(sliceData);
    end
end

function kspaceIdx = mapImageSliceToKSpace(imageIdx,imageSize,kspaceSize)
    if imageSize <= 1
        kspaceIdx = round((kspaceSize + 1) / 2);
    else
        kspaceIdx = round((imageIdx - 1) / (imageSize - 1) * (kspaceSize - 1)) + 1;
    end
    kspaceIdx = min(max(kspaceIdx,1),kspaceSize);
end

function updateSliceControls(hFig)
    state = guidata(hFig);
    handles = state.handles;
    dims = getVolumeDims(state.volumeRSS);

    configureSlider(handles.xSlider,dims(1),state.sliceIndex(1));
    configureSlider(handles.ySlider,dims(2),state.sliceIndex(2));
    configureSlider(handles.zSlider,dims(3),state.sliceIndex(3));
end

function configureSlider(hSlider,maxValue,currentValue)
    maxValue = max(1,round(maxValue));
    currentValue = min(max(1,round(currentValue)),maxValue);

    if maxValue == 1
        sliderStep = [1 1];
    else
        sliderStep = [1/(maxValue-1), min(10/(maxValue-1),1)];
    end

    set(hSlider,'Enable','on','Min',1,'Max',maxValue,'Value',currentValue,...
        'SliderStep',sliderStep);
end

function updateInfoText(hFig)
    state = guidata(hFig);
    protocol = state.protocol;
    info = state.reconInfo;
    [~,protName,protExt] = fileparts(protocol.ProtocolFile);
    noiseSummary = formatNoiseSummary(state);

    if strcmpi(state.reconMode,'cartesian')
        infoLines = {
            ['Sequence: ',protocol.SequenceType],...
            ['FOV / MatSize: ',num2str(protocol.FOV),' / ',num2str(protocol.MatSize)],...
            sprintf('Cartesian Matrix: %s | Rx: %d',num2str(info.matSize),info.numCoils),...
            ['Files: ',protName,protExt],...
            noiseSummary...
            };
        set(state.handles.infoText,'String',infoLines);
        set(state.handles.paramText,'String','Cartesian FFT reconstruction');
        return;
    end

    [~,trajName,trajExt] = fileparts(protocol.TrajectoryFile);
    recommendedSpokes = estimateRecommendedSpokes(info,info.retainedMaxRadius);
    spokeRatio = info.numSpokes / recommendedSpokes;

    infoLines = {
        ['Sequence: ',protocol.SequenceType],...
        ['FOV / MatSize: ',num2str(protocol.FOV),' / ',num2str(protocol.MatSize)],...
        ['Readout x Spokes: ',num2str([info.samplesPerSpoke, info.numSpokes])],...
        sprintf('Spoke density: %d / %d (%.2f%% of rough Nyquist)',...
            info.numSpokes,recommendedSpokes,100*spokeRatio),...
        sprintf('Recon: %d^3 | %.4g mm voxels | Noise Scale: %g',...
            info.reconSize,1000*info.voxelSizeMeters(1),state.noiseScale),...
        ['Files: ',protName,protExt,' | ',trajName,trajExt],...
        noiseSummary...
        };
    set(state.handles.infoText,'String',infoLines);
    set(state.handles.paramText,'String','r^2 DCF, Kaiser-Bessel width 4, 2x oversampling');
end

function noiseSummary = formatNoiseSummary(state)
    if ~state.noiseLoaded || isempty(state.noiseFiles)
        noiseSummary = 'Noise: none loaded';
    elseif numel(state.noiseFiles) == 1
        noiseSummary = ['Noise: ',state.noiseFiles{1}];
    else
        noiseSummary = sprintf('Noise: %d files loaded for %d Rx channels',...
            numel(state.noiseFiles),state.loadedNRx);
    end
end

function recommendedSpokes = estimateRecommendedSpokes(info,radius)
    kSpaceDiameter = 2 * radius * max(info.fovMeters);
    recommendedSpokes = max(1,round(pi * kSpaceDiameter^2));
end

function plotCartesianTrajectoryFigure(traj,matSize,orientation)
    [~,orientationIndex] = ismember(orientation,{'Axial','Sagittal','Coronal'});
    modelAxes = cartesianAxes(orientationIndex,false);
    inPlane = sort(modelAxes(1:2));
    x = reshape(traj(:,inPlane(1)),matSize);
    y = reshape(traj(:,inPlane(2)),matSize);
    % A NaN after each readout keeps the plotted lines within that readout.
    lineX = [x; nan(1,matSize(2))];
    lineY = [y; nan(1,matSize(2))];

    hFig = figure('Visible','on','MenuBar','none','Name','2D Cartesian Trajectory',...
        'NumberTitle','off','Position',[100 100 820 700],'Color',[1 1 1],...
        'Toolbar','figure');
    movegui(hFig,'center');
    hAxes = axes('Parent',hFig);
    plot(hAxes,lineX(:),lineY(:),'-','Color',[.55 .60 .67]);
    hold(hAxes,'on');
    plot(hAxes,x(:),y(:),'.','Color',[0 .32 .68]);
    hold(hAxes,'off');
    grid(hAxes,'on');
    axis(hAxes,'equal');
    axisNames = 'xyz';
    xlabel(hAxes,sprintf('k_%c (cycles/m)',axisNames(inPlane(1))));
    ylabel(hAxes,sprintf('k_%c (cycles/m)',axisNames(inPlane(2))));
    title(hAxes,sprintf('Loaded .ktrj (%d samples, %d readouts)',numel(x),matSize(2)));
end

function plotTrajectoryFigure(traj,info)
    hFig = figure('Visible','on','MenuBar','none','Name','3D Radial Trajectory',...
        'NumberTitle','off','Position',[100 100 1180 860],'Color',[1 1 1],...
        'Toolbar','figure');
    movegui(hFig,'center');

    % Preserve the exported physical origin; do not recenter midpoint samples.

    numSpokes = size(traj,2);
    numPreview = min(numSpokes,64);
    previewIdx = unique(round(linspace(1,numSpokes,numPreview)));
    previewTraj = traj(:,previewIdx,:);
    colors = lines(max(numel(previewIdx),1));

    h3 = subplot(2,2,[1 3],'Parent',hFig);
    hold(h3,'on');
    for idx = 1:numel(previewIdx)
        plot3(h3,previewTraj(:,idx,1),previewTraj(:,idx,2),previewTraj(:,idx,3),'.',...
            'Color',colors(idx,:),'MarkerSize',8);
    end
    plot3(h3,0,0,0,'ko','MarkerFaceColor','k','MarkerSize',5);
    hold(h3,'off');
    grid(h3,'on');
    axis(h3,'equal');
    xlabel(h3,'k_x (cycles/m)');
    ylabel(h3,'k_y (cycles/m)');
    zlabel(h3,'k_z (cycles/m)');
    title(h3,sprintf('Loaded .ktrj Preview (%d of %d spokes)',numel(previewIdx),numSpokes));
    view(h3,35,25);

    radius = sqrt(sum(previewTraj.^2,3));
    hRadius = subplot(2,2,2,'Parent',hFig);
    plot(hRadius,radius,'.','MarkerSize',8);
    xlabel(hRadius,'Sample Index');
    ylabel(hRadius,'|k| (cycles/m)');
    title(hRadius,'Radius Along Preview Spokes');
    grid(hRadius,'on');

    hInfo = subplot(2,2,4,'Parent',hFig);
    axis(hInfo,'off');
    recommendedSpokes = estimateRecommendedSpokes(info,info.maxRadius);
    infoLines = {
        sprintf('Samples per spoke: %d',info.samplesPerSpoke),...
        sprintf('Loaded spokes: %d',info.numSpokes),...
        sprintf('Rough Nyquist spokes: %d',recommendedSpokes),...
        sprintf('Sampling fraction: %.2f%%',100 * info.numSpokes / recommendedSpokes),...
        'Exported k-space origin: [0 0 0] cycles/m',...
        sprintf('Max |k|: %0.4g',info.maxRadius)...
        };
    text(0,1,infoLines,'Parent',hInfo,'VerticalAlignment','top');
end

function setStatus(hFig,message)
    state = guidata(hFig);
    set(state.handles.statusText,'String',{message});
    drawnow;
end

function beginBusyState(hFig,message)
    if ~isgraphics(hFig,'figure')
        return;
    end

    state = guidata(hFig);
    if nargin < 2 || isempty(message)
        message = 'Working...';
    end

    state.busyDepth = state.busyDepth + 1;
    guidata(hFig,state);
    set(state.handles.busyText,'String',message);
    set(state.handles.busyOverlay,'Visible','on');
    set(hFig,'Pointer','watch','Name',[state.defaultFigureName,' - ',message]);
    drawnow;
end

function updateBusyState(hFig,message)
    if ~isgraphics(hFig,'figure')
        return;
    end

    state = guidata(hFig);
    if nargin < 2 || isempty(message) || state.busyDepth == 0
        return;
    end

    set(state.handles.busyText,'String',message);
    set(hFig,'Pointer','watch','Name',[state.defaultFigureName,' - ',message]);
    drawnow;
end

function endBusyState(hFig)
    if ~isgraphics(hFig,'figure')
        return;
    end

    state = guidata(hFig);
    if state.busyDepth == 0
        return;
    end

    state.busyDepth = state.busyDepth - 1;
    if state.busyDepth > 0
        guidata(hFig,state);
        return;
    end

    guidata(hFig,state);
    set(state.handles.busyOverlay,'Visible','off');
    set(state.handles.busyText,'String','');
    set(hFig,'Pointer','arrow','Name',state.defaultFigureName);
    drawnow;
end

function message = stripStatusPrefix(message)
    prefix = 'Status: ';
    if strncmp(message,prefix,numel(prefix))
        message = message((numel(prefix)+1):end);
    end
end

%% File selection and input parsing

function [selectedFiles,dataPath] = selectSignalFiles(nRx)
    repositoryPath = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    initialPath = fullfile(repositoryPath,'protocols','*.ksig');
    [selectedFiles,dataPath] = selectComplexFiles(nRx,'*.ksig','OPEN: K-space Data',initialPath);
end

function [selectedFiles,dataPath] = selectNoiseFiles(nRx,initialPath)
    if nargin < 2
        initialPath = '';
    end
    [selectedFiles,dataPath] = selectComplexFiles(nRx,'*.nois','OPEN: Noise',initialPath);
end

function [selectedFiles,dataPath] = selectComplexFiles(nRx,fileSpec,dialogTitle,initialPath)
    dataPath = '';
    selectedFiles = {};

    if nargin < 4 || isempty(initialPath)
        dialogPath = fileSpec;
    else
        dialogPath = initialPath;
    end

    if nRx == 1
        [fileName,pathName,index] = uigetfile(fileSpec,dialogTitle,dialogPath);
        if isequal(index,0)
            return;
        end
        selectedFiles = {fileName};
        dataPath = pathName;
    else
        [fileNames,pathName,index] = uigetfile(fileSpec,dialogTitle,dialogPath,...
            'Multiselect','on');
        if isequal(index,0)
            return;
        end
        if ischar(fileNames)
            fileNames = {fileNames};
        end
        if numel(fileNames) ~= nRx
            error('Check the number of Rx channels and selected files.');
        end
        selectedFiles = sortSignalFiles(fileNames);
        dataPath = pathName;
    end
end

function sortedFiles = sortSignalFiles(fileNames)
    sortKeys = zeros(numel(fileNames),1);
    for idx = 1:numel(fileNames)
        [~,baseName] = fileparts(fileNames{idx});
        token = regexp(baseName,'(\d+)$','tokens','once');
        if isempty(token)
            sortKeys(idx) = idx;
        else
            sortKeys(idx) = str2double(token{1});
        end
    end
    [~,order] = sort(sortKeys);
    sortedFiles = fileNames(order);
end

function selectedFiles = discoverNumberedSignalFiles(dataPath,firstFile,numRx)
    [~,baseName,extension] = fileparts(firstFile);
    token = regexp(baseName,'^(.*?)(\d+)$','tokens','once');
    if isempty(token)
        baseRoot = baseName;
    else
        baseRoot = token{1};
    end

    selectedFiles = cell(1,numRx);
    missingFiles = {};
    for idx = 1:numRx
        candidate = [baseRoot,num2str(idx),extension];
        selectedFiles{idx} = candidate;
        if exist(fullfile(dataPath,candidate),'file') ~= 2
            missingFiles{end+1} = candidate; %#ok<AGROW>
        end
    end

    if ~isempty(missingFiles)
        error('Could not find all numbered Rx signal files. Missing: %s',strjoin(missingFiles,', '));
    end

    selectedFiles = sortSignalFiles(selectedFiles);
end

function signalData = loadSignalDataFiles(dataPath,selectedFiles)
    signalData = loadComplexDataFiles(dataPath,selectedFiles,'K-space',[]);
end

function noiseData = loadNoiseDataFiles(dataPath,selectedFiles,expectedSamples)
    noiseData = loadComplexDataFiles(dataPath,selectedFiles,'noise',expectedSamples);
end

function complexDataMatrix = loadComplexDataFiles(dataPath,selectedFiles,dataLabel,expectedSamples)
    for idx = 1:numel(selectedFiles)
        fileName = fullfile(dataPath,selectedFiles{idx});
        fid = fopen(fileName,'r');
        if fid == -1
            error(['Unable to open ',dataLabel,' file: ',fileName]);
        end
        raw = fread(fid,[2,Inf],'float32');
        fclose(fid);

        complexData = raw(1,:) + 1i*raw(2,:);
        logRadialReco('Read %s file %d/%d: %s raw=%s complexSamples=%d',...
            dataLabel,idx,numel(selectedFiles),fileName,reconstructionSizeString(raw),numel(complexData));
        if idx == 1
            complexDataMatrix = zeros(numel(complexData),numel(selectedFiles));
        elseif size(complexDataMatrix,1) ~= numel(complexData)
            error(['All selected ',dataLabel,' files must have the same sample count.']);
        end

        if nargin >= 4 && ~isempty(expectedSamples) && numel(complexData) ~= expectedSamples
            error(['Selected ',dataLabel,' sample count does not match the loaded .ksig data.']);
        end

        complexDataMatrix(:,idx) = complexData(:);
    end
end

function trajFlat = loadTrajectoryFile(fileName,totalSamples)
    fid = fopen(fileName,'r');
    if fid == -1
        error(['Unable to open trajectory file: ',fileName]);
    end
    raw = fread(fid,3*totalSamples,'float32');
    extraByte = fread(fid,1,'uint8');
    fclose(fid);

    if numel(raw) ~= 3*totalSamples || ~isempty(extraByte)
        error('Trajectory sample count does not match the selected .ksig data.');
    end
    if any(~isfinite(raw))
        error('Trajectory file contains nonfinite coordinates.');
    end
    trajFlat = reshape(raw,3,[]).';
    logRadialReco('Read trajectory file: %s trajFlat=%s',fileName,reconstructionSizeString(trajFlat));
end

function protocol = parseRadialProtocolFile(protFileName)
    protocol.SequenceType = 'Unknown';
    protocol.FOV = [0 0];
    protocol.MatSize = [0 0];
    protocol.RadialResolutionMm = [];
    protocol.NumRx = 1;
    protocol.ProtocolFile = protFileName;
    protocol.TrajectoryFile = '';
    protocol.SliceOrientation = 'Axial';
    protocol.PEDirection = 'P--A';
    protocol.FOVOffset = [0 0 0];
    protocol.ModelSpacing = [NaN NaN NaN];

    fid = fopen(protFileName,'r');
    if fid == -1
        error(['Unable to open protocol file: ',protFileName]);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    protLine = fgetl(fid);
    while ischar(protLine)
        key = strtrim(protLine);
        switch key
            case 'Sequence Type:'
                protocol.SequenceType = strtrim(fgetl(fid));

            case 'FOV(mm)'
                protocol.FOV = sscanf(fgetl(fid),'%f').';

            case 'MatSize:'
                protocol.MatSize = sscanf(fgetl(fid),'%f').';

            case 'Radial Acquisition Resolution(mm):'
                protocol.RadialResolutionMm = parseRadialResolutionMm(fgetl(fid));

            case '# Rx:'
                protocol.NumRx = str2double(strtrim(fgetl(fid)));

            case 'KMap Filename:'
                protocol.TrajectoryFile = strtrim(fgetl(fid));

            case 'Slice Orientation:'
                protocol.SliceOrientation = strtrim(fgetl(fid));

            case 'PE Direct:'
                protocol.PEDirection = strtrim(fgetl(fid));

            case 'FOV Offset:'
                protocol.FOVOffset = readProtocolXYZ(fid,'FOV Offset');

            case 'Model Res.:'
                protocol.ModelSpacing = readProtocolXYZ(fid,'Model Res.');
        end
        protLine = fgetl(fid);
    end

    if isempty(protocol.SequenceType)
        protocol.SequenceType = 'Unknown';
    end
end

function values = readProtocolXYZ(fid,fieldName)
    values = zeros(1,3);
    for idx = 1:3
        labelLine = fgetl(fid);
        valueLine = fgetl(fid);
        if ~ischar(labelLine) || ~ischar(valueLine)
            error('Protocol field "%s" is incomplete.',fieldName);
        end
        values(idx) = str2double(strtrim(valueLine));
        if ~isfinite(values(idx))
            error('Protocol field "%s" contains a nonnumeric value.',fieldName);
        end
    end
end

%% Radial reconstruction

function [samplesPerSpoke,numSpokes] = inferRadialDimensions(protocol,totalSamples)
    matSize = protocol.MatSize;
    if isempty(matSize)
        error('Protocol file does not define MatSize.');
    end

    logRadialReco('Inferring dimensions from MatSize=%s totalSamples=%d',mat2str(matSize),totalSamples);

    samplesPerSpoke = max(1,round(matSize(1)));
    if mod(totalSamples,samplesPerSpoke) ~= 0
        if numel(matSize) > 1 && mod(totalSamples,max(1,round(matSize(2)))) == 0
            samplesPerSpoke = max(1,round(matSize(2)));
        else
            error('Unable to infer readout samples per spoke from protocol MatSize.');
        end
    end

    numSpokes = round(totalSamples / samplesPerSpoke);
end

function spokeData = reshapeSignalData(signalData,samplesPerSpoke,numSpokes)
    inferredNumSpokes = validateSpokeCount(size(signalData,1),samplesPerSpoke,numSpokes,...
        'K-space');
    numCoils = size(signalData,2);
    logRadialReco('Reshaping signalData %s to [%d %d %d]',...
        reconstructionSizeString(signalData),samplesPerSpoke,inferredNumSpokes,numCoils);
    spokeData = reshape(signalData,samplesPerSpoke,inferredNumSpokes,numCoils);
end

function traj = reshapeTrajectoryData(trajFlat,samplesPerSpoke,numSpokes)
    inferredNumSpokes = validateSpokeCount(size(trajFlat,1),samplesPerSpoke,numSpokes,...
        'Trajectory');
    logRadialReco('Reshaping trajFlat %s to [%d %d 3]',...
        reconstructionSizeString(trajFlat),samplesPerSpoke,inferredNumSpokes);
    traj = reshape(trajFlat,samplesPerSpoke,inferredNumSpokes,3);
end

function inferredNumSpokes = validateSpokeCount(totalSamples,samplesPerSpoke,numSpokes,dataLabel)
    logRadialReco('Validating %s samples: total=%d samplesPerSpoke=%d protocolNumSpokes=%d',...
        dataLabel,totalSamples,samplesPerSpoke,numSpokes);
    if mod(totalSamples,samplesPerSpoke) ~= 0
        error(['Selected ',dataLabel,' sample count does not divide evenly into the inferred ',...
            'samples per spoke from the protocol MatSize.']);
    end

    inferredNumSpokes = totalSamples / samplesPerSpoke;
    if nargin >= 3 && ~isempty(numSpokes) && inferredNumSpokes ~= numSpokes
        error([dataLabel,' sample count implies ',num2str(inferredNumSpokes),...
            ' spokes, but the protocol MatSize implies ',num2str(numSpokes),'.']);
    end
end

function warningText = validateCenterOutTrajectory(traj)
    % Preserve the exported physical origin; do not recenter midpoint samples.
    radius = sqrt(sum(traj.^2,3));
    maxRadius = max(radius(:));

    if maxRadius <= 0
        warningText = 'Trajectory radius is zero. Check the selected .ktrj file.';
        return;
    end

    startFraction = median(radius(1,:)) / maxRadius;
    radiusDiff = diff(radius,1,1);
    if isempty(radiusDiff)
        monotonicFraction = 1;
    else
        monotonicFraction = mean(radiusDiff(:) >= -1e-6);
    end
    warningParts = {};

    if startFraction > 0.15
        warningParts{end+1} = 'The first ADC sample is not close to k-space center.'; %#ok<AGROW>
    end
    if monotonicFraction < 0.9
        warningParts{end+1} = 'The trajectory radius does not increase monotonically along most spokes.'; %#ok<AGROW>
    end

    if isempty(warningParts)
        warningText = '';
    else
        warningText = strjoin(warningParts,sprintf('\n'));
    end
end

%% Companion-file resolution

function protFileName = resolveCompanionProtocolFileRadial(dataFileName,selectedFiles)
    [dataDir,dataBase] = fileparts(dataFileName);
    candidateBases = {dataBase};
    selectionBase = getSelectedFileBaseRadial(selectedFiles);

    if ~isempty(selectionBase) && ~any(strcmp(candidateBases,selectionBase))
        candidateBases{end+1} = selectionBase; %#ok<AGROW>
    end

    protFileName = fullfile(dataDir,[candidateBases{1},'.prot']);
    for idx = 1:numel(candidateBases)
        candidateFile = fullfile(dataDir,[candidateBases{idx},'.prot']);
        if exist(candidateFile,'file') == 2
            protFileName = candidateFile;
            return;
        end
    end

    parentDir = fileparts(dataDir);
    if ~isempty(parentDir)
        for idx = 1:numel(candidateBases)
            candidateFile = fullfile(parentDir,[candidateBases{idx},'.prot']);
            if exist(candidateFile,'file') == 2
                protFileName = candidateFile;
                return;
            end
        end
    end

    protFiles = dir(fullfile(dataDir,'*.prot'));
    if numel(protFiles) == 1
        protFileName = fullfile(dataDir,protFiles(1).name);
    end
end

function trajFileName = resolveCompanionTrajectoryFile(dataFileName,selectedFiles)
    [dataDir,dataBase] = fileparts(dataFileName);
    candidateBases = {dataBase};
    selectionBase = getSelectedFileBaseRadial(selectedFiles);

    if ~isempty(selectionBase) && ~any(strcmp(candidateBases,selectionBase))
        candidateBases{end+1} = selectionBase; %#ok<AGROW>
    end

    trajFileName = fullfile(dataDir,[candidateBases{1},'.ktrj']);
    for idx = 1:numel(candidateBases)
        candidateFile = fullfile(dataDir,[candidateBases{idx},'.ktrj']);
        if exist(candidateFile,'file') == 2
            trajFileName = candidateFile;
            return;
        end
    end

    parentDir = fileparts(dataDir);
    if ~isempty(parentDir)
        for idx = 1:numel(candidateBases)
            candidateFile = fullfile(parentDir,[candidateBases{idx},'.ktrj']);
            if exist(candidateFile,'file') == 2
                trajFileName = candidateFile;
                return;
            end
        end
    end

    trajFiles = dir(fullfile(dataDir,'*.ktrj'));
    if numel(trajFiles) == 1
        trajFileName = fullfile(dataDir,trajFiles(1).name);
    end
end

function selectionBase = getSelectedFileBaseRadial(selectedFiles)
    if isempty(selectedFiles)
        selectionBase = '';
        return;
    end

    if ischar(selectedFiles)
        selectedFiles = {selectedFiles};
    end

    [~,selectionBase] = fileparts(selectedFiles{1});
    for idx = 2:numel(selectedFiles)
        [~,nextBase] = fileparts(selectedFiles{idx});
        maxLength = min(length(selectionBase),length(nextBase));
        prefixLength = 0;

        while prefixLength < maxLength && selectionBase(prefixLength+1) == nextBase(prefixLength+1)
            prefixLength = prefixLength + 1;
        end

        selectionBase = selectionBase(1:prefixLength);
        if isempty(selectionBase)
            return;
        end
    end
end

%% Logging and small utilities

function setRadialRecoLoggingEnabled(enabled)
    setappdata(0,'reconstructionViewer_logging_enabled',logical(enabled));
end

function enabled = isRadialRecoLoggingEnabled()
    if isappdata(0,'reconstructionViewer_logging_enabled')
        enabled = logical(getappdata(0,'reconstructionViewer_logging_enabled'));
    else
        enabled = true;
        setRadialRecoLoggingEnabled(enabled);
    end
end

function logRadialReco(message,varargin)
    if ~isRadialRecoLoggingEnabled()
        return;
    end

    timeStamp = datestr(now,'HH:MM:SS.FFF');
    if nargin > 1
        fprintf('[reconstructionViewer %s] %s\n',timeStamp,sprintf(message,varargin{:}));
    else
        fprintf('[reconstructionViewer %s] %s\n',timeStamp,message);
    end
end

function logException(ME)
    if ~isRadialRecoLoggingEnabled()
        return;
    end

    if isempty(ME.stack)
        fprintf(2,'[reconstructionViewer] No stack information available.\n');
        return;
    end

    for idx = 1:numel(ME.stack)
        fprintf(2,'[reconstructionViewer] Stack %d: %s (line %d)\n',idx,...
            ME.stack(idx).name,ME.stack(idx).line);
    end
end

function state = onOff(condition)
    if condition
        state = 'on';
    else
        state = 'off';
    end
end
