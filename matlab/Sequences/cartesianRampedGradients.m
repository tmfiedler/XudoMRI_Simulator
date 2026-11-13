function [timing,gradients] = cartesianRampedGradients(TE,TR,matrixSize,fov, ...
    rfDuration,bandwidth,enabled,slice,gammaHz,limits,startTime,sequence)
%CARTESIANRAMPEDGRADIENTS Design Cartesian gradient lobes in mT/m and ms.
% Each linear ramp is exported as raster intervals at their mean amplitudes.
validateattributes(limits,{'numeric'},{'row','numel',3,'real','finite','positive'});
maxGradient = limits(1);
slew = limits(2); % T/m/s = (mT/m)/ms
raster = limits(3)/1000;
validateattributes(bandwidth,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(rfDuration,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(fov,{'numeric'},{'real','finite','positive'});
sliceThickness = [];
if enabled.ss
    sliceThickness = slice.TH;
    validateattributes(sliceThickness,{'numeric'},{'scalar','real','finite','positive'});
end
[maxBandwidth,minRFDuration] = cartesianGradientBounds(fov(1),sliceThickness,enabled,gammaHz,maxGradient);
adcDuration = matrixSize(1)/bandwidth;
readAmplitude = 0;
sliceAmplitude = 0;
phaseArea = 0;
if enabled.fe
    if bandwidth > maxBandwidth
        error('Sequence:GradientLimit','Maximum ADC bandwidth is %.6g kHz at this FOV and nucleus.',maxBandwidth);
    end
    readAmplitude = maxGradient*(bandwidth/maxBandwidth);
end
if enabled.ss
    if rfDuration < minRFDuration
        error('Sequence:GradientLimit','Minimum RF duration is %.6g ms at this slice thickness and nucleus.',minRFDuration);
    end
    sliceAmplitude = maxGradient*(minRFDuration/rfDuration);
end
if enabled.pe && matrixSize(2) > 1
    phaseArea = -(matrixSize(2)-1)/2 * 1e9/(gammaHz*fov(2));
end

readTicks = ceil(abs(readAmplitude)/(slew*raster));
sliceTicks = ceil(abs(sliceAmplitude)/(slew*raster));
readRise = readTicks*raster;
sliceRise = sliceTicks*raster;
% The readout starts at -N/2 sample steps. Refocus slice phase from RF center.
pre = areaLobe(-readAmplitude*(adcDuration+readRise)/2);
rephase = areaLobe(-sliceAmplitude*(rfDuration+sliceRise)/2);
phase = areaLobe(phaseArea);
spinEcho = strcmp(sequence,'SE');
epi = strcmp(sequence,'GRE_EPI');
lineCount = matrixSize(2);
trainDuration = adcDuration;
if epi
    blipArea = enabled.pe*1e9/(gammaHz*fov(2));
    blip = areaLobe(blipArea);
    gap = max(2*readRise,blip.duration);
    trainDuration = adcDuration*lineCount+gap*(lineCount-1);
end
timing.rfStart = startTime + sliceRise;
encodingTime = max([pre.duration+readRise, rephase.duration+sliceRise, phase.duration]);
halfWidths = (rfDuration+trainDuration)/2;
rewindTime = readRise;
if spinEcho
    % Fit the two slice lobes between RF pulses and all encoding before ADC.
    timing.minTE = 2*max(rfDuration+2*(rephase.duration+sliceRise), ...
        halfWidths+encodingTime);
    rewindTime = max(readRise+pre.duration,phase.duration);
else
    timing.minTE = halfWidths+encodingTime;
end
timing.minTR = timing.rfStart+halfWidths+max(TE,timing.minTE)+rewindTime;
if nargout == 1
    return;
end
if spinEcho
    % SE has always generated at the effective timing when asked for less.
    TE = max(TE,timing.minTE);
    TR = max(TR,timing.minTR);
end
timing.TE = TE;
timing.TR = TR;
validateattributes(TE,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(TR,{'numeric'},{'scalar','real','finite','positive'});
if TE < timing.minTE-1e-10 || TR < timing.minTR-1e-10
    error('Sequence:GradientTiming','Scanner profile requires TE >= %.6g ms and TR >= %.6g ms.', ...
        timing.minTE,timing.minTR);
end

rfEnd = timing.rfStart+rfDuration;
adcStart = timing.rfStart+(rfDuration-trainDuration)/2+TE;
[readSteps,readValues] = plateau(readAmplitude,readTicks,adcDuration);
[sliceSteps,sliceValues] = plateau(sliceAmplitude,sliceTicks,rfDuration);
preSteps = lobeSteps(pre);
preValues = lobeValues(pre);
rephaseSteps = lobeSteps(rephase);
rephaseValues = lobeValues(rephase);
phaseSteps = lobeSteps(phase);
phaseValues = lobeValues(phase);
feSteps = [preSteps,readSteps];
feValues = [preValues,readValues];
ssSteps = [sliceSteps,rephaseSteps];
ssValues = [sliceValues,rephaseValues];
if epi
    % Each inter-line FE transition integrates to zero, including when
    % the PE blip needs extra time at zero readout gradient.
    up = ramp(readAmplitude,readTicks);
    rampSteps = repmat(raster,1,readTicks);
    polarity = (-1).^(0:lineCount-1);
    feTrainSteps = repmat([rampSteps,adcDuration,rampSteps,gap-2*readRise].',1,lineCount);
    feTrainSteps(end,end) = 0;
    feTrainValues = [up,readAmplitude,fliplr(up),0].'.*polarity;
    feSteps = [preSteps,feTrainSteps(:).'];
    feValues = [preValues,feTrainValues(:).'];

    blipSteps = lobeSteps(blip);
    blipValues = lobeValues(blip);
    peBetweenSteps = repmat([adcDuration,blipSteps,gap-blip.duration],1,lineCount-1);
    peBetweenValues = repmat([0,blipValues,0],1,lineCount-1);
    phaseSteps = [phaseSteps,adcStart-rfEnd-phase.duration,peBetweenSteps,adcDuration];
    phaseValues = [phaseValues,0,peBetweenValues,0];
    dwell = ones(1,matrixSize(1))/bandwidth;
    adcSteps = [repmat([dwell,gap],1,lineCount-1),dwell];
    adcValues = [repmat([ones(size(dwell)),0],1,lineCount-1),ones(size(dwell))];
    gradients.ADC = struct('tStep',[startTime,adcStart-startTime,adcSteps, ...
        max(0,TR-adcStart-trainDuration)],'value',[-2,0,adcValues,0]);
elseif spinEcho
    feSteps = [feSteps,preSteps];
    feValues = [feValues,preValues];
    sliceGap = max(0,TE/2-rfDuration-2*(sliceRise+rephase.duration));
    ssSteps = [ssSteps,sliceGap,rephaseSteps,sliceSteps,rephaseSteps];
    ssValues = [ssValues,0,rephaseValues,sliceValues,rephaseValues];
    rfEnd = rfEnd+TE/2;
    phaseGap = adcStart+adcDuration-rfEnd-phase.duration;
    phaseSteps = [phaseSteps,phaseGap,phaseSteps];
    phaseValues = [phaseValues,0,-phaseValues];
end
gradients.Gfe = channel(adcStart-readRise-pre.duration,feSteps,feValues);
gradients.Gss = channel(startTime,ssSteps,ssValues);
gradients.Gpe = channel(rfEnd,phaseSteps,phaseValues);
gradients.Gpe.increment = zeros(size(gradients.Gpe.value));
if ~epi && phaseArea ~= 0
    gradients.Gpe.increment = -2*gradients.Gpe.value/(matrixSize(2)-1);
end

    function lobe = areaLobe(area)
        lobe = gradientAreaLobe(area,maxGradient,slew,raster);
    end

    function steps = lobeSteps(lobe)
        steps = [repmat(raster,1,lobe.rise), lobe.flat*raster, repmat(raster,1,lobe.rise)];
    end

    function values = lobeValues(lobe)
        up = ramp(lobe.peak,lobe.rise);
        values = [up,lobe.peak,fliplr(up)];
    end

    function result = channel(start,steps,values)
        steps = [start,steps,max(0,TR-start-sum(steps))];
        values = [0,values,0];
        keep = steps > 1e-12;
        result = struct('tStep',steps(keep),'value',values(keep));
    end

    function [steps,values] = plateau(amplitude,ticks,duration)
        up = ramp(amplitude,ticks);
        rampSteps = repmat(raster,1,ticks);
        steps = [rampSteps,duration,rampSteps];
        values = [up,amplitude,fliplr(up)];
    end
end

function values = ramp(peak,ticks)
values = peak*((1:ticks)-0.5)/ticks;
end
