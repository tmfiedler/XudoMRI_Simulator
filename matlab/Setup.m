function readPreview = Setup

%SETUP Prepare, inspect, and run a Bloch-simulator protocol.
%   SETUP builds the main GUI programmatically. Its nested callbacks share this
%   function workspace, including inputCmd, Tx/Rx state, cached geometry, and
%   sequence state. Callback groups appear below in workflow order:
%   protocol files, input selection, geometry display, imaging controls,
%   sequence generation/preview, engine launch, then local helper functions.
%   READPREVIEW = SETUP returns a reader for this window's preview waveform.
%
%   See docs/ARCHITECTURE.md before extracting callbacks: moving a nested
%   function without its captured state can silently change GUI behavior.

% Clear screen.
clc;

matlabRoot = fileparts(mfilename('fullpath'));
repositoryRoot = fileparts(matlabRoot);
protocolRoot = fullfile(repositoryRoot,'protocols');
engineRoot = fullfile(repositoryRoot,'engine','bin');

initializeSimulatorPaths(true);

%% Repository paths, shared state, and GUI construction
% The interface retains its historical fixed-pixel layout. temp001 and temp002
% below are mutable x/y layout cursors; they do not hold simulation data.
temp01 = 1040;
temp02 = 590;
hGap = 4;
vGap = 25;
leftPanelX = .01;
leftPanelW = .48;
rightPanelX = .50;
rightPanelW = .49;
rightControlX = .51*temp01;
rightFieldX = .515*temp01;

% % Global variables.
global fileAddr;

% Set default file path.
addr = matlabRoot;

% Set file selection path
fileAddr = matlabRoot;

% Create folder 'Protocols' if it does not exist.
if exist(protocolRoot,'dir')~=7
    mkdir(protocolRoot);
end;

% % Init Main.
hMain = figure('Visible','on','MenuBar','none','Name','XudoMRI',...
    'NumberTitle','off','Position',[100,100,temp01,temp02],'Resize','off',...
    'Toolbar','none','Color',[1,1,1],...
    'DefaultUicontrolFontUnits','pixels','DefaultUicontrolFontSize',11,...
    'DefaultUipanelFontUnits','pixels','DefaultUipanelFontSize',12);
movegui(hMain,'center'); 
defaultFigureName = get(hMain,'Name');
busyState.depth = 0;
enqueueActive = false;
enqueueBusy = false;
 
% Display the supplied NYU artwork without its transparent outer padding.
[nyuLogo,nyuMap,nyuAlpha] = imread(fullfile(matlabRoot,'assets','NYU-Logo.png'));
if ~isempty(nyuMap)
    nyuLogo = ind2rgb(nyuLogo,nyuMap);
end
[nyuRows,nyuColumns] = find(nyuAlpha>0);
nyuRows = min(nyuRows):max(nyuRows);
nyuColumns = min(nyuColumns):max(nyuColumns);
nyuWidth = 63*numel(nyuColumns)/numel(nyuRows);
% Retain the accepted common text center after the small DKFZ adjustment.
headerCenterX = (62+nyuWidth+384)/2;
hNyuAxes = axes('Parent',hMain,'Units','pixels',...
    'Position',[62 520 nyuWidth 63]);
hNyuImage = image(hNyuAxes,nyuLogo(nyuRows,nyuColumns,:));
set(hNyuImage,'AlphaData',im2double(nyuAlpha(nyuRows,nyuColumns)));
axis(hNyuAxes,'image','off');
set(hNyuAxes,'Tag','NYULogo');
uicontrol(hMain,'Style','text','String','XudoMRI',...
    'Position',[headerCenterX-136 537 272 52],'BackgroundColor','white',...
    'ForegroundColor',[0 38 93]/255,'HorizontalAlignment','center',...
    'FontUnits','pixels','FontSize',42,'FontWeight','bold','Tag','SimulatorTitle');
uicontrol(hMain,'Style','text','String','MRI Simulator',...
    'Position',[headerCenterX-110 503 220 40],'BackgroundColor','white',...
    'ForegroundColor',[1 165/255 0],'HorizontalAlignment','center',...
    'FontUnits','pixels','FontName','Times New Roman','FontSize',26,...
    'FontWeight','bold','Tag','MRISimulatorSubtitle');
clear nyuLogo nyuMap nyuAlpha nyuRows nyuColumns nyuWidth headerCenterX hNyuAxes hNyuImage;

% Display the DKFZ logo beside the simulator title.
[dkfzLogo,~,dkfzAlpha] = imread(fullfile(matlabRoot,'assets','DKFZ_logo.png'));
hDkfzAxes = axes('Parent',hMain,'Units','pixels',...
    'Position',[378 533 112 41],...
    'Color','white');
hDkfzImage = image(hDkfzAxes,dkfzLogo);
set(hDkfzAxes,'Tag','DKFZLogo');
if ~isempty(dkfzAlpha)
    set(hDkfzImage,'AlphaData',double(dkfzAlpha)/double(intmax(class(dkfzAlpha))));
end
axis(hDkfzAxes,'image','off');
clear dkfzLogo dkfzAlpha hDkfzAxes hDkfzImage;

% % Display the GeoPanel.
hGeoPanel = uipanel(hMain,'Title','Geometry Editor','BackgroundColor','white',...
    'Position',[rightPanelX .01 rightPanelW .98],'FontWeight','bold','FontSize',10);
geometryAxisPixels = 208;
geometryRightX = .5046;
geometryBottomY = .0663;
hImages.hAxlImage = axes('Parent',hGeoPanel,'Units','normalized',...
    'Position',[geometryRightX geometryBottomY+.4755 geometryAxisPixels/436 geometryAxisPixels/490]);
hImages.hSagImage = axes('Parent',hGeoPanel,'Units','normalized',...
    'Position',[.0206 geometryBottomY geometryAxisPixels/436 geometryAxisPixels/490]);
hImages.hCrlImage = axes('Parent',hGeoPanel,'Units','normalized',...
    'Position',[geometryRightX geometryBottomY geometryAxisPixels/436 geometryAxisPixels/490]);
clear geometryAxisPixels geometryRightX geometryBottomY;

hImages = initializeGeometryPanels(hImages,hGeoPanel,true);

% Keep the GUI version synchronized with the repository-wide identifier.
simulatorVersion = readRepositoryVersion(fullfile(repositoryRoot,'VERSION'));
uicontrol(hGeoPanel,'Style','text','String',['v' simulatorVersion],...
    'Units','normalized','Position',[.60 .004 .38 .024],...
    'HorizontalAlignment','right','FontUnits','pixels','FontSize',10,...
    'ForegroundColor',[.4 .4 .4],'BackgroundColor','white',...
    'Tag','SimulatorVersion');
clear simulatorVersion;

global inputCmd;

% % % Save FileName Addresses.
inputCmd = initializeInputCmd();
cachedTissueDisplayFile = '';
cachedTissueDisplayStamp = [];
cachedTissueDisplayData = [];
activeRunDir = '';
activeRunStudy = '';
sequenceState = struct('previewWaveform', [], 'isDirty', false, ...
    'radialRestorationPending', false);
readPreview = @readSequencePreview;
noiseLoading = struct('Mode','Full','Bounds',[],'Note','');

global Tx Rx;

Tx.Num = 1;
Tx.MagMat = ones(Tx.Num,1);
Tx.PhsMat = zeros(Tx.Num,1);
Tx.RefB1 = NaN;

Rx.Num = 1;

% % % Display DisplayMenu.
uicontrol(hMain,'Style','text','String','Display',...
    'Position',[rightControlX .915*temp02 38 13],'BackgroundColor',[1,1,1]);
hDisplayMenu = uicontrol(hMain,'Style','popupmenu','String',{'ID','T1','T2','Conc. (mol/L)','Chemical Shift','Conductivity','Mass Density'},...
    'Position',[rightControlX+38 .915*temp02-3 92 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@DisplayMenu_Callback,''});

% % % Display ScaleMenu.
uicontrol(hMain,'Style','text','String','Scale',...
    'Position',[rightControlX+38+100 .915*temp02 35 13],'BackgroundColor',[1,1,1]);
hScaleMenu = uicontrol(hMain,'Style','popupmenu','String',{'Linear';'Log'},...
    'Position',[rightControlX+38+100+35 .915*temp02-3 55 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@ScaleMenu_Callback,''});

temp001 = rightControlX; temp002 = .915*temp02-vGap;
% % % Display OrientationMenu.
uicontrol(hMain,'Style','text','String','Slice Orientation',...
    'Position',[temp001 temp002 88 13],'BackgroundColor',[1,1,1]);
temp001 = temp001+88; temp002 = .915*temp02-vGap-3;
hOrientationMenu = uicontrol(hMain,'Style','popupmenu',...
    'String',{'Axial';'Sagittal';'Coronal'},'Value',1,...
    'Position',[temp001 temp002 82 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@OrientationMenu_Callback,''});
temp001 = temp001+82+hGap; temp002 = .915*temp02-vGap-3;
% % % Display Match button.
hMatch=uicontrol(hMain,'Style','pushbutton','string','Match',...
    'Position',[temp001 temp002 52 13+7],...
    'BackgroundColor',[1,1,1],'TooltipString','Fit the signal box to the FOV with two voxels of padding per side.', ...
    'Callback',{@Match_Callback,''});

temp001 = rightControlX; temp002 = temp002-vGap+3;
% % % Display GeoSliderTH.
uicontrol(hMain,'Style','text','String','Slice Thick.',...
    'Position',[temp001 temp002 67 13],'BackgroundColor',[1,1,1]);
temp001 = temp001+67; temp002 = temp002-3;
hGeoSliceTH = uicontrol(hMain,'Style','edit','String','0',...
    'Position',[temp001 temp002 25 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@GeoSliceTHEdit_Callback,''});

% % % Display the FOV popup.
temp001 = temp001+25+hGap; temp002 = temp002+3;
hFOV_Pop = uicontrol(hMain,'Style','popup','string','FOV FE|PE (mm)',...
    'Position',[temp001 temp002 118 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@FOV_Pop_Callback,''});

% % % Display the FOV edit.
temp001 = temp001+118+hGap; temp002 = temp002-3;
hFOV = uicontrol(hMain,'Style','edit','String','300',...
    'Position',[temp001 temp002-1 30 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@FOV_Callback,''});

temp001 = rightControlX; temp002 = temp002-vGap+6;
% % % Display SlicePosition.
uicontrol(hMain,'Style','text','String','Slice Position',...
    'Position',[temp001 temp002 68 13],'BackgroundColor',[1,1,1]);

temp001 = rightControlX; temp002 = temp002-vGap;
% % % Display GeoSlider.
hGeoSlider = uicontrol(hMain,'Style','slider','Max',100,'Min',0,...
    'Value',0,'SliderStep',[1/100,10/100],...
    'Position',[temp001 temp002 180 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@GeoSlider_Callback,''});

temp001 = temp001+180+2;
% % % Display GeoSliderEdit.
hGeoSliderEdit = uicontrol(hMain,'Style','edit',...
    'String','0','Position',[temp001 temp002 25 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@GeoSliderEdit_Callback,''});

temp001 = rightFieldX+hGap+5; temp002 = 372.5/500*temp02-vGap;
% % % Display texts.
uicontrol(hMain,'Style','text','String','Sample',...
    'Position',[temp001 temp002 35 13],...
    'BackgroundColor',[1,1,1]);
temp001 = temp001+35+5;
uicontrol(hMain,'Style','text','String','Sample',...
    'Position',[temp001 temp002 35 13],...
    'BackgroundColor',[1,1,1]);
temp001 = temp001+35+5;
uicontrol(hMain,'Style','text','String','Grad.',...
    'Position',[temp001 temp002 35 13],...
    'BackgroundColor',[1,1,1]);
temp001 = temp001+35+5;
uicontrol(hMain,'Style','text','String','FOV',...
    'Position',[temp001 temp002 35 13],...
    'BackgroundColor',[1,1,1]);
temp001 = temp001+35+5;
uicontrol(hMain,'Style','text','String','Model',...
    'Position',[temp001 temp002 35 13],...
    'BackgroundColor',[1,1,1]);
temp001 = rightFieldX+hGap+5; temp002 = temp002-14;
uicontrol(hMain,'Style','text','String','Min',...
    'Position',[temp001 temp002 35 13],...
    'BackgroundColor',[1,1,1]);
temp001 = temp001+35+5;
uicontrol(hMain,'Style','text','String','Max',...
    'Position',[temp001 temp002 35 13],...
    'BackgroundColor',[1,1,1]);
temp001 = temp001+35+5;
uicontrol(hMain,'Style','text','String','IsoCtr',...
    'Position',[temp001 temp002 35 13],...
    'BackgroundColor',[1,1,1]);
temp001 = temp001+35+5;
uicontrol(hMain,'Style','text','String','Offset',...
    'Position',[temp001 temp002 35 13],...
    'BackgroundColor',[1,1,1]);
temp001 = temp001+35+5;
uicontrol(hMain,'Style','text','String','Res.',...
    'Position',[temp001 temp002 35 13],...
    'BackgroundColor',[1,1,1]);
temp001 = rightFieldX-5; temp002 = temp002-vGap+3;
uicontrol(hMain,'Style','text','String','X',...
    'Position',[temp001 temp002 10 13],'BackgroundColor',[1,1,1]);
temp002 = temp002-vGap;
uicontrol(hMain,'Style','text','String','Y',...
    'Position',[temp001 temp002 10 13],'BackgroundColor',[1,1,1]);
temp002 = temp002-vGap;
uicontrol(hMain,'Style','text','String','Z',...
    'Position',[temp001 temp002 10 13],'BackgroundColor',[1,1,1]);

temp001 = rightFieldX+8; temp002 = 372.5/500*temp02-vGap*3+9;
% % % Display Min,Max,Ctr,Wid edits.
hXMin = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@XMin_Callback,''});
temp001 = temp001+35+5;
hXMax = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@XMax_Callback,''});
temp001 = temp001+35+5;
hXCtr = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@XCtr_Callback,''});
temp001 = temp001+35+5;
hXSet = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@XSet_Callback,''});
temp001 = temp001+35+5;
hXWid = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@XWid_Callback});
temp001 = rightFieldX+8; temp002 = temp002-vGap;
hYMin = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@YMin_Callback,''});
temp001 = temp001+35+5;
hYMax = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@YMax_Callback,''});
temp001 = temp001+35+5;
hYCtr = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@YCtr_Callback,''});
temp001 = temp001+35+5;
hYSet = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@YSet_Callback,''});
temp001 = temp001+35+5;
hYWid = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@YWid_Callback});
temp001 = rightFieldX+8; temp002 = temp002-vGap;
hZMin = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@ZMin_Callback,''});
temp001 = temp001+35+5;
hZMax = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@ZMax_Callback,''});
temp001 = temp001+35+5;
hZCtr = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@ZCtr_Callback,''});
temp001 = temp001+35+5;
hZSet = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@ZSet_Callback,''});
temp001 = temp001+35+5;
hZWid = uicontrol(hMain,'Style','edit','Enable','Inactive',...
    'Position',[temp001 temp002 35 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@ZWid_Callback});

% % Display the StudyPanel.
uipanel(hMain,'Title','Study','BackgroundColor','white',...
    'Position',[leftPanelX .78 leftPanelW .08],'FontWeight','bold','FontSize',10);

temp001 = .018*temp01;
% % % Display the StudyNameText.
uicontrol(hMain,'Style','text','string','Name',...
    'Position',[temp001 .80*temp02 35 13],'BackgroundColor',[1,1,1]);

% % % Display the StudyName.
hStudyName = uicontrol(hMain,'Style','edit','Enable','inactive',...
    'Position',[temp001+35 .80*temp02-3 260 13+6],...
    'BackgroundColor',[1,1,1]);

% % % Display the New button.
hNew = uicontrol(hMain,'Style','pushbutton','String','New',...
    'Position',[temp001+35+260+2 .80*temp02-3 35 13+6],...
    'BusyAction','cancel','Callback',{@StudyNew_Callback,''}); %#ok<NASGU>

% % % Display the Load button.
hLoad = uicontrol(hMain,'Style','pushbutton','String','Load',...
    'Position',[temp001+35+260+2+(35+2)*1 .80*temp02-3 35 13+6],...
    'BusyAction','cancel','Callback',{@StudyLoad_Callback}); %#ok<NASGU>

% % % Display the Save button.
hSave = uicontrol(hMain,'Style','pushbutton','String','Save',...
    'Position',[temp001+35+260+2+(35+2)*2 .80*temp02-3 35 13+6],...
    'BusyAction','cancel','Callback',{@StudySave_Callback,''});

% % % Display the Reset button.
hReset = uicontrol(hMain,'Style','pushbutton','String','Reset',...
    'Position',[temp001+35+260+2+(35+2)*3 .80*temp02-3 38 13+6],...
    'BusyAction','cancel','Callback',{@StudyReset_Callback});

% % Display the InputFilenamesPanel.
uipanel(hMain,'Title','Input Files','BackgroundColor','white',...
    'Position',[leftPanelX .32 leftPanelW .46],'FontWeight','bold','FontSize',10);
inputPanelRight = (leftPanelX + leftPanelW - .009) * temp01;

temp001 = .019*temp01; temp002 = .716*temp02;
% % % Display the Geometry button.
hExpGeo = uicontrol(hMain,'Style','pushbutton',...
    'string','Geometry','Position',[temp001 temp002 60 13+6],...
    'BusyAction','cancel','Callback',{@ExpGeometry_Callback,''});

temp001 = temp001 + (60+2);
% % % Display the GeoName.
hExpGeoEdit = uicontrol(hMain,'Style','edit','Enable','inactive',...
    'string','Geo Filename','FontAngle','italic',...
    'Position',[temp001 temp002 150 13+6],...
    'BackgroundColor',[1,1,1]);

temp001 = temp001 + (150+2);
% % % Display the Tissue button.
hExpTiss = uicontrol(hMain,'Style','pushbutton',...
    'string','Tissue',...
    'Position',[temp001 temp002 50 13+6],...
    'BusyAction','cancel','Callback',{@ExpTissue_Callback,''});

temp001 = temp001 + (50+2);
% % % Display the TissName.
hExpTissEdit = uicontrol(hMain,'Style','edit','Enable','inactive',...
    'string','Tiss Filename','FontAngle','italic',...
    'Position',[temp001 temp002 inputPanelRight-temp001 13+6],...
    'BackgroundColor',[1,1,1]);

temp001 = .019*temp01; temp002 = temp002-vGap+3;
% % % Display the #Tx text.
uicontrol(hMain,'Style','text','string','#Tx',...
    'Position',[temp001 temp002 20 13],...
    'BackgroundColor',[1,1,1]);

% % % Display the #Tx edit.
temp001=temp001+20+hGap; temp002 = temp002-3;
hTx = uicontrol(hMain,'Style','edit','String','1',...
    'Position',[temp001 temp002 20 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@hTx_Callback,''});

% % % Display the #Rx text.
temp001 = temp001+20+hGap; temp002 = temp002+3;
uicontrol(hMain,'Style','text','string','#Rx',...
    'Position',[temp001 temp002 20 13],...
    'BackgroundColor',[1,1,1]);

% % % Display the #Rx edit.
temp001=temp001+20+hGap; temp002 = temp002-3;
hRx = uicontrol(hMain,'Style','edit','String','1',...
    'Position',[temp001 temp002 20 13+6],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@hRx_Callback,''});

temp001=temp001+25+hGap;
% % % Display the Seq button.
hExpSeq = uicontrol(hMain,'Style','pushbutton','string','Pulse Seq',...
    'Position',[temp001 temp002 60 13+6],...
    'BusyAction','cancel','Callback',{@ExpSeq_Callback,''});

temp001 = temp001+(60+2);
% % % Display the seqEdit.
hExpSeqEdit = uicontrol(hMain,'Style','edit','string','Use setup or Seq Filename',...
    'Position',[temp001 temp002 inputPanelRight-temp001 13+6],'FontAngle','italic',...
    'Enable','inactive','BackgroundColor',[1,1,1]);

temp001 = .019*temp01; temp002 = temp002-vGap;
% % % Display the dB0 button.
hExpDB0 = uicontrol(hMain,'Style','pushbutton','string','dB0',...
    'Position',[temp001 temp002 30 13+6],...
    'BusyAction','cancel','Callback',{@ExpDB0_Callback,''});

temp001 = temp001+(30+2);
% % % Display the dB0Edit.
hExpDB0Edit = uicontrol(hMain,'Style','edit','string','0 or dB0 Filename',...
    'Position',[temp001 temp002 inputPanelRight-temp001 13+6],'FontAngle','italic',...
    'Enable','inactive','BackgroundColor',[1,1,1]);

temp001 = .019*temp01; temp002 = temp002-vGap;
% % % Display the B1p button.
hExpB1p = uicontrol(hMain,'Style','pushbutton','string','B1+',...
    'Position',[temp001 temp002 30 13+6],...
    'BusyAction','cancel','Callback',{@ExpB1p_Callback,''});

temp001 = .019*temp01+30+2;
% % % Display the B1pEdit.
hExpB1pEdit = uicontrol(hMain,'Style','edit','string','Homogeneous or B1+ Filename(s)',...
    'Position',[temp001 temp002 inputPanelRight-temp001 13+6],'FontAngle','italic',...
    'Enable','inactive','BackgroundColor',[1,1,1]);

temp001 = .019*temp01; temp002 = temp002-vGap;
% % % Display the E1p button.
hExpE1p = uicontrol(hMain,'Style','pushbutton','string','E1+',...
    'Position',[temp001 temp002 30 13+6],...
    'BusyAction','cancel','Callback',{@ExpE1p_Callback,''});

temp001 = temp001 + (30+2);
% % % Display the E1pEdit.
hExpE1pEdit = uicontrol(hMain,'Style','edit','string','E1+ Filename(s)',...
    'Position',[temp001 temp002 inputPanelRight-temp001 13+6],'FontAngle','italic',...
    'Enable','inactive','BackgroundColor',[1,1,1]);

temp001 = .019*temp01; temp002 = temp002-vGap;
% % % Display the B1m button.
hExpB1m = uicontrol(hMain,'Style','pushbutton','string','B1-',...
    'Position',[temp001 temp002 30 13+6],...
    'BusyAction','cancel','Callback',{@ExpB1m_Callback,''});

temp001 = temp001+(30+2);
% % % Display the B1mEdit.
hExpB1mEdit = uicontrol(hMain,'Style','edit','string','Homogeneous or B1- Filename(s)',...
    'Position',[temp001 temp002 inputPanelRight-temp001 13+6],'FontAngle','italic',...
    'Enable','inactive','BackgroundColor',[1,1,1]);

temp001 = .019*temp01; temp002 = temp002-vGap;
% % % Display the E1m button.
hExpE1m = uicontrol(hMain,'Style','pushbutton','string','E1-',...
    'Position',[temp001 temp002 30 13+6],...
    'BusyAction','cancel','Callback',{@ExpE1m_Callback,''});

temp001 = temp001+(30+2);
% % % Display the E1mEdit.
hExpE1mEdit = uicontrol(hMain,'Style','edit','string','E1- Filename(s)',...
    'Position',[temp001 temp002 inputPanelRight-temp001-134 13+6],'FontAngle','italic',...
    'Enable','inactive','BackgroundColor',[1,1,1]);
hNoiseLoading = uicontrol(hMain,'Style','pushbutton','String','Noise: Full sample',...
    'Position',[inputPanelRight-130 temp002 130 13+6],'Enable','off',...
    'Tag','NoiseLoading','BusyAction','cancel','Callback',@NoiseLoading_Callback);

temp001 = .019*temp01; temp002 = temp002-vGap;
% % % Display the Gx button.
hExpGx = uicontrol(hMain,'Style','pushbutton','string','Gx',...
    'Position',[temp001 temp002 25 13+6],...
    'BusyAction','cancel','Callback',{@ExpGx_Callback,''});

temp001 = temp001+(25+2);
% % % Display the GxEdit.
hExpGxEdit = uicontrol(hMain,'Style','edit','string','Gx Filename',...
    'Position',[temp001 temp002 inputPanelRight-temp001 13+6],'FontAngle','italic',...
    'Enable','inactive','BackgroundColor',[1,1,1]);

temp001 = .019*temp01; temp002 = temp002-vGap;
% % % Display the Gy button.
hExpGy = uicontrol(hMain,'Style','pushbutton','string','Gy',...
    'Position',[temp001 temp002 25 13+6],...
    'BusyAction','cancel','Callback',{@ExpGy_Callback,''});

temp001 = temp001+(25+2);
% % % Display the GyEdit.
hExpGyEdit = uicontrol(hMain,'Style','edit','string','Gy Filename',...
    'Position',[temp001 temp002 inputPanelRight-temp001 13+6],'FontAngle','italic',...
    'BusyAction','cancel','Enable','inactive','BackgroundColor',[1,1,1]);

temp001 = .019*temp01; temp002 = temp002-vGap;
% % % Display the Gz button.
hExpGz = uicontrol(hMain,'Style','pushbutton','string','Gz',...
    'Position',[temp001 temp002 25 13+6],...
    'BusyAction','cancel','Callback',{@ExpGz_Callback,''});

temp001 = temp001+(25+2);
% % % Display the GzEdit.
hExpGzEdit = uicontrol(hMain,'Style','edit','string','Gz Filename',...
    'Position',[temp001 temp002 inputPanelRight-temp001 13+6],'FontAngle','italic',...
    'Enable','inactive','BackgroundColor',[1,1,1]);

% % Display the ImagingPanel.
uipanel(hMain,'Title','Imaging Setup',...
    'BackgroundColor','white','Position',[leftPanelX .062 leftPanelW .255],...
    'FontWeight','bold','FontSize',10);

temp001 = .02*temp01; temp002 = .255*temp02;
% % % Display the B0Text.
hB0Label = uicontrol(hMain,'Style','text','string','B0(T)',...
    'Position',[temp001 temp002 32 13],...
    'BackgroundColor',[1,1,1]);

temp001 = temp001+(32+2); temp002 = temp002-3;
% % % Display the B0Edit.
hB0Edit = uicontrol(hMain,'Style','edit','string','3',...
    'Position',[temp001 temp002 25 13+6],...
    'BackgroundColor',[1,1,1],'Callback',{@B0Edit_Callback,''});

temp001 = temp001+(25+6); temp002 = .255*temp02;
% % % Display the Nucleus text.
hNucleusLabel = uicontrol(hMain,'Style','text','string','Nuc.',...
    'Position',[temp001 temp002 26 13],...
    'BackgroundColor',[1,1,1]);

temp001 = temp001+26; temp002 = temp002-3;
% % % Display the Nucleus menu.
nucleusDefinitions = getNucleusDefinition();
hNucleus = uicontrol(hMain,'Style','popupmenu',...
    'String',{nucleusDefinitions.name},'Value',1,...
    'Position',[temp001 temp002 60 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@Nucleus_Callback,''});

temp001 = temp001+(60+4); temp002 = .255*temp02;
% % % Display the SequenceType text.
uicontrol(hMain,'Style','text','string','Seq.',...
    'Position',[temp001 temp002 30 13],...
    'BackgroundColor',[1,1,1]);

temp001 = temp001+30; temp002 = temp002-3;
% % % Display the SequenceType menu.
% tempCell = what('Sequences');
% for tempN = 1:length(tempCell.m) %#ok<FXUP>
%     tempM = find(tempCell.m{tempN}=='.',1,'last');
%     tempCell.m{tempN} = tempCell.m{tempN}(1:(tempM-1));
% end;
% hSeqType = uicontrol(hMain,'Style','popupmenu',...
%     'String',tempCell.m,'Value',1,...
%     'Position',[temp001 temp002 60 13+7],...
%     'BackgroundColor',[1,1,1],'BusyAction','cancel',...
%     'Callback',{@SeqType_Callback,''});

tempCell = SeqInterfaceIn;
hSeqType = uicontrol(hMain,'Style','popupmenu',...
    'String',tempCell,'Value',1,...
    'Position',[temp001 temp002 75 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@SeqType_Callback,''});
cd(addr);

clear tempN tempM tempCell;

temp001 = temp001+hGap*2+75; temp002 = temp002+3;
% % % Display the RFShape text.
uicontrol(hMain,'Style','text','string','RF Shape',...
    'Position',[temp001 temp002 50 13],...
    'BackgroundColor',[1,1,1]);

% % % Display the RF_Shape menu.
temp001 = temp001+50; temp002 = temp002-3;
hRF_Shape = uicontrol(hMain,'Style','popupmenu',...
    'String',{'Sinc';'Rect';'Gauss'},'Value',1,...
    'Position',[temp001 temp002 65 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@RF_Shape_Callback,''});

% % % Display the RF_FA text.
temp001 = temp001+65+hGap; temp002 = temp002+3;
uicontrol(hMain,'Style','text','string','RF FA',...
    'Position',[temp001 temp002 40 13],...
    'BackgroundColor',[1,1,1]);

% % % Display the RF_FA edit.
temp001 = temp001+40+hGap; temp002 = temp002-3;
hRF_FA = uicontrol(hMain,'Style','edit',...
    'String','90',...
    'Position',[temp001 temp002 30 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@RF_FA_Callback,''});

% % % Display the RF_Duration text.
temp001 = .02*temp01; temp002 = temp002-vGap+1;
uicontrol(hMain,'Style','text','string','RF Pulse Dur. (ms)',...
    'Position',[temp001 temp002 102 13],...
    'BackgroundColor',[1,1,1]);

% % % Display the RF_Duration edit.
temp001 = temp001+hGap+102; temp002 = temp002-3;
hRF_Duration = uicontrol(hMain,'Style','edit',...
    'String','2.6',...
    'Position',[temp001 temp002 36 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@RF_Duration_Callback,''});

% % % Display the RF# text.
temp001 = temp001+30+36; temp002 = temp002+3;
uicontrol(hMain,'Style','text','string','# Pts in RF Pulse',...
    'Position',[temp001 temp002 95 13],...
    'BackgroundColor',[1,1,1]);

% % % Display the RF# edit.
temp001 = temp001+95+hGap; temp002 = temp002-3;
hRF_Num = uicontrol(hMain,'Style','edit',...
    'String','512',...
    'Position',[temp001 temp002 36 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@RF_Num_Callback,''});

% % % Display the target B1+ text.
temp001 = temp001+30+36; temp002 = temp002+3;
b1Tip = ['Editing RF FA sets target B1+ for the current pulse shape and duration. ', ...
    'With a calibrated target, changing pulse duration updates the displayed FA. ', ...
    'Leave blank to use the shim B1+ from Tx Array.'];
uicontrol(hMain,'Style','text','string','B1+ (uT)','TooltipString',b1Tip,...
    'Position',[temp001 temp002 52 13],...
    'BackgroundColor',[1,1,1]);

% % % Display the target B1+ edit.
temp001 = temp001+52+hGap; temp002 = temp002-3;
hTargetB1 = uicontrol(hMain,'Style','edit',...
    'String','',...
    'Position',[temp001 temp002 32 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel','Enable','off',...
    'TooltipString',b1Tip,...
    'Callback',{@TargetB1_Callback,''});

% % % Display the TI text.
temp001 = .02*temp01; temp002 = temp002+3-vGap-1;
hTILabel = uicontrol(hMain,'Style','text','string','TI(ms)',...
    'Position',[temp001 temp002 34 13],...
    'BackgroundColor',[1,1,1],'Enable','off');

% % % Display the TI edit.
temp001 = temp001+hGap+34; temp002 = temp002-3;
hTI = uicontrol(hMain,'Style','edit',...
    'String','10',...
    'Position',[temp001 temp002 30 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel','Enable','off',...
    'Callback',{@TI_Duration_Callback,''});

% % % Display the MatSize popup.
temp001 = temp001+30+24; temp002 = temp002+2;
hMatSize_Pop = uicontrol(hMain,'Style','popup','string','MatSize FE|PE',...
    'Position',[temp001 temp002 118 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@MatSize_Pop_Callback,''});

% % % Display the MatSize edit.
temp001 = temp001+118+hGap; temp002 = temp002-3;
hMatSize = uicontrol(hMain,'Style','edit','value',[128,128],...
    'Position',[temp001 temp002 40 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@MatSize_Callback,''});

% % % Display the ADC_Freq text.
temp001 = temp001+26+40; temp002 = temp002+3;
hADCLabel = uicontrol(hMain,'Style','text','string','Rcvr BW (kHz)',...
    'Position',[temp001 temp002 92 13],...
    'BackgroundColor',[1,1,1]);

% % % Display the ADC_Freq edit.
temp001=temp001+92; temp002 = temp002-3;
hADC_Freq = uicontrol(hMain,'Style','edit','String','50',...
    'Position',[temp001 temp002 36 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@ADC_Freq_Callback,''});

temp001=.02*temp01; temp002 = temp002-vGap+3;
% % % Display the Gradient ON text.
uicontrol(hMain,'Style','text','string','Gradient ON',...
    'Position',[temp001 temp002 78 13],...
    'BackgroundColor',[1,1,1]);

temp001=temp001+78+hGap;
% % % Display the SS checkbox.
hSS=uicontrol(hMain,'Style','checkbox','string','SS','Value',1,...
    'Position',[temp001 temp002 38 13],...
    'BackgroundColor',[1,1,1],'Callback',{@SS_Callback,''});

temp001=temp001+38;
% % % Display the PE checkbox.
hPE=uicontrol(hMain,'Style','checkbox','string','PE','Value',1,...
    'Position',[temp001 temp002 38 13],...
    'BackgroundColor',[1,1,1],'Callback',{@PE_Callback,''});

temp001=temp001+38;
% % % Display the FE checkbox.
hFE=uicontrol(hMain,'Style','checkbox','string','FE','Value',1,...
    'Position',[temp001 temp002 38 13],...
    'BackgroundColor',[1,1,1],'Callback',{@FE_Callback,''});

% % % Display the TE text.
temp001=temp001+38+30;
hTELabel = uicontrol(hMain,'Style','text','string','TE (ms)',...
    'Position',[temp001 temp002 42 13],...
    'BackgroundColor',[1,1,1]);

temp001=temp001+42; temp002 = temp002-3;
% % % Display the TE edit.
hTE = uicontrol(hMain,'Style','edit',...
    'String','10',...
    'Position',[temp001 temp002 40 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@TE_Callback,''});

temp001=temp001+40+26; temp002 = temp002+3;
% % % Display the TR text.
hTRLabel = uicontrol(hMain,'Style','text','string','TR (ms)',...
    'Position',[temp001 temp002 42 13],...
    'BackgroundColor',[1,1,1]);

temp001=temp001+42; temp002 = temp002-3;
% % % Display the TR edit.
hTR = uicontrol(hMain,'Style','edit','String','500',...
    'Position',[temp001 temp002 45 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@TR_Callback,''});

% % % Display the #DummyTR text.
temp001=.02*temp01; temp002 = temp002-vGap+3;
uicontrol(hMain,'Style','text','string','#Dummy TRs',...
    'Position',[temp001 temp002 74 13],...
    'BackgroundColor',[1,1,1]);

% % % Display the DummyNum edit.
temp001 = temp001+74; temp002 = temp002-3;
hDummyNum = uicontrol(hMain,'Style','edit',...
    'String','0',...
    'Position',[temp001 temp002 28 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@DummyNum_Callback,''});

% % % Display the PEDirect text.
temp001=temp001+28+8; temp002 = temp002+3;
peDirectionX = temp001;
hPEDirectLabel = uicontrol(hMain,'Style','text','string','PE Direction',...
    'Position',[temp001 temp002 80 13],...
    'BackgroundColor',[1,1,1]);

% % % Display the PEDirect edit.
temp001 = temp001+80+4; temp002 = temp002-3;
hPEDirectMenu = uicontrol(hMain,'Style','popup',...
    'String',{'P--A';'A--P';'L--R';'R--L'},'Value',1,...
    'Position',[temp001 temp002 75 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@PEDirectMenu_Callback,''});

hRadialResolutionLabel = uicontrol(hMain,'Style','text','String','Acq. resolution (mm)',...
    'Position',[peDirectionX temp002+3 116 13],'BackgroundColor',[1,1,1],'Visible','off');
hRadialResolution = uicontrol(hMain,'Style','edit','String','','UserData','',...
    'Position',[peDirectionX+116 temp002 43 20],'BackgroundColor',[1,1,1],'Visible','off',...
    'Tag','RadialAcquisitionResolution','Callback',@radialResolutionCallback);

temp001=.345*temp01; temp002 = temp002-2;
% % %  Display the Gen. Seq. button.
hSeqGen = uicontrol(hMain,'Style','pushbutton','String','Gen. Seq.',...
    'Position',[temp001 temp002 65 19],'BusyAction','cancel',...
    'Callback',{@SeqGen_Callback}); % on to change to on.

global hSeqPlot;
temp001=temp001+67;
% % % Display the Plot Seq. button.
hSeqPlot = uicontrol(hMain,'Style','pushbutton','String','Plot Seq.',...
    'Position',[temp001 temp002 60 19],'BusyAction','cancel',...
    'Callback',{@SeqPlot_Callback});

temp001 = .01*temp01; temp002 = .02*temp02;
% % Display the NumIso text.
uicontrol(hMain,'Style','text','string','NumIso',...
    'Position',[temp001 temp002 40 13],...
    'BackgroundColor',[1,1,1]);

temp001 = temp001+40; temp002 = temp002-3;
% % Display the NumIso edit.
hNumIso = uicontrol(hMain,'Style','edit','String','1',...
    'Position',[temp001 temp002 20 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@NumIso_Callback,''});

temp001 = temp001+20; temp002 = temp002+3;
% % Display the CPU text.
uicontrol(hMain,'Style','text','string','CPU(s)',...
    'Position',[temp001 temp002 40 13],...
    'BackgroundColor',[1,1,1]);

temp001 = temp001+40; temp002 = temp002-3;
% % Display the CPU edit.
hCPU = uicontrol(hMain,'Style','edit','String','1',...
    'Position',[temp001 temp002 20 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@CPU_Callback,''});

temp001 = temp001+20+hGap; temp002 = .02*temp02;
% % Display the NEX text.
uicontrol(hMain,'Style','text','string','NEX',...
    'Position',[temp001 temp002 28 13],...
    'BackgroundColor',[1,1,1]);

temp001 = temp001+28; temp002 = temp002-3;
% % Display the NEX edit.
hNEX = uicontrol(hMain,'Style','edit','String','1',...
    'Position',[temp001 temp002 25 13+7],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@NEX_Callback,''});

temp001 = temp001+25+hGap; temp002 = .02*temp02;
% % Display the Mode text.
uicontrol(hMain,'Style','text','string','Mode',...
    'Position',[temp001 temp002 40 13],...
    'BackgroundColor',[1,1,1]);

temp001 = temp001+40; temp002 = temp002-3;
% % Display the Mode Menu.
hMode = uicontrol(hMain,'Style','popupmenu',...
    'String',{'Signal';'SAR';'Noise'},'Value',1,...
    'Position',[temp001 temp002 85 13+7.8],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@Mode_Callback,''});

temp001 = temp001+85+4; temp002 = temp002+3;
% % Display the Signal GPU toggle.
hSignalGPU = uicontrol(hMain,'Style','checkbox','string','GPU','Value',0,...
    'Position',[temp001 temp002+0.5 45 13],...
    'BackgroundColor',[1,1,1],'BusyAction','cancel',...
    'Callback',{@SignalGPU_Callback,''});

% %  Display the Fields button.
hFields = uicontrol(hMain,'Style','pushbutton','String','Fields',...
    'Position',[temp001+45+10 .012*temp02 60 25],...
    'FontSize',11,'BackgroundColor',[0.8,0.92,1],...
    'Callback',{@FieldViewer_Callback});

% %  Display the Run button.
hRun = uicontrol(hMain,'Style','pushbutton','String','Run',...
    'Position',[temp001+45+10+65 .012*temp02 60 25],...
    'FontSize',12,'BackgroundColor',[0,1,0],'FontWeight','bold',...
    'Callback',{@Run_Callback});
hJobs = uicontrol(hMain,'Style','pushbutton','String','Jobs',...
    'Position',[temp001+45+10+130 .012*temp02 60 25],'FontSize',10,...
    'Callback',@ShowSignalJobs_Callback); %#ok<NASGU>


% Block accidental clicks while long operations are running.
hBusyOverlay = uipanel(hMain,'Units','pixels','Position',[1 1 temp01 temp02],...
    'BackgroundColor',[0.94,0.94,0.94],'BorderType','none','Visible','off');
hBusyPanel = uipanel(hBusyOverlay,'Title','Please wait','Units','pixels',...
    'Position',[round(temp01/2)-150 round(temp02/2)-35 300 70],...
    'BackgroundColor',[1,1,1]);
hBusyText = uicontrol(hBusyPanel,'Style','text','String','',...
    'Position',[15 12 270 28],'FontWeight','bold',...
    'HorizontalAlignment','center','BackgroundColor',[1,1,1]);

clear temp01 temp02;
clear hGap vGap;

reset();

    %% Protocol lifecycle callbacks
    % --- Executes on StudyNew button.
    function StudyNew_Callback(source,eventdata,flag) %#ok<INUSD,INUSD>
        if strcmp(flag,'')
            prompt={'Enter new protocol name (maximum 30 characters):'};
            title='New Protocol';
            numChar=[1,30];
            newStudy=inputdlg(prompt,title,numChar);

            if isempty(newStudy)
                return;
            end;
            studyName = char(strtrim(newStudy{1}));
        else
            studyName = char(strtrim(flag));
        end;

        validationMessage = validateNewStudyName(studyName);
        if ~isempty(validationMessage)
            errordlg(validationMessage,'New Protocol','modal');
            return;
        end

        studyDir = fullfile(protocolRoot,studyName);
        if exist(studyDir,'dir') ~= 7 && exist(studyDir,'file') == 2
            errordlg(['A file named "',studyName,'" already exists. ',...
                'Choose a different protocol name.'],...
                'New Protocol','modal');
            return;
        end

        if exist(studyDir,'dir') ~= 7
            [created,message] = mkdir(studyDir);
            if ~created
                errordlg(['Unable to create protocol folder: ',message],...
                    'New Protocol','modal');
                return;
            end
        end

        if ~isempty(get(hStudyName,'String'))
            reset();
        end
        set(hStudyName,'String',studyName);
        set(hExpGeo,'Enable','on');
        initializeStudyOutputPaths(studyName);
        logSetup('Created blank protocol "%s" in %s',studyName,studyDir);

        if strcmp(flag,'')
            reformatChoice = questdlg( ...
                ['Blank protocol created in ',studyDir,'. ',...
                 'Start the CST reformatter for this protocol now?'],...
                'New Protocol','Start Reformatter','Not Now','Start Reformatter');
            if strcmp(reformatChoice,'Start Reformatter')
                try
                    reformatter(studyDir);
                    geometryFile = fullfile(studyDir,'geometry.smpl');
                    if exist(geometryFile,'file') == 2
                        ExpGeometry_Callback(source,eventdata,geometryFile);
                    end
                catch reformatError
                    logSetup('Reformatter failed for "%s": %s',studyName,reformatError.message);
                    errordlg(['Reformatter failed: ',reformatError.message],...
                        'Reformatter Error','modal');
                end
            end
        end;
    end

    %% --- Executes on StudyLoad button.
    function StudyLoad_Callback(source,eventdata)
        global geoData;
        global inputInfo;
        global displayInfo;
        
        [fileName,pathName] = uigetfile( ...
            {'*.prot','Protocol File (*.prot)';'*.*','All Files (*.*)'}, ...
            'OPEN: Protocol File',fullfile(protocolRoot,'*.prot'));

        if ~isequal(fileName,0)
            [~,~,extension] = fileparts(fileName);
            if ~strcmpi(extension,'.prot')
                errordlg('Select a protocol file with the .prot extension.','Invalid Protocol File','modal');
                return;
            end
            logSetup('Loading protocol: %s', [pathName,fileName]);
            beginBusyState('Loading protocol...');
            protocolBusyCleanup = onCleanup(@() endBusyState()); %#ok<NASGU>
            reset();
            tempStr = filenameCvrt(fileName);
            set(hStudyName,'String',tempStr);
            if exist([protocolRoot,'\',tempStr,'\'],'file')~=7
                mkdir([protocolRoot,'\',tempStr,'\']);
            end;
            inputCmd{12,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{12,2}=[tempStr,'.ksig']; % KSpace FileName
            inputCmd{13,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{13,2}=[tempStr,'.ktrj']; % KMap FileName
            inputCmd{14,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{14,2}=[tempStr,'.nois']; % Noise FileName
            inputCmd{15,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{15,2}=[tempStr,'.sar'];  % SAR FileName
            
            fileAddr = pathName;
            protocol = readSetupProtocol([pathName,fileName]);
            
            [inputCmd{1,1},inputCmd{1,2}] = resolveProtocolPath(protocol.geometryFilename(),pathName);
            if isempty(inputCmd{1,1})
                set(hExpGeoEdit,'String','Geo Filename');
            else
                ExpGeometry_Callback(source,eventdata,[inputCmd{1,1},inputCmd{1,2}]);
                set(hExpGeo,'Enable','on');
            end;  
            
            tissueFilename = protocol.tissueFilename();
            [inputCmd{2,1},inputCmd{2,2}] = resolveProtocolPath(tissueFilename,pathName);
            if isempty(inputCmd{2,1})
                set(hExpTissEdit,'String','Tiss Filename');
            else
                ExpTissue_Callback(source,eventdata,tissueFilename);
                set(hExpTiss,'Enable','on');
            end;
            
            [inputCmd{3,1},inputCmd{3,2}] = resolveProtocolPath(protocol.deltaB0Filename(),pathName);
            if isempty(inputCmd{3,1})
                set(hExpDB0Edit,'String','0 or dB0 Filename');
            else
                set(hExpDB0Edit,'String',filenameCvrt(inputCmd{3,2}));
                set(hExpDB0Edit,'FontAngle','normal');
            end;

            [inputCmd{4,1},inputCmd{4,2}] = resolveProtocolPath(protocol.sequenceFilename(),pathName);
            if isempty(inputCmd{4,1})
                set(hExpSeqEdit,'String','Use setup or Seq Filename');
                set(hExpSeqEdit,'FontAngle','italic');
            else
                set(hExpSeqEdit,'String',filenameCvrt(inputCmd{4,2}));
                set(hExpSeqEdit,'FontAngle','normal');
            end;

            hTx_Callback(source,eventdata,protocol.txCountText());
            
            Tx.MagMat = ones(Tx.Num,1);
            Tx.PhsMat = zeros(Tx.Num,1);
            Tx.RefB1 = NaN;
            for n=1:Tx.Num
                weights = protocol.txWeight(n);
                Tx.MagMat(n) = weights(1);
                Tx.PhsMat(n) = weights(2);
            end;

            shimB1Text = protocol.shimB1Text();
            if ~isempty(shimB1Text)
                Tx.RefB1 = parseOptionalPositiveScalar(shimB1Text);
            end
            
            coilFiles = protocol.b1PlusFiles();
            if ~iscell(coilFiles)
                [tempStr1,tempStr2] = resolveProtocolPath(coilFiles,pathName);
                if isempty(tempStr2)
                    inputCmd{5,1} = '';
                    inputCmd{5,2} = '';
                    set(hExpB1pEdit,'String','Homogeneous or B1+ Filename(s)');
                else
                    inputCmd{5,1} = {tempStr1};
                    inputCmd{5,2} = {tempStr2};
                    set(hExpB1pEdit,'String',filenameCvrt(tempStr2));
                    set(hExpB1pEdit,'FontAngle','normal');
                end;
            else
                [inputCmd{5,1},inputCmd{5,2}] = resolveProtocolPath(coilFiles,pathName);
                tempStr1 = '';
                for n=1:length(inputCmd{5,2})
                    tempStr1 = [tempStr1,filenameCvrt(inputCmd{5,2}{n}),'; ']; %#ok<AGROW>
                end;
                set(hExpB1pEdit,'String',tempStr1);
                set(hExpB1pEdit,'FontAngle','normal');
            end;
            
            coilFiles = protocol.e1PlusFiles();
            if ~iscell(coilFiles)
                [tempStr1,tempStr2] = resolveProtocolPath(coilFiles,pathName);
                if isempty(tempStr2)
                    inputCmd{6,1} = '';
                    inputCmd{6,2} = '';
                    set(hExpE1pEdit,'String','E1+ Filename(s)');
                else
                    inputCmd{6,1} = {tempStr1};
                    inputCmd{6,2} = {tempStr2};
                    set(hExpE1pEdit,'String',filenameCvrt(tempStr2));
                    set(hExpE1pEdit,'FontAngle','normal');
                end;
            else
                [inputCmd{6,1},inputCmd{6,2}] = resolveProtocolPath(coilFiles,pathName);
                tempStr1 = '';
                for n=1:length(inputCmd{6,2})
                    tempStr1 = [tempStr1,filenameCvrt(inputCmd{6,2}{n}),'; ']; %#ok<AGROW>
                end;
                set(hExpE1pEdit,'String',tempStr1);
                set(hExpE1pEdit,'FontAngle','normal');
            end;

            hRx_Callback(source,eventdata,protocol.rxCountText());
            
            coilFiles = protocol.b1MinusFiles();
            if ~iscell(coilFiles)
                [tempStr1,tempStr2] = resolveProtocolPath(coilFiles,pathName);
                if isempty(tempStr2)
                    inputCmd{7,1} = '';
                    inputCmd{7,2} = '';
                    set(hExpB1mEdit,'String','Homogeneous or B1- Filename(s)');
                else
                    inputCmd{7,1} = {tempStr1};
                    inputCmd{7,2} = {tempStr2};
                    set(hExpB1mEdit,'String',filenameCvrt(inputCmd{7,2}));
                    set(hExpB1mEdit,'FontAngle','normal');
                end;
            else
                [inputCmd{7,1},inputCmd{7,2}] = resolveProtocolPath(coilFiles,pathName);
                tempStr1 = '';
                for n=1:length(inputCmd{7,2})
                    tempStr1 = [tempStr1,filenameCvrt(inputCmd{7,2}{n}),'; ']; %#ok<AGROW>
                end;
                set(hExpB1mEdit,'String',tempStr1);
                set(hExpB1mEdit,'FontAngle','normal');
            end;
            
            coilFiles = protocol.e1MinusFiles();
            if ~iscell(coilFiles)
                [tempStr1,tempStr2] = resolveProtocolPath(coilFiles,pathName);
                if isempty(tempStr2)
                    inputCmd{8,1} = '';
                    inputCmd{8,2} = '';
                    set(hExpE1mEdit,'String','E1- Filename(s)');
                else
                    inputCmd{8,1} = {tempStr1};
                    inputCmd{8,2} = {tempStr2};
                    set(hExpE1mEdit,'String',filenameCvrt(tempStr2));
                    set(hExpE1mEdit,'FontAngle','normal');
                end;
            else
                [inputCmd{8,1},inputCmd{8,2}] = resolveProtocolPath(coilFiles,pathName);
                tempStr1 = '';
                for n=1:length(inputCmd{8,2})
                    tempStr1 = [tempStr1,filenameCvrt(inputCmd{8,2}{n}),'; ']; %#ok<AGROW>
                end;
                set(hExpE1mEdit,'String',tempStr1);
                set(hExpE1mEdit,'FontAngle','normal');
            end;
            
            [inputCmd{9,1},inputCmd{9,2}] = resolveProtocolPath(protocol.gxFilename(),pathName);
            if isempty(inputCmd{9,1})
                set(hExpGxEdit,'String','Gx Filename');
            else
                set(hExpGxEdit,'String',filenameCvrt(inputCmd{9,2}));
                set(hExpGxEdit,'FontAngle','normal');
            end;
            
            [inputCmd{10,1},inputCmd{10,2}] = resolveProtocolPath(protocol.gyFilename(),pathName);
            if isempty(inputCmd{10,1})
                set(hExpGyEdit,'String','Gy Filename');
            else
                set(hExpGyEdit,'String',filenameCvrt(inputCmd{10,2}));
                set(hExpGyEdit,'FontAngle','normal');
            end;
            
            [inputCmd{11,1},inputCmd{11,2}] = resolveProtocolPath(protocol.gzFilename(),pathName);
            if isempty(inputCmd{11,1})
                set(hExpGzEdit,'String','Gz Filename');
            else
                set(hExpGzEdit,'String',filenameCvrt(inputCmd{11,2}));
                set(hExpGzEdit,'FontAngle','normal');
            end;
            
            [inputCmd{12,1},inputCmd{12,2}] = resolveProtocolOutputPath(protocol.kspaceFilename(),pathName);

            [inputCmd{13,1},inputCmd{13,2}] = resolveProtocolOutputPath(protocol.trajectoryFilename(),pathName);
            
            [inputCmd{14,1},inputCmd{14,2}] = resolveProtocolOutputPath(protocol.noiseFilename(),pathName);
            
            [inputCmd{15,1},inputCmd{15,2}] = resolveProtocolOutputPath(protocol.sarFilename(),pathName);

            DisplayMenu_Callback(source,eventdata,protocol.display());

            ScaleMenu_Callback(source,eventdata,protocol.scale());
                      
            OrientationMenu_Callback(source,eventdata,protocol.sliceOrientation());

            tempCell = get(hPEDirectMenu,'String');
            temp = find(strcmp(tempCell,protocol.phaseEncodeDirection()));
            if ~isempty(temp)
                set(hPEDirectMenu,'Value',temp);
            end
            
            GeoSliceTHEdit_Callback(source,eventdata,protocol.sliceThicknessText());
        
            XMin_Callback(source,eventdata,protocol.xMinText());
            YMin_Callback(source,eventdata,protocol.yMinText());
            ZMin_Callback(source,eventdata,protocol.zMinText());
            
            XMax_Callback(source,eventdata,protocol.xMaxText());
            YMax_Callback(source,eventdata,protocol.yMaxText());
            ZMax_Callback(source,eventdata,protocol.zMaxText());
            
            XCtr_Callback(source,eventdata,protocol.xCenterText());
            YCtr_Callback(source,eventdata,protocol.yCenterText());
            ZCtr_Callback(source,eventdata,protocol.zCenterText());
            
            XSet_Callback(source,eventdata,protocol.xOffsetText());
            YSet_Callback(source,eventdata,protocol.yOffsetText());
            ZSet_Callback(source,eventdata,protocol.zOffsetText());
            
            B0Edit_Callback(source,eventdata,protocol.b0Text());
            Nucleus_Callback(source,eventdata,protocol.nucleus());
            SeqType_Callback(source,eventdata,protocol.sequenceType());
            if ~protocol.hasUnifiedFOV || is3DRadSequenceName(getCurrentSequenceName())
                savedPosition = str2double(protocol.slicePositionText());
                if isreal(savedPosition) && isfinite(savedPosition)
                    setSlicePosition(savedPosition);
                end
            end
            syncSlicePosition();
            RF_Shape_Callback(source,eventdata,protocol.rfShape());
            RF_Duration_Callback(source,eventdata,protocol.rfDurationText());
            RF_Num_Callback(source,eventdata,protocol.rfCountText());
            RF_FA_Callback(source,eventdata,protocol.flipAngleText());
            set(hTargetB1,'String',protocol.targetB1Text());
            FOV_Callback(source,eventdata,protocol.fovText());
            MatSize_Callback(source,eventdata,protocol.matrixSizeText());
            ADC_Freq_Callback(source,eventdata,protocol.adcFrequencyText());
            if is3DRadSequenceName(getCurrentSequenceName())
                setRadialResolutionText(protocol.radialResolutionText());
            end
            TI_Duration_Callback(source,eventdata,protocol.inversionTimeText());
            % Legacy protocols may contain a saved Filter state. Match is now
            % an explicit one-shot action, so loading a protocol should not
            % change the saved simulation range.
            
            SS_Callback(source,eventdata,protocol.sliceSelectText());
            PE_Callback(source,eventdata,protocol.phaseEncodeText());
            FE_Callback(source,eventdata,protocol.frequencyEncodeText());

            radialAxesRestored = updateRadialAxisControls();
            sequenceState.radialRestorationPending = radialAxesRestored;
            if radialAxesRestored
                restorationMessage = ['Restored all three RAD_3D axes in memory. ' ...
                    'Regenerate the sequence before saving, running or plotting. ' ...
                    'Existing protocol, sequence and acquired data files have not been changed.'];
                warnSetup('%s',restorationMessage);
                warndlg(restorationMessage,'RAD_3D axes restored');
            end

            DummyNum_Callback(source,eventdata,protocol.dummyCountText());
            
            TE_Callback(source,eventdata,protocol.teText());
            TR_Callback(source,eventdata,protocol.trText());
            
            NumIso_Callback(source,eventdata,protocol.numIsoText());
            
            CPU_Callback(source,eventdata,protocol.cpuCountText());

            SignalGPU_Callback(source,eventdata,protocol.signalEngine());

            NEX_Callback(source,eventdata,protocol.nexText());
            
            noiseLoading = protocol.noiseLoading();
            updateNoiseLoadingButton();

            Mode_Callback(source,eventdata,protocol.mode());

            displayInfo.HideFOVOverlay = false;
            updateBusyState('Restoring sequence preview...');
            restoreLoadedSequencePreview();
            updateTargetFlipAngleDisplay();
            updateReadoutTooltips();
            slice = readSequenceSlice(inputInfo);
            if radialAxesRestored || (~protocol.hasUnifiedFOV && slice.offset ~= 0)
                markSequenceDirty();
            else
                markSequenceClean();
            end
            
            clear tempStr tempCell;
            
            if ~isempty(inputCmd{1,1}) && ~isempty(inputCmd{2,1}) && ~isempty(inputCmd{4,1}) && ...
                    exist([inputCmd{1,1},inputCmd{1,2}],'file') == 2 && ...
                    exist([inputCmd{2,1},inputCmd{2,2}],'file') == 2 && ...
                    exist([inputCmd{4,1},inputCmd{4,2}],'file') == 2
                set(hRun,'Enable','on');
            else
                set(hRun,'Enable','off');
            end
            updateFieldViewerButtonState();

            logSetup('Loaded protocol "%s": sequence=%s, nucleus=%s, Tx=%d, Rx=%d', ...
                get(hStudyName,'String'), getCurrentSequenceName(), getCurrentNucleus(), Tx.Num, Rx.Num);
            logSetup('Input summary: geometry=%s, tissue=%s, B1+=%d file(s), B1-=%d file(s), E1+=%d file(s), E1-=%d file(s)', ...
                formatInputFileForLog(1), formatInputFileForLog(2), countInputFiles(5), countInputFiles(7), ...
                countInputFiles(6), countInputFiles(8));

            if get(hDisplayMenu,'Value') ~= 1 && ~isempty(inputCmd{2,1})
                DisplayMenu_Callback(source,eventdata,'');
            else
                displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
            end
        end;
        
        clear tempAddr;
    end

    %% --- Executes on StudySave button.
    function StudySave_Callback(source,eventdata,flag) %#ok<INUSL,INUSL>
        if sequenceState.radialRestorationPending
            message = 'Regenerate the restored RAD_3D sequence before saving this protocol.';
            warnSetup('Save cancelled: %s',message);
            warndlg(message,'RAD_3D regeneration required');
            return;
        end
        if updateRadialAxisControls()
            markSequenceDirty();
        end
        showSaveBusy = strcmp(flag,'');
        if showSaveBusy && ~isempty(inputCmd{4,1}) && ...
                ~ensureCurrentSequence(source,eventdata,'saving','Save cancelled')
            return;
        end
        if showSaveBusy
            beginBusyState('Saving protocol...');
            saveBusyCleanup = onCleanup(@() endBusyState()); %#ok<NASGU>
        end
        
        cd(addr);
        
        tempAddr = addr;

        fileName = get(hStudyName,'String');
        pathName = horzcat(protocolRoot,'\',get(hStudyName,'String'),'\');

        writeSetupProtocol([pathName,fileName,'.prot'],collectSetupProtocol());
        logSetup('Saved protocol file: %s', [pathName,fileName,'.prot']);
                
        cd(tempAddr);
        clear tempAddr;
    end

    function protocol = collectSetupProtocol()
        protocol.geometryFilename = selectedProtocolFile(1);
        protocol.tissueFilename = selectedProtocolFile(2);
        protocol.deltaB0Filename = selectedProtocolFile(3);
        protocol.sequenceFilename = selectedProtocolFile(4);
        protocol.b1PlusFiles = selectedProtocolCoils(5);
        protocol.e1PlusFiles = selectedProtocolCoils(6);
        protocol.b1MinusFiles = selectedProtocolCoils(7);
        protocol.e1MinusFiles = selectedProtocolCoils(8);
        protocol.gxFilename = selectedProtocolFile(9);
        protocol.gyFilename = selectedProtocolFile(10);
        protocol.gzFilename = selectedProtocolFile(11);
        protocol.kspaceFilename = selectedProtocolFile(12);
        protocol.trajectoryFilename = selectedProtocolFile(13);
        protocol.noiseFilename = selectedProtocolFile(14);
        protocol.sarFilename = selectedProtocolFile(15);
        protocol.tx = Tx;
        protocol.shimB1Text = formatOptionalScalar(Tx.RefB1);
        protocol.rxCount = Rx.Num;

        protocol.display = selectedProtocolMenuText(hDisplayMenu);
        protocol.scale = selectedProtocolMenuText(hScaleMenu);
        protocol.sliceOrientation = selectedProtocolMenuText(hOrientationMenu);
        protocol.sequenceType = selectedProtocolMenuText(hSeqType);
        protocol.rfShape = selectedProtocolMenuText(hRF_Shape);
        protocol.phaseEncodeDirection = selectedProtocolMenuText(hPEDirectMenu);
        protocol.mode = selectedProtocolMenuText(hMode);
        protocol.sliceThicknessText = get(hGeoSliceTH,'String');
        protocol.slicePositionText = get(hGeoSliderEdit,'String');
        protocol.xMinText = get(hXMin,'String');
        protocol.yMinText = get(hYMin,'String');
        protocol.zMinText = get(hZMin,'String');
        protocol.xMaxText = get(hXMax,'String');
        protocol.yMaxText = get(hYMax,'String');
        protocol.zMaxText = get(hZMax,'String');
        protocol.xCenterText = get(hXCtr,'String');
        protocol.yCenterText = get(hYCtr,'String');
        protocol.zCenterText = get(hZCtr,'String');
        protocol.xOffsetText = get(hXSet,'String');
        protocol.yOffsetText = get(hYSet,'String');
        protocol.zOffsetText = get(hZSet,'String');
        protocol.xWidthText = get(hXWid,'String');
        protocol.yWidthText = get(hYWid,'String');
        protocol.zWidthText = get(hZWid,'String');
        protocol.b0Text = get(hB0Edit,'String');
        protocol.rfDurationText = get(hRF_Duration,'String');
        protocol.rfCountText = get(hRF_Num,'String');
        protocol.flipAngleText = get(hRF_FA,'String');
        protocol.targetB1Text = get(hTargetB1,'String');
        protocol.adcFrequencyText = get(hADC_Freq,'String');
        protocol.radialResolutionText = get(hRadialResolution,'String');
        protocol.inversionTimeText = get(hTI,'String');
        protocol.teText = get(hTE,'String');
        protocol.trText = get(hTR,'String');
        protocol.dummyCountText = get(hDummyNum,'String');
        protocol.numIsoText = get(hNumIso,'String');
        protocol.cpuCountText = get(hCPU,'String');
        protocol.nexText = get(hNEX,'String');
        protocol.nucleus = getCurrentNucleus();
        protocol.fov = get(hFOV,'Value');
        protocol.matrixSize = get(hMatSize,'Value');
        protocol.sliceSelect = get(hSS,'Value');
        protocol.phaseEncode = get(hPE,'Value');
        protocol.frequencyEncode = get(hFE,'Value');
        protocol.signalEngine = getSignalEngineLabel();
        protocol.noiseLoading = noiseLoading;
    end

    function filename = selectedProtocolFile(row)
        filename = '';
        if strcmp(inputCmd{row,1},'') ~= 1
            filename = [inputCmd{row,1},inputCmd{row,2}];
        end
    end

    function files = selectedProtocolCoils(row)
        files = {};
        if strcmp(inputCmd{row,1},'') ~= 1
            directories = inputCmd{row,1};
            filenames = inputCmd{row,2};
            files = cell(size(filenames));
            for n = 1:length(filenames)
                files{n} = [directories{n},filenames{n}];
            end
        end
    end

    function text = selectedProtocolMenuText(control)
        choices = get(control,'String');
        text = choices{get(control,'Value')};
    end

    %% --- Executes on StudyReset button.
    function StudyReset_Callback(source,eventdata) %#ok<INUSD>
        temp = questdlg('All input will be lost. Are you sure to continue?','Reset','Yes','No','No');
        if strcmp(temp,'Yes')
            logSetup('Resetting current study settings.');
            reset();
            tempStr = get(hStudyName,'String');
            if exist([protocolRoot,'\',tempStr,'\'],'file')~=7
                mkdir([protocolRoot,'\',tempStr,'\']);
            end;
            inputCmd{12,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{12,2}=[tempStr,'.ksig']; % KSpace FileName
            inputCmd{13,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{13,2}=[tempStr,'.ktrj']; % KMap FileName
            inputCmd{14,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{14,2}=[tempStr,'.nois']; % Noise FileName
            inputCmd{15,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{15,2}=[tempStr,'.sar']; % SAR FileName
            set(hExpGeo,'Enable','on');
        end;
    end

    %% Input and field-map selection callbacks
    % --- Executes on Geometry button.
    function ExpGeometry_Callback(source,eventdata,flag) %#ok<INUSL,INUSL>
              
        global geoData;
        global inputGeoData;
        global displayInfo;
        global inputInfo;
        
        if strcmp(flag,'')==1 % User Action
            
            cd (fileAddr);
            
            [fileName,pathName,index]=uigetfile({'*.smpl','Tissue Geometry File (*.smpl)';'*.*','All Fiiles (*.*)'},'OPEN: Geometry File');
            if index ~= 0
                reset();
                
                tempStr = get(hStudyName,'String');
                if exist([protocolRoot,'\',tempStr,'\'],'file')~=7
                    mkdir([protocolRoot,'\',tempStr,'\']);
                end;
                inputCmd{12,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{12,2}=[tempStr,'.ksig']; % KSpace FileName
                inputCmd{13,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{13,2}=[tempStr,'.ktrj']; % KMap FileName
                inputCmd{14,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{14,2}=[tempStr,'.nois']; % Noise FileName
                inputCmd{15,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{15,2}=[tempStr,'.sar']; % SAR FileName
                
                set(hExpGeo,'Enable','on');
                
                inputCmd{1,1} = pathName;
                inputCmd{1,2} = fileName;
               
                fileAddr = pathName;
            end;
        else
            index = 1;
            
            reset();
            tempStr = get(hStudyName,'String');
            if exist([protocolRoot,'\',tempStr,'\'],'file')~=7
                mkdir([protocolRoot,'\',tempStr,'\']);
            end;
            inputCmd{12,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{12,2}=[tempStr,'.ksig']; % KSpace FileName
            inputCmd{13,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{13,2}=[tempStr,'.ktrj']; % KMap FileName
            inputCmd{14,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{14,2}=[tempStr,'.nois']; % Noise FileName
            inputCmd{15,1}=[protocolRoot,'\',tempStr,'\']; inputCmd{15,2}=[tempStr,'.sar']; % SAR FileName
            
            set(hExpGeo,'Enable','on');
            
            [pathName, fileName] = addrCvrt(flag);
            inputCmd{1,1} = pathName;
            inputCmd{1,2} = fileName;
        end;

        if index ~= 0 % If *.smpl file is selected
            logSetup('Loading geometry: %s', [inputCmd{1,1},inputCmd{1,2}]);
            beginBusyState('Loading geometry...');
            geometryBusyCleanup = onCleanup(@() endBusyState()); %#ok<NASGU>
            [inputCmd{1,1},inputCmd{1,2}] = resolveProtocolPath([inputCmd{1,1},inputCmd{1,2}],...
                [protocolRoot,'\',get(hStudyName,'String'),'\']);
            file=[inputCmd{1,1},inputCmd{1,2}];
            inputInfo.filename=file;
            set(hExpGeoEdit,'String',filenameCvrt(inputCmd{1,2}));
            set(hExpGeoEdit,'FontAngle','normal');

            % Read in data.
            fid = fopen(file);
            if fid == -1
                errordlg(['Unable to open geometry file: ',file],'File Error');
                return;
            end

            legacyVoxelCount = fread(fid,1,'float32');
            geometryFileInfo = dir(file);
            geometryHeaderBytes = 13 * 4;
            geometryRecordBytes = 4 * 4;
            if isempty(geometryFileInfo) || geometryFileInfo.bytes < geometryHeaderBytes
                fclose(fid);
                errordlg('Geometry file is smaller than its 52-byte header.','Geometry File Error');
                return;
            end
            geometryPayloadBytes = geometryFileInfo.bytes - geometryHeaderBytes;
            if mod(geometryPayloadBytes,geometryRecordBytes) ~= 0
                fclose(fid);
                errordlg('Geometry payload is not a whole number of 16-byte voxel records.','Geometry File Error');
                return;
            end
            inputInfo.totNumVox = geometryPayloadBytes / geometryRecordBytes;
            if double(legacyVoxelCount) ~= inputInfo.totNumVox
                logSetup(['Geometry legacy float32 header reports %.0f voxels, but the payload ' ...
                    'contains %.0f. Using the payload-derived count.'], ...
                    double(legacyVoxelCount),inputInfo.totNumVox);
            end

            inputInfo.minX = round(fread(fid,1,'float32'));
            set(hXMin,'String',round(inputInfo.minX),'Enable','on');

            inputInfo.maxX = round(fread(fid,1,'float32'));                
            set(hXMax,'String',round(inputInfo.maxX),'Enable','on');

            inputInfo.minY = round(fread(fid,1,'float32'));
            set(hYMin,'String',round(inputInfo.minY),'Enable','on');

            inputInfo.maxY = round(fread(fid,1,'float32'));
            set(hYMax,'String',round(inputInfo.maxY),'Enable','on');

            inputInfo.minZ = round(fread(fid,1,'float32'));
            set(hZMin,'String',round(inputInfo.minZ),'Enable','on');

            inputInfo.maxZ = round(fread(fid,1,'float32'));
            set(hZMax,'String',round(inputInfo.maxZ),'Enable','on');

            inputInfo.ctrX = round(fread(fid,1,'float32'));
            set(hXCtr,'String',round(inputInfo.ctrX),'Enable','on');

            inputInfo.ctrY = round(fread(fid,1,'float32'));
            set(hYCtr,'String',round(inputInfo.ctrY),'Enable','on');

            inputInfo.ctrZ = round(fread(fid,1,'float32'));
            set(hZCtr,'String',round(inputInfo.ctrZ),'Enable','on');
            
            inputInfo.setX = 0;
            set(hXSet,'String',inputInfo.setX,'Enable','on');
            inputInfo.setY = 0;
            set(hYSet,'String',inputInfo.setY,'Enable','on');
            inputInfo.setZ = 0;
            set(hZSet,'String',inputInfo.setZ,'Enable','on');

            inputInfo.widX = fread(fid,1,'float32');
            set(hXWid,'String',sprintf('%.9g',inputInfo.widX),'Enable','inactive');

            inputInfo.widY = fread(fid,1,'float32');
            set(hYWid,'String',sprintf('%.9g',inputInfo.widY),'Enable','inactive');

            inputInfo.widZ = fread(fid,1,'float32');
            set(hZWid,'String',sprintf('%.9g',inputInfo.widZ),'Enable','inactive');
            

            inputGeoData = fread(fid,[4, Inf],'float32');
            fclose(fid);
            logSetup('Geometry loaded: %d voxels, bounds X[%d,%d] Y[%d,%d] Z[%d,%d], voxel size [%g %g %g] mm', ...
                round(inputInfo.totNumVox), round(inputInfo.minX), round(inputInfo.maxX), ...
                round(inputInfo.minY), round(inputInfo.maxY), round(inputInfo.minZ), round(inputInfo.maxZ), ...
                inputInfo.widX, inputInfo.widY, inputInfo.widZ);

            % Display images.
            displayInfo.Scale = get(hScaleMenu,'Value');
            
            displayInfo.minX = inputInfo.minX; % Fixed value, not to be changed by user input
            displayInfo.maxX = inputInfo.maxX;
            displayInfo.minY = inputInfo.minY;
            displayInfo.maxY = inputInfo.maxY;
            displayInfo.minZ = inputInfo.minZ;
            displayInfo.maxZ = inputInfo.maxZ;
            
            displayInfo.geoLengthX = displayInfo.maxX-displayInfo.minX+1;
            displayInfo.geoLengthY = displayInfo.maxY-displayInfo.minY+1;
            displayInfo.geoLengthZ = displayInfo.maxZ-displayInfo.minZ+1;

            displayInfo.geoDeltaX = (displayInfo.geoLengthX+1)/2-(displayInfo.maxX+displayInfo.minX)/2;
            displayInfo.geoDeltaY = (displayInfo.geoLengthY+1)/2-(displayInfo.maxY+displayInfo.minY)/2;
            displayInfo.geoDeltaZ = (displayInfo.geoLengthZ+1)/2-(displayInfo.maxZ+displayInfo.minZ)/2;

            geoData = zeros(displayInfo.geoLengthX, displayInfo.geoLengthY, displayInfo.geoLengthZ); % ID
            for n=1:length(inputGeoData(4,:))
                geoData(inputGeoData(1,n)+displayInfo.geoDeltaX, inputGeoData(2,n)+displayInfo.geoDeltaY, inputGeoData(3,n)+displayInfo.geoDeltaZ)=inputGeoData(4,n);
            end;

            displayInfo.imageLengthXY = max(displayInfo.geoLengthX,displayInfo.geoLengthY)*1.1;
            displayInfo.padAxial_X = ceil((displayInfo.imageLengthXY - displayInfo.geoLengthX)/2);
            displayInfo.padAxial_Y = ceil((displayInfo.imageLengthXY - displayInfo.geoLengthY)/2);

            displayInfo.imageLengthYZ = max(displayInfo.geoLengthY,displayInfo.geoLengthZ)*1.1;
            displayInfo.padSagittal_Y = ceil((displayInfo.imageLengthYZ - displayInfo.geoLengthY)/2);
            displayInfo.padSagittal_Z = ceil((displayInfo.imageLengthYZ - displayInfo.geoLengthZ)/2);

            displayInfo.imageLengthXZ = max(displayInfo.geoLengthX,displayInfo.geoLengthZ)*1.1;
            displayInfo.padCoronal_X = ceil((displayInfo.imageLengthXZ - displayInfo.geoLengthX)/2);
            displayInfo.padCoronal_Z = ceil((displayInfo.imageLengthXZ - displayInfo.geoLengthZ)/2);

            syncSlicePosition();

            set(hGeoSliceTH,'Enable','on');
            axesXYZ = cartesianAxes(get(hOrientationMenu,'Value'),false);
            spacing = [inputInfo.widX, inputInfo.widY, inputInfo.widZ];
            inputInfo.sliceTH = spacing(axesXYZ(3));
            set(hGeoSliceTH,'String',num2str(inputInfo.sliceTH,'%.9g'));
            inputInfo.FOV = str2double(get(hFOV,'String'));

            if strcmp(flag,'')==1
                updateBusyState('Rendering geometry...');
                displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
            end;

            set(hExpTiss,'Enable','on');
            set(hNoiseLoading,'Enable','on');
            set(hOrientationMenu,'Enable','on');
            set(hSave,'Enable','on');
            set(hReset,'Enable','on');
            set(hGeoSlider,'Enable','on');
            set(hGeoSliderEdit,'Enable','on');
            set(hScaleMenu,'Enable','on');

            updateFieldViewerButtonState();
        end;
    end

    %% --- Executes on Tissue button.
    function ExpTissue_Callback(source,eventdata,flag) %#ok<INUSL,INUSL>
        
        if strcmp(flag,'')==1
            
            cd (fileAddr);
            
            [fileName,pathName,index]=uigetfile({'*.prop','Tissue Property File (*.prop)';'*.*','All Fiiles (*.*)'},'OPEN: Tissue Property File');
            if index ~= 0
                inputCmd{2,1} = pathName;
                inputCmd{2,2} = fileName;
                invalidateTissueDisplayCache();
                
                fileAddr = pathName;
            end;
        else
            index = 1;
        end;
        
        if index ~= 0   % If *.prop file is selected
            invalidateTissueDisplayCache();
            if isempty(loadTissueDisplayData())
                inputCmd{2,1} = '';
                inputCmd{2,2} = '';
                set(hExpTissEdit,'String','Tiss Filename','FontAngle','italic');
                set(hRun,'Enable','off');
                return;
            end
            logSetup('Loaded tissue properties: %s', [inputCmd{2,1},inputCmd{2,2}]);
            set(hExpTissEdit,'String',filenameCvrt(inputCmd{2,2}));
            set(hExpTissEdit,'FontAngle','normal');

            set(hSave,'Enable','on');
            
            set(hDisplayMenu,'Enable','on');
            
            set(hExpSeq,'Enable','on');
            set(hSeqType,'Enable','on');
            set(hRF_Shape,'Enable','on');
            set(hRF_Duration,'Enable','on');
            set(hRF_Num,'Enable','on');
            set(hRF_FA,'Enable','on');
            set(hTargetB1,'Enable','on');
            set(hDummyNum,'Enable','on');
            set(hFOV,'Enable','on');
            set(hFOV_Pop,'Enable','on');
            set(hMatch,'Enable','on');
            set(hMatSize,'Enable','on');
            set(hMatSize_Pop,'Enable','on');
                    
            set(hADC_Freq,'Enable','on');
            
            set(hTx,'Enable','on');
            set(hRx,'Enable','on');
            
            updateSequenceSpecificFieldLabels();
            set(hTE,'Enable','on');
            set(hTR,'Enable','on');
            set(hSS,'Enable','on');
            set(hPE,'Enable','on');
            set(hFE,'Enable','on');
            set(hPEDirectMenu,'Enable','on');
            set(hSeqGen,'Enable','on');
            set(hMode,'Enable','on');
            
            
            % % % Get minTE, minTR
            updateSeq();
            Mode_Callback(source,eventdata,'');
            
        end;
    end

    %% --- Executes on DB0 button.
    function ExpDB0_Callback(source,eventdata,flag) %#ok<INUSL,INUSL>
        global button inputInfo
        if strcmp(flag,'')==1

            %             cd (fileAddr);
            button = questdlg('Please select an option.','Delta B0 File','Load File','Create File','Cancel','Load File');
            switch button
                case 'Create File'
                    hB0Solver = B0Solver;
                    if ishghandle(hB0Solver)
                        uiwait(hB0Solver);
                    end
                    if isstruct(inputInfo) && isfield(inputInfo,'savefilename') && isfield(inputInfo,'pathname') && ...
                            ~isequal(inputInfo.savefilename,0) && ~isequal(inputInfo.pathname,0)
                        fileName=inputInfo.savefilename;
                        pathName=inputInfo.pathname;
                        inputCmd{3,1} = pathName;
                        inputCmd{3,2} = fileName;
                        index=1;
                        fileAddr = pathName;
                    else
                        index = 0;
                    end

                    if index ~= 0
                        set(hExpDB0Edit,'String',filenameCvrt(inputCmd{3,2}));
                        set(hExpDB0Edit,'FontAngle','normal');
                    end;
                case 'Load File'
                    [fileName,pathName,index]=uigetfile({'*.db0','Delta B0 File (*.db0)';'*.*','All Fiiles (*.*)'},'OPEN: Delta B0 File');
                    if index ~= 0
                        inputCmd{3,1} = pathName;
                        inputCmd{3,2} = fileName;

                        fileAddr = pathName;
                        %                     end;
                    else
                        index = 0;
                    end;

                    if index ~= 0
                        set(hExpDB0Edit,'String',filenameCvrt(inputCmd{3,2}));
                        set(hExpDB0Edit,'FontAngle','normal');
                    end;
                case 'Cancel'
                    return
            end
        end
    end

    %% --- Executes on Seq button.
    function ExpSeq_Callback(source,eventdata,flag) %#ok<INUSL,INUSL>
        
        global geoData;
        global displayInfo;
        global inputInfo;
        
        if strcmp(flag,'')==1
            
            cd (fileAddr);
            
            [fileName,pathName,index]=uigetfile({'*.seqn','Sequence File (*.seqn)';'*.*','All Fiiles (*.*)'},'OPEN: Sequence File');
            if index ~= 0
                inputCmd{4,1} = pathName;
                inputCmd{4,2} = fileName;

                fileAddr = pathName;
            end;
        else
            index = 1;
        end;
        
        if index ~= 0
            logSetup('Using external sequence file: %s', [inputCmd{4,1},inputCmd{4,2}]);
            fid = fopen([inputCmd{4,1},inputCmd{4,2}],'r');
            if fid == -1
                warnSetup('Cannot open external sequence file.');
                return;
            end
            header = fread(fid,5,'float32');
            if numel(header) == 5 && header(1) == -1 && header(2) == 1
                sequenceChannels = header(4:5);
            else
                sequenceChannels = [];
            end
            fclose(fid);
            if numel(sequenceChannels) ~= 2 || any(~isfinite(sequenceChannels)) || ...
                    any(sequenceChannels ~= fix(sequenceChannels)) || ...
                    sequenceChannels(1) < 0 || sequenceChannels(2) < 1 || any(sequenceChannels > 65535)
                warnSetup('Invalid external sequence header. V1 is required; regenerate old sequences with current Setup.');
                return;
            end
            set(hExpSeqEdit,'String',filenameCvrt(inputCmd{4,2}));
            set(hExpSeqEdit,'FontAngle','normal');

            % % % Display OrientationMenu.
            set(hOrientationMenu,'Enable','off');

            % % % Display GeoSliderTH.
            set(hGeoSliceTH,'String','0','Enable','off');

            % % % Display GeoSlider.
            set(hGeoSlider,'Max',100,'Min',0,'Value',0,...
                'SliderStep',[1/100,10/100],'Enable','off');

            % % % Display GeoSliderEdit.
            set(hGeoSliderEdit,'String','0','Enable','off');

            % % % Display the B0Edit.
            set(hB0Edit,'string','3','Enable','on');
            set(hNucleus,'Value',1,'Enable','on');

            % % % Display the SequenceType menu.
            set(hSeqType,'Value',1,'Enable','off');

            % % % Display the RF_Shape menu.
            set(hRF_Shape,'Value',1,'Enable','off');

            % % % Display the RF_Duration edit.
            set(hRF_Duration,'String','2.6','Enable','off');

            % % % Display the RF# edit.
            set(hRF_Num,'String','512','Enable','off');
            
            % % % Display the RF_FA edit.
            set(hRF_FA,'String','90','Enable','off');

            % % % Display the target B1+ edit.
            set(hTargetB1,'String','','Enable','off');

            % % % Display the FOV edit.
            set(hFOV,'String','300','Enable','off');

            % % % Display the MatSize edit.
            set(hMatSize,'String','128','Enable','off');

            % % % Display the ADC_Freq edit.
            set(hADC_Freq,'String','50','Enable','off');
            resetRadialResolutionControls();

            % % % Display the #Tx edit.
            Tx.Num=sequenceChannels(1);
            
            set(hTx,'String',num2str(Tx.Num),'Enable','off');            
            Tx.MagMat = ones(Tx.Num,1);
            Tx.PhsMat = zeros(Tx.Num,1);
            Tx.RefB1 = NaN;
            
            % % % Display the #Rx edit.
            Rx.Num=sequenceChannels(2);
            
            set(hRx,'String',num2str(Rx.Num),'Enable','off');
                        
            % % % Display the SS checkbox.
            set(hSS,'String','SS','Value',1,'Enable','off');

            % % % Display the PE checkbox.
            set(hPE,'String','PE','Value',1,'Enable','off');

            % % % Display the FE checkbox.
            set(hFE,'String','FE','Value',1,'Enable','off');

            % % % Display the TE edit.
            set(hTE,'String','TE','String','10','Enable','off');

            % % % Display the TR edit.
            set(hTR,'String','TR','String','500','Enable','off');

            % % % Display the DummyNum edit.
            set(hDummyNum,'String','0','Enable','off');

            % % % Display the PEDirect edit.
            set(hPEDirectMenu,'String',{'P--A';'A--P';'L--R';'R--L'},'Value',1,...
               'Enable','off'); % to be edited

            set(hSeqGen,'Enable','off');

            set(hSeqPlot,'Enable','off');
            updateLarmorTooltips();
            updateReadoutTooltips();
            displayInfo.HideFOVOverlay = true;

            displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
            markSequenceClean();
            
            set(hMode,'Enable','on');
            tempMode = get(hMode,'Value');
            switch tempMode
                case 1
                    set(hB0Edit,'Enable','on');
                    set(hNucleus,'Enable','on');
                    set(hExpDB0,'Enable','on');
                    set(hExpB1m,'Enable','on');
                    set(hExpGx,'Enable','on');
                    set(hExpGy,'Enable','on');
                    set(hExpGz,'Enable','on');
                    
                    set(hExpB1p,'Enable','on');
                    set(hExpE1p,'Enable','off');
                    
                    set(hExpE1m,'Enable','off');

                    set(hNumIso,'Enable','on');
                    set(hCPU,'Enable','on');
                    set(hSignalGPU,'Enable','on');
                    set(hNEX,'Enable','off');
                    
                case 2
                    set(hB0Edit,'Enable','off');
                    set(hNucleus,'Enable','off');
                    set(hExpDB0,'Enable','off');
                    set(hExpB1p,'Enable','off');
                    set(hExpB1m,'Enable','off');
                    set(hExpGx,'Enable','off');
                    set(hExpGy,'Enable','off');
                    set(hExpGz,'Enable','off');
                    
                    set(hExpB1p,'Enable','on');
                    set(hExpE1p,'Enable','on');
                    
                    set(hExpE1m,'Enable','off');
                    
                    set(hNumIso,'Enable','off');
                    set(hCPU,'Enable','on');
                    set(hSignalGPU,'Enable','off');
                    set(hNEX,'Enable','off');
                    
                case 3
                    set(hB0Edit,'Enable','off');
                    set(hNucleus,'Enable','off');
                    set(hExpDB0,'Enable','off');
                    set(hExpB1p,'Enable','off');
                    set(hExpB1m,'Enable','off');
                    set(hExpGx,'Enable','off');
                    set(hExpGy,'Enable','off');
                    set(hExpGz,'Enable','off');
                    
                    set(hExpB1p,'Enable','off');
                    set(hExpE1p,'Enable','off');
                    
                    set(hExpE1m,'Enable','on');
                    
                    set(hNumIso,'Enable','off');
                    set(hCPU,'Enable','off');
                    set(hSignalGPU,'Enable','off');
                    set(hNEX,'Enable','on');
            end;
            
            if ~isempty(inputCmd{1,1}) && ~isempty(inputCmd{2,1})
                set(hRun,'Enable','on');
                if tempMode ~= 3
                    set(hCPU,'Enable','on');
                end
            end;
        end;
    end

    %% --- Executes on B1p button.
    function ExpB1p_Callback(source,eventdata,flag) %#ok<INUSL,INUSL>

        if strcmp(flag,'')==1
            RF.FA = str2double(get(hRF_FA,'String')); %Degrees
            [fileName,pathName,index]=B1pTxFileNameGUI(Tx.Num,inputCmd{5,1},inputCmd{5,2},Tx.MagMat,Tx.PhsMat,RF.FA);
            if index ~= 0
                if (iscell(fileName) == 1 && Tx.Num == length(fileName))
                    inputCmd{5,1} = pathName;
                    inputCmd{5,2} = fileName;
                end;
            end;
        else
            index = 1;
        end;
        
        if index ~= 0
            logSetup('Loaded B1+ files: %d Tx channel(s)', countInputFiles(5));
            tempStr = '';
            for n=1:length(inputCmd{5,2})
                tempStr = [tempStr,filenameCvrt(inputCmd{5,2}{n}),'; ']; %#ok<AGROW>
            end;
            set(hExpB1pEdit,'String',tempStr);
            set(hExpB1pEdit,'FontAngle','normal');
        end;
        updateFieldViewerButtonState();
    end

    %% --- Executes on E1p button.
    function ExpE1p_Callback(source,eventdata,flag) %#ok<INUSL,INUSL>
        
        if strcmp(flag,'')==1
            
            RF.FA = str2double(get(hRF_FA,'String')); %Degrees
            [fileName,pathName,index]=E1pTxFileNameGUI(Tx.Num,inputCmd{6,1},inputCmd{6,2},Tx.MagMat,Tx.PhsMat,RF.FA);
            if index ~= 0
                if (iscell(fileName) == 1 && Tx.Num == length(fileName))
                    inputCmd{6,1} = pathName;
                    inputCmd{6,2} = fileName;
                end;
            end;
        else
            index = 1;
        end;
        
        if index ~= 0
            logSetup('Loaded E1+ files: %d Tx channel(s)', countInputFiles(6));
            tempStr = '';
            for n=1:length(inputCmd{6,2})
                tempStr = [tempStr,filenameCvrt(inputCmd{6,2}{n}),'; ']; %#ok<AGROW>
            end;
            set(hExpE1pEdit,'String',tempStr);
            set(hExpE1pEdit,'FontAngle','normal');
        end;
        updateFieldViewerButtonState();
    end

    %% --- Executes on B1m button.
    function ExpB1m_Callback(source,eventdata,flag) %#ok<INUSL,INUSL>
        
        if strcmp(flag,'')==1
            
            cd (fileAddr);
            
            [fileName,pathName,index]=uigetfile({'*.bfld','B1 Minus File (*.bfld)';'*.*','All Fiiles (*.*)'},'OPEN: B1 Minus File','MultiSelect','on');
            if index ~= 0                
                if (iscell(fileName) ~= 1 && Rx.Num == 1)
                    inputCmd{7,1}{1} = pathName;
                    inputCmd{7,2}{1} = fileName;
                elseif (iscell(fileName) == 1 && Rx.Num == length(fileName))
                    inputCmd{7,1} = fileName;
                    for n=1:length(inputCmd{7,1})
                        inputCmd{7,1}{n} = pathName;
                    end;
                    inputCmd{7,2} = fileName;
                else
                    tempStr = '# Rx does not match the sequence file!';
                    warnSetup('B1- selection cancelled: selected file count does not match #Rx=%d.', Rx.Num);
                    errordlg(tempStr,'modal');
                    index = 0;
                end;
                fileAddr = pathName;
            end;
        else
            index = 1;
        end;
        
        if index ~= 0
            logSetup('Loaded B1- files: %d Rx channel(s)', countInputFiles(7));
            if iscell(inputCmd{7,2}) ~= 1
                set(hExpB1mEdit,'String',[filenameCvrt(inputCmd{7,2}),'; ']);
            else
                tempStr = '';
                for n=1:length(inputCmd{7,2})
                    tempStr = [tempStr,filenameCvrt(inputCmd{7,2}{n}),'; ']; %#ok<AGROW>
                end;
                set(hExpB1mEdit,'String',tempStr);
            end;
            set(hExpB1mEdit,'FontAngle','normal');
        end;
        updateFieldViewerButtonState();
    end

    %% --- Executes on E1m button.
    function ExpE1m_Callback(source,eventdata,flag) %#ok<INUSL,INUSL>
        
        if strcmp(flag,'')==1
            
            cd (fileAddr);
            
            [fileName,pathName,index]=uigetfile({'*.efld','E1 Minus File (*.efld)';'*.*','All Fiiles (*.*)'},'OPEN: E1 Minus File','MultiSelect','on');
            if index ~= 0
                if (iscell(fileName) ~= 1 && Rx.Num == 1)
                    inputCmd{8,1}{1} = pathName;
                    inputCmd{8,2}{1} = fileName;
                elseif (iscell(fileName) == 1 && Rx.Num == length(fileName))
                    inputCmd{8,1} = fileName;
                    for n=1:length(inputCmd{8,1})
                        inputCmd{8,1}{n} = pathName;
                    end;
                    inputCmd{8,2} = fileName;
                else
                    tempStr = '# Rx does not match the sequence file!';
                    warnSetup('E1- selection cancelled: selected file count does not match #Rx=%d.', Rx.Num);
                    errordlg(tempStr,'modal');
                    index = 0;
                end;
                
                fileAddr = pathName;
            end;
        else
            index = 1;
        end;
        
        if index ~= 0
            logSetup('Loaded E1- files: %d Rx channel(s)', countInputFiles(8));
            if iscell(inputCmd{8,2}) ~= 1
                set(hExpE1mEdit,'String',[filenameCvrt(inputCmd{8,2}),'; ']);
            else
                tempStr = '';
                for n=1:length(inputCmd{8,2})
                    tempStr = [tempStr,filenameCvrt(inputCmd{8,2}{n}),'; ']; %#ok<AGROW>
                end;
                set(hExpE1mEdit,'String',tempStr);
            end;
            set(hExpE1mEdit,'FontAngle','normal');
        end;
        updateFieldViewerButtonState();
    end

    function FieldViewer_Callback(source,eventdata) %#ok<INUSD,INUSD>
        global inputInfo displayInfo;

        if isempty(inputInfo) || isempty(displayInfo) || isempty(inputCmd{1,1}) || ...
                exist([inputCmd{1,1},inputCmd{1,2}],'file') ~= 2
            warnSetup('Cannot open field viewer: load geometry first.');
            errordlg('Please load geometry before opening the field viewer.','modal');
            return;
        end

        [viewerData,viewerError] = collectFieldViewerData();
        if ~isempty(viewerError)
            warnSetup('Cannot open field viewer: %s', viewerError);
            uiwait(errordlg(viewerError,'Field Viewer','modal'));
            return;
        end

        if isempty(viewerData.B1pFiles) && isempty(viewerData.B1mFiles) && ...
                isempty(viewerData.E1pFiles) && isempty(viewerData.E1mFiles)
            warnSetup('Cannot open field viewer: no B1 or E field files are loaded.');
            errordlg('Please load at least one B1 or E field file before opening the field viewer.','modal');
            return;
        end

        beginBusyState('Opening field viewer...');
        fieldViewerCleanup = onCleanup(@() endBusyState()); %#ok<NASGU>
        logSetup('Opening field viewer: B1+=%d, B1-=%d, E1+=%d, E1-=%d file(s)', ...
            numel(viewerData.B1pFiles), numel(viewerData.B1mFiles), numel(viewerData.E1pFiles), numel(viewerData.E1mFiles));
        studyFieldViewer(viewerData);
    end

%% --- Executes on Gx button.
    function ExpGx_Callback(source,eventdata,flag) %#ok<INUSL>
        
        if strcmp(flag,'')==1
            
            cd (fileAddr);
            
            [fileName,pathName,index]=uigetfile({'*.grad','Grad Distribution File (*.grad)';'*.*','All Fiiles (*.*)'},'OPEN: Grad Distribution File');
            if index ~= 0
                inputCmd{9,1} = pathName;
                inputCmd{9,2} = fileName;
                
                fileAddr = pathName;
            end;
        else
            index = 1;
        end;
        
        if index ~= 0
            set(hExpGxEdit,'String',filenameCvrt(inputCmd{9,2}));
        end;

        set(hExpGxEdit,'FontAngle','normal');
    end

    %% --- Executes on Gy button.
    function ExpGy_Callback(source,eventdata,flag) %#ok<INUSL>
        
        if strcmp(flag,'')==1
            
            cd (fileAddr);
            
            [fileName,pathName,index]=uigetfile({'*.grad','Grad Distribution File (*.grad)';'*.*','All Fiiles (*.*)'},'OPEN: Grad Distribution File');            
            if index ~= 0
                inputCmd{10,1} = pathName;
                inputCmd{10,2} = fileName;
               
                fileAddr = pathName;
            end;            
        else
            index = 1;
        end;
        
        if index ~= 0
            set(hExpGyEdit,'String',filenameCvrt(inputCmd{10,2}));
        end;
        
        set(hExpGyEdit,'FontAngle','normal');
    end

    %% --- Executes on Gz button.
    function ExpGz_Callback(source,eventdata,flag) %#ok<INUSL>
        
        if strcmp(flag,'')==1
            
            cd (fileAddr);
            
            [fileName,pathName,index]=uigetfile({'*.grad','Grad Distribution File (*.grad)';'*.*','All Fiiles (*.*)'},'OPEN: Grad Distribution File');
            if index ~= 0
                inputCmd{11,1} = pathName;
                inputCmd{11,2} = fileName;
                
                fileAddr = pathName;
            end;
        else
            index = 1;
        end;
        
        if index ~= 0
            set(hExpGzEdit,'String',filenameCvrt(inputCmd{11,2}));
        end;
        set(hExpGzEdit,'FontAngle','normal');
    end

    %% Geometry display and sampling controls
    % --- Executes on DisplayMenu.
    function DisplayMenu_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo inputGeoData;
        
        if strcmp(flag,'')==1
            temp = get(hDisplayMenu,'Value');
            if rebuildDisplayedGeometry(temp)
                refreshGeometryDisplay();
            end
        else
            tempDisplayMenu = get(hDisplayMenu,'String');
            tempLoc=find(strcmp(tempDisplayMenu,flag));
            if isempty(tempLoc) && strcmp(flag,'T2') && any(strcmp(tempDisplayMenu,'T2s'))
                tempLoc = find(strcmp(tempDisplayMenu,'T2s'),1);
            end
            if isempty(tempLoc)
                tempLoc = 1;
            end
            set(hDisplayMenu,'Value',tempLoc);
        end;
        clear tempDisplayMenu;
    end

    %% --- Executes on ScaleMenu.
    function ScaleMenu_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo;
        
        if strcmp(flag,'')==1
            displayInfo.Scale = get(hScaleMenu,'Value');
            refreshGeometryDisplay();
        else
            if isnumeric(flag)
                tempScale = flag;
            else
                tempScaleMenu = get(hScaleMenu,'String');
                tempScale = find(strcmp(tempScaleMenu,flag),1);
            end
            if ~isempty(tempScale)
                set(hScaleMenu,'Value',tempScale);
                displayInfo.Scale = tempScale;
            end
        end;
        clear tempDisplayMenu;
    end
        
    %% --- Executes on OrientationMenu.
    function OrientationMenu_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo;
        
        if ~isempty(flag)
            orientations = get(hOrientationMenu,'String');
            set(hOrientationMenu,'Value',find(strcmp(orientations,flag),1));
        end
        setCartesianPEDirectionOptions();
        syncSlicePosition();
        if isempty(flag)
            refreshGeometryDisplay();
            markSequenceDirty();
        end
    end

    function GeoSliceTHEdit_Callback(source,eventdata,flag) %#ok<INUSL>
        global inputInfo;
        isInteractive = isempty(flag);
        if isInteractive
            flag = get(hGeoSliceTH,'String');
        end
        thickness = str2double(flag);
        if ~isreal(thickness) || ~isfinite(thickness) || thickness <= 0
            thickness = inputInfo.sliceTH;
        end
        inputInfo.sliceTH = thickness;
        set(hGeoSliceTH,'String',num2str(thickness,'%.9g'));
        refreshGeometryDisplay();
        if isInteractive
            updateReadoutTooltips();
        end
        markSequenceDirty();
    end

    function GeoSlider_Callback(source,eventdata,flag) %#ok<INUSD>
        changeSlicePosition(get(hGeoSlider,'Value'));
    end

    function GeoSliderEdit_Callback(source,eventdata,flag) %#ok<INUSD>
        changeSlicePosition(str2double(get(hGeoSliderEdit,'String')));
    end

    function changeSlicePosition(position)
        if isreal(position) && isfinite(position)
            setSlicePosition(position);
            if ~is3DRadSequenceName(getCurrentSequenceName())
                markSequenceDirty();
            end
        end
        updateSliceDisplay();
    end

    function updateSliceDisplay()
        syncSlicePosition();
        if rebuildDisplayedGeometry(get(hDisplayMenu,'Value'))
            refreshGeometryDisplay();
        end
    end

    function setSlicePosition(position)
        global inputInfo;
        axesXYZ = cartesianAxes(get(hOrientationMenu,'Value'),false);
        axisName = 'XYZ';
        axisName = axisName(axesXYZ(3));
        if is3DRadSequenceName(getCurrentSequenceName())
            inputInfo.(['current',axisName]) = round(position);
        else
            field = ['set',axisName];
            inputInfo.(field) = round(position) - inputInfo.(['ctr',axisName]);
            offsets = [hXSet,hYSet,hZSet];
            set(offsets(axesXYZ(3)),'String',num2str(inputInfo.(field)));
        end
    end

    function syncSlicePosition()
        global inputInfo displayInfo;
        axesXYZ = cartesianAxes(get(hOrientationMenu,'Value'),false);
        axisNames = 'XYZ';
        radial = is3DRadSequenceName(getCurrentSequenceName());
        for axisName = axisNames
            current = ['current',axisName];
            lo = displayInfo.(['min',axisName]);
            hi = displayInfo.(['max',axisName]);
            if radial && isfield(inputInfo,current)
                position = inputInfo.(current);
            else
                position = inputInfo.(['ctr',axisName]) + inputInfo.(['set',axisName]);
            end
            inputInfo.(current) = min(hi,max(lo,position));
            if axisName == axisNames(axesXYZ(3))
                % The edit can prescribe outside the model while the view stays inside.
                step = 1/max(1,hi-lo);
                set(hGeoSlider,'Min',lo,'Max',max(lo+1,hi), ...
                    'Value',inputInfo.(current),'SliderStep',[step,max(step,0.1)]);
                set(hGeoSliderEdit,'String',num2str(position));
            end
        end
    end

    %% --- Executes on xMin_edit.
    function XMin_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo;
        
        if strcmp(flag,'')==1
            temp = round(str2double(get(hXMin, 'String')));
                      
            if temp <= str2double(get(hXMax, 'String'))
                set(hXMin,'String',num2str(temp));
                inputInfo.minX = str2double(get(hXMin, 'String'));
            elseif temp > str2double(get(hXMax, 'String'))
                set(hXMin,'String',num2str(str2double(get(hXMax, 'String'))));
                inputInfo.minX = str2double(get(hXMin, 'String'));
            else
                set(hXMin, 'String',num2str(inputInfo.minX));
            end;
                       
            displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
        else
            set(hXMin,'String',flag);
            inputInfo.minX = round(str2double(get(hXMin, 'String')));
        end;
    end

    %% --- Executes on xMax_edit.
    function XMax_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo;
        
        if strcmp(flag,'')==1
            temp = round(str2double(get(hXMax, 'String')));
            
            if temp >= str2double(get(hXMin, 'String'))
                set(hXMax,'String',num2str(temp));
                inputInfo.maxX = str2double(get(hXMax, 'String'));
            elseif temp < str2double(get(hXMin, 'String'))
                set(hXMax,'String',num2str(str2double(get(hXMin, 'String'))));
                inputInfo.maxX = str2double(get(hXMax, 'String'));
            else
                set(hXMax, 'String',num2str(inputInfo.maxX));
            end;

            displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
        else
            set(hXMax,'String',flag);
            inputInfo.maxX = round(str2double(get(hXMax, 'String')));
        end;
    end

    %% --- Executes on yMin_edit.
    function YMin_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo;
        
        if strcmp(flag,'')==1
            temp = round(str2double(get(hYMin, 'String')));
            
            if temp <= str2double(get(hYMax, 'String'))
                set(hYMin,'String',num2str(temp));
                inputInfo.minY = str2double(get(hYMin, 'String'));
            elseif temp > str2double(get(hYMax, 'String'))
                set(hYMin,'String',num2str(str2double(get(hYMax, 'String'))));
                inputInfo.minY = str2double(get(hYMin, 'String'));
            else
                set(hYMin, 'String',num2str(inputInfo.minY));
            end;

            displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
        else
            set(hYMin,'String',flag); 
            inputInfo.minY = round(str2double(get(hYMin, 'String')));
        end;        
    end

    %% --- Executes on yMax_edit.
    function YMax_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo;
        
        if strcmp(flag,'')==1
            temp = round(str2double(get(hYMax, 'String')));
            
            if temp >= str2double(get(hYMin, 'String'))
                set(hYMax,'String',num2str(temp));
                inputInfo.maxY = str2double(get(hYMax, 'String'));
            elseif temp < str2double(get(hYMin, 'String'))
                set(hYMax,'String',num2str(str2double(get(hYMin, 'String'))));
                inputInfo.maxY = str2double(get(hYMax, 'String'));
            else
                set(hYMax, 'String',num2str(inputInfo.maxY));
            end;

            displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
        else
            set(hYMax,'String',flag);
            inputInfo.maxY = round(str2double(get(hYMax, 'String')));
        end;
    end

    %% --- Executes on zMin_edit.
    function ZMin_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo;
        
        if strcmp(flag,'')==1
            temp = round(str2double(get(hZMin, 'String')));

            if temp <= str2double(get(hZMax, 'String'))
                set(hZMin,'String',num2str(temp));
                inputInfo.minZ = str2double(get(hZMin, 'String'));
            elseif temp > str2double(get(hZMax, 'String'))
                set(hZMin,'String',num2str(str2double(get(hZMax, 'String'))));
                inputInfo.minZ = str2double(get(hZMin, 'String'));
            else
                set(hZMin, 'String',num2str(inputInfo.minZ));
            end;

            displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
        else
            set(hZMin,'String',flag);
            inputInfo.minZ = round(str2double(get(hZMin, 'String')));
        end;
    end

    %% --- Executes on zMax_edit.
    function ZMax_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo;
        
        if strcmp(flag,'')==1
            temp = round(str2double(get(hZMax, 'String')));
            
            if temp >= str2double(get(hZMin, 'String'))
                set(hZMax,'String',num2str(temp));
                inputInfo.maxZ = str2double(get(hZMax, 'String'));
            elseif temp < str2double(get(hZMin, 'String'))
                set(hZMax,'String',num2str(str2double(get(hZMin, 'String'))));
                inputInfo.maxZ = str2double(get(hZMax, 'String'));
            else
                set(hZMax, 'String',num2str(inputInfo.maxZ));
            end;

            displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
        else
            set(hZMax,'String',flag);
            inputInfo.maxZ = round(str2double(get(hZMax, 'String')));
        end;
    end

    %% --- Executes on xCtr_edit.
    function XCtr_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo button;
        if strcmp(button,'Create File')==1
            h = questdlg('Continuing will destroy dB0-geometry relationship.','Warning','Change','Cancel','Cancel');
%             uiwait(h)
            if strcmp(h,'Change')==1;
                if strcmp(flag,'')==1
                    temp = round(str2double(get(hXCtr, 'String')));
                    if ~isnan(temp)
                        inputInfo.ctrX = temp;
                        set(hXCtr,'String',num2str(temp));
                        updateSliceDisplay();
                    else
                        temp = inputInfo.ctrX;
                        set(hXCtr,'String',num2str(temp));
                    end;
                else
                    set(hXCtr,'String',flag);
                    inputInfo.ctrX = round(str2double(get(hXCtr, 'String')));
                end;
            else
                set(hXCtr,'String',num2str(inputInfo.ctrX));
                return
            end
        else
            if strcmp(flag,'')==1
                temp = round(str2double(get(hXCtr, 'String')));
                if ~isnan(temp)
                    inputInfo.ctrX = temp;
                    set(hXCtr,'String',num2str(temp));
                    updateSliceDisplay();
                else
                    temp = inputInfo.ctrX;
                    set(hXCtr,'String',num2str(temp));
                end;
            else
                set(hXCtr,'String',flag);
                inputInfo.ctrX = round(str2double(get(hXCtr, 'String')));
            end;
        end
    end
    %% --- Executes on yCtr_edit.
    function YCtr_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo button;
        if strcmp(button,'Create File')==1
            h = questdlg('Continuing will destroy dB0-geometry relationship.','Warning','Change','Cancel','Cancel');
%             uiwait(h)
            if strcmp(h,'Change')==1;
                if strcmp(flag,'')==1
                    temp = round(str2double(get(hYCtr, 'String')));
                    if ~isnan(temp)
                        inputInfo.ctrY = temp;
                        set(hYCtr,'String',num2str(temp));
                        updateSliceDisplay();
                    else
                        temp = inputInfo.ctrY;
                        set(hYCtr,'String',num2str(temp));
                    end;
                else
                    set(hYCtr,'String',flag);
                    inputInfo.ctrY = round(str2double(get(hYCtr, 'String')));
                end;
            else
                set(hYCtr,'String',num2str(inputInfo.ctrY));
                return
            end
        else
            if strcmp(flag,'')==1
                temp = round(str2double(get(hYCtr, 'String')));
                if ~isnan(temp)
                    inputInfo.ctrY = temp;
                    set(hYCtr,'String',num2str(temp));
                    updateSliceDisplay();
                else
                    temp = inputInfo.ctrY;
                    set(hYCtr,'String',num2str(temp));
                end;
            else
                set(hYCtr,'String',flag);
                inputInfo.ctrY = round(str2double(get(hYCtr, 'String')));
            end;
        end
    end

    %% --- Executes on zCtr_edit.
    function ZCtr_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo button;
        if strcmp(button,'Create File')==1
            h = questdlg('Continuing will destroy dB0-geometry relationship.','Warning','Change','Cancel','Cancel');
%             uiwait(h)
            if strcmp(h,'Change')==1;
                if strcmp(flag,'')==1
                    temp = round(str2double(get(hZCtr, 'String')));
                    if ~isnan(temp)
                        inputInfo.ctrZ = temp;
                        set(hZCtr,'String',num2str(temp));
                        updateSliceDisplay();
                    else
                        temp = inputInfo.ctrZ;
                        set(hZCtr,'String',num2str(temp));
                    end;
                else
                    set(hZCtr,'String',flag);
                    inputInfo.ctrZ = round(str2double(get(hZCtr, 'String')));
                end;
            else
                set(hZCtr,'String',num2str(inputInfo.ctrZ));
                return
            end
        else
            if strcmp(flag,'')==1
                temp = round(str2double(get(hZCtr, 'String')));
                if ~isnan(temp)
                    inputInfo.ctrZ = temp;
                    set(hZCtr,'String',num2str(temp));
                    updateSliceDisplay();
                else
                    temp = inputInfo.ctrZ;
                    set(hZCtr,'String',num2str(temp));
                end;
            else
                set(hZCtr,'String',flag);
                inputInfo.ctrZ = round(str2double(get(hZCtr, 'String')));
            end;
        end
    end

    function XSet_Callback(source,eventdata,flag) %#ok<INUSL>
        changeFOVOffset(hXSet,'setX',flag);
    end

    function YSet_Callback(source,eventdata,flag) %#ok<INUSL>
        changeFOVOffset(hYSet,'setY',flag);
    end

    function ZSet_Callback(source,eventdata,flag) %#ok<INUSL>
        changeFOVOffset(hZSet,'setZ',flag);
    end

    function changeFOVOffset(control,field,flag)
        global inputInfo;
        if isempty(flag)
            value = str2double(get(control,'String'));
        else
            value = str2double(flag);
        end
        if isreal(value) && isfinite(value)
            inputInfo.(field) = round(value);
        end
        set(control,'String',num2str(inputInfo.(field)));
        if isempty(flag)
            updateSliceDisplay();
            markSequenceDirty();
        end
    end

    %% Sequence and imaging controls
    % --- Executes on hSeqType_Menu.
    function SeqType_Callback(source,eventdata,flag)
        global geoData;

        if strcmp(flag,'')==1
            updateSequenceSpecificFieldLabels();
            updateSeq();
            if ~isempty(geoData)
                syncSlicePosition();
                refreshGeometryDisplay();
            end
        else
            tempStr = get(hSeqType,'String');
            flag = normalizeSequenceDisplayName(flag);
            temp = find(strcmp(tempStr,flag));
            if ~isempty(temp)
                set(hSeqType,'Value',temp(1));
            end
            updateSequenceSpecificFieldLabels();
            if ~isempty(geoData)
                refreshGeometryDisplay();
            end
            clear tempStr temp;
        end;
    end

    function updateSequenceSpecificFieldLabels()
        updateRadialAxisControls();
        if sequenceUsesTI(getCurrentSequenceName()) && strcmpi(get(hSeqType,'Enable'),'on')
            set(hTILabel,'Enable','on');
            set(hTI,'Enable','on');
        else
            set(hTILabel,'Enable','off');
            set(hTI,'Enable','off');
        end

        if is3DRadSequenceName(getCurrentSequenceName())
            set([hRadialResolutionLabel,hRadialResolution],'Visible','on');
            set(hRadialResolution,'Enable',get(hSeqType,'Enable'));
            set([hPEDirectLabel,hPEDirectMenu],'Visible','off');
            set(hOrientationMenu,'Value',1,'Enable','off');
            set(hPEDirectMenu,'String',{'Not used'},'Value',1,'Enable','off');
            fovValue = get(hFOV,'Value');
            if isempty(fovValue)
                fovValue = str2double(get(hFOV,'String'));
            end
            fovValue = fovValue(~isnan(fovValue));
            if isempty(fovValue)
                fovValue = 300;
            end
            isoFov = max(fovValue);
            set(hFOV_Pop,'String','FOV Iso. (mm)','Value',1);
            set(hFOV,'Value',[isoFov isoFov],'String',sprintf('%1.0f',isoFov));
            set(hMatSize_Pop,'String','Num Samples|Num Spokes');
        else
            set([hRadialResolutionLabel,hRadialResolution],'Visible','off');
            set([hPEDirectLabel,hPEDirectMenu],'Visible','on');
            set(hOrientationMenu,'Enable','on');
            setCartesianPEDirectionOptions();
            set(hFOV_Pop,'String','FOV FE|PE (mm)','Value',min(get(hFOV_Pop,'Value'),2));
            set(hMatSize_Pop,'String','MatSize FE|PE');
        end
    end

    function restored = updateRadialAxisControls()
        axesControls = [hFE,hPE,hSS];
        restored = false;
        if is3DRadSequenceName(getCurrentSequenceName())
            restored = any(cell2mat(get(axesControls,'Value')) ~= 1);
            set(axesControls,'Value',1,'Enable','off');
        else
            set(axesControls,'Enable',get(hSeqType,'Enable'));
        end
    end

    function setCartesianPEDirectionOptions()
        currentOptions = get(hPEDirectMenu,'String');
        currentValue = get(hPEDirectMenu,'Value');
        if ischar(currentOptions)
            currentOptions = cellstr(currentOptions);
        end
        currentValue = min(max(1,currentValue),numel(currentOptions));
        currentSelection = currentOptions{currentValue};

        switch get(hOrientationMenu,'Value')
            case 1
                newOptions = {'P--A';'A--P';'L--R';'R--L'};
            case 2
                newOptions = {'P--A';'A--P';'F--H';'H--F'};
            otherwise
                newOptions = {'L--R';'R--L';'F--H';'H--F'};
        end
        newValue = find(strcmp(newOptions,currentSelection),1);
        if isempty(newValue)
            newValue = 1;
        end
        set(hPEDirectMenu,'String',newOptions,'Value',newValue,'Enable','on');
    end

    function sequenceName = getCurrentSequenceName()
        tempStr = get(hSeqType,'String');
        tempVal = get(hSeqType,'Value');

        if ischar(tempStr)
            tempStr = cellstr(tempStr);
        end

        if isempty(tempStr)
            sequenceName = '';
        else
            tempVal = min(max(1,tempVal),numel(tempStr));
            sequenceName = tempStr{tempVal};
        end
    end

    function tf = is3DRadSequenceName(sequenceName)
        normalizedName = strtrim(sequenceName);
        tf = usesRadial3DWorkflow(normalizedName);
    end

    function tf = sequenceUsesTI(sequenceName)
        % Add a sequence here only when its waveform contains an inversion
        % pulse whose timing is controlled by the TI input.
        inversionTimeSequences = {};
        tf = any(strcmpi(strtrim(sequenceName),inversionTimeSequences));
    end

    function sequenceName = normalizeSequenceDisplayName(sequenceName)
        sequenceName = strtrim(sequenceName);
    end

    function modeName = getCurrentModeName()
        modeStrings = get(hMode,'String');
        modeValue = get(hMode,'Value');
        if ischar(modeStrings)
            modeStrings = cellstr(modeStrings);
        end
        modeValue = min(max(1,modeValue),numel(modeStrings));
        modeName = modeStrings{modeValue};
    end

    function logSetup(message,varargin)
        writeSetupLog(1,'',message,varargin{:});
    end

    function warnSetup(message,varargin)
        writeSetupLog(2,'WARNING: ',message,varargin{:});
    end

    function writeSetupLog(stream,prefix,message,varargin)
        if nargin > 3 && ~isempty(varargin)
            message = sprintf(message,varargin{:});
        end
        fprintf(stream,'[Setup %s] %s%s\n',datestr(now,'HH:MM:SS'),prefix,message);
    end

    function count = countInputFiles(inputIndex)
        count = numel(buildInputFileList(inputCmd{inputIndex,1},inputCmd{inputIndex,2}));
    end

    function fileText = formatInputFileForLog(inputIndex)
        files = buildInputFileList(inputCmd{inputIndex,1},inputCmd{inputIndex,2});
        if isempty(files)
            fileText = '(none)';
        elseif numel(files) == 1
            fileText = files{1};
        else
            fileText = sprintf('%d files',numel(files));
        end
    end

    %% --- Executes on hB0Edit_Editbox.
    function B0Edit_Callback(source,eventdata,flag)
        if strcmp(flag,'')==1
            temp = str2double(get(hB0Edit,'String'));
            if ~isnan(temp)        
                set(hB0Edit,'String',num2str(abs(temp)));
            else
                set(hB0Edit,'String','3');
            end;
        else
            set(hB0Edit,'String',flag); 
        end;
        updateLarmorTooltips();
    end
    
    %% --- Executes on hNucleus_Menu.
    function Nucleus_Callback(source,eventdata,flag) %#ok<INUSD,INUSD>
        if strcmp(flag,'')==1
            updateLarmorTooltips();
            updateReadoutTooltips();
            updateTargetFlipAngleDisplay();
            markSequenceDirty();
            return;
        end

        tempStr = get(hNucleus,'String');
        temp = find(strcmp(tempStr,strtrim(flag)));
        if isempty(temp)
            error('Setup:UnsupportedNucleus','Nucleus %s is absent from config/nuclei.yaml.',strtrim(flag));
        end
        set(hNucleus,'Value',temp(1));
        updateLarmorTooltips();
        updateTargetFlipAngleDisplay();
    end

    function nucleus = getCurrentNucleus()
        tempStr = get(hNucleus,'String');
        nucleus = tempStr{get(hNucleus,'Value')};
    end

    %% --- Executes on hRF_Shape_Menu.
    function RF_Shape_Callback(source,eventdata,flag)
        if strcmp(flag,'')==1
            updateSeq();
        else
            tempStr = get(hRF_Shape,'String');
            temp = find(strcmp(tempStr,flag));
            set(hRF_Shape,'Value',temp);
            clear tempStr temp;
        end;
    end
    
    %% --- Executes on hRF_Duration_Editbox.
    function RF_Duration_Callback(source,eventdata,flag)
        if strcmp(flag,'')==1
            temp = str2double(get(hRF_Duration,'String'));
            if ~isnan(temp)
                set(hRF_Duration,'String',num2str(abs(temp)));
            else
                set(hRF_Duration,'String','2.6');
            end;
            updateSeq();
        else
            set(hRF_Duration,'String',flag); 
        end;
    end

    %% --- Executes on hRF_Num_Editbox.
    function RF_Num_Callback(source,eventdata,flag)
        if strcmp(flag,'')==1
            temp = str2double(get(hRF_Num,'String'));
            if ~isnan(temp)
                set(hRF_Num,'String',num2str(round(abs(temp))));
            else
                set(hRF_Num,'String','512');
            end;
            updateSeq();
        else
            set(hRF_Num,'String',flag); 
        end;
    end

    %% --- Executes on hRF_FA_Editbox.
    function RF_FA_Callback(source,eventdata,flag)
        if strcmp(flag,'')==1
            temp = str2double(get(hRF_FA,'String'));
            if ~isnan(temp)
                set(hRF_FA,'String',num2str(abs(temp)));
                updateTargetB1FromFlipAngle(abs(temp));
            else
                set(hRF_FA,'String','90');
                updateTargetB1FromFlipAngle(90);
            end;
            updateSeq();
        else
            set(hRF_FA,'String',flag); 
        end;
    end

    %% --- Executes on hTargetB1_Editbox.
    function TargetB1_Callback(source,eventdata,flag)
        if strcmp(flag,'')==1
            tempStr = strtrim(get(hTargetB1,'String'));
        else
            tempStr = strtrim(flag);
        end

        if isempty(tempStr)
            set(hTargetB1,'String','');
        else
            temp = str2double(tempStr);
            if ~isnan(temp)
                set(hTargetB1,'String',num2str(abs(temp)));
            else
                set(hTargetB1,'String','');
            end
        end

        updateTargetFlipAngleDisplay();
        if strcmp(flag,'')==1
            updateFlipAngleFromTargetB1();
        end
        if strcmp(flag,'')==1
            markSequenceDirty();
        end
    end

    %% --- Executes on hTI_Duration_Editbox.
    function TI_Duration_Callback(source,eventdata,flag)
        if strcmp(flag,'')==1
            temp = str2double(get(hTI,'String'));
            if ~isnan(temp)
                if abs(temp) ~= 0
                    set(hTI,'String',num2str(abs(temp)));
                else
                    set(hTI,'String','10');
                end;
            else
                set(hTI,'String','10');
            end;
            updateSeq();
        else
            set(hTI,'String',flag);
        end;
    end
%% --- Executes on Match button.
    function Match_Callback(source,eventdata,flag) %#ok<INUSD>
        global geoData inputInfo displayInfo;
        bufferVoxels = 2;
        [center,width] = fovBox(inputInfo,fovDisplaySettings(displayInfo),get(hOrientationMenu,'Value'));
        fullMin = [displayInfo.minX, displayInfo.minY, displayInfo.minZ];
        fullMax = [displayInfo.maxX, displayInfo.maxY, displayInfo.maxZ];
        minBounds = max(fullMin,floor(center-width/2+0.5)-bufferVoxels);
        maxBounds = min(fullMax,ceil(center+width/2-0.5)+bufferVoxels);
        if any(minBounds > maxBounds)
            warnSetup('The FOV and its padding lie outside the available geometry.');
            return;
        end

        inputInfo.minX = minBounds(1);
        inputInfo.maxX = maxBounds(1);
        inputInfo.minY = minBounds(2);
        inputInfo.maxY = maxBounds(2);
        inputInfo.minZ = minBounds(3);
        inputInfo.maxZ = maxBounds(3);

        set(hXMin,'string',num2str(inputInfo.minX));
        set(hXMax,'string',num2str(inputInfo.maxX));
        set(hYMin,'string',num2str(inputInfo.minY));
        set(hYMax,'string',num2str(inputInfo.maxY));
        set(hZMin,'string',num2str(inputInfo.minZ));
        set(hZMax,'string',num2str(inputInfo.maxZ));

        refreshGeometryDisplay();
    end

    function overlaps = signalBoxOverlapsFOV()
        global inputInfo displayInfo;
        [center,width] = fovBox(inputInfo,fovDisplaySettings(displayInfo),get(hOrientationMenu,'Value'));
        signalMin = [inputInfo.minX, inputInfo.minY, inputInfo.minZ] - 0.5;
        signalMax = [inputInfo.maxX, inputInfo.maxY, inputInfo.maxZ] + 0.5;
        overlaps = all(max(signalMin,center-width/2) < min(signalMax,center+width/2));
    end

    %% --- Executes on hFOV_Pop_popmenu.
    function FOV_Pop_Callback(source,eventdata,flag)
        global geoData inputInfo displayInfo;
        if strcmp(flag,'')==1
            val = get(hFOV_Pop,'Value');
            FOV=get(hFOV,'value');
            PE=get(hPEDirectMenu,'Value');
            if is3DRadSequenceName(getCurrentSequenceName())
                isoFov = max(FOV);
                if isempty(isoFov) || isnan(isoFov)
                    isoFov = str2double(get(hFOV,'String'));
                end
                if isnan(isoFov) || isoFov == 0
                    isoFov = 300;
                end
                set(hFOV_Pop,'Value',1);
                set(hFOV,'Value',[isoFov isoFov],'String',sprintf('%1.0f',isoFov));
                return;
            end
            switch val
                case 1   % User selected the first item
%                     if PE==1
                        if isempty(FOV)
                            FOV=get(hFOV,'Value');
                            set(hFOV,'value',FOV);
                        else
                            set(hFOV,'string',sprintf('%1.0f',FOV(1)));
%                             switch get(hOrientationMenu,'Value')
%                                 case 1
%                                     set(hFOV,'string',sprintf('%1.0f',FOV(1)));
%                                 case 2
%                                     set(hFOV,'string',sprintf('%1.0f',FOV(2)));
%                                 case 3
%                                     set(hFOV,'string',sprintf('%1.0f',FOV(2)));
%                             end
                        end
%                     else
%                         if FOV==0
%                             FOV=str2double(get(hFOV,'string'));
%                             FOV(2)=FOV;
%                             set(hFOV,'value',FOV);
%                         else
%                             if length(FOV)>1
%                                 set(hFOV,'string',sprintf('%1.0f',FOV(2)));
% %                                 switch get(hOrientationMenu,'Value')
% %                                     case 1
% %                                         set(hFOV,'string',sprintf('%1.0f',FOV(2)));
% %                                     case 2
% %                                         set(hFOV,'string',sprintf('%1.0f',FOV(1)));
% %                                     case 3
% %                                         set(hFOV,'string',sprintf('%1.0f',FOV(1)));
% %                                 end
%                             else
%                                 FOV(2)=FOV;
%                                 set(hFOV,'string',sprintf('%1.0f',FOV(2)));
%                                 set(hFOV,'value',FOV);
%                             end
%                         end
%                     end
                case 2   % User selected the second item
%                     if PE==1
                        if FOV==0
                            FOV=str2double(get(hFOV,'string'));
                            FOV(2)=FOV;
                            set(hFOV,'value',FOV);
                        else
                            if length(FOV)>1
                                set(hFOV,'string',sprintf('%1.0f',FOV(2)));
%                                 switch get(hOrientationMenu,'Value')
%                                     case 1
%                                         set(hFOV,'string',sprintf('%1.0f',FOV(2)));
%                                     case 2
%                                         set(hFOV,'string',sprintf('%1.0f',FOV(1)));
%                                     case 3
%                                         set(hFOV,'string',sprintf('%1.0f',FOV(1)));
%                                 end
                            else
                                FOV(2)=FOV;
                                set(hFOV,'string',sprintf('%1.0f',FOV(2)));
                                set(hFOV,'value',FOV);
                            end
                        end
%                     else
%                         if isempty(FOV)
%                             FOV=get(hFOV,'Value');
%                             set(hFOV,'value',FOV);
%                         else
%                             set(hFOV,'string',sprintf('%1.0f',FOV(1)));
% %                             switch get(hOrientationMenu,'Value')
% %                                 case 1
% %                                     set(hFOV,'string',sprintf('%1.0f',FOV(1)));
% %                                 case 2
% %                                     set(hFOV,'string',sprintf('%1.0f',FOV(2)));
% %                                 case 3
% %                                     set(hFOV,'string',sprintf('%1.0f',FOV(2)));
% %                             end
%                         end
%                     end
            end
        end
    end

    %% --- Executes on hFOV_Editbox.
    function FOV_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo;
        tempStr = get(hFOV_Pop,'value');
        temp = tempStr;
        if strcmp(flag,'')==1
            FOV=get(hFOV,'value');
            if is3DRadSequenceName(getCurrentSequenceName())
                FOVtemp=str2double(get(hFOV,'String'));
                if isnan(FOVtemp)
                    set(hFOV,'String','300');
                    FOVtemp = 300;
                elseif FOVtemp==0
                    FOVtemp=1;
                    set(hFOV,'string',sprintf('%1.0f',FOVtemp));
                end
                FOV = [FOVtemp FOVtemp];
                set(hFOV,'Value',FOV,'String',sprintf('%1.0f',FOVtemp));
                inputInfo.FOV=FOV;
                displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
                updateSeq();
                return;
            end
            switch temp
                case 1 %FE
                    FOVtemp=str2double(get(hFOV,'String'));
                    if FOVtemp==0
                        FOVtemp=1;
                        set(hFOV,'string',sprintf('%1.0f',FOVtemp));
                    end
                    FOV(1)=FOVtemp;
                    if length(FOV)<2
                        FOV(2)=FOVtemp;
                    end
                    if ~isnan(FOV(1))
                        set(hFOV,'value',FOV);
                    else
                        set(hFOV,'String','300');
                    end;
                        inputInfo.FOV=FOV;
                        displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
                case 2 %PE
                    FOVtemp=str2double(get(hFOV,'String'));
                    if FOVtemp==0
                        FOVtemp=1;
                        set(hFOV,'string',sprintf('%1.0f',FOVtemp));
                    end
                    FOV(2)=FOVtemp;
                    if length(FOV)<2
                        FOV(1)=FOVtemp;
                    end
                    if ~isnan(FOV(2))
                        set(hFOV,'value',FOV);
                    else
                        set(hFOV,'String','300');
                    end;
                    inputInfo.FOV = FOV;
                    displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
            end
            updateSeq();
        else
            flag=sscanf(flag,'%f');
            if is3DRadSequenceName(getCurrentSequenceName())
                flag = max(flag);
                flag = [flag flag];
            end
            set(hFOV,'Value',flag,'String',num2str(flag(min(temp,numel(flag)))));
            inputInfo.FOV = flag;
        end;
    end
    %% Matrix size is stored in logical FE/PE order (samples/spokes for radial).
    function MatSize_Pop_Callback(source,eventdata,flag) %#ok<INUSD>
        matrixSize = get(hMatSize,'Value');
        index = get(hMatSize_Pop,'Value');
        set(hMatSize,'String',num2str(matrixSize(index)));
    end

    function MatSize_Callback(source,eventdata,flag) %#ok<INUSL>
        index = get(hMatSize_Pop,'Value');
        if isempty(flag)
            matrixSize = get(hMatSize,'Value');
            value = str2double(get(hMatSize,'String'));
            if isreal(value) && isfinite(value) && value >= 0 && value == fix(value)
                matrixSize(index) = max(1,value);
            end
        else
            matrixSize = sscanf(flag,'%f').';
            if isscalar(matrixSize)
                matrixSize(2) = matrixSize(1);
            end
        end
        set(hMatSize,'Value',matrixSize,'String',num2str(matrixSize(index)));
        if isempty(flag)
            updateSeq();
        end
    end

    %% --- Executes on hADC_Freq_Editbox.
    function ADC_Freq_Callback(source,eventdata,flag) %#ok<INUSL>
        if strcmp(flag,'')==1
            temp = str2double(get(hADC_Freq,'String'));
            if ~isnan(temp)
                set(hADC_Freq,'String',num2str(abs(temp)));
            else
                set(hADC_Freq,'String','50');
            end;
            updateSeq();
        else
            set(hADC_Freq,'String',flag); 
        end;
    end

    function radialResolutionCallback(source,~)
        try
            setRadialResolutionText(get(source,'String'));
        catch ME
            set(source,'String',get(source,'UserData'));
            errordlg(ME.message,'RAD_3D acquisition resolution');
            return;
        end
        updateSeq();
    end

    function setRadialResolutionText(text)
        text = strtrim(text);
        parseRadialResolutionMm(text);
        set(hRadialResolution,'String',text,'UserData',text);
    end

    function resetRadialResolutionControls()
        set(hRadialResolution,'String','','UserData','');
        set([hRadialResolutionLabel,hRadialResolution],'Visible','off');
        set([hPEDirectLabel,hPEDirectMenu],'Visible','on');
    end

    %% --- Executes on hTx_Editbox.
    function hTx_Callback(source,eventdata,flag) %#ok<INUSL>
        if strcmp(flag,'')==1
            temp = str2double(get(hTx,'String'));
            if ~isnan(temp)
                set(hTx,'String',num2str(round(abs(temp))));
            else
                set(hTx,'String','1');
            end;
        else
            set(hTx,'String',flag); 
        end;
        
        Tx.Num = str2double(get(hTx,'String'));
        Tx.MagMat = ones(Tx.Num,1);
        Tx.PhsMat = zeros(Tx.Num,1);
        Tx.RefB1 = NaN;
        if strcmp(flag,'')==1
            logSetup('Set #Tx to %d. Reload B1+/E1+ files if needed.', Tx.Num);
            markSequenceDirty();
        end
        updateTargetFlipAngleDisplay();
    end

    %% --- Executes on hRx_Editbox.
    function hRx_Callback(source,eventdata,flag) %#ok<INUSL>
        if strcmp(flag,'')==1
            temp = str2double(get(hRx,'String'));
            if ~isnan(temp)
                set(hRx,'String',num2str(round(abs(temp))));
            else
                set(hRx,'String','1');
            end;
        else
            set(hRx,'String',flag); 
        end;
        
        Rx.Num = str2double(get(hRx,'String'));
        if strcmp(flag,'')==1
            logSetup('Set #Rx to %d. Reload B1-/E1- files if needed.', Rx.Num);
            markSequenceDirty();
        end
    end

    %% --- Executes on hSS_Checkbox.
    function SS_Callback(source,eventdata,flag) %#ok<INUSL>
        if strcmp(flag,'')==1
            updateSeq();
            refreshGeometryDisplay();
        else
            set(hSS,'Value',str2double(flag)); 
        end;
    end

    %% --- Executes on hFE_Checkbox.
    function FE_Callback(source,eventdata,flag) %#ok<INUSL>
        if strcmp(flag,'')==1
            updateSeq();
        else
            set(hFE,'Value',str2double(flag)); 
        end;
    end  

    %% --- Executes on hPE_Checkbox.
    function PE_Callback(source,eventdata,flag) %#ok<INUSL>
        if strcmp(flag,'')==1
            updateSeq();
        else
            set(hPE,'Value',str2double(flag)); 
        end;
    end  

    %% --- Executes on hTE_Editbox.
    function TE_Callback(source,eventdata,flag) %#ok<INUSL>
        if strcmp(flag,'')==1
            temp = str2double(get(hTE,'String'));
            if ~isnan(temp)
                set(hTE,'String',num2str(abs(temp)));
            else
                set(hTE,'String','10');
            end;
            updateSeq();
        else
            set(hTE,'String',flag); 
        end;
    end  

    %% --- Executes on hTR_Editbox.
    function TR_Callback(source,eventdata,flag) %#ok<INUSL>
        if strcmp(flag,'')==1
            temp = str2double(get(hTR,'String'));
            if ~isnan(temp)
                set(hTR,'String',num2str(abs(temp)));
            else
                set(hTR,'String','500');
            end;
            updateSeq();
        else
            set(hTR,'String',flag); 
        end;
    end  

    %% --- Executes on hDummyNum_Editbox.
    function DummyNum_Callback(source,eventdata,flag) %#ok<INUSL>
        if strcmp(flag,'')==1
            temp = str2double(get(hDummyNum,'String'));
            if ~isnan(temp)
                set(hDummyNum,'String',num2str(round(abs(temp))));
            else
                set(hDummyNum,'String','0');
            end;
            markSequenceDirty();
        else
            set(hDummyNum,'String',flag);
        end;
    end

    %% --- Executes on PEDirectMenu
    function PEDirectMenu_Callback(source,eventdata,flag) %#ok<INUSL>
        global geoData inputInfo displayInfo;
        if strcmp(flag,'')==1
            markSequenceDirty();
        else
            tempStr = get(hPEDirectMenu,'String');
            temp = find(strcmp(tempStr,flag),1);
            if ~isempty(temp)
                set(hPEDirectMenu,'Value',temp);
            end
        end

        if isempty(inputInfo.FOV)
            inputInfo.FOV = get(hFOV,'Value');
        end

        FOV_Callback(source,eventdata,num2str(get(hFOV,'Value')));
        FOV_Pop_Callback(source,eventdata,'');
        displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
    end

    %% Sequence generation and preview
    % --- Executes on hSeqGen_Button.
    function SeqGen_Callback(source,eventdata) %#ok<INUSD,INUSD>
        global inputInfo displayInfo;
        updateRadialAxisControls();
        if strcmp(getCurrentSequenceName(),'SE')
            updateSeq(); % Loaded short-timing protocols use the corrected limits.
        end
                
        cd(addr);
        
        requestedFlipAngle = str2double(get(hRF_FA,'String')); % degrees
        [MagMat, PhsMat,RefB1,index] = TxMagPhsGUI(Tx.Num,Tx.MagMat,Tx.PhsMat,requestedFlipAngle,Tx.RefB1);

        if index ~= 0
            [~,~,txScaleError] = getEffectiveTxMagMat(MagMat,RefB1);
            if ~isempty(txScaleError)
                warnSetup('Sequence generation cancelled: %s', txScaleError);
                uiwait(errordlg(txScaleError,'Tx Scaling','modal'));
                return;
            end

            beginBusyState('Generating sequence...');
            logSetup('Generating sequence: %s, nucleus=%s, FOV=%s mm, MatSize=%s, BW=%g kHz, Tx=%d, Rx=%d', ...
                getCurrentSequenceName(), getCurrentNucleus(), mat2str(get(hFOV,'Value')), ...
                mat2str(get(hMatSize,'Value')), str2double(get(hADC_Freq,'String')), Tx.Num, Rx.Num);
            seqGenBusyCleanup = onCleanup(@() endBusyState()); %#ok<NASGU>
            Tx.MagMat = MagMat;
            Tx.PhsMat = PhsMat;
            Tx.RefB1 = RefB1;
            updateTargetFlipAngleDisplay();
            
            set(hTx,'Enable','off');
            set(hRx,'Enable','off');
            
            settings = readSequenceControls();
            TI.duration = str2double(get(hTI,'String')); % ms
            sequenceName = getCurrentSequenceName();
            isRadial3D = is3DRadSequenceName(sequenceName);
            if isRadial3D
                peDirection = {'P--A'};
                sequenceOrientation = 1;
            else
                temp = get(hPEDirectMenu,'String');
                peDirection = temp(get(hPEDirectMenu,'Value'));
                sequenceOrientation = get(hOrientationMenu,'Value');
                clear temp;
            end
            slice = readSequenceSlice(inputInfo);
            sequenceIndex = get(hSeqType,'Value');
            sequenceState.previewWaveform = dispatchSequence(sequenceName,sequenceIndex,settings,slice,TI);

            set(hSeqPlot,'Enable','on');
            displayInfo.HideFOVOverlay = false;

            updateBusyState('Converting sequence...');
            finalSeqData = combineSeqRect(sequenceState.previewWaveform,sequenceOrientation,peDirection,settings.Dummy,isRadial3D);

            updateBusyState('Writing sequence file...');
            if ~expSeq(finalSeqData,settings.Dummy,Tx,Rx)
                warnSetup('Sequence export did not complete. Check Tx scaling and sequence inputs.');
                return;
            end
            logSetup('Wrote sequence file: %s', [protocolRoot,'\',get(hStudyName,'String'),'\',get(hStudyName,'String'),'.seqn']);

            % inputCmd{5,1}=''; inputCmd{5,2}=''; % B1+ FileName
            % inputCmd{6,1}=''; inputCmd{6,2}=''; % E1+ FileName
            % inputCmd{7,1}=''; inputCmd{7,2}=''; % B1- FileName
            % inputCmd{8,1}=''; inputCmd{8,2}=''; % E1- FileName
            
            if ~isempty(inputCmd{1,1}) && ~isempty(inputCmd{2,1})
                set(hRun,'Enable','on');
            end;

            set(hExpSeqEdit,'String',get(hStudyName,'String'),'FontAngle','normal');
            inputCmd{4,2} = [get(hStudyName,'String'),'.seqn'];
            inputCmd{4,1} = [protocolRoot,'\',get(hStudyName,'String'),'\']; %%---
            sequenceState.radialRestorationPending = false;
            markSequenceClean();

            set(hSeqPlot,'Enable','on');

            set(hMode,'Enable','on');
            tempMode = get(hMode,'Value');
            switch tempMode
                case 1
                    set(hB0Edit,'Enable','on');
                    set(hNucleus,'Enable','on');
                    set(hExpDB0,'Enable','on');
                    
                    set(hExpB1m,'Enable','on');
                    
                    set(hExpGx,'Enable','on');
                    set(hExpGy,'Enable','on');
                    set(hExpGz,'Enable','on');

                    set(hExpB1p,'Enable','on');
                    
                    set(hExpE1p,'Enable','off');
                    set(hExpE1pEdit,'String','E1+ Filename(s)','FontAngle','italic');
                    clearInputFileSelection(6);
                    
                    set(hExpE1m,'Enable','off');
                    set(hExpE1mEdit,'String','E1- Filename(s)','FontAngle','italic');
                    clearInputFileSelection(8);

                    set(hNumIso,'Enable','on');
                    set(hCPU,'Enable','on');
                    set(hSignalGPU,'Enable','on');
                    set(hNEX,'Enable','off');

                case 2
                    set(hB0Edit,'Enable','off');
                    set(hNucleus,'Enable','off');
                    set(hExpDB0,'Enable','off');
                                       
                    set(hExpGx,'Enable','off');
                    set(hExpGy,'Enable','off');
                    set(hExpGz,'Enable','off');

                    set(hExpB1p,'Enable','on');
                    set(hExpB1m,'Enable','on');
                    
                    set(hExpE1p,'Enable','on');
                    % set(hExpE1pEdit,'String','E1+ Filename(s)','FontAngle','italic');
                    
                    set(hExpE1m,'Enable','off');
                    set(hExpE1mEdit,'String','E1- Filename(s)','FontAngle','italic');
                    clearInputFileSelection(8);
                    
                    set(hNumIso,'Enable','off');
                    set(hCPU,'Enable','on');
                    set(hSignalGPU,'Enable','off');
                    set(hNEX,'Enable','off');

                case 3
                    set(hB0Edit,'Enable','off');
                    set(hNucleus,'Enable','off');
                    set(hExpDB0,'Enable','off');
                                         
                    set(hExpB1m,'Enable','off');
                    
                    set(hExpGx,'Enable','off');
                    set(hExpGy,'Enable','off');
                    set(hExpGz,'Enable','off');

                    set(hExpB1p,'Enable','off');
                    
                    set(hExpE1p,'Enable','off');
                    set(hExpE1pEdit,'String','E1+ Filename(s)','FontAngle','italic');
                    clearInputFileSelection(6);
                    
                    set(hExpE1m,'Enable','on');
                    if isempty(inputCmd{8,1})
                        set(hExpE1mEdit,'string','E1- Filename(s)','FontAngle','italic');
                    end
                    
                    set(hNumIso,'Enable','off');
                    set(hCPU,'Enable','off');
                    set(hSignalGPU,'Enable','off');
                    set(hNEX,'Enable','on');
            end;

            if ~isempty(inputCmd{1,1}) && ~isempty(inputCmd{2,1})
                set(hRun,'Enable','on');
                if tempMode ~= 3
                    set(hCPU,'Enable','on');
                end
            end;
        end
    end


%% --- Executes on hSeqPlot_Button.
function SeqPlot_Callback(source,eventdata)
    if ~ensureCurrentSequence(source,eventdata,'plotting','Sequence plot cancelled')
        return;
    end

    beginBusyState('Rendering sequence plot...');
    seqPlotBusyCleanup = onCleanup(@() endBusyState()); %#ok<NASGU>
    renderSequencePreview(sequenceState.previewWaveform);
end

function renderSequencePreview(interSeqData)
    % ---- NEW: how many excitations/TRs to plot ----
    nex = 16;  % plot first 16 RF excitations (edit as desired)

    if plotExcitationPreview(interSeqData,nex)
        return;
    end

    if isfield(interSeqData.Main,'repeat')
        nex = min(nex, interSeqData.Main.repeat);
    end

    % ---- Helper: build cumulative time from tStep ----
    cumTime = @(tStep) [0, cumsum(tStep)];

    % ---- One-TR time axes (relative within a TR) ----
    tADC1  = cumTime(interSeqData.Main.ADC.tStep);
    tRF1   = cumTime(interSeqData.Main.RF.tStep);
    tDF1   = cumTime(interSeqData.Main.DFreq.tStep);
    tSS1   = cumTime(interSeqData.Main.Gss.tStep);
    tPE1   = cumTime(interSeqData.Main.Gpe.tStep);
    tFE1   = cumTime(interSeqData.Main.Gfe.tStep);

    % TR length: safest is use interSeqData.TR if present; otherwise infer from RF tSteps sum
    if isfield(interSeqData,'TR')
        TRms = interSeqData.TR;
    else
        TRms = sum(interSeqData.Main.RF.tStep);
    end

    % ---- Normalize per-TR waveforms (same as your original logic) ----
    RF1 = abs(interSeqData.Main.RF.value);
    RF1 = RF1 ./ max(RF1 + (max(RF1)==0));  % avoid divide-by-zero

    DFreq1 = interSeqData.Main.DFreq.value;
    if max(abs(DFreq1)) ~= 0, DFreq1 = DFreq1 ./ max(abs(DFreq1)); end

    SS1 = interSeqData.Main.Gss.value;
    if max(abs(SS1)) ~= 0, SS1 = SS1 ./ max(abs(SS1)); end

    % NOTE: PE/FE are handled per excitation if increments exist, so only keep base here
    ADC1 = interSeqData.Main.ADC.value;

    % ---- Diffs for vertical transition drawing ----
    dRF1    = diff([0, abs(interSeqData.Main.RF.value)]);
    dDFreq1 = diff([0, abs(interSeqData.Main.DFreq.value)]);
    dSS1    = diff([0, interSeqData.Main.Gss.value]);
    dADC1   = diff([0, interSeqData.Main.ADC.value]);

    % ---- Figure ----
    hSeqPlotFig=figure('Visible','on','MenuBar','none','Name','Sequence Plot',...
        'NumberTitle','off','Position',[100,100,1000,800],'Resize','off',...
        'Toolbar','figure','Color',[1,1,1]);
    movegui(hSeqPlotFig,'center');

    timeMax = nex*TRms * 5/4;
    xlim([0 timeMax]);
    ylim([-0.5 15.0]);
    set(gca,'YTickLabelMode','manual');
    set(gca,'YTick',[0.3;1.7;4;6.6;9.2;11.8;13.5]);
    set(gca,'YTickLabel',{'Events';'Acq';'FE';'PE';'SS';'DFreq';'RF'});

    hold on;
    
    PEref = interSeqData.Main.Gpe.value;
    FEref = interSeqData.Main.Gfe.value;

    peScale = max(abs(PEref));
    feScale = max(abs(FEref));
    if peScale==0, peScale=1; end
    if feScale==0, feScale=1; end
    
    % ---- Plot nex TRs ----
    for k = 1:nex
        t0 = (k-1)*TRms;

        % --- RF ---
        for t=1:length(tRF1)-1
            line([t0+tRF1(t), t0+tRF1(t+1)], [RF1(t),RF1(t)]+13.5,...
                'LineStyle','-','linewidth',3,'color',[60 42 196]/255);
            if dRF1(t)~=0
                line([t0+tRF1(t), t0+tRF1(t)], [RF1(t-1),RF1(t)]+13.5,...
                    'LineStyle','-','linewidth',3,'color',[60 42 196]/255);
            end
        end

        % --- DFreq ---
        for t=1:length(tDF1)-1
            line([t0+tDF1(t), t0+tDF1(t+1)], [DFreq1(t),DFreq1(t)]+11.8,...
                'LineStyle','-','linewidth',3,'color',[60 42 196]/255);
            if dDFreq1(t)~=0
                line([t0+tDF1(t), t0+tDF1(t)], [DFreq1(t-1),DFreq1(t)]+11.8,...
                    'LineStyle','-','linewidth',3,'color',[60 42 196]/255);
            end
        end

        % --- SS ---
        for t=1:length(tSS1)-1
            line([t0+tSS1(t), t0+tSS1(t+1)], [SS1(t),SS1(t)]+9.2,...
                'LineStyle','-','linewidth',3,'color',[0 125 197]/255);
            if dSS1(t)~=0
                line([t0+tSS1(t), t0+tSS1(t)], [SS1(t-1),SS1(t)]+9.2,...
                    'LineStyle','-','linewidth',3,'color',[0 125 197]/255);
            end
        end

        % --- PE/FE (apply increments per excitation if present) ---
        PEk = interSeqData.Main.Gpe.value;
        if isfield(interSeqData.Main.Gpe,'increment')
            PEk = PEk + (k-1)*interSeqData.Main.Gpe.increment;
        end
        FEk = interSeqData.Main.Gfe.value;
        if isfield(interSeqData.Main.Gfe,'increment')
            FEk = FEk + (k-1)*interSeqData.Main.Gfe.increment;
        end

        % Normalize each TR for display consistency
%         PEkN = PEk; if max(abs(PEkN))~=0, PEkN = PEkN./max(abs(PEkN)); end
%         FEkN = FEk; if max(abs(FEkN))~=0, FEkN = FEkN./max(abs(FEkN)); end
        PEkN = PEk / peScale;
        FEkN = FEk / feScale;        
        dPEk = diff([0, PEk]);
        dFEk = diff([0, FEk]);

        for t=1:length(tPE1)-1
            line([t0+tPE1(t), t0+tPE1(t+1)], [PEkN(t),PEkN(t)]+6.6,...
                'LineStyle','-','linewidth',3,'color',[237 24 73]/255);
            if dPEk(t)~=0
                line([t0+tPE1(t), t0+tPE1(t)], [PEkN(max(t-1,1)),PEkN(t)]+6.6,...
                    'LineStyle','-','linewidth',3,'color',[237 24 73]/255);
            end
        end

        for t=1:length(tFE1)-1
            line([t0+tFE1(t), t0+tFE1(t+1)], [FEkN(t),FEkN(t)]+4,...
                'LineStyle','-','linewidth',3,'color',[0 169 79]/255);
            if dFEk(t)~=0
                line([t0+tFE1(t), t0+tFE1(t)], [FEkN(max(t-1,1)),FEkN(t)]+4,...
                    'LineStyle','-','linewidth',3,'color',[0 169 79]/255);
            end
        end

        % --- ADC + Events ---
        for t=1:length(tADC1)-1
            if ADC1(t)==1
                line([(t0+tADC1(t)+t0+tADC1(t+1))/2, (t0+tADC1(t)+t0+tADC1(t+1))/2],...
                    [0,1]+1.7,'LineStyle','-','linewidth',0.1,'color',[247 80 13]/255);
            else
                line([t0+tADC1(t), t0+tADC1(t+1)], [0 0]+1.7,...
                    'LineStyle','-','linewidth',3,'color',[247 80 13]/255);
            end
        end

        for t=1:length(tADC1)-1
            if ADC1(t)==-2
                line([(t0+tADC1(t)+t0+tADC1(t+1))/2, (t0+tADC1(t)+t0+tADC1(t+1))/2],...
                    [0 1]+0.3,'LineStyle','-','linewidth',5,'color','m');
                % optional: only label once to avoid clutter
                if k==1
                    text((tADC1(t)+tADC1(t+1))/2-0.5,0.1,'Ideal Crushing');
                end
            else
                line([t0+tADC1(t), t0+tADC1(t+1)], [0 0]+0.3,...
                    'LineStyle','-','linewidth',3,'color','m');
            end
        end
    end

    title('Pulse Sequence Diagram');
    xlabel('Time(ms)');
    hold off;
end

function handled = plotExcitationPreview(interSeqData,defaultNex)
    handled = false;

    if ~isfield(interSeqData,'Plot') || ~isfield(interSeqData.Plot,'mode')
        return;
    end

    if ~strcmp(interSeqData.Plot.mode,'excitationPreview')
        return;
    end

    rfMag = abs(interSeqData.Main.RF.value);
    rfStarts = find(rfMag > 0 & [true, rfMag(1:end-1) == 0]);
    if isempty(rfStarts)
        return;
    end

    nex = min(defaultNex,length(rfStarts));
    if isfield(interSeqData.Plot,'previewExcitations')
        nex = min(nex,interSeqData.Plot.previewExcitations);
    end

    endIdx = length(interSeqData.Main.RF.tStep);
    if nex < length(rfStarts)
        endIdx = rfStarts(nex+1) - 1;
    end

    plotData.tStep = interSeqData.Main.RF.tStep(1:endIdx);
    plotData.RF = normalizeSequenceTrace(abs(interSeqData.Main.RF.value(1:endIdx)));
    plotData.DFreq = normalizeSequenceTrace(interSeqData.Main.DFreq.value(1:endIdx));
    plotData.Gss = normalizeSequenceTrace(interSeqData.Main.Gss.value(1:endIdx));
    plotData.Gpe = normalizeSequenceTrace(interSeqData.Main.Gpe.value(1:endIdx));
    plotData.Gfe = normalizeSequenceTrace(interSeqData.Main.Gfe.value(1:endIdx));
    plotData.ADC = interSeqData.Main.ADC.value(1:endIdx);

    tAxis = [0, cumsum(plotData.tStep)];
    timeMax = max(tAxis(end),eps) * 5/4;

    sliceLabel = 'SS';
    if isfield(interSeqData.Plot,'sliceAxisLabel')
        sliceLabel = interSeqData.Plot.sliceAxisLabel;
    end

    hasKspacePreview = hasRadialKspacePreview(interSeqData.Plot);

    figWidth = 1000;
    if hasKspacePreview
        figWidth = 1320;
    end

    hSeqPlotFig=figure('Visible','on','MenuBar','none','Name','Sequence Plot',...
        'NumberTitle','off','Position',[100,100,figWidth,800],'Resize','off',...
        'Toolbar','figure','Color',[1,1,1]);
    movegui(hSeqPlotFig,'center');

    if hasKspacePreview
        hSeqAxes = subplot(1,2,1,'Parent',hSeqPlotFig);
    else
        hSeqAxes = axes('Parent',hSeqPlotFig,'Position',[0.08 0.08 0.88 0.84]);
    end
    axes(hSeqAxes);

    xlim([0 timeMax]);
    ylim([-0.5 15.0]);
    set(hSeqAxes,'YTickLabelMode','manual');
    set(hSeqAxes,'YTick',[0.3;1.7;4;6.6;9.2;11.8;13.5]);
    set(hSeqAxes,'YTickLabel',{'Events';'Acq';'FE';'PE';sliceLabel;'DFreq';'RF'});

    hold(hSeqAxes,'on');
    plotSequenceTrace(tAxis,plotData.RF,13.5,[60 42 196]/255);
    plotSequenceTrace(tAxis,plotData.DFreq,11.8,[60 42 196]/255);
    plotSequenceTrace(tAxis,plotData.Gss,9.2,[0 125 197]/255);
    plotSequenceTrace(tAxis,plotData.Gpe,6.6,[237 24 73]/255);
    plotSequenceTrace(tAxis,plotData.Gfe,4,[0 169 79]/255);
    plotADCTrace(tAxis,plotData.ADC);
    if isfield(interSeqData.Plot,'excitationCount')
        title(sprintf('Pulse Sequence Diagram (first %d of %d excitations)',...
            nex,interSeqData.Plot.excitationCount));
    else
        title(sprintf('Pulse Sequence Diagram (first %d excitations)',nex));
    end
    xlabel('Time(ms)');

    if hasKspacePreview
        hKspaceAxes = subplot(1,2,2,'Parent',hSeqPlotFig);
        plotKspacePreview3D(hKspaceAxes,interSeqData.Plot.kspacePreview);
    end

    hold(hSeqAxes,'off');

    handled = true;
end

function available = hasRadialKspacePreview(plotInfo)
    available = isfield(plotInfo,'kspacePreview') && isstruct(plotInfo.kspacePreview) && ...
        isfield(plotInfo.kspacePreview,'spokeDirections') && ...
        isfield(plotInfo.kspacePreview,'samplesPerSpoke') && isfield(plotInfo.kspacePreview,'kEdge') && ...
        size(plotInfo.kspacePreview.spokeDirections,2) == 3;
end

function plotKspacePreview3D(hAxes,kspacePreview)
    spokeDirections = kspacePreview.spokeDirections;
    if isempty(spokeDirections)
        axes(hAxes);
        title('3D K-Space Preview Unavailable');
        return;
    end

    numPreview = size(spokeDirections,1);
    if isfield(kspacePreview,'previewSpokes')
        numPreview = min(numPreview,kspacePreview.previewSpokes);
    end

    samplesPerSpoke = kspacePreview.samplesPerSpoke;
    radii = ((1:samplesPerSpoke)' - 0.5) * (kspacePreview.kEdge / samplesPerSpoke);
    spokeColors = lines(max(numPreview,1));

    cla(hAxes);
    hold(hAxes,'on');
    for idx = 1:numPreview
        traj = radii * spokeDirections(idx,:);
        plot3(hAxes,traj(:,1),traj(:,2),traj(:,3),'.-',...
            'LineWidth',1.5,'Color',spokeColors(idx,:));
    end

    plot3(hAxes,0,0,0,'ko','MarkerFaceColor','k','MarkerSize',5);
    hold(hAxes,'off');
    grid(hAxes,'on');
    axis(hAxes,'equal');
    limits = [-1.05 1.05] * kspacePreview.kEdge;
    xlim(hAxes,limits);
    ylim(hAxes,limits);
    zlim(hAxes,limits);
    xlabel(hAxes,'k_x (cycles/m)');
    ylabel(hAxes,'k_y (cycles/m)');
    zlabel(hAxes,'k_z (cycles/m)');
    title(hAxes,sprintf('3D K-Space Preview (first %d spokes)',numPreview));
    view(hAxes,35,25);
end

function values = normalizeSequenceTrace(values)
    scale = max(abs(values));
    if scale ~= 0
        values = values ./ scale;
    end
end

function plotSequenceTrace(tAxis,values,yOffset,traceColor)
    for t = 1:length(values)
        line([tAxis(t), tAxis(t+1)], [values(t),values(t)] + yOffset,...
            'LineStyle','-','linewidth',3,'color',traceColor);

        if t == 1
            prevVal = 0;
        else
            prevVal = values(t-1);
        end

        if values(t) ~= prevVal
            line([tAxis(t), tAxis(t)], [prevVal,values(t)] + yOffset,...
                'LineStyle','-','linewidth',3,'color',traceColor);
        end
    end
end

function plotADCTrace(tAxis,adcValues)
    for t = 1:length(adcValues)
        if adcValues(t) == 1
            tMid = (tAxis(t) + tAxis(t+1)) / 2;
            line([tMid, tMid], [0,1] + 1.7,...
                'LineStyle','-','linewidth',0.1,'color',[247 80 13]/255);
        else
            line([tAxis(t), tAxis(t+1)], [0 0] + 1.7,...
                'LineStyle','-','linewidth',3,'color',[247 80 13]/255);
        end
    end

    for t = 1:length(adcValues)
        if adcValues(t) == -2
            tMid = (tAxis(t) + tAxis(t+1)) / 2;
            line([tMid, tMid], [0 1] + 0.3,...
                'LineStyle','-','linewidth',5,'color','m');
            if t == 1 || adcValues(t-1) ~= -2
                text(tMid-0.5,0.1,'Ideal Crushing');
            end
        else
            line([tAxis(t), tAxis(t+1)], [0 0] + 0.3,...
                'LineStyle','-','linewidth',3,'color','m');
        end
    end
end

    %% Engine configuration and execution
    % --- Executes on hNumIso_Editbox.
    function NumIso_Callback(source,eventdata,flag) %#ok<INUSD,INUSD>
        if strcmp(flag,'')==1
            temp = str2double(get(hNumIso,'String'));
            if ~isnan(temp)
%                 if round(abs(temp))>9
%                     set(hNumIso,'String',num2str(9));
%                 else
                    set(hNumIso,'String',num2str(round(abs(temp))));
%                 end;
            else
                set(hNumIso,'String','1');
            end;
        else
            set(hNumIso,'String',flag); 
        end;
    end

    %% --- Executes on hCPU_Editbox.
    function CPU_Callback(source,eventdata,flag) %#ok<INUSD,INUSD>
        if strcmp(flag,'')==1
            temp = str2double(get(hCPU,'String'));
            if ~isnan(temp)
                set(hCPU,'String',num2str(round(abs(temp))));
            else
                set(hCPU,'String','1');
            end;
        else
            set(hCPU,'String',flag); 
        end;
    end

    %% --- Executes on Signal GPU checkbox.
    function SignalGPU_Callback(source,eventdata,flag) %#ok<INUSD,INUSD>
        if strcmp(flag,'')==1
            return;
        end

        if strcmpi(flag,'GPU') || strcmp(flag,'1')
            set(hSignalGPU,'Value',1);
        else
            set(hSignalGPU,'Value',0);
        end
    end

    function signalEngineLabel = getSignalEngineLabel()
        if get(hSignalGPU,'Value') == 1
            signalEngineLabel = 'GPU';
        else
            signalEngineLabel = 'CPU';
        end
    end

    function signalEngineExe = getSignalEngineExecutable()
        signalEngineExe = ['NutateSignal_',getSignalEngineLabel(),'.exe'];
    end

    function sarEnginePath = getExperimentalSAREnginePath()
        sarEnginePath = fullfile(repositoryRoot,'engine','sar', ...
            'build-msvc','bin','NutateSAR.exe');
    end

    %% Independent receive-noise loading
    function NoiseLoading_Callback(source,eventdata) %#ok<INUSD>
        modeNames = {'Full','Cropped'};
        bounds = noiseLoading.Bounds;
        if isempty(bounds)
            bounds = [str2double(get(hXMin,'String')),str2double(get(hYMin,'String')), ...
                str2double(get(hZMin,'String')),str2double(get(hXMax,'String')), ...
                str2double(get(hYMax,'String')),str2double(get(hZMax,'String'))];
        end
        note = noiseLoading.Note;
        if isempty(note), note = 'Explicit crop'; end
        parentPosition = get(hMain,'Position');
        window = dialog('Name','Noise loading','WindowStyle','modal', ...
            'Position',[parentPosition(1)+300 parentPosition(2)+180 440 265], ...
            'Color','white','Tag','NoiseLoadingDialog');
        uicontrol(window,'Style','text','String','Noise loading', ...
            'Position',[15 233 100 18],'BackgroundColor','white','HorizontalAlignment','left');
        mode = uicontrol(window,'Style','popupmenu', ...
            'String',{'Full represented sample';'Cropped approximation'}, ...
            'Value',find(strcmp(modeNames,noiseLoading.Mode)), ...
            'Position',[120 232 300 22],'Tag','NoiseLoadingMode','Callback',@updateFields);
        uicontrol(window,'Style','text', ...
            'String','Full loading uses represented geometry independently of the signal box.', ...
            'Position',[15 191 410 32],'BackgroundColor','white','HorizontalAlignment','left');
        uicontrol(window,'Style','text','String','Voxel indices', ...
            'Position',[15 164 90 18],'BackgroundColor','white','HorizontalAlignment','left');
        editors = gobjects(1,6);
        for axis = 1:3
            x = 120+(axis-1)*100;
            uicontrol(window,'Style','text','String',char('X'+axis-1), ...
                'Position',[x 164 80 18],'BackgroundColor','white');
            for side = 1:2
                index = axis+3*(side-1);
                editors(index) = uicontrol(window,'Style','edit','String',num2str(bounds(index)), ...
                    'Position',[x 141-(side-1)*30 80 22], ...
                    'Tag',sprintf('NoiseLoadingBound%d',index),'BackgroundColor','white');
            end
        end
        uicontrol(window,'Style','text','String','Min', ...
            'Position',[15 143 80 18],'BackgroundColor','white','HorizontalAlignment','left');
        uicontrol(window,'Style','text','String','Max', ...
            'Position',[15 113 80 18],'BackgroundColor','white','HorizontalAlignment','left');
        copy = uicontrol(window,'Style','pushbutton','String','Use signal box', ...
            'Position',[15 76 140 23],'Tag','NoiseLoadingCopy','Callback',@copySignalBox);
        uicontrol(window,'Style','text','String','Crop note', ...
            'Position',[15 45 70 18],'BackgroundColor','white','HorizontalAlignment','left');
        noteEditor = uicontrol(window,'Style','edit','String',note, ...
            'Position',[90 43 330 23],'Tag','NoiseLoadingNote','BackgroundColor','white');
        uicontrol(window,'Style','pushbutton','String','Apply', ...
            'Position',[255 9 75 25],'Tag','NoiseLoadingApply','Callback',@apply);
        uicontrol(window,'Style','pushbutton','String','Cancel', ...
            'Position',[345 9 75 25],'Tag','NoiseLoadingCancel','Callback',@(~,~) delete(window));
        updateFields();
        uiwait(window);

        function updateFields(varargin)
            enabled = 'off';
            if get(mode,'Value') == 2, enabled = 'on'; end
            set(editors,'Enable',enabled);
            set(copy,'Enable',enabled);
            set(noteEditor,'Enable',enabled);
        end

        function copySignalBox(varargin)
            values = {get(hXMin,'String'),get(hYMin,'String'),get(hZMin,'String'), ...
                get(hXMax,'String'),get(hYMax,'String'),get(hZMax,'String')};
            for index = 1:6, set(editors(index),'String',values{index}); end
            set(noteEditor,'String','Copied signal box (fixed bounds)');
        end

        function apply(varargin)
            values = zeros(1,6);
            for index = 1:6, values(index) = str2double(get(editors(index),'String')); end
            candidate = struct('Mode',modeNames{get(mode,'Value')}, ...
                'Bounds',values,'Note',strtrim(get(noteEditor,'String')));
            if strcmp(candidate.Mode,'Full')
                candidate.Bounds = [];
                candidate.Note = '';
            elseif isempty(candidate.Note)
                candidate.Note = 'Explicit crop';
            end
            try
                noiseLoadingArguments(candidate);
            catch invalidCrop
                errordlg(invalidCrop.message,'Invalid noise crop','modal');
                return;
            end
            noiseLoading = candidate;
            updateNoiseLoadingButton();
            delete(window);
        end
    end

    function updateNoiseLoadingButton()
        if strcmp(noiseLoading.Mode,'Full')
            label = 'Noise: Full sample';
        else
            label = 'Noise: Cropped';
        end
        set(hNoiseLoading,'String',label);
    end

    %% --- Executes on hNEX_Editbox.
    function NEX_Callback(source,eventdata,flag) %#ok<INUSD,INUSD>
        if strcmp(flag,'')==1
            temp = str2double(get(hNEX,'String'));
        else
            temp = str2double(flag);
        end;

        if ~isnan(temp)
            set(hNEX,'String',num2str(max(round(abs(temp)),1)));
        else
            set(hNEX,'String','1');
        end;
    end

    %% --- Executes on hMode_Menu
    function Mode_Callback(source,eventdata,flag)
        if strcmp(flag,'')==1
            tempMode = get(hMode,'Value');
        else
            tempStr = get(hMode,'String');
            tempMode = find(strcmp(tempStr,flag));
            set(hMode,'Value',tempMode);
        end;
        logSetup('Mode set to %s.', getCurrentModeName());
        
        switch tempMode
            case 1
                set(hRun,'String','Run','FontSize',12,'BackgroundColor',[0,1,0]);
                set(hB0Edit,'Enable','on');
                set(hNucleus,'Enable','on');
                set(hExpDB0,'Enable','on');
                
                set(hExpGx,'Enable','on');
                set(hExpGy,'Enable','on');
                set(hExpGz,'Enable','on');

                set(hExpB1p,'Enable','on');
                set(hExpB1m,'Enable','on');
                set(hExpE1p,'Enable','off');

                set(hExpE1m,'Enable','off');
                
                set(hNumIso,'Enable','on');
                set(hCPU,'Enable','on');
                set(hSignalGPU,'Enable','on');
                set(hNEX,'Enable','off');

            case 2
                set(hRun,'String','Experimental SAR','FontSize',10, ...
                    'BackgroundColor',[1,0.85,0.45]);
                set(hB0Edit,'Enable','off');
                set(hNucleus,'Enable','off');
                set(hExpDB0,'Enable','off');

                set(hExpGx,'Enable','off');
                set(hExpGy,'Enable','off');
                set(hExpGz,'Enable','off');

                set(hExpB1p,'Enable','on');
                set(hExpB1m,'Enable','on');
                set(hExpE1p,'Enable','on');

                set(hExpE1m,'Enable','off');
                
                set(hNumIso,'Enable','off');
                set(hCPU,'Enable','on');
                set(hSignalGPU,'Enable','off');
                set(hNEX,'Enable','off');

            case 3
                set(hRun,'String','Run','FontSize',12,'BackgroundColor',[0,1,0]);
                set(hB0Edit,'Enable','off');
                set(hNucleus,'Enable','off');
                set(hExpDB0,'Enable','off');

                set(hExpGx,'Enable','off');
                set(hExpGy,'Enable','off');
                set(hExpGz,'Enable','off');

                set(hExpB1p,'Enable','off');
                set(hExpE1p,'Enable','off');

                set(hExpE1m,'Enable','on');
                
                set(hNumIso,'Enable','off');
                set(hCPU,'Enable','off');
                set(hSignalGPU,'Enable','off');
                set(hNEX,'Enable','on');
        end;
    end

    %% --- Executes on hRun_Button.
    function Run_Callback(source,eventdata) %#ok<INUSD,INUSD>
        if enqueueActive
            logSetup('A simulation job is already being prepared.');
            return;
        end
        enqueueActive = true;
        enqueueCleanup = onCleanup(@finishEnqueue); %#ok<NASGU>
        cd(addr);
        
        tempMode = get(hMode,'Value');
        studyName = get(hStudyName,'String');
        logSetup('Preparing %s run for study "%s".', getCurrentModeName(), studyName);
        queue = signalJobs(false);
        if tempMode == 2 && ~isempty(queue) && strcmp(activeRunStudy,studyName) && queue.ownsDirectory(activeRunDir)
            warnSetup('Run cancelled: the selected signal run is still queued or running.');
            errordlg('Wait for this signal job to finish before adding SAR output to its run folder.',...
                'Signal Job Not Finished','modal');
            return;
        end

        if tempMode == 2
            sarEnginePath = getExperimentalSAREnginePath();
            if exist(sarEnginePath,'file') ~= 2
                warnSetup('Cannot run experimental SAR: missing local engine %s.', sarEnginePath);
                errordlg(['The experimental NutateSAR build was not found.' newline ...
                    'Run engine\\sar\\build_windows.cmd first.'],'Experimental SAR','modal');
                return
            end
            sarChoice = questdlg(['This runs the historical NutateSAR engine for experimental review only.' newline ...
                'Its B1+ scaling and output physics are unvalidated. Continue?'], ...
                'Experimental SAR','Run experimental SAR','Cancel','Cancel');
            if ~strcmp(sarChoice,'Run experimental SAR')
                logSetup('Experimental SAR run cancelled by user.');
                return
            end
        end

        if tempMode == 1 && ~signalBoxOverlapsFOV()
            choice = questdlg(['The green FOV and red signal simulation box do not overlap. ' ...
                'Match the signal box to the FOV before running?'], ...
                'FOV Outside Signal Box','Match','Cancel','Match');
            if ~strcmp(choice,'Match')
                return;
            end
            Match_Callback(source,eventdata,'');
            if ~signalBoxOverlapsFOV()
                warndlg('The available geometry cannot provide a signal box that overlaps the FOV.', ...
                    'FOV Outside Geometry','modal');
                return;
            end
        end

        if tempMode == 1 || tempMode == 3
            try
                readTissuePropertyFile([inputCmd{2,1},inputCmd{2,2}],getCurrentNucleus());
            catch tissueError
                warnSetup('Run cancelled: %s',tissueError.message);
                errordlg(tissueError.message,'Invalid Tissue Property File','modal');
                return;
            end
        end

        if tempMode == 3 && strcmp(noiseLoading.Mode,'Full') && countInputFiles(8) < Rx.Num
            message = sprintf(['Full noise loading requires a supplied E1- map for each of %d ' ...
                'receive channels; only %d map(s) are selected. Complete the ordered receive E-field list.'], ...
                Rx.Num,countInputFiles(8));
            warnSetup('Run cancelled: incomplete receive E-field coverage. %s',message);
            errordlg(message,'Incomplete receive E coverage','modal');
            return;
        end

        if ~ensureCurrentSequence(source,eventdata,'running','Run cancelled')
            cd(addr);
            return;
        end

        if tempMode ~= 2
            enqueueBusy = true;
            beginBusyState('Preparing simulation job...');
        end
        StudySave_Callback(source,eventdata,'Run');
        runDir = resolveRunDirectory(tempMode,studyName);
        logSetup('Run directory: %s', runDir);
        queue = signalJobs(false);
        if tempMode == 2 && ~isempty(queue) && queue.ownsDirectory(runDir)
            warnSetup('Run cancelled: this folder belongs to an unfinished signal job.');
            errordlg('Wait for this signal job to finish before adding SAR output to its run folder.',...
                'Signal Job Not Finished','modal');
            return;
        end

        if copyRunProtocolFile(runDir,studyName) ~= 1
            warnSetup('Run cancelled: could not copy protocol file for study "%s".', studyName);
            cd(addr);
            return;
        end

        [sequenceReady,runSequenceFile] = copyRunSequenceFile(runDir,studyName);
        if sequenceReady ~= 1
            warnSetup('Run cancelled: no generated sequence file is available. Click SeqGen first or select a sequence file.');
            cd(addr);
            return;
        end

        runInputs = struct('geometryFile', [inputCmd{1,1},inputCmd{1,2}], ...
            'tissueFile', [inputCmd{2,1},inputCmd{2,2}], 'sequenceFile', runSequenceFile);
        switch tempMode
            case 1
                runType = 'Signal';
                signalEngineExe = getSignalEngineExecutable();
                executable = fullfile(engineRoot,signalEngineExe);
                if exist(executable,'file') ~= 2
                    warnSetup('Cannot run signal simulation: missing engine %s.', executable);
                    errordlg(['Cannot find signal engine ',signalEngineExe,'.'],'modal');
                    return
                end
                if isempty(inputCmd{12,1})
                    warnSetup('Cannot run signal simulation: missing KSpace output filename.');
                    errordlg('Please Specify kSpace Filename.','modal');
                    return
                end
                if isempty(inputCmd{13,1})
                    warnSetup('Cannot run signal simulation: missing KMap output filename.');
                    errordlg('Please Specify kMap Filename.','modal');
                    return
                end

                runInputs.numIso = get(hNumIso,'String');
                runInputs.threads = get(hCPU,'String');
                runInputs.b0 = get(hB0Edit,'String');
                runInputs.nucleus = getCurrentNucleus();
                runInputs.deltaB0File = selectedProtocolFile(3);
                runInputs.transmitB1Files = buildInputFileList(inputCmd{5,:});
                runInputs.receiveB1Files = buildInputFileList(inputCmd{7,:});
                runInputs.deltaGxFile = selectedProtocolFile(9);
                runInputs.deltaGyFile = selectedProtocolFile(10);
                runInputs.deltaGzFile = selectedProtocolFile(11);
                runInputs.kSpaceFile = getStudyFilePath(runDir,studyName,'.ksig');
                runInputs.kMapFile = getStudyFilePath(runDir,studyName,'.ktrj');
                runInputs.xCenter = get(hXCtr,'String');
                runInputs.yCenter = get(hYCtr,'String');
                runInputs.zCenter = get(hZCtr,'String');

            case 2
                runType = 'SAR';
                executable = sarEnginePath;
                if isempty(inputCmd{5,1})
                    warnSetup('Cannot run SAR simulation: B1+ files are required.');
                    errordlg('Please Specify B1+ Filename(s).','modal');
                    return
                end
                if isempty(inputCmd{6,1})
                    warnSetup('Cannot run SAR simulation: E1+ files are required.');
                    errordlg('Please Specify E1+ Filename(s).','modal');
                    return
                end
                if isempty(inputCmd{15,1})
                    warnSetup('Cannot run SAR simulation: missing SAR output filename.');
                    errordlg('Please Specify SAR Filename.','modal');
                    return
                end

                runInputs.threads = get(hCPU,'String');
                runInputs.transmitB1Files = buildInputFileList(inputCmd{5,:});
                runInputs.transmitE1Files = buildInputFileList(inputCmd{6,:});
                runInputs.receiveB1Files = buildInputFileList(inputCmd{7,:});
                runInputs.sarFile = getStudyFilePath(runDir,studyName,'.sar');

            case 3
                runType = 'Noise';
                executable = fullfile(engineRoot,'NutateNoise.exe');
                if exist(executable,'file') ~= 2
                    warnSetup('Cannot run noise simulation: missing engine %s.', executable);
                    errordlg('Cannot find noise engine NutateNoise.exe.','modal');
                    return
                end
                noiseSeed = randi([0 double(intmax('uint32'))],1,1,'uint32');
                runInputs.noiseSeed = sprintf('%u',noiseSeed);
                if isempty(inputCmd{8,1})
                    warnSetup('Cannot run noise simulation: E1- files are required.');
                    errordlg('Please Specify E1- Filename(s).','modal');
                    return
                end
                if isempty(inputCmd{14,1})
                    warnSetup('Cannot run noise simulation: missing noise output filename.');
                    errordlg('Please Specify Noise Filename.','modal');
                    return
                end

                runInputs.nex = get(hNEX,'String');
                runInputs.nucleus = getCurrentNucleus();
                runInputs.receiveE1Files = buildInputFileList(inputCmd{8,:});
                runInputs.noiseFile = getStudyFilePath(runDir,studyName,'.nois');
                runInputs.noiseLoading = noiseLoading;
        end

        if tempMode == 1 || tempMode == 2
            runInputs.sampleBounds = struct( ...
                'xMin', get(hXMin,'String'), 'xMax', get(hXMax,'String'), ...
                'yMin', get(hYMin,'String'), 'yMax', get(hYMax,'String'), ...
                'zMin', get(hZMin,'String'), 'zMax', get(hZMax,'String'));
        end
        [command, argumentText] = buildRunCommand(runType,executable,runInputs);

        if tempMode == 3
            if strcmp(noiseLoading.Mode,'Full')
                logSetup('Noise loading: full represented sample; independent of the signal box.');
            else
                logSetup('Noise loading: cropped approximation. %s',noiseLoading.Note);
                if countInputFiles(8) < Rx.Num
                    warnSetup('Receive E-field coverage is incomplete; unprovided channels use native ideal defaults.');
                end
            end
        end

        scriptName = ['run',runType];
        scriptFile = [runDir,scriptName,'.bat'];
        fid = fopen(scriptFile,'w');
        fprintf(fid,'%s \n',command);
        logSetup('Wrote run script: %s', scriptFile);
        switch tempMode
            case 1
                logSetup('Signal outputs: k-space=%s, trajectory=%s', runInputs.kSpaceFile, runInputs.kMapFile);
            case 2
                logSetup('SAR output: %s', runInputs.sarFile);
            case 3
                logSetup('Noise output: %s, seed=%s', runInputs.noiseFile,runInputs.noiseSeed);
        end
        fclose(fid);

        cd(runDir);

        if tempMode ~= 2
            backend = 'CPU';
            if tempMode == 1 && get(hSignalGPU,'Value'),backend = 'CUDA';end
            % Snapshot the exact batch arguments so Jobs uses no later Setup state.
            descriptor = struct('Study',studyName,'Backend',backend,'Type',runType,...
                'Executable',executable,'Arguments',argumentText,'Directory',runDir);
            queue = signalJobs();
            id = queue.enqueue(descriptor);
            logSetup('Queued %s job %d (%s). Outputs: %s',lower(runType),id,backend,runDir);
        else
            dos([scriptName,' &']);
            logSetup('Launched %s run. Watch MATLAB and engine output for completion or errors.', getCurrentModeName());
        end

        cd(addr);
    end

    function ShowSignalJobs_Callback(~,~)
        queue = signalJobs();queue.show();
    end

    function finishEnqueue()
        if enqueueBusy,enqueueBusy = false;endBusyState();end
        enqueueActive = false;
        cd(addr);
    end

    %% Shared state and sequence helpers
    function updateSeq()
        global inputInfo;
        updateRadialAxisControls();
        
        tempAddr = addr;
        
        % Capture FOV before the menu refresh can normalize it.
        settings = readSequenceControls();
        if settings.RF.Num == 1 && settings.RF.Shape == 1
            set(hRF_Num,'String','2');
            settings.RF.Num = 2;
        end

        sequenceNames = SeqInterfaceIn;
        set(hSeqType,'String',sequenceNames);
        updateSequenceSpecificFieldLabels();

        slice = readSequenceSlice(inputInfo);
        sequenceIndex = get(hSeqType,'Value');
        sequenceNames = get(hSeqType,'String');
        sequenceName = sequenceNames{sequenceIndex};
        TI.duration = str2double(get(hTI,'String'));
        TI.handle = hTI;
        [minTE,minTR] = dispatchSequence(sequenceName,sequenceIndex,settings,slice,TI);

        if strcmp(sequenceName,'SE')
            % Round limits upward; recompute TR for the TE actually displayed.
            if str2double(get(hTE,'String')) < minTE
                set(hTE,'String',sprintf('%.4f',ceil(minTE*10000)/10000));
            end
            settings.TE = str2double(get(hTE,'String'));
            [~,minTR] = dispatchSequence(sequenceName,sequenceIndex,settings,slice,TI);
            if str2double(get(hTR,'String')) < minTR
                set(hTR,'String',sprintf('%.4f',ceil(minTR*10000)/10000));
            end
        else
            if str2double(get(hTE,'String')) < minTE
                set(hTE,'String',num2str(round(minTE*10000)/10000));
            end;
            if str2double(get(hTR,'String')) < minTR
                set(hTR,'String',num2str(round(minTR*10000)/10000));
            end;
        end

        updateReadoutTooltips();
        updateTargetFlipAngleDisplay();
        markSequenceDirty();

        cd(tempAddr);
    end

    function updateLarmorTooltips()
        b0 = str2double(get(hB0Edit,'String'));
        nucleus = getCurrentNucleus();
        tip = 'Enter a finite B0 to calculate the Larmor frequency.';
        if isreal(b0) && isfinite(b0) && b0 >= 0
            [~,gammaHzPerT] = getNucleusGamma(nucleus);
            tip = sprintf('Larmor frequency for %s at %g T: %.9g MHz.', ...
                nucleus,b0,(gammaHzPerT/1e6)*b0);
        end
        set([hB0Label,hB0Edit,hNucleusLabel,hNucleus],'TooltipString',tip);
    end

    function updateReadoutTooltips()
        global inputInfo;
        bwTip = '';
        teTip = '';
        trTip = '';
        if strcmp(get(hSeqType,'Enable'),'on')
            settings = readSequenceControls();
            bandwidth = settings.ADC.BW; % kHz
            samples = settings.MatSize(1);
            if isreal(bandwidth) && isfinite(bandwidth) && bandwidth > 0
                sequenceName = getCurrentSequenceName();
                readout = 'line';
                if is3DRadSequenceName(sequenceName)
                    readout = 'spoke';
                end
                bwTip = sprintf('Readout per %s: %.6g ms (%g samples). Dwell: %.6g us.', ...
                    readout,samples/bandwidth,samples,1000/bandwidth);

                % Use the displayed TE for the TR limit. Omit the TI control
                % so this timing query leaves protocol settings untouched.
                slice = readSequenceSlice(inputInfo);
                [minTE,minTR] = dispatchSequence(sequenceName,get(hSeqType,'Value'),settings,slice,[]);
                if isreal(minTE) && isfinite(minTE)
                    teTip = sprintf('Minimum TE for the current settings: %.6g ms.',minTE);
                end
                if isreal(minTR) && isfinite(minTR)
                    trTip = sprintf('Minimum TR at the current TE: %.6g ms.',minTR);
                end
            end
        end
        set([hADCLabel,hADC_Freq],'TooltipString',bwTip);
        set([hTELabel,hTE],'TooltipString',teTip);
        set([hTRLabel,hTR],'TooltipString',trTip);
    end

    function settings = readSequenceControls()
        settings.TE = str2double(get(hTE,'String')); % ms
        settings.TR = str2double(get(hTR,'String')); % ms
        settings.MatSize = get(hMatSize,'Value');
        settings.FOV = get(hFOV,'Value'); % mm
        settings.RF.Duration = str2double(get(hRF_Duration,'String')); % ms
        settings.RF.Num = str2double(get(hRF_Num,'String'));
        settings.RF.Shape = get(hRF_Shape,'Value');
        settings.RF.FA = str2double(get(hRF_FA,'String')); % degrees
        settings.ADC.BW = str2double(get(hADC_Freq,'String')); % kHz
        if is3DRadSequenceName(getCurrentSequenceName())
            settings.ADC.radialResolutionMm = parseRadialResolutionMm(get(hRadialResolution,'String'));
        end
        settings.GradOn.ss = get(hSS,'Value');
        settings.GradOn.fe = get(hFE,'Value');
        settings.GradOn.pe = get(hPE,'Value');
        settings.Dummy = str2double(get(hDummyNum,'String'));
    end

    function slice = readSequenceSlice(geometry)
        axesXYZ = cartesianAxes(get(hOrientationMenu,'Value'),false);
        spacing = [geometry.widX, geometry.widY, geometry.widZ];
        offsets = [geometry.setX, geometry.setY, geometry.setZ];
        slice.TH = geometry.sliceTH/1000;
        slice.offset = offsets(axesXYZ(3))*spacing(axesXYZ(3))/1000;
    end

    function varargout = dispatchSequence(sequenceName,sequenceIndex,settings,slice,TI)
        [varargout{1:nargout}] = SeqInterfaceOut(sequenceName,sequenceIndex, ...
            settings.TE,settings.TR,settings.MatSize,settings.FOV,settings.RF, ...
            settings.ADC,settings.GradOn,settings.Dummy,slice,TI,getCurrentNucleus());
    end

    function ready = ensureCurrentSequence(source,eventdata,action,cancelMessage)
        ready = true;
        if ~sequenceState.isDirty
            return;
        end

        question = sprintf(['Sequence parameters changed after the sequence file was generated. ' ...
            'Regenerate the sequence before %s?'],action);
        regenChoice = questdlg(question,'Sequence Out of Date','Regenerate','Cancel','Regenerate');
        if ~strcmp(regenChoice,'Regenerate')
            warnSetup('%s: sequence parameters changed and sequence regeneration was not requested.',cancelMessage);
            ready = false;
            return;
        end

        logSetup('Regenerating sequence before %s because sequence parameters changed.',action);
        SeqGen_Callback(source,eventdata);
        ready = ~sequenceState.isDirty;
        if ~ready
            warnSetup('%s: sequence regeneration did not complete.',cancelMessage);
        end
    end

    function waveform = readSequencePreview()
        waveform = sequenceState.previewWaveform;
    end

    function markSequenceDirty()
        sequenceState.isDirty = true;
        if ~isempty(inputCmd{4,1})
            set(hExpSeqEdit,'FontAngle','italic');
        end
    end

    function markSequenceClean()
        if sequenceState.radialRestorationPending
            markSequenceDirty();
            return;
        end
        sequenceState.isDirty = false;
        set(hExpSeqEdit,'FontAngle','normal');
    end

    function updateTargetFlipAngleDisplay()
        updateFlipAngleFromTargetB1();
    end

    function updateFlipAngleFromTargetB1()
        [~,targetB1,txScaleError] = getTxAmplitudeScale();
        if ~isempty(txScaleError) || isnan(targetB1)
            return;
        end

        RF.Duration = str2double(get(hRF_Duration,'String'));
        RF.Num = str2double(get(hRF_Num,'String'));
        RF.Shape = get(hRF_Shape,'Value');
        gammaRadPerTPerS = getNucleusGamma(getCurrentNucleus());
        pulseAreaSeconds = rfPulseAreaSeconds(RF);
        targetFA = flipAngleFromB1(targetB1,pulseAreaSeconds,gammaRadPerTPerS);
        if ~isnan(targetFA)
            set(hRF_FA,'String',sprintf('%.5g',targetFA));
        end
    end

    function updateTargetB1FromFlipAngle(flipAngleDeg)
        RF.Duration = str2double(get(hRF_Duration,'String'));
        RF.Num = str2double(get(hRF_Num,'String'));
        RF.Shape = get(hRF_Shape,'Value');
        gammaRadPerTPerS = getNucleusGamma(getCurrentNucleus());
        pulseAreaSeconds = rfPulseAreaSeconds(RF);
        targetB1 = b1MicroTeslaFromFlipAngle(flipAngleDeg,pulseAreaSeconds,gammaRadPerTPerS);
        if ~isnan(targetB1)
            set(hTargetB1,'String',sprintf('%.5g',targetB1));
        end
    end

    function [scaleFactor,effectiveTargetB1,errorMessage] = getTxAmplitudeScale(refB1)
        if nargin < 1 || isempty(refB1)
            refB1 = Tx.RefB1;
        end

        desiredB1 = parseOptionalNonnegativeScalar(get(hTargetB1,'String'));
        [scaleFactor,effectiveTargetB1,errorMessage] = resolveTxAmplitudeScale(desiredB1,refB1);
    end

    function [effectiveTxMag,scaleFactor,errorMessage] = getEffectiveTxMagMat(rawTxMag,refB1)
        if nargin < 1 || isempty(rawTxMag)
            rawTxMag = Tx.MagMat;
        end
        if nargin < 2 || isempty(refB1)
            refB1 = Tx.RefB1;
        end

        [scaleFactor,~,errorMessage] = getTxAmplitudeScale(refB1);
        effectiveTxMag = rawTxMag(:);
        if isempty(errorMessage)
            effectiveTxMag = effectiveTxMag * scaleFactor;
        end
    end

    function value = parseOptionalNonnegativeScalar(inputString)
        inputString = strtrim(inputString);
        if isempty(inputString)
            value = NaN;
            return;
        end

        value = str2double(inputString);
        if isnan(value) || ~isfinite(value) || value < 0
            value = NaN;
        end
    end

    function value = parseOptionalPositiveScalar(inputString)
        value = parseOptionalNonnegativeScalar(inputString);
        if value == 0
            value = NaN;
        end
    end

    function outputString = formatOptionalScalar(value)
        if isempty(value) || isnan(value)
            outputString = '';
        else
            outputString = num2str(value);
        end
    end

    %% Sequence export
    function success = expSeq(finalSeqData,dummy,Tx,Rx)
        success = false;

        maxExactFloat32Integer = 2^24;
        if finalSeqData.totalNum > maxExactFloat32Integer
            sequenceCountWarning = sprintf([ ...
                'This sequence contains %.0f time steps. The V1 .seqn header stores the ' ...
                'total as float32, which cannot represent every integer above %.0f exactly. ' ...
                'The file will still be written, but the engine may read a rounded sequence length.'], ...
                finalSeqData.totalNum,maxExactFloat32Integer);
            warnSetup('%s',sequenceCountWarning);
            warndlg(sequenceCountWarning,'Sequence Header Precision');
        end
        
        tempStr = get(hStudyName,'String');
        [effectiveTxMag,~,txScaleError] = getEffectiveTxMagMat(Tx.MagMat,Tx.RefB1);
        if ~isempty(txScaleError)
            uiwait(errordlg(txScaleError,'Tx Scaling','modal'));
            return;
        end

        cd([protocolRoot,'\',tempStr]);
        
        fid=fopen([tempStr,'.seqn'],'w');
        txScale = effectiveTxMag(:).' .* exp(1i*Tx.PhsMat(:).' / 180 * pi);

        fwrite(fid,[-1 1 finalSeqData.totalNum],'float32');
        fwrite(fid,Tx.Num,'float32');
        fwrite(fid,Rx.Num,'float32');
        
        % Time
        if dummy > 0
            fwrite(fid,length(finalSeqData.Dummy.Time.value),'float32');
            fwrite(fid,finalSeqData.Dummy.Time.repeat,'float32');
            fwrite(fid,finalSeqData.Dummy.Time.value,'float32');
        end;
        fwrite(fid,length(finalSeqData.Main.Time.value),'float32');
        fwrite(fid,finalSeqData.Main.Time.repeat,'float32');
        fwrite(fid,finalSeqData.Main.Time.value,'float32');
        
        % ADC
        if dummy > 0
            fwrite(fid,length(finalSeqData.Dummy.ADC.value),'float32');
            fwrite(fid,finalSeqData.Dummy.ADC.repeat,'float32');
            fwrite(fid,finalSeqData.Dummy.ADC.value,'float32');
        end;
        fwrite(fid,length(finalSeqData.Main.ADC.value),'float32');
        fwrite(fid,finalSeqData.Main.ADC.repeat,'float32');
        fwrite(fid,finalSeqData.Main.ADC.value,'float32');

        % Version 1: observation offset and original ADC dwell, in milliseconds.
        for field = {'SampleOffset','Dwell'}
            if dummy > 0
                block = finalSeqData.Dummy.(field{1});
                fwrite(fid,numel(block.value),'float32');
                fwrite(fid,block.repeat,'float32');
                fwrite(fid,block.value,'float32');
            end
            block = finalSeqData.Main.(field{1});
            fwrite(fid,numel(block.value),'float32');
            fwrite(fid,block.repeat,'float32');
            fwrite(fid,block.value,'float32');
        end
        
        % RF: write each channel's complete dummy/main timeline together.
        mainRF = reshape(finalSeqData.Main.RF.value,1,[]);
        mainDFreq = reshape(finalSeqData.Main.DFreq.value,1,[]);
        for m=1:Tx.Num
            if dummy > 0
                dummyRF = reshape(finalSeqData.Dummy.RF.value,1,[]);
                dummyDFreq = reshape(finalSeqData.Dummy.DFreq.value,1,[]);
                fwrite(fid,length(finalSeqData.Dummy.RF.value),'float32');
                fwrite(fid,finalSeqData.Dummy.RF.repeat,'float32');
                dummyRFWrite = dummyRF * txScale(m);
                fwrite(fid,[real(dummyRFWrite); imag(dummyRFWrite); dummyDFreq],'float32');
            end;
            fwrite(fid,length(finalSeqData.Main.RF.value),'float32');
            fwrite(fid,finalSeqData.Main.RF.repeat,'float32');
            mainRFWrite = mainRF * txScale(m);
            fwrite(fid,[real(mainRFWrite); imag(mainRFWrite); mainDFreq],'float32');
        end;
        
        % Gx
        if dummy > 0
            fwrite(fid,length(finalSeqData.Dummy.Gx.value),'float32');
            fwrite(fid,finalSeqData.Dummy.Gx.repeat,'float32');
            fwrite(fid,finalSeqData.Dummy.Gx.value,'float32');
        end;
        fwrite(fid,length(finalSeqData.Main.Gx.value),'float32');
        fwrite(fid,finalSeqData.Main.Gx.repeat,'float32');
        fwrite(fid,finalSeqData.Main.Gx.value,'float32');
        
        % Gy
        if dummy > 0
            fwrite(fid,length(finalSeqData.Dummy.Gy.value),'float32');
            fwrite(fid,finalSeqData.Dummy.Gy.repeat,'float32');
            fwrite(fid,finalSeqData.Dummy.Gy.value,'float32');
        end;
        fwrite(fid,length(finalSeqData.Main.Gy.value),'float32');
        fwrite(fid,finalSeqData.Main.Gy.repeat,'float32');
        fwrite(fid,finalSeqData.Main.Gy.value,'float32');
        
        % Gz
        if dummy > 0
            fwrite(fid,length(finalSeqData.Dummy.Gz.value),'float32');
            fwrite(fid,finalSeqData.Dummy.Gz.repeat,'float32');
            fwrite(fid,finalSeqData.Dummy.Gz.value,'float32');
        end;
        fwrite(fid,length(finalSeqData.Main.Gz.value),'float32');
        fwrite(fid,finalSeqData.Main.Gz.repeat,'float32');
        fwrite(fid,finalSeqData.Main.Gz.value,'float32');
        
        fclose(fid);
        
        cd(addr);
        
        success = true;
    end

    %% Reset and GUI support helpers
    function reset()
        global displayInfo;
        sequenceState.radialRestorationPending = false;
        noiseLoading = struct('Mode','Full','Bounds',[],'Note','');
        updateNoiseLoadingButton();
        set(hNoiseLoading,'Enable','off');

        hImages = initializeGeometryPanels(hImages,hGeoPanel,false);

        % % % Save FileName Addresses.
        inputCmd = initializeInputCmd();
        invalidateTissueDisplayCache();
        activeRunDir = '';
        activeRunStudy = '';

        Tx.Num = 1;
        Tx.MagMat = ones(Tx.Num,1);
        Tx.PhsMat = zeros(Tx.Num,1);
        Tx.RefB1 = NaN;
        
        Rx.Num = 1;
        
        set(hSave,'Enable','off');
        set(hReset,'Enable','off');
        
        % % % Display DisplayMenu.
        set(hDisplayMenu,'String',{'ID','T1','T2','Conc. (mol/L)','Chemical Shift','Conductivity','Mass Density'},'Value',1,'Enable','off');
        
        % % % Display ScaleMenu.
        set(hScaleMenu,'Value',1,'Enable','off');

        % % % Display OrientationMenu.
        set(hOrientationMenu,'Value',1,'Enable','off');

        % % % Display GeoSliderTH.
        set(hGeoSliceTH,'String','0','Enable','off');

        % % % Display GeoSlider.
        set(hGeoSlider,'Max',100,'Min',0,'Value',0,...
            'SliderStep',[1/100,10/100],'Enable','off');

        % % % Display GeoSliderEdit.
        set(hGeoSliderEdit,'String','0','Enable','off');

        % % % Display Min,Max,Ctr,Wid,Set edits.
        set(hXMin,'String','','Enable','Inactive');
        set(hYMin,'String','','Enable','Inactive');
        set(hZMin,'String','','Enable','Inactive');
        set(hXMax,'String','','Enable','Inactive');
        set(hYMax,'String','','Enable','Inactive');
        set(hZMax,'String','','Enable','Inactive');
        set(hXCtr,'String','','Enable','Inactive');
        set(hYCtr,'String','','Enable','Inactive');
        set(hZCtr,'String','','Enable','Inactive');
        set(hXWid,'String','','Enable','Inactive');
        set(hYWid,'String','','Enable','Inactive');
        set(hZWid,'String','','Enable','Inactive');
        set(hXSet,'String','','Enable','Inactive');
        set(hYSet,'String','','Enable','Inactive');
        set(hZSet,'String','','Enable','Inactive');
        

        % % % Display the GeoName.
        set(hExpGeoEdit,'String','Geo Filename','Enable','inactive',...
            'FontAngle','italic');
        set(hExpGeo,'Enable','off');

        % % % Display the TissName.
        set(hExpTissEdit,'String','Tiss Filename','Enable','inactive',...
            'FontAngle','italic');
        set(hExpTiss,'Enable','off');
        
        % % % Display the dB0Edit.
        set(hExpDB0Edit,'String','0 or dB0 Filename','Enable','inactive',...
            'FontAngle','italic');
        set(hExpDB0,'Enable','off');

        % % % Display the seqEdit.
        set(hExpSeqEdit,'string','Use setup or Seq Filename',...
            'Enable','inactive',...
            'FontAngle','italic');
        set(hExpSeq,'Enable','off');
        
        % % % Display the B1pEdit.
        set(hExpB1pEdit,'string','Homogeneous or B1+ Filename(s)',...
            'Enable','inactive',...
            'FontAngle','italic');
        set(hExpB1p,'Enable','off');
        
        % % % Display the E1pEdit.
        set(hExpE1pEdit,'string','E1+ Filename(s)',...
            'Enable','inactive',...
            'FontAngle','italic');
        set(hExpE1p,'Enable','off');
        
        % % % Display the B1mEdit.
        set(hExpB1mEdit,'string','Homogeneous or B1- Filename(s)',...
            'Enable','inactive',...
            'FontAngle','italic');
        set(hExpB1m,'Enable','off');
        
        % % % Display the E1mEdit.
        set(hExpE1mEdit,'string','E1- Filename(s)',...
            'Enable','inactive',...
            'FontAngle','italic');
        set(hExpE1m,'Enable','off');
        
        % % % Display the GxEdit.
        set(hExpGxEdit,'string','Gx Filename','Enable','inactive',...
            'FontAngle','italic');
        set(hExpGx,'Enable','off');
        
        % % % Display the GyEdit.
        set(hExpGyEdit,'string','Gy Filename','Enable','inactive',...
            'FontAngle','italic');
        set(hExpGy,'Enable','off');
        
        % % % Display the GzEdit.
        set(hExpGzEdit,'string','Gz Filename','Enable','inactive',...
            'FontAngle','italic');
        set(hExpGz,'Enable','off');
                
        % % % Display the B0Edit.
        set(hB0Edit,'string','3','Enable','off');

        % % % Display the Nucleus menu.
        set(hNucleus,'Value',1,'Enable','off');
        
        % % % Display the SequenceType menu.
        set(hSeqType,'Value',1,'Enable','off');
        
        % % % Display the RF_Shape menu.
        set(hRF_Shape,'Value',1,'Enable','off');
        
        % % % Display the RF_Duration edit.
        set(hRF_Duration,'String','2.6','Enable','off');
        
        % % % Display the RF# edit.
        set(hRF_Num,'String','512','Enable','off');
        
        % % % Display the RF_FA edit.
        set(hRF_FA,'String','90','Enable','off');

        % % % Display the target B1+ edit.
        set(hTargetB1,'String','','Enable','off');
        
        % % % Display the RF_TI edit.
        set(hTI,'String','10','Enable','off');
        
        % % % Display the FOV edit.
        set(hFOV_Pop,'String','FOV FE|PE (mm)','Enable','off');

        % % % Display the FOV edit.
        set(hFOV,'String','300','Value',[300,300],'Enable','off');
        
        % % % Display the MatSize edit.
        set(hMatSize_Pop,'String','MatSize FE|PE','Enable','off');

        % % % Display the MatSize edit.
        set(hMatSize,'String','128','Value',[128,128],'Enable','off');

        % % % Display the ADC_Freq edit.
        set(hADC_Freq,'String','50','Enable','off');
        resetRadialResolutionControls();

        % % % Display the Tx edit.
        set(hTx,'String','1','Enable','off');
        % % % Display the Rx edit.
        set(hRx,'String','1','Enable','off');
        
        % % % Display the Match button.
        set(hMatch,'String','Match','Enable','off');
        
        % % % Display the SS checkbox.
        set(hSS,'String','SS','Value',1,'Enable','off');

        % % % Display the PE checkbox.
        set(hPE,'String','PE','Value',1,'Enable','off');

        % % % Display the FE checkbox.
        set(hFE,'String','FE','Value',1,'Enable','off');

        % % % Display the TE edit.
        set(hTE,'String','TE','String','10','Enable','off');

        % % % Display the TR edit.
        set(hTR,'String','TR','String','500','Enable','off');
        
        % % % Display the TI_Duration edit.
        set(hTI,'String','10','Enable','off');
        
        % % % Display the DummyNum edit.
        set(hDummyNum,'String','0','Enable','off');

        % % % Display the PEDirect edit.
        set(hPEDirectMenu,'String',{'P--A';'A--P';'L--R';'R--L'},'Value',1,...
           'Enable','off'); % to be edited
        
        set(hSeqGen,'Enable','off');
        
        set(hSeqPlot,'Enable','off');
        displayInfo.HideFOVOverlay = false;
        
        % % Display the NumIso edit.
        set(hNumIso, 'String','1','Enable','off');
        
        % % Display the CPU edit.
        set(hCPU, 'String','1','Enable','off');

        % % Display the Signal GPU toggle.
        set(hSignalGPU,'Value',0,'Enable','off');

        % % Display the NEX edit.
        set(hNEX, 'String','1','Enable','off');

        % % Display the Mode menu.
        set(hMode,'Enable','off');
        
        % %  Display the Fields button.
        set(hFields,'Enable','off');

        % %  Display the Run button.
        set(hRun,'Enable','off');
        updateLarmorTooltips();
        updateReadoutTooltips();
    end

    function beginBusyState(message)
        if nargin < 1 || isempty(message)
            message = 'Working...';
        end

        busyState.depth = busyState.depth + 1;
        set(hBusyText,'String',message);
        set(hBusyOverlay,'Visible','on');
        set(hMain,'Pointer','watch','Name',[defaultFigureName,' - ',message]);
        drawnow;
    end

    function updateBusyState(message)
        if nargin < 1 || isempty(message) || busyState.depth == 0
            return;
        end

        set(hBusyText,'String',message);
        set(hMain,'Pointer','watch','Name',[defaultFigureName,' - ',message]);
        drawnow;
    end

    function endBusyState()
        if busyState.depth == 0
            return;
        end

        busyState.depth = busyState.depth - 1;
        if busyState.depth > 0
            return;
        end

        set(hBusyOverlay,'Visible','off');
        set(hBusyText,'String','');
        set(hMain,'Pointer','arrow','Name',defaultFigureName);
        drawnow;
    end

    function displayImages(hImages,inputInfo,displayInfo,selectView,geoData)
        displayImagesCore(hImages,inputInfo,fovDisplaySettings(displayInfo),selectView,geoData);
    end

    function info = fovDisplaySettings(info)
        info.ActiveSequenceName = getCurrentSequenceName();
        info.SwapInPlane = get(hPEDirectMenu,'Value') > 2;
        info.SliceSelect = logical(get(hSS,'Value'));
    end

    function hImages = initializeGeometryPanels(hImages, hGeoPanel, showLabels)
        initializeBlankGeometryAxis(hImages.hAxlImage);
        if showLabels
            createGeometryPanelLabel(hGeoPanel,hImages.hAxlImage,'Axial');
        end
        hImages.Axial = createGeometryOverlayHandles(hImages.hAxlImage);

        initializeBlankGeometryAxis(hImages.hSagImage);
        if showLabels
            createGeometryPanelLabel(hGeoPanel,hImages.hSagImage,'Sagittal');
        end
        hImages.Sagittal = createGeometryOverlayHandles(hImages.hSagImage);

        initializeBlankGeometryAxis(hImages.hCrlImage);
        if showLabels
            createGeometryPanelLabel(hGeoPanel,hImages.hCrlImage,'Coronal');
        end
        hImages.Coronal = createGeometryOverlayHandles(hImages.hCrlImage);
    end

    function createGeometryPanelLabel(hGeoPanel, axisHandle, labelText)
        hLabel = uicontrol(hGeoPanel,'Style','text','string',labelText,...
            'Position',[1 1 60 13],'FontWeight','bold',...
            'BackgroundColor',[1,1,1]);
        labelExtent = get(hLabel,'Extent');
        axisPos = getpixelposition(axisHandle);
        labelWidth = max(40,ceil(labelExtent(3)));
        labelHeight = max(13,ceil(labelExtent(4)));
        labelX = axisPos(1) + (axisPos(3)-labelWidth)/2;
        labelY = max(1,axisPos(2)-labelHeight-8);
        set(hLabel,'Position',[round(labelX) round(labelY) labelWidth labelHeight]);
    end

    function initializeBlankGeometryAxis(axisHandle)
        axes(axisHandle); %#ok<MAXES>
        image(0);
        colormap(gray);
        axis image off;
    end

    function overlays = createGeometryOverlayHandles(axisHandle)
        overlays.slice = rectangle('Parent',axisHandle,'EdgeColor','r','Visible','off');
        overlays.center = rectangle('Parent',axisHandle,'EdgeColor','y','Visible','off');
        overlays.volume = rectangle('Parent',axisHandle,'EdgeColor','g','Visible','off');
    end

    function inputCmd = initializeInputCmd()
        inputCmd = cell(15,2);
        inputCmd(:) = {''};
    end

    function clearInputFileSelection(rowIndex)
        inputCmd{rowIndex,1} = '';
        inputCmd{rowIndex,2} = '';
    end

    function refreshGeometryDisplay()
        global geoData inputInfo displayInfo;

        if isempty(geoData) || isempty(inputInfo) || isempty(displayInfo)
            return;
        end

        displayImages(hImages,inputInfo,displayInfo,get(hOrientationMenu,'Value'),geoData);
    end

    function [viewerData,errorMessage] = collectFieldViewerData()
        global inputInfo displayInfo;

        errorMessage = '';

        viewerData = struct();
        viewerData.StudyName = get(hStudyName,'String');
        viewerData.SequenceName = getCurrentSequenceName();
        viewerData.Nucleus = getCurrentNucleus();
        viewerData.FullMin = [displayInfo.minX, displayInfo.minY, displayInfo.minZ];
        viewerData.FullMax = [displayInfo.maxX, displayInfo.maxY, displayInfo.maxZ];
        viewerData.SampleMin = [inputInfo.minX, inputInfo.minY, inputInfo.minZ];
        viewerData.SampleMax = [inputInfo.maxX, inputInfo.maxY, inputInfo.maxZ];
        viewerData.InitialSlices = [inputInfo.currentX, inputInfo.currentY, inputInfo.currentZ];
        [viewerData.TxMag,~,errorMessage] = getEffectiveTxMagMat();
        if ~isempty(errorMessage)
            viewerData = struct();
            return;
        end
        viewerData.TxPhs = Tx.PhsMat(:);
        viewerData.RF = struct(...
            'Duration',str2double(get(hRF_Duration,'String')),...
            'Num',str2double(get(hRF_Num,'String')),...
            'Shape',get(hRF_Shape,'Value'));
        viewerData.B1pFiles = buildInputFileList(inputCmd{5,1},inputCmd{5,2});
        viewerData.B1mFiles = buildInputFileList(inputCmd{7,1},inputCmd{7,2});
        viewerData.E1pFiles = buildInputFileList(inputCmd{6,1},inputCmd{6,2});
        viewerData.E1mFiles = buildInputFileList(inputCmd{8,1},inputCmd{8,2});
    end

    function fileList = buildInputFileList(pathData,fileData)
        fileList = {};

        if isempty(pathData) || isempty(fileData)
            return;
        end

        if iscell(fileData)
            if ~iscell(pathData) || numel(pathData) ~= numel(fileData)
                return;
            end

            fileList = cell(numel(fileData),1);
            for idx = 1:numel(fileData)
                fileList{idx} = [pathData{idx},fileData{idx}];
            end
            return;
        end

        if iscell(pathData)
            if isempty(pathData)
                return;
            end
            pathData = pathData{1};
        end

        fileList = {[pathData,fileData]};
    end

    function updateFieldViewerButtonState()
        hasGeometry = ~isempty(inputCmd{1,1}) && exist([inputCmd{1,1},inputCmd{1,2}],'file') == 2;
        hasFieldFiles = ~isempty(buildInputFileList(inputCmd{5,1},inputCmd{5,2})) || ...
            ~isempty(buildInputFileList(inputCmd{6,1},inputCmd{6,2})) || ...
            ~isempty(buildInputFileList(inputCmd{7,1},inputCmd{7,2})) || ...
            ~isempty(buildInputFileList(inputCmd{8,1},inputCmd{8,2}));

        if hasGeometry && hasFieldFiles
            set(hFields,'Enable','on');
        else
            set(hFields,'Enable','off');
        end
    end

    function success = rebuildDisplayedGeometry(displaySelection)
        global geoData inputInfo displayInfo inputGeoData;

        success = false;
        if isempty(inputGeoData)
            success = true;
            return;
        end

        if displaySelection == 1
            inputTissData = [];
        else
            inputTissData = loadTissueDisplayData();
            if isempty(inputTissData)
                return;
            end
        end

        for n = 1:length(inputGeoData(4,:))
            if inputInfo.currentX == inputGeoData(1,n) || inputInfo.currentY == inputGeoData(2,n) || inputInfo.currentZ == inputGeoData(3,n)
                xIndex = inputGeoData(1,n) + displayInfo.geoDeltaX;
                yIndex = inputGeoData(2,n) + displayInfo.geoDeltaY;
                zIndex = inputGeoData(3,n) + displayInfo.geoDeltaZ;

                if displaySelection == 1
                    geoData(xIndex,yIndex,zIndex) = inputGeoData(4,n);
                else
                    tempResult = find(inputTissData{1} == inputGeoData(4,n),1);
                    if isempty(tempResult)
                        tempStr = ['Tissue Type ',num2str(inputGeoData(4,n)),' not Found in File!'];
                        errordlg(tempStr,'modal');
                        return;
                    end

                    geoData(xIndex,yIndex,zIndex) = inputTissData{displaySelection}(tempResult);
                end
            end
        end

        success = true;
    end

    function inputTissData = loadTissueDisplayData()
        currentTissueDisplayFile = [inputCmd{2,1}, inputCmd{2,2}];
        currentTissueDisplayInfo = dir(currentTissueDisplayFile);
        if ~isempty(cachedTissueDisplayData) && strcmp(cachedTissueDisplayFile,currentTissueDisplayFile)
            if ~isempty(currentTissueDisplayInfo) && isequal(cachedTissueDisplayStamp,currentTissueDisplayInfo(1).datenum)
                configureTissueDisplayMenu(cachedTissueDisplayData.displayLabels);
                inputTissData = cachedTissueDisplayData.displayValues;
                return;
            end
        end

        inputTissData = [];
        try
            tissueDisplayData = readTissuePropertyFile(currentTissueDisplayFile);
        catch tissueError
            errordlg(tissueError.message,'Invalid Tissue Property File','modal');
            return;
        end

        configureTissueDisplayMenu(tissueDisplayData.displayLabels);
        inputTissData = tissueDisplayData.displayValues;

        cachedTissueDisplayFile = currentTissueDisplayFile;
        if isempty(currentTissueDisplayInfo)
            cachedTissueDisplayStamp = [];
        else
            cachedTissueDisplayStamp = currentTissueDisplayInfo(1).datenum;
        end
        cachedTissueDisplayData = tissueDisplayData;
    end

    function configureTissueDisplayMenu(labels)
        currentLabels = get(hDisplayMenu,'String');
        if ischar(currentLabels)
            currentLabels = cellstr(currentLabels);
        end
        currentValue = get(hDisplayMenu,'Value');
        currentLabel = 'ID';
        if currentValue >= 1 && currentValue <= numel(currentLabels)
            currentLabel = currentLabels{currentValue};
        end
        newValue = find(strcmp(labels,currentLabel),1);
        if isempty(newValue) && strcmp(currentLabel,'T2') && any(strcmp(labels,'T2s'))
            newValue = find(strcmp(labels,'T2s'),1);
        end
        if isempty(newValue)
            newValue = 1;
        end
        set(hDisplayMenu,'String',labels,'Value',newValue);
    end

    function invalidateTissueDisplayCache()
        cachedTissueDisplayFile = '';
        cachedTissueDisplayStamp = [];
        cachedTissueDisplayData = [];
    end

    function success = restoreLoadedSequencePreview()
        global inputInfo displayInfo;
        updateRadialAxisControls();

        success = false;

        if isempty(inputCmd{4,1}) || exist([inputCmd{4,1},inputCmd{4,2}],'file') ~= 2
            set(hSeqPlot,'Enable','off');
            return;
        end

        tempAddr = addr;
        try
            settings = readSequenceControls();
            TI.duration = str2double(get(hTI,'String'));
            slice = readSequenceSlice(inputInfo);
            sequenceIndex = get(hSeqType,'Value');
            sequenceNames = get(hSeqType,'String');
            sequenceState.previewWaveform = dispatchSequence(sequenceNames{sequenceIndex},sequenceIndex,settings,slice,TI);

            set(hSeqPlot,'Enable','on');
            displayInfo.HideFOVOverlay = false;
            success = true;
        catch
            set(hSeqPlot,'Enable','off');
        end

        cd(tempAddr);
    end

    function runDir = resolveRunDirectory(tempMode, studyName)
        studyDir = getStudyDir(studyName);

        if tempMode == 3
            runDir = createRunDirectory(studyDir,'_noise');
            return;
        end
        if tempMode == 1
            runDir = createRunDirectory(studyDir,'_signal');
        elseif isempty(activeRunDir) || ~strcmp(activeRunStudy,studyName) || ...
                exist(activeRunDir,'dir') ~= 7 || ~runProtocolMatchesCurrent(activeRunDir,studyName)
            runDir = createRunDirectory(studyDir,'');
        else
            runDir = activeRunDir;
        end

        activeRunDir = runDir;
        activeRunStudy = studyName;
    end

    function studyDir = getStudyDir(studyName)
        studyDir = [protocolRoot,'\',studyName,'\'];
    end

    function initializeStudyOutputPaths(studyName)
        studyDir = getStudyDir(studyName);
        inputCmd{12,1}=studyDir; inputCmd{12,2}=[studyName,'.ksig']; % KSpace FileName
        inputCmd{13,1}=studyDir; inputCmd{13,2}=[studyName,'.ktrj']; % KMap FileName
        inputCmd{14,1}=studyDir; inputCmd{14,2}=[studyName,'.nois']; % Noise FileName
        inputCmd{15,1}=studyDir; inputCmd{15,2}=[studyName,'.sar']; % SAR FileName
    end

    function message = validateNewStudyName(studyName)
        message = '';
        if isempty(studyName)
            message = 'Enter a protocol name.';
            return;
        end
        if length(studyName) > 30
            message = 'Protocol names are limited to 30 characters.';
            return;
        end
        if ~isempty(regexp(studyName,'[<>:"/\\|?*\x00-\x1F]','once'))
            message = 'The protocol name contains a character that is not valid in a Windows folder name.';
            return;
        end
        if studyName(end) == '.' || studyName(end) == ' '
            message = 'The protocol name cannot end with a period or space.';
            return;
        end

        reservedName = regexpi(studyName,...
            '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$','once');
        if ~isempty(reservedName)
            message = 'That name is reserved by Windows. Choose a different protocol name.';
        end
    end

    function runDir = createRunDirectory(studyDir, typeSuffix)
        if exist(studyDir,'dir') ~= 7
            mkdir(studyDir);
        end

        timeStamp = datestr(now,'yyyymmdd_HHMMSS');
        runDir = [studyDir,'run_',timeStamp,typeSuffix,'\'];
        suffix = 1;

        while exist(runDir,'dir') == 7
            runDir = [studyDir,'run_',timeStamp,'_',num2str(suffix),typeSuffix,'\'];
            suffix = suffix + 1;
        end

        mkdir(runDir);
    end

    function filePath = getStudyFilePath(baseDir, studyName, extension)
        filePath = [baseDir,studyName,extension];
    end

    function match = runProtocolMatchesCurrent(runDir, studyName)
        match = false;

        currentProtocolFile = getStudyFilePath(getStudyDir(studyName),studyName,'.prot');
        runProtocolFile = getStudyFilePath(runDir,studyName,'.prot');

        if exist(currentProtocolFile,'file') ~= 2 || exist(runProtocolFile,'file') ~= 2
            return;
        end

        match = strcmp(fileread(currentProtocolFile),fileread(runProtocolFile));
    end

    function success = copyRunProtocolFile(runDir, studyName)
        sourceFile = getStudyFilePath(getStudyDir(studyName),studyName,'.prot');
        targetFile = getStudyFilePath(runDir,studyName,'.prot');
        [success,message] = copyfile(sourceFile,targetFile,'f');

        if success ~= 1
            errordlg(['Unable to copy protocol file: ',message],'File Error');
        end
    end

    function [success,runSequenceFile] = copyRunSequenceFile(runDir, studyName)
        success = 0;
        runSequenceFile = '';

        sourceFile = [inputCmd{4,1},inputCmd{4,2}];
        if isempty(inputCmd{4,1}) || exist(sourceFile,'file') ~= 2
            errordlg('Please Specify Sequence Filename.','modal');
            return;
        end

        runSequenceFile = getStudyFilePath(runDir,studyName,'.seqn');
        if strcmpi(sourceFile,runSequenceFile)
            success = 1;
            return;
        end

        [success,message] = copyfile(sourceFile,runSequenceFile,'f');

        if success ~= 1
            errordlg(['Unable to copy sequence file: ',message],'File Error');
            runSequenceFile = '';
        end
    end

end
   
