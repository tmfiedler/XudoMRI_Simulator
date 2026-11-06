function [sequenceNames, workflows] = getSupportedSequences()
%GETSUPPORTEDSEQUENCES Register each generator name and its acquisition workflow.

    sequences = {
        'GRE',     'cartesian2D';
        'SE',      'cartesian2D';
        'GRE_EPI', 'cartesian2D';
        'RAD_3D',  'radial3D';
    };
    sequenceNames = sequences(:,1).';
    workflows = sequences(:,2).';
end
