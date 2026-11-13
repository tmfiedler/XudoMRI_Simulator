function writeSetupProtocol(filename,protocol)
%WRITESETUPPROTOCOL Write a Setup snapshot in the current .prot format.
hasRadialResolution = usesRadial3DWorkflow(protocol.sequenceType) && ...
    isfield(protocol,'radialResolutionText') && ~isempty(strtrim(protocol.radialResolutionText));
if hasRadialResolution
    parseRadialResolutionMm(protocol.radialResolutionText);
end
fid = fopen(filename,'w');
if fid >= 0
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
end

fprintf(fid,'INPUT FILENAMES:\n');
writeFiles('Geometry Filename:',protocol.geometryFilename);
writeFiles('Tissue Filename:',protocol.tissueFilename);
writeFiles('Sequence Filename:',protocol.sequenceFilename);
writeFiles('Delta Bo Filename:',protocol.deltaB0Filename);
writeField('# Tx:',num2str(protocol.tx.Num));
fprintf(fid,'  Tx Mag & Phs:\n');
for n = 1:protocol.tx.Num
    fprintf(fid,'    %s %s\n',num2str(protocol.tx.MagMat(n)),num2str(protocol.tx.PhsMat(n)));
end
writeField('Shim B1+ (uT):',protocol.shimB1Text);
writeFiles('B1p Filename:',protocol.b1PlusFiles);
writeFiles('E1p Filename:',protocol.e1PlusFiles);
writeField('# Rx:',num2str(protocol.rxCount));
writeFiles('B1m Filename:',protocol.b1MinusFiles);
writeFiles('E1m Filename:',protocol.e1MinusFiles);
writeFiles('Gx Filename:',protocol.gxFilename);
writeFiles('Gy Filename:',protocol.gyFilename);
writeFiles('Gz Filename:',protocol.gzFilename);

fprintf(fid,'\nOUTPUT FILENAMES:\n');
writeFiles('KSpace Filename:',protocol.kspaceFilename);
writeFiles('KMap Filename:',protocol.trajectoryFilename);
writeFiles('Noise Filename:',protocol.noiseFilename);
writeFiles('SAR Filename:',protocol.sarFilename);

fprintf(fid,'\nGEOMETRY EDITOR SETUP:\n');
writeField('Display:',protocol.display);
writeField('Scale:',protocol.scale);
writeField('Slice Orientation:',protocol.sliceOrientation);
writeField('Slice Thickness:',protocol.sliceThicknessText);
writeField('Slice Position:',protocol.slicePositionText);
writeXYZ('Sample Min:','Min',{protocol.xMinText,protocol.yMinText,protocol.zMinText});
writeXYZ('Sample Max:','Max',{protocol.xMaxText,protocol.yMaxText,protocol.zMaxText});
writeXYZ('Grad. IsoCtr:','Ctr',{protocol.xCenterText,protocol.yCenterText,protocol.zCenterText});
writeField('Unified FOV Prescription:','1');
writeXYZ('FOV Offset:','Set',{protocol.xOffsetText,protocol.yOffsetText,protocol.zOffsetText});
fprintf(fid,'  Filter:\n      0\n');
writeXYZ('Model Res.:','Wid',{protocol.xWidthText,protocol.yWidthText,protocol.zWidthText});

fprintf(fid,'\nIMAGING PARAMETER SETUP:\n');
writeField('B0(T):',protocol.b0Text);
writeField('Nucleus:',protocol.nucleus);
writeField('Sequence Type:',protocol.sequenceType);
if isfield(protocol,'scannerProfile') && ~isempty(protocol.scannerProfile)
    writeField('Scanner Profile:',protocol.scannerProfile.name);
    writeField('Scanner Gradient Limits:',sprintf('%.17g %.17g %.17g',protocol.scannerProfile.limits));
end
writeField('RF Shape:',protocol.rfShape);
writeField('RF Duration(ms):',protocol.rfDurationText);
writeField('# Points in RF Pulse:',protocol.rfCountText);
writeField('RF Flip Angle:',protocol.flipAngleText);
writeField('Target B1+ (uT):',protocol.targetB1Text);
writeField('FOV(mm)',num2str(protocol.fov));
writeField('MatSize:',num2str(protocol.matrixSize));
writeField('ADC Freq(kHz):',protocol.adcFrequencyText);
if hasRadialResolution
    writeField('Radial Acquisition Resolution(mm):',protocol.radialResolutionText);
end
writeField('TI_Duration(ms):',protocol.inversionTimeText);
fprintf(fid,'  Gradient ON:\n');
fprintf(fid,'    SS:\n      %s\n',num2str(protocol.sliceSelect));
fprintf(fid,'    PE:\n      %s\n',num2str(protocol.phaseEncode));
fprintf(fid,'    FE:\n      %s\n',num2str(protocol.frequencyEncode));
writeField('TE(ms):',protocol.teText);
writeField('TR(ms):',protocol.trText);
writeField('#Dummy TRs:',protocol.dummyCountText);
writeField('PE Direct:',protocol.phaseEncodeDirection);

fprintf(fid,'\nPROGRAM INFO:\n');
writeField('NumIso:',protocol.numIsoText);
writeField('CPU #:',protocol.cpuCountText);
writeField('Signal Engine:',protocol.signalEngine);
writeField('NEX:',protocol.nexText);
writeField('Noise Loading Domain:',protocol.noiseLoading.Mode);
writeField('Noise Crop Bounds:',num2str(protocol.noiseLoading.Bounds));
writeField('Noise Crop Note:',protocol.noiseLoading.Note);
writeField('Mode:',protocol.mode);

    function writeField(label,value)
        fprintf(fid,'  %s\n    %s\n',label,value);
    end

    function writeFiles(label,files)
        fprintf(fid,'  %s\n',label);
        if isempty(files)
            fprintf(fid,'\n');
        elseif iscell(files)
            fprintf(fid,'    %s\n',files{:});
        else
            fprintf(fid,'    %s\n',files);
        end
    end

    function writeXYZ(label,suffix,values)
        fprintf(fid,'  %s\n',label);
        axesNames = 'XYZ';
        for k = 1:3
            fprintf(fid,'    %c%s:\n      %s\n',axesNames(k),suffix,values{k});
        end
    end
end
