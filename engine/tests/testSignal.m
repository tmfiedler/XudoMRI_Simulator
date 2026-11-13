function testSignal(backend)
%TESTSIGNAL Basic native signal checks, without a GUI or stored fixtures.
% From the repository root: addpath('engine/tests'); testSignal
% Default: CPU and GPU. testSignal('CPU') explicitly checks CPU only.
% Build first with engine/signal/build_windows.cmd. Requires Windows/MATLAB.
% Temporary files are removed on exit, including after a failed assertion.

if nargin < 1, backend = 'Both'; end
backend = validatestring(backend,{'Both','CPU','GPU'});
assert(ispc,'This test requires native Windows signal executables.');
repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
backends = {'CPU','GPU'};
if ~strcmp(backend,'Both'), backends = {backend}; end
for b = backends
    assert(isfile(fullfile(repo,'engine','bin',['NutateSignal_' b{1} '.exe'])), ...
        'Build the missing %s executable first.',b{1});
end
oldPath = path;
work = tempname; mkdir(work);
cleanup = onCleanup(@() finish(work,oldPath)); %#ok<NASGU>
addpath(fullfile(repo,'matlab')); initializeSimulatorPaths;
signalTolerance = 5e-4; trajectoryTolerance = 1e-4;
fprintf('testSignal: MATLAB %s; %s; signal %.1g/S0, k %.1g cycles/m\n', ...
    version,backend,signalTolerance,trajectoryTolerance);

for name = {'1H','23Na'}
    nucleus = name{1}; sodium = strcmp(nucleus,'23Na');
    gamma = 42576000; spin = 0.5; concentration = 111; t1 = 600;
    if sodium
        gamma = 11262000; spin = 1.5; concentration = 0.06; t1 = 25;
    end
    folder = fullfile(work,nucleus); mkdir(folder);
    % 24 one-micrometre voxels, x-fastest, with asymmetric density/Rx phase.
    x = -12:11; count = numel(x); width = 1e-6; b0 = 3;
    c = double(single(concentration*(0.5+(1:count)/count)));
    rx = double(single(1e-6*(1+(1:count)/48+1i*(-0.3+(1:count)/80))));
    writeFloats(fullfile(folder,'geometry.smpl'), ...
        [count -12 11 0 0 0 0 0 0 0 .001 .001 .001 ...
        reshape([x;zeros(2,count);1:count],1,[])]);
    writeTissue(fullfile(folder,'tissue.prop'),nucleus,c,t1,sodium);
    tau = .0001; idle = .5; dwell = .2; samples = 6; wait = 25;
    writeFloats(fullfile(folder,'transmit.bfld'), ...
        [count reshape([repmat(1/(4*gamma*tau*1e-3),1,count);zeros(1,count)],1,[])]);
    writeFloats(fullfile(folder,'receive.bfld'), ...
        [count reshape([real(rx);imag(rx)],1,[])]);

    % Independent Curie-law equilibrium and reciprocity receive reference.
    % No production nucleus, magnetization, sequence or signal helper is used.
    hbar = 1.0545718176461565e-34; kB = 1.380649e-23; NA = 6.02214076e23;
    omega = 2*pi*gamma;
    m0 = 1000*c*NA*(hbar*omega)^2*spin*(spin+1)*b0/(3*kB*310);
    amplitude = m0*(omega*b0)*width^3.*conj(rx);
    scale = sum(abs(amplitude));
    t = tau/2+idle+((0:samples-1)+.5)*dwell; % RF center to midpoint, ms
    k = gamma*.01*((0:samples-1)+.5)*dwell*1e-3; % cycles/m
    decay = exp(-t/100);
    if sodium, decay = .6*exp(-t/3)+.4*exp(-t/20); end
    % Omitted uniform-voxel sinc attenuation is bounded below 1e-6 here.
    assert(max((pi*k*width).^2/6)<1e-6);
    base = -1i*sum(amplitude(:).*exp(1i*2*pi*(x(:)*width)*k),1).*decay;

    for scenario = 1:4
        angle = 90; recovery = 1;
        if scenario == 1, angle = 30; end
        % Columns: ms, event, RF real/imag, carrier Hz, Gx/Gy/Gz mT/m.
        steps = [tau 0 angle/90 0 0 0 0 0; idle 0 0 0 0 0 0 0; ...
            repmat([dwell 1 0 0 0 10 0 0],samples,1)];
        if scenario == 3
            % Ideal saturation/spoil, longitudinal recovery, then readout90.
            steps = [tau 0 1 0 0 0 0 0; zeros(1,8); ...
                wait 0 0 0 0 0 0 0; steps];
            steps(2,2) = -2; % clear transverse state, preserve Mz
            recovery = 1-exp(-wait/t1);
        end
        expectedK = [k;zeros(2,samples)];
        extraArgs = {};
        if scenario == 4
            % Model z=0 is 25 mm above the overridden gradient isocenter.
            % The carrier cancels the RF-time gradient field at that plane.
            steps(1,5) = gamma*.01*.025;
            steps(1,8) = 10;
            extraArgs = {'zCtr=-25000'};
            expectedK(3,:) = gamma*.01*tau*1e-3;
        end
        writeSteps(fullfile(folder,'sequence.seqn'),steps);
        expected = base*sind(angle)*recovery;
        signals = cell(1,numel(backends));
        for b = 1:numel(backends)
            tag = sprintf('%s_case%d',backends{b},scenario);
            [s,actualK] = simulate(repo,folder,backends{b},tag,nucleus,extraArgs{:});
            assert(numel(s)==samples && all(isfinite(s)),'Invalid signal payload.');
            err = max(abs(s(:).'-expected))/scale;
            kerr = max(abs(actualK-expectedK),[],'all');
            assert(err<=signalTolerance,'%s %s case%d signal error %.6g/S0.', ...
                nucleus,backends{b},scenario,err);
            assert(kerr<=trajectoryTolerance,'Trajectory error %.6g cycles/m.',kerr);
            signals{b} = s;
            fprintf('PASS %-4s %-3s case%d signal %.3g/S0, k %.3g cycles/m\n', ...
                nucleus,backends{b},scenario,err,kerr);
        end
        if numel(signals)==2
            assert(max(abs(signals{1}-signals{2}))/scale<=signalTolerance, ...
                'CPU/CUDA disagreement.');
        end
    end

    % Workflow smoke: real GRE generator -> V1 export -> engine -> reconstruction.
    % Eight-by-eight data, no slice selection; not a physical image reference.
    rf = struct('Shape',2,'Duration',.1,'Num',20,'FA',90);
    inter = GRE(5,12000,[8 8],[64 64],rf,struct('BW',16), ...
        struct('ss',0,'pe',1,'fe',1),0,struct('TH',.018,'offset',0),nucleus);
    seq = combineSeqRect(inter,1,{'P--A'},0);
    writeGenerated(fullfile(folder,'sequence.seqn'),seq);
    % Unit RF in the generator: reset the map to a .1 ms90 excitation.
    writeFloats(fullfile(folder,'transmit.bfld'), ...
        [count reshape([repmat(1/(4*gamma*.1e-3),1,count);zeros(1,count)],1,[])]);
    protocol = struct('MatSize',[8 8],'SequenceType','GRE', ...
        'SliceOrientation','Axial','PEDirection','P--A','FOVOffset',[0 0 0], ...
        'SampleMin',[-12 0 0],'SampleMax',[11 0 0]);
    smokeSignals = cell(1,numel(backends));
    for b = 1:numel(backends)
        [s,actualK] = simulate(repo,folder,backends{b},'GRE',nucleus);
        assert(numel(s)==64 && all(isfinite(actualK),'all') && ...
            any(abs(actualK(:))>0),'Invalid generated acquisition.');
        [image,matrix] = reconstructCartesianDataset(s(:),protocol);
        assert(isequal(matrix,[8 8]) && numel(image.volumeRSS)==64 && ...
            all(isfinite(image.volumeRSS),'all') && max(image.volumeRSS(:))>0, ...
            'Generated GRE reconstruction smoke check failed.');
        smokeSignals{b} = s;
        fprintf('PASS %-4s %-3s generated GRE / simulation / reconstruction\n', ...
            nucleus,backends{b});
    end
    if numel(smokeSignals)==2
        assert(max(abs(smokeSignals{1}-smokeSignals{2}))/ ...
            max(abs(smokeSignals{1}))<=signalTolerance,'GRE CPU/CUDA disagreement.');
    end

    % Scanner-limited GRE. Independent Cartesian sample coordinates in cycles/m.
    limits = [22 120 10]; % mT/m, T/m/s, us
    adc = struct('BW',12);
    encoding = struct('ss',0,'pe',1,'fe',1);
    slice = [];
    [te,tr] = GRE(0,0,[8 8],[64 64],rf,adc,encoding,0,slice,nucleus,limits);
    inter = GRE(te,tr,[8 8],[64 64],rf,adc,encoding,0,slice,nucleus,limits);
    seq = combineSeqRect(inter,1,{'P--A'},0);
    writeGenerated(fullfile(folder,'sequence.seqn'),seq);
    [fe,pe] = ndgrid((-3.5:3.5)/.064);
    expectedK = [fe(:).';pe(:).';zeros(1,numel(fe))];
    [previewPath,previewSamples] = cartesianTrajectoryPreview(seq.Main,{'Gx','Gy'},gamma);
    assert(max(abs(previewSamples.'-expectedK(1:2,:)),[],'all') < 1e-6, ...
        'Ramped GRE preview sample positions differ from the Cartesian reference.');
    assert(any(isnan(previewPath(:,1))) && min(previewPath(:,1),[],'omitnan') < min(fe(:)), ...
        'Ramped GRE preview must show the prephaser and break at trajectory resets.');
    for b = 1:numel(backends)
        [s,actualK] = simulate(repo,folder,backends{b},'RampedGRE',nucleus);
        % Allow accumulated float32 rounding across the stepped ramps.
        kError = max(abs(double(actualK)-expectedK),[],'all');
        assert(kError < 5e-4,'Ramped GRE trajectory error %.6g cycles/m.',kError);
        [image,matrix] = reconstructCartesianDataset(s(:),protocol);
        assert(isequal(matrix,[8 8]) && all(isfinite(image.volumeRSS),'all') && ...
            max(image.volumeRSS(:)) > 0,'Ramped GRE reconstruction failed.');
        fprintf('PASS %-4s %-3s ramped GRE k %.3g cycles/m (limit 0.0005) / reconstruction\n', ...
            nucleus,backends{b},kError);
    end

    % Slice gradient area after RF center must cancel the rephasing lobe.
    rfSelective = rf;
    rfSelective.Duration = 5;
    encoding.ss = 1;
    slice = struct('TH',.018,'offset',0);
    [te,tr] = GRE(0,0,[8 8],[64 64],rfSelective,adc,encoding,1,slice,nucleus,limits);
    inter = GRE(te,tr,[8 8],[64 64],rfSelective,adc,encoding,1,slice,nucleus,limits);
    ss = inter.Main.Gss;
    edges = [0,cumsum(ss.tStep)];
    rfCenter = inter.Main.RF.tStep(1)+rfSelective.Duration/2;
    postRF = max(0,edges(2:end)-max(edges(1:end-1),rfCenter));
    assert(abs(sum(ss.value.*postRF)) < 1e-10,'Ramped GRE slice did not refocus.');
    for gradient = {inter.Main.Gfe,inter.Main.Gpe,ss}
        g = gradient{1};
        centers = cumsum(g.tStep)-g.tStep/2;
        assert(max(abs(g.value)) <= limits(1)+1e-10,'GRE exceeded gradient amplitude.');
        assert(max(abs(diff(g.value)./diff(centers))) <= limits(2)+1e-8,'GRE exceeded ramp slew.');
    end
    combineSeqRect(inter,1,{'P--A'},1);

    % Ramped SE at its minimum timing. Each side of the refocusing center
    % must balance the slice moment independently.
    [te,tr] = SE(0,0,[8 8],[64 64],rfSelective,adc,encoding,1,slice,nucleus,limits);
    inter = SE(0,0,[8 8],[64 64],rfSelective,adc,encoding,1,slice,nucleus,limits);
    rfStarts = [inter.Main.RF.tStep(1),sum(inter.Main.RF.tStep(1:rf.Num+2))];
    rfCenters = rfStarts+rfSelective.Duration/2;
    adcCenter = sum(inter.Main.ADC.tStep(1:2))+4/adc.BW;
    assert(abs(diff(rfCenters)-te/2)<1e-10 && ...
        abs(adcCenter-rfCenters(2)-te/2)<1e-10 && abs(inter.TR-tr)<1e-10, ...
        'Ramped SE echo or repetition timing is incorrect.');
    ss = inter.Main.Gss;
    edges = [0,cumsum(ss.tStep)];
    limitsAtEcho = [rfCenters,adcCenter];
    for interval = 1:2
        overlap = max(0,min(edges(2:end),limitsAtEcho(interval+1))- ...
            max(edges(1:end-1),limitsAtEcho(interval)));
        assert(abs(sum(ss.value.*overlap))<1e-10,'Ramped SE slice moment is unbalanced.');
    end
    for gradient = {inter.Main.Gfe,inter.Main.Gpe,ss}
        g = gradient{1};
        centers = cumsum(g.tStep)-g.tStep/2;
        assert(max(abs(g.value))<=limits(1)+1e-10 && ...
            max(abs(diff(g.value)./diff(centers)))<=limits(2)+1e-8, ...
            'Ramped SE exceeded amplitude or slew limits.');
    end
    assert(abs(sum(inter.Main.Gfe.value.*inter.Main.Gfe.tStep))<1e-10 && ...
        abs(sum(inter.Main.Gpe.value.*inter.Main.Gpe.tStep))<1e-10 && ...
        abs(sum(inter.Main.Gpe.increment.*inter.Main.Gpe.tStep))<1e-10, ...
        'Ramped SE FE or PE rewinder did not balance its axis.');
    combineSeqRect(inter,1,{'P--A'},1);

    encoding.ss = 0;
    inter = SE(0,0,[8 8],[64 64],rf,adc,encoding,0,[],nucleus,limits);
    seq = combineSeqRect(inter,1,{'P--A'},0);
    writeGenerated(fullfile(folder,'sequence.seqn'),seq);
    seProtocol = protocol;
    seProtocol.SequenceType = 'SE';
    for b = 1:numel(backends)
        [s,actualK] = simulate(repo,folder,backends{b},'RampedSE',nucleus);
        kError = max(abs(double(actualK)-expectedK),[],'all');
        assert(kError<5e-4,'Ramped SE trajectory error %.6g cycles/m.',kError);
        [image,matrix] = reconstructCartesianDataset(s(:),seProtocol);
        assert(isequal(matrix,[8 8]) && all(isfinite(image.volumeRSS),'all') && ...
            max(image.volumeRSS(:))>0,'Ramped SE reconstruction failed.');
        fprintf('PASS %-4s %-3s ramped SE k %.3g cycles/m (limit 0.0005) / reconstruction\n', ...
            nucleus,backends{b},kError);
    end

    % EPI has one acquisition per line in alternating directions. Exercise
    % even and odd trains and the single-line case at minimum TE/TR.
    epiProtocol = protocol;
    epiProtocol.SequenceType = 'GRE_EPI';
    for lines = [1 7 8]
        matrixSize = [8 lines];
        epiProtocol.MatSize = matrixSize;
        [te,tr] = GRE_EPI(0,0,matrixSize,[64 64],rf,adc,encoding,0,[],nucleus,limits);
        inter = GRE_EPI(te,tr,matrixSize,[64 64],rf,adc,encoding,0,[],nucleus,limits);
        step = inter.Main.ADC.tStep;
        sample = inter.Main.ADC.value==1;
        centers = cumsum(step)-step/2;
        adcCenters = reshape(centers(sample),8,lines);
        rfCenter = inter.Main.RF.tStep(1)+rf.Duration/2;
        assert(abs(mean(adcCenters(:))-rfCenter-te)<1e-10,'EPI train center changed.');
        readAmplitude = 12e9/(gamma*64);
        raster = limits(3)/1000;
        rise = ceil(readAmplitude/(limits(2)*raster))*raster;
        % One PE step is triangular for these inputs. Its raster-rounded
        % duration can exceed the readout reversal, depending on nucleus.
        blipDuration = 2*raster*ceil(sqrt(1e9/(gamma*64*limits(2)))/raster);
        assert(all(abs(diff(adcCenters(1,:))-8/12-max(2*rise,blipDuration))<1e-10), ...
            'EPI echo spacing does not account for the FE reversal and PE blip.');
        assert(abs(tr-centers(find(sample,1,'last'))-1/24-rise)<1e-10, ...
            'EPI TR must include the final ramp.');
        seq = combineSeqRect(inter,1,{'P--A'},0);
        writeGenerated(fullfile(folder,'sequence.seqn'),seq);
        fe = ((-3.5:3.5)'/.064).*(-1).^(0:lines-1);
        pe = repmat(((0:lines-1)-(lines-1)/2)/.064,8,1);
        expectedEPI = [fe(:).';pe(:).';zeros(1,8*lines)];
        for b = 1:numel(backends)
            [s,actualK] = simulate(repo,folder,backends{b},'RampedEPI',nucleus);
            kError = max(abs(double(actualK)-expectedEPI),[],'all');
            assert(kError<5e-4,'Ramped EPI trajectory error %.6g cycles/m.',kError);
            [image,matrix] = reconstructCartesianDataset(s(:),epiProtocol);
            assert(isequal(matrix,matrixSize) && all(isfinite(image.volumeRSS),'all') && ...
                max(image.volumeRSS(:))>0,'Ramped EPI reconstruction failed.');
            fprintf('PASS %-4s %-3s ramped EPI %d lines k %.3g cycles/m (limit 0.0005)\n', ...
                nucleus,backends{b},lines,kError);
        end
    end

    % Uniform radial readout at 5 mm nominal resolution over 400 mm FOV.
    % Increase the sample count at fixed bandwidth and at fixed duration.
    radialCases = [80 16; 256 16; 256 51.2]; % Samples per spoke, bandwidth in kHz.
    for acquisition = radialCases.'
        radialSamples = acquisition(1);
        bandwidth = acquisition(2);
        adc = struct('BW',bandwidth,'radialResolutionMm',5);
        inter = RAD_3D(1,150,[radialSamples 8],[400 400],rf,adc, ...
            struct('ss',1,'pe',1,'fe',1),0,struct('TH',.4,'offset',0),nucleus);
        seq = combineSeqRect(inter,1,{'P--A'},0,true);
        writeGenerated(fullfile(folder,'sequence.seqn'),seq);
        expectedRadius = 100*((1:radialSamples)'-.5)/radialSamples;
        % Each axis accumulates two float32 increments per dwell. Bound the
        % relative rounding by n*u/(1-n*u), with eight extra operations for
        % input quantization, unit conversion and increment calculation.
        roundingBudget = (2*radialSamples+8)*double(eps('single'))/2;
        radialTolerance = 100*roundingBudget/(1-roundingBudget);
        for b = 1:numel(backends)
            tag = sprintf('RAD_%d_%g',radialSamples,bandwidth);
            [s,actualK] = simulate(repo,folder,backends{b},tag,nucleus);
            radii = reshape(vecnorm(actualK),radialSamples,[]);
            assert(numel(s)==radialSamples*8 && all(isfinite(s)),'Invalid radial signal payload.');
            kerr = max(abs(radii-expectedRadius),[],'all');
            assert(kerr <= radialTolerance, ...
                '%s %s %d samples at %g kHz radial midpoint error %.6g cycles/m (bound %.6g).', ...
                nucleus,backends{b},radialSamples,bandwidth,kerr,radialTolerance);
            fprintf('PASS %-4s %-3s RAD_3D %3d samples/spoke at %g kHz, midpoint error %.3g cycles/m (bound %.3g)\n', ...
                nucleus,backends{b},radialSamples,bandwidth,kerr,radialTolerance);
        end
    end

    % Two oblique spokes. A 24 mT/m vector fits the 22 mT/m axis limit
    % because the largest direction component is sqrt(3)/2.
    directions = [sqrt(3)/2,0,-.5; ...
        sqrt(3)/2*cos(pi*(3-sqrt(5))),sqrt(3)/2*sin(pi*(3-sqrt(5))),.5];
    adc = struct('BW',gamma*24*16/1e8,'radialResolutionMm',5);
    axesOn = struct('ss',1,'pe',1,'fe',1);
    [te,tr] = RAD_3D(0,0,[16 2],[400 400],rf,adc,axesOn,0,[],nucleus,limits);
    inter = RAD_3D(0,0,[16 2],[400 400],rf,adc,axesOn,0,[],nucleus,limits);
    main = inter.Main;
    rows = find(main.ADC.value==-1);
    step = main.ADC.tStep;
    gradient = [main.Gfe.value;main.Gpe.value;main.Gss.value];
    assert(abs(inter.TR-2*tr)<1e-10,'Ramped radial TR mismatch.');
    for spoke = 1:2
        ends = [rows(2)-1,numel(step)];
        idx = rows(spoke):ends(spoke);
        adcFirst = find(main.ADC.value(idx)==1,1);
        assert(abs(sum(step(idx(1:adcFirst-1)))-step(idx(1))-rf.Duration/2-te)<1e-10, ...
            'Ramped radial TE must end at ADC onset.');
        assert(max(abs(sum(gradient(:,idx).*step(idx),2)))<1e-10,'Radial rewind left residual area.');
        centers = cumsum(step(idx))-step(idx)/2;
        assert(max(abs(gradient(:,idx)),[],'all')<=limits(1)+1e-10 && ...
            max(abs(diff(gradient(:,idx),1,2)./diff(centers)),[],'all')<=limits(2)+1e-8, ...
            'Ramped radial waveform exceeded per-axis limits.');
    end
    seq = combineSeqRect(inter,1,{'P--A'},0,true);
    writeGenerated(fullfile(folder,'sequence.seqn'),seq);
    radii = ((1:16)-.5)*100/16;
    expectedRadial = [directions(1,:).'*radii,directions(2,:).'*radii];
    for b = 1:numel(backends)
        [s,actualK] = simulate(repo,folder,backends{b},'RampedRAD',nucleus);
        kError = max(abs(double(actualK)-expectedRadial),[],'all');
        assert(kError<5e-4,'Ramped RAD_3D trajectory error %.6g cycles/m.',kError);
        context = buildRadialReconstructionContext(reshape(actualK.',16,2,3),8,[.04 .04 .04]);
        image = reconstructRadialDataset(reshape(s,16,2),context);
        assert(all(isfinite(image.volumeRSS),'all') && max(image.volumeRSS(:))>0, ...
            'Ramped radial reconstruction failed.');
        fprintf('PASS %-4s %-3s ramped RAD_3D k %.3g cycles/m (limit 0.0005)\n', ...
            nucleus,backends{b},kError);
    end
end
checkRadialReconstruction();
fprintf('PASS: requested backends and both nuclei. GUI and noise coverage is separate.\n');
end

function checkRadialReconstruction()
% Synthetic point source, 5 mm acquisition at 80 mm FOV. Compare the complex
% gridding result with direct evaluation at matched physical coordinates.
fov = .08;
point = [.01 -.015 .005];
radii = ((1:48)'-.5) * (100/48);
directions = [eye(3);-eye(3);[1 2 3]/sqrt(14);[-2 3 1]/sqrt(14)];
k = radii .* reshape(directions,1,[],3);
flatK = reshape(k,[],3);
samples = exp(2i*pi*(flatK*point.'));
% Gridding with the tabulated width-4 kernel is approximate. Allow 0.005
% of the unit point peak over a grid of probe positions inside the FOV.
tolerance = .005;
for matrixSize = [8 15 16 32]
    context = buildRadialReconstructionContext(k,matrixSize,[fov fov fov]);
    inside = vecnorm(flatK,2,2) <= matrixSize/(2*fov);
    assert(isequal(context.retained,inside),'Unexpected radial band selection.');
    raw = samples;
    raw(~inside) = 1000; % Out-of-band values must have no effect.
    result = reconstructRadialDataset(reshape(raw,size(k,1),size(k,2)),context);
    assert(isequal(size(result.volumeComplex),repmat(matrixSize,1,3)),'Incorrect reconstruction matrix.');
    offsets = round((-4:3)*floor(matrixSize/2)/4);
    [x,y,z] = ndgrid(offsets);
    positions = [x(:),y(:),z(:)] * (fov/matrixSize);
    weights = sum(flatK(inside,:).^2,2);
    direct = exp(-2i*pi*(positions*flatK(inside,:).')) * ...
        (samples(inside).*weights) / sum(weights);
    index = floor(matrixSize/2)+1+offsets;
    observed = result.volumeComplex(index,index,index);
    err = max(abs(double(observed(:))-direct));
    assert(err<=tolerance,'Radial %d^3 gridding error %.6g exceeds %.6g.',matrixSize,err,tolerance);
    fprintf('PASS RAD_3D %2d^3 vs direct Fourier sum, peak-normalized error %.3g (limit %.3g)\n', ...
        matrixSize,err,tolerance);
end
end

function [signal,k] = simulate(repo,folder,backend,tag,nucleus,varargin)
base = fullfile(folder,[tag '_' backend]);
args = {['TissueTypeFile=' fullfile(folder,'tissue.prop')], ...
    ['GeometryFile=' fullfile(folder,'geometry.smpl')], ...
    ['SequenceFile=' fullfile(folder,'sequence.seqn')], ...
    ['B1PlusFile=' fullfile(folder,'transmit.bfld')], ...
    ['B1MinsFile=' fullfile(folder,'receive.bfld')],['Nucleus=' nucleus], ...
    'B0=3','NumIso=1','Thread=2',['KSpaceFile=' base '.ksig'],['KMapFile=' base '.ktrj'],varargin{:}};
p = System.Diagnostics.Process;
p.StartInfo.FileName = fullfile(repo,'engine','bin',['NutateSignal_' backend '.exe']);
p.StartInfo.Arguments = strjoin(cellfun(@(s) ['"' s '"'],args,'UniformOutput',false),' ');
p.StartInfo.WorkingDirectory = repo;
p.StartInfo.UseShellExecute = false; p.StartInfo.CreateNoWindow = true;
p.StartInfo.RedirectStandardInput = true;
p.StartInfo.RedirectStandardOutput = true; p.StartInfo.RedirectStandardError = true;
processCleanup = onCleanup(@() p.Dispose()); %#ok<NASGU>
assert(p.Start(),'Could not launch signal engine.');
out = p.StandardOutput.ReadToEndAsync(); err = p.StandardError.ReadToEndAsync();
p.StandardInput.WriteLine(); p.StandardInput.Close();
if ~p.WaitForExit(60000), p.Kill(); p.WaitForExit(); error('Signal test timed out.'); end
log = [char(out.Result) char(err.Result)];
assert(p.ExitCode==0,'Signal engine failed:\n%s',log);
identity = 'Simulation backend: CPU (OpenMP host implementation).';
if strcmp(backend,'GPU'), identity = 'Simulation backend: NVIDIA CUDA.'; end
assert(contains(log,identity),'Engine did not identify the requested backend:\n%s',log);
raw = readFloats([base '1.ksig']);
assert(mod(numel(raw),2)==0,'Incomplete complex signal.');
signal = complex(raw(1:2:end),raw(2:2:end));
raw = readFloats([base '.ktrj']);
assert(numel(raw)==3*numel(signal),'Signal/trajectory size mismatch.');
k = reshape(raw,3,[]);
end

function writeSteps(file,steps)
duration = double(single(steps(:,1)));
steps(:,9) = duration/2.*(steps(:,2)==1);
steps(:,10) = duration.*(steps(:,2)==1);
raw = [-1;1;size(steps,1);1;1];
for columns = {1,2,9,10,3:5,6,7,8}
    raw = [raw;size(steps,1);1;reshape(steps(:,columns{1}).',[],1)]; %#ok<AGROW>
end
writeFloats(file,raw);
end

function writeGenerated(file,seq)
assert(~isfield(seq,'Dummy'),'Smoke fixture must have no dummy repetitions.');
raw = [-1;1;seq.totalNum;1;1];
blocks = {'Time','ADC','SampleOffset','Dwell','RF','Gx','Gy','Gz'};
for n = 1:numel(blocks)
    block = seq.Main.(blocks{n}); values = block.value;
    if strcmp(blocks{n},'RF')
        values = [real(values);imag(values);seq.Main.DFreq.value];
    end
    raw = [raw;numel(block.value);block.repeat;values(:)]; %#ok<AGROW>
end
writeFloats(file,raw);
end

function writeTissue(file,nucleus,c,t1,sodium)
fid = fopen(file,'w'); assert(fid>=0,'Cannot write tissue fixture.');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'TISSUE_PROPERTIES_V1 Nucleus=%s\n',nucleus);
t2 = 'T2_ms'; if sodium, t2 = 'T2s_ms T2l_ms'; end
fprintf(fid,['ID T1_ms %s Concentration_mol_per_L chemical_shift_ppm ' ...
    'conductivity_S_per_m mass_density_kg_per_m3 tissue_name\n'],t2);
for n = 1:numel(c)
    if sodium, times = '3 20'; else, times = '100'; end
    fprintf(fid,'%d %g %s %.17g 0 0 1000 voxel%d\n',n,t1,times,c(n),n);
end
end

function writeFloats(file,values)
fid = fopen(file,'w','ieee-le'); assert(fid>=0,'Cannot write %s.',file);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
assert(fwrite(fid,values,'single')==numel(values),'Incomplete fixture write.');
end

function values = readFloats(file)
info = dir(file); assert(isscalar(info) && mod(info.bytes,4)==0,'Invalid %s.',file);
fid = fopen(file,'r','ieee-le'); assert(fid>=0,'Cannot read %s.',file);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
values = fread(fid,Inf,'single=>double');
end

function finish(work,oldPath)
path(oldPath);
if isfolder(work), rmdir(work,'s'); end
end
