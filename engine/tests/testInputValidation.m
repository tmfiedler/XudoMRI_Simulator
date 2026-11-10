function testInputValidation(backend)
%TESTINPUTVALIDATION Regression checks for protocol/native input and output guards.
% Build both native engines, then run from the repository root:
% addpath('engine/tests'); testInputValidation
% testInputValidation('CPU') explicitly omits CUDA checks.
if nargin < 1, backend='Both'; end
backend=validatestring(backend,{'Both','CPU','GPU'});
repo=fileparts(fileparts(fileparts(mfilename('fullpath'))));
backends={'CPU','GPU'}; if ~strcmp(backend,'Both'),backends={backend};end
oldPath=path; work=tempname; mkdir(work);
cleanup=onCleanup(@()finish(work,oldPath)); %#ok<NASGU>
addpath(fullfile(repo,'matlab')); initializeSimulatorPaths;
fprintf('testInputValidation: MATLAB %s; %s\n',version,backend);

% Treat protocol values as data. Even the harmless print expression must fail.
file=fullfile(work,'weights.prot');
for row={'1 0',' .5 -9e1 ','+1.0e0 +180.'}
    writeWeight(file,row{1}); p=readSetupProtocol(file);
    actual=p.txWeight(1);
    if strcmp(row{1},'1 0'),expected=[1 0];
    elseif contains(row{1},'.5'),expected=[.5 -90];else,expected=[1 180];end
    assert(isequal(actual,expected),'Valid transmit weights changed.');
end
for row={'1 fprintf(''UNSAFE_PROTOCOL_EXPRESSION'')','[1 0]','1+1 0', ...
        '-1 0','Inf 0','1 NaN','1 2i','1 0 extra','1,000 0','1;0','1 1e309',''}
    writeWeight(file,row{1}); p=readSetupProtocol(file);
    captured=evalc('expectError(@()p.txWeight(1),''SetupProtocol:TxWeight'');');
    assert(~contains(captured,'UNSAFE_PROTOCOL_EXPRESSION'),'Protocol expression executed.');
end
p=readSetupProtocol(fullfile(repo,'protocols','example','example.prot'));
assert(isequal(p.txWeight(1),[10 0]),'Bundled protocol weights changed.');
fprintf('PASS protocol numeric parsing and expression rejection\n');

% Three original records; the crop below selects record 2, not record 1.
geometry=[3 -1 1 0 0 0 0 0 0 0 .001 .001 .001 -1 0 0 1 0 0 0 1 1 0 0 1];
gamma=42576000; tauMs=.01;
tx=[3 repmat([1/(4*gamma*tauMs*1e-3) 0],1,3)];
rx=[3 repmat([1e-6 0],1,3)]; efield=[3 repmat([1 0 0 0 0 0],1,3)];
writeFloats(fullfile(work,'geometry.smpl'),geometry);
writeFloats(fullfile(work,'tx.bfld'),tx);writeFloats(fullfile(work,'rx.bfld'),rx);
writeFloats(fullfile(work,'receive.efld'),efield);
writeTissue(work,'1H',.4);
% Independent two-interval V1 fixture: short RF, one ADC midpoint in 10 mT/m Gx.
raw=[-1 1 2 1 1];
for values={[tauMs .2],[0 1],[0 .1],[0 .2],[1 0 0 0 0 0],[10 10],[0 0],[0 0]}
    raw=[raw 2 1 values{1}]; %#ok<AGROW>
end
writeFloats(fullfile(work,'sequence.seqn'),raw);
common={['GeometryFile=' fullfile(work,'geometry.smpl')], ...
    ['TissueTypeFile=' fullfile(work,'tissue.prop')],['SequenceFile=' fullfile(work,'sequence.seqn')], ...
    'Nucleus=1H','xMin=0','xMax=0'};
signalMaps={['B1PlusFile=' fullfile(work,'tx.bfld')],['B1MinsFile=' fullfile(work,'rx.bfld')]};
noise=fullfile(repo,'engine','bin','NutateNoise.exe');
noiseArgs=[common {['E1MinsFile=' fullfile(work,'receive.efld')],'NoiseSeed=7','NEX=1'}];

for b=backends
    exe=fullfile(repo,'engine','bin',['NutateSignal_' b{1} '.exe']);
    runSuccess(exe,[common signalMaps],work,['valid_' b{1}],false);
    % Valid syntax/limits, including retained zero and negative field conventions.
    for pair={'B0=0','B0=-3','B0=3e0','Thread=1e0','NumIso=2','xMin=-0x1','xMax=01','xCtr=.5'}
        runSuccess(exe,[common signalMaps pair],work,['valid_option_' b{1}],false);
    end
    runSuccess(exe,common,work,['ideal_' b{1}],false);
    for pair={'B0=garbage','B0=3garbage','B0=NaN','B0=Inf','B0=1e99','B0=1e-46', ...
            'Thread=0','Thread=1.5','Thread=65536','NumIso=0','NumIso=-1','NumIso=65535.0001', ...
            'xMin=1.5','xMax=08','xMin=16777217','xCtr=2x','yCtr=NaN','zCtr=Inf', ...
            'xWid=0','yWid=-1','zWid=1e-43','xWid=2mm'}
        key=extractBefore(pair{1},'=');
        runFailure(exe,[common signalMaps pair],work,['bad_option_' b{1}],char(key),false);
    end
    for map={'tx.bfld','rx.bfld'}
        baseline=tx;kind='B1+';if strcmp(map{1},'rx.bfld'),baseline=rx;kind='B1-';end
        for component=4:5 % real/imaginary components in original voxel record 2
            for bad=[NaN Inf -Inf]
                values=baseline;values(component)=bad;
                writeFloats(fullfile(work,map{1}),values);
                log=runFailure(exe,[common signalMaps],work,['bad_map_' b{1}],['Nonfinite ' kind],false);
                assert(contains(log,map{1}) && contains(log,'voxel record 2'),'Missing field-record diagnostic.');
            end
        end
        writeFloats(fullfile(work,map{1}),baseline);
    end
    % Finite, extreme RF can overflow float evolution: the export guard must fail.
    huge=tx;huge(4)=realmax('single');writeFloats(fullfile(work,'tx.bfld'),huge);
    runFailure(exe,[common signalMaps],work,['overflow_' b{1}],'Nonfinite signal',false);
    writeFloats(fullfile(work,'tx.bfld'),tx);
    fprintf('PASS %s numeric CLI, selected B1 records, ideal fields and overflow rejection\n',b{1});
end

runSuccess(noise,noiseArgs,work,'valid_noise',true);
for pair={'xMin=2x','xMax=1.5','xWid=Inf','yWid=0','zWid=-1','zWid=1e-43','NEX=0','NEX=2x', ...
        'NoiseSeed=-1','NoiseSeed= -1','NoiseSeed=+7','NoiseSeed= 7'}
    key=extractBefore(pair{1},'=');runFailure(noise,[noiseArgs pair],work,'bad_noise_option',char(key),true);
end
for component=8:13 % all six E components in original voxel record 2
    for bad=[NaN Inf -Inf]
        values=efield;values(component)=bad;writeFloats(fullfile(work,'receive.efld'),values);
        log=runFailure(noise,noiseArgs,work,'bad_e','Nonfinite E1-',true);
        assert(contains(log,'receive.efld') && contains(log,'voxel record 2'));
    end
end
writeFloats(fullfile(work,'receive.efld'),efield);
% Finite inputs can also overflow noise's float32 output; keep the covariance math.
huge=efield;huge(8)=realmax('single');writeFloats(fullfile(work,'receive.efld'),huge);
writeTissue(work,'1H',3e38);
runFailure(noise,noiseArgs,work,'overflow_noise','Nonfinite noise',true);
writeTissue(work,'1H',.4);writeFloats(fullfile(work,'receive.efld'),efield);
fprintf('PASS noise numeric CLI, selected E records and overflow rejection\n');

% Invalid geometry must fail before casts, including nonfinite cropped-out rows.
badGeometries={};
for slot=[1 8 11 14 18 21]
    values=geometry;values(slot)=NaN;badGeometries{end+1}=values; %#ok<AGROW>
end
for value=[.5 2^31]
    values=geometry;values(21)=value;badGeometries{end+1}=values; %#ok<AGROW>
end
values=geometry;values(11)=0;badGeometries{end+1}=values;
for values=badGeometries
    writeFloats(fullfile(work,'geometry.smpl'),values{1});
    for b=backends
        exe=fullfile(repo,'engine','bin',['NutateSignal_' b{1} '.exe']);
        runFailure(exe,[common signalMaps],work,['bad_geometry_' b{1}],'',false);
    end
    runFailure(noise,noiseArgs,work,'bad_noise_geometry','',true);
end
writeFloats(fullfile(work,'geometry.smpl'),geometry);
% Float32 count metadata may be rounded or stale; actual payload remains authoritative.
for count=[0 16777216 2^32]
    values=geometry;values(1)=count;writeFloats(fullfile(work,'geometry.smpl'),values);
    for b=backends
        exe=fullfile(repo,'engine','bin',['NutateSignal_' b{1} '.exe']);
        log=runSuccess(exe,[common signalMaps],work,['rounded_count_' b{1}],false);
        assert(contains(log,'Using the payload-derived count.'));
    end
    log=runSuccess(noise,noiseArgs,work,'rounded_noise_count',true);
    assert(contains(log,'Using the payload-derived count.'));
end
writeFloats(fullfile(work,'geometry.smpl'),geometry);
fprintf('PASS geometry metadata/records rejected before conversion\n');
fprintf('PASS input validation; unchanged analytic physics is checked separately by testSignal.\n');
end

function writeWeight(file,row)
fid=fopen(file,'w');c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'Tx Mag & Phs:\n%s\nEnd:\n\n',row);
end
function expectError(fn,id)
try,fn();catch ex,assert(strcmp(ex.identifier,id),'Unexpected error: %s',ex.message);return;end
error('testInputValidation:Accepted','Invalid protocol value was accepted.');
end
function writeTissue(work,nucleus,sigma)
fid=fopen(fullfile(work,'tissue.prop'),'w');c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'TISSUE_PROPERTIES_V1 Nucleus=%s\n',nucleus);
fprintf(fid,'ID T1_ms T2_ms Concentration_mol_per_L chemical_shift_ppm conductivity_S_per_m mass_density_kg_per_m3 tissue_name\n');
fprintf(fid,'1 600 100 111 0 %.17g 1000 reference\n',sigma);
end
function writeFloats(file,values)
fid=fopen(file,'w','ieee-le');assert(fid>=0);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
assert(fwrite(fid,values,'single')==numel(values));
end
function [code,log]=runNative(exe,args)
assert(isfile(exe),'Build the missing engine: %s',exe);
p=System.Diagnostics.Process;c=onCleanup(@()p.Dispose()); %#ok<NASGU>
p.StartInfo.FileName=exe;
p.StartInfo.Arguments=strjoin(cellfun(@(s)['"' s '"'],args,'UniformOutput',false),' ');
p.StartInfo.UseShellExecute=false;p.StartInfo.CreateNoWindow=true;
p.StartInfo.RedirectStandardInput=true;p.StartInfo.RedirectStandardOutput=true;p.StartInfo.RedirectStandardError=true;
assert(p.Start());out=p.StandardOutput.ReadToEndAsync();err=p.StandardError.ReadToEndAsync();
p.StandardInput.WriteLine();p.StandardInput.Close();
if ~p.WaitForExit(60000),p.Kill();p.WaitForExit();error('testInputValidation:Timeout','Engine timed out.');end
code=double(p.ExitCode);log=[char(out.Result) char(err.Result)];
end
function [args,output]=withOutputs(args,work,tag,noise)
folder=fullfile(work,tag);if ~isfolder(folder),mkdir(folder);end
if noise
    args=[args {['KNoiseFile=' fullfile(folder,'result.nois')]}];
    output=fullfile(folder,'noiseSet1','result1.nois');
else
    args=[args {['KSpaceFile=' fullfile(folder,'result.ksig')],['KMapFile=' fullfile(folder,'result.ktrj')]}];
    output=fullfile(folder,'result1.ksig');
end
end
function log=runSuccess(exe,args,work,tag,noise)
[args,output]=withOutputs(args,work,tag,noise);
[code,log]=runNative(exe,args);assert(code==0,'Valid fixture failed:\n%s',log);
fid=fopen(output,'r','ieee-le');assert(fid>=0);raw=fread(fid,Inf,'single');fclose(fid);
assert(numel(raw)==2 && all(isfinite(raw)),'Expected one finite complex sample.');
end
function log=runFailure(exe,args,work,tag,diagnostic,noise)
[args,output]=withOutputs(args,work,tag,noise);
assert(~isfile(output),'Failure fixture must start without output.');
[code,log]=runNative(exe,args);
assert(code~=0,'Invalid fixture reported success:\n%s',log);
assert(isempty(diagnostic)||contains(log,diagnostic),'Missing error diagnostic:\n%s',log);
assert(~isfile(output),'Rejected fixture created a signal/noise output.');
end
function finish(work,oldPath)
path(oldPath);if isfolder(work),rmdir(work,'s');end
end
