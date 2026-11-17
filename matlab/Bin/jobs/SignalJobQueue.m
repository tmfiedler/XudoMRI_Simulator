classdef SignalJobQueue < handle
    %SIGNALJOBQUEUE Serial FIFO of captured signal and noise commands and run folders.
    % Jobs read no mutable Setup state. Existing protocol/sequence/batch files
    % remain the run record; this queue is held only in the MATLAB session.
    properties (Access=private)
        Jobs = struct('Descriptor',{},'State',{},'Process',{})
        Active = 0
        Polling = false
        CleanupFailure = ''
        CancelRequested = 0
        Timer
        Window = []
        Table = []
        Detail = []
        CancelButton = []
        Selected = 0
        LogWindow = []
        LogText = []
        Visible
    end
    methods
        function obj=SignalJobQueue(visible)
            if nargin<1,visible='on';end
            obj.Visible=visible;
            obj.Timer=timer('ExecutionMode','fixedSpacing','Period',.1,...
                'BusyMode','drop','Name','SignalJobQueue','TimerFcn',@(~,~)obj.service());
        end
        function ids=enqueue(obj,descriptors)
            % A combined run reserves its directory once and adds both jobs together.
            directory=descriptors(1).Directory;
            assert(~obj.ownsDirectory(directory),'SignalQueue:Directory',...
                'That output folder already belongs to a queued or running job.');
            if numel(descriptors)>1
                assert(numel(descriptors)==2 && ...
                    strcmp(obj.jobType(descriptors(1)),'Signal') && ...
                    strcmp(obj.jobType(descriptors(2)),'Noise') && ...
                    strcmpi(obj.directoryKey(directory),obj.directoryKey(descriptors(2).Directory)),...
                    'SignalQueue:InvalidRun','Expected one Signal job followed by one Noise job in the same run folder.');
            end
            state=signalProgressStatus('');state.Phase='queued';state.ExitCode=NaN;
            ids=numel(obj.Jobs)+(1:numel(descriptors));
            for n=1:numel(ids)
                obj.Jobs(ids(n))=struct('Descriptor',descriptors(n),'State',state,'Process',[]);
            end
            obj.Selected=ids(1);obj.show();
            if strcmp(obj.Timer.Running,'off'),start(obj.Timer);end
        end
        function show(obj)
            if isempty(obj.Window)||~isgraphics(obj.Window)
                obj.Window=figure('Name','Simulation jobs','NumberTitle','off',...
                    'MenuBar','none','ToolBar','none','Position',[100 100 1100 480],...
                    'Visible','off','CloseRequestFcn',@(~,~)set(obj.Window,'Visible','off'));
                obj.Table=uitable(obj.Window,'Units','pixels',...
                    'ColumnName',{'Job','Study','Type','Backend','Status','Compute %','Elapsed','Remaining (est.)','Output folder'},...
                    'ColumnWidth',{40 140 65 65 105 95 80 145 320},...
                    'CellSelectionCallback',@(~,e)obj.select(e));
                obj.Detail=uicontrol(obj.Window,'Style','text','Units','pixels',...
                    'HorizontalAlignment','left');
                uicontrol(obj.Window,'Style','pushbutton','String','View output',...
                    'Units','pixels','Callback',@(~,~)obj.showOutput());
                uicontrol(obj.Window,'Style','pushbutton','String','Open run folder',...
                    'Units','pixels','Callback',@(~,~)obj.openFolder());
                obj.CancelButton=uicontrol(obj.Window,'Style','pushbutton','String','Cancel job',...
                    'Units','pixels','Callback',@(~,~)obj.cancelJob(obj.Selected));
            end
            set(obj.Window,'SizeChangedFcn',@(~,~)obj.layout());obj.layout();
            set(obj.Window,'Visible',obj.Visible);obj.refresh();
        end
        function records=snapshot(obj),records=rmfield(obj.Jobs,'Process');end
        function owned=ownsDirectory(obj,directory)
            owned=false;
            for j=1:numel(obj.Jobs)
                if ismember(obj.Jobs(j).State.Phase,{'queued','preparing','running','finalizing','cancelling','cleanup failed'})&&...
                        strcmpi(obj.directoryKey(obj.Jobs(j).Descriptor.Directory),obj.directoryKey(directory))
                    owned=true;return;
                end
            end
        end
        function cancelJob(obj,id)
            if id<1||id>numel(obj.Jobs),return;end
            if strcmp(obj.Jobs(id).State.Phase,'queued')
                obj.Jobs(id).State.Phase='cancelled';obj.refresh();
            elseif id==obj.Active&&ismember(obj.Jobs(id).State.Phase,{'preparing','running','finalizing'})
                % Service the request outside GUI callbacks; retain writer ownership.
                obj.CancelRequested=id;obj.Jobs(id).State.Phase='cancelling';
                obj.Jobs(id).State.RemainingSeconds=NaN;obj.refresh();
            end
        end
        function service(obj)
            if obj.Polling,return;end
            obj.Polling=true;guard=onCleanup(@()obj.finishPoll()); %#ok<NASGU>
            if obj.Active==0
                next=find(arrayfun(@(j)strcmp(j.State.Phase,'queued'),obj.Jobs),1);
                if isempty(next)
                    if strcmp(obj.Timer.Running,'on'),stop(obj.Timer);end
                    obj.refresh();return;
                end
                obj.Active=next;obj.Jobs(next).State.Phase='preparing';d=obj.Jobs(next).Descriptor;
                try
                    obj.Jobs(next).Process=SignalProcess(d.Executable,d.Arguments,d.Directory);
                    obj.Jobs(next).Process.start();
                catch ex
                    obj.cleanupFailedJob(next,ex.message);
                end
            else
                id=obj.Active;
                if ~isempty(obj.CleanupFailure)
                    % Keep the writer owned and pause FIFO until exit is confirmed.
                    try
                        if ~obj.Jobs(id).Process.hasExited(),obj.refresh();return;end
                        obj.Jobs(id).Process.close();delete(obj.Jobs(id).Process);
                        obj.Jobs(id).Process=[];obj.fail(id,obj.CleanupFailure);
                        obj.CleanupFailure='';obj.Active=0;obj.CancelRequested=0;
                    catch cleanup
                        if ~contains(obj.Jobs(id).State.Output,cleanup.message)
                            obj.Jobs(id).State.Output=[obj.Jobs(id).State.Output newline cleanup.message];
                        end
                    end
                    obj.refresh();return;
                end
                try
                    obj.Jobs(id).Process.poll();obj.Jobs(id).State=obj.Jobs(id).Process.State;
                    if strcmp(obj.jobType(obj.Jobs(id).Descriptor),'Noise') && ...
                            strcmp(obj.Jobs(id).State.Phase,'preparing')
                        obj.Jobs(id).State.Phase='running';
                    end
                    cancelNow=obj.CancelRequested==id&&~obj.Jobs(id).Process.hasExited();
                    if obj.Jobs(id).Process.Done||cancelNow
                        obj.Jobs(id).Process.close();
                        if cancelNow
                            obj.Jobs(id).State.Phase='cancelled';obj.Jobs(id).State.RemainingSeconds=NaN;
                            obj.Jobs(id).State.Output=[obj.Jobs(id).State.Output newline 'Cancelled by user. Output files may be incomplete.'];
                        end
                        delete(obj.Jobs(id).Process);obj.Jobs(id).Process=[];obj.Active=0;obj.CancelRequested=0;
                    elseif obj.CancelRequested==id
                        obj.Jobs(id).State.Phase='cancelling';obj.Jobs(id).State.RemainingSeconds=NaN;
                    end
                catch ex
                    obj.cleanupFailedJob(id,ex.message);
                end
            end
            obj.refresh();
        end
        function delete(obj)
            if ~isempty(obj.Timer)&&isvalid(obj.Timer),stop(obj.Timer);delete(obj.Timer);end
            for j=1:numel(obj.Jobs)
                if ~isempty(obj.Jobs(j).Process),delete(obj.Jobs(j).Process);end
            end
            if isgraphics(obj.Window),delete(obj.Window);end
            if isgraphics(obj.LogWindow),delete(obj.LogWindow);end
        end
    end
    methods (Access=private)
        function layout(obj)
            % Only the table absorbs vertical resizing; the footer stays compact.
            delete(setdiff(findall(obj.Window,'Type','uicontrol','Style','text'),obj.Detail));
            bounds=getpixelposition(obj.Window);margin=16;gap=6;buttonHeight=30;detailHeight=22;
            width=max(1,bounds(3)-2*margin);detailY=margin+buttonHeight+gap;
            tableY=detailY+detailHeight+10;
            set(obj.Table,'Units','pixels','Position',[margin tableY width max(1,bounds(4)-tableY-margin)]);
            set(obj.Detail,'Units','pixels','Position',[margin detailY width detailHeight]);
            buttons={findall(obj.Window,'Type','uicontrol','Style','pushbutton','String','View output'),...
                findall(obj.Window,'Type','uicontrol','Style','pushbutton','String','Open run folder')};
            if isempty(obj.CancelButton)||~isgraphics(obj.CancelButton)
                % An already-open window can still have its original Cancel control.
                obj.CancelButton=setdiff(findall(obj.Window,'Type','uicontrol','Style','pushbutton'),...
                    [buttons{1};buttons{2}]);
            end
            set(obj.CancelButton,'String','Cancel job','Callback',@(~,~)obj.cancelJob(obj.Selected));
            buttons{3}=obj.CancelButton;buttonGap=12;
            buttonWidth=max(1,min(160,(width-2*buttonGap)/3));
            for k=1:3
                set(buttons{k},'Units','pixels','Position',[margin+(k-1)*(buttonWidth+buttonGap) margin buttonWidth buttonHeight]);
            end
        end
        function key=directoryKey(~,directory)
            key=regexprep(char(System.IO.Path.GetFullPath(char(directory))),'[\\/]+$','');
        end
        function finishPoll(obj),obj.Polling=false;end
        function cleanupFailedJob(obj,id,message)
            try
                if ~isempty(obj.Jobs(id).Process)
                    obj.Jobs(id).Process.close();delete(obj.Jobs(id).Process);obj.Jobs(id).Process=[];
                end
                obj.fail(id,message);obj.Active=0;obj.CancelRequested=0;
            catch cleanup
                obj.CleanupFailure=sprintf('%s\nQueue paused: native process cleanup failed: %s',message,cleanup.message);
                obj.fail(id,obj.CleanupFailure);obj.Jobs(id).State.Phase='cleanup failed';
            end
        end
        function fail(obj,id,message)
            obj.Jobs(id).State.Phase='failed';obj.Jobs(id).State.RemainingSeconds=NaN;
            obj.Jobs(id).State.Output=[obj.Jobs(id).State.Output newline message];
        end
        function select(obj,event)
            if ~isempty(event.Indices),obj.Selected=event.Indices(1,1);obj.refresh();end
        end
        function type=jobType(~,descriptor)
            type='Signal';
            if isfield(descriptor,'Type'),type=descriptor.Type;end
        end
        function refresh(obj)
            if isempty(obj.Window)||~isgraphics(obj.Window),return;end
            if isempty(obj.CancelButton)||~isgraphics(obj.CancelButton),obj.layout();end
            data=cell(numel(obj.Jobs),9);
            for j=1:numel(obj.Jobs)
                s=obj.Jobs(j).State;d=obj.Jobs(j).Descriptor;percent='—';remaining='—';elapsed='—';
                if isfinite(s.Percent),percent=sprintf('%.1f',s.Percent);end
                if ~strcmp(s.Phase,'queued')&&s.ElapsedSeconds>0,elapsed=obj.duration(s.ElapsedSeconds);end
                if strcmp(s.Phase,'running')&&isfinite(s.Percent),remaining=obj.duration(s.RemainingSeconds);end
                status=s.Phase;
                if strcmp(status,'failed')&&isfinite(s.ExitCode),status=sprintf('failed (%d)',s.ExitCode);end
                data(j,:)={j,d.Study,obj.jobType(d),d.Backend,status,percent,elapsed,remaining,d.Directory};
            end
            set(obj.Table,'Data',data);
            details='Select a job.';cancellable=false;
            if obj.Selected>=1&&obj.Selected<=numel(obj.Jobs)
                d=obj.Jobs(obj.Selected).Descriptor;
                details=sprintf('Job %d: %s',obj.Selected,d.Directory);
                cancellable=ismember(obj.Jobs(obj.Selected).State.Phase,{'queued','preparing','running','finalizing'});
            end
            set(obj.Detail,'String',details);
            if cancellable,set(obj.CancelButton,'Enable','on');else,set(obj.CancelButton,'Enable','off');end
            if isgraphics(obj.LogText),set(obj.LogText,'String',obj.outputText());end
        end
        function text=outputText(obj)
            text='Select a job to inspect its engine output.';
            if obj.Selected<1||obj.Selected>numel(obj.Jobs),return;end
            j=obj.Jobs(obj.Selected);d=j.Descriptor;
            text=sprintf('Job %d — %s — %s — %s — %s\n',obj.Selected,d.Study,obj.jobType(d),d.Backend,j.State.Phase);
            if j.State.OutputTruncated,text=[text 'Earlier output omitted; showing the latest output from each stream.' newline];end
            text=[text regexprep(j.State.Output,'\r\n|\r',newline)];
        end
        function showOutput(obj)
            if isempty(obj.LogWindow)||~isgraphics(obj.LogWindow)
                obj.LogWindow=figure('Name','Job engine output','NumberTitle','off',...
                    'MenuBar','none','ToolBar','none','Position',[150 150 820 460],'Visible',obj.Visible);
                obj.LogText=uicontrol(obj.LogWindow,'Style','edit','Max',2,'Min',0,'Enable','inactive',...
                    'Units','normalized','Position',[.02 .02 .96 .96],'HorizontalAlignment','left',...
                    'FontName','Consolas','FontSize',10);
            end
            set(obj.LogText,'String',obj.outputText());set(obj.LogWindow,'Visible',obj.Visible);
        end
        function openFolder(obj)
            if obj.Selected>=1&&obj.Selected<=numel(obj.Jobs),winopen(obj.Jobs(obj.Selected).Descriptor.Directory);end
        end
        function value=duration(~,seconds)
            if ~isfinite(seconds),value='Estimating...';return;end
            n=floor(max(0,seconds)+.5);value=sprintf('%02d:%02d:%02d',floor(n/3600),floor(mod(n,3600)/60),mod(n,60));
        end
    end
end
