
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%       SE with real spoiling
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function varargout = SE(TE,TR,MatSize,FOV,RF,ADC,GradOn,dummy,slice,nucleus)

DEBUG = 0;

%% Init
    MatSize1=MatSize(1);
    if length(MatSize)>1
        MatSize2=MatSize(2);
    else
        MatSize2=MatSize1;
    end
    FOV1=FOV(1);
    if length(FOV)>1
        FOV2=FOV(2);
    else
        FOV2=FOV1;
    end
    
    startTime = 0.001; %ms
    if nargin < 10 || isempty(nucleus)
        nucleus = getDefaultNucleus();
    end
    gamma = getNucleusGamma(nucleus);
    GMax = 22; %mT/m
    
    ADC.duration = MatSize1/ADC.BW; %ms

    % Use the same effective timing for limit queries and waveform generation.
    % Every endpoint is measured from TR start in milliseconds. In particular,
    % the phase rewinder can finish later than the readout rewinder.
    phaseDuration = 0;
    if GradOn.pe == 1 && MatSize2 > 1
        phaseDuration = 1/(FOV2/1000)/gamma*2*pi/(2*GMax/(MatSize2-1)/1000)*1000;
    end
    readoutRewind = 0;
    if GradOn.fe == 1, readoutRewind = ADC.duration/3; end
    sliceReph = 0;
    slicePost = 0;
    if GradOn.ss == 1
        sliceReph = RF.Duration/2/5;
        slicePost = RF.Duration/5;
    end
    minTE = max(2*(RF.Duration+sliceReph+slicePost), ...
        RF.Duration+ADC.duration+2*(slicePost+phaseDuration+readoutRewind));
    TE = max(TE,minTE);
    rfEnd = startTime+TE/2+RF.Duration;
    adcEnd = startTime+TE+RF.Duration/2+ADC.duration/2;
    endpoints = [rfEnd,adcEnd,adcEnd+readoutRewind, ...
        adcEnd+phaseDuration,rfEnd+slicePost];
    if dummy > 0
        % Preserve the historical dummy RF shift even with slice selection off.
        endpoints(end+1) = rfEnd+RF.Duration/5;
    end
    minTR = max(endpoints);
    TR = max(TR,minTR);
    
    frqBW = 4/RF.Duration*1000; % RF.Duration = 4/frqBW*1000; % ms
    if GradOn.ss == 1
        Gss.amp = frqBW * 2*pi / gamma / slice.TH * 1000; % frqBW = (Gss.amp/1000) * slice.TH * gamma /2/pi; % Gss.amp in mT/m
        frqOffset = (Gss.amp/1000) * slice.offset * gamma /2/pi;
    else
        Gss.amp = 0;
        frqOffset = 0;
    end
    RF.Freq = RF.Num / RF.Duration; % kHz
    
    %% Return SeqData
    if nargout == 1
        switch RF.Shape
            case 1 % 'Sinc'
                if RF.Num == 1
                    tempRF_Y = 1;
                else
                    tempRF_X = -(2/frqBW):(4/frqBW/(RF.Num-1)):(2/frqBW);
                    tempRF_Y = sinc(tempRF_X * frqBW);
                    clear tempRF_X;
                end
            case 2 % 'Rect'
                tempRF_Y = ones(1,RF.Num);
            case 3 % 'Gauss'
                tempRF_Y = (gausswin(RF.Num))';
        end;
        tempRF_Size = sum(tempRF_Y)/(RF.Freq*1000); % 1/RF.Freq = RF.Duration/RF.Num;
        tempRF_Y1 = tempRF_Y;
        
        if DEBUG == 1
            tempRF_X = -(2/frqBW):(4/frqBW/(80-1)):(2/frqBW);
            tempRF_Y = sinc(tempRF_X * frqBW);
            tempRF_Size = sum(tempRF_Y)/(RF.Freq*1000); % 1/RF.Freq = RF.Duration/RF.Num;
        end;
        if RF.FA > 0
            refocusScale = 180 / RF.FA;
        else
            refocusScale = 0;
        end
        % Absolute RF amplitude is controlled by Tx/B1+ scaling in Setup.m;
        % RF.FA only sets the 180-degree refocusing pulse relative to RF1.
        tempRF_Y2 = tempRF_Y .* refocusScale;
        
        %% Waveform plot

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%                            SE Sequence Diagram
%
%           |-----------------------------TE-----------------------------|
%
%  RF --|  RF1  |----------------------|  RF2  |----------------------------------------
%
%  Gs --|GradSS1|-|GradReph|-----------|GradSS2|----------------------------------------
%
%  Gp ----------------------|GradPE|-----------------------------------------------------
%
%  Gr ---------------------------------------------------|GradprePh|-|GradFE|-----------
%
% ADC ---------------------------------------------------------------| ADC  |-----------
% 
%     |-------------------------------------TR------------------------------------------|
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        Gss.refocusReph.duration = RF.Duration/5;

        % Bounded delays/tails may round just below zero at the exact limit.
        % Keep positive expressions unchanged for valid longer-TR waveforms.
        %% Dummy tStep
        if dummy>0
            varargout{1}.Dummy.tStep = [startTime,ones(1,RF.Num)/RF.Freq,TE/2-RF.Duration+Gss.refocusReph.duration,...
                ones(1,RF.Num)/RF.Freq,max(TR-startTime-RF.Duration-TE/2-Gss.refocusReph.duration,0)]; % ms; 1kHz = 1ms
        end;
        
        %% RF pulse
        varargout{1}.Main.RF.dPhs = 0;
        if DEBUG == 1
            varargout{1}.Main.RF.tStep = [startTime,ones(1,RF.Num)/RF.Freq,max(TE/2-RF.Duration,0),...
                ones(1,80)/RF.Freq,max(TR-startTime-RF.Duration-TE/2,0)]; % ms; 1kHz = 1ms
        else
            varargout{1}.Main.RF.tStep = [startTime,ones(1,RF.Num)/RF.Freq,max(TE/2-RF.Duration,0),...
                ones(1,RF.Num)/RF.Freq,max(TR-startTime-RF.Duration-TE/2,0)]; % ms; 1kHz = 1ms
        end;
        varargout{1}.Main.RF.value = [0+0i,tempRF_Y1.*(1+0i),0+0i,tempRF_Y2.*(1+0i),0+0i];
        
        if dummy>0
            varargout{1}.Dummy.RF.dPhs = 0;
            varargout{1}.Dummy.RF.tStep = varargout{1}.Dummy.tStep;
            varargout{1}.Dummy.RF.value = [0+0i,tempRF_Y1.*(1+0i),0+0i,tempRF_Y2.*(1+0i),0+0i];
        end;
        
        %% RF DFreq
        if DEBUG == 1
            varargout{1}.Main.DFreq.tStep = [startTime,ones(1,RF.Num)/RF.Freq,max(TE/2-RF.Duration,0),...
                ones(1,80)/RF.Freq,max(TR-startTime-RF.Duration-TE/2,0)]; % ms; 1kHz = 1ms
        else
            varargout{1}.Main.DFreq.tStep = [startTime,ones(1,RF.Num)/RF.Freq,max(TE/2-RF.Duration,0),...
                ones(1,RF.Num)/RF.Freq,max(TR-startTime-RF.Duration-TE/2,0)]; % ms; 1kHz = 1ms
        end;
        if DEBUG == 1            
            varargout{1}.Main.DFreq.value = [0,ones(1,RF.Num)*frqOffset,0,ones(1,80)*0,0];
        else
            varargout{1}.Main.DFreq.value = [0,ones(1,RF.Num)*frqOffset,0,ones(1,RF.Num)*frqOffset,0];
        end;
        
        if dummy>0
            varargout{1}.Dummy.DFreq.tStep = varargout{1}.Dummy.tStep;
            varargout{1}.Dummy.DFreq.value = zeros(1,2*RF.Num+3);
        end;
        
        %% ADC
        varargout{1}.Main.ADC.tStep = [startTime,TE+RF.Duration/2-ADC.duration/2,...
            ones(1,MatSize1)/ADC.BW,max(TR-TE-RF.Duration/2-startTime-ADC.duration/2,0)]; % ms
        varargout{1}.Main.ADC.value = [-1,0,ones(1,MatSize1),0];
        
        if dummy>0
            varargout{1}.Dummy.ADC.tStep = varargout{1}.Dummy.tStep;
            varargout{1}.Dummy.ADC.value = [-1,zeros(1,2*RF.Num+2)];
        end;

        %% Slice Selection gradient
        if GradOn.ss == 1
            Gss.reph.duration = RF.Duration/2/5;
            Gss.duration = RF.Duration;
            Gss.rephAmp = -Gss.amp*Gss.duration/2/Gss.reph.duration;
            
            Gss.refocusReph.duration = RF.Duration/5;
            Gss.refocusRephAmp = -Gss.amp*Gss.duration/2/Gss.refocusReph.duration;
            
            varargout{1}.Main.Gss.tStep = [startTime,Gss.duration,Gss.reph.duration,...
                max(TE/2 - Gss.duration - Gss.reph.duration - Gss.refocusReph.duration,0), Gss.refocusReph.duration, Gss.duration, Gss.refocusReph.duration,...
                max(TR-startTime-Gss.duration-Gss.reph.duration-(TE/2 - Gss.duration - Gss.reph.duration - Gss.refocusReph.duration)-Gss.duration-2*Gss.refocusReph.duration,0)]; % ms
            if DEBUG == 1
                varargout{1}.Main.Gss.value = [0,Gss.amp,Gss.rephAmp,0,Gss.refocusRephAmp,0,Gss.refocusRephAmp,0];
            else
                varargout{1}.Main.Gss.value = [0,Gss.amp,Gss.rephAmp,0,Gss.refocusRephAmp,Gss.amp,Gss.refocusRephAmp,0];
            end;
        else
            Gss.duration = 0;
            Gss.reph.duration = 0;
            varargout{1}.Main.Gss.tStep = [startTime,TR-startTime]; % ms
            varargout{1}.Main.Gss.value = [0,0];
        end;
        
        if dummy>0
            varargout{1}.Dummy.Gss.tStep = varargout{1}.Dummy.tStep;
            varargout{1}.Dummy.Gss.value = zeros(1,2*RF.Num+3);
        end;

        %% Phase Encoding gradient
        if GradOn.fe == 1
            GfePreph.duration = ADC.duration/3;
        else
            GfePreph.duration = 0;
        end

        if GradOn.pe == 1 && MatSize2 > 1
            Gpe.duration = 1/(FOV2/1000)/gamma*2*pi/(2*GMax/(MatSize2-1)/1000)*1000; %ms, Page 239
            Gpe.delAmp = 2*GMax/(MatSize2-1); %mT/m
            Gpe.rewind.duration = Gpe.duration;
            Gpe.delay = TE+RF.Duration/2-ADC.duration/2-GfePreph.duration-Gpe.duration;
            
            varargout{1}.Main.Gpe.tStep = [startTime,Gpe.delay,...
                Gpe.duration,ADC.duration+GfePreph.duration,Gpe.rewind.duration,...
                max(TR-startTime-Gpe.delay-Gpe.duration-ADC.duration-GfePreph.duration-Gpe.rewind.duration,0)];
            % Match the Cartesian line-order convention used by GRE: acquire
            % phase encodes from negative to positive. The rewinder remains
            % equal and opposite for every repetition.
            varargout{1}.Main.Gpe.value = [0,0,-GMax,0,GMax,0];
            varargout{1}.Main.Gpe.increment = [0,0,Gpe.delAmp,0,-Gpe.delAmp,0]; % Abs Value
        else
            Gpe.duration = 0;
            varargout{1}.Main.Gpe.tStep = [startTime,TR-startTime]; %ms
            varargout{1}.Main.Gpe.value = [0,0];
            varargout{1}.Main.Gpe.increment = [0,0]; % Abs Value
        end;
        
        if dummy>0
            varargout{1}.Dummy.Gpe.tStep = varargout{1}.Dummy.tStep;
            varargout{1}.Dummy.Gpe.value = zeros(1,2*RF.Num+3);
        end;
            
        %% Frequency Encoding gradient
        if GradOn.fe == 1
            Gfe.preph.duration = ADC.duration/3; %ms
            Gfe.amp = 1/gamma*2*pi*(ADC.BW*1000)/(FOV1/1000)*1000; %mT/m, Page 238
            Gfe.duration=ADC.duration; %ms
            Gfe.prephAmp = -Gfe.amp*Gfe.duration/2/Gfe.preph.duration; %mT/m
            
            Gfe.rewind.duration = Gfe.preph.duration;
            Gfe.rewindAmp = Gfe.prephAmp;
            varargout{1}.Main.Gfe.tStep = [startTime,...
                TE+RF.Duration/2-ADC.duration/2-Gfe.preph.duration,...
                Gfe.preph.duration,ones(1,MatSize1)/ADC.BW,Gfe.rewind.duration,...
                max(TR-startTime-TE-RF.Duration/2-ADC.duration/2-Gfe.rewind.duration,0)];
            varargout{1}.Main.Gfe.value = [0,0,Gfe.prephAmp,Gfe.amp*ones(1,MatSize1),Gfe.rewindAmp,0];            
        else
            varargout{1}.Main.Gfe.tStep = [startTime,TR-startTime]; %ms
            varargout{1}.Main.Gfe.value = [0,0];
        end;
        
        if dummy>0
            varargout{1}.Dummy.Gfe.tStep = varargout{1}.Dummy.tStep;
            varargout{1}.Dummy.Gfe.value = zeros(1,2*RF.Num+3);
        end;
        
        %%
        varargout{1}.TR = TR; %ms
        varargout{1}.Main.repeat = MatSize2;
        varargout{1}.Dummy.repeat = dummy;
    end;

    %% Return [minTE, minTR]
    if nargout == 2
        varargout{1} = minTE;
        varargout{2} = minTR;
    end;

end
