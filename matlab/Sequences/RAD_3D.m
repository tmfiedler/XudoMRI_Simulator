%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%       RAD_3D sequence with 3D radial spoke readout
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function varargout = RAD_3D(TE,TR,MatSize,FOV,RF,ADC,GradOn,dummy,slice,nucleus,scannerLimits)

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
    [gamma,gammaHz] = getNucleusGamma(nucleus);

    ADC.numSamples = MatSize1;
    ADC.duration = MatSize1/ADC.BW; % ms

    % Backend implementation for the user-facing RAD_3D sequence.
    % It behaves as a nonselective UTE-style radial sequence.
    % FE/PE/SS are the logical x/y/z radial axes and must all be enabled.
    % The GUI shows one isotropic FOV and stores it in the legacy two-entry
    % vector. max(...) preserves compatibility with older protocol files.
    ramped = nargin >= 11 && ~isempty(scannerLimits);
    if ramped
        validateattributes(scannerLimits,{'numeric'},{'row','numel',3,'real','finite','positive'});
        validateattributes(ADC.BW,{'numeric'},{'scalar','real','finite','positive'});
        [kEdge,spokeDirs,maxComponent] = radialReadoutGeometry([MatSize1 MatSize2],[FOV1 FOV2],ADC);
        maxBW = radialGradientBounds(MatSize1,kEdge,maxComponent,gammaHz,scannerLimits(1));
        if ADC.BW > maxBW
            error('Sequence:GradientLimit','Maximum radial ADC bandwidth is %.6g kHz for these spokes.',maxBW);
        end
        spokeAmp = scannerLimits(1)/maxComponent*(ADC.BW/maxBW);
    elseif isfield(ADC,'radialResolutionMm') && ~isempty(ADC.radialResolutionMm)
        validateattributes(ADC.radialResolutionMm,{'numeric'},{'scalar','real','finite','positive'});
        kEdge = 500 / ADC.radialResolutionMm; % cycles/m
        spokeAmp = 1000 * kEdge / (gammaHz * (ADC.duration / 1000)); % mT/m
        validateattributes(spokeAmp,{'numeric'},{'scalar','real','finite','positive'});
    else
        radialFOV = max([FOV1, FOV2, 1]);
        kEdge = MatSize1 * 1000 / (2 * radialFOV);
        spokeAmp = readoutAmp(gamma,ADC.BW,radialFOV);
    end

    Gread.amp = spokeAmp;

    % Return each spoke to k = 0 before the next TR. The Bloch simulator
    % exports one trajectory sample per ADC point, so leaving residual
    % readout area here pushes the next spoke off-center in the .ktrj file.
    Gread.rewind.duration = ADC.duration/5;
    Gread.rewind.scale = -ADC.duration / Gread.rewind.duration;
    Gread.before.steps = [];
    Gread.before.values = [];
    Gread.after.steps = Gread.rewind.duration;
    Gread.after.values = Gread.amp*Gread.rewind.scale;
    if ramped
        maxGradient = scannerLimits(1)/maxComponent;
        slew = scannerLimits(2)/maxComponent;
        raster = scannerLimits(3)/1000;
        ticks = ceil(spokeAmp/(slew*raster));
        rise = ticks*raster;
        % The prephaser puts k=0 at ADC onset. The rewinder cancels the
        % entire sampled plateau and the area of the falling ramp.
        [~,preSteps,preValues] = gradientAreaLobe(-spokeAmp*rise/2,maxGradient,slew,raster);
        [~,postSteps,postValues] = gradientAreaLobe(-spokeAmp*(ADC.duration+rise/2),maxGradient,slew,raster);
        rampSteps = repmat(raster,1,ticks);
        up = spokeAmp*((1:ticks)-0.5)/ticks;
        Gread.before.steps = [preSteps,rampSteps];
        Gread.before.values = [preValues,up];
        Gread.after.steps = [rampSteps,postSteps];
        Gread.after.values = [fliplr(up),postValues];
    end

    % TE is measured from RF center to ADC onset.
    minTE = RF.Duration/2+sum(Gread.before.steps);
    if TE < minTE
        TE = minTE;
    end

    minTR = startTime + RF.Duration/2 + TE + ADC.duration + sum(Gread.after.steps);
    if TR < minTR
        TR = minTR;
    end

    readDelay = TE - minTE;
    tailDelay = TR - minTR;
    minTI = 0;

    %% Return SeqData
    if nargout == 1
        if ~ramped
            [~,spokeDirs] = radialReadoutGeometry([MatSize1 MatSize2],[FOV1 FOV2],ADC);
        end
        varargout{1} = buildRadialSpokeSequence(spokeDirs,startTime,RF,ADC,Gread, ...
            readDelay,tailDelay,TR,kEdge,dummy);
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
