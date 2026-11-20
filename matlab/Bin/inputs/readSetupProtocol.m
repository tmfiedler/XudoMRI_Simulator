function protocol = readSetupProtocol(filename)
%READSETUPPROTOCOL Read Setup protocol text through named field accessors.
% Decode fields on demand so a load encounters errors at the field it applies.
lines = cellstr(splitlines(string(fileread(filename))));
if ~isempty(lines) && isempty(lines{end})
    lines(end) = [];
end
lines = cellfun(@strtrim,lines,'UniformOutput',false);

fields = {
    'geometryFilename', 'Geometry Filename:';
    'tissueFilename', 'Tissue Filename:';
    'deltaB0Filename', 'Delta Bo Filename:';
    'sequenceFilename', 'Sequence Filename:';
    'gxFilename', 'Gx Filename:';
    'gyFilename', 'Gy Filename:';
    'gzFilename', 'Gz Filename:';
    'kspaceFilename', 'KSpace Filename:';
    'trajectoryFilename', 'KMap Filename:';
    'noiseFilename', 'Noise Filename:';
    'sarFilename', 'SAR Filename:';
    'display', 'Display:';
    'scale', 'Scale:';
    'sliceOrientation', 'Slice Orientation:';
    'phaseEncodeDirection', 'PE Direct:';
    'sliceThicknessText', 'Slice Thickness:';
    'slicePositionText', 'Slice Position:';
    'xMinText', 'XMin:';
    'yMinText', 'YMin:';
    'zMinText', 'ZMin:';
    'xMaxText', 'XMax:';
    'yMaxText', 'YMax:';
    'zMaxText', 'ZMax:';
    'xCenterText', 'XCtr:';
    'yCenterText', 'YCtr:';
    'zCenterText', 'ZCtr:';
    'xOffsetText', 'XSet:';
    'yOffsetText', 'YSet:';
    'zOffsetText', 'ZSet:';
    'b0Text', 'B0(T):';
    'nucleus', 'Nucleus:';
    'sequenceType', 'Sequence Type:';
    'rfShape', 'RF Shape:';
    'rfDurationText', 'RF Duration(ms):';
    'rfCountText', '# Points in RF Pulse:';
    'flipAngleText', 'RF Flip Angle:';
    'fovText', 'FOV(mm)';
    'matrixSizeText', 'MatSize:';
    'adcFrequencyText', 'ADC Freq(kHz):';
    'inversionTimeText', 'TI_Duration(ms):';
    'sliceSelectText', 'SS:';
    'phaseEncodeText', 'PE:';
    'frequencyEncodeText', 'FE:';
    'dummyCountText', '#Dummy TRs:';
    'teText', 'TE(ms):';
    'trText', 'TR(ms):';
    'numIsoText', 'NumIso:';
    'cpuCountText', 'CPU #:';
    'mode', 'Mode:';
    'txCountText', '# Tx:';
    'rxCountText', '# Rx:';
    'shimB1Text', 'Shim B1+ (uT):';
    'targetB1Text', 'Target B1+ (uT):';
    'signalEngine', 'Signal Engine:';
    'nexText', 'NEX:';
};
for k = 1:size(fields,1)
    label = fields{k,2};
    protocol.(fields{k,1}) = @() valueAfter(label);
end
protocol.hasUnifiedFOV = any(strcmp(lines,'Unified FOV Prescription:'));
protocol.radialResolutionText = @() optionalValueAfter('Radial Acquisition Resolution(mm):');
protocol.radialTransitionText = @() optionalValueAfter('DA-3DPR Transition Time(ms):');
protocol.scannerProfile = @() readScannerProfile();
protocol.txWeight = @readTxWeight;
protocol.b1PlusFiles = @() filesBetween('B1p Filename:','E1p Filename:');
protocol.e1PlusFiles = @() filesBetween('E1p Filename:','# Rx:');
protocol.b1MinusFiles = @() filesBetween('B1m Filename:','E1m Filename:');
protocol.e1MinusFiles = @() filesBetween('E1m Filename:','Gx Filename:');
protocol.noiseLoading = @() readNoiseLoadingProtocol(lines);

    function profile = readScannerProfile()
        profile = [];
        name = optionalValueAfter('Scanner Profile:');
        values = optionalValueAfter('Scanner Gradient Limits:');
        if ~isempty(name) || ~isempty(values)
            limits = str2double(strsplit(strtrim(values)));
            validateattributes(limits,{'numeric'},{'row','numel',3,'real','finite','positive'});
            assert(~isempty(name) && ~strcmpi(name,'None'),'Invalid saved scanner profile.');
            profile = struct('name',name,'limits',limits);
        end
    end

    function value = valueAfter(label)
        index = fieldIndex(label)+1;
        value = lines{index};
    end

    function value = optionalValueAfter(label)
        value = '';
        if any(strcmp(lines,label))
            value = valueAfter(label);
        end
    end

    function index = fieldIndex(label)
        index = find(strcmp(lines,label));
        if ~isscalar(index) || index == numel(lines)
            error('SetupProtocol:Field', ...
                'Protocol requires one "%s" label and its value line. Recreate older protocols in Setup.',label);
        end
    end

    function weights = readTxWeight(coilIndex)
        validateattributes(coilIndex,{'numeric'},{'scalar','real','finite','integer','positive'});
        index = fieldIndex('Tx Mag & Phs:')+coilIndex;
        if index > numel(lines)
            error('SetupProtocol:TxWeight','Missing transmit weight row %d.',coilIndex);
        end
        tokens = regexp(lines{index},'\s+','split');
        decimal = '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$';
        if numel(tokens) ~= 2 || any(cellfun(@(s) isempty(regexp(s,decimal,'once')),tokens))
            error('SetupProtocol:TxWeight', ...
                'Transmit weight row %d requires two real numbers: magnitude and phase in degrees.',coilIndex);
        end
        weights = str2double(tokens);
        if any(~isfinite(weights)) || weights(1) < 0
            error('SetupProtocol:TxWeight', ...
                'Transmit weight row %d requires finite values and a nonnegative magnitude.',coilIndex);
        end
    end

    function files = filesBetween(firstLabel,nextLabel)
        first = fieldIndex(firstLabel)+1;
        last = fieldIndex(nextLabel)-1;
        if last-first == 0
            files = cell2mat(lines(first,:));
        else
            files = lines(first:last,:);
        end
    end
end
