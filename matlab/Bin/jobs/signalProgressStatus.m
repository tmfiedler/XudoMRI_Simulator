function state=signalProgressStatus(text,state)
%SIGNALPROGRESSSTATUS Interpret completed compute work, never process success.
if nargin<2
    state=struct('Phase','preparing','Percent',NaN,'RemainingSeconds',NaN, ...
        'ElapsedSeconds',0,'Output','','OutputTruncated',false);
end
if ismember(state.Phase,{'completed','failed','finalizing'}),return;end
tokens=regexp(text,'Calculating\s+(\d+(?:\.\d+)?)% done, remaining time\s+(estimating\.\.\.|\d+:\d\d:\d\d)','tokens');
if ~isempty(tokens)
    last=tokens{end};value=str2double(last{1});
    if value>=0&&value<=100&&(isnan(state.Percent)||value>=state.Percent)
        state.Phase='running';state.Percent=min(value,99.9);
        state.RemainingSeconds=NaN;
        if ~strcmp(last{2},'estimating...')
            hms=sscanf(last{2},'%d:%d:%d');
            if numel(hms)==3,state.RemainingSeconds=double(hms.'*[3600;60;1]);end
        end
    end
end
if contains(text,'Finalizing simulation outputs...')
    state.Phase='finalizing';state.Percent=100;state.RemainingSeconds=NaN;
end
end
