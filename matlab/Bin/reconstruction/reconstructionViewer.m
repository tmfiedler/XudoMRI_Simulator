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
        'DataPath',char(parser.Results.DataPath));
end

function hFig = createReconstructionFigure()

    repositoryPath = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    simulatorVersion = readRepositoryVersion(fullfile(repositoryPath,'VERSION'));
    hFig = figure('Name','Reconstruction','NumberTitle','off',...
        'MenuBar','none','Toolbar','figure','Color',[1 1 1],...
        'Units','pixels','Position',[100 100 1400 920]);
    movegui(hFig,'center');

    hControlViewport = uipanel('Parent',hFig,'Units','normalized','BorderType','none',...
        'Position',[0.004 0.007 0.185 0.986],'BackgroundColor',[1 1 1]);
    hControl = uipanel('Parent',hControlViewport,'Title','Controls','Units','normalized',...
        'Position',[0 0 1 1],'BackgroundColor',[1 1 1],...
        'BorderType','line','HighlightColor',[0.55 0.55 0.55]);
    hControlScroll = uicontrol(hControlViewport,'Style','slider','Units','pixels',...
        'Min',0,'Max',1,'Value',1,'Visible','off','TooltipString','Scroll Reco controls');

    actionHeight = 0.026;
    loadButtonHeight = 0.032;
    labelHeight = 0.021;
    sliderHeight = 0.018;
    labelInset = (actionHeight-labelHeight)/2;
    sliderInset = (labelHeight-sliderHeight)/2;
    displayY = 0.922;

    handles.loadButton = uicontrol(hControl,'Style','pushbutton',...
        'String','Load Signal (.ksig)','Units','normalized','FontWeight','bold',...
        'Position',[0.025 0.958 0.455 loadButtonHeight],'Callback',@loadDataCallback);

    handles.loadNoiseButton = uicontrol(hControl,'Style','pushbutton',...
        'String','Load Noise (.nois)','Units','normalized','FontWeight','bold',...
        'Position',[0.520 0.958 0.455 loadButtonHeight],'Enable','off',...
        'Callback',@loadNoiseCallback);

    uicontrol(hControl,'Style','text','String','Display','Units','normalized',...
        'Position',[0.025 displayY+labelInset 0.165 labelHeight],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left','FontSize',8);
    handles.displayPopup = uicontrol(hControl,'Style','popupmenu',...
        'String',{'RSS Mag.';'Sum Mag.';'Coh. Mag.';...
                   'Coh. Phase';'Coh. Real';'Coh. Imag.'},...
        'Value',1,'Units','normalized','Position',[0.195 displayY 0.40 actionHeight],...
        'BackgroundColor',[1 1 1],'FontSize',8,'Callback',@displayModeCallback);

    uicontrol(hControl,'Style','text','String','Noise Scale','Units','normalized',...
        'Position',[0.604 displayY+labelInset 0.255 labelHeight],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left','FontSize',8);
    handles.noiseScaleEdit = uicontrol(hControl,'Style','edit','String','0',...
        'Units','normalized','Position',[0.863 displayY 0.112 actionHeight],...
        'BackgroundColor',[1 1 1],'Enable','off',...
        'Callback',@noiseScaleCallback);

    topControls = hControl.Children;
    handles.infoText = uicontrol(hControl,'Style','listbox',...
        'String',{'No data loaded.'},'Units','normalized',...
        'Position',[0.025 0.29 0.95 0.59],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');

    sagittalLabel = uicontrol(hControl,'Style','text','String','Sagittal Slice','Units','normalized',...
        'Position',[0.025 0.257 0.40 labelHeight],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.xSlider = uicontrol(hControl,'Style','slider','Units','normalized',...
        'Position',[0.025 0.235+sliderInset 0.75 sliderHeight],'Min',1,'Max',2,'Value',1,...
        'SliderStep',[1 1],'Enable','off','Tag','x','UserData',1,...
        'Callback',@sliceSliderCallback);
    handles.xValue = uicontrol(hControl,'Style','text','String','1','Units','normalized',...
        'Position',[0.79 0.235 0.085 labelHeight],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');

    uicontrol(hControl,'Style','text','String','Coronal Slice','Units','normalized',...
        'Position',[0.025 0.203 0.40 labelHeight],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.ySlider = uicontrol(hControl,'Style','slider','Units','normalized',...
        'Position',[0.025 0.181+sliderInset 0.75 sliderHeight],'Min',1,'Max',2,'Value',1,...
        'SliderStep',[1 1],'Enable','off','Tag','y','UserData',2,...
        'Callback',@sliceSliderCallback);
    handles.yValue = uicontrol(hControl,'Style','text','String','1','Units','normalized',...
        'Position',[0.79 0.181 0.085 labelHeight],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');

    uicontrol(hControl,'Style','text','String','Axial Slice','Units','normalized',...
        'Position',[0.025 0.149 0.40 labelHeight],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.zSlider = uicontrol(hControl,'Style','slider','Units','normalized',...
        'Position',[0.025 0.127+sliderInset 0.75 sliderHeight],'Min',1,'Max',2,'Value',1,...
        'SliderStep',[1 1],'Enable','off','Tag','z','UserData',3,...
        'Callback',@sliceSliderCallback);
    handles.zValue = uicontrol(hControl,'Style','text','String','1','Units','normalized',...
        'Position',[0.79 0.127 0.085 labelHeight],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');

    sliceValues = [handles.xValue handles.yValue handles.zValue];
    for column = 1:3
        rowY = sliceValues(column).Position(2);
        handles.rotateButtons(column) = uicontrol(hControl,'Style','pushbutton',...
            'String',char(8635),'FontName','Segoe UI Symbol','Units','normalized',...
            'Position',[0.882 rowY-labelInset 0.093 actionHeight],'Enable','off',...
            'TooltipString','Rotate image 90 degrees clockwise',...
            'UserData',column,'Callback',@rotateSliceCallback);
    end

    uicontrol(hControl,'Style','text','String','Export View','Units','normalized',...
        'Position',[0.025 0.102 0.33 labelHeight],'BackgroundColor',[1 1 1],...
        'HorizontalAlignment','left');
    handles.exportViewPopup = uicontrol(hControl,'Style','popupmenu',...
        'String',{'Sagittal';'Coronal';'Axial'},'Value',1,...
        'Units','normalized','Position',[0.025 0.072 0.54 actionHeight],...
        'BackgroundColor',[1 1 1],'Enable','off');
    handles.exportViewButton = uicontrol(hControl,'Style','pushbutton',...
        'String','Export Pane','Units','normalized',...
        'Position',[0.645 0.072 0.33 actionHeight],'Enable','off',...
        'Callback',@exportViewPortCallback);

    trajectoryY = 0.040;
    bottomActionY = 0.008;
    handles.trajectoryButton = uicontrol(hControl,'Style','pushbutton',...
        'String','View Trajectory','Units','normalized',...
        'Position',[0.025 trajectoryY 0.44 actionHeight],'Enable','off',...
        'Callback',@viewTrajectoryCallback);

    uicontrol(hControl,'Style','text','String','Matrix','Units','normalized',...
        'Position',[0.65 trajectoryY 0.19 labelHeight],'BackgroundColor',[1 1 1]);
    handles.reconMatrixEdit = uicontrol(hControl,'Style','edit',...
        'Units','normalized','Position',[0.855 trajectoryY 0.12 actionHeight],'BackgroundColor',[1 1 1],...
        'Enable','off','Tag','RadialReconstructionMatrix','Callback',@reconMatrixCallback,...
        'TooltipString','Voxels per axis for 3D radial data. Clear to restore the protocol default.');

    handles.snrMapButton = uicontrol(hControl,'Style','pushbutton',...
        'String','SNR Map','Units','normalized',...
        'Position',[0.025 bottomActionY 0.43 actionHeight],'Enable','off',...
        'TooltipString','Requires a second, different simulated .nois realization.',...
        'Callback',@snrMapCallback);
    handles.globalScaleCheckbox = uicontrol(hControl,'Style','checkbox',...
        'String','Global Scale','Units','normalized',...
        'Position',[0.58 bottomActionY+labelInset 0.395 labelHeight],...
        'BackgroundColor',[1 1 1],...
        'Value',0,'Callback',@globalScaleCallback);

    hPreview = uipanel('Parent',hFig,'Units','pixels','BorderType','none',...
        'BackgroundColor',[1 1 1]);
    handles.sagittalAxes = axes('Parent',hPreview,'Units','normalized',...
        'Position',[0 0.54 0.30 0.38]);
    handles.coronalAxes = axes('Parent',hPreview,'Units','normalized',...
        'Position',[0.35 0.54 0.30 0.38]);
    handles.axialAxes = axes('Parent',hPreview,'Units','normalized',...
        'Position',[0.70 0.54 0.30 0.38]);
    for column = 1:3
        handles.kspaceAxes(column) = axes('Parent',hPreview,'Units','normalized',...
            'Position',[(column-1)*0.35 0.08 0.30 0.38],'Visible','off');
    end

    hVersion = uicontrol(hPreview,'Style','text','String',['v' simulatorVersion],...
        'Units','pixels','HorizontalAlignment','right','FontUnits','pixels','FontSize',10,...
        'ForegroundColor',[.4 .4 .4],'BackgroundColor','white','Tag','SimulatorVersion');

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
    state.loadedNRx = 1;
    state.displayMode = 1;
    state.globalImageLimits = [];
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
    state.sliceQuarterTurns = [0 0 0];
    state.resetSliceIndex = false;

    guidata(hFig,state);
    configureViewerResize(hFig,hControl,hControlScroll,hPreview,hVersion,topControls,...
        handles.infoText,sagittalLabel);
    refreshDisplay(hFig,true);
end

function configureViewerResize(hFig,hControl,hControlScroll,hPreview,hVersion,topControls,...
        infoBox,sagittalLabel)
    viewport = hControl.Parent;
    set(viewport,'Units','pixels');
    set(hControl,'Units','pixels');
    set(hControl.Children,'Units','pixels');
    controlPosition = viewport.Position;
    topPositions = vertcat(topControls.Position);
    spacing = 5;
    infoPosition = infoBox.Position;
    infoPosition(2) = sum(sagittalLabel.Position([2 4])) + spacing;
    infoPosition(4) = min(topPositions(:,2)) - spacing - infoPosition(2);
    layout = @(~,~) resizeViewer(hFig,hControl,hControlScroll,hPreview,hVersion,...
        controlPosition,topControls,topPositions,infoBox,infoPosition);
    set(hFig,'SizeChangedFcn',layout);
    set(hControlScroll,'Callback',layout);
    layout(hFig,[]);
end

function resizeViewer(hFig,hControl,hControlScroll,hPreview,hVersion,controlPosition,...
        topControls,topPositions,infoBox,infoPosition)
    position = hFig.Position;
    width = position(3);
    height = position(4);
    inset = controlPosition(2);
    scrollbarWidth = 16;
    previewLeft = controlPosition(1) + controlPosition(3) + scrollbarWidth + inset;
    minWidth = previewLeft + 320 + inset;
    if width < minWidth
        position(3) = ceil(minWidth);
        hFig.Position = position;
        width = position(3);
    end

    verticalInset = min(inset,floor((height-1)/2));
    viewportHeight = height - 2*verticalInset;
    borderInset = min(2,floor((viewportHeight-1)/2));
    visibleHeight = viewportHeight - 2*borderInset;
    minInfoHeight = 88;
    contentHeight = max(visibleHeight,controlPosition(4) - infoPosition(4) + minInfoHeight);
    overflow = contentHeight - visibleHeight;
    controlWidth = controlPosition(3);
    hControl.Parent.Position = [controlPosition(1) verticalInset ...
        controlWidth + scrollbarWidth viewportHeight];
    if overflow > 0
        step = min(1,24/overflow);
        page = min(1,viewportHeight/overflow);
        set(hControlScroll,'Position',[controlWidth+1 1 scrollbarWidth viewportHeight],...
            'SliderStep',[step max(step,page)],'Visible','on');
    else
        set(hControlScroll,'Visible','off','Value',1);
    end
    hControl.Position = [1 1+borderInset-overflow*hControlScroll.Value controlWidth contentHeight];
    heightChange = contentHeight - controlPosition(4);
    positions = topPositions;
    positions(:,2) = positions(:,2) + heightChange;
    set(topControls,{'Position'},num2cell(positions,2));
    infoPosition(4) = infoPosition(4) + heightChange;
    infoBox.Position = infoPosition;
    previewWidth = width - previewLeft - inset;
    hPreview.Position = [previewLeft 1 previewWidth height];
    hVersion.Position = [previewWidth-100 3 100 15];
end

function initializeAxes(hAxes,titleStr)
    updateAxesImage(hAxes,zeros(64),titleStr);
end

%% Signal and noise loading callbacks

function loadDataCallback(source,~)
    hFig = ancestor(source,'figure');

    try
        [selectedFiles,dataPath] = selectSignalFiles();
        if isempty(selectedFiles)
            logRadialReco('Data selection cancelled');
            return;
        end
        loadSelectedSignalData(hFig,selectedFiles,dataPath);
    catch ME
        logRadialReco('ERROR: %s',ME.message);
        logException(ME);
        errordlg(ME.message,'Reconstruction Error','modal');
    end
end

function loadSelectedSignalData(hFig,selectedFiles,dataPath)

    selectedFiles = sortSignalFiles(selectedFiles);
    logRadialReco('Selected data path: %s',dataPath);
    logRadialReco('Selected signal files: %s',strjoin(selectedFiles,', '));

    try
        dataFileName = fullfile(dataPath,selectedFiles{1});
        protFileName = resolveCompanionFile(dataFileName,selectedFiles,'.prot');
        logRadialReco('Resolved protocol file: %s',protFileName);

        if exist(protFileName,'file') ~= 2
            [protName,protPath,protIndex] = uigetfile('*.prot','OPEN: Protocol File',dataPath);
            if isequal(protIndex,0)
                logRadialReco('Protocol selection cancelled');
                return;
            end
            protFileName = fullfile(protPath,protName);
            logRadialReco('User-selected protocol file: %s',protFileName);
        end

        beginBusyState(hFig,'Loading reconstruction data...');
        loadBusyCleanup = onCleanup(@() endBusyState(hFig)); %#ok<NASGU>
        updateBusyState(hFig,'Reading protocol...');
        protocol = readReconstructionProtocol(protFileName);
        logRadialReco('Protocol sequence=%s MatSize=%s FOV=%s NumRx=%d',...
            protocol.SequenceType,mat2str(protocol.MatSize),mat2str(protocol.FOV),protocol.NumRx);

        if numel(selectedFiles) > protocol.NumRx
            error('Selected Rx channel count exceeds the protocol # Rx value.');
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
            trajFileName = resolveCompanionFile(dataFileName,selectedFiles,'.ktrj');
            if exist(trajFileName,'file') ~= 2
                [trajName,trajPath,trajIndex] = uigetfile('*.ktrj','OPEN: Trajectory File',dataPath);
                if isequal(trajIndex,0)
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

        warningText = '';
        if samplesPerSpoke > 1 || ~strcmpi(protocol.SequenceType,'DA_3DPR')
            warningText = validateCenterOutTrajectory(traj);
        end
        if ~isempty(warningText)
            logRadialReco('Trajectory warning: %s',strrep(warningText,sprintf('\n'),' | '));
            warndlg(warningText,'Trajectory Warning','modal');
        end

        state = initializeDataset(guidata(hFig),protocol,signalData,dataPath,selectedFiles);
        state.reconMode = 'radial';
        state.samplesPerSpoke = samplesPerSpoke;
        state.numSpokes = numSpokes;
        state.reconSize = reconSize;
        state.defaultReconSize = reconSize;
        state.trajectory = traj;
        state.cartesianMatSize = [];
        guidata(hFig,state);
        applyCurrentReconstruction(hFig,'Reconstructing 3D volume...');
    end
end

function loadCartesianReconstruction(hFig,protocol,signalData,dataPath,selectedFiles)
    updateBusyState(hFig,'Reconstructing Cartesian data...');
    [recon,matSize] = reconstructCartesianDataset(signalData,protocol);

    state = initializeDataset(guidata(hFig),protocol,signalData,dataPath,selectedFiles);
    state.reconMode = 'cartesian';
    state.cleanRecon = recon;
    state.samplesPerSpoke = [];
    state.numSpokes = [];
    state.reconSize = [];
    state.defaultReconSize = [];
    state.trajectory = [];
    state.cartesianMatSize = matSize;
    showReconstruction(hFig,state,recon);
end

function state = initializeDataset(state,protocol,signalData,dataPath,selectedFiles)
    state.protocol = protocol;
    state.signalDataClean = signalData;
    state.cleanRecon = [];
    state.reconContext = [];
    state.loadedNRx = size(signalData,2);
    state.noiseData = [];
    state.noiseLoaded = false;
    state.noiseScale = 0;
    state.signalFiles = selectedFiles;
    state.noiseFiles = {};
    state.dataPath = dataPath;
    state.sliceQuarterTurns = [0 0 0];
    state.resetSliceIndex = true;
end

%% Interactive controls

function displayModeCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    state.displayMode = get(source,'Value');
    state.globalImageLimits = [];
    guidata(hFig,state);
    refreshDisplay(hFig,false);
end

function globalScaleCallback(source,~)
    refreshDisplay(ancestor(source,'figure'),false);
end

function sliceSliderCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    if ~state.dataLoaded
        return;
    end

    state.sliceIndex(source.UserData) = round(source.Value);
    guidata(hFig,state);
    refreshDisplay(hFig,false);
end

function rotateSliceCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    column = source.UserData;
    state.sliceQuarterTurns(column) = mod(state.sliceQuarterTurns(column)+1,4);
    guidata(hFig,state);
    refreshDisplay(hFig,false);
end

function loadNoiseCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    if ~state.dataLoaded || isempty(state.signalDataClean)
        return;
    end

    try
        [selectedFiles,dataPath] = selectNoiseFiles(state.loadedNRx,state.dataPath);
        if isempty(selectedFiles)
            logRadialReco('Noise selection cancelled');
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
        applyCurrentReconstruction(hFig,'Reconstructing with noise...');
    catch ME
        logRadialReco('ERROR loading noise: %s',ME.message);
        logException(ME);
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
        return;
    end

    if state.noiseScale == noiseScale
        return;
    end

    state.noiseScale = noiseScale;
    guidata(hFig,state);

    try
        applyCurrentReconstruction(hFig,'Updating reconstruction noise scale...');
    catch ME
        logRadialReco('ERROR updating noise scale: %s',ME.message);
        logException(ME);
        errordlg(ME.message,'Reconstruction Error','modal');
    end
end

function exportViewPortCallback(source,~)
    hFig = ancestor(source,'figure');
    state = guidata(hFig);
    if ~state.dataLoaded
        return;
    end

    popup = state.handles.exportViewPopup;
    viewIndex = get(popup,'Value');
    viewNames = get(popup,'String');
    viewAxes = get(popup,'UserData');
    viewName = viewNames{viewIndex};
    exportAxesToFigure(viewAxes(viewIndex),viewName);
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
        warndlg(['Select a second, different set of simulated noise files for the SNR map.',...
            sprintf('\n\n'),...
            'Do not reuse the same .nois realization that is already loaded.'],...
            'SNR Map','modal');
        [selectedFiles,dataPath] = selectNoiseFiles(state.loadedNRx,state.dataPath);
        if isempty(selectedFiles)
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

        updateBusyState(hFig,'Reconstructing SNR map...');
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
    catch ME
        logRadialReco('ERROR building SNR map: %s',ME.message);
        logException(ME);
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
                fileName = resolveCompanionFile(signalFile,state.signalFiles,'.ktrj');
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
        applyCurrentReconstruction(hFig,'Updating radial reconstruction matrix...');
    catch ME
        guidata(hFig,previous);
        set(source,'String',num2str(previous.reconSize));
        errordlg(ME.message,'Radial Reconstruction Matrix');
    end
end

%% Reconstruction orchestration

function applyCurrentReconstruction(hFig,busyMessage)
    state = guidata(hFig);
    if isempty(state.signalDataClean)
        error('No data is loaded for reconstruction.');
    end

    useCleanRecon = ~state.noiseLoaded || isempty(state.noiseData) || state.noiseScale == 0;

    beginBusyState(hFig,busyMessage);
    reconstructionBusyCleanup = onCleanup(@() endBusyState(hFig)); %#ok<NASGU>
    state = guidata(hFig);
    if strcmpi(state.reconMode,'cartesian')
        if useCleanRecon
            if isempty(state.cleanRecon)
                [state.cleanRecon,state.cartesianMatSize] = ...
                    reconstructCartesianDataset(state.signalDataClean,state.protocol);
            end
            recon = state.cleanRecon;
        else
            signalData = state.signalDataClean + state.noiseScale * state.noiseData;
            [recon,state.cartesianMatSize] = reconstructCartesianDataset(signalData,state.protocol);
        end
    else
        if isempty(state.trajectory)
            error('No radial trajectory is loaded for reconstruction.');
        end
        [state,reconContext] = getReconstructionContext(state);
        if useCleanRecon
            [state,recon] = getCleanReconstruction(state,reconContext);
        else
            signalData = state.signalDataClean + state.noiseScale * state.noiseData;
            logRadialReco('Reconstructing with noise scale %g',state.noiseScale);
            recon = reconstructSignalDataset(state,signalData,reconContext);
        end
        logRadialReco('Reconstruction ready RSS=%s SOM=%s Complex=%s Kspace=%s',...
            reconstructionSizeString(recon.volumeRSS),reconstructionSizeString(recon.volumeSOM),...
            reconstructionSizeString(recon.volumeComplex),reconstructionSizeString(recon.kspaceMagnitude));
    end
    showReconstruction(hFig,state,recon);
end

function showReconstruction(hFig,state,recon)
    state.reconInfo = recon.info;
    state.volumeRSS = recon.volumeRSS;
    state.volumeSOM = recon.volumeSOM;
    state.volumeComplex = recon.volumeComplex;
    state.globalImageLimits = [];
    state.kspaceMagnitude = recon.kspaceMagnitude;
    state.dataLoaded = true;
    dims = getVolumeDims(state.volumeRSS);
    if state.resetSliceIndex
        state.sliceIndex = round((dims + 1) / 2);
    else
        state.sliceIndex = clampSliceIndex(state.sliceIndex,dims);
    end
    state.resetSliceIndex = false;

    guidata(hFig,state);
    updateSliceControls(hFig);
    updateInfoText(hFig);
    updateDataControls(hFig);
    handles = state.handles;
    set([handles.exportViewPopup handles.exportViewButton handles.trajectoryButton],'Enable','on');
    % Radial users can open the SNR control to see the noise requirements.
    set(handles.snrMapButton,'Enable',onOff(strcmpi(state.reconMode,'radial')));
    refreshDisplay(hFig,true);
end

function [state,reconContext] = getReconstructionContext(state)
    if ~isempty(state.reconContext)
        reconContext = state.reconContext;
        return;
    end

    fovMeters = radialFOVMeters(state.protocol.FOV);
    densityAdaptedEdge = [];
    if strcmpi(state.protocol.SequenceType,'DA_3DPR')
        adc = struct('radialResolutionMm',state.protocol.RadialResolutionMm);
        densityAdaptedEdge = radialReadoutGeometry(state.samplesPerSpoke,state.protocol.FOV,adc);
    end
    reconContext = buildRadialReconstructionContext(state.trajectory,state.reconSize, ...
        fovMeters,@logRadialReco,densityAdaptedEdge);
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

%% Display management

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

    sliceIndex = min(max(1,round(reshape(sliceIndex,1,3))),dims(1:3));
end

function dims = getVolumeDims(volume)
    dims = size(volume);
    if numel(dims) < 3
        dims(end+1:3) = 1;
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

function refreshDisplay(hFig,refreshKSpace)
    state = guidata(hFig);
    handles = state.handles;

    if ~state.dataLoaded
        initializeAxes(handles.axialAxes,'Axial');
        initializeAxes(handles.sagittalAxes,'Sagittal');
        initializeAxes(handles.coronalAxes,'Coronal');
        for hAxes = handles.kspaceAxes
            clearPreviewAxes(hAxes);
        end
        return;
    end

    xIdx = state.sliceIndex(1);
    yIdx = state.sliceIndex(2);
    zIdx = state.sliceIndex(3);

    orientations = {'Sagittal';'Coronal';'Axial'};
    imageAxes = [handles.sagittalAxes handles.coronalAxes handles.axialAxes];
    isCartesian = strcmpi(state.reconMode,'cartesian');
    if isCartesian
        available = find(strcmp(orientations,state.reconInfo.sliceOrientation));
    else
        available = 1:3;
    end
    if refreshKSpace
        inactive = setdiff(1:3,available);
        for hAxes = [imageAxes(inactive) handles.kspaceAxes(inactive)]
            clearPreviewAxes(hAxes);
        end
        set(handles.rotateButtons(available),'Enable','on');
        set(handles.rotateButtons(inactive),'Enable','off');
        for column = available
            if isCartesian
                left = 0.065;
                width = 0.87;
            else
                left = (column-1)*0.35;
                width = 0.30;
            end
            set(imageAxes(column),'Position',[left 0.54 width 0.38]);
            set(handles.kspaceAxes(column),'Position',[left 0.08 width 0.38]);
        end
        refreshKSpacePanes(state,available,isCartesian);

        viewNames = [orientations(available); strcat(orientations(available),{' K-space'})];
        popup = handles.exportViewPopup;
        if ~isequal(popup.String,viewNames)
            viewAxes = [imageAxes(available) handles.kspaceAxes(available)];
            set(popup,'String',viewNames,'Value',1,'UserData',viewAxes);
        end
    end

    [sourceVolume,sliceTransform] = selectDisplayVolume(state);
    useGlobalScale = handles.globalScaleCheckbox.Value ~= 0;
    if useGlobalScale && isempty(state.globalImageLimits)
        state.globalImageLimits = calculateGlobalImageLimits(sourceVolume,sliceTransform,...
            state.displayMode <= 3);
        guidata(hFig,state);
    end
    imageTitles = {sprintf('Sagittal (x = %d)',xIdx),...
        sprintf('Coronal (y = %d)',yIdx),sprintf('Axial (z = %d)',zIdx)};

    for column = available
        if isCartesian
            imageTitles{column} = orientations{column};
        end
        imageSlice = extractDisplaySlice(sourceVolume,column,state.sliceIndex(column),sliceTransform);
        imageSlice = rot90(imageSlice,-state.sliceQuarterTurns(column));
        updateAxesImage(imageAxes(column),imageSlice,imageTitles{column});
        if useGlobalScale
            imageAxes(column).CLim = state.globalImageLimits;
        end
    end

    set(handles.xValue,'String',num2str(xIdx));
    set(handles.yValue,'String',num2str(yIdx));
    set(handles.zValue,'String',num2str(zIdx));
end

function refreshKSpacePanes(state,available,isCartesian)
    kspaceAxes = state.handles.kspaceAxes;
    if isCartesian
        updateAxesImage(kspaceAxes(available),rot90(log1p(state.kspaceMagnitude)),...
            'K-space (log magnitude)');
        return;
    end

    frequencyAxes = 'xyz';
    peak = 0;
    for column = 1:3
        center = floor(size(state.kspaceMagnitude,column)/2) + 1;
        kspaceSlice = extractDisplaySlice(state.kspaceMagnitude,column,center,@log1p);
        updateAxesImage(kspaceAxes(column),kspaceSlice,...
            sprintf('Gridded k-space (k_{%c} = 0)',frequencyAxes(column)));
        peak = max(peak,max(kspaceSlice(:)));
    end
    if peak == 0
        peak = 1;
    end
    set(kspaceAxes,'CLim',[0 peak]);
end

function updateAxesImage(hAxes,imageData,titleStr)
    hImages = findobj(hAxes,'-depth',1,'Type','image');
    if isempty(hImages)
        imagesc(hAxes,imageData);
    else
        if numel(hImages) > 1
            delete(hImages(2:end));
        end
        set(hImages(1),'CData',imageData,'XData',[1 size(imageData,2)],...
            'YData',[1 size(imageData,1)]);
        set(hAxes,'CLimMode','auto');
    end
    axis(hAxes,'image');
    axis(hAxes,'off');
    colormap(hAxes,gray(256));
    title(hAxes,titleStr);
    hAxes.PickableParts = 'visible';
    if ~isempty(hAxes.Toolbar)
        hAxes.Toolbar.Visible = 'on';
    end
end

function clearPreviewAxes(hAxes)
    cla(hAxes);
    title(hAxes,'');
    hAxes.PickableParts = 'none';
    if ~isempty(hAxes.Toolbar)
        hAxes.Toolbar.Visible = 'off';
    end
end

function [sourceVolume,sliceTransform] = selectDisplayVolume(state)
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

end

function limits = calculateGlobalImageLimits(volume,transform,isMagnitude)
    if ~isempty(transform)
        volume = transform(volume);
    end
    limits = double([min(volume(:),[],'omitnan') max(volume(:),[],'omitnan')]);
    if any(~isfinite(limits))
        finiteValues = volume(isfinite(volume));
        if isempty(finiteValues)
            limits = [0 1];
        else
            limits = double([min(finiteValues) max(finiteValues)]);
        end
    end
    if isMagnitude
        limits = [0 max(limits(2),0)];
        if limits(2) == 0
            limits(2) = 1;
        end
    elseif limits(1) == limits(2)
        padding = max(1,abs(limits(1))) * 0.01;
        limits = limits + [-padding padding];
    end
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

function updateSliceControls(hFig)
    state = guidata(hFig);
    handles = state.handles;
    if strcmpi(state.reconMode,'cartesian')
        set([handles.xSlider handles.ySlider handles.zSlider],'Enable','off');
        return;
    end
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
        acquisitionLines = {
            ['Slice orientation: ',protocol.SliceOrientation],...
            ['PE direction: ',protocol.PEDirection]
            };
    else
        [~,trajName,trajExt] = fileparts(protocol.TrajectoryFile);
        recommendedSpokes = estimateRecommendedSpokes(info,info.retainedMaxRadius);
        spokeRatio = info.numSpokes / recommendedSpokes;

        infoLines = {
            ['Sequence: ',protocol.SequenceType],...
            ['FOV / MatSize: ',num2str(protocol.FOV),' / ',num2str(protocol.MatSize)],...
            sprintf('Readout x Spokes: %d x %d | Rx: %d',...
                info.samplesPerSpoke,info.numSpokes,state.loadedNRx),...
            sprintf('Spoke density: %d / %d (%.2f%% of rough Nyquist)',...
                info.numSpokes,recommendedSpokes,100*spokeRatio),...
            sprintf('Recon: %d^3 | %.4g mm voxels | Noise Scale: %g',...
                info.reconSize,1000*info.voxelSizeMeters(1),state.noiseScale),...
            ['Files: ',protName,protExt,' | ',trajName,trajExt],...
            noiseSummary...
            };
        acquisitionLines = {};
        if ~isempty(protocol.RadialResolutionMm)
            acquisitionLines = {sprintf('Nominal radial resolution (mm): %g',protocol.RadialResolutionMm)};
        end
    end
    infoLines = [infoLines(:); acquisitionLines(:); protocol.SequenceDetails];
    infoBox = state.handles.infoText;
    set(infoBox,'String',infoLines,'Value',min(infoBox.Value,numel(infoLines)),...
        'ListboxTop',min(infoBox.ListboxTop,numel(infoLines)));
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

%% File selection and input parsing

function [selectedFiles,dataPath] = selectSignalFiles()
    repositoryPath = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    initialPath = fullfile(repositoryPath,'protocols','*.ksig');
    [selectedFiles,dataPath] = selectComplexFiles('*.ksig','OPEN: K-space Data',initialPath);
end

function [selectedFiles,dataPath] = selectNoiseFiles(nRx,initialPath)
    if nargin < 2
        initialPath = '';
    end
    [selectedFiles,dataPath] = selectComplexFiles('*.nois','OPEN: Noise',initialPath);
    if ~isempty(selectedFiles) && numel(selectedFiles) ~= nRx
        error('Select one noise file for each loaded receive channel.');
    end
    selectedFiles = sortSignalFiles(selectedFiles);
end

function [selectedFiles,dataPath] = selectComplexFiles(fileSpec,dialogTitle,initialPath)
    dataPath = '';
    selectedFiles = {};

    if isempty(initialPath)
        dialogPath = fileSpec;
    else
        dialogPath = initialPath;
    end

    [fileNames,pathName,index] = uigetfile(fileSpec,dialogTitle,dialogPath,'Multiselect','on');
    if isequal(index,0)
        return;
    end
    if ischar(fileNames)
        fileNames = {fileNames};
    end
    selectedFiles = fileNames;
    dataPath = pathName;
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

function protocol = readReconstructionProtocol(protFileName)
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

    % Keep display-only fields as saved so they do not affect reconstruction.
    sequenceFields = {
        'Nucleus:', 'Nucleus';
        'B0(T):', 'B0 (T)';
        'TE(ms):', 'TE (ms)';
        'TR(ms):', 'TR (ms)';
        '#Dummy TRs:', 'Dummy TRs';
        'ADC Freq(kHz):', 'ADC sampling rate (kHz)';
        'RF Shape:', 'RF shape';
        'RF Duration(ms):', 'RF duration (ms)';
        '# Points in RF Pulse:', 'RF pulse points';
        'RF Flip Angle:', 'RF flip angle (deg)';
        'Target B1+ (uT):', 'Target B1+ (uT)';
        'Shim B1+ (uT):', 'Shim B1+ (uT)';
        'TI_Duration(ms):', 'Saved TI (ms)';
        'Slice Thickness:', 'Saved slice thickness (mm)';
        'Slice Position:', 'Saved slice position (model voxels)';
        'SS:', 'Gradient SS enabled';
        'PE:', 'Gradient PE enabled';
        'FE:', 'Gradient FE enabled';
        'Scanner Profile:', 'Scanner profile';
        'Scanner Gradient Limits:', 'Scanner limits (mT/m, T/m/s, us)';
        'NEX:', 'NEX';
        };
    details = cell(size(sequenceFields,1),1);

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

            otherwise
                field = find(strcmp(sequenceFields(:,1),key),1);
                if ~isempty(field)
                    valueLine = fgetl(fid);
                    if ischar(valueLine) && ~isempty(strtrim(valueLine))
                        details{field} = [sequenceFields{field,2},': ',strtrim(valueLine)];
                    end
                end
        end
        protLine = fgetl(fid);
    end

    if isempty(protocol.SequenceType)
        protocol.SequenceType = 'Unknown';
    end
    protocol.SequenceDetails = details(~cellfun(@isempty,details));
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
    if strcmpi(protocol.SequenceType,'DA_3DPR')
        numSpokes = max(1,round(matSize(end)));
        validateSpokeCount(totalSamples,samplesPerSpoke,numSpokes,'DA-3DPR');
        return;
    end
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

function fileName = resolveCompanionFile(signalFile,selectedFiles,extension)
    [dataDir,dataBase] = fileparts(signalFile);
    candidateBases = {dataBase};
    selectionBase = getSelectedFileBase(selectedFiles);
    if ~isempty(selectionBase) && ~strcmp(dataBase,selectionBase)
        candidateBases{end+1} = selectionBase;
    end

    fileName = fullfile(dataDir,[dataBase,extension]);
    % Check exact candidates in the run folder before checking its parent.
    searchDirs = {dataDir,fileparts(dataDir)};
    for dirIndex = 1:numel(searchDirs)
        folder = searchDirs{dirIndex};
        if dirIndex == 2 && isempty(folder)
            continue;
        end
        for baseIndex = 1:numel(candidateBases)
            candidate = fullfile(folder,[candidateBases{baseIndex},extension]);
            if exist(candidate,'file') == 2
                fileName = candidate;
                return;
            end
        end
    end

    candidates = dir(fullfile(dataDir,['*',extension]));
    if isscalar(candidates)
        fileName = fullfile(dataDir,candidates.name);
    end
end

function selectionBase = getSelectedFileBase(selectedFiles)

    [~,selectionBase] = fileparts(selectedFiles{1});
    if isscalar(selectedFiles)
        selectionBase = regexprep(selectionBase,'\d+$','');
        return;
    end
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

function logRadialReco(message,varargin)
    timeStamp = datestr(now,'HH:MM:SS.FFF');
    if nargin > 1
        fprintf('[reconstructionViewer %s] %s\n',timeStamp,sprintf(message,varargin{:}));
    else
        fprintf('[reconstructionViewer %s] %s\n',timeStamp,message);
    end
end

function logException(ME)
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
