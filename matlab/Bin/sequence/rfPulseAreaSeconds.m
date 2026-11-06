function pulseAreaSeconds = rfPulseAreaSeconds(RF)
%RFPULSEAREASECONDS Integrate the sampled, normalized RF envelope in seconds.
% RF.Duration is in ms, RF.Num is the sample count and RF.Shape selects
% Sinc (1), Rect (2) or Gauss (3).

if isnan(RF.Duration) || isnan(RF.Num) || isnan(RF.Shape)
    pulseAreaSeconds = NaN;
    return;
end

rfDurationMs = max(realmin('single'),RF.Duration);
rfNum = max(1,round(RF.Num));
if RF.Shape == 1 && rfNum == 1
    rfNum = 2;
end

rfSampleRateKHz = rfNum / rfDurationMs;
bandwidthHz = 4/rfDurationMs*1000;

switch RF.Shape
    case 1
        sampleTimes = -(2/bandwidthHz):(4/bandwidthHz/(rfNum-1)):(2/bandwidthHz);
        envelope = sinc(sampleTimes * bandwidthHz);
    case 2
        envelope = ones(1,rfNum);
    case 3
        envelope = (gausswin(rfNum))';
    otherwise
        envelope = ones(1,rfNum);
end

pulseAreaSeconds = sum(envelope)/(rfSampleRateKHz*1000);
end
