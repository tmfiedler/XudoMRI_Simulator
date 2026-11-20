function varargout = SeqInterfaceOut(tempStr,tempNum,TE,TR,MatSize,FOV,RF,ADC,GradOn,dummy,slice,TI,nucleus)

    if nargin < 13 || isempty(nucleus)
        nucleus = getDefaultNucleus();
    end

    errStr = 0;
    sequenceFn = resolveSequence(tempStr,tempNum);

    if isempty(sequenceFn)
        errStr = 1;
    elseif nargout == 1
        varargout{1} = sequenceFn(TE,TR,MatSize,FOV,RF,ADC,GradOn,dummy,slice,nucleus);
    else
        if usesRadial3DWorkflow(tempStr)
            [minTE,minTR,minTI] = sequenceFn(TE,TR,MatSize,FOV,RF,ADC,GradOn,dummy,slice,nucleus);
            varargout{3} = minTI;
            if isstruct(TI) && isfield(TI,'handle') && str2double(get(TI.handle,'String')) < minTI
                set(TI.handle,'String',num2str(round(minTI*10000)/10000));
            end;
        else
            [minTE,minTR] = sequenceFn(TE,TR,MatSize,FOV,RF,ADC,GradOn,dummy,slice,nucleus);
        end

        varargout{1} = minTE;
        varargout{2} = minTR;
    end;

    if errStr==1
        errordlg('Error in SeqInterfaceOut.m.');
    end;

end

function sequenceFn = resolveSequence(tempStr,tempNum)

    sequenceNames = getSupportedSequences();
    if tempNum < 1 || tempNum > numel(sequenceNames)
        sequenceFn = [];
        return;
    end

    expectedName = sequenceNames{tempNum};
    if strcmpi(tempStr,expectedName) == 0
        sequenceFn = [];
        return;
    end

    sequenceFn = str2func(expectedName);
end
