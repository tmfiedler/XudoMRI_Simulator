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

    for scenario = 1:3
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
        writeSteps(fullfile(folder,'sequence.seqn'),steps);
        expected = base*sind(angle)*recovery;
        signals = cell(1,numel(backends));
        for b = 1:numel(backends)
            tag = sprintf('%s_case%d',backends{b},scenario);
            [s,actualK] = simulate(repo,folder,backends{b},tag,nucleus);
            assert(numel(s)==samples && all(isfinite(s)),'Invalid signal payload.');
            err = max(abs(s(:).'-expected))/scale;
            kerr = max(abs(actualK-[k;zeros(2,samples)]),[],'all');
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
end
fprintf('PASS: requested backends and both nuclei. GUI/radial/noise coverage is separate.\n');
end

function [signal,k] = simulate(repo,folder,backend,tag,nucleus)
base = fullfile(folder,[tag '_' backend]);
args = {['TissueTypeFile=' fullfile(folder,'tissue.prop')], ...
    ['GeometryFile=' fullfile(folder,'geometry.smpl')], ...
    ['SequenceFile=' fullfile(folder,'sequence.seqn')], ...
    ['B1PlusFile=' fullfile(folder,'transmit.bfld')], ...
    ['B1MinsFile=' fullfile(folder,'receive.bfld')],['Nucleus=' nucleus], ...
    'B0=3','NumIso=1','Thread=2',['KSpaceFile=' base '.ksig'],['KMapFile=' base '.ktrj']};
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
