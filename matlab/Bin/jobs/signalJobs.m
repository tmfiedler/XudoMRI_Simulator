function queue=signalJobs(create)
%SIGNALJOBS One in-memory serial signal and noise queue per MATLAB session.
% signalJobs(false) inspects an existing queue without creating a window.
persistent current
if nargin<1,create=true;end
if isempty(current)||~isvalid(current)
    current=[];
    if create,current=SignalJobQueue;end
end
queue=current;
end
