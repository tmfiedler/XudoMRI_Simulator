function varargout = SeqInterfaceIn(varargin)
    switch nargout
        case 0
            if nargin >= 2
                set(varargin{2},'Enable','off');
            end;
        case 1
            varargout{1} = getSupportedSequences();
    end;
end
