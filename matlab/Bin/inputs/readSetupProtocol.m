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
protocol.txWeight = @readTxWeight;
protocol.b1PlusFiles = @() filesBetween('B1p Filename:','E1p Filename:');
protocol.e1PlusFiles = @() filesBetween('E1p Filename:','# Rx:');
protocol.b1MinusFiles = @() filesBetween('B1m Filename:','E1m Filename:');
protocol.e1MinusFiles = @() filesBetween('E1m Filename:','Gx Filename:');
protocol.noiseLoading = @() readNoiseLoadingProtocol(lines);

    function value = valueAfter(label)
        index = fieldIndex(label)+1;
        value = lines{index};
    end

    function index = fieldIndex(label)
        index = find(strcmp(lines,label));
        if ~isscalar(index) || index == numel(lines)
            error('SetupProtocol:Field', ...
                'Protocol requires one "%s" label and its value line. Recreate older protocols in Setup.',label);
        end
    end

    function weights = readTxWeight(coilIndex)
        index = fieldIndex('Tx Mag & Phs:')+coilIndex;
        weights = str2num(cell2mat(lines(index,:))); %#ok<ST2NM>
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
