function varargout = DA_3DPR(TE,TR,MatSize,FOV,RF,ADC,GradOn,dummy,~,nucleus,scannerLimits)
%DA_3DPR Center-out radial acquisition with the density-adapted Nagel readout.
% ADC.BW is in kHz. ADC.radialTransitionMs is optional; [] selects automatic t0.
% A smaller explicit value is raised to the earliest feasible transition.
    if ~isscalar(GradOn.fe) || ~isscalar(GradOn.pe) || ~isscalar(GradOn.ss) || ...
            GradOn.fe ~= 1 || GradOn.pe ~= 1 || GradOn.ss ~= 1
        error('DA_3DPR:RequiresThreeAxes','DA_3DPR requires all three logical radial axes.');
    end
    if nargin < 10 || isempty(nucleus)
        nucleus = getDefaultNucleus();
    end
    if nargin < 11 || isempty(scannerLimits)
        error('DA_3DPR:ScannerRequired','Select a scanner profile to design the DA-3DPR readout.');
    end
    validateattributes(scannerLimits,{'numeric'},{'row','numel',3,'real','finite','positive'});
    if ~isscalar(ADC.BW) || ~isreal(ADC.BW) || ~isfinite(ADC.BW) || ADC.BW <= 0
        error('DA_3DPR:Bandwidth','Receiver bandwidth must be positive and finite.');
    end

    matrix = max(1,round(MatSize(:).'));
    if isscalar(matrix)
        matrix = [matrix matrix];
    end
    ADC.numSamples = matrix(1);
    ADC.duration = ADC.numSamples/ADC.BW;
    [kEdge,spokeDirs,maxComponent] = radialReadoutGeometry(matrix,FOV,ADC);
    [~,gammaHz] = getNucleusGamma(nucleus);
    gamma = gammaHz/1e6; % cycles/m per (mT/m * ms)
    raster = scannerLimits(3)/1000; % ms
    slew = scannerLimits(2)/maxComponent; % (mT/m)/ms
    % The peak gradient bounds every radial sample gap by 1/FOV.
    maxGap = 1000/max([FOV(:);1]); % cycles/m
    peakLimit = min(scannerLimits(1)/maxComponent,maxGap*ADC.BW/gamma);

    requested = [];
    if isfield(ADC,'radialTransitionMs')
        requested = ADC.radialTransitionMs;
    end
    [rise,t0,peak] = designReadout(ADC.duration,raster,slew,peakLimit,kEdge/gamma,requested);
    a = t0-rise/2;
    endGradient = peak*(a/(a+3*(ADC.duration-t0)))^(2/3);
    fallTicks = ceil(endGradient/(slew*raster));
    fallTime = fallTicks*raster;
    fall = endGradient*(1-((1:fallTicks)-0.5)/fallTicks);
    [rewind,rewindSteps,rewindValues] = gradientAreaLobe( ...
        -kEdge/gamma-endGradient*fallTime/2,scannerLimits(1)/maxComponent,slew,raster);

    startTime = 0.001; % ms, radial trajectory reset interval
    minTE = RF.Duration/2;
    TE = max(TE,minTE);
    minTR = startTime + RF.Duration/2 + TE + ADC.duration + fallTime + rewind.duration;
    if nargout > 1
        varargout = {minTE,minTR,0,t0};
        return
    end
    TR = max(TR,minTR);

    % Integrate the continuous trajectory at raster boundaries. Holding each
    % interval at its mean gradient preserves the area there.
    edges = 0:raster:ADC.duration;
    % Avoid subtracting nearly equal areas over a roundoff-sized final step.
    if ADC.duration-edges(end) <= 1e-6*raster
        edges(end) = ADC.duration;
    else
        edges(end+1) = ADC.duration;
    end
    radialArea = peak*(edges-rise/2);
    onRamp = edges < rise;
    radialArea(onRamp) = peak*edges(onRamp).^2/(2*rise);
    onTaper = edges >= t0;
    radialArea(onTaper) = peak*nthroot(a^2*(a+3*(edges(onTaper)-t0)),3);

    Gread.amp = peak;
    Gread.before = struct('steps',[],'values',[]);
    Gread.during.steps = diff(edges);
    Gread.during.values = diff(radialArea)./Gread.during.steps;
    Gread.after.steps = [repmat(raster,1,fallTicks),rewindSteps];
    Gread.after.values = [fall,rewindValues];
    sequence = buildRadialSpokeSequence(spokeDirs,startTime,RF,ADC,Gread, ...
        TE-minTE,TR-minTR,TR,kEdge,dummy);
    midpoints = ((1:ADC.numSamples)-0.5)/ADC.BW;
    sequence.Plot.kspacePreview.sampleRadii = gamma*interp1(edges,radialArea,midpoints);
    sequence.Plot.transitionMs = t0;
    varargout{1} = sequence;
end

function [rise,t0,peak] = designReadout(duration,raster,slew,peakLimit,area,requested)
    if ~isempty(requested)
        validateattributes(requested,{'numeric'},{'scalar','real','finite','nonnegative'});
        if requested >= duration
            error('DA_3DPR:TransitionLimit','t0 must be shorter than the %.6g ms readout.',duration);
        end
    end

    [rise,t0,peak] = findReadout(duration,raster,slew,peakLimit,area,requested);
    if ~isfinite(rise) && ~isempty(requested)
        % For a fixed ramp, increasing t0 only relaxes the constraints.
        [rise,t0,peak] = findReadout(duration,raster,slew,peakLimit,area,[]);
    end
    if ~isfinite(rise)
        error('DA_3DPR:InfeasibleReadout', ...
            ['No DA-3DPR readout meets the gradient, slew and radial spacing limits. ' ...
             'Try a longer readout or a coarser acquisition resolution.']);
    end
end

function [rise,t0,peak] = findReadout(duration,raster,slew,peakLimit,area,requested)
    t0 = duration;
    rise = NaN;
    peak = NaN;
    % Any longer ramp is unnecessary: for the same t0 it raises both the
    % required peak and taper slew, while the peak is already capped.
    maxTicks = min(floor(duration/raster),ceil(peakLimit/(slew*raster)));
    for ticks = 1:maxTicks
        ramp = ticks*raster;
        if ramp >= t0
            break
        end
        ceiling = min(peakLimit,slew*ramp);
        if ~isempty(requested)
            if ramp > requested
                break
            end
            candidate = requested;
        else
            low = ramp;
            high = t0;
            if ~isFeasible(high,ramp,ceiling)
                continue
            end
            if ~isFeasible(low,ramp,ceiling)
                % For fixed rise time, both peak and taper slew decrease as
                % t0 increases. Find the first feasible point on this ramp.
                for iteration = 1:48
                    middle = (low+high)/2;
                    if isFeasible(middle,ramp,ceiling)
                        high = middle;
                    else
                        low = middle;
                    end
                end
                low = high;
            end
            candidate = low;
        end
        [feasible,amplitude] = isFeasible(candidate,ramp,ceiling);
        if feasible && candidate < t0
            rise = ramp;
            t0 = candidate;
            peak = amplitude;
            if ~isempty(requested)
                return
            end
        end
    end
    function [ok,amplitude] = isFeasible(transition,ramp,ceiling)
        a = transition-ramp/2;
        amplitude = area/nthroot(a^2*(a+3*(duration-transition)),3);
        ok = amplitude <= ceiling && 2*amplitude/a <= slew;
    end
end
