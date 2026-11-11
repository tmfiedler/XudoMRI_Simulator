function Output = combineSeqRect(interSeqData,orientation,peDirection,dummy,preserveLogicalAxes)

    if nargin < 5
        preserveLogicalAxes = false;
    end

    if canUseAlignedFastPath(interSeqData,dummy)
        Result = buildAlignedResult(interSeqData,dummy);
    else
        %% Generate new tAbs
        if dummy > 0
            interSeqData.Dummy.RF.tAbs = cumsum(interSeqData.Dummy.RF.tStep);
            interSeqData.Dummy.DFreq.tAbs = cumsum(interSeqData.Dummy.DFreq.tStep);
            interSeqData.Dummy.Gfe.tAbs = cumsum(interSeqData.Dummy.Gfe.tStep);
            interSeqData.Dummy.Gpe.tAbs = cumsum(interSeqData.Dummy.Gpe.tStep);
            interSeqData.Dummy.Gss.tAbs = cumsum(interSeqData.Dummy.Gss.tStep);
            interSeqData.Dummy.ADC.tAbs = cumsum(interSeqData.Dummy.ADC.tStep);
        end;

        interSeqData.Main.RF.tAbs = cumsum(interSeqData.Main.RF.tStep);
        interSeqData.Main.DFreq.tAbs = cumsum(interSeqData.Main.DFreq.tStep);
        interSeqData.Main.Gfe.tAbs = cumsum(interSeqData.Main.Gfe.tStep);
        interSeqData.Main.Gpe.tAbs = cumsum(interSeqData.Main.Gpe.tStep);
        interSeqData.Main.Gss.tAbs = cumsum(interSeqData.Main.Gss.tStep);
        interSeqData.Main.ADC.tAbs = cumsum(interSeqData.Main.ADC.tStep);

        % for Main
        temp1 = unique(mergesort(interSeqData.Main.Gfe.tAbs,interSeqData.Main.Gpe.tAbs));
        temp2 = unique(mergesort(temp1,interSeqData.Main.Gss.tAbs)); clear temp1;
        temp3 = unique(mergesort(temp2,interSeqData.Main.ADC.tAbs)); clear temp2;
        temp4 = unique(mergesort(interSeqData.Main.DFreq.tAbs,interSeqData.Main.RF.tAbs));
        Result.Main.tAbs = unique(mergesort(temp3,temp4)); clear temp3 temp4;
        Result.Main.repeat = interSeqData.Main.repeat;
        Result.Main.RF.dPhs = interSeqData.Main.RF.dPhs;

        % for Dummy
        if dummy > 0
            temp1 = unique(mergesort(interSeqData.Dummy.Gfe.tAbs,interSeqData.Dummy.Gpe.tAbs));
            temp2 = unique(mergesort(temp1,interSeqData.Dummy.Gss.tAbs)); clear temp1;
            temp3 = unique(mergesort(temp2,interSeqData.Dummy.ADC.tAbs)); clear temp2;
            temp4 = unique(mergesort(interSeqData.Dummy.DFreq.tAbs,interSeqData.Dummy.RF.tAbs));
            Result.Dummy.tAbs = unique(mergesort(temp3,temp4)); clear temp3 temp4;
            Result.Dummy.repeat = interSeqData.Dummy.repeat;
            Result.Dummy.RF.dPhs = interSeqData.Dummy.RF.dPhs;
        end;

        %% Interpolation

        % For Main
        % When inserting data for ADC sequence, the new data value should be
        % 0;
        Result.Main.ADC.value = seqInterp(interSeqData.Main.ADC.value,interSeqData.Main.ADC.tAbs,Result.Main.tAbs,1);

        % When inserting data for other sequences, the new data value should
        % equal to the previous data.

        Result.Main.RF.value = round(seqInterp(interSeqData.Main.RF.value,interSeqData.Main.RF.tAbs,Result.Main.tAbs,2)*1000000000)/1000000000;
        Result.Main.DFreq.value = round(seqInterp(interSeqData.Main.DFreq.value,interSeqData.Main.DFreq.tAbs,Result.Main.tAbs,2)*1000000000)/1000000000;

        Result.Main.Gfe.value = round(seqInterp(interSeqData.Main.Gfe.value,interSeqData.Main.Gfe.tAbs,Result.Main.tAbs,2)*1000000000)/1000000000;
        try %#ok<TRYNC>
            Result.Main.Gfe.increment = round(seqInterp(interSeqData.Main.Gfe.increment,interSeqData.Main.Gfe.tAbs,Result.Main.tAbs,2)*1000000000)/1000000000;
        end;

        Result.Main.Gpe.value = round(seqInterp(interSeqData.Main.Gpe.value,interSeqData.Main.Gpe.tAbs,Result.Main.tAbs,2)*1000000000)/1000000000;
        try %#ok<TRYNC>
            Result.Main.Gpe.increment = round(seqInterp(interSeqData.Main.Gpe.increment,interSeqData.Main.Gpe.tAbs,Result.Main.tAbs,2)*1000000000)/1000000000;
        end;

        Result.Main.Gss.value = round(seqInterp(interSeqData.Main.Gss.value,interSeqData.Main.Gss.tAbs,Result.Main.tAbs,2)*1000000000)/1000000000;
        try %#ok<TRYNC>
            Result.Main.Gss.increment = round(seqInterp(interSeqData.Main.Gss.increment,interSeqData.Main.Gss.tAbs,Result.Main.tAbs,2)*1000000000)/1000000000;
        end;

        if dummy > 0
            % For Dummy
            % When inserting data for ADC sequence, the new data value should be
            % 0;
            Result.Dummy.ADC.value = round(seqInterp(interSeqData.Dummy.ADC.value,interSeqData.Dummy.ADC.tAbs,Result.Dummy.tAbs,1)*1000000000)/1000000000;

            % When inserting data for other sequences, the new data value should
            % equal to the previous data.

            Result.Dummy.RF.value = round(seqInterp(interSeqData.Dummy.RF.value,interSeqData.Dummy.RF.tAbs,Result.Dummy.tAbs,2)*1000000000)/1000000000;
            Result.Dummy.DFreq.value = round(seqInterp(interSeqData.Dummy.DFreq.value,interSeqData.Dummy.DFreq.tAbs,Result.Dummy.tAbs,2)*1000000000)/1000000000;
            Result.Dummy.Gfe.value = round(seqInterp(interSeqData.Dummy.Gfe.value,interSeqData.Dummy.Gfe.tAbs,Result.Dummy.tAbs,2)*1000000000)/1000000000;
            Result.Dummy.Gpe.value = round(seqInterp(interSeqData.Dummy.Gpe.value,interSeqData.Dummy.Gpe.tAbs,Result.Dummy.tAbs,2)*1000000000)/1000000000;
            Result.Dummy.Gss.value = round(seqInterp(interSeqData.Dummy.Gss.value,interSeqData.Dummy.Gss.tAbs,Result.Dummy.tAbs,2)*1000000000)/1000000000;
        end;
    end
    
    %% Sequence Generation
    
    Result.Main = attachADCWindows(Result.Main,interSeqData.Main);
    if dummy > 0
        Result.Dummy = attachADCWindows(Result.Dummy,interSeqData.Dummy);
    end

    % Main
    Output.Main.Time.value = [Result.Main.tAbs(1),diff(Result.Main.tAbs)];
    Output.Main.Time.repeat = Result.Main.repeat;
    
    Output.Main.ADC.value = Result.Main.ADC.value;
    Output.Main.ADC.repeat = Result.Main.repeat;
    Output.Main.SampleOffset = struct('value',Result.Main.SampleOffset,'repeat',Result.Main.repeat);
    Output.Main.Dwell = struct('value',Result.Main.Dwell,'repeat',Result.Main.repeat);
       
    if Result.Main.RF.dPhs ~= 0
        Output.Main.RF.value = Result.Main.RF.value;
        for n=1:(Result.Main.repeat-1)
            Output.Main.RF.value = [Output.Main.RF.value, Result.Main.RF.value * exp(Result.Main.RF.dPhs*n/180*pi*1i)];
        end;
        Output.Main.RF.repeat = 1;
        
        Output.Main.DFreq.value = Result.Main.DFreq.value;
        for n=1:(Result.Main.repeat-1)
            Output.Main.DFreq.value = [Output.Main.DFreq.value, Result.Main.DFreq.value];
        end;
        Output.Main.DFreq.repeat = 1;
    else
        Output.Main.RF.value = Result.Main.RF.value;
        Output.Main.RF.repeat = Result.Main.repeat;
        
        Output.Main.DFreq.value = Result.Main.DFreq.value;
        Output.Main.DFreq.repeat = Result.Main.repeat;
    end;
        
    axesXYZ = [1 2 3];
    peSign = 1;
    if ~preserveLogicalAxes
        direction = peDirection{1};
        swapInPlane = (orientation == 1 && any(direction(1) == 'LR')) || ...
            (orientation ~= 1 && any(direction(1) == 'FH'));
        axesXYZ = cartesianAxes(orientation,swapInPlane);
        peSign = 1 - 2*ismember(direction,{'A--P','R--L','H--F'});
    end
    fields = {'Gx','Gy','Gz'};
    fe = fields{axesXYZ(1)};
    pe = fields{axesXYZ(2)};
    ss = fields{axesXYZ(3)};
    Output.Main.(fe).value = Result.Main.Gfe.value;
    Output.Main.(fe).repeat = Result.Main.repeat;
    if isfield(Result.Main.Gpe,'increment')
        increment = Result.Main.Gpe.increment;
    else
        increment = seqInterp(interSeqData.Main.Gpe.increment,interSeqData.Main.Gpe.tAbs,Result.Main.tAbs,2);
    end
    Output.Main.(pe).value = peSign .* Result.Main.Gpe.value;
    for n = 1:(Result.Main.repeat-1)
        Output.Main.(pe).value = [Output.Main.(pe).value, ...
            peSign .* (Result.Main.Gpe.value + increment .* n)];
    end
    Output.Main.(pe).repeat = 1;
    Output.Main.(ss).value = Result.Main.Gss.value;
    Output.Main.(ss).repeat = Result.Main.repeat;

    % Dummy
    if dummy>0
        Output.Dummy.Time.value = [Result.Dummy.tAbs(1),diff(Result.Dummy.tAbs)];
        Output.Dummy.Time.repeat = Result.Dummy.repeat;

        Output.Dummy.ADC.value = Result.Dummy.ADC.value;
        Output.Dummy.ADC.repeat = Result.Dummy.repeat;
        Output.Dummy.SampleOffset = struct('value',Result.Dummy.SampleOffset,'repeat',Result.Dummy.repeat);
        Output.Dummy.Dwell = struct('value',Result.Dummy.Dwell,'repeat',Result.Dummy.repeat);

        if Result.Dummy.RF.dPhs ~= 0
            Output.Dummy.RF.value = Result.Dummy.RF.value;
            for n=1:(Result.Dummy.repeat-1)
                Output.Dummy.RF.value = [Output.Dummy.RF.value, Result.Dummy.RF.value * exp(-Result.Dummy.RF.dPhs*n/180*pi*1i)];
            end;
            Output.Dummy.RF.repeat = 1;

            Output.Dummy.DFreq.value = Result.Dummy.DFreq.value;
            for n=1:(Result.Dummy.repeat-1)
                Output.Dummy.DFreq.value = [Output.Dummy.DFreq.value, Result.Dummy.DFreq.value];
            end;
            Output.Dummy.DFreq.repeat = 1;
        else
            Output.Dummy.RF.value = Result.Dummy.RF.value;
            Output.Dummy.RF.repeat = Result.Dummy.repeat;

            Output.Dummy.DFreq.value = Result.Dummy.DFreq.value;
            Output.Dummy.DFreq.repeat = Result.Dummy.repeat;
        end;
        
        %%
        Output.Dummy.(fe).value = Result.Dummy.Gfe.value;
        Output.Dummy.(fe).repeat = Result.Dummy.repeat;
        Output.Dummy.(pe).value = peSign .* Result.Dummy.Gpe.value;
        Output.Dummy.(pe).repeat = Result.Dummy.repeat;
        Output.Dummy.(ss).value = Result.Dummy.Gss.value;
        Output.Dummy.(ss).repeat = Result.Dummy.repeat;
    end;
    
    if dummy > 0
        try
            hasError = (length(Output.Main.Time.value) * Output.Main.Time.repeat ~= length(Output.Main.ADC.value) * Output.Main.ADC.repeat)...
                +...
            (length(Output.Main.Time.value) * Output.Main.Time.repeat ~= length(Output.Main.RF.value) * Output.Main.RF.repeat)...
                +...
            (length(Output.Main.RF.value) ~= length(Output.Main.DFreq.value)) + (Output.Main.RF.repeat ~= Output.Main.DFreq.repeat)...
                +...
            (length(Output.Main.Time.value) * Output.Main.Time.repeat ~= length(Output.Main.Gx.value) * Output.Main.Gx.repeat)...
                +...
            (length(Output.Main.Time.value) * Output.Main.Time.repeat ~= length(Output.Main.Gy.value) * Output.Main.Gy.repeat)...
                +...
            (length(Output.Main.Time.value) * Output.Main.Time.repeat ~= length(Output.Main.Gz.value) * Output.Main.Gz.repeat)...
                +...
            (length(Output.Dummy.Time.value) * Output.Dummy.Time.repeat ~= length(Output.Dummy.ADC.value) * Output.Dummy.ADC.repeat)...
                +...
            (length(Output.Dummy.Time.value) * Output.Dummy.Time.repeat ~= length(Output.Dummy.RF.value) * Output.Dummy.RF.repeat)...
                +...
            (length(Output.Dummy.RF.value) ~= length(Output.Dummy.DFreq.value)) + (Output.Dummy.RF.repeat ~= Output.Dummy.DFreq.repeat)...
                +...
            (length(Output.Dummy.Time.value) * Output.Dummy.Time.repeat ~= length(Output.Dummy.(fe).value) * Output.Dummy.(fe).repeat)...
                +...
            (length(Output.Dummy.Time.value) * Output.Dummy.Time.repeat ~= length(Output.Dummy.(pe).value) * Output.Dummy.(pe).repeat)...
                +...
            (length(Output.Dummy.Time.value) * Output.Dummy.Time.repeat ~= length(Output.Dummy.(ss).value) * Output.Dummy.(ss).repeat);
            if hasError
                error('Sequence channel lengths are inconsistent.');
            end
        
        catch %#ok<CTCH>
            msgbox('Sequence Error!');
            error('Sequence Error!');
        end;
    else
        try
            hasError = (length(Output.Main.Time.value) * Output.Main.Time.repeat ~= length(Output.Main.ADC.value) * Output.Main.ADC.repeat)...
                +...
            (length(Output.Main.Time.value) * Output.Main.Time.repeat ~= length(Output.Main.RF.value) * Output.Main.RF.repeat)...
                +...
            (length(Output.Main.RF.value) ~= length(Output.Main.DFreq.value)) + (Output.Main.RF.repeat ~= Output.Main.DFreq.repeat)...
                +...
            (length(Output.Main.Time.value) * Output.Main.Time.repeat ~= length(Output.Main.Gx.value) * Output.Main.Gx.repeat)...
                +...
            (length(Output.Main.Time.value) * Output.Main.Time.repeat ~= length(Output.Main.Gy.value) * Output.Main.Gy.repeat)...
                +...
            (length(Output.Main.Time.value) * Output.Main.Time.repeat ~= length(Output.Main.Gz.value) * Output.Main.Gz.repeat);
            if hasError
                error('Sequence channel lengths are inconsistent.');
            end
        catch %#ok<CTCH>
            msgbox('Sequence Error!');
            error('Sequence Error!');
        end;
    end;
    
    if dummy > 0
        Output.totalNum = length(Output.Main.Time.value) * Output.Main.Time.repeat + length(Output.Dummy.Time.value) * Output.Dummy.Time.repeat;
    else
        Output.totalNum = length(Output.Main.Time.value) * Output.Main.Time.repeat;
    end;

    function tf = canUseAlignedFastPath(interSeqData,dummy)
        tf = interSeqData.Main.repeat == 1 && channelsShareTimeline(interSeqData.Main);

        if tf && dummy > 0
            tf = channelsShareTimeline(interSeqData.Dummy);
        end
    end

    function tf = channelsShareTimeline(seqData)
        refTStep = seqData.RF.tStep;
        tf = isequal(refTStep,seqData.DFreq.tStep) && ...
            isequal(refTStep,seqData.Gfe.tStep) && ...
            isequal(refTStep,seqData.Gpe.tStep) && ...
            isequal(refTStep,seqData.Gss.tStep) && ...
            isequal(refTStep,seqData.ADC.tStep);
    end

    function Result = buildAlignedResult(interSeqData,dummy)
        Result.Main = buildAlignedResultBlock(interSeqData.Main);

        if dummy > 0
            Result.Dummy = buildAlignedResultBlock(interSeqData.Dummy);
        end
    end

    function resultBlock = buildAlignedResultBlock(seqData)
        resultBlock.tAbs = cumsum(seqData.RF.tStep);
        resultBlock.repeat = seqData.repeat;
        resultBlock.RF.dPhs = seqData.RF.dPhs;

        resultBlock.ADC.value = seqData.ADC.value;
        resultBlock.RF.value = round(seqData.RF.value*1000000000)/1000000000;
        resultBlock.DFreq.value = round(seqData.DFreq.value*1000000000)/1000000000;
        resultBlock.Gfe.value = round(seqData.Gfe.value*1000000000)/1000000000;
        resultBlock.Gpe.value = round(seqData.Gpe.value*1000000000)/1000000000;
        resultBlock.Gss.value = round(seqData.Gss.value*1000000000)/1000000000;

        if isfield(seqData.Gfe,'increment')
            resultBlock.Gfe.increment = round(seqData.Gfe.increment*1000000000)/1000000000;
        end
        if isfield(seqData.Gpe,'increment')
            resultBlock.Gpe.increment = round(seqData.Gpe.increment*1000000000)/1000000000;
        end
        if isfield(seqData.Gss,'increment')
            resultBlock.Gss.increment = round(seqData.Gss.increment*1000000000)/1000000000;
        end
    end

    %% Sequence Interpolation Function
    function result = attachADCWindows(result,source)
        % ADC observation belongs to its source window, not a field subinterval.
        adcEnds = cumsum(source.ADC.tStep);
        adcStarts = [0 adcEnds(1:end-1)];
        zeroControls = find(source.ADC.tStep == 0 & source.ADC.value < 0);
        zeroSlots = zeros(size(source.ADC.value));
        if isequal(result.tAbs,adcEnds)
            zeroSlots(zeroControls) = zeroControls;
        elseif ~isempty(zeroControls)
            % unique field clocks omit coincident zero-duration control events.
            % Merge them once, after equal endpoints and in source order. Each
            % inserted row copies the next original field row (last at the end).
            originalEnds = result.tAbs;
            originalCount = numel(originalEnds);
            mergedEnds = zeros(1,originalCount+numel(zeroControls));
            fieldIndex = zeros(size(mergedEnds));
            next = 1;
            written = 0;
            for control = zeroControls
                while next <= originalCount && originalEnds(next) <= adcEnds(control)
                    written = written+1;
                    mergedEnds(written) = originalEnds(next);
                    fieldIndex(written) = next;
                    next = next+1;
                end
                written = written+1;
                mergedEnds(written) = adcEnds(control);
                fieldIndex(written) = min(next,originalCount);
                zeroSlots(control) = written;
            end
            remaining = next:originalCount;
            mergedEnds(written+1:end) = originalEnds(remaining);
            fieldIndex(written+1:end) = remaining;
            for channel = {'RF','DFreq','Gfe','Gpe','Gss'}
                for field = {'value','increment'}
                    if isfield(result.(channel{1}),field{1})
                        values = result.(channel{1}).(field{1});
                        result.(channel{1}).(field{1}) = values(fieldIndex);
                    end
                end
            end
            result.tAbs = mergedEnds;
        end
        starts = [0 result.tAbs(1:end-1)];
        duration = result.tAbs-starts;
        result.ADC.value = zeros(size(duration));
        result.SampleOffset = zeros(size(duration));
        result.Dwell = zeros(size(duration));
        % Source events and field clocks are chronological. Separate cursors
        % preserve the earliest eligible interval for samples and controls.
        sampleIndex = 1;
        controlIndex = 1;
        intervalCount = numel(duration);
        for event = 1:numel(source.ADC.value)
            flag = source.ADC.value(event);
            if flag == 1
                width = source.ADC.tStep(event);
                if ~isfinite(width) || width <= 0
                    error('Sequence:ADCWindow','Original ADC dwell must be finite and positive.');
                end
                midpoint = adcStarts(event)+width/2;
                % An exact boundary belongs to the preceding positive interval.
                while sampleIndex <= intervalCount && ...
                        (duration(sampleIndex) <= 0 || result.tAbs(sampleIndex) < midpoint)
                    sampleIndex = sampleIndex+1;
                end
                index = sampleIndex;
                if index > intervalCount || ...
                        ~(midpoint > starts(index) && midpoint <= result.tAbs(index)) || ...
                        result.ADC.value(index) ~= 0
                    error('Sequence:ADCWindow','Cannot place original ADC midpoint in the field timeline.');
                end
                result.ADC.value(index) = 1;
                result.SampleOffset(index) = midpoint-starts(index);
                if midpoint == result.tAbs(index)
                    result.SampleOffset(index) = duration(index);
                end
                result.Dwell(index) = width;
            elseif flag < 0
                index = zeroSlots(event);
                if index == 0
                    while controlIndex <= intervalCount && ...
                            (duration(controlIndex) <= 0 || result.tAbs(controlIndex) < adcEnds(event))
                        controlIndex = controlIndex+1;
                    end
                    index = controlIndex;
                    if index > intervalCount || result.tAbs(index) ~= adcEnds(event)
                        error('Sequence:ADCControl','Cannot preserve ADC control event ordering.');
                    end
                end
                if result.ADC.value(index) ~= 0
                    error('Sequence:ADCControl','Cannot preserve ADC control event ordering.');
                end
                result.ADC.value(index) = flag;
            end
        end
    end

    function newY = seqInterp(tableY,tableX,newX,type)
        newY = 0 .* newX;
        index = 1;
        % Both clocks are sorted; retain the first equal endpoint, including
        % duplicates. A single forward sweep replaces one full search/query.
        switch type
            case 1 % for ADC
                for n=1:length(newX) %#ok<*FXUP>
                    while index <= numel(tableX) && tableX(index) < newX(n)
                        index = index+1;
                    end
                    if index > numel(tableX) || tableX(index) ~= newX(n)
                        newY(n) = 0;
                    else
                        newY(n) = tableY(index);
                    end;
                end;
            case 2 % for others
                for n=1:length(newX)
                    while index <= numel(tableX) && tableX(index) < newX(n)
                        index = index+1;
                    end
                    matched = index;
                    if index > numel(tableX), matched = []; end
                    try
                        newY(n) = tableY(matched);
                    catch
                        a=1;
                    end;
                end;
        end;
    end
end
