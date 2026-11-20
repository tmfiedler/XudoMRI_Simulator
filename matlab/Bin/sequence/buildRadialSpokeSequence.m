function sequence = buildRadialSpokeSequence(spokeDirs,startTime,RF,ADC,Gread,readDelay,tailDelay,TR,kEdge,dummy)
%BUILDRADIALSPOKESEQUENCE Assemble nonselective center-out radial excitations.
    RF.Freq = RF.Num / RF.Duration;
    tempRF_Y = makeRFEnvelope(RF,4/RF.Duration*1000);
    MatSize1 = ADC.numSamples;
    MatSize2 = size(spokeDirs,1);
    mainBlock = buildSpokeSeries(spokeDirs,1,tempRF_Y,...
        startTime,RF,ADC,Gread,readDelay,tailDelay);

    sequence.Main.RF.dPhs = 0;
    sequence.Main.RF.tStep = mainBlock.tStep;
    sequence.Main.RF.value = mainBlock.RF;

    sequence.Main.DFreq.tStep = mainBlock.tStep;
    sequence.Main.DFreq.value = mainBlock.DFreq;

    sequence.Main.ADC.tStep = mainBlock.adcStep;
    sequence.Main.ADC.value = mainBlock.ADC;

    sequence.Main.Gfe.tStep = mainBlock.tStep;
    sequence.Main.Gfe.value = mainBlock.Gfe;
    sequence.Main.Gfe.increment = zeros(size(mainBlock.Gfe));

    sequence.Main.Gpe.tStep = mainBlock.tStep;
    sequence.Main.Gpe.value = mainBlock.Gpe;
    sequence.Main.Gpe.increment = zeros(size(mainBlock.Gpe));

    sequence.Main.Gss.tStep = mainBlock.tStep;
    sequence.Main.Gss.value = mainBlock.Gss;
    sequence.Main.Gss.increment = zeros(size(mainBlock.Gss));

    sequence.Main.repeat = 1;
    sequence.TR = TR * MatSize2;

    % The sequence plot GUI expects repeat-based excitations, but the 3D
    % radial spokes are exported as one concatenated waveform block.
    % Provide preview metadata so Setup only renders the first spokes.
    sequence.Plot.mode = 'excitationPreview';
    sequence.Plot.previewExcitations = min(8,MatSize2);
    sequence.Plot.excitationCount = MatSize2;
    sequence.Plot.sliceAxisLabel = 'Z';
    sequence.Plot.kspacePreview.samplesPerSpoke = MatSize1;
    sequence.Plot.kspacePreview.kEdge = kEdge;
    sequence.Plot.kspacePreview.spokeDirections = spokeDirs;
    sequence.Plot.kspacePreview.previewSpokes = min(64,MatSize2);

    if dummy > 0
        dummyBlock = buildSpokeBlock(spokeDirs(1,:),0,tempRF_Y,...
            startTime,RF,ADC,Gread,readDelay,tailDelay);

        sequence.Dummy.tStep = dummyBlock.tStep;
        sequence.Dummy.RF.dPhs = 0;
        sequence.Dummy.RF.tStep = dummyBlock.tStep;
        sequence.Dummy.RF.value = dummyBlock.RF;

        sequence.Dummy.DFreq.tStep = dummyBlock.tStep;
        sequence.Dummy.DFreq.value = dummyBlock.DFreq;

        sequence.Dummy.ADC.tStep = dummyBlock.adcStep;
        sequence.Dummy.ADC.value = dummyBlock.ADC;

        sequence.Dummy.Gfe.tStep = dummyBlock.tStep;
        sequence.Dummy.Gfe.value = dummyBlock.Gfe;

        sequence.Dummy.Gpe.tStep = dummyBlock.tStep;
        sequence.Dummy.Gpe.value = dummyBlock.Gpe;

        sequence.Dummy.Gss.tStep = dummyBlock.tStep;
        sequence.Dummy.Gss.value = dummyBlock.Gss;

        sequence.Dummy.repeat = dummy;
    else
        sequence.Dummy.repeat = 0;
    end
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

function block = buildSpokeSeries(spokeDirs,acquire,tempRF_Y,...
    startTime,RF,ADC,Gread,readDelay,tailDelay)

    numSpokes = size(spokeDirs,1);
    tStepCells = cell(1,numSpokes);
    adcStepCells = cell(1,numSpokes);
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
        adcStepCells{n} = spokeBlock.adcStep;
        rfCells{n} = spokeBlock.RF;
        dFreqCells{n} = spokeBlock.DFreq;
        adcCells{n} = spokeBlock.ADC;
        gfeCells{n} = spokeBlock.Gfe;
        gpeCells{n} = spokeBlock.Gpe;
        gssCells{n} = spokeBlock.Gss;
    end

    block.tStep = [tStepCells{:}];
    if isfield(Gread,'during')
        block.adcStep = [adcStepCells{:}];
    else
        block.adcStep = block.tStep;
    end
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
    if isfield(Gread,'during')
        readSteps = Gread.during.steps;
        readValues = Gread.during.values;
    else
        readSteps = repmat(dwell,1,numSamples);
        readValues = repmat(Gread.amp,1,numSamples);
    end
    readCount = numel(readSteps);

    if acquire == 1
        adcRead = ones(1,numSamples);
    else
        adcRead = zeros(1,numSamples);
    end

    beforeCount = numel(Gread.before.steps);
    afterCount = numel(Gread.after.steps);
    numEntries = 1 + RF.Num + (readDelay > 0) + beforeCount + readCount + ...
        afterCount + (tailDelay > 0);

    block.tStep = zeros(1,numEntries);
    block.RF = zeros(1,numEntries) + 0i;
    block.DFreq = zeros(1,numEntries);
    block.Gfe = zeros(1,numEntries);
    block.Gpe = zeros(1,numEntries);
    block.Gss = zeros(1,numEntries);

    idx = 1;
    block.tStep(idx) = startTime;
    idx = idx + 1;

    rfIdx = idx:(idx + RF.Num - 1);
    block.tStep(rfIdx) = 1 / RF.Freq;
    block.RF(rfIdx) = tempRF_Y .* (1 + 0i);
    idx = rfIdx(end) + 1;

    if readDelay > 0
        block.tStep(idx) = readDelay;
        idx = idx + 1;
    end

    beforeIdx = idx:(idx+beforeCount-1);
    block.tStep(beforeIdx) = Gread.before.steps;
    block.Gfe(beforeIdx) = Gread.before.values*dirVec(1);
    block.Gpe(beforeIdx) = Gread.before.values*dirVec(2);
    block.Gss(beforeIdx) = Gread.before.values*dirVec(3);
    idx = idx+beforeCount;

    readIdx = idx:(idx + readCount - 1);
    block.tStep(readIdx) = readSteps;
    block.Gfe(readIdx) = readValues*dirVec(1);
    block.Gpe(readIdx) = readValues*dirVec(2);
    block.Gss(readIdx) = readValues*dirVec(3);
    idx = readIdx(end) + 1;

    afterIdx = idx:(idx+afterCount-1);
    block.tStep(afterIdx) = Gread.after.steps;
    block.Gfe(afterIdx) = Gread.after.values*dirVec(1);
    block.Gpe(afterIdx) = Gread.after.values*dirVec(2);
    block.Gss(afterIdx) = Gread.after.values*dirVec(3);
    idx = idx+afterCount;

    if tailDelay > 0
        block.tStep(idx) = tailDelay;
    end

    % Keep each original ADC window even if a gradient raster boundary splits it.
    beforeRead = 1:readIdx(1)-1;
    afterRead = readIdx(end)+1:numEntries;
    if isfield(Gread,'during')
        block.adcStep = [block.tStep(beforeRead),repmat(dwell,1,numSamples),block.tStep(afterRead)];
    else
        block.adcStep = block.tStep;
    end
    block.ADC = [eventFlag,zeros(1,numel(beforeRead)-1),adcRead,zeros(size(afterRead))];
end
