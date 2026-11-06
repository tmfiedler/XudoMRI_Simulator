classdef SignalProcess < handle
    %SIGNALPROCESS One owned native process, polled without blocking MATLAB.
    properties (SetAccess=private)
        State
        Done = false
    end
    properties (Access=private)
        Process
        Streams
        Buffers
        Tasks
        Ended = [false false]
        Started = false
        Clock
        StdoutTail = ''
        OutputTails = {'',''}
    end
    methods
        function obj=SignalProcess(executable,arguments,directory)
            obj.State=signalProgressStatus('');obj.State.ExitCode=NaN;
            info=System.Diagnostics.ProcessStartInfo;
            info.FileName=char(executable);info.Arguments=char(arguments);
            info.WorkingDirectory=char(directory);
            info.UseShellExecute=false;info.CreateNoWindow=true;
            info.RedirectStandardOutput=true;info.RedirectStandardError=true;
            info.RedirectStandardInput=true;
            obj.Process=System.Diagnostics.Process;obj.Process.StartInfo=info;
        end
        function start(obj)
            % The queue owns this object before any native child is started.
            assert(~obj.Started,'SignalProcess:Started','This process was already started.');
            assert(obj.Process.Start(),'SignalProcess:Start','Could not start the simulation engine.');
            obj.Started=true;obj.Clock=tic;
            obj.Streams={obj.Process.StandardOutput,obj.Process.StandardError};
            obj.Buffers={NET.createArray('System.Char',4096),NET.createArray('System.Char',4096)};
            obj.Tasks=cell(1,2);
            for k=1:2,obj.startRead(k);end
            try
                obj.Process.StandardInput.WriteLine('');obj.Process.StandardInput.Close();
            catch ex
                % A child that exits immediately may already have closed stdin.
                if ~obj.Process.HasExited,rethrow(ex);end
            end
        end
        function poll(obj)
            if obj.Done,return;end
            for k=1:2
                % Bound one timer callback's work, even for a verbose child.
                for batch=1:16
                    if obj.Ended(k)||~obj.Tasks{k}.IsCompleted,break;end
                    count=double(obj.Tasks{k}.Result);
                    if count==0,obj.Ended(k)=true;break;end
                    chunk=char(System.String(obj.Buffers{k},int32(0),int32(count)));
                    if k==1
                        obj.StdoutTail=[obj.StdoutTail chunk];
                        obj.StdoutTail=obj.StdoutTail(max(1,end-8191):end);
                        obj.State=signalProgressStatus(obj.StdoutTail,obj.State);
                    end
                    obj.OutputTails{k}=[obj.OutputTails{k} chunk];
                    if numel(obj.OutputTails{k})>48000
                        obj.OutputTails{k}=obj.OutputTails{k}(end-47999:end);
                        obj.State.OutputTruncated=true;
                    end
                    obj.State.Output=['[stdout]' newline obj.OutputTails{1} newline '[stderr]' newline obj.OutputTails{2}];
                    obj.startRead(k);
                end
            end
            obj.State.ElapsedSeconds=toc(obj.Clock);
            if all(obj.Ended)&&obj.Process.HasExited
                obj.State.ExitCode=double(obj.Process.ExitCode);
                if obj.State.ExitCode==0
                    obj.State.Phase='completed';obj.State.Percent=100;obj.State.RemainingSeconds=0;
                else
                    obj.State.Phase='failed';obj.State.RemainingSeconds=NaN;
                end
                obj.Done=true;
            end
        end
        function exited=hasExited(obj)
            exited=isempty(obj.Process)||~obj.Started||obj.Process.HasExited;
        end
        function close(obj)
            if isempty(obj.Process),return;end
            if obj.Started&&~obj.Process.HasExited
                try
                    obj.Process.Kill();
                catch ex
                    % Exiting between HasExited and Kill is normal.
                    if ~obj.Process.HasExited,rethrow(ex);end
                end
                assert(obj.Process.WaitForExit(int32(5000)),'SignalProcess:Cleanup', ...
                    'The interrupted native process did not exit within five seconds.');
            end
            obj.Process.Dispose();obj.Process=[];
        end
        function delete(obj)
            obj.close();
        end
    end
    methods (Access=private)
        function startRead(obj,k)
            obj.Tasks{k}=obj.Streams{k}.ReadAsync(obj.Buffers{k},int32(0),int32(4096));
        end
    end
end
