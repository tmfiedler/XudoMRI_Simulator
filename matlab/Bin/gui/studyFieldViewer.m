function studyFieldViewer(viewerData)

    viewerData = normalizeViewerData(viewerData);
    gamma = getNucleusGamma(viewerData.Nucleus);
    mapSpecs = buildMapSpecs(viewerData);
    if isempty(mapSpecs)
        errordlg('No B1 or E field files are loaded for this study.','Field Viewer','modal');
        return;
    end

    expandedFiles = {};
    preparedPaths = containers.Map('KeyType','char','ValueType','char');
    for specIndex = 1:numel(mapSpecs)
        for channelIndex = 1:numel(mapSpecs(specIndex).files)
            source = mapSpecs(specIndex).files{channelIndex};
            if ~isKey(preparedPaths,source)
                [rawFile,expandedFiles{end+1}] = expandModelInput(source); %#ok<AGROW>
                preparedPaths(source) = rawFile;
            end
            mapSpecs(specIndex).files{channelIndex} = preparedPaths(source);
        end
    end
    validateFieldHeaders(mapSpecs,viewerData);

    existingFigure = findall(0,'Type','figure','Tag','StudyFieldViewer');
    if ~isempty(existingFigure)
        delete(existingFigure(ishandle(existingFigure)));
    end

    state = initializeState(viewerData,mapSpecs,gamma);

    createViewer();
    updateChannelMenu();
    renderViewer();

    function data = normalizeViewerData(data)
        data.StudyName = getStructText(data,'StudyName','Study');
        data.SequenceName = getStructText(data,'SequenceName','');
        data.Nucleus = getStructText(data,'Nucleus',getDefaultNucleus());

        data.FullMin = round(getNumericVector(data,'FullMin',[1 1 1]));
        data.FullMax = round(getNumericVector(data,'FullMax',data.FullMin));
        data.FullMax = max(data.FullMax,data.FullMin);

        data.SampleMin = round(getNumericVector(data,'SampleMin',data.FullMin));
        data.SampleMax = round(getNumericVector(data,'SampleMax',data.FullMax));
        data.SampleMin = min(max(data.SampleMin,data.FullMin),data.FullMax);
        data.SampleMax = min(max(data.SampleMax,data.FullMin),data.FullMax);
        sampleMin = min(data.SampleMin,data.SampleMax);
        sampleMax = max(data.SampleMin,data.SampleMax);
        data.SampleMin = sampleMin;
        data.SampleMax = sampleMax;

        defaultSlices = round((data.FullMin + data.FullMax)/2);
        data.InitialSlices = round(getNumericVector(data,'InitialSlices',defaultSlices));
        data.InitialSlices = min(max(data.InitialSlices,data.FullMin),data.FullMax);

        fullDims = data.FullMax - data.FullMin + 1;
        txCount = max([numel(getFieldOrDefault(data,'B1pFiles',{})), numel(getFieldOrDefault(data,'E1pFiles',{})), 1]);
        data.TxMag = getNumericColumn(data,'TxMag',ones(txCount,1));
        data.TxPhs = getNumericColumn(data,'TxPhs',zeros(txCount,1));
        if numel(data.TxMag) < txCount
            data.TxMag(end+1:txCount,1) = 1;
        end
        if numel(data.TxPhs) < txCount
            data.TxPhs(end+1:txCount,1) = 0;
        end

        data.RF = getStructOrDefault(data,'RF',struct());
        data.RF.Duration = getStructNumber(data.RF,'Duration',2.6);
        data.RF.Num = max(1,round(getStructNumber(data.RF,'Num',128)));
        data.RF.Shape = round(getStructNumber(data.RF,'Shape',1));
        if data.RF.Shape < 1 || data.RF.Shape > 3
            data.RF.Shape = 1;
        end

        data.B1pFiles = normalizeFileList(getFieldOrDefault(data,'B1pFiles',{}));
        data.B1mFiles = normalizeFileList(getFieldOrDefault(data,'B1mFiles',{}));
        data.E1pFiles = normalizeFileList(getFieldOrDefault(data,'E1pFiles',{}));
        data.E1mFiles = normalizeFileList(getFieldOrDefault(data,'E1mFiles',{}));

        if any(fullDims < 1)
            error('Field viewer requires a valid loaded geometry.');
        end
    end

    function specs = buildMapSpecs(data)
        specs = struct('id',{},'label',{},'files',{},'channelPrefix',{});

        if ~isempty(data.B1pFiles)
            specs(end+1) = createMapSpec('b1p','B1+',data.B1pFiles,'Tx'); %#ok<AGROW>
            specs(end+1) = createMapSpec('flip','Flip Angle',data.B1pFiles,'Tx'); %#ok<AGROW>
        end

        if ~isempty(data.B1mFiles)
            specs(end+1) = createMapSpec('b1m','B1-',data.B1mFiles,'Rx'); %#ok<AGROW>
        end

        if ~isempty(data.E1pFiles)
            specs(end+1) = createMapSpec('e1p','E1+',data.E1pFiles,'Ch'); %#ok<AGROW>
        end

        if ~isempty(data.E1mFiles)
            specs(end+1) = createMapSpec('e1m','E1-',data.E1mFiles,'Ch'); %#ok<AGROW>
        end
    end

    function spec = createMapSpec(id,label,files,channelPrefix)
        spec = struct('id',id,'label',label,'files',[],'channelPrefix',channelPrefix);
        spec.files = files(:).';
    end

    function validateFieldHeaders(specs,data)
        expectedVoxelCount = prod(data.FullMax - data.FullMin + 1);
        fileList = {};

        for specIndex = 1:numel(specs)
            for fileIndex = 1:numel(specs(specIndex).files)
                filePath = specs(specIndex).files{fileIndex};
                if ~any(strcmp(fileList,filePath))
                    fileList{end+1} = filePath; %#ok<AGROW>
                end
            end
        end

        waitHandle = waitbar(0,'Checking field files...','Name','Field Viewer');
        waitCleanup = onCleanup(@() closeIfValid(waitHandle)); %#ok<NASGU>

        for fileIndex = 1:numel(fileList)
            if isgraphics(waitHandle)
                waitbar(fileIndex/numel(fileList),waitHandle,...
                    sprintf('Checking %d of %d...',fileIndex,numel(fileList)));
            end
            validateFieldFile(fileList{fileIndex},expectedVoxelCount);
        end
    end

    function validateFieldFile(filePath,expectedVoxelCount)
        fid = fopen(filePath,'r');
        if fid == -1
            error('Unable to open field file: %s',filePath);
        end
        fidCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

        voxelCount = fread(fid,1,'float32=>double');
        if isempty(voxelCount)
            error('Field file is empty: %s',filePath);
        end

        fileInfo = dir(filePath);
        if isempty(fileInfo)
            error('Unable to inspect field file: %s',filePath);
        end

        expectedBytes = 4 + getFieldBytesPerVoxel(filePath) * expectedVoxelCount;
        if fileInfo(1).bytes ~= expectedBytes
            error('Field file does not match the loaded geometry: %s',filePath);
        end

        % The voxel-count header is stored as float32, so large studies can lose
        % integer precision even when the file contents are correct. Once the
        % data payload size matches the geometry, trust the file size check.
    end

    function currentState = initializeState(data,specs,gyro)
        currentState = struct();
        currentState.figure = [];
        currentState.isClosing = false;
        currentState.controls = struct();
        currentState.axes = struct();
        currentState.viewerData = data;
        currentState.mapSpecs = specs;
        currentState.gamma = gyro;
        currentState.dims = data.FullMax - data.FullMin + 1;
        currentState.fullMin = data.FullMin;
        currentState.fullMax = data.FullMax;
        currentState.sampleMin = data.SampleMin;
        currentState.sampleMax = data.SampleMax;
        currentState.currentSlices = data.InitialSlices;
        currentState.txMag = single(data.TxMag(:));
        currentState.txScale = currentState.txMag .* exp(1i * single(data.TxPhs(:)) * pi / 180);
        currentState.pulseArea = rfPulseAreaSeconds(data.RF);
    end

    function createViewer()
        state.figure = figure('Visible','off','MenuBar','none',...
            'Name',['Field Viewer - ',state.viewerData.StudyName],...
            'Tag','StudyFieldViewer','NumberTitle','off',...
            'Position',[120 80 1180 760],'Resize','off',...
            'Toolbar','none','Color',[1 1 1],...
            'DefaultUicontrolFontUnits','pixels',...
            'DefaultUicontrolFontSize',11,...
            'CloseRequestFcn',@closeViewer);
        setappdata(state.figure,'ExpandedModelInputs',expandedFiles);
        expandedFiles = {};
        movegui(state.figure,'center');

        uicontrol(state.figure,'Style','text','String','Map',...
            'Position',[20 723 30 16],'BackgroundColor',[1 1 1],...
            'HorizontalAlignment','left');
        state.controls.mapMenu = uicontrol(state.figure,'Style','popupmenu',...
            'String',{state.mapSpecs.label},'Value',1,...
            'Position',[55 720 130 22],'BackgroundColor',[1 1 1],...
            'Callback',@mapChanged);

        uicontrol(state.figure,'Style','text','String','Channel',...
            'Position',[200 723 48 16],'BackgroundColor',[1 1 1],...
            'HorizontalAlignment','left');
        state.controls.channelMenu = uicontrol(state.figure,'Style','popupmenu',...
            'String',{'Combined'},'Value',1,...
            'Position',[250 720 120 22],'BackgroundColor',[1 1 1],...
            'Callback',@channelChanged);

        state.controls.summaryText = uicontrol(state.figure,'Style','text',...
            'String',buildSummaryText(),'Position',[390 720 625 22],...
            'BackgroundColor',[1 1 1],'HorizontalAlignment','left');

        state.controls.exportButton = uicontrol(state.figure,'Style','pushbutton',...
            'String','Export Image','Position',[1035 718 125 26],...
            'BackgroundColor',[1 1 1],'Callback',@exportCurrentImage);

        state.controls.rangeText = uicontrol(state.figure,'Style','text',...
            'String','Displayed range: --','Position',[20 694 1140 16],...
            'BackgroundColor',[1 1 1],'HorizontalAlignment','left');

        state.controls.probeText = uicontrol(state.figure,'Style','text',...
            'String','Probe: click any pane to sample the current map at that voxel.',...
            'Position',[20 672 1140 16],...
            'BackgroundColor',[1 1 1],'HorizontalAlignment','left');

        createPlanePanel('Axial',[0.02 0.05 0.30 0.83],'Z');
        createPlanePanel('Sagittal',[0.35 0.05 0.30 0.83],'X');
        createPlanePanel('Coronal',[0.68 0.05 0.30 0.83],'Y');

        set(state.figure,'Visible','on');
    end

    function createPlanePanel(panelName,panelPosition,axisLabel)
        fieldName = lower(panelName);
        panelHandle = uipanel(state.figure,'Title',panelName,...
            'Units','normalized','Position',panelPosition,...
            'BackgroundColor',[1 1 1],'FontWeight','bold');

        state.controls.([fieldName,'Panel']) = panelHandle;
        state.axes.(fieldName) = axes('Parent',panelHandle,'Units','normalized',...
            'Position',[0.11 0.18 0.68 0.73]);
        state.controls.([fieldName,'Colorbar']) = colorbar(state.axes.(fieldName),'eastoutside');
        xlabel(state.axes.(fieldName),getPlaneAxisLabels(panelName));

        uicontrol(panelHandle,'Style','text','String',[axisLabel,' Slice'],...
            'Units','normalized','Position',[0.06 0.07 0.14 0.05],...
            'BackgroundColor',[1 1 1],'HorizontalAlignment','left');
        state.controls.([fieldName,'Slider']) = uicontrol(panelHandle,'Style','slider',...
            'Units','normalized','Position',[0.20 0.075 0.58 0.05],...
            'BackgroundColor',[1 1 1],...
            'Callback',@(source,eventdata) sliceSliderChanged(panelName,source)); %#ok<INUSD>
        state.controls.([fieldName,'Edit']) = uicontrol(panelHandle,'Style','edit',...
            'Units','normalized','Position',[0.80 0.065 0.12 0.07],...
            'BackgroundColor',[1 1 1],...
            'Callback',@(source,eventdata) sliceEditChanged(panelName,source)); %#ok<INUSD>

        configureSliceControl(panelName);
    end

    function textValue = buildSummaryText()
        sequenceName = state.viewerData.SequenceName;
        if isempty(sequenceName)
            sequenceName = 'Sequence not set';
        end

        textValue = sprintf('Study: %s | %s | %s | RF: %s, %.4g ms, %d pts | Reopen after changing Tx/RF settings in Setup.',...
            state.viewerData.StudyName,sequenceName,state.viewerData.Nucleus,getRFShapeName(state.viewerData.RF.Shape),...
            state.viewerData.RF.Duration,state.viewerData.RF.Num);
    end


    function mapChanged(source,eventdata) %#ok<INUSD>
        if ~viewerAlive()
            return;
        end
        updateChannelMenu();
        renderViewer();
    end

    function channelChanged(source,eventdata) %#ok<INUSD>
        if ~viewerAlive()
            return;
        end
        renderViewer();
    end

    function updateChannelMenu()
        if ~handleAlive(state.controls.channelMenu)
            return;
        end

        spec = getSelectedMapSpec();
        labels = {'Combined'};
        for channelIndex = 1:numel(spec.files)
            labels{end+1} = sprintf('%s %d',spec.channelPrefix,channelIndex); %#ok<AGROW>
        end

        setIfAlive(state.controls.channelMenu,'String',labels,'Value',1);
    end

    function renderViewer()
        if ~viewerAlive()
            return;
        end

        setIfAlive(state.figure,'Pointer','watch');
        drawnow;

        try
            if ~viewerAlive()
                return;
            end

            [spec,displayInfo,axialSlice,sagittalSlice,coronalSlice,colorLimits,channelLabel] = ...
                getCurrentDisplayState();
            renderPlane('Axial',axialSlice,colorLimits,spec.label,channelLabel,state.currentSlices(3),displayInfo);
            renderPlane('Sagittal',sagittalSlice,colorLimits,spec.label,channelLabel,state.currentSlices(1),displayInfo);
            renderPlane('Coronal',coronalSlice,colorLimits,spec.label,channelLabel,state.currentSlices(2),displayInfo);

            setIfAlive(state.controls.rangeText,'String',...
                formatRangeText(colorLimits,displayInfo));
            setIfAlive(state.controls.probeText,'String',...
                formatProbeText(axialSlice,displayInfo,spec.label,channelLabel));
        catch ME
            if viewerAlive()
                errordlg(ME.message,'Field Viewer','modal');
            end
        end

        setIfAlive(state.figure,'Pointer','arrow');
        if viewerAlive()
            drawnow;
        end
    end

    function [spec,displayInfo,axialSlice,sagittalSlice,coronalSlice,colorLimits,channelLabel] = getCurrentDisplayState()
        spec = getSelectedMapSpec();
        displayInfo = getMapDisplayInfo(spec);
        channelSelection = max(0,round(getIfAlive(state.controls.channelMenu,'Value',1)) - 1);
        axialSlice = computeMapSlice(spec,'Axial',state.currentSlices(3),channelSelection);
        sagittalSlice = computeMapSlice(spec,'Sagittal',state.currentSlices(1),channelSelection);
        coronalSlice = computeMapSlice(spec,'Coronal',state.currentSlices(2),channelSelection);

        axialSlice = applyDisplayScale(axialSlice,displayInfo.scaleFactor);
        sagittalSlice = applyDisplayScale(sagittalSlice,displayInfo.scaleFactor);
        coronalSlice = applyDisplayScale(coronalSlice,displayInfo.scaleFactor);

        maxValue = max([axialSlice(:); sagittalSlice(:); coronalSlice(:)]);
        if isempty(maxValue) || ~isfinite(maxValue) || maxValue <= 0
            colorLimits = [0 1];
        else
            colorLimits = [0 double(maxValue)];
        end

        channelLabel = getSelectedChannelLabel();
    end

    function renderPlane(planeName,sliceData,colorLimits,mapLabel,channelLabel,sliceCoord,displayInfo)
        axisHandle = state.axes.(lower(planeName));
        if ~handleAlive(axisHandle)
            return;
        end

        cla(axisHandle);

        [xCoords,yCoords,xLabel,yLabel] = getDisplayAxes(planeName);
        imageHandle = imagesc(axisHandle,xCoords,yCoords,sliceData.');
        set(axisHandle,'YDir','normal');
        axis(axisHandle,'image');
        box(axisHandle,'on');
        colormap(axisHandle,turbo(256));
        caxis(axisHandle,colorLimits);
        xlabel(axisHandle,xLabel);
        ylabel(axisHandle,yLabel);
        set(axisHandle,'ButtonDownFcn',@(source,eventdata) probePlane(planeName,axisHandle)); %#ok<INUSD>
        set(imageHandle,'ButtonDownFcn',@(source,eventdata) probePlane(planeName,axisHandle)); %#ok<INUSD>
        title(axisHandle,sprintf('%s | %s | %s | %s=%d',planeName,mapLabel,channelLabel,...
            getSliceAxisName(planeName),sliceCoord),'Interpreter','none');

        colorbarHandle = state.controls.([lower(planeName),'Colorbar']);
        if handleAlive(colorbarHandle)
            set(colorbarHandle,'Color',[0 0 0]);
            ylabel(colorbarHandle,displayInfo.unitLabel,'Interpreter','none');
        end

        hold(axisHandle,'on');
        rectangle(axisHandle,'Position',getSampleOverlay(planeName),...
            'EdgeColor',[1 0 0],'LineWidth',1);
        plotProbeMarker(planeName,axisHandle);
        hold(axisHandle,'off');
    end

    function renderExportPlane(parentFigure,planeName,sliceData,colorLimits,mapLabel,channelLabel,sliceCoord,displayInfo,axisPosition)
        axisHandle = axes('Parent',parentFigure,'Units','normalized','Position',axisPosition);
        [xCoords,yCoords,xLabel,yLabel] = getDisplayAxes(planeName);
        imagesc(axisHandle,xCoords,yCoords,sliceData.');
        set(axisHandle,'YDir','normal');
        axis(axisHandle,'image');
        box(axisHandle,'on');
        colormap(axisHandle,turbo(256));
        caxis(axisHandle,colorLimits);
        xlabel(axisHandle,xLabel);
        ylabel(axisHandle,yLabel);
        title(axisHandle,sprintf('%s | %s | %s | %s=%d',planeName,mapLabel,channelLabel,...
            getSliceAxisName(planeName),sliceCoord),'Interpreter','none');
        colorbarHandle = colorbar(axisHandle,'eastoutside');
        ylabel(colorbarHandle,displayInfo.unitLabel,'Interpreter','none');

        hold(axisHandle,'on');
        rectangle(axisHandle,'Position',getSampleOverlay(planeName),...
            'EdgeColor',[1 0 0],'LineWidth',1);
        hold(axisHandle,'off');
    end

    function [xCoords,yCoords,xLabel,yLabel] = getDisplayAxes(planeName)
        switch planeName
            case 'Axial'
                xCoords = state.fullMin(1):state.fullMax(1);
                yCoords = state.fullMin(2):state.fullMax(2);
                xLabel = 'X';
                yLabel = 'Y';
            case 'Sagittal'
                xCoords = state.fullMin(2):state.fullMax(2);
                yCoords = state.fullMin(3):state.fullMax(3);
                xLabel = 'Y';
                yLabel = 'Z';
            otherwise
                xCoords = state.fullMin(1):state.fullMax(1);
                yCoords = state.fullMin(3):state.fullMax(3);
                xLabel = 'X';
                yLabel = 'Z';
        end
    end

    function overlay = getSampleOverlay(planeName)
        switch planeName
            case 'Axial'
                overlay = [state.sampleMin(1)-0.5, state.sampleMin(2)-0.5, ...
                    state.sampleMax(1)-state.sampleMin(1)+1, ...
                    state.sampleMax(2)-state.sampleMin(2)+1];
            case 'Sagittal'
                overlay = [state.sampleMin(2)-0.5, state.sampleMin(3)-0.5, ...
                    state.sampleMax(2)-state.sampleMin(2)+1, ...
                    state.sampleMax(3)-state.sampleMin(3)+1];
            otherwise
                overlay = [state.sampleMin(1)-0.5, state.sampleMin(3)-0.5, ...
                    state.sampleMax(1)-state.sampleMin(1)+1, ...
                    state.sampleMax(3)-state.sampleMin(3)+1];
        end
    end

    function sliceData = computeMapSlice(spec,planeName,sliceCoord,channelSelection)
        switch spec.id
            case 'b1p'
                sliceData = computeB1PlusSlice(spec.files,planeName,sliceCoord,channelSelection);
            case 'flip'
                sliceData = computeB1PlusSlice(spec.files,planeName,sliceCoord,channelSelection);
                sliceData = single(state.gamma * state.pulseArea * 180 / pi) .* sliceData;
            case 'b1m'
                sliceData = computeB1MinusSlice(spec.files,planeName,sliceCoord,channelSelection);
            case {'e1p','e1m'}
                sliceData = computeEFieldSlice(spec.files,planeName,sliceCoord,channelSelection);
            otherwise
                error('Unsupported map type: %s',spec.id);
        end
    end

    function displayInfo = getMapDisplayInfo(spec)
        displayInfo = struct('scaleFactor',single(1),'unitLabel','');

        switch spec.id
            case {'b1p','b1m'}
                displayInfo.scaleFactor = single(1e6);
                displayInfo.unitLabel = 'uT';
            case 'flip'
                displayInfo.unitLabel = 'deg';
            case {'e1p','e1m'}
                displayInfo.unitLabel = 'V/m';
            otherwise
                error('Unsupported map type: %s',spec.id);
        end
    end

    function textValue = formatRangeText(colorLimits,displayInfo)
        if isempty(displayInfo.unitLabel)
            textValue = sprintf('Displayed range: %.6g to %.6g',colorLimits(1),colorLimits(2));
        else
            textValue = sprintf('Displayed range: %.6g to %.6g %s',...
                colorLimits(1),colorLimits(2),displayInfo.unitLabel);
        end
    end

    function textValue = formatProbeText(axialSlice,displayInfo,mapLabel,channelLabel)
        probeX = state.currentSlices(1);
        probeY = state.currentSlices(2);
        probeZ = state.currentSlices(3);

        xIndex = probeX - state.fullMin(1) + 1;
        yIndex = probeY - state.fullMin(2) + 1;

        if xIndex < 1 || xIndex > size(axialSlice,1) || yIndex < 1 || yIndex > size(axialSlice,2)
            textValue = sprintf('Probe: X=%d, Y=%d, Z=%d | value unavailable',probeX,probeY,probeZ);
            return;
        end

        probeValue = axialSlice(xIndex,yIndex);
        if isempty(displayInfo.unitLabel)
            valueText = sprintf('%.12g',probeValue);
        else
            valueText = sprintf('%.12g %s',probeValue,displayInfo.unitLabel);
        end

        textValue = sprintf('Probe: X=%d, Y=%d, Z=%d | %s | %s = %s | click any pane to move the probe.',...
            probeX,probeY,probeZ,mapLabel,channelLabel,valueText);
    end

    function sliceData = applyDisplayScale(sliceData,scaleFactor)
        if scaleFactor ~= 1
            sliceData = scaleFactor .* sliceData;
        end
    end

    function sliceData = computeB1PlusSlice(fileList,planeName,sliceCoord,channelSelection)
        sliceSize = getSliceSize(planeName);

        if channelSelection == 0
            combinedSlice = complex(zeros(sliceSize,'single'));
            for channelIndex = 1:numel(fileList)
                combinedSlice = combinedSlice + getTxWeight(channelIndex) .* ...
                    readComplexFieldSlice(fileList{channelIndex},planeName,sliceCoord);
            end
            sliceData = abs(combinedSlice);
        else
            sliceData = abs(getTxMagnitude(channelSelection) .* ...
                readComplexFieldSlice(fileList{channelSelection},planeName,sliceCoord));
        end
    end

    function sliceData = computeB1MinusSlice(fileList,planeName,sliceCoord,channelSelection)
        if channelSelection == 0
            powerSlice = zeros(getSliceSize(planeName),'single');
            for channelIndex = 1:numel(fileList)
                fieldSlice = readComplexFieldSlice(fileList{channelIndex},planeName,sliceCoord);
                powerSlice = powerSlice + abs(fieldSlice).^2;
            end
            sliceData = sqrt(powerSlice);
        else
            sliceData = abs(readComplexFieldSlice(fileList{channelSelection},planeName,sliceCoord));
        end
    end

    function sliceData = computeEFieldSlice(fileList,planeName,sliceCoord,channelSelection)
        sliceSize = getSliceSize(planeName);

        if channelSelection == 0
            exSlice = complex(zeros(sliceSize,'single'));
            eySlice = complex(zeros(sliceSize,'single'));
            ezSlice = complex(zeros(sliceSize,'single'));
            for channelIndex = 1:numel(fileList)
                [tempEx,tempEy,tempEz] = readEFieldSlice(fileList{channelIndex},planeName,sliceCoord);
                tempWeight = getTxWeight(channelIndex);
                exSlice = exSlice + tempWeight .* tempEx;
                eySlice = eySlice + tempWeight .* tempEy;
                ezSlice = ezSlice + tempWeight .* tempEz;
            end
        else
            [tempEx,tempEy,tempEz] = readEFieldSlice(fileList{channelSelection},planeName,sliceCoord);
            tempWeight = getTxMagnitude(channelSelection);
            exSlice = tempWeight .* tempEx;
            eySlice = tempWeight .* tempEy;
            ezSlice = tempWeight .* tempEz;
        end

        sliceData = sqrt(abs(exSlice).^2 + abs(eySlice).^2 + abs(ezSlice).^2);
    end

    function fieldSlice = readComplexFieldSlice(filePath,planeName,sliceCoord)
        coordIndex = getSliceIndex(planeName,sliceCoord);
        fid = fopen(filePath,'r');
        if fid == -1
            error('Unable to open field file: %s',filePath);
        end
        fidCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

        headerBytes = 4;
        bytesPerVoxel = 8;
        nx = state.dims(1);
        ny = state.dims(2);
        nz = state.dims(3);

        switch planeName
            case 'Axial'
                startOffset = headerBytes + (coordIndex-1) * nx * ny * bytesPerVoxel;
                fseek(fid,startOffset,'bof');
                raw = fread(fid,[2, nx*ny],'2*float32=>single');
                fieldSlice = reshape(complex(raw(1,:),raw(2,:)),[nx, ny]);

            case 'Sagittal'
                startOffset = headerBytes + (coordIndex-1) * bytesPerVoxel;
                fseek(fid,startOffset,'bof');
                raw = fread(fid,[2, ny*nz],'2*float32=>single',(nx-1)*bytesPerVoxel);
                fieldSlice = reshape(complex(raw(1,:),raw(2,:)),[ny, nz]);

            case 'Coronal'
                startOffset = headerBytes + (coordIndex-1) * nx * bytesPerVoxel;
                fseek(fid,startOffset,'bof');
                raw = fread(fid,[2*nx, nz],sprintf('%d*float32=>single',2*nx),nx*(ny-1)*bytesPerVoxel);
                raw = reshape(raw,[2, nx, nz]);
                fieldSlice = reshape(complex(raw(1,:,:),raw(2,:,:)),[nx, nz]);

            otherwise
                error('Unsupported plane: %s',planeName);
        end
    end

    function [exSlice,eySlice,ezSlice] = readEFieldSlice(filePath,planeName,sliceCoord)
        coordIndex = getSliceIndex(planeName,sliceCoord);
        fid = fopen(filePath,'r');
        if fid == -1
            error('Unable to open field file: %s',filePath);
        end
        fidCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

        headerBytes = 4;
        bytesPerVoxel = 24;
        nx = state.dims(1);
        ny = state.dims(2);
        nz = state.dims(3);

        switch planeName
            case 'Axial'
                startOffset = headerBytes + (coordIndex-1) * nx * ny * bytesPerVoxel;
                fseek(fid,startOffset,'bof');
                raw = fread(fid,[6, nx*ny],'6*float32=>single');
                raw = reshape(raw,[6, nx, ny]);
                exSlice = reshape(complex(raw(1,:,:),raw(2,:,:)),[nx, ny]);
                eySlice = reshape(complex(raw(3,:,:),raw(4,:,:)),[nx, ny]);
                ezSlice = reshape(complex(raw(5,:,:),raw(6,:,:)),[nx, ny]);

            case 'Sagittal'
                startOffset = headerBytes + (coordIndex-1) * bytesPerVoxel;
                fseek(fid,startOffset,'bof');
                raw = fread(fid,[6, ny*nz],'6*float32=>single',(nx-1)*bytesPerVoxel);
                raw = reshape(raw,[6, ny, nz]);
                exSlice = reshape(complex(raw(1,:,:),raw(2,:,:)),[ny, nz]);
                eySlice = reshape(complex(raw(3,:,:),raw(4,:,:)),[ny, nz]);
                ezSlice = reshape(complex(raw(5,:,:),raw(6,:,:)),[ny, nz]);

            case 'Coronal'
                startOffset = headerBytes + (coordIndex-1) * nx * bytesPerVoxel;
                fseek(fid,startOffset,'bof');
                raw = fread(fid,[6*nx, nz],sprintf('%d*float32=>single',6*nx),nx*(ny-1)*bytesPerVoxel);
                raw = reshape(raw,[6, nx, nz]);
                exSlice = reshape(complex(raw(1,:,:),raw(2,:,:)),[nx, nz]);
                eySlice = reshape(complex(raw(3,:,:),raw(4,:,:)),[nx, nz]);
                ezSlice = reshape(complex(raw(5,:,:),raw(6,:,:)),[nx, nz]);

            otherwise
                error('Unsupported plane: %s',planeName);
        end
    end

    function sliceIndex = getSliceIndex(planeName,sliceCoord)
        switch planeName
            case 'Axial'
                sliceIndex = sliceCoord - state.fullMin(3) + 1;
            case 'Sagittal'
                sliceIndex = sliceCoord - state.fullMin(1) + 1;
            otherwise
                sliceIndex = sliceCoord - state.fullMin(2) + 1;
        end
    end

    function sliceSize = getSliceSize(planeName)
        switch planeName
            case 'Axial'
                sliceSize = [state.dims(1), state.dims(2)];
            case 'Sagittal'
                sliceSize = [state.dims(2), state.dims(3)];
            otherwise
                sliceSize = [state.dims(1), state.dims(3)];
        end
    end

    function configureSliceControl(planeName)
        [minimumValue,maximumValue,currentValue] = getSliceBounds(planeName);
        sliderField = [lower(planeName),'Slider'];
        editField = [lower(planeName),'Edit'];

        if ~isfield(state.controls,sliderField) || ~isfield(state.controls,editField)
            return;
        end

        if maximumValue <= minimumValue
            sliderStep = [1 1];
        else
            sliderStep = [1/(maximumValue-minimumValue), min(1,10/(maximumValue-minimumValue))];
        end

        setIfAlive(state.controls.(sliderField),'Min',minimumValue,'Max',maximumValue,...
            'Value',currentValue,'SliderStep',sliderStep);
        setIfAlive(state.controls.(editField),'String',num2str(currentValue));
    end

    function [minimumValue,maximumValue,currentValue] = getSliceBounds(planeName)
        switch planeName
            case 'Axial'
                minimumValue = state.fullMin(3);
                maximumValue = state.fullMax(3);
                currentValue = state.currentSlices(3);
            case 'Sagittal'
                minimumValue = state.fullMin(1);
                maximumValue = state.fullMax(1);
                currentValue = state.currentSlices(1);
            otherwise
                minimumValue = state.fullMin(2);
                maximumValue = state.fullMax(2);
                currentValue = state.currentSlices(2);
        end
    end

    function updateAllSliceControls()
        configureSliceControl('Axial');
        configureSliceControl('Sagittal');
        configureSliceControl('Coronal');
    end

    function probePlane(planeName,axisHandle)
        if ~handleAlive(axisHandle)
            return;
        end

        clickedPoint = get(axisHandle,'CurrentPoint');
        clickedX = round(clickedPoint(1,1));
        clickedY = round(clickedPoint(1,2));

        switch planeName
            case 'Axial'
                state.currentSlices(1) = clampCoordinate(clickedX,state.fullMin(1),state.fullMax(1));
                state.currentSlices(2) = clampCoordinate(clickedY,state.fullMin(2),state.fullMax(2));
            case 'Sagittal'
                state.currentSlices(2) = clampCoordinate(clickedX,state.fullMin(2),state.fullMax(2));
                state.currentSlices(3) = clampCoordinate(clickedY,state.fullMin(3),state.fullMax(3));
            case 'Coronal'
                state.currentSlices(1) = clampCoordinate(clickedX,state.fullMin(1),state.fullMax(1));
                state.currentSlices(3) = clampCoordinate(clickedY,state.fullMin(3),state.fullMax(3));
            otherwise
                return;
        end

        updateAllSliceControls();
        renderViewer();
    end

    function plotProbeMarker(planeName,axisHandle)
        [probeX,probeY] = getPlaneProbeCoordinates(planeName);

        plot(axisHandle,probeX,probeY,'wo','MarkerSize',7,'LineWidth',1.2,...
            'HandleVisibility','off','HitTest','off');
        plot(axisHandle,probeX,probeY,'w+','MarkerSize',10,'LineWidth',1.2,...
            'HandleVisibility','off','HitTest','off');
    end

    function [probeX,probeY] = getPlaneProbeCoordinates(planeName)
        switch planeName
            case 'Axial'
                probeX = state.currentSlices(1);
                probeY = state.currentSlices(2);
            case 'Sagittal'
                probeX = state.currentSlices(2);
                probeY = state.currentSlices(3);
            otherwise
                probeX = state.currentSlices(1);
                probeY = state.currentSlices(3);
        end
    end

    function sliceSliderChanged(planeName,sliderHandle)
        if ~handleAlive(sliderHandle)
            return;
        end

        tempValue = round(get(sliderHandle,'Value'));
        setCurrentSlice(planeName,tempValue);
        configureSliceControl(planeName);
        renderViewer();
    end

    function sliceEditChanged(planeName,editHandle)
        if ~handleAlive(editHandle)
            return;
        end

        tempValue = round(str2double(get(editHandle,'String')));
        if isnan(tempValue)
            configureSliceControl(planeName);
            return;
        end

        setCurrentSlice(planeName,tempValue);
        configureSliceControl(planeName);
        renderViewer();
    end

    function setCurrentSlice(planeName,tempValue)
        [minimumValue,maximumValue] = getSliceBounds(planeName);
        tempValue = min(max(tempValue,minimumValue),maximumValue);

        switch planeName
            case 'Axial'
                state.currentSlices(3) = tempValue;
            case 'Sagittal'
                state.currentSlices(1) = tempValue;
            otherwise
                state.currentSlices(2) = tempValue;
        end
    end

    function spec = getSelectedMapSpec()
        specIndex = 1;
        if handleAlive(state.controls.mapMenu)
            specIndex = round(get(state.controls.mapMenu,'Value'));
        end
        specIndex = min(max(specIndex,1),numel(state.mapSpecs));
        spec = state.mapSpecs(specIndex);
    end

    function label = getSelectedChannelLabel()
        label = 'Combined';
        if ~handleAlive(state.controls.channelMenu)
            return;
        end

        tempString = get(state.controls.channelMenu,'String');
        tempValue = round(get(state.controls.channelMenu,'Value'));
        if iscell(tempString) && ~isempty(tempString)
            tempValue = min(max(tempValue,1),numel(tempString));
            label = tempString{tempValue};
        end
    end

    function exportCurrentImage(source,eventdata) %#ok<INUSD>
        if ~viewerAlive()
            return;
        end

        [fileName,filePath] = uiputfile(...
            {'*.png','PNG Image (*.png)'; '*.tif','TIFF Image (*.tif)'; '*.jpg','JPEG Image (*.jpg)'; '*.pdf','PDF File (*.pdf)'},...
            'Export Visible Field',getDefaultExportFileName());
        if isequal(fileName,0) || isequal(filePath,0)
            return;
        end

        outputFile = fullfile(filePath,fileName);
        [~,~,fileExt] = fileparts(outputFile);
        if isempty(fileExt)
            outputFile = [outputFile,'.png'];
            fileExt = '.png';
        end

        setIfAlive(state.figure,'Pointer','watch');
        drawnow;

        exportFigure = [];
        try
            [spec,displayInfo,axialSlice,sagittalSlice,coronalSlice,colorLimits,channelLabel] = ...
                getCurrentDisplayState();
            exportFigure = figure('Visible','off','Color',[1 1 1],...
                'Units','pixels','Position',[100 100 1200 430],...
                'PaperPositionMode','auto','InvertHardcopy','off');
            exportCleanup = onCleanup(@() closeIfValid(exportFigure)); %#ok<NASGU>

            renderExportPlane(exportFigure,'Axial',axialSlice,colorLimits,spec.label,channelLabel,...
                state.currentSlices(3),displayInfo,[0.055 0.15 0.235 0.72]);
            renderExportPlane(exportFigure,'Sagittal',sagittalSlice,colorLimits,spec.label,channelLabel,...
                state.currentSlices(1),displayInfo,[0.385 0.15 0.235 0.72]);
            renderExportPlane(exportFigure,'Coronal',coronalSlice,colorLimits,spec.label,channelLabel,...
                state.currentSlices(2),displayInfo,[0.715 0.15 0.235 0.72]);

            if exist('exportgraphics','file') == 2
                exportgraphics(exportFigure,outputFile,'Resolution',300);
            else
                print(exportFigure,outputFile,getPrintDevice(fileExt),'-r300');
            end
        catch ME
            if viewerAlive()
                errordlg(ME.message,'Export Visible Field','modal');
            end
        end

        setIfAlive(state.figure,'Pointer','arrow');
    end

    function fileName = getDefaultExportFileName()
        spec = getSelectedMapSpec();
        fileName = sprintf('%s_%s_%s_X%d_Y%d_Z%d.png',...
            state.viewerData.StudyName,spec.label,getSelectedChannelLabel(),...
            state.currentSlices(1),state.currentSlices(2),state.currentSlices(3));
        fileName = regexprep(fileName,'[^A-Za-z0-9_\-.]','_');
    end

    function device = getPrintDevice(fileExt)
        switch lower(fileExt)
            case '.pdf'
                device = '-dpdf';
            case {'.jpg','.jpeg'}
                device = '-djpeg';
            case {'.tif','.tiff'}
                device = '-dtiff';
            otherwise
                device = '-dpng';
        end
    end

    function value = getTxWeight(channelIndex)
        if channelIndex <= numel(state.txScale)
            value = state.txScale(channelIndex);
        else
            value = single(1);
        end
    end

    function value = getTxMagnitude(channelIndex)
        if channelIndex <= numel(state.txMag)
            value = state.txMag(channelIndex);
        else
            value = single(1);
        end
    end

    function closeViewer(source,eventdata) %#ok<INUSD>
        if state.isClosing
            return;
        end

        state.isClosing = true;
        if isgraphics(state.figure)
            set(state.figure,'CloseRequestFcn','');
            delete(state.figure);
        end
        state.figure = [];
    end

    function active = viewerAlive()
        active = ~state.isClosing && ~isempty(state.figure) && isgraphics(state.figure);
    end

    function active = handleAlive(handle)
        active = viewerAlive() && ~isempty(handle) && all(isgraphics(handle(:)));
    end

    function setIfAlive(handle,varargin)
        if handleAlive(handle)
            set(handle,varargin{:});
        end
    end

    function value = getIfAlive(handle,propertyName,defaultValue)
        value = defaultValue;
        if handleAlive(handle)
            value = get(handle,propertyName);
        end
    end

    function value = clampCoordinate(value,minimumValue,maximumValue)
        value = min(max(value,minimumValue),maximumValue);
    end
end

function value = getStructText(data,fieldName,defaultValue)
    value = defaultValue;
    if isfield(data,fieldName) && ~isempty(data.(fieldName))
        if isstring(data.(fieldName))
            value = char(data.(fieldName));
        else
            value = data.(fieldName);
        end
    end
end

function value = getFieldOrDefault(data,fieldName,defaultValue)
    if isfield(data,fieldName)
        value = data.(fieldName);
    else
        value = defaultValue;
    end
end

function value = getStructOrDefault(data,fieldName,defaultValue)
    if isfield(data,fieldName) && isstruct(data.(fieldName))
        value = data.(fieldName);
    else
        value = defaultValue;
    end
end

function value = getStructNumber(data,fieldName,defaultValue)
    value = defaultValue;
    if isfield(data,fieldName)
        tempValue = double(data.(fieldName));
        if isfinite(tempValue)
            value = tempValue;
        end
    end
end

function value = getNumericVector(data,fieldName,defaultValue)
    if isfield(data,fieldName)
        tempValue = double(data.(fieldName));
        if numel(tempValue) == 3 && all(isfinite(tempValue(:)))
            value = reshape(tempValue,1,3);
            return;
        end
    end

    value = reshape(double(defaultValue),1,3);
end

function value = getNumericColumn(data,fieldName,defaultValue)
    if isfield(data,fieldName)
        tempValue = double(data.(fieldName));
        if ~isempty(tempValue) && all(isfinite(tempValue(:)))
            value = tempValue(:);
            return;
        end
    end

    value = double(defaultValue(:));
end

function fileList = normalizeFileList(fileList)
    if isempty(fileList)
        fileList = {};
        return;
    end

    if ischar(fileList) || isstring(fileList)
        fileList = {char(fileList)};
    elseif ~iscell(fileList)
        fileList = {};
        return;
    end

    keepMask = false(size(fileList));
    for index = 1:numel(fileList)
        currentValue = fileList{index};
        if isstring(currentValue)
            currentValue = char(currentValue);
        end

        if ischar(currentValue)
            currentValue = strtrim(currentValue);
            if ~isempty(currentValue)
                fileList{index} = currentValue;
                keepMask(index) = true;
            end
        end
    end

    fileList = fileList(keepMask);
    fileList = fileList(:);
end

function label = getRFShapeName(shapeIndex)
    switch shapeIndex
        case 1
            label = 'Sinc';
        case 2
            label = 'Rect';
        case 3
            label = 'Gauss';
        otherwise
            label = 'Unknown';
    end
end

function label = getSliceAxisName(planeName)
    switch planeName
        case 'Axial'
            label = 'Z';
        case 'Sagittal'
            label = 'X';
        otherwise
            label = 'Y';
    end
end

function label = getPlaneAxisLabels(planeName)
    switch planeName
        case 'Axial'
            label = 'X';
        case 'Sagittal'
            label = 'Y';
        otherwise
            label = 'X';
    end
end

function bytesPerVoxel = getFieldBytesPerVoxel(filePath)
    [~,~,fileExt] = fileparts(filePath);
    switch lower(fileExt)
        case '.bfld'
            bytesPerVoxel = 8;
        case '.efld'
            bytesPerVoxel = 24;
        otherwise
            error('Unsupported field file type: %s',filePath);
    end
end

function closeIfValid(handle)
    if ~isempty(handle) && isgraphics(handle)
        delete(handle);
    end
end
