function tf = usesRadial3DWorkflow(sequenceName)
%USESRADIAL3DWORKFLOW Check whether a registered sequence uses the 3D radial workflow.

    [sequenceNames, workflows] = getSupportedSequences();
    tf = any(strcmpi(sequenceName,sequenceNames) & strcmp(workflows,'radial3D'));
end
