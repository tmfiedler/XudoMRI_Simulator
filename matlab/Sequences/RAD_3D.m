%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%       RAD_3D sequence with 3D radial spoke readout
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function varargout = RAD_3D(TE,TR,MatSize,FOV,RF,ADC,GradOn,dummy,slice,nucleus)

    if ~isscalar(GradOn.fe) || ~isscalar(GradOn.pe) || ~isscalar(GradOn.ss) || ...
            GradOn.fe ~= 1 || GradOn.pe ~= 1 || GradOn.ss ~= 1
        error('RAD_3D:RequiresThreeAxes', ...
            'RAD_3D requires all three logical radial axes (FE, PE and SS) enabled.');
    end

    %% Init
    % MatSize(1) is the readout samples per spoke, MatSize(2) is the spoke count.
    MatSize1 = max(1,round(MatSize(1)));
    if length(MatSize) > 1
        MatSize2 = max(1,round(MatSize(2)));
    else
        MatSize2 = MatSize1;
    end

    FOV1 = FOV(1);
    if length(FOV) > 1
        FOV2 = FOV(2);
    else
        FOV2 = FOV1;
    end

    startTime = 0.001; % ms
    if nargin < 10 || isempty(nucleus)
        nucleus = getDefaultNucleus();
    end
    gamma = getNucleusGamma(nucleus);

    ADC.numSamples = MatSize1;
    ADC.duration = MatSize1/ADC.BW; % ms
    RF.Freq = RF.Num / RF.Duration; % kHz

    frqBW = 4/RF.Duration*1000;

    % Backend implementation for the user-facing RAD_3D sequence.
    % It behaves as a nonselective UTE-style radial sequence.
    % FE/PE/SS are the logical x/y/z radial axes and must all be enabled.
    % The GUI shows one isotropic FOV and stores it in the legacy two-entry
    % vector. max(...) preserves compatibility with older protocol files.
    radialFOV = max([FOV1, FOV2, 1]);
    spokeAmp = readoutAmp(gamma,ADC.BW,radialFOV);

    Gread.amp = [0,0,0];
    if GradOn.fe == 1
        Gread.amp(1) = spokeAmp;
    end
    if GradOn.pe == 1
        Gread.amp(2) = spokeAmp;
    end
    if GradOn.ss == 1
        Gread.amp(3) = spokeAmp;
    end

    % Return each spoke to k = 0 before the next TR. The Bloch simulator
    % exports one trajectory sample per ADC point, so leaving residual
    % readout area here pushes the next spoke off-center in the .ktrj file.
    Gread.rewind.duration = ADC.duration/5;
    Gread.rewind.scale = -ADC.duration / Gread.rewind.duration;

    % For a center-out half-spoke, TE is referenced to the first acquired
    % sample rather than the midpoint of the readout.
    minTE = RF.Duration/2;
    if TE < minTE
        TE = minTE;
    end

    minTR = startTime + RF.Duration + (TE - minTE) + ADC.duration + Gread.rewind.duration;
    if TR < minTR
        TR = minTR;
    end

    readDelay = TE - minTE;
    tailDelay = TR - minTR;
    minTI = 0;

    %% Return SeqData
    if nargout == 1
        tempRF_Y = makeRFEnvelope(RF,frqBW);
        tempRF_Size = sum(tempRF_Y)/(RF.Freq*1000);
        RF.factor(1) = (RF.FA/180*pi)/gamma/tempRF_Size;
        % left out so RF amplitude purly depends on input ampltiude not FA
        %tempRF_Y = tempRF_Y .* RF.factor(1);

        spokeDirs = spokeDirections(MatSize2);
        mainBlock = buildSpokeSeries(spokeDirs,1,tempRF_Y,...
            startTime,RF,ADC,Gread,readDelay,tailDelay);

        varargout{1}.Main.RF.dPhs = 0;
        varargout{1}.Main.RF.tStep = mainBlock.tStep;
        varargout{1}.Main.RF.value = mainBlock.RF;

        varargout{1}.Main.DFreq.tStep = mainBlock.tStep;
        varargout{1}.Main.DFreq.value = mainBlock.DFreq;

        varargout{1}.Main.ADC.tStep = mainBlock.tStep;
        varargout{1}.Main.ADC.value = mainBlock.ADC;

        varargout{1}.Main.Gfe.tStep = mainBlock.tStep;
        varargout{1}.Main.Gfe.value = mainBlock.Gfe;
        varargout{1}.Main.Gfe.increment = zeros(size(mainBlock.Gfe));

        varargout{1}.Main.Gpe.tStep = mainBlock.tStep;
        varargout{1}.Main.Gpe.value = mainBlock.Gpe;
        varargout{1}.Main.Gpe.increment = zeros(size(mainBlock.Gpe));

        varargout{1}.Main.Gss.tStep = mainBlock.tStep;
        varargout{1}.Main.Gss.value = mainBlock.Gss;
        varargout{1}.Main.Gss.increment = zeros(size(mainBlock.Gss));

        varargout{1}.Main.repeat = 1;
        varargout{1}.TR = TR * MatSize2;

        % The sequence plot GUI expects repeat-based excitations, but the 3D
        % radial spokes are exported as one concatenated waveform block.
        % Provide preview metadata so Setup only renders the first spokes.
        varargout{1}.Plot.mode = 'excitationPreview';
        varargout{1}.Plot.previewExcitations = min(8,MatSize2);
        varargout{1}.Plot.excitationCount = MatSize2;
        varargout{1}.Plot.sliceAxisLabel = 'Z';
        varargout{1}.Plot.kspacePreview.samplesPerSpoke = MatSize1;
        varargout{1}.Plot.kspacePreview.spokeDirections = spokeDirs;
        varargout{1}.Plot.kspacePreview.previewSpokes = min(64,MatSize2);

        if dummy > 0
            dummyDir = representativeDirection(spokeDirs,GradOn);
            dummyBlock = buildSpokeBlock(dummyDir,0,tempRF_Y,...
                startTime,RF,ADC,Gread,readDelay,tailDelay);

            varargout{1}.Dummy.tStep = dummyBlock.tStep;
            varargout{1}.Dummy.RF.dPhs = 0;
            varargout{1}.Dummy.RF.tStep = dummyBlock.tStep;
            varargout{1}.Dummy.RF.value = dummyBlock.RF;

            varargout{1}.Dummy.DFreq.tStep = dummyBlock.tStep;
            varargout{1}.Dummy.DFreq.value = dummyBlock.DFreq;

            varargout{1}.Dummy.ADC.tStep = dummyBlock.tStep;
            varargout{1}.Dummy.ADC.value = dummyBlock.ADC;

            varargout{1}.Dummy.Gfe.tStep = dummyBlock.tStep;
            varargout{1}.Dummy.Gfe.value = dummyBlock.Gfe;

            varargout{1}.Dummy.Gpe.tStep = dummyBlock.tStep;
            varargout{1}.Dummy.Gpe.value = dummyBlock.Gpe;

            varargout{1}.Dummy.Gss.tStep = dummyBlock.tStep;
            varargout{1}.Dummy.Gss.value = dummyBlock.Gss;

            varargout{1}.Dummy.repeat = dummy;
        else
            varargout{1}.Dummy.repeat = 0;
        end
    end

    %% Return [minTE, minTR, minTI]
    if nargout > 1
        varargout{1} = minTE;
        varargout{2} = minTR;
        if nargout > 2
            % TI is handled at the protocol/engine layer rather than in the
            % exported sequence waveform, so this generator only enforces a
            % non-negative value.
            varargout{3} = minTI;
        end
    end

end

function amp = readoutAmp(gamma,bw,fovMm)
    % RAD_3D acquires one center-out half-spoke per TR, so the readout only
    % needs to reach the Nyquist edge rather than traverse a full spoke.
    amp = 1/gamma * pi * (bw*1000) / (max(fovMm,1e-6)/1000) * 1000;
end

function env = makeRFEnvelope(RF,frqBW)
    switch RF.Shape
        case 1 % Sinc
            if RF.Num == 1
                env = 1;
            else
                tempRF_X = -(2/frqBW):(4/frqBW/(RF.Num-1)):(2/frqBW);
                env = sinc(tempRF_X * frqBW);
            end
        case 2 % Rect
            env = ones(1,RF.Num);
        case 3 % Gauss
            env = (gausswin(RF.Num))';
        otherwise
            env = ones(1,RF.Num);
    end
end

function dirs = spokeDirections(numSpokes)
    goldenAngle = pi * (3 - sqrt(5));
    spokeIdx = (1:numSpokes)';
    z = -1 + 2*(spokeIdx - 0.5) / numSpokes;
    r = sqrt(max(0,1 - z.^2));
    phi = (spokeIdx - 1) * goldenAngle;
    dirs = [r .* cos(phi), r .* sin(phi), z];
end

function dirVec = representativeDirection(dirs,GradOn)
    if ~isempty(dirs)
        dirVec = dirs(1,:);
        return;
    end

    dirVec = [GradOn.fe, GradOn.pe, GradOn.ss] ~= 0;
    if any(dirVec)
        dirVec = dirVec ./ norm(dirVec);
    else
        dirVec = [0,0,0];
    end
end

function block = emptyBlock()
    block.tStep = [];
    block.RF = [];
    block.DFreq = [];
    block.ADC = [];
    block.Gfe = [];
    block.Gpe = [];
    block.Gss = [];
end

function block = buildSpokeSeries(spokeDirs,acquire,tempRF_Y,...
    startTime,RF,ADC,Gread,readDelay,tailDelay)

    numSpokes = size(spokeDirs,1);
    if numSpokes == 0
        block = emptyBlock();
        return;
    end

    tStepCells = cell(1,numSpokes);
    rfCells = cell(1,numSpokes);
    dFreqCells = cell(1,numSpokes);
    adcCells = cell(1,numSpokes);
    gfeCells = cell(1,numSpokes);
    gpeCells = cell(1,numSpokes);
    gssCells = cell(1,numSpokes);

    for n = 1:numSpokes
        spokeBlock = buildSpokeBlock(spokeDirs(n,:),acquire,tempRF_Y,...
            startTime,RF,ADC,Gread,readDelay,tailDelay);
        tStepCells{n} = spokeBlock.tStep;
        rfCells{n} = spokeBlock.RF;
        dFreqCells{n} = spokeBlock.DFreq;
        adcCells{n} = spokeBlock.ADC;
        gfeCells{n} = spokeBlock.Gfe;
        gpeCells{n} = spokeBlock.Gpe;
        gssCells{n} = spokeBlock.Gss;
    end

    block.tStep = [tStepCells{:}];
    block.RF = [rfCells{:}];
    block.DFreq = [dFreqCells{:}];
    block.ADC = [adcCells{:}];
    block.Gfe = [gfeCells{:}];
    block.Gpe = [gpeCells{:}];
    block.Gss = [gssCells{:}];
end

function block = buildSpokeBlock(dirVec,acquire,tempRF_Y,...
    startTime,RF,ADC,Gread,readDelay,tailDelay)

    numSamples = max(1,round(ADC.numSamples));
    dwell = ADC.duration / numSamples;
    eventFlag = -1;
    gRead = dirVec .* Gread.amp;

    if acquire == 1
        adcRead = ones(1,numSamples);
    else
        adcRead = zeros(1,numSamples);
    end

    gRewind = gRead * Gread.rewind.scale;
    numEntries = 1 + RF.Num + (readDelay > 0) + numSamples + ...
        (Gread.rewind.duration > 0) + (tailDelay > 0);

    block.tStep = zeros(1,numEntries);
    block.RF = zeros(1,numEntries) + 0i;
    block.DFreq = zeros(1,numEntries);
    block.ADC = zeros(1,numEntries);
    block.Gfe = zeros(1,numEntries);
    block.Gpe = zeros(1,numEntries);
    block.Gss = zeros(1,numEntries);

    idx = 1;
    block.tStep(idx) = startTime;
    block.ADC(idx) = eventFlag;
    idx = idx + 1;

    rfIdx = idx:(idx + RF.Num - 1);
    block.tStep(rfIdx) = 1 / RF.Freq;
    block.RF(rfIdx) = tempRF_Y .* (1 + 0i);
    idx = rfIdx(end) + 1;

    if readDelay > 0
        block.tStep(idx) = readDelay;
        idx = idx + 1;
    end

    adcIdx = idx:(idx + numSamples - 1);
    block.tStep(adcIdx) = dwell;
    block.ADC(adcIdx) = adcRead;
    block.Gfe(adcIdx) = gRead(1);
    block.Gpe(adcIdx) = gRead(2);
    block.Gss(adcIdx) = gRead(3);
    idx = adcIdx(end) + 1;

    if Gread.rewind.duration > 0
        block.tStep(idx) = Gread.rewind.duration;
        block.Gfe(idx) = gRewind(1);
        block.Gpe(idx) = gRewind(2);
        block.Gss(idx) = gRewind(3);
        idx = idx + 1;
    end

    if tailDelay > 0
        block.tStep(idx) = tailDelay;
    end
end
