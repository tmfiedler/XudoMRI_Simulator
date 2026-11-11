function testFOV
%TESTFOV Check prescription geometry, generated carriers and image centering.
oldPath = path;
cleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(repo,'matlab')); initializeSimulatorPaths;

info = struct('ctrX',10,'ctrY',20,'ctrZ',30,'setX',2,'setY',-3,'setZ',4, ...
    'widX',1,'widY',2,'widZ',3,'FOV',[60 24],'sliceTH',6);
displayInfo = struct('ActiveSequenceName','GRE','SwapInPlane',false,'SliceSelect',true);
[center,width] = fovBox(info,displayInfo,3);
assert(isequal(center,[12 17 34]) && isequal(width,[24 3 20]));
displayInfo.SwapInPlane = true;
[~,width] = fovBox(info,displayInfo,3);
assert(isequal(width,[60 3 8]));

rf = struct('Shape',1,'Duration',1.2,'Num',20,'FA',90);
grad = struct('ss',1,'pe',1,'fe',1);
slice = struct('TH',.004,'offset',-.010);
% Pulse bandwidth is four cycles over the pulse duration. The selected
% plane is 2.5 nominal slice thicknesses below the center.
expectedHz = -2.5*4/(rf.Duration*1e-3);
for nucleus = {'1H','23Na'}
    for generator = {@GRE,@SE,@GRE_EPI}
        for shape = 1:3
            rf.Shape = shape;
            generate = generator{1};
            wave = generate(60,300,[8 6],[48 36],rf,struct('BW',16),grad,1,slice,nucleus{1});
            seq = combineSeqRect(wave,2,{'H--F'},1);
            carrier = seq.Main.DFreq.value;
            active = carrier ~= 0;
            assert(any(active) && max(abs(carrier(active)-expectedHz)) < 1e-5);
            misplacedTime = sum(seq.Main.Time.value(active & seq.Main.Gx.value <= 0));
            assert(misplacedTime < 1e-8, ...
                '%s %s RF shape %d had %.12g ms of carrier outside positive Gss.', ...
                nucleus{1},func2str(generate),shape,misplacedTime);
            assert(all(seq.Dummy.DFreq.value == 0));
        end
    end
end

% Model X/Y trajectory of a reversed-PE Cartesian EPI acquisition.
[kx,ky] = ndgrid((-4:3)/.048,(2:-1:-3)/.036);
kx(:,2:2:end) = flipud(kx(:,2:2:end));
k = [kx(:),ky(:),zeros(numel(kx),1)];
point = [.002;-.006;0];
signal = exp(2i*pi*k*point);
protocol = struct('MatSize',[8 6],'SequenceType','GRE_EPI', ...
    'SliceOrientation','Axial','PEDirection','A--P');
protocol.FOVPhase = fovCenterPhase(k,[2 -3 0],[1 2 3]);
assert(max(abs(signal.*protocol.FOVPhase-1)) < 1e-12);
image = reconstructCartesianDataset(signal,protocol);
assert(abs(max(image.volumeRSS(:))-48) < 1e-6 && nnz(image.volumeRSS > 1e-6) == 1);
fprintf('PASS: FOV geometry, both nuclei and three Cartesian generators, EPI recentering.\n');
end
