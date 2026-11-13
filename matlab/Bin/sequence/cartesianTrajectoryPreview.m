function [path,samples] = cartesianTrajectoryPreview(main,gradientFields,gammaHz)
%CARTESIANTRAJECTORYPREVIEW Integrate the exported in-plane gradient timeline.
% The input uses mT/m and ms. Negative ADC events reset the nominal integral.
duration = main.Time.value(:);
events = main.ADC.value(:);
sampleRows = events == 1;
offset = main.SampleOffset.value(sampleRows);
reset = events < 0;
count = numel(duration);
repeats = main.Time.repeat;
fields = {main.(gradientFields{1}),main.(gradientFields{2})};
pathBlocks = cell(repeats,1);
sampleBlocks = cell(repeats,1);
k = [0 0];
% Index the last reset before each interval, with row 1 as the block start.
lastReset = cummax([1; 1+(1:count)'.*reset]);
fromBlockStart = lastReset(1:end-1)==1;
for block = 1:repeats
    gradient = zeros(count,2);
    for axis = 1:2
        values = fields{axis}.value;
        first = mod(block-1,repeats/fields{axis}.repeat)*count;
        gradient(:,axis) = values(first+(1:count));
    end
    rate = gradient*(gammaHz*1e-6);
    step = rate.*duration;
    step(reset,:) = 0;
    integral = [0 0; cumsum(step,1)];
    starts = integral(1:end-1,:) - integral(lastReset(1:end-1),:);
    starts(fromBlockStart,:) = starts(fromBlockStart,:)+k;
    ends = starts+step;
    sampleBlocks{block} = starts(sampleRows,:)+rate(sampleRows,:).*offset(:);
    % Keep the turns and ramp endpoints, with a break at each reset.
    moving = any(step ~= 0,2);
    vertices = [reshape([starts(:,1),ends(:,1)].',[],1), ...
        reshape([starts(:,2),ends(:,2)].',[],1)];
    vertices(repelem(reset,2),:) = NaN;
    pathBlocks{block} = vertices(repelem(moving | reset,2),:);
    k = ends(end,:);
    if reset(end)
        k = [0 0];
    end
end
path = vertcat(pathBlocks{:});
samples = vertcat(sampleBlocks{:});
end
