function ThermalPro_v8_82
    % ThermalPro v8.82 - EBWAM Analysis (Full-Sequence Auto Calibration)
    %
    % [FIX LOG v8.82 (Latest)]
    % 1. FEATURE (Auto Sequence): Added onAutoSequence — one-click full-frame boundary
    %    detection. Replaces manual frame-by-frame anchor picking. Scans all frames,
    %    detects melt pool boundaries via gradient analysis, fills gaps with linear
    %    interpolation, applies moving median denoising, and stores anchors at regular
    %    intervals. Includes cancel support, progress bar, and post-capture review chart.
    % 2. FEATURE (Anchor Review): Added showAnchorReview chart showing raw boundary temps,
    %    smoothed curve, refTemp reference line, and stored anchor positions.
    % 3. ENHANCEMENT: detectMeltPoolBoundaryTemp now accepts optional minRadials parameter
    %    for quality threshold control (default 3 for single-frame, 15 for auto-sequence).
    % 4. BUG FIX (Export Processed Data): Removed save-v7.3 pre-creation step that squeezed
    %    trailing singleton dimensions, causing 3D index into 2D variable error.
    % 5. BUG FIX (Save Project): Same save-v7.3 dimenson trap. Now writes params and
    %    pre-allocates data directly via matfile without intermediate save.
    % 6. BUG FIX (Manual Anchor Picking): onMouseDown now uses getProcessedFrame instead of
    %    S.hImg.CData, preventing coordinate-space mismatch when stabilization is active.
    % 7. BUG FIX (Stab Target Without Rendered Frame): onSetStabTarget now uses
    %    getProcessedFrame for image dimensions instead of S.hImg.CData which may be empty.
    %
    % [FIX LOG v8.81]
    % 1. PHYSICS FIX (Melt Pool Boundary Calibration): Replaced global-max auto-catch with
    %    gradient-based melt pool boundary detection (detectMeltPoolBoundaryTemp).
    %    The solid-liquid interface is a thermodynamically guaranteed isotherm,
    %    providing a calibration anchor independent of beam power or emissivity.
    % 2. PHYSICS FIX (maskWeights Normalization): Replaced dispLow and localMax with
    %    physical constants physFloor (bgCurve or 25 C) and physCeil (refTemp).
    %    maskWeights are now invariant to display settings and frame-to-frame variations.
    %
    % [FIX LOG v8.80]
    % 1. BUG FIX (Auto Max Global Max-Point Shift): Fix onAutoCatch reading coordinates from screen-rendered (hImg.CData) image causing position shift after stabilization。
    %    Now uses getProcessedFrame for true calibrated coordinates, applying stabilization offset to display circle for alignment with corrected thermal image。
    % 2. BUG FIX (UI Hang After Closing Progress Bar): Added Cancel button to 5 long-computation progress bars:「Cancel」button：
    %    onCalcArea / onCalcMotion / calcBackgroundCurve / extractTimeProfile / onSetLocalAnchor
    %    Each loop iteration checks cancel state;Cancel closing or clicking Cancel immediately exits loop and releases UI.Cancel。
% 3. PHYSICS FIX (HAZ Threshold): Changed default T_htw from 600 C to 980 C (TC4 beta-transus ~980 C).
%    Previous 600 C default was incompatible with metallographic HAZ definition。
    %
    % [FIX LOG v8.79]
    % 1. RELIABILITY: Fixed reference temperature sync, stabilization rollback, dynamic-anchor ordering, and NDT profile bounds.
    % 2. PROJECT RECOVERY: Extended project save/load to preserve NDT, thermal-cycle, anchor, ROI, and plotting state.
    % 3. DATA SAFETY: Added numeric validation, FPS synchronization, safer heat-curve parsing, and chunked MAT export.
    % 4. UI PREP: Added theme/layout preference tokens and reusable validation helpers for the upcoming UI modernization.
    %
    % [FIX LOG v8.78]
    % 1. AREA DIMENSIONAL ANALYSIS: Upgraded morph-engine to extract BoundingBox dims (Size H / Size L).
    % 2. MULTI-CHART SYNC: Replaced single Area Axes with a 3-tab ui-group (Area, Size H, Size L).
    % 3. GLOBAL PROGRESS TRACKER: Extended progress line logic into all Area-based sub-charts.
    % 4. DYNAMIC SCALING: Strictly isolated quadratic scaling (Area: mm^2) from linear scaling (Length: mm).
    % 5. WYSIWYG OVERLAY: Rendered dynamic bounding geometry for Melt Pool and HTW within the contour tracking view.

    %% --- Global State Variables ---
    S = struct();
    S.matObj = []; S.dataName = ''; S.N = 0; S.frameIdx = 1;
    S.isLoaded = false; S.hImg = []; S.playTimer = [];
    S.fps = 5; 
    S.plotXMode = 'Time'; 
    
    % Global View State for A2 Mode
    S.viewMode = 'PROC'; % Can be 'PROC' or 'RAW'
    
    S.hUI = struct();
    S.uiPrefs = struct('theme', 'CodexDesktop', 'layoutVersion', 'legacy-compatible', 'density', 'compact');
    
    % Image Processing Parameters
    S.preproc = struct();
    S.preproc.denoiseType = 'None'; 
    S.preproc.denoiseParam = 3;      
    S.preproc.claheSchedule = [];   
    
    % Vapor/Calibration State
    S.vapor = struct();
    S.vapor.enabled = false;
    S.vapor.refTemp = 1500;     % Global Default
    S.vapor.refSchedule = [];   % [StartF, EndF, RefT]
    S.vapor.anchors = [];       % Legacy Anchors
    S.vapor.isPicking = false; 
    S.vapor.gammaSchedule = []; 
    S.vapor.bgRect = []; S.vapor.bgCurve = []; S.vapor.bgRefVal = 0; % De-haze
    
    S.hAutoCircle = [];         
    
    % Calibration Mode
    S.calibMode = 'Single';     % 'Single' or 'Multi'
    S.heatCurve = [];           
    S.layers = struct('id',{},'sampleF',{},'measPeak',{},'startF',{},'endF',{},'Q',{},'targetT',{},'offset',{});
    S.physics = struct('refQ', 100, 'refT', 1500); 
    
    % Stabilization
    S.stab = struct();
    S.stab.enabled = false;
    S.stab.refFrameIdx = 1;
    S.stab.initialRect = [];    
    S.stab.shifts = [];         
    S.stab.anchorOffset = [0, 0]; 
    S.stab.isCalculated = false;
    S.stab.autoMode = true;     
    
    % Dynamic ROI Anchoring (Local Feature Tracking)
    S.dynamicAnchor = struct('isActive', false, 'refFrame', 1, 'refRect', [], 'localShifts', [], 'isCalculated', false);
    S.analysisBaseCoords = {}; % Stores original coords for dynamic rendering
    
    % Area Analysis Parameters (Expanded in v8.78)
    S.area = struct();
    S.area.enabled = false;          
    S.area.T_melt = 1400;            
    S.area.T_htw = 980;
    S.area.mpHistory = [];
    S.area.htwHistory = [];          
    S.area.hMPHistory = [];          % [NEW] Size H for MP
    S.area.lMPHistory = [];          % [NEW] Size L for MP
    S.area.hHTWHistory = [];         % [NEW] Size H for HTW
    S.area.lHTWHistory = [];         % [NEW] Size L for HTW
    S.area.morphKernel = 3;          
    S.area.plotMode = 1;             
    S.area.proximityThresh = 2.0;    
    S.area.minRatio = 20.0;          
    S.area.forcedFrames = [];        
    S.area.blacklistedFrames = [];   
    S.area.isCalibrated = false;     
    S.area.pxPerMm = 1.0;            
    
    % NDT Ground Truth Mapping Data
    S.ndt = struct();
    S.ndt.gtTable = cell(0, 4); % {ID, TrueDepth, RawZ, ProcZ}
    S.ndt.baselinePos = [];     
    S.ndt.layerLinesRaw = {};   
    S.ndt.layerLinesProc = {};  
    S.ndt.selectedRow = [];     
    
    % Analysis Data
    S.pointDataCell = {}; S.allMarkerFrames = {}; 
    S.hPointMarkers = []; S.hPointTexts = []; S.hPlotLines = []; 
    S.hRectOutlines = []; 
    S.roiLines = []; S.hLines = struct('Ts',[], 'Te',[], 'Tr',[]);
    S.draggingLine = []; 
    S.selectMode = false; S.currentROI = []; S.hBoxObj = [];
    S.selectedIndices = []; S.hPermanentHighlights = []; S.hHoverHighlight = [];        
    
    % Progress Line Tracker (Expanded in v8.78)
    S.showProgressLine = false;
    S.hProgressLine = [];
    S.hProgressLineArea = []; % [NEW]
    S.hProgressLineH = [];    % [NEW]
    S.hProgressLineL = [];    % [NEW]
    
    %% --- UI Construction ---
    fig = figure('Name','ThermalPro v8.80 | EBWAM Interactive Lab','NumberTitle','off',...
        'Color',[0.94 0.94 0.94], 'Units','pixels', 'Position', [50 50 1550 900], ...
        'WindowButtonDownFcn', @onMouseDown, ...
        'WindowButtonUpFcn', @onMouseUp, ...
        'WindowButtonMotionFcn', @onMouseMoveGlobal, ...
        'CloseRequestFcn', @onMainClose);
    
    % --- Left Layout (Video) ---
    S.hUI.lblFileName = uicontrol('Parent', fig, 'Style', 'text', 'String', 'Current File: None', ...
        'Units', 'normalized', 'Position', [.05 .94 .60 .03], ...
        'HorizontalAlignment', 'left', 'FontSize', 10, 'FontWeight', 'bold', ...
        'BackgroundColor', [0.94 0.94 0.94], 'ForegroundColor', [.2 .2 .2]);
        
    axMain = axes('Parent',fig,'Units','normalized','Position',[.05 .25 .60 .65],...
        'Color',[.1 .1 .1],'XColor',[.3 .3 .3],'YColor',[.3 .3 .3],'Tag','axMain');
    axMain.Toolbar.Visible = 'off';
    
    S.hUI.sld = uicontrol('Style','slider','Min',1,'Max',100,'Value',1,...
        'Units','normalized','Position',[.05 .17 .60 .03]);
    addlistener(S.hUI.sld, 'Value', 'PostSet', @(src,ev) updateFrame(round(get(S.hUI.sld,'Value'))));
    
    uicontrol('Style','pushbutton','String','◀','Units','normalized',...
        'Position',[.05 .11 .06 .04],'Callback',@(~,~) shiftFrame(-1));
    S.hUI.btnPlay = uicontrol('Style','togglebutton','String','> Play','Units','normalized',...
        'Position',[.25 .11 .2 .04],'Callback',@onPlayToggle);
    uicontrol('Style','pushbutton','String','▶','Units','normalized',...
        'Position',[.59 .11 .06 .04],'Callback',@(~,~) shiftFrame(1));
        
    % --- Right Control Panel ---
    pSide = uipanel('Parent',fig,'Title','Control Panel','FontSize',11,'FontWeight','bold',...
        'Units','normalized','Position',[.67 .05 .32 .9],'BackgroundColor', [1 1 1]);
        
    % 1) Data Loading
    uicontrol('Parent',pSide,'Style','pushbutton','String','Open .MAT Data File',...
        'Units','normalized','Position',[.05 .94 .9 .045],'BackgroundColor',[.2 .6 .9],...
        'ForegroundColor','w', 'FontWeight','bold','Callback',@onLoadFile);
        
    % Dual Export
    uicontrol('Parent',pSide,'Style','pushbutton','String','Save Project',...
        'Units','normalized','Position',[.05 .89 .44 .045],'BackgroundColor',[.8 .9 .8],...
        'TooltipString','Saves RAW data + Parameters. Revertable.',...
        'Callback',@onExportProject); 
        
    uicontrol('Parent',pSide,'Style','pushbutton','String','Export Processed Data',...
        'Units','normalized','Position',[.51 .89 .44 .045],'BackgroundColor',[.95 .8 .8],...
        'TooltipString','Saves PROCESSED data only. Not Revertable.',...
        'Callback',@onExportBaked);
    
    uicontrol('Parent',pSide,'Style','text','String','Display Range:','Units','normalized',...
        'Position',[.05 .85 .45 .02],'HorizontalAlignment','left','BackgroundColor',[1 1 1]);
    S.hUI.efLow = uicontrol('Parent',pSide,'Style','edit','String','500','Units','normalized',...
        'Position',[.05 .82 .2 .03],'Callback',@(~,~) updateVisuals());
    S.hUI.efHigh = uicontrol('Parent',pSide,'Style','edit','String','1500','Units','normalized',...
        'Position',[.28 .82 .2 .03],'Callback',@(~,~) updateVisuals());
        
    % MP4 Video Export Button
    uicontrol('Parent',pSide,'Style','pushbutton','String',' Export View to MP4',...
        'Units','normalized','Position',[.51 .815 .44 .035],'BackgroundColor',[.15 .65 .45],...
        'ForegroundColor','w','FontWeight','bold','Callback',@onExportMP4,...
        'TooltipString','Captures current view including all trackers and exports to MP4.');
        
    % 2) Multi-function Tabs
    mainTabGroup = uitabgroup('Parent',pSide,'Units','normalized','Position',[.02 .01 .96 .80]);
    
    % === Tab A: Pre-proc ===
    tabPreProc = uitab('Parent',mainTabGroup, 'Title', 'Pre-proc');
    
    % --- Panel 1: Stabilization ---
    pStab = uipanel('Parent',tabPreProc,'Title','1. Auto Stabilization (Centered)','FontSize',10,...
        'Units','normalized','Position',[.02 .75 .96 .23],'BackgroundColor',[1 1 1]);
    
    uicontrol('Parent',pStab,'Style','pushbutton','String',' Auto Track (Fix Substrate)',...
        'Units','normalized','Position',[.05 .55 .55 .30],'BackgroundColor',[.85 .9 .95],...
        'FontWeight','bold','Callback',@onAutoCalcMotion);
        
    uicontrol('Parent',pStab,'Style','pushbutton','String','Manual Box',...
        'Units','normalized','Position',[.62 .55 .33 .30],'Callback',@onSetStabTarget);
        
    S.hUI.chkStabApply = uicontrol('Parent',pStab,'Style','checkbox','String','Apply Stabilization',...
        'Units','normalized','Position',[.05 .25 .9 .2],'BackgroundColor',[1 1 1],...
        'Enable','off','Callback',@(~,~) updateVisuals()); 
    S.hUI.lblStabStatus = uicontrol('Parent',pStab,'Style','text','String','Status: Not Calculated',...
        'Units','normalized','Position',[.05 .05 .9 .2],'ForegroundColor',[.6 .6 .6],'BackgroundColor',[1 1 1]);
        
    % --- Panel 2: Vapor Compensation (DUAL MODE) ---
    pVapor = uipanel('Parent',tabPreProc,'Title','2. Calibration & De-Haze','FontSize',10,...
        'Units','normalized','Position',[.02 .30 .96 .44],'BackgroundColor',[1 1 1]);
    
    % Mode Selection
    uicontrol('Parent',pVapor,'Style','text','String','Calib Mode:',...
        'Units','normalized','Position',[.05 .88 .30 .08],'HorizontalAlignment','left','BackgroundColor',[1 1 1]);
    S.hUI.popCalibMode = uicontrol('Parent',pVapor,'Style','popupmenu',...
        'String',{'Mode A: Single Ref (Global)', 'Mode B: Multi-Layer (Heat Map)'},...
        'Units','normalized','Position',[.35 .88 .60 .08],'Callback',@onModeChange);
    % De-Haze (Common)
    uicontrol('Parent',pVapor,'Style','pushbutton','String',' Set Clean BG (De-Haze)',...
        'Units','normalized','Position',[.05 .72 .90 .12],'BackgroundColor',[.8 .8 .8],...
        'Callback',@onSetBackgroundBox);
    S.hUI.lblBgStatus = uicontrol('Parent',pVapor,'Style','text','String','BG Correction: None',...
        'Units','normalized','Position',[.05 .65 .9 .06],'HorizontalAlignment','center',...
        'ForegroundColor',[.5 .5 .5],'FontSize',9,'BackgroundColor',[1 1 1]);
    
    S.hUI.lblActiveRef = uicontrol('Parent',pVapor,'Style','text','String','Active: 1500 (Global)',...
        'Units','normalized','Position',[.05 .58 .90 .06],'HorizontalAlignment','center',...
        'ForegroundColor', 'b', 'FontWeight','bold', 'BackgroundColor',[1 1 1]);
        
    % Dynamic Panel Content
    % Group A: Single Ref Controls
    S.hUI.panelSingle = uipanel('Parent',pVapor,'BorderType','none','BackgroundColor',[1 1 1],...
        'Units','normalized','Position',[0 .14 1 .42]);
        
    uicontrol('Parent',S.hUI.panelSingle,'Style','text','String','Ref Temp (°C):','Units','normalized',...
        'Position',[.05 .75 .35 .2],'HorizontalAlignment','left','BackgroundColor',[1 1 1]);
    S.hUI.efRefTemp = uicontrol('Parent',S.hUI.panelSingle,'Style','edit','String','1500',...
        'Units','normalized','Position',[.45 .78 .50 .2],'Callback',@onVaporConfigChange);
        
    S.hUI.btnPick = uicontrol('Parent',S.hUI.panelSingle,'Style','pushbutton','String','+ Anchor Point (Pick)',...
        'Units','normalized','Position',[.05 .50 .44 .20],'Callback',@onTogglePicking);
    S.hUI.btnAutoCatch = uicontrol('Parent',S.hUI.panelSingle,'Style','pushbutton','String','Auto Max',...
        'Units','normalized','Position',[.51 .50 .44 .20],'Callback',@onAutoCatch,'Enable', 'off');

    uicontrol('Parent',S.hUI.panelSingle,'Style','pushbutton','String','Auto Sequence (All Frames)',...
        'Units','normalized','Position',[.05 .30 .90 .15],...
        'BackgroundColor',[0.3 0.6 0.9],'ForegroundColor','w','FontWeight','bold',...
        'TooltipString','Automatically scan all frames for melt pool boundaries.',...
        'Callback',@onAutoSequence);

    uicontrol('Parent',S.hUI.panelSingle,'Style','pushbutton','String',' View/Edit Data Table (Popup)',...
        'Units','normalized','Position',[.05 .03 .90 .22],'BackgroundColor',[.9 1 .9],...
        'Callback', @onShowAnchorTable);
        
    % Group B: Multi-Layer Controls
    S.hUI.panelMulti = uipanel('Parent',pVapor,'BorderType','none','BackgroundColor',[1 1 1],...
        'Units','normalized','Position',[0 .14 1 .42], 'Visible', 'off');
    
    uicontrol('Parent',S.hUI.panelMulti,'Style','pushbutton','String',' Open Layer Manager',...
        'Units','normalized','Position',[.05 .60 .90 .30],'BackgroundColor',[.6 .8 1],...
        'FontWeight','bold', 'FontSize', 10, 'Callback',@onLayerManager, ...
        'TooltipString', 'Interactive table to define layers and capture peak temps.');
        
    S.hUI.lblMultiStatus = uicontrol('Parent',S.hUI.panelMulti,'Style','text','String','Layers: 0 | Heat Curve: No',...
        'Units','normalized','Position',[.05 .30 .90 .20],'HorizontalAlignment','center',...
        'ForegroundColor', 'b', 'BackgroundColor',[1 1 1]);
        
    uicontrol('Parent',S.hUI.panelMulti,'Style','pushbutton','String',' Import/View Heat Curve',...
        'Units','normalized','Position',[.05 .05 .90 .20],'BackgroundColor',[.95 .85 1],...
        'Callback',@onHeatCurveMenu);
    % Common Apply
    S.hUI.chkVaporApply = uicontrol('Parent',pVapor,'Style','checkbox','String','Apply Correction',...
        'Units','normalized','Position',[.05 .02 .90 .10],'BackgroundColor',[1 1 1],...
        'FontWeight','bold','Callback',@onVaporConfigChange);
    % --- Panel 3: Filter ---
    pFilter = uipanel('Parent',tabPreProc,'Title','3. Filter & Enhance','FontSize',10,...
        'Units','normalized','Position',[.02 .01 .96 .28],'BackgroundColor',[1 1 1]);
    
    uicontrol('Parent',pFilter,'Style','text','String','Filter Type:','HorizontalAlignment','left',...
        'Units','normalized','Position',[.05 .75 .25 .15],'BackgroundColor',[1 1 1]);
    S.hUI.popDenoise = uicontrol('Parent',pFilter,'Style','popupmenu','String',{'None','Median (Salt&Pepper)','Gaussian (Smooth)','Despeckle (Morph)'},...
        'Units','normalized','Position',[.35 .76 .40 .15],'Callback',@onFilterConfigChange);
    S.hUI.editDenoiseParam = uicontrol('Parent',pFilter,'Style','edit','String','3',...
        'Units','normalized','Position',[.80 .78 .15 .15],'Callback',@onFilterConfigChange);
    
    uicontrol('Parent',pFilter,'Style','text','String','CLAHE (Range:Clip):','HorizontalAlignment','left',...
        'Units','normalized','Position',[.05 .45 .9 .15],'BackgroundColor',[1 1 1],'FontWeight','bold');
    uicontrol('Parent',pFilter,'Style','text','String','Ex: 1-100:0.01; 101-200:0.02',...
        'Units','normalized','Position',[.05 .32 .9 .12],'HorizontalAlignment','left',...
        'BackgroundColor',[1 1 1],'ForegroundColor',[.4 .4 .4],'FontSize',8);
    S.hUI.editCLAHEConfig = uicontrol('Parent',pFilter,'Style','edit','String','',...
        'Units','normalized','Position',[.05 .05 .9 .25],'HorizontalAlignment','left',...
        'Callback',@onFilterConfigChange);
        
    % === Tab B: Temp Analysis ===
    tabTempAnalysis = uitab('Parent',mainTabGroup, 'Title', 'Temp Analysis');
    
    uicontrol('Parent',tabTempAnalysis,'Style','text','String','Current Focus:',...
        'Units','normalized','Position',[.05 .93 .30 .03],'HorizontalAlignment','left','BackgroundColor',[1 1 1]);
    S.hUI.selFocus = uicontrol('Parent',tabTempAnalysis,'Style','popupmenu','String',{' '},...
        'Units','normalized','Position',[.35 .93 .60 .04],'Callback', @(~,~) refreshMarkers());
    
    % Parameter Grid
    uicontrol('Parent',tabTempAnalysis,'Style','text','String','Ts Thresh:','Units','normalized',...
        'Position',[.05 .87 .20 .03],'HorizontalAlignment','right');
    S.hUI.efTStart = uicontrol('Parent',tabTempAnalysis,'Style','edit','String','1000','Units','normalized',...
        'Position',[.26 .87 .20 .04]);
        
    uicontrol('Parent',tabTempAnalysis,'Style','text','String','Te Thresh:','Units','normalized',...
        'Position',[.52 .87 .20 .03],'HorizontalAlignment','right');
    S.hUI.efTEnd = uicontrol('Parent',tabTempAnalysis,'Style','edit','String','600','Units','normalized',...
        'Position',[.74 .87 .20 .04]);
        
    uicontrol('Parent',tabTempAnalysis,'Style','text','String','FPS (Hz):','Units','normalized',...
        'Position',[.05 .81 .20 .03],'HorizontalAlignment','right');
    S.hUI.efFPS = uicontrol('Parent',tabTempAnalysis,'Style','edit','String','5',... 
        'Units','normalized','Position',[.26 .81 .20 .04], 'Callback', @onFPSChange);
        
    S.hUI.chkShowTrough = uicontrol('Parent',tabTempAnalysis,'Style','checkbox','String','Show Trough Min',...
        'Units','normalized','Position',[.55 .81 .40 .04],'Value',0,'BackgroundColor',[1 1 1],'Callback', @(~,~) refreshMarkers());
        
    % Dynamic Anchor Panel
    pAnc = uipanel('Parent',tabTempAnalysis,'Title','Dynamic Anchor (Sub-pixel Wobble Fix)',...
        'FontSize',9,'Units','normalized','Position',[.02 .68 .96 .11],'BackgroundColor', [1 1 1]);
    uicontrol('Parent',pAnc,'Style','pushbutton','String',' Set Anchor',...
        'Units','normalized','Position',[.02 .1 .35 .8],'Callback',@onSetLocalAnchor,...
        'BackgroundColor', [.8 .9 .95], 'FontWeight', 'bold');
    S.hUI.chkLinkAnchor = uicontrol('Parent',pAnc,'Style','checkbox','String','Link ROI',...
        'Units','normalized','Position',[.40 .1 .28 .8],'Value',0,'Enable','off','BackgroundColor', [1 1 1]);
    S.hUI.lblAnchorStatus = uicontrol('Parent',pAnc,'Style','text','String','Not Set',...
        'Units','normalized','Position',[.70 .1 .28 .6],'ForegroundColor',[.6 .6 .6],'BackgroundColor', [1 1 1]);

    % Tool Grid
    uicontrol('Parent',tabTempAnalysis,'Style','pushbutton','String','+ Point',...
        'Units','normalized','Position',[.05 .61 .44 .05],'Callback',@(~,~) addROI('point'));
    uicontrol('Parent',tabTempAnalysis,'Style','pushbutton','String','+ Rect Area',...
        'Units','normalized','Position',[.51 .61 .44 .05],'Callback',@(~,~) addROI('rect_mean'));
    uicontrol('Parent',tabTempAnalysis,'Style','pushbutton','String','Analysis Section',...
        'Units','normalized','Position',[.05 .55 .44 .05],'FontWeight','bold','Callback',@(~,~) addROI('box_select'));
    uicontrol('Parent',tabTempAnalysis,'Style','pushbutton','String','+ Line Scan',...
        'Units','normalized','Position',[.51 .55 .44 .05],'Callback',@(~,~) addROI('line'));
        
    % Action Bars
    uicontrol('Parent',tabTempAnalysis,'Style','pushbutton','String',' Curves',...
        'Units','normalized','Position',[.02 .49 .18 .05],'Callback',@onManageCurves);
    S.hUI.btnAxisTemp = uicontrol('Parent',tabTempAnalysis,'Style','pushbutton','String',' Time',...
        'Units','normalized','Position',[.21 .49 .18 .05],'Callback',@onToggleXAxis);
    S.hUI.btnProgress = uicontrol('Parent',tabTempAnalysis,'Style','pushbutton','String','Cursor:OFF',...
        'Units','normalized','Position',[.40 .49 .18 .05],'Callback',@onToggleProgressLine);
    uicontrol('Parent',tabTempAnalysis,'Style','pushbutton','String','Export CSV',...
        'Units','normalized','Position',[.59 .49 .19 .05],'BackgroundColor',[.2 .7 .3],'ForegroundColor','w','Callback',@exportToCSV);
    uicontrol('Parent',tabTempAnalysis,'Style','pushbutton','String','Clear All',...
        'Units','normalized','Position',[.79 .49 .19 .05],'ForegroundColor',[.8 0 0],'Callback',@clearROIs);
    
    tGroup = uitabgroup('Parent',tabTempAnalysis,'Units','normalized','Position',[.02 .01 .96 .46]);
    tabLog = uitab('Parent',tGroup, 'Title', 'Log');
    
    S.hUI.resBox = uicontrol('Parent',tabLog,'Style','edit','Max',100,'Min',0,'Units','normalized',...
        'Position',[.02 .02 .96 .96],'HorizontalAlignment','left','Enable','on','FontSize',9,'BackgroundColor',[.98 .98 .98]);
        
    tabPoint = uitab('Parent',tGroup, 'Title', 'Cycles');
    axPoint = axes('Parent',tabPoint,'Units','normalized','Position',[.15 .15 .80 .75],'Tag','axPoint');
    tabLine = uitab('Parent',tGroup, 'Title', 'Line Scan');
    axLine = axes('Parent',tabLine,'Units','normalized','Position',[.15 .15 .80 .75]);
    
    % === Tab C: Area Analysis (Expanded v8.78) ===
    tabAreaAnalysis = uitab('Parent',mainTabGroup, 'Title', 'Area Analysis');
    
    % --- TOP SECTION: Visuals & Multi-Chart TabGroup (Y: 0.35 - 1.0) ---
    S.hUI.lblAreaDiag = uicontrol('Parent',tabAreaAnalysis,'Style','edit','String','Waiting for analysis...',...
        'Units','normalized','Position',[.02 .94 .96 .05],'Enable','inactive','Max', 2, ...
        'BackgroundColor',[.9 .9 .9],'FontWeight','bold','HorizontalAlignment','left');
        
    % [NEW v8.78] TabGroup replacing single Area Axes
    tgAreaCharts = uitabgroup('Parent', tabAreaAnalysis, 'Units','normalized','Position',[.02 .36 .96 .56]);
    
    tabAreaPlot = uitab('Parent', tgAreaCharts, 'Title', 'Area');
    axArea = axes('Parent',tabAreaPlot,'Units','normalized','Position',[.12 .15 .83 .75],'Box','on');
    
    tabSizeHPlot = uitab('Parent', tgAreaCharts, 'Title', 'Size H (Vert/Depth)');
    axSizeH = axes('Parent',tabSizeHPlot,'Units','normalized','Position',[.12 .15 .83 .75],'Box','on');
    
    tabSizeLPlot = uitab('Parent', tgAreaCharts, 'Title', 'Size L (Horiz/Scan)');
    axSizeL = axes('Parent',tabSizeLPlot,'Units','normalized','Position',[.12 .15 .83 .75],'Box','on');

    % --- BOTTOM SECTION: Control Hub (Y: 0.0 - 0.35) ---
    subTabGroup = uitabgroup('Parent', tabAreaAnalysis, 'Position', [.02 .01 .96 .34]);
    
    % Sub-Tab 1: Auto Config
    sTabAuto = uitab('Parent', subTabGroup, 'Title', 'Auto Config');
    
    uicontrol('Parent',sTabAuto,'Style','text','String','MP T:','Units','normalized',...
        'Position',[.02 .75 .15 .15],'HorizontalAlignment','right');
    S.hUI.efAreaMP = uicontrol('Parent',sTabAuto,'Style','edit','String','1400','Units','normalized',...
        'Position',[.19 .78 .20 .15],'Callback',@onAreaConfigChange);
        
    S.hUI.chkAreaVis = uicontrol('Parent',sTabAuto,'Style','checkbox','String','Show Contour Tracking',...
        'Units','normalized','Position',[.50 .75 .45 .20],'Value', 0, 'Callback',@onAreaConfigChange);
        
    uicontrol('Parent',sTabAuto,'Style','text','String','HTW T:','Units','normalized',...
        'Position',[.02 .45 .15 .15],'HorizontalAlignment','right');
    S.hUI.efAreaHAZ = uicontrol('Parent',sTabAuto,'Style','edit','String','980','Units','normalized',...
        'Position',[.19 .48 .20 .15],'Callback',@onAreaConfigChange);
    
    uicontrol('Parent',sTabAuto,'Style','text','String','Mode:','Units','normalized',...
        'Position',[.45 .45 .15 .15],'HorizontalAlignment','right');
    S.hUI.popAreaDisplay = uicontrol('Parent',sTabAuto,'Style','popupmenu',...
        'String',{'Show All', 'MP Only', 'HTW Only'},...
        'Units','normalized','Position',[.62 .48 .30 .15],'Callback',@(~,~) plotAreaCurves());
        
    uicontrol('Parent',sTabAuto,'Style','pushbutton','String','▶ Calculate Full Frame Curve',...
        'Units','normalized','Position',[.05 .08 .90 .28],'BackgroundColor',[.8 .85 .95],...
        'FontWeight', 'bold', 'FontSize', 10, 'Callback',@onCalcArea);
    
    % Sub-Tab 2: Manual Fix
    sTabMan = uitab('Parent', subTabGroup, 'Title', 'Manual Fix');
    
    uicontrol('Parent',sTabMan,'Style','text','String','Dist (px):',...
        'Units','normalized','Position',[.01 .78 .18 .12],'HorizontalAlignment','left');
    S.hUI.efDist = uicontrol('Parent',sTabMan,'Style','edit','String','2.0',...
        'Units','normalized','Position',[.20 .80 .12 .12],'Callback',@onParamConfigChange);
        
    uicontrol('Parent',sTabMan,'Style','text','String','Ratio (1:X):',...
        'Units','normalized','Position',[.01 .48 .18 .12],'HorizontalAlignment','left');
    S.hUI.efRatio = uicontrol('Parent',sTabMan,'Style','edit','String','20.0',...
        'Units','normalized','Position',[.20 .50 .12 .12],'Callback',@onParamConfigChange);
        
    uicontrol('Parent',sTabMan,'Style','text','String','Kernel:',...
        'Units','normalized','Position',[.01 .18 .18 .12],'HorizontalAlignment','left');
    S.hUI.efMorph = uicontrol('Parent',sTabMan,'Style','edit','String','3',...
        'Units','normalized','Position',[.20 .20 .12 .12],'Callback',@onParamConfigChange);
        
    S.hUI.chkAreaDebug = uicontrol('Parent',sTabMan,'Style','checkbox','String',' Debug Mode (Show Failures)',...
        'Units','normalized','Position',[.38 .80 .60 .12],'Callback', @(~,~) updateFrame(S.frameIdx));
        
    uicontrol('Parent',sTabMan,'Style','text','String','Adjust params to see live diagnostics.',...
        'Units','normalized','Position',[.38 .68 .60 .10],'HorizontalAlignment','left', 'ForegroundColor', [.4 .4 .4], 'FontSize', 9);
    
    uicontrol('Parent',sTabMan,'Style','pushbutton','String',' Force Valid (Include)',...
        'Units','normalized','Position',[.38 .36 .58 .25],'BackgroundColor',[.8 .95 .8],...
        'TooltipString', 'Manually include frame.', 'Callback', @onForceValid);
    uicontrol('Parent',sTabMan,'Style','pushbutton','String',' Force Remove (Exclude)',...
        'Units','normalized','Position',[.38 .05 .58 .25],'BackgroundColor',[.95 .8 .8],...
        'TooltipString', 'Manually exclude frame.', 'Callback', @onForceRemove);
        
    % Sub-Tab 3: Tools
    sTabTool = uitab('Parent', subTabGroup, 'Title', 'Tools');
    
    uicontrol('Parent',sTabTool,'Style','pushbutton','String',' Calibrate Scale',...
        'Units','normalized','Position',[.05 .40 .90 .20],'BackgroundColor',[.95 .9 .8],...
        'Callback', @onCalibrateScale);
        
    S.hUI.btnAxisArea = uicontrol('Parent',sTabTool,'Style','pushbutton','String',' Toggle X-Axis',...
        'Units','normalized','Position',[.05 .70 .40 .20], 'Callback', @onToggleXAxis);
        
    % [NEW v8.78] Area-specific Progress Line Toggle
    S.hUI.btnProgressArea = uicontrol('Parent',sTabTool,'Style','pushbutton','String','Cursor:OFF',...
        'Units','normalized','Position',[.50 .70 .45 .20], 'Callback', @onToggleProgressLine);
        
    uicontrol('Parent',sTabTool,'Style','pushbutton','String',' Export CSV',...
        'Units','normalized','Position',[.05 .10 .90 .20],'Callback',@onExportAreaCSV);
    
    % === Tab D: NDT Evaluation ===
    tabNDT = uitab('Parent',mainTabGroup, 'Title', 'NDT Eval');
    
    % Section 0: Set Universal Geometric Baseline
    pBase = uipanel('Parent',tabNDT,'Title','Step 0: Universal Baseline (Absolute Zero for Layer 1)','FontSize',10,...
        'Units','normalized','Position',[.02 .85 .96 .13],'BackgroundColor',[1 1 1]);
        
    uicontrol('Parent',pBase,'Style','pushbutton','String',' Draw Global Baseline',...
        'Units','normalized','Position',[.05 .15 .50 .65],'BackgroundColor',[.9 .8 .9],'FontWeight','bold',...
        'Callback',@onSetBaseline);
        
    S.hUI.lblBaselineStatus = uicontrol('Parent',pBase,'Style','text','String','Status: Not Drawn',...
        'Units','normalized','Position',[.58 .15 .35 .65],'ForegroundColor','r','BackgroundColor',[1 1 1]);
    
    % Section 1: Phase 1 & 2 Global Button
    uicontrol('Parent',tabNDT,'Style','pushbutton','String',' Phase 1&2: Generate 4-Panel NDT Report',...
        'Units','normalized','Position',[.05 .72 .90 .11],'BackgroundColor',[.8 .9 1],'FontWeight','bold',...
        'TooltipString','Computes TTC, Profile, Temporal Cycles, and Baseline Stability.',...
        'Callback',@onGenerateNDTReport);
        
    % Section 2: Phase 3 Dynamic Geometric Correction (Automated)
    pZDepth = uipanel('Parent',tabNDT,'Title','Phase 3: Dynamic Layer Height Correction (Auto)','FontSize',10,...
        'Units','normalized','Position',[.02 .54 .96 .16],'BackgroundColor',[1 1 1]);
        
    S.hUI.chkZStartupFilter = uicontrol('Parent',pZDepth,'Style','checkbox','String','Startup Spike Filter',...
        'Units','normalized','Position',[.05 .60 .25 .30],'BackgroundColor',[1 1 1],'Value',1);
    uicontrol('Parent',pZDepth,'Style','text','String','First N Frames:',...
        'Units','normalized','Position',[.32 .58 .18 .30],'BackgroundColor',[1 1 1],'HorizontalAlignment','right');
    S.hUI.efZStartupN = uicontrol('Parent',pZDepth,'Style','edit','String','50',...
        'Units','normalized','Position',[.52 .62 .10 .25]);
    uicontrol('Parent',pZDepth,'Style','text','String','Upper Limit (px):',...
        'Units','normalized','Position',[.65 .58 .18 .30],'BackgroundColor',[1 1 1],'HorizontalAlignment','right');
    S.hUI.efZLimit = uicontrol('Parent',pZDepth,'Style','edit','String','50',...
        'Units','normalized','Position',[.85 .62 .10 .25]);
    uicontrol('Parent',pZDepth,'Style','pushbutton','String',' Extract True Layer Height Profile',...
        'Units','normalized','Position',[.05 .15 .90 .40],'BackgroundColor',[.85 .95 .85],'FontWeight','bold',...
        'Callback',@onExtractZDepth);
        
    % Section 3: Phase 4 Physical Ground-Truth Mapping (A2 Manual Mode)
    pParity = uipanel('Parent',tabNDT,'Title','Phase 4: Correlation Mapping (Expert Manual Override)','FontSize',10,...
        'Units','normalized','Position',[.02 .02 .96 .50],'BackgroundColor',[1 1 1]);
        
    S.hUI.tblGT = uitable('Parent',pParity,'Units','normalized','Position',[.02 .40 .96 .55],...
        'ColumnName', {'ID', 'True Z(mm)', 'Raw Z', 'Proc Z'}, ...
        'ColumnWidth', {35, 80, 80, 80}, ...
        'ColumnEditable', [false true true true], ... 
        'Data', S.ndt.gtTable, ...
        'CellEditCallback', @onGtCellEdit, ...
        'CellSelectionCallback', @onGtCellSelect); 
        
    uicontrol('Parent',pParity,'Style','pushbutton','String',' Add Blank Layer',...
        'Units','normalized','Position',[.05 .20 .30 .15],'Callback',@onAddGTRow);
    uicontrol('Parent',pParity,'Style','pushbutton','String',' Delete Selected Row',...
        'Units','normalized','Position',[.37 .20 .30 .15],'ForegroundColor','r','Callback',@onDelGTRow);
    
    uicontrol('Parent',pParity,'Style','pushbutton','String',' Draw Section Line',...
        'Units','normalized','Position',[.69 .20 .28 .15],'BackgroundColor',[.95 .9 .8],'FontWeight','bold',...
        'Callback',@onDrawSectionLine);
        
    S.hUI.btnViewMode = uicontrol('Parent',pParity,'Style','pushbutton','String',' View: PROC',...
        'Units','normalized','Position',[.05 .02 .44 .15],'BackgroundColor',[.46 .67 .18],...
        'ForegroundColor','w','FontWeight','bold','Callback',@onToggleViewMode);
        
    uicontrol('Parent',pParity,'Style','pushbutton','String',' Plot Chart',...
        'Units','normalized','Position',[.51 .02 .44 .15],'BackgroundColor',[.9 .8 .9],'FontWeight','bold',...
        'Callback',@onPlotParity);
        
    % Status Bar
    lblProbe = uicontrol('Style','text','String','Probe: -- °C','Units','normalized','Position',[.75 .005 .2 .025],...
        'HorizontalAlignment','right','FontWeight','bold','BackgroundColor',[0.94 0.94 0.94]);
    
    %% --- Core Data Link & Global Toggles ---
    S.playTimer = timer('ExecutionMode','fixedRate','Period',0.05,'TimerFcn',@(~,~) shiftFrame(1));

    function onMainClose(~,~)
        try
            if ~isempty(S.playTimer) && isvalid(S.playTimer)
                stop(S.playTimer);
                delete(S.playTimer);
            end
        catch
        end
        try
            delete(fig);
        catch
        end
    end

    function val = readPositiveScalar(hCtrl, fallback, label, showDialog)
        if nargin < 4, showDialog = true; end
        if isnan(fallback) || ~isfinite(fallback) || fallback <= 0
            fallback = 1;
        end
        val = fallback;
        if isgraphics(hCtrl)
            val = str2double(get(hCtrl, 'String'));
        end
        if isnan(val) || ~isfinite(val) || val <= 0
            val = fallback;
            if isgraphics(hCtrl), set(hCtrl, 'String', num2str(fallback)); end
            if showDialog
                warndlg(sprintf('%s must be a positive number. Reverted to %.4g.', label, fallback), 'Invalid Numeric Input');
            end
        end
    end

    function fps = syncFPS(showDialog)
        if nargin < 1, showDialog = true; end
        fps = readPositiveScalar(S.hUI.efFPS, S.fps, 'FPS', showDialog);
        S.fps = fps;
    end

    function onFPSChange(~,~)
        syncFPS(true);
        refreshPointPlot();
        plotAreaCurves();
        updateFrame(S.frameIdx);
    end

    function vals = parseNumericVector(str)
        cleaned = regexprep(str, '[\[\],;\r\n\t]+', ' ');
        vals = sscanf(cleaned, '%f').';
    end
    
    % View Mode Toggle Function
    function onToggleViewMode(~,~)
        if strcmp(S.viewMode, 'PROC')
            S.viewMode = 'RAW';
            set(S.hUI.btnViewMode, 'String', ' View: RAW', 'BackgroundColor', [0.85 0.32 0.09]);
        else
            S.viewMode = 'PROC';
            set(S.hUI.btnViewMode, 'String', ' View: PROC', 'BackgroundColor', [.46 .67 .18]);
        end
        updateFrame(S.frameIdx);
    end

    function onLoadFile(~,~)
        [f, p] = uigetfile('*.mat'); if isequal(f,0), return; end
        try
            S.matObj = matfile(fullfile(p, f)); allVars = whos(S.matObj);
            set(S.hUI.lblFileName, 'String', ['Current File: ' f]);
            
            isProject = false;
            if any(strcmp({allVars.name}, 'ThermalProParams')), isProject = true; end
            
            targetVar = ''; maxE = 0;
            for i = 1:length(allVars)
                if length(allVars(i).size) == 3 && ~strcmp(allVars(i).name, 'ThermalProParams')
                    ne = prod(allVars(i).size); if ne > maxE, maxE = ne; targetVar = allVars(i).name; end
                end
            end
            
            if isProject && any(strcmp({allVars.name}, 'RawData')), targetVar = 'RawData'; end
            
            if isempty(targetVar), errordlg('Variable Not Found'); return; end
            S.dataName = targetVar; S.N = whos(S.matObj, S.dataName).size(3);
            stepDen = max(1, S.N - 1);
            set(S.hUI.sld, 'Max', S.N, 'SliderStep', [min(1, 1/stepDen), min(1, 10/stepDen)], 'Value', 1);
            S.isLoaded = true;
            
            frame1 = double(S.matObj.(S.dataName)(:,:,1));
            minV = min(frame1(:), [], 'omitnan'); maxV = max(frame1(:), [], 'omitnan');
            if isempty(minV) || isnan(minV) || minV >= maxV, minV = 0; maxV = 1500; end
            set(S.hUI.efLow, 'String', num2str(minV)); set(S.hUI.efHigh, 'String', num2str(maxV));
            
            cla(axMain); S.hImg = []; set(axMain, 'CLim', [minV, maxV]);
            S.vapor.isPicking = false; 
            
            if isfield(S.hUI, 'btnPick') && isgraphics(S.hUI.btnPick)
                set(S.hUI.btnPick, 'String', '+ Anchor Point', 'BackgroundColor', [0.94 0.94 0.94]);
            end
            if isfield(S.hUI, 'btnAutoCatch') && isgraphics(S.hUI.btnAutoCatch)
                set(S.hUI.btnAutoCatch, 'Enable', 'off'); 
            end
            
            if isProject
                SavedParams = S.matObj.ThermalProParams;
                S.preproc = SavedParams.preproc; S.vapor = SavedParams.vapor;
                S.stab = SavedParams.stab; S.area = SavedParams.area;
                if isfield(SavedParams, 'calibMode'), S.calibMode = SavedParams.calibMode; end
                if isfield(SavedParams, 'heatCurve'), S.heatCurve = SavedParams.heatCurve; end
                if isfield(SavedParams, 'layers'), S.layers = SavedParams.layers; end
                if isfield(SavedParams, 'physics'), S.physics = SavedParams.physics; end
                if isfield(SavedParams, 'ndt'), S.ndt = SavedParams.ndt; end
                if isfield(SavedParams, 'dynamicAnchor'), S.dynamicAnchor = SavedParams.dynamicAnchor; end
                if isfield(SavedParams, 'pointDataCell'), S.pointDataCell = SavedParams.pointDataCell; end
                if isfield(SavedParams, 'allMarkerFrames'), S.allMarkerFrames = SavedParams.allMarkerFrames; end
                if isfield(SavedParams, 'analysisBaseCoords'), S.analysisBaseCoords = SavedParams.analysisBaseCoords; end
                if isfield(SavedParams, 'roiLines'), S.roiLines = SavedParams.roiLines; end
                if isfield(SavedParams, 'plotXMode'), S.plotXMode = SavedParams.plotXMode; end
                if isfield(SavedParams, 'fps') && isnumeric(SavedParams.fps) && isscalar(SavedParams.fps) && isfinite(SavedParams.fps) && SavedParams.fps > 0, S.fps = SavedParams.fps; end
                if isfield(SavedParams, 'uiPrefs'), S.uiPrefs = SavedParams.uiPrefs; end
                
                % [v8.78 Forward Compatibility]: Pre-allocate missing dimensional fields for old projects
                if ~isfield(S.area, 'hMPHistory'), S.area.hMPHistory = []; end
                if ~isfield(S.area, 'lMPHistory'), S.area.lMPHistory = []; end
                if ~isfield(S.area, 'hHTWHistory'), S.area.hHTWHistory = []; end
                if ~isfield(S.area, 'lHTWHistory'), S.area.lHTWHistory = []; end
                if ~isfield(S.area, 'morphKernel') || isnan(S.area.morphKernel) || S.area.morphKernel <= 0, S.area.morphKernel = 3; end
                if ~isfield(S.area, 'minRatio') || isnan(S.area.minRatio) || S.area.minRatio <= 0, S.area.minRatio = 20; end
                if ~isfield(S.area, 'proximityThresh') || isnan(S.area.proximityThresh) || S.area.proximityThresh <= 0, S.area.proximityThresh = 2; end
                if ~isfield(S.area, 'T_melt') || isnan(S.area.T_melt) || S.area.T_melt <= 0, S.area.T_melt = 1400; end
                if ~isfield(S.area, 'T_htw') || isnan(S.area.T_htw) || S.area.T_htw <= 0 || S.area.T_htw >= S.area.T_melt, S.area.T_htw = 980; end
                if ~isfield(S.ndt, 'gtTable'), S.ndt.gtTable = cell(0, 4); end
                if ~isfield(S.ndt, 'baselinePos'), S.ndt.baselinePos = []; end
                if ~isfield(S.ndt, 'layerLinesRaw'), S.ndt.layerLinesRaw = {}; end
                if ~isfield(S.ndt, 'layerLinesProc'), S.ndt.layerLinesProc = {}; end
                if ~isfield(S.ndt, 'selectedRow'), S.ndt.selectedRow = []; end
                if ~isfield(S.dynamicAnchor, 'isCalculated'), S.dynamicAnchor.isCalculated = false; end
                if ~isfield(S.dynamicAnchor, 'localShifts'), S.dynamicAnchor.localShifts = []; end
                if ~isfield(S.dynamicAnchor, 'refRect'), S.dynamicAnchor.refRect = []; end
                
                restoreUiState();
                set(S.hUI.chkVaporApply, 'Value', S.vapor.enabled);
                if S.stab.isCalculated, set(S.hUI.chkStabApply, 'Enable', 'on', 'Value', S.stab.enabled); end
                msgbox('Project Restored.', 'Project Loaded');
            else
                S.stab.isCalculated = false; S.stab.shifts = []; S.stab.enabled = false;
                S.stab.anchorOffset = [0, 0];
                set(S.hUI.chkStabApply,'Enable','off','Value',0); set(S.hUI.lblStabStatus,'String','Status: Not Calculated','ForegroundColor',[.6 .6 .6]);
                
                S.vapor.enabled = false; S.vapor.anchors = [];
                S.vapor.bgRect = []; S.vapor.bgCurve = []; S.vapor.bgRefVal = 0;
                
                S.calibMode = 'Single'; S.heatCurve = []; 
                S.layers = struct('id',{},'sampleF',{},'measPeak',{},'startF',{},'endF',{},'Q',{},'targetT',{},'offset',{});
                
                set(S.hUI.chkVaporApply,'Value',0); 
                S.area.mpHistory = []; S.area.htwHistory = [];
                S.area.hMPHistory = []; S.area.lMPHistory = [];
                S.area.hHTWHistory = []; S.area.lHTWHistory = [];
                S.area.forcedFrames = []; S.area.blacklistedFrames = []; 
                S.area.isCalibrated = false; S.area.pxPerMm = 1.0;
                
                ylabel(axArea, 'Area (pixels)');
                ylabel(axSizeH, 'Size H (pixels)');
                ylabel(axSizeL, 'Size L (pixels)');
                cla(axArea); cla(axSizeH); cla(axSizeL);
            end
            
            if ~isProject
                % Reset analysis/NDT data for raw imports only. Project loads restore the saved workspace.
                S.ndt.gtTable = cell(0, 4);
                S.ndt.layerLinesRaw = {};
                S.ndt.layerLinesProc = {};
                S.ndt.selectedRow = [];
                S.ndt.baselinePos = [];
                S.plotXMode = 'Time';
                S.dynamicAnchor = struct('isActive', false, 'refFrame', 1, 'refRect', [], 'localShifts', [], 'isCalculated', false);
                S.analysisBaseCoords = {};
                S.pointDataCell = {};
                S.allMarkerFrames = {};
                S.roiLines = [];
            end

            if isfield(S.hUI, 'tblGT') && isgraphics(S.hUI.tblGT)
                set(S.hUI.tblGT, 'Data', S.ndt.gtTable);
            end
            if isempty(S.ndt.baselinePos)
                set(S.hUI.lblBaselineStatus, 'String', 'Status: Not Drawn', 'ForegroundColor', 'r');
            else
                set(S.hUI.lblBaselineStatus, 'String', 'Status: Baseline Set', 'ForegroundColor', [0 .6 0]);
            end

            if strcmp(S.plotXMode, 'Time')
                set(S.hUI.btnAxisTemp, 'String', ' Time');
            else
                set(S.hUI.btnAxisTemp, 'String', ' Frame');
            end
            set(S.hUI.btnAxisArea, 'String', ' Toggle X-Axis');
            set(S.hUI.efFPS, 'String', num2str(S.fps));

            if isfield(S.hUI, 'chkLinkAnchor') && isgraphics(S.hUI.chkLinkAnchor)
                if S.dynamicAnchor.isCalculated
                    set(S.hUI.chkLinkAnchor, 'Enable', 'on', 'Value', 1);
                    set(S.hUI.lblAnchorStatus, 'String', 'Ready', 'ForegroundColor', [0 .6 0]);
                else
                    set(S.hUI.chkLinkAnchor, 'Value', 0, 'Enable', 'off');
                    set(S.hUI.lblAnchorStatus, 'String', 'Not Set', 'ForegroundColor', [.6 .6 .6]);
                end
            end
            S.showProgressLine = false;
            set(S.hUI.btnProgress, 'String', 'Cursor:OFF', 'BackgroundColor', [.94 .94 .94]);
            set(S.hUI.btnProgressArea, 'String', 'Cursor:OFF', 'BackgroundColor', [.94 .94 .94]);
            
            updateFrame(1);
            plotAreaCurves();
            refreshPointPlot();
            restoreAnalysisGraphics();
            
        catch ME
            errordlg(ME.message);
        end
    end
    
    function onExportMP4(~,~)
        if ~S.isLoaded, errordlg('No data loaded.'); return; end
        if strcmp(S.playTimer.Running, 'on'), onPlayToggle(S.hUI.btnPlay, []); end 
        [file, path] = uiputfile('ThermalPresentation.mp4', 'Save Video As MP4');
        if isequal(file, 0), return; end
        
        hWait = waitbar(0, 'Capturing frames and encoding MP4... (Do not occlude main view)', 'CreateCancelBtn', 'setappdata(gcbf,''canceling'',1)');
        setappdata(hWait, 'canceling', 0);
        try
            vFile = fullfile(path, file); v = VideoWriter(vFile, 'MPEG-4'); v.Quality = 100; 
            reqFPS = syncFPS(true);
            v.FrameRate = reqFPS; open(v); axes(axMain); 
            isCanceled = false;
            for i = 1:S.N
                if ~isgraphics(hWait) || getappdata(hWait, 'canceling'), isCanceled = true; break; end
                updateFrame(i); figure(fig); drawnow; 
                frame = getframe(axMain); cdata = frame.cdata;
                targetHeight = 1080; scale = max(2.0, targetHeight / size(cdata, 1));
                if scale > 1, cdata = imresize(cdata, scale, 'bicubic'); end
                if mod(size(cdata, 1), 2) ~= 0, cdata = cdata(1:end-1, :, :); end
                if mod(size(cdata, 2), 2) ~= 0, cdata = cdata(:, 1:end-1, :); end
                writeVideo(v, cdata);
                if mod(i, 2) == 0 && isgraphics(hWait), waitbar(i/S.N, hWait, sprintf('Rendering HD video... Frame %d / %d', i, S.N)); end
            end
            close(v); if isgraphics(hWait), delete(hWait); end
            if isCanceled, msgbox('Video export cancelled.', 'Cancelled'); else, msgbox(sprintf('MP4 video exported successfully to:\n%s', vFile), 'Export Success'); end
        catch ME
            if exist('v', 'var'), try close(v); catch; end; end
            if exist('hWait', 'var') && isgraphics(hWait), delete(hWait); end
            errordlg(['MP4 export failed: ' ME.message]);
        end
    end
    
    function restoreUiState()
        val = 1; if strcmp(S.calibMode, 'Multi'), val = 2; end
        set(S.hUI.popCalibMode, 'Value', val);
        onModeChange();
        updateVaporTable();
        if ~isempty(S.vapor.bgRect)
            set(S.hUI.lblBgStatus, 'String', 'BG Correction: Ready', 'ForegroundColor', [0 .6 .0]);
        end
        if S.stab.isCalculated, set(S.hUI.lblStabStatus, 'String', 'Calculated.', 'ForegroundColor', [0 .6 .0]); end
        denoiseIdx = 1;
        if strcmp(S.preproc.denoiseType, 'Median'), denoiseIdx = 2;
        elseif strcmp(S.preproc.denoiseType, 'Gaussian'), denoiseIdx = 3;
        elseif strcmp(S.preproc.denoiseType, 'Morph'), denoiseIdx = 4; end
        set(S.hUI.popDenoise, 'Value', denoiseIdx);
        set(S.hUI.editDenoiseParam, 'String', num2str(S.preproc.denoiseParam));
        set(S.hUI.efRefTemp, 'String', num2str(S.vapor.refTemp));
        set(S.hUI.efFPS, 'String', num2str(S.fps));
        set(S.hUI.efAreaMP, 'String', num2str(S.area.T_melt));
        set(S.hUI.efAreaHAZ, 'String', num2str(S.area.T_htw));
        set(S.hUI.efDist, 'String', num2str(S.area.proximityThresh));
        set(S.hUI.efRatio, 'String', num2str(S.area.minRatio));
        set(S.hUI.efMorph, 'String', num2str(S.area.morphKernel));
        set(S.hUI.chkAreaVis, 'Value', S.area.enabled);
        onVaporConfigChange(); 
    end
    function onExportProject(~,~)
        if ~S.isLoaded, errordlg('No data loaded.'); return; end
        [f, p] = uiputfile('ThermalProject.mat', 'Save Project');
        if isequal(f,0), return; end
        hWait = waitbar(0, 'Saving Project...');
        try
            syncFPS(false);
            tempF = double(S.matObj.(S.dataName)(:,:,1)); [h, w] = size(tempF);
            outFile = fullfile(p, f);
            ThermalProParams = struct('preproc',S.preproc, 'vapor',S.vapor, 'stab',S.stab, 'area',S.area, ...
                'calibMode',S.calibMode, 'heatCurve',S.heatCurve, 'layers',S.layers, 'physics',S.physics, ...
                'ndt',S.ndt, 'dynamicAnchor',S.dynamicAnchor, 'pointDataCell',{S.pointDataCell}, ...
                'allMarkerFrames',{S.allMarkerFrames}, 'analysisBaseCoords',{S.analysisBaseCoords}, ...
                'roiLines',S.roiLines, 'plotXMode',S.plotXMode, 'fps',S.fps, 'uiPrefs',S.uiPrefs);
            mOut = matfile(outFile, 'Writable', true);
            mOut.ThermalProParams = ThermalProParams;
            mOut.RawData(h, w, S.N) = 0;
            for i = 1:S.N
                mOut.RawData(:,:,i) = double(S.matObj.(S.dataName)(:,:,i));
                if mod(i, 20) == 0 && isvalid(hWait), waitbar(i/S.N, hWait); end
            end
            if isvalid(hWait), delete(hWait); end; msgbox('Project Saved.', 'Success');
        catch ME, if isvalid(hWait), delete(hWait); end; errordlg(['Save Failed: ' ME.message]); end
    end
    function onExportBaked(~,~)
        if ~S.isLoaded, errordlg('No data loaded.'); return; end
        [f, p] = uiputfile('ProcessedData.mat', 'Export Processed Data');
        if isequal(f,0), return; end
        hWait = waitbar(0, 'Baking Video...');
        try
            tempF = getProcessedFrame(1); [h, w] = size(tempF);
            outFile = fullfile(p, f);
            mOut = matfile(outFile, 'Writable', true);
            mOut.ProcessedData(h, w, S.N) = 0;
            for i = 1:S.N
                mOut.ProcessedData(:,:,i) = getProcessedFrame(i);
                if mod(i, 20) == 0 && isvalid(hWait), waitbar(i/S.N, hWait); end
            end
            if isvalid(hWait), delete(hWait); end; msgbox('Processed Data Exported.', 'Success');
        catch ME, if isvalid(hWait), delete(hWait); end; errordlg(['Export Failed: ' ME.message]); end
    end
    
    %% --- DUAL MODE UI SWITCHER ---
    function onModeChange(~,~)
        val = get(S.hUI.popCalibMode, 'Value');
        if val == 1
            S.calibMode = 'Single';
            set(S.hUI.panelSingle, 'Visible', 'on');
            set(S.hUI.panelMulti, 'Visible', 'off');
        else
            S.calibMode = 'Multi';
            set(S.hUI.panelSingle, 'Visible', 'off');
            set(S.hUI.panelMulti, 'Visible', 'on');
        end
        updateMultiStatus();
        updateFrame(S.frameIdx);
    end
    function updateMultiStatus()
        nL = length(S.layers);
        hasQ = ~isempty(S.heatCurve);
        qStr = 'No'; if hasQ, qStr = sprintf('Yes (%d pts)', length(S.heatCurve)); end
        set(S.hUI.lblMultiStatus, 'String', sprintf('Layers: %d | Heat Curve: %s', nL, qStr));
    end
    function onHeatCurveMenu(~,~)
        answer = inputdlg({'Paste Heat Input (Q) Vector (e.g. from Excel):'}, 'Import Heat Data', [10 50], {''});
        if isempty(answer), return; end
        str = answer{1}; qVec = parseNumericVector(str); 
        if isempty(qVec) || any(~isfinite(qVec)), errordlg('Invalid numeric data.'); return; end
        S.heatCurve = qVec;
        hF = figure('Name', 'Heat Input Curve Verification', 'MenuBar','none','ToolBar','none','NumberTitle','off');
        plot(qVec, 'o-', 'LineWidth', 1.5); grid on; xlabel('Layer Number'); ylabel('Heat Input (Q)'); title('Imported Heat Profile');
        updateMultiStatus(); msgbox(sprintf('Successfully imported %d data points.', length(qVec)));
    end
    
    %% --- INTERACTIVE LAYER MANAGER ---
    function onLayerManager(~,~)
        if ~S.isLoaded, errordlg('Load Data First'); return; end
        hFigL = figure('Name', ' Layer & Temperature Manager', 'NumberTitle', 'off', ...
            'MenuBar', 'none', 'ToolBar', 'none', 'Position', [200 200 900 550], 'Color', [.94 .94 .94]);
        pCal = uipanel('Parent',hFigL, 'Title', 'Physics Baseline (Layer 1)', 'Units','normalized','Position',[.02 .85 .96 .13]);
        uicontrol('Parent',pCal,'Style','text','String','Q_ref (Layer 1):', 'Units','normalized','Position',[.02 .3 .15 .4]);
        efRefQ = uicontrol('Parent',pCal,'Style','edit','String',num2str(S.physics.refQ), 'Units','normalized','Position',[.18 .3 .1 .5], 'Callback',@updPhy);
        uicontrol('Parent',pCal,'Style','text','String','T_ref (Layer 1):', 'Units','normalized','Position',[.3 .3 .15 .4]);
        efRefT = uicontrol('Parent',pCal,'Style','edit','String',num2str(S.physics.refT), 'Units','normalized','Position',[.46 .3 .1 .5], 'Callback',@updPhy);
        uicontrol('Parent',pCal,'Style','pushbutton','String','Apply & Recalculate', 'Units','normalized','Position',[.7 .2 .25 .6], ...
            'Callback', @recalcAll, 'BackgroundColor',[.8 1 .8]);
        hTable = uitable('Parent', hFigL, 'Units', 'normalized', 'Position', [.02 .30 .96 .53], ...
            'ColumnName', {'Layer #', 'Sample Frame', 'Meas Peak', 'Start Frame', 'End Frame', 'Heat Q', 'Target T', 'Offset'}, ...
            'ColumnEditable', [false false false true true true false false], ...
            'ColumnWidth', {50, 80, 80, 80, 80, 60, 60, 60}, ...
            'Data', getTableData(), 'CellEditCallback', @onCellEdit);
        uicontrol('Parent',hFigL,'Style','pushbutton','String',' Capture Current Frame as New Layer', ...
            'Units','normalized','Position',[.05 .15 .40 .10], 'FontSize', 11, 'FontWeight','bold', ...
            'BackgroundColor', [1 .9 .8], 'Callback', @captureFrame);
        uicontrol('Parent',hFigL,'Style','text','String','(Auto-detects Peak Temp & Fetches Q from Curve)', ...
            'Units','normalized','Position',[.05 .10 .40 .04], 'ForegroundColor',[.4 .4 .4]);
        uicontrol('Parent',hFigL,'Style','pushbutton','String','Update Table View', ...
            'Units','normalized','Position',[.55 .15 .20 .10], 'Callback', @(~,~) set(hTable, 'Data', getTableData()));
        uicontrol('Parent',hFigL,'Style','pushbutton','String','Delete Last', ...
            'Units','normalized','Position',[.80 .15 .15 .10], 'ForegroundColor','r', 'Callback', @delLast);
        function updPhy(~,~)
            S.physics.refQ = str2double(efRefQ.String); S.physics.refT = str2double(efRefT.String);
        end
        function d = getTableData()
            d = [];
            for k=1:length(S.layers), d = [d; {S.layers(k).id, S.layers(k).sampleF, S.layers(k).measPeak, S.layers(k).startF, S.layers(k).endF, S.layers(k).Q, S.layers(k).targetT, S.layers(k).offset}]; end
        end
        function captureFrame(~,~)
            f = S.frameIdx; raw = double(S.matObj.(S.dataName)(:,:,f));
            if S.vapor.enabled && ~isempty(S.vapor.bgCurve), drift = S.vapor.bgCurve(f) - S.vapor.bgRefVal; raw = raw - drift; end
            if S.preproc.denoiseParam > 0, se = strel('disk', S.preproc.denoiseParam); raw = imopen(raw, se); end
            measP = max(raw(:)); id = length(S.layers) + 1;
            Q_val = S.physics.refQ; 
            if ~isempty(S.heatCurve), if id <= length(S.heatCurve), Q_val = S.heatCurve(id); else, Q_val = S.heatCurve(end); end; end
            ratio = Q_val / S.physics.refQ; tgt = S.physics.refT * (ratio^0.25); offs = tgt - measP;
            newL = struct('id', id, 'sampleF', f, 'measPeak', measP, 'startF', 0, 'endF', 0, 'Q', Q_val, 'targetT', tgt, 'offset', offs);
            S.layers = [S.layers; newL]; set(hTable, 'Data', getTableData()); updateMultiStatus();
            msgbox(sprintf('Layer %d Captured!\nMeas Peak: %.1f\nTarget: %.1f\nOffset: %.1f\n\nPlease fill Start/End Frames.', id, measP, tgt, offs));
        end
        function onCellEdit(~, ev)
            r = ev.Indices(1); c = ev.Indices(2); val = ev.NewData;
            if c==4, S.layers(r).startF = val; elseif c==5, S.layers(r).endF = val; elseif c==6, S.layers(r).Q = val; recalcRow(r); end
        end
        function recalcRow(r)
             L = S.layers(r); ratio = L.Q / S.physics.refQ; L.targetT = S.physics.refT * (ratio^0.25); L.offset = L.targetT - L.measPeak; S.layers(r) = L; set(hTable, 'Data', getTableData());
        end
        function recalcAll(~,~)
            for k=1:length(S.layers), recalcRow(k); end
            updateVisuals();
        end
        function delLast(~,~)
            if ~isempty(S.layers), S.layers(end) = []; set(hTable, 'Data', getTableData()); updateMultiStatus(); end
        end
    end
    
    %% --- POPUP ANCHOR TABLE (MODE A) ---
    function onShowAnchorTable(~,~)
        if isfield(S.hUI, 'hAnchorFig') && isgraphics(S.hUI.hAnchorFig), figure(S.hUI.hAnchorFig); return; end
        S.hUI.hAnchorFig = figure('Name', 'Vapor Anchors Data Grid', 'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', 'Position', [150 150 500 400], 'Color', [.94 .94 .94]);
        hc = uicontextmenu(S.hUI.hAnchorFig); uimenu(hc, 'Label', 'Delete Selected Row(s)', 'Callback', @execDelete);
        S.hUI.tblVapor = uitable('Parent', S.hUI.hAnchorFig, 'Units', 'normalized', 'Position', [.02 .1 .96 .88], 'ColumnName', {'Frame', 'Meas', 'Offset'}, 'Data', [], 'UIContextMenu', hc, 'CellSelectionCallback', @trackSel);
        uicontrol('Parent', S.hUI.hAnchorFig, 'Style', 'text', 'String', 'Right-click to delete rows.', 'Units', 'normalized', 'Position', [.02 .02 .96 .06], 'BackgroundColor', [.94 .94 .94]);
        updateVaporTable();
        function trackSel(~, ev), if ~isempty(ev.Indices), set(S.hUI.hAnchorFig, 'UserData', unique(ev.Indices(:,1))); end; end
        function execDelete(~,~), rows = get(S.hUI.hAnchorFig, 'UserData'); if isempty(rows), return; end; S.vapor.anchors(rows, :) = []; set(S.hUI.hAnchorFig, 'UserData', []); updateVaporTable(); updateVisuals(); end
    end
    
    function [refT, srcLabel] = getRefTempForFrame(fIdx)
        refT = S.vapor.refTemp; srcLabel = 'Global';
        if strcmp(S.calibMode, 'Multi') && ~isempty(S.layers) && isstruct(S.layers)
            for k = 1:length(S.layers)
                if isfield(S.layers(k), 'startF') && isfield(S.layers(k), 'endF') && fIdx >= S.layers(k).startF && fIdx <= S.layers(k).endF
                    refT = S.layers(k).targetT; srcLabel = sprintf('Layer %d', S.layers(k).id); return;
                end
            end
        elseif ~isempty(S.vapor.refSchedule)
            mask = (fIdx >= S.vapor.refSchedule(:,1)) & (fIdx <= S.vapor.refSchedule(:,2)); idx = find(mask, 1);
            if ~isempty(idx), refT = S.vapor.refSchedule(idx, 3); srcLabel = sprintf('Segment %d', idx); end
        end
    end
    
    % Core processing function
    function img = getProcessedFrame(idx)
        raw = double(S.matObj.(S.dataName)(:,:,idx));
        if strcmp(S.preproc.denoiseType, 'Median'), raw = medfilt2(raw, [S.preproc.denoiseParam S.preproc.denoiseParam]); elseif strcmp(S.preproc.denoiseType, 'Gaussian'), raw = imgaussfilt(raw, S.preproc.denoiseParam); elseif strcmp(S.preproc.denoiseType, 'Morph'), se = strel('disk', S.preproc.denoiseParam); raw = imopen(raw, se); end
        if S.vapor.enabled && ~isempty(S.vapor.bgCurve) && idx <= length(S.vapor.bgCurve), drift = S.vapor.bgCurve(idx) - S.vapor.bgRefVal; raw = raw - drift; raw(raw < 0) = 0; end
        isStabActive = get(S.hUI.chkStabApply, 'Value') && S.stab.enabled && S.stab.isCalculated;
        if isStabActive && idx <= size(S.stab.shifts,1), shift = S.stab.shifts(idx, :); totalShift = -shift + S.stab.anchorOffset; raw = imtranslate(raw, totalShift, 'FillValues', 0); end
        if strcmp(S.calibMode, 'Multi')
            if ~isempty(S.layers) && isstruct(S.layers) && isfield(S.layers, 'startF')
                layerIdx = find([S.layers.startF] <= idx & [S.layers.endF] >= idx, 1);
                if ~isempty(layerIdx), raw = raw + S.layers(layerIdx).offset; end
            end
        else
            maskWeights = zeros(size(raw));
            if S.vapor.enabled
                physFloor = 25;
                if ~isempty(S.vapor.bgCurve) && idx <= length(S.vapor.bgCurve)
                    physFloor = S.vapor.bgCurve(idx);
                end
                physCeil = S.vapor.refTemp;
                if physCeil <= physFloor, physCeil = physFloor + 100; end
                maskWeights = (raw - physFloor) / (physCeil - physFloor);
                maskWeights = max(0, min(1, maskWeights));
                currentGamma = 1.0;
                if ~isempty(S.vapor.gammaSchedule)
                    for k = 1:length(S.vapor.gammaSchedule)
                        item = S.vapor.gammaSchedule(k);
                        if idx >= item.fS && idx <= item.fE
                            t = (idx - item.fS) / max(1, (item.fE - item.fS));
                            if strcmp(item.mode, 'Lin'), currentGamma = item.gS + t * (item.gE - item.gS); elseif strcmp(item.mode, 'Exp'), gS = max(0.1, item.gS); gE = max(0.1, item.gE); currentGamma = gS * (gE / gS)^t; end
                            break;
                        end
                    end
                end
                maskWeights = maskWeights .^ currentGamma;
            end
            if S.vapor.enabled && ~isempty(S.vapor.anchors)
                [uniqueFrames, uIdx] = unique(S.vapor.anchors(:,1)); uniqueVals = S.vapor.anchors(uIdx, 2);
                if ~isempty(uniqueFrames)
                    if length(uniqueFrames) == 1, currentOffset = S.vapor.refTemp - uniqueVals(1); else, calculatedOffsets = S.vapor.refTemp - uniqueVals; currentOffset = interp1(uniqueFrames, calculatedOffsets, idx, 'linear', 'extrap'); end
                    raw = raw + (currentOffset .* maskWeights);
                end
            end
        end
        if ~isempty(S.preproc.claheSchedule)
            rowIdx = find(idx >= S.preproc.claheSchedule(:,1) & idx <= S.preproc.claheSchedule(:,2), 1);
            if ~isempty(rowIdx)
                clipVal = S.preproc.claheSchedule(rowIdx, 3); minVal = min(raw(:)); maxVal = max(raw(:));
                if maxVal > minVal, normImg = (raw - minVal) / (maxVal - minVal); normImg = adapthisteq(normImg, 'ClipLimit', clipVal); raw = normImg * (maxVal - minVal) + minVal; end
            end
        end
        img = raw;
    end
    
    % [NEW v8.78] Helper to extract morphology sizes
    function [w, h, cx, cy] = getMorphDims(bwMask)
        w = 0; h = 0; cx = 0; cy = 0;
        props = regionprops(bwMask, 'BoundingBox', 'Centroid', 'Area');
        if ~isempty(props)
            [~, bestIdx] = max([props.Area]);
            bb = props(bestIdx).BoundingBox; % [x, y, width, height]
            w = bb(3);
            h = bb(4);
            cx = props(bestIdx).Centroid(1);
            cy = props(bestIdx).Centroid(2);
        end
    end
    
    % Global Frame Updater (respects Global View Mode)
    function updateFrame(idx)
        if ~S.isLoaded, return; end; 
        S.frameIdx = idx; 
        
        if strcmp(S.viewMode, 'RAW')
            imgData = double(S.matObj.(S.dataName)(:,:,idx));
        else
            imgData = getProcessedFrame(idx);
        end
        
        if isempty(S.hImg)||~isgraphics(S.hImg)
            S.hImg = imagesc(axMain, imgData); colormap(axMain, hot); colorbar(axMain); axis(axMain,'image');
        else
            set(S.hImg, 'CData', imgData); 
        end
        
        vL = str2double(get(S.hUI.efLow,'String')); vH = str2double(get(S.hUI.efHigh,'String'));
        if ~isnan(vL) && ~isnan(vH) && vL < vH, set(axMain, 'CLim', [vL, vH]); end
        
        delete(findall(axMain, 'Tag', 'TempLayerLine'));
        delete(findall(axMain, 'Tag', 'AreaContour')); 
        delete(findall(axMain, 'Tag', 'LocalAnchorVisual'));
        delete(findall(axMain, 'Tag', 'BaselineLine'));
        
        hold(axMain, 'on');
        if isfield(S.ndt, 'baselinePos') && ~isempty(S.ndt.baselinePos)
            plot(axMain, S.ndt.baselinePos(:,1), S.ndt.baselinePos(:,2), 'm-', 'LineWidth', 2, 'Tag', 'BaselineLine', 'HitTest', 'off');
        end
        if strcmp(S.viewMode, 'RAW')
            ndtLines = S.ndt.layerLinesRaw;
        else
            ndtLines = S.ndt.layerLinesProc;
        end
        for lineIdx = 1:numel(ndtLines)
            if ~isempty(ndtLines{lineIdx})
                plot(axMain, ndtLines{lineIdx}(:,1), ndtLines{lineIdx}(:,2), 'y--', 'LineWidth', 1.5, 'Tag', 'TempLayerLine', 'HitTest', 'off');
            end
        end
        hold(axMain, 'off');
        
        if ~isempty(S.hAutoCircle) && isgraphics(S.hAutoCircle), delete(S.hAutoCircle); S.hAutoCircle=[]; end
        
        if S.vapor.enabled && ~isempty(S.vapor.bgCurve) && idx <= length(S.vapor.bgCurve)
            drift = S.vapor.bgCurve(idx) - S.vapor.bgRefVal; set(S.hUI.lblBgStatus, 'String', sprintf('BG Comp: %.1f (De-Hazing ON)', -drift), 'ForegroundColor', [0 .6 0]);
        else
            set(S.hUI.lblBgStatus, 'String', 'BG Correction: Off', 'ForegroundColor', [.5 .5 .5]);
        end
        
        [currRef, refSrc] = getRefTempForFrame(idx); set(S.hUI.lblActiveRef, 'String', sprintf('Active: %.0f (%s)', currRef, refSrc));
        
        if S.area.enabled
            hold(axMain, 'on'); bwMP = imgData >= S.area.T_melt; bwHAZ = (imgData >= S.area.T_htw) & (imgData < S.area.T_melt); se = strel('disk', S.area.morphKernel); bwHAZ = imopen(bwHAZ, se); CC_HTW = bwconncomp(bwHAZ); 
            if CC_HTW.NumObjects > 0, numPixels = cellfun(@numel, CC_HTW.PixelIdxList); [~, maxIdx] = max(numPixels); bwHAZ = false(size(bwHAZ)); bwHAZ(CC_HTW.PixelIdxList{maxIdx}) = true; end
            isForced = ismember(idx, S.area.forcedFrames); isBlacklisted = ismember(idx, S.area.blacklistedFrames); isValidFrame = false; diagStatus = 'WAIT'; diagDist = NaN; diagRatio = NaN; areaMP = 0; areaHAZ = 0;
            if isBlacklisted
                isValidFrame = false; diagStatus = 'BLACKLIST'; areaMP = sum(bwMP(:)); areaHAZ = sum(bwHAZ(:));
                if areaMP>0 && areaHAZ>0, D_MP = bwdist(bwMP); diagDist = min(D_MP(bwHAZ)); diagRatio = areaHAZ/areaMP; end
            elseif isForced
                isValidFrame = true; diagStatus = 'FORCED'; areaMP = sum(bwMP(:)); areaHAZ = sum(bwHAZ(:));
                if areaMP>0 && areaHAZ>0, D_MP = bwdist(bwMP); diagDist = min(D_MP(bwHAZ)); diagRatio = areaHAZ/areaMP; end
            else
                CC_MP = bwconncomp(bwMP);
                if CC_MP.NumObjects > 0
                    if any(bwHAZ(:)) && CC_MP.NumObjects > 1
                        D_HAZ = bwdist(bwHAZ); minDists = zeros(1, CC_MP.NumObjects); for k = 1:CC_MP.NumObjects, minDists(k) = min(D_HAZ(CC_MP.PixelIdxList{k})); end
                        [~, bestIdx] = min(minDists); bwMP = false(size(bwMP)); bwMP(CC_MP.PixelIdxList{bestIdx}) = true;
                    end
                    areaMP = sum(bwMP(:)); areaHAZ = sum(bwHAZ(:));
                    if areaHAZ > 0, D_MP = bwdist(bwMP); diagDist = min(D_MP(bwHAZ)); diagRatio = areaHAZ / areaMP; ratioOk = areaMP >= (areaHAZ / S.area.minRatio); distOk = diagDist <= S.area.proximityThresh; if distOk && ratioOk, isValidFrame = true; diagStatus = 'VALID'; else, diagStatus = 'REJECTED'; end
                    else, isValidFrame = true; diagStatus = 'VALID (No HTW)'; end
                else, diagStatus = 'REJECTED (No MP)'; end
            end
            
            unitStr = 'px^2'; scaleFactor = 1; if S.area.isCalibrated, unitStr = 'mm^2'; scaleFactor = (1/S.area.pxPerMm)^2; end
            strDist = '--'; if ~isnan(diagDist), if diagDist > S.area.proximityThresh, strDist = sprintf('%.1fpx [FAIL > %.1f]', diagDist, S.area.proximityThresh); else, strDist = sprintf('%.1fpx', diagDist); end; end
            strRatio = '--'; if ~isnan(diagRatio), if areaMP < (areaHAZ / S.area.minRatio), strRatio = sprintf('1:%.0f [FAIL < 1:%.0f]', diagRatio, S.area.minRatio); else, strRatio = sprintf('1:%.0f', diagRatio); end; end
            monitorStr = sprintf('[%s] Dist: %s | Ratio: %s | MP: %.1f%s | HTW: %.1f%s', diagStatus, strDist, strRatio, areaMP*scaleFactor, unitStr, areaHAZ*scaleFactor, unitStr);
            bgCol = [.9 .9 .9]; if strcmp(diagStatus, 'VALID'), bgCol = [.8 1 .8]; elseif strcmp(diagStatus, 'FORCED'), bgCol = [.8 .9 1]; elseif strcmp(diagStatus, 'BLACKLIST'), bgCol = [.4 .4 .4]; elseif contains(diagStatus, 'REJECTED'), bgCol = [1 .8 .8]; end
            set(S.hUI.lblAreaDiag, 'String', monitorStr, 'BackgroundColor', bgCol);
            debugMode = get(S.hUI.chkAreaDebug, 'Value');
            
            try
                % --- Shape Visuals overlay (Contour + Dimensions) ---
                if isValidFrame || (debugMode && (contains(diagStatus, 'REJECTED') || strcmp(diagStatus, 'BLACKLIST')))
                    ls_mp = '-'; ls_haz = '-'; c_mp = 'r'; c_haz = [0.6 0 0.8]; lw = 1.5;
                    if ~isValidFrame, ls_mp = '--'; ls_haz = '--'; c_mp = [0.9 0.8 0]; c_haz = [0.9 0.8 0]; lw = 1; end
                    
                    % 1. Melt Pool Tracking
                    [B_mp, ~] = bwboundaries(bwMP, 'noholes'); 
                    for k = 1:length(B_mp)
                        boundary = B_mp{k}; plot(axMain, boundary(:,2), boundary(:,1), 'Color', c_mp, 'LineStyle', ls_mp, 'LineWidth', lw, 'Tag', 'AreaContour'); 
                    end
                    % Size H/L Crosshair
                    [lMP, hMP, cxMP, cyMP] = getMorphDims(bwMP);
                    if lMP > 0 && hMP > 0
                        plot(axMain, [cxMP - lMP/2, cxMP + lMP/2], [cyMP, cyMP], 'Color', c_mp, 'LineStyle', ls_mp, 'LineWidth', 1, 'Tag', 'AreaContour');
                        plot(axMain, [cxMP, cxMP], [cyMP - hMP/2, cyMP + hMP/2], 'Color', c_mp, 'LineStyle', ls_mp, 'LineWidth', 1, 'Tag', 'AreaContour');
                        uLine = 'px'; scL = 1; if S.area.isCalibrated, uLine = 'mm'; scL = 1/S.area.pxPerMm; end
                        text(axMain, cxMP+lMP/2, cyMP, sprintf(' l:%.1f', lMP*scL), 'Color', c_mp, 'FontSize', 8, 'Tag', 'AreaContour', 'Clipping', 'on');
                        text(axMain, cxMP, cyMP-hMP/2, sprintf(' h:%.1f', hMP*scL), 'Color', c_mp, 'FontSize', 8, 'Tag', 'AreaContour', 'Clipping', 'on', 'VerticalAlignment', 'bottom');
                    end

                    % 2. HTW Tracking
                    [B_haz, ~] = bwboundaries(bwHAZ, 'noholes'); 
                    for k = 1:length(B_haz)
                        boundary = B_haz{k}; plot(axMain, boundary(:,2), boundary(:,1), 'Color', c_haz, 'LineStyle', ls_haz, 'LineWidth', lw, 'Tag', 'AreaContour'); 
                    end
                    % Size H/L Crosshair for HTW
                    [lHAZ, hHAZ, cxHAZ, cyHAZ] = getMorphDims(bwHAZ);
                    if lHAZ > 0 && hHAZ > 0
                        plot(axMain, [cxHAZ - lHAZ/2, cxHAZ + lHAZ/2], [cyHAZ, cyHAZ], 'Color', c_haz, 'LineStyle', ls_haz, 'LineWidth', 1, 'Tag', 'AreaContour');
                        plot(axMain, [cxHAZ, cxHAZ], [cyHAZ - hHAZ/2, cyHAZ + hHAZ/2], 'Color', c_haz, 'LineStyle', ls_haz, 'LineWidth', 1, 'Tag', 'AreaContour');
                    end
                end
            catch ME
                warning('ThermalPro:OverlayRender', 'Area overlay render failed: %s', ME.message);
            end
            hold(axMain, 'off');
        end
        if ~isempty(S.roiLines)
            [~,~,c] = improfile(imgData, S.roiLines(:,1), S.roiLines(:,2)); nx = length(c);
            if abs(S.roiLines(1,1)-S.roiLines(2,1)) > abs(S.roiLines(1,2)-S.roiLines(2,2)), px = linspace(S.roiLines(1,1), S.roiLines(2,1), nx); lab = 'X (pix)';
            else, px = linspace(S.roiLines(1,2), S.roiLines(2,2), nx); lab = 'Y Pixel'; end
            plot(axLine, px, c, 'Color', [.2 .6 .9], 'LineWidth', 1.5); grid(axLine,'on'); xlabel(axLine, lab); ylabel(axLine, 'T (°C)');
        end
        
        % Dynamic Anchor Visual Updates
        useAnchor = get(S.hUI.chkLinkAnchor, 'Value') && S.dynamicAnchor.isCalculated;
        shiftX = 0; shiftY = 0;
        if useAnchor && idx <= size(S.dynamicAnchor.localShifts, 1)
            shiftX = S.dynamicAnchor.localShifts(idx, 1);
            shiftY = S.dynamicAnchor.localShifts(idx, 2);
            
            anchorBox = S.dynamicAnchor.refRect;
            anchorBox(1) = anchorBox(1) + shiftX;
            anchorBox(2) = anchorBox(2) + shiftY;
            rectangle(axMain, 'Position', anchorBox, 'EdgeColor', 'y', 'LineStyle', '--', 'LineWidth', 1.5, 'HitTest', 'off', 'Tag', 'LocalAnchorVisual');
        end
        
        for k = 1:length(S.hPointMarkers)
            if isgraphics(S.hPointMarkers(k)) && k <= length(S.analysisBaseCoords)
                base = S.analysisBaseCoords{k}.coords;
                if strcmp(S.analysisBaseCoords{k}.type, 'Point')
                    set(S.hPointMarkers(k), 'XData', base(1) + shiftX, 'YData', base(2) + shiftY);
                    if k <= length(S.hPointTexts) && isgraphics(S.hPointTexts(k))
                        set(S.hPointTexts(k), 'Position', [base(1)+5+shiftX, base(2)-5+shiftY, 0]);
                    end
                elseif strcmp(S.analysisBaseCoords{k}.type, 'Rect')
                    if k <= length(S.hRectOutlines) && isgraphics(S.hRectOutlines(k))
                        set(S.hRectOutlines(k), 'Position', [base(1)+shiftX, base(2)+shiftY, base(3), base(4)]);
                    end
                    if k <= length(S.hPointTexts) && isgraphics(S.hPointTexts(k))
                        set(S.hPointTexts(k), 'Position', [base(1)+shiftX, base(2)-10+shiftY, 0]);
                    end
                end
            end
        end
        
        % [NEW v8.78] Multi-Axis Progress Cursor Update
        if S.showProgressLine
            currentX = idx;
            if strcmp(S.plotXMode, 'Time'), currentX = currentX / S.fps; end
            
            % Temp Analysis Point Axis
            if isempty(S.hProgressLine) || ~isgraphics(S.hProgressLine)
                hold(axPoint, 'on');
                S.hProgressLine = xline(axPoint, 1, 'k-', 'LineWidth', 1.2, 'HitTest', 'off');
                S.hProgressLine.Annotation.LegendInformation.IconDisplayStyle = 'off';
            end
            set(S.hProgressLine, 'Value', currentX, 'Visible', 'on');
            
            % Area Analysis Sub-Axes
            axesList = {axArea, axSizeH, axSizeL};
            linesList = {'hProgressLineArea', 'hProgressLineH', 'hProgressLineL'};
            for aIdx = 1:3
                ca = axesList{aIdx}; lName = linesList{aIdx};
                if isempty(S.(lName)) || ~isgraphics(S.(lName))
                    hold(ca, 'on'); S.(lName) = xline(ca, 1, 'k-', 'LineWidth', 1.2, 'HitTest', 'off');
                    S.(lName).Annotation.LegendInformation.IconDisplayStyle = 'off';
                end
                set(S.(lName), 'Value', currentX, 'Visible', 'on');
            end
        else
            if ~isempty(S.hProgressLine) && isgraphics(S.hProgressLine), set(S.hProgressLine, 'Visible', 'off'); end
            if ~isempty(S.hProgressLineArea) && isgraphics(S.hProgressLineArea), set(S.hProgressLineArea, 'Visible', 'off'); end
            if ~isempty(S.hProgressLineH) && isgraphics(S.hProgressLineH), set(S.hProgressLineH, 'Visible', 'off'); end
            if ~isempty(S.hProgressLineL) && isgraphics(S.hProgressLineL), set(S.hProgressLineL, 'Visible', 'off'); end
        end
        
        statusStr = ''; if get(S.hUI.chkStabApply, 'Value') && S.stab.enabled, statusStr = [statusStr '[Stab] ']; end
        if S.vapor.enabled, statusStr = [statusStr '[Vapor] ']; end
        title(axMain, sprintf('%sVariable: %s | %s Mode | Frame: %d / %d', statusStr, S.dataName, S.viewMode, idx, S.N));
    end
    
    function onSetLocalAnchor(~,~)
        if ~S.isLoaded, errordlg('Please load data first'); return; end
        msgbox('Draw a rectangle around a target with sharp edges. System uses “melt-pool masking” gradient tracking immunizes against thermal blooming near hot melt pools.', 'Dynamic Anchor (Melt-Pool Immune)');
        h = imrect(axMain); pos = wait(h);
        if isempty(pos), if isgraphics(h), delete(h); end; return; end

        S.dynamicAnchor.refRect = round(pos);
        S.dynamicAnchor.refFrame = S.frameIdx;
        S.dynamicAnchor.localShifts = zeros(S.N, 2);

        refImg = getProcessedFrame(S.frameIdx);
        T = imcrop(refImg, S.dynamicAnchor.refRect);
        
        T_m = readPositiveScalar(S.hUI.efAreaMP, 1400, 'Melt Pool Threshold', true);
        
        [Gmag_T, ~] = imgradient(T);
        mask_T = T > T_m;
        
        tempGmag_T = Gmag_T;
        tempGmag_T(mask_T) = NaN; 
        T_mean = mean(tempGmag_T(:), 'omitnan');
        if isnan(T_mean), T_mean = 0; end
        
        T_norm = Gmag_T - T_mean;
        T_norm(mask_T) = 0; 

        if std(T_norm(:), 'omitnan') < 1e-5
            errordlg('Selected region has insufficient edge features or is covered by melt pool. Re-select physical boundary.');
            delete(h); return;
        end

        % [FIX v8.80 Bug2] Cancel button on dynamic anchor tracking
        hWait = waitbar(0, 'Computing melt-pool immune edge tracking...', 'CreateCancelBtn', 'setappdata(gcbf,''canceling'',1)');
        setappdata(hWait, 'canceling', 0);
        searchPad = 25; 
        prev_shift = [0, 0]; 
        frameOrder = [S.dynamicAnchor.refFrame:S.N, (S.dynamicAnchor.refFrame-1):-1:1];

        for orderIdx = 1:numel(frameOrder)
            i = frameOrder(orderIdx);
            if i == S.dynamicAnchor.refFrame
                S.dynamicAnchor.localShifts(i, :) = [0, 0];
                prev_shift = [0, 0];
                continue;
            end
            if i == S.dynamicAnchor.refFrame - 1
                prev_shift = [0, 0];
            end
            img = getProcessedFrame(i);
            [imH, imW] = size(img);
            [tH, tW] = size(T);
            
            cX = S.dynamicAnchor.refRect(1); cY = S.dynamicAnchor.refRect(2);
            
            expectedX = cX + prev_shift(1);
            expectedY = cY + prev_shift(2);
            
            roiX = round(max(1, expectedX - searchPad));
            roiY = round(max(1, expectedY - searchPad));
            roiW = round(min(imW - roiX, tW + 2*searchPad));
            roiH = round(min(imH - roiY, tH + 2*searchPad));

            if roiW < tW || roiH < tH
                S.dynamicAnchor.localShifts(i, :) = prev_shift;
                continue;
            end

            searchImg = imcrop(img, [roiX, roiY, roiW, roiH]);
            
            [Gmag_S, ~] = imgradient(searchImg);
            mask_S = searchImg > T_m;
            
            tempGmag_S = Gmag_S;
            tempGmag_S(mask_S) = NaN;
            searchImg_mean = mean(tempGmag_S(:), 'omitnan');
            if isnan(searchImg_mean), searchImg_mean = 0; end
            
            searchImg_norm = Gmag_S - searchImg_mean;
            searchImg_norm(mask_S) = 0; 

            c = normxcorr2(T_norm, searchImg_norm);
            [maxVal, maxIdx] = max(c(:));
            
            if maxVal < 0.25 
                S.dynamicAnchor.localShifts(i, :) = prev_shift;
                continue;
            end

            [ypeak, xpeak] = ind2sub(size(c), maxIdx);

            dx_sub = 0; dy_sub = 0;
            if xpeak > 1 && xpeak < size(c,2)
                val_m1 = c(ypeak, xpeak-1); val_0 = c(ypeak, xpeak); val_p1 = c(ypeak, xpeak+1);
                denom = 2 * (val_m1 - 2*val_0 + val_p1);
                if denom ~= 0, dx_sub = (val_m1 - val_p1) / denom; end
            end
            if ypeak > 1 && ypeak < size(c,1)
                val_m1 = c(ypeak-1, xpeak); val_0 = c(ypeak, xpeak); val_p1 = c(ypeak+1, xpeak);
                denom = 2 * (val_m1 - 2*val_0 + val_p1);
                if denom ~= 0, dy_sub = (val_m1 - val_p1) / denom; end
            end

            dx_sub = max(-1, min(1, dx_sub));
            dy_sub = max(-1, min(1, dy_sub));

            yOffROI = (ypeak + dy_sub) - tH;
            xOffROI = (xpeak + dx_sub) - tW;

            foundX = roiX + xOffROI;
            foundY = roiY + yOffROI;

            dx_total = foundX - cX;
            dy_total = foundY - cY;
            
            prev_shift = [dx_total, dy_total];
            S.dynamicAnchor.localShifts(i, :) = prev_shift;

            if ~isvalid(hWait) || getappdata(hWait, 'canceling'), if isvalid(hWait), delete(hWait); end; return; end
            if mod(orderIdx, 20)==0 && isvalid(hWait), waitbar(orderIdx/max(1,numel(frameOrder)), hWait); end
        end
        if isvalid(hWait), delete(hWait); end
        
        S.dynamicAnchor.isCalculated = true;
        set(S.hUI.lblAnchorStatus, 'String', 'Ready', 'ForegroundColor', [0 .6 0]);
        set(S.hUI.chkLinkAnchor, 'Enable', 'on', 'Value', 1);
        delete(h);
        msgbox('Edge gradient (melt-pool immune) anchor complete! Yellow dashed tracking box during playback.');
        updateVisuals();
    end
    
    function onToggleProgressLine(~,~)
        S.showProgressLine = ~S.showProgressLine;
        if S.showProgressLine
            set(S.hUI.btnProgress, 'String', 'Cursor:ON', 'BackgroundColor', [.8 1 .8]);
            set(S.hUI.btnProgressArea, 'String', 'Cursor:ON', 'BackgroundColor', [.8 1 .8]);
        else
            set(S.hUI.btnProgress, 'String', 'Cursor:OFF', 'BackgroundColor', [.94 .94 .94]);
            set(S.hUI.btnProgressArea, 'String', 'Cursor:OFF', 'BackgroundColor', [.94 .94 .94]);
        end
        updateFrame(S.frameIdx);
    end

    function onSetStabTarget(~,~)
        if ~S.isLoaded, errordlg('Please load data first'); return; end
        msgbox('MANUAL MODE: Draw a rectangle around a STATIC feature on the part.', 'Stabilization Setup'); h = imrect(axMain); pos = wait(h); 
        if ~isempty(pos), S.stab.initialRect = round(pos); S.stab.refFrameIdx = S.frameIdx; S.stab.autoMode = false; S.stab.shifts = zeros(S.N, 2); S.stab.isCalculated = false; S.stab.enabled = false; set(S.hUI.chkStabApply,'Enable','off','Value',0); refFrame = getProcessedFrame(S.frameIdx); [imgH, imgW] = size(refFrame); anchorCX = pos(1) + pos(3)/2; anchorCY = pos(2) + pos(4)/2; targetX = imgW * 0.5; targetY = imgH * 0.8; S.stab.anchorOffset = [targetX - anchorCX, targetY - anchorCY]; delete(h); set(S.hUI.lblStabStatus, 'String', sprintf('Manual Anchor Set @ Frame %d.', S.frameIdx), 'ForegroundColor', 'k'); end
    end
    function onAutoCalcMotion(~,~), if ~S.isLoaded, errordlg('Please load data first'); return; end; S.stab.autoMode = true; onCalcMotion(); end
    function onCalcMotion(~,~)
        prevStab = S.stab;
        wasStab = get(S.hUI.chkStabApply, 'Value');
        set(S.hUI.chkStabApply, 'Value', 0, 'Enable', 'off');
        if S.stab.autoMode
            S.stab.refFrameIdx = 1;
            S.stab.initialRect = [];
        end
        refF = S.stab.refFrameIdx;
        S.stab.isCalculated = false;
        S.stab.enabled = false;
        S.stab.shifts = zeros(S.N, 2);
        % [FIX v8.80 Bug2] Cancel button on stabilization tracking
        hWait = waitbar(0, 'Initializing Auto-Tracking Engine...', 'CreateCancelBtn', 'setappdata(gcbf,''canceling'',1)');
        setappdata(hWait, 'canceling', 0);
        function rect = findGoodFeature(imgIn), mask = imgIn < 1000; [~, Gmag] = imgradient(imgIn); Gmag(~mask) = 0; blkSz = 64; [H, W] = size(imgIn); bestScore = -1; bestR = 1; bestC = 1; stride = 32; for r = 1:stride:(H-blkSz), for c = 1:stride:(W-blkSz), val = sum(sum(Gmag(r:r+blkSz, c:c+blkSz))); centerBias = 1 - abs(c - W/2)/(W); score = val * centerBias; if score > bestScore, bestScore = score; bestR = r; bestC = c; end; end; end; if bestScore < 100, rect = []; else, rect = [bestC, bestR, blkSz, blkSz]; end; end
        try
            fullImg = getProcessedFrame(refF); [imH, imW] = size(fullImg);
            if S.stab.autoMode, if isvalid(hWait), waitbar(0.05, hWait, 'Auto-Detecting Features...'); end; S.stab.initialRect = findGoodFeature(fullImg); if isempty(S.stab.initialRect), for k = refF+1:min(S.N, refF+100), fullImg = getProcessedFrame(k); rect = findGoodFeature(fullImg); if ~isempty(rect), S.stab.refFrameIdx = k; S.stab.initialRect = rect; refF = k; break; end; end; end; end
            if isempty(S.stab.initialRect), error('Could not find any trackable feature (Video too dark?).'); end
            anchorCX = S.stab.initialRect(1) + S.stab.initialRect(3)/2; anchorCY = S.stab.initialRect(2) + S.stab.initialRect(4)/2; targetX = imW * 0.5; targetY = imH * 0.8; S.stab.anchorOffset = [targetX - anchorCX, targetY - anchorCY]; currRect = S.stab.initialRect; currTempl = imcrop(fullImg, currRect); [tH, tW] = deal(currRect(4), currRect(3)); cumulativeShift = [0, 0]; searchPad = 60; 
            for i = refF+1 : S.N
                img = getProcessedFrame(i); [imH, imW] = size(img); cX = currRect(1); cY = currRect(2); roiX = round(max(1, cX - searchPad)); roiY = round(max(1, cY - searchPad)); roiW = round(min(imW - roiX, tW + 2*searchPad)); roiH = round(min(imH - roiY, tH + 2*searchPad)); foundMatch = false;
                if roiW >= tW && roiH >= tH, searchImg = imcrop(img, [roiX, roiY, roiW, roiH]); searchImg = searchImg - mean(searchImg(:)); currTemplNorm = currTempl - mean(currTempl(:)); if std(single(currTemplNorm(:))) > 1e-5, c = normxcorr2(currTemplNorm, searchImg); [maxVal, maxIdx] = max(c(:)); if maxVal >= 0.6, [ypeak, xpeak] = ind2sub(size(c), maxIdx); yOffROI = ypeak - size(currTempl, 1); xOffROI = xpeak - size(currTempl, 2); foundX = roiX + xOffROI; foundY = roiY + yOffROI; foundMatch = true; end; end; end
                if ~foundMatch, padWide = 300; roiX = round(max(1, cX - padWide)); roiY = round(max(1, cY - padWide)); roiW = round(min(imW - roiX, tW + 2*padWide)); roiH = round(min(imH - roiY, tH + 2*padWide)); if roiW >= tW && roiH >= tH, searchImg = imcrop(img, [roiX, roiY, roiW, roiH]); searchImg = searchImg - mean(searchImg(:)); currTemplNorm = currTempl - mean(currTempl(:)); if std(single(currTemplNorm(:))) > 1e-5, c = normxcorr2(currTemplNorm, searchImg); [maxVal, maxIdx] = max(c(:)); if maxVal >= 0.55, [ypeak, xpeak] = ind2sub(size(c), maxIdx); yOffROI = ypeak - size(currTempl, 1); xOffROI = xpeak - size(currTempl, 2); foundX = roiX + xOffROI; foundY = roiY + yOffROI; foundMatch = true; end; end; end; end
                if ~foundMatch, if S.stab.autoMode, newRect = findGoodFeature(img); if isempty(newRect), S.stab.shifts(i, :) = cumulativeShift; else, currRect = newRect; currTempl = imcrop(img, currRect); [tH, tW] = deal(currRect(4), currRect(3)); S.stab.shifts(i, :) = cumulativeShift; end; continue; else, S.stab.shifts(i, :) = cumulativeShift; continue; end; end
                dX = foundX - cX; dY = foundY - cY; if abs(dX) > 200 || abs(dY) > 200, dX = 0; dY = 0; end
                cumulativeShift = cumulativeShift + [dX, dY]; S.stab.shifts(i, :) = cumulativeShift; currRect = [foundX, foundY, tW, tH]; currTempl = imcrop(img, currRect); 
                if ~isvalid(hWait) || getappdata(hWait, 'canceling'), break; end
                if mod(i, 20) == 0 && isvalid(hWait), waitbar((i-refF)/max(1, S.N-refF), hWait, sprintf('Tracking... Frame %d', i)); end
            end
            S.stab.isCalculated = true; S.stab.enabled = true; set(S.hUI.chkStabApply, 'Enable', 'on', 'Value', 1); status = 'Manual Tracking Done'; if S.stab.autoMode, status = 'Auto Relay Tracking Done'; end; set(S.hUI.lblStabStatus, 'String', status, 'ForegroundColor', [0 .6 .0]); if isvalid(hWait), delete(hWait); end; msgbox(['Stabilization Complete. ' status]); updateVisuals();
        catch ME
            if isvalid(hWait), delete(hWait); end
            S.stab = prevStab;
            if S.stab.isCalculated
                set(S.hUI.chkStabApply, 'Enable', 'on', 'Value', wasStab);
            else
                set(S.hUI.chkStabApply, 'Enable', 'off', 'Value', 0);
            end
            errordlg(['Tracking Error: ' ME.message]);
        end
    end
    function onSetBackgroundBox(~,~)
        if ~S.isLoaded, errordlg('Load data first'); return; end
        msgbox('Draw a box on a CLEAN area (e.g. chamber wall) that should be COLD/BLACK.', 'BG Correction Setup'); h = imrect(axMain); pos = wait(h);
        if ~isempty(pos), S.vapor.bgRect = round(pos); calcBackgroundCurve(); S.vapor.enabled = true; if isfield(S.hUI, 'chkVaporApply') && isgraphics(S.hUI.chkVaporApply), set(S.hUI.chkVaporApply, 'Value', 1); end; if isgraphics(h), delete(h); end; updateVisuals(); msgbox('Background correction calculated. De-hazing active.'); end
    end
    function calcBackgroundCurve()
        S.vapor.bgCurve = zeros(S.N, 1); r = S.vapor.bgRect;
        % [FIX v8.80 Bug2] Cancel button added
        hWait = waitbar(0, 'Analyzing Background Drift...', 'CreateCancelBtn', 'setappdata(gcbf,''canceling'',1)');
        setappdata(hWait, 'canceling', 0);
        lastValidVal = 0; firstVal = 0; isCanceled = false;
        for i = 1:S.N
            if ~isvalid(hWait) || getappdata(hWait, 'canceling'), isCanceled = true; break; end
            raw = double(S.matObj.(S.dataName)(:,:,i)); roi = imcrop(raw, r); currVal = mean(roi(:));
            if i == 1, lastValidVal = currVal; firstVal = currVal; S.vapor.bgCurve(i) = currVal; else, delta = currVal - lastValidVal; if delta > 50, S.vapor.bgCurve(i) = lastValidVal; else, S.vapor.bgCurve(i) = currVal; lastValidVal = currVal; end; end
            if mod(i, 20) == 0 && isvalid(hWait), waitbar(i/S.N, hWait); end
        end
        if isvalid(hWait), delete(hWait); end
        if isCanceled, msgbox('Calculation cancelled.', 'Cancelled'); return; end
        S.vapor.bgRefVal = firstVal; 
    end
    
    function ensureHistoryExists()
        if isempty(S.area.mpHistory) || length(S.area.mpHistory) ~= S.N
            S.area.mpHistory = zeros(S.N, 1); S.area.htwHistory = zeros(S.N, 1); 
            S.area.hMPHistory = zeros(S.N, 1); S.area.lMPHistory = zeros(S.N, 1);
            S.area.hHTWHistory = zeros(S.N, 1); S.area.lHTWHistory = zeros(S.N, 1);
        end
    end
    
    function [valMP, valHAZ, hMP, lMP, hHAZ, lHAZ] = performSingleFrameCalc(idx)
        img = getProcessedFrame(idx); bwMP = img >= S.area.T_melt; bwHAZ = (img >= S.area.T_htw) & (img < S.area.T_melt); 
        se = strel('disk', S.area.morphKernel); bwHAZ = imopen(bwHAZ, se); 
        CC_HTW = bwconncomp(bwHAZ); 
        if CC_HTW.NumObjects > 0, numPixels = cellfun(@numel, CC_HTW.PixelIdxList); [~, maxIdx] = max(numPixels); bwHAZ = false(size(bwHAZ)); bwHAZ(CC_HTW.PixelIdxList{maxIdx}) = true; end; 
        CC_MP = bwconncomp(bwMP); 
        if CC_MP.NumObjects > 0
            if any(bwHAZ(:)) && CC_MP.NumObjects > 1
                D_HAZ = bwdist(bwHAZ); minDists = zeros(1, CC_MP.NumObjects); for k = 1:CC_MP.NumObjects, minDists(k) = min(D_HAZ(CC_MP.PixelIdxList{k})); end; 
                [~, bestIdx] = min(minDists); bwMP = false(size(bwMP)); bwMP(CC_MP.PixelIdxList{bestIdx}) = true; 
            end
        end; 
        valMP = sum(bwMP(:)); valHAZ = sum(bwHAZ(:));
        [lMP, hMP, ~, ~] = getMorphDims(bwMP);
        [lHAZ, hHAZ, ~, ~] = getMorphDims(bwHAZ);
    end
    
    function onForceValid(~,~)
        if ~S.isLoaded, return; end
        S.area.blacklistedFrames(S.area.blacklistedFrames == S.frameIdx) = []; 
        if ~ismember(S.frameIdx, S.area.forcedFrames)
            S.area.forcedFrames(end+1) = S.frameIdx; ensureHistoryExists(); 
            [valMP, valHAZ, hMP, lMP, hHAZ, lHAZ] = performSingleFrameCalc(S.frameIdx); 
            S.area.mpHistory(S.frameIdx) = valMP; S.area.htwHistory(S.frameIdx) = valHAZ; 
            S.area.hMPHistory(S.frameIdx) = hMP; S.area.lMPHistory(S.frameIdx) = lMP;
            S.area.hHTWHistory(S.frameIdx) = hHAZ; S.area.lHTWHistory(S.frameIdx) = lHAZ;
            plotAreaCurves(); updateFrame(S.frameIdx); 
        end
    end
    function onForceRemove(~,~)
        if ~S.isLoaded, return; end
        S.area.forcedFrames(S.area.forcedFrames == S.frameIdx) = []; 
        if ~ismember(S.frameIdx, S.area.blacklistedFrames)
            S.area.blacklistedFrames(end+1) = S.frameIdx; ensureHistoryExists(); 
            S.area.mpHistory(S.frameIdx) = 0; S.area.htwHistory(S.frameIdx) = 0; 
            S.area.hMPHistory(S.frameIdx) = 0; S.area.lMPHistory(S.frameIdx) = 0;
            S.area.hHTWHistory(S.frameIdx) = 0; S.area.lHTWHistory(S.frameIdx) = 0;
            plotAreaCurves(); updateFrame(S.frameIdx); 
        end
    end
    
    function onCalcArea(~,~)
        if ~S.isLoaded, errordlg('Please load data first.'); return; end
        T_m = readPositiveScalar(S.hUI.efAreaMP, S.area.T_melt, 'Melt Pool Threshold', true);
        T_h = readPositiveScalar(S.hUI.efAreaHAZ, S.area.T_htw, 'HTW Threshold', true);
        if T_h >= T_m, errordlg('HTW threshold must be lower than Melt Pool threshold.'); return; end
        S.area.T_melt = T_m; S.area.T_htw = T_h; 
        S.area.morphKernel = max(1, round(S.area.morphKernel));
        set(S.hUI.efMorph, 'String', num2str(S.area.morphKernel));
        % [FIX v8.80 Bug2] Add Cancel button; checking it allows the loop to
        % abort immediately so the UI becomes responsive again.
        hWait = waitbar(0, 'Processing Area & Dimensional Statistics...', ...
            'CreateCancelBtn', 'setappdata(gcbf,''canceling'',1)');
        setappdata(hWait, 'canceling', 0);
        mp_hist = zeros(S.N, 1); htw_hist = zeros(S.N, 1); 
        h_mp = zeros(S.N, 1); l_mp = zeros(S.N, 1);
        h_htw = zeros(S.N, 1); l_htw = zeros(S.N, 1);
        se = strel('disk', S.area.morphKernel);
        % [FIX v8.80 Bug2] Cancel-safe loop
        try
            isCanceled = false;
            for i = 1:S.N
                if ~isvalid(hWait) || getappdata(hWait, 'canceling')
                    isCanceled = true; break;
                end
                if ismember(i, S.area.blacklistedFrames)
                    mp_hist(i) = 0; htw_hist(i) = 0; continue;
                end
                img = getProcessedFrame(i); bwMP = img >= T_m; bwHTW = (img >= T_h) & (img < T_m); bwHTW = imopen(bwHTW, se);
                CC_HTW = bwconncomp(bwHTW);
                if CC_HTW.NumObjects > 0, numPixels = cellfun(@numel, CC_HTW.PixelIdxList); [~, maxIdx] = max(numPixels); bwHTW = false(size(bwHTW)); bwHTW(CC_HTW.PixelIdxList{maxIdx}) = true; end;
                if ismember(i, S.area.forcedFrames)
                    mp_hist(i) = sum(bwMP(:)); htw_hist(i) = sum(bwHTW(:));
                    [l_mp(i), h_mp(i), ~, ~] = getMorphDims(bwMP);
                    [l_htw(i), h_htw(i), ~, ~] = getMorphDims(bwHTW);
                    continue;
                end
                mpCount = 0; htwCount = 0;
                hMPVal = 0; lMPVal = 0; hHTWVal = 0; lHTWVal = 0;
                CC_MP = bwconncomp(bwMP);
                if CC_MP.NumObjects > 0
                    if any(bwHTW(:)) && CC_MP.NumObjects > 1
                        D_HTW = bwdist(bwHTW); minDists = zeros(1, CC_MP.NumObjects); for k = 1:CC_MP.NumObjects, minDists(k) = min(D_HTW(CC_MP.PixelIdxList{k})); end;
                        [~, bestIdx] = min(minDists); bwMP = false(size(bwMP)); bwMP(CC_MP.PixelIdxList{bestIdx}) = true;
                    end
                    areaMP = sum(bwMP(:)); areaHTW = sum(bwHTW(:));
                    if areaHTW > 0
                        D_MP = bwdist(bwMP); minDist = min(D_MP(bwHTW)); ratioOk = areaMP >= (areaHTW / S.area.minRatio);
                        if minDist <= S.area.proximityThresh && ratioOk
                            mpCount = areaMP; htwCount = areaHTW;
                            [lMPVal, hMPVal, ~, ~] = getMorphDims(bwMP);
                            [lHTWVal, hHTWVal, ~, ~] = getMorphDims(bwHTW);
                        end
                    else
                        mpCount = areaMP;
                        [lMPVal, hMPVal, ~, ~] = getMorphDims(bwMP);
                    end
                end
                mp_hist(i) = mpCount; htw_hist(i) = htwCount;
                h_mp(i) = hMPVal; l_mp(i) = lMPVal;
                h_htw(i) = hHTWVal; l_htw(i) = lHTWVal;
                if mod(i, 20) == 0 && isvalid(hWait), waitbar(i/S.N, hWait, sprintf('Frame %d / %d', i, S.N)); end
            end
            if isvalid(hWait), delete(hWait); end
            if isCanceled
                msgbox('Calculation cancelled.', 'Cancelled');
            else
                S.area.mpHistory = mp_hist; S.area.htwHistory = htw_hist;
                S.area.hMPHistory = h_mp; S.area.lMPHistory = l_mp;
                S.area.hHTWHistory = h_htw; S.area.lHTWHistory = l_htw;
                plotAreaCurves();
            end
        catch ME, if isvalid(hWait), delete(hWait); end; errordlg(['Calculation Error: ' ME.message]); end
    end
    
    function plotAreaCurves()
        cla(axArea); hold(axArea, 'on');
        cla(axSizeH); hold(axSizeH, 'on');
        cla(axSizeL); hold(axSizeL, 'on');
        
        xData = 1:S.N;
        xLabelStr = 'Frame';
        if strcmp(S.plotXMode, 'Time')
            xData = xData / S.fps;
            xLabelStr = 'Time (s)';
        end
        
        unitArea = 'pixels'; unitLine = 'pixels';
        scaleArea = 1; scaleLine = 1;
        if S.area.isCalibrated
            unitArea = 'mm^2'; unitLine = 'mm'; 
            scaleArea = (1/S.area.pxPerMm)^2; 
            scaleLine = 1/S.area.pxPerMm;
        end
        
        hX1 = xlabel(axArea, xLabelStr); hY1 = ylabel(axArea, sprintf('Area (%s)', unitArea));
        hX2 = xlabel(axSizeH, xLabelStr); hY2 = ylabel(axSizeH, sprintf('Size H [Vert] (%s)', unitLine));
        hX3 = xlabel(axSizeL, xLabelStr); hY3 = ylabel(axSizeL, sprintf('Size L [Horz] (%s)', unitLine));
        
        set([hX1, hY1, hX2, hY2, hX3, hY3], 'ButtonDownFcn', @onEditLabel, 'PickableParts', 'visible');
        set([axArea, axSizeH, axSizeL], 'FontSize', 10);
        set([hX1, hX2, hX3], 'FontWeight', 'bold');
        
        if isempty(S.area.mpHistory), return; end
        
        % Data scaling
        mpA = S.area.mpHistory * scaleArea; htwA = S.area.htwHistory * scaleArea;
        hMP = S.area.hMPHistory * scaleLine; lMP = S.area.lMPHistory * scaleLine;
        hHTW = S.area.hHTWHistory * scaleLine; lHTW = S.area.lHTWHistory * scaleLine;
        
        mode = get(S.hUI.popAreaDisplay, 'Value');
        
        if mode == 1 || mode == 2
             plot(axArea, xData, mpA, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Melt Pool Area');
             plot(axSizeH, xData, hMP, 'r-', 'LineWidth', 1.5, 'DisplayName', 'MP Size H');
             plot(axSizeL, xData, lMP, 'r-', 'LineWidth', 1.5, 'DisplayName', 'MP Size L');
        end
        if mode == 1 || mode == 3
             plot(axArea, xData, htwA, 'Color', [0.6 0 0.8], 'LineWidth', 1.5, 'DisplayName', 'HTW Area');
             plot(axSizeH, xData, hHTW, 'Color', [0.6 0 0.8], 'LineWidth', 1.5, 'DisplayName', 'HTW Size H');
             plot(axSizeL, xData, lHTW, 'Color', [0.6 0 0.8], 'LineWidth', 1.5, 'DisplayName', 'HTW Size L');
        end
        
        legend(axArea, 'show'); grid(axArea, 'on');
        legend(axSizeH, 'show'); grid(axSizeH, 'on');
        legend(axSizeL, 'show'); grid(axSizeL, 'on');
        
        % Redraw progress lines after cla
        if S.showProgressLine
            currentX = S.frameIdx; if strcmp(S.plotXMode, 'Time'), currentX = currentX / S.fps; end
            S.hProgressLineArea = xline(axArea, currentX, 'k-', 'LineWidth', 1.2, 'HitTest', 'off'); S.hProgressLineArea.Annotation.LegendInformation.IconDisplayStyle = 'off';
            S.hProgressLineH = xline(axSizeH, currentX, 'k-', 'LineWidth', 1.2, 'HitTest', 'off'); S.hProgressLineH.Annotation.LegendInformation.IconDisplayStyle = 'off';
            S.hProgressLineL = xline(axSizeL, currentX, 'k-', 'LineWidth', 1.2, 'HitTest', 'off'); S.hProgressLineL.Annotation.LegendInformation.IconDisplayStyle = 'off';
        end
    end
    
    function onExportAreaCSV(~,~)
        if isempty(S.area.mpHistory), errordlg('No data to export.'); return; end
        syncFPS(true);
        scaleArea = 1; scaleLine = 1;
        uArea = '_Px2'; uLine = '_Px';
        if S.area.isCalibrated
            scaleArea = (1/S.area.pxPerMm)^2; scaleLine = 1/S.area.pxPerMm;
            uArea = '_mm2'; uLine = '_mm';
        end
        [f,p] = uiputfile('area_size_stats.csv');
        if f
            Frames = (1:S.N)';
            Time = Frames / S.fps;
            T = table(Frames, Time, S.area.mpHistory*scaleArea, S.area.htwHistory*scaleArea, ...
                S.area.hMPHistory*scaleLine, S.area.lMPHistory*scaleLine, S.area.hHTWHistory*scaleLine, S.area.lHTWHistory*scaleLine, ...
                'VariableNames', {'Frame', 'Time_s', ['MeltPoolArea' uArea], ['HTWArea' uArea], ...
                ['MP_SizeH' uLine], ['MP_SizeL' uLine], ['HTW_SizeH' uLine], ['HTW_SizeL' uLine]});
            writetable(T, fullfile(p,f));
        end
    end
    function onVaporConfigChange(~,~)
        if isfield(S.hUI, 'efRefTemp') && isgraphics(S.hUI.efRefTemp)
            S.vapor.refTemp = readPositiveScalar(S.hUI.efRefTemp, S.vapor.refTemp, 'Reference Temperature', true);
        end
        if isfield(S.hUI, 'chkVaporApply') && isgraphics(S.hUI.chkVaporApply)
            S.vapor.enabled = get(S.hUI.chkVaporApply, 'Value');
        end
        
        if S.vapor.enabled && S.vapor.isPicking
            onTogglePicking(); 
        end
        
        if isfield(S.hUI, 'hAnchorFig') && isgraphics(S.hUI.hAnchorFig)
             updateVaporTable();
        end
        
        updateVisuals();
    end
    
    function onClearVapor(~,~)
        S.vapor.anchors = []; 
        S.vapor.bgRect = []; S.vapor.bgCurve = [];
        S.layers = struct('id',{},'sampleF',{},'measPeak',{},'startF',{},'endF',{},'Q',{},'targetT',{},'offset',{}); 
        updateVaporTable(); 
        if isfield(S.hUI, 'lblMultiStatus') && isgraphics(S.hUI.lblMultiStatus), updateMultiStatus(); end
        updateVisuals();
    end
    
    function onFilterConfigChange(~,~)
        val = S.hUI.popDenoise.Value; strs = S.hUI.popDenoise.String; typeStr = strs{val};
        if contains(typeStr, 'Median'), S.preproc.denoiseType = 'Median';
        elseif contains(typeStr, 'Gaussian'), S.preproc.denoiseType = 'Gaussian';
        elseif contains(typeStr, 'Morph'), S.preproc.denoiseType = 'Morph';
        else, S.preproc.denoiseType = 'None'; end
        S.preproc.denoiseParam = readPositiveScalar(S.hUI.editDenoiseParam, max(1, S.preproc.denoiseParam), 'Filter Parameter', true);
        if strcmp(S.preproc.denoiseType, 'Median') || strcmp(S.preproc.denoiseType, 'Morph')
            S.preproc.denoiseParam = max(1, round(S.preproc.denoiseParam));
            set(S.hUI.editDenoiseParam, 'String', num2str(S.preproc.denoiseParam));
        end
        strConfig = get(S.hUI.editCLAHEConfig, 'String');
        S.preproc.claheSchedule = [];
        if ~isempty(strConfig)
            try
                entries = strsplit(strConfig, ';');
                for i = 1:length(entries)
                    entry = strtrim(entries{i});
                    if isempty(entry), continue; end
                    parts = strsplit(entry, ':');
                    if length(parts) == 2
                        rangeStr = parts{1}; clipStr = parts{2};
                        rangeParts = strsplit(rangeStr, '-');
                        if length(rangeParts) == 2
                            sF = str2double(rangeParts{1}); eF = str2double(rangeParts{2}); clip = str2double(clipStr);
                            if ~isnan(sF) && ~isnan(eF) && ~isnan(clip) && sF >= 1 && eF >= sF && clip > 0 && clip <= 1
                                S.preproc.claheSchedule = [S.preproc.claheSchedule; sF, eF, clip];
                            end
                        end
                    end
                end
            catch, disp('CLAHE Config Parse Error'); end
        end
        updateVisuals();
    end
    function onAreaConfigChange(~,~)
        newTm = readPositiveScalar(S.hUI.efAreaMP, S.area.T_melt, 'Melt Pool Threshold', true);
        newTh = readPositiveScalar(S.hUI.efAreaHAZ, S.area.T_htw, 'HTW Threshold', true);
        if newTh >= newTm
            warndlg('HTW threshold must be lower than Melt Pool threshold. Reverted to previous values.', 'Invalid Area Thresholds');
            set(S.hUI.efAreaMP, 'String', num2str(S.area.T_melt));
            set(S.hUI.efAreaHAZ, 'String', num2str(S.area.T_htw));
        else
            S.area.T_melt = newTm;
            S.area.T_htw = newTh;
        end
        S.area.enabled = get(S.hUI.chkAreaVis, 'Value');
        updateFrame(S.frameIdx); 
    end
    function onParamConfigChange(~,~)
        S.area.proximityThresh = readPositiveScalar(S.hUI.efDist, S.area.proximityThresh, 'Proximity Distance', true);
        S.area.minRatio = readPositiveScalar(S.hUI.efRatio, S.area.minRatio, 'Minimum Ratio', true);
        S.area.morphKernel = max(1, round(readPositiveScalar(S.hUI.efMorph, S.area.morphKernel, 'Morph Kernel', true)));
        set(S.hUI.efDist, 'String', num2str(S.area.proximityThresh));
        set(S.hUI.efRatio, 'String', num2str(S.area.minRatio));
        set(S.hUI.efMorph, 'String', num2str(S.area.morphKernel));
        updateFrame(S.frameIdx); 
    end
    function onManageCurves(~,~)
        if isempty(S.pointDataCell), msgbox('No curves to manage.'); return; end
        numC = length(S.pointDataCell);
        names = cell(1, numC);
        for i=1:numC, names{i} = sprintf('ID %d', i); end
        if isempty(S.hPlotLines) || ~all(isgraphics(S.hPlotLines)), refreshPointPlot(); end
        currentVis = true(1, numC);
        for i=1:numC
            if strcmp(S.hPlotLines(i).Visible, 'off'), currentVis(i) = false; end
        end
        initialIdx = find(currentVis);
        [indx, tf] = listdlg('ListString', names, 'SelectionMode', 'multiple', ...
            'Name', 'Curve Visibility', 'PromptString', 'Select curves to SHOW:', ...
            'InitialValue', initialIdx);
        if tf
            for i=1:numC
                if ismember(i, indx)
                    S.hPlotLines(i).Visible = 'on';
                else
                    S.hPlotLines(i).Visible = 'off';
                end
            end
        end
    end
    function onToggleXAxis(~,~)
        if strcmp(S.plotXMode, 'Time')
            S.plotXMode = 'Frame';
            set(S.hUI.btnAxisTemp, 'String', ' Frame');
            set(S.hUI.btnAxisArea, 'String', ' Toggle X-Axis');
        else
            S.plotXMode = 'Time';
            set(S.hUI.btnAxisTemp, 'String', ' Time');
            set(S.hUI.btnAxisArea, 'String', ' Toggle X-Axis');
        end
        syncFPS(true);
        refreshPointPlot();
        plotAreaCurves();
    end
    function onCalibrateScale(~,~)
        if ~S.isLoaded, return; end
        msgbox('Click and drag a line over a known physical length (e.g. part width).', 'Calibration Step 1');
        h = drawline(axMain, 'Color', 'c', 'LineWidth', 2);
        pos = h.Position;
        lenPx = sqrt(sum((pos(2,:) - pos(1,:)).^2));
        answer = inputdlg({sprintf('Measured Length: %.1f pixels.\nEnter Real Length (mm):', lenPx)}, 'Calibration Step 2', [1 50], {'10'});
        if ~isempty(answer)
            realMm = str2double(answer{1});
            if ~isnan(realMm) && realMm > 0
                S.area.pxPerMm = lenPx / realMm;
                S.area.isCalibrated = true;
                ylabel(axArea, 'Area (mm^2)');
                plotAreaCurves(); 
                updateFrame(S.frameIdx); 
                delete(h);
                msgbox(sprintf('Calibration Saved.\nRatio: %.2f pixels/mm', S.area.pxPerMm), 'Success');
            else
                delete(h);
                errordlg('Invalid length entered.');
            end
        else
            delete(h);
        end
    end
    function onEditLabel(src, ~)
        answer = inputdlg('Enter new label text:', 'Rename Label', [1 50], {src.String});
        if ~isempty(answer)
            src.String = answer{1};
        end
    end
    function onTogglePicking(~,~)
        if ~S.isLoaded, return; end
        if S.vapor.isPicking
            S.vapor.isPicking = false;
            set(S.hUI.btnPick, 'String', '+ Anchor Point', 'BackgroundColor', [0.94 0.94 0.94]);
            set(S.hUI.btnAutoCatch, 'Enable', 'off');
            title(axMain, sprintf('Variable: %s | Frame: %d / %d', S.dataName, S.frameIdx, S.N));
            if ~isempty(S.hAutoCircle) && isgraphics(S.hAutoCircle), delete(S.hAutoCircle); S.hAutoCircle=[]; end
        else
            S.vapor.isPicking = true;
            stop(S.playTimer); set(S.hUI.btnPlay, 'String', '> Play', 'Value', 0);
            set(S.hUI.btnPick, 'String', 'Stop Picking', 'BackgroundColor', [1 0.8 0.8]);
            set(S.hUI.btnAutoCatch, 'Enable', 'on');
            title(axMain, '【PICKING MODE】Manual click OR Auto-Catch. Move slider to change frame.', 'Color', 'm', 'FontSize', 11);
        end
    end
    function onAutoCatch(~,~)
        % [FIX v8.81] Gradient-based melt pool boundary detection replaces global max.
        % The solid-liquid interface at T = T_liquidus is a thermodynamically
        % guaranteed isotherm, providing a physics-based calibration anchor.
        % Radial gradient analysis locates the steepest thermal gradient from
        % the melt pool center outward — the boundary where |dT/dr| peaks.
        if ~S.vapor.isPicking, return; end
        img = getProcessedFrame(S.frameIdx);
        [maxVal, maxIdx] = max(img(:));
        [cy, cx] = ind2sub(size(img), maxIdx);

        bTemp = detectMeltPoolBoundaryTemp(img, S.vapor.refTemp);
        if isnan(bTemp)
            warndlg(sprintf(['Melt pool boundary not detected in this frame.\n\n' ...
                'Max pixel: %.0f C at (%d,%d).\n\n' ...
                'Possible causes:\n' ...
                '- No melt pool present (cooling / interpass)\n' ...
                '- Melt pool too small or irregular\n' ...
                '- Try a frame with a clear, stable melt pool.'], maxVal, cx, cy), ...
                'Boundary Detection Failed');
            return;
        end
        addVaporAnchorPoint(S.frameIdx, bTemp);

        hold(axMain, 'on');
        if ~isempty(S.hAutoCircle) && isgraphics(S.hAutoCircle), delete(S.hAutoCircle); end
        S.hAutoCircle = plot(axMain, cx, cy, 'go', 'MarkerSize', 8, 'LineWidth', 2, 'HitTest', 'off');
        hold(axMain, 'off');
        title(axMain, sprintf('Boundary: T=%.1f C (offset=%.0f) | Max=%.0f C @(%d,%d)', ...
            bTemp, S.vapor.refTemp - bTemp, maxVal, cx, cy), 'Color', 'g');
    end
    function addVaporAnchorPoint(f, val)
        S.vapor.anchors = [S.vapor.anchors; f, val];
        updateVaporTable();
        updateFrame(S.frameIdx);
    end

    function onAutoSequence(~,~)
        % Full-sequence automatic melt pool boundary detection.
        % Processes every frame, detects solid-liquid interface via gradient
        % analysis, fills gaps with linear interpolation, applies moving
        % median denoising, and stores anchors at regular intervals.
        if ~S.isLoaded, errordlg('Please load data first.'); return; end

        answer = questdlg(sprintf(['Auto-detect melt pool boundaries across all %d frames.\n\n' ...
            'Estimated time: ~%d seconds.\n\n' ...
            'This will:\n' ...
            '  1. Scan every frame for solid-liquid boundaries\n' ...
            '  2. Fill gaps with interpolation\n' ...
            '  3. Apply noise reduction\n' ...
            '  4. Store anchors at regular intervals\n' ...
            '  5. Show a review chart for verification'], S.N, round(S.N * 0.004)), ...
            'Auto Sequence Calibration', 'Start', 'Cancel', 'Start');
        if ~strcmp(answer, 'Start'), return; end

        if strcmp(S.playTimer.Running, 'on')
            stop(S.playTimer);
            set(S.hUI.btnPlay, 'String', '> Play', 'Value', 0);
        end

        refTemp = S.vapor.refTemp;
        MIN_RADIALS = 15;
        MIN_INTERVAL = 3;

        % De-haze must be configured BEFORE running auto-sequence.
        % Without it, the rising background (~525 to ~928 C) shifts boundary
        % temperatures upward, corrupting the offset curve.
        if isempty(S.vapor.bgCurve)
            warndlg(sprintf(['De-Haze (Set Clean BG) not configured.\n\n' ...
                'The rising background temperature will bias boundary detection.\n\n' ...
                'RECOMMENDED WORKFLOW:\n' ...
                '1. Click Set Clean BG -> Draw ROI on a cold chamber area\n' ...
                '2. Then run Auto Sequence again\n\n' ...
                'Proceeding without de-haze may produce incorrect offsets.']), ...
                'Pre-flight Warning');
        end

        hWait = waitbar(0, 'Scanning frames for melt pool boundaries...', ...
            'CreateCancelBtn', 'setappdata(gcbf,''canceling'',1)');
        setappdata(hWait, 'canceling', 0);

        boundTemps = nan(S.N, 1);
        isCanceled = false;

        try
            for i = 1:S.N
                if ~isvalid(hWait) || getappdata(hWait, 'canceling')
                    isCanceled = true; break;
                end
                raw = double(S.matObj.(S.dataName)(:,:,i));
                % Apply denoise if configured (consistent with getProcessedFrame)
                if strcmp(S.preproc.denoiseType, 'Median')
                    raw = medfilt2(raw, [S.preproc.denoiseParam S.preproc.denoiseParam]);
                elseif strcmp(S.preproc.denoiseType, 'Gaussian')
                    raw = imgaussfilt(raw, S.preproc.denoiseParam);
                elseif strcmp(S.preproc.denoiseType, 'Morph')
                    se = strel('disk', S.preproc.denoiseParam);
                    raw = imopen(raw, se);
                end
                % Apply de-haze to remove background drift before boundary detection
                if ~isempty(S.vapor.bgCurve) && i <= length(S.vapor.bgCurve)
                    drift = S.vapor.bgCurve(i) - S.vapor.bgRefVal;
                    raw = raw - drift;
                end
                boundTemps(i) = detectMeltPoolBoundaryTemp(raw, refTemp, MIN_RADIALS);
                if mod(i, 200) == 0 && isvalid(hWait)
                    nFound = sum(~isnan(boundTemps(1:i)));
                    waitbar(i/S.N, hWait, sprintf('Frame %d/%d | %d boundaries found', i, S.N, nFound));
                end
            end
        catch ME
            if isvalid(hWait), delete(hWait); end
            errordlg(['Scan error: ' ME.message]); return;
        end

        if isvalid(hWait), delete(hWait); end
        if isCanceled, msgbox('Auto-sequence cancelled.', 'Cancelled'); return; end

        nDetected = sum(~isnan(boundTemps));
        if nDetected < 2
            errordlg(sprintf('Only %d frames with melt pool detected. Cannot build anchor sequence.', nDetected));
            return;
        end

        boundFilled = fillmissing(boundTemps, 'linear');
        boundSmooth = movmedian(boundFilled, 11, 'omitnan');

        S.vapor.anchors = [];
        lastFrame = -MIN_INTERVAL;
        anchorCount = 0;
        for i = 1:S.N
            if ~isnan(boundTemps(i)) && (i - lastFrame) >= MIN_INTERVAL
                lastFrame = i;
                anchorCount = anchorCount + 1;
                S.vapor.anchors(anchorCount, :) = [i, boundSmooth(i)];
            end
        end

        updateVaporTable();
        updateVisuals();

        showAnchorReview(boundTemps, boundSmooth, refTemp, S.vapor.anchors);

        msgbox(sprintf(['Auto-sequence complete.\n\n' ...
            '%d melt pool boundaries detected (%d frames scanned).\n' ...
            '%d anchors stored.\n\n' ...
            'Review the chart to verify boundary quality.'], ...
            nDetected, S.N, anchorCount), 'Auto Sequence Done');
    end

    function showAnchorReview(rawTemps, smoothTemps, refTemp, anchors)
        % --- English Figure ---
        figEN = figure('Name', 'Anchor Sequence Review', 'NumberTitle', 'off', ...
            'Color', 'w', 'Position', [150 150 1000 500]);

        axEN = axes('Parent', figEN);
        hold(axEN, 'on');

        xAll = 1:length(rawTemps);
        plot(axEN, xAll, rawTemps, '.', 'Color', [0.7 0.7 0.7], 'MarkerSize', 2, ...
            'DisplayName', 'Raw Boundary Detection');
        plot(axEN, xAll, smoothTemps, 'b-', 'LineWidth', 1.5, ...
            'DisplayName', 'Smoothed (movmedian)');

        yline(axEN, refTemp, 'r--', 'LineWidth', 1.5, ...
            'DisplayName', sprintf('refTemp = %.0f °C', refTemp));

        if ~isempty(anchors)
            plot(axEN, anchors(:,1), anchors(:,2), 'go', 'MarkerSize', 4, ...
                'MarkerFaceColor', 'g', 'DisplayName', sprintf('%d Stored Anchors', size(anchors,1)));
        end

        xlabel(axEN, 'Frame', 'FontWeight', 'bold');
        ylabel(axEN, 'Boundary Temperature (°C)', 'FontWeight', 'bold');
        title(axEN, sprintf('Melt Pool Boundary Temperature vs. Frame (refTemp=%.0f °C)', refTemp), ...
            'FontWeight', 'bold');
        legend(axEN, 'Location', 'best');
        grid(axEN, 'on');

        % --- Russian Figure ---
        figRU = figure('Name', 'Обзор последовательности якорей', 'NumberTitle', 'off', ...
            'Color', 'w', 'Position', [200 200 1000 500]);

        axRU = axes('Parent', figRU);
        hold(axRU, 'on');

        plot(axRU, xAll, rawTemps, '.', 'Color', [0.7 0.7 0.7], 'MarkerSize', 2, ...
            'DisplayName', 'Исходное обнаружение границ');
        plot(axRU, xAll, smoothTemps, 'b-', 'LineWidth', 1.5, ...
            'DisplayName', 'Сглаженные (медианный фильтр)');

        yline(axRU, refTemp, 'r--', 'LineWidth', 1.5, ...
            'DisplayName', sprintf('refTemp = %.0f °C', refTemp));

        if ~isempty(anchors)
            plot(axRU, anchors(:,1), anchors(:,2), 'go', 'MarkerSize', 4, ...
                'MarkerFaceColor', 'g', 'DisplayName', sprintf('%d сохранённых якорей', size(anchors,1)));
        end

        xlabel(axRU, 'Кадр', 'FontWeight', 'bold');
        ylabel(axRU, 'Температура границы (°C)', 'FontWeight', 'bold');
        title(axRU, sprintf('Температура границы ванны расплава от кадра (refTemp=%.0f °C)', refTemp), ...
            'FontWeight', 'bold');
        legend(axRU, 'Location', 'best');
        grid(axRU, 'on');
    end

    function bTemp = detectMeltPoolBoundaryTemp(img, refTemp, minRadials)
        % Locate melt pool boundary via radial gradient analysis.
        % The solid-liquid interface has the steepest thermal gradient.
        % Returns camera-measured temperature at the boundary, or NaN if not detected.
        % minRadials: minimum valid radial directions (default 3 for single-frame, 15 for auto-sequence)
        if nargin < 3, minRadials = 3; end
        [H, W] = size(img);
        [maxVal, maxIdx] = max(img(:));
        if isempty(maxVal) || maxVal < (refTemp * 0.5)
            bTemp = NaN; return;
        end
        [cy, cx] = ind2sub([H, W], maxIdx);
        nAngles = 36;
        angles = linspace(0, 2*pi, nAngles + 1); angles = angles(1:end-1);
        maxR = min([cx-2, W-cx-1, cy-2, H-cy-1]);
        if maxR < 10, bTemp = NaN; return; end

        boundTemps = [];
        for theta = angles
            nPts = min(60, maxR);
            r = linspace(2, maxR, nPts);
            xs = round(cx + r .* cos(theta)); ys = round(cy + r .* sin(theta));
            valid = xs >= 1 & xs <= W & ys >= 1 & ys <= H;
            if sum(valid) < 5, continue; end
            prof = img(sub2ind([H,W], ys(valid), xs(valid)));
            if length(prof) < 5 || prof(1) < (refTemp * 0.5), continue; end
            grad = abs(diff(prof));
            [~, gIdx] = max(grad);
            if gIdx > 1 && gIdx < length(prof)
                boundTemps(end+1) = prof(gIdx);
            end
        end

        if isempty(boundTemps)
            bTemp = NaN;
        else
            medT = median(boundTemps);
            thresh = max(2 * std(boundTemps), 50);
            valid = abs(boundTemps - medT) <= thresh;
            if sum(valid) < minRadials
                bTemp = NaN;
            else
                bTemp = mean(boundTemps(valid));
            end
        end
    end

    function updateVaporTable()
        if isempty(S.vapor.anchors)
            d = []; 
        else
            refVal = S.vapor.refTemp; 
            offsets = refVal - S.vapor.anchors(:,2);
            d = [S.vapor.anchors(:,1), S.vapor.anchors(:,2), offsets]; 
        end
        
        if isfield(S.hUI, 'tblVapor') && isgraphics(S.hUI.tblVapor)
            set(S.hUI.tblVapor, 'Data', d);
        end
    end

    function restoreAnalysisGraphics()
        if ~S.isLoaded, return; end
        if ~isempty(S.hPointMarkers), delete(S.hPointMarkers(isgraphics(S.hPointMarkers))); end
        if ~isempty(S.hPointTexts), delete(S.hPointTexts(isgraphics(S.hPointTexts))); end
        if ~isempty(S.hRectOutlines), delete(S.hRectOutlines(isgraphics(S.hRectOutlines))); end
        delete(findall(axMain, 'Tag', 'AnalysisOverlay'));
        S.hPointMarkers = gobjects(0);
        S.hPointTexts = gobjects(0);
        S.hRectOutlines = gobjects(0);

        useAnchor = get(S.hUI.chkLinkAnchor, 'Value') && S.dynamicAnchor.isCalculated;
        shiftX = 0; shiftY = 0;
        if useAnchor && S.frameIdx <= size(S.dynamicAnchor.localShifts, 1)
            shiftX = S.dynamicAnchor.localShifts(S.frameIdx, 1);
            shiftY = S.dynamicAnchor.localShifts(S.frameIdx, 2);
        end

        hold(axMain, 'on');
        for pIdx = 1:length(S.analysisBaseCoords)
            item = S.analysisBaseCoords{pIdx};
            if ~isstruct(item) || ~isfield(item, 'type') || ~isfield(item, 'coords'), continue; end
            base = item.coords;
            if strcmp(item.type, 'Point')
                pos = [base(1) + shiftX, base(2) + shiftY];
                S.hPointMarkers(end+1) = plot(axMain, pos(1), pos(2), 'go', 'MarkerSize', 8, 'LineWidth', 1.5, 'HitTest', 'off', 'Tag', 'AnalysisOverlay');
                S.hPointTexts(end+1) = text(axMain, pos(1)+5, pos(2)-5, num2str(pIdx), 'Color', 'g', 'FontWeight', 'bold', 'HitTest', 'off', 'Tag', 'AnalysisOverlay');
            elseif strcmp(item.type, 'Rect')
                pos = [base(1)+shiftX, base(2)+shiftY, base(3), base(4)];
                S.hRectOutlines(end+1) = rectangle(axMain, 'Position', pos, 'EdgeColor', 'g', 'FaceColor', 'none', 'HitTest', 'off', 'Tag', 'AnalysisOverlay');
                S.hPointTexts(end+1) = text(axMain, pos(1), pos(2)-10, ['Area ' num2str(pIdx)], 'Color', 'g', 'FontWeight', 'bold', 'HitTest', 'off', 'Tag', 'AnalysisOverlay');
            end
        end
        if ~isempty(S.roiLines)
            plot(axMain, S.roiLines(:,1), S.roiLines(:,2), 'c-', 'LineWidth', 1.5, 'HitTest', 'off', 'Tag', 'AnalysisOverlay');
        end
        hold(axMain, 'off');
    end

    function previewGammaCurve(~,~)
       if ~S.isLoaded, errordlg('Load Data First'); return; end
       onVaporConfigChange();
       if isempty(S.vapor.gammaSchedule), errordlg('No valid gamma config'); return; end
       gFig = figure('Name', 'Gamma Curve Preview', 'NumberTitle','off','Color','w', 'Position', [100 100 600 400]);
       axG = axes('Parent',gFig); hold(axG, 'on');
       x = 1:S.N; y = ones(1, S.N);
       for idx = 1:S.N
            for k = 1:length(S.vapor.gammaSchedule)
                item = S.vapor.gammaSchedule(k);
                if idx >= item.fS && idx <= item.fE
                    t = (idx - item.fS) / max(1, (item.fE - item.fS));
                    if strcmp(item.mode, 'Lin'), y(idx) = item.gS + t * (item.gE - item.gS);
                    elseif strcmp(item.mode, 'Exp'), gS = max(0.1, item.gS); gE = max(0.1, item.gE); y(idx) = gS * (gE / gS)^t; end
                    break;
                end
            end
       end
       plot(axG, x, y, 'b-', 'LineWidth', 2); grid(axG, 'on'); xlabel('Frame'); ylabel('Gamma Value'); title('Dynamic Gamma Compensation Curve');
    end
    
    function history = extractTimeProfile(roiType, coords)
        history = zeros(S.N, 1);
        % [FIX v8.80 Bug2] Cancel button
        hWait = waitbar(0, 'Extracting Data...', 'CreateCancelBtn', 'setappdata(gcbf,''canceling'',1)');
        setappdata(hWait, 'canceling', 0);
        useAnchor = get(S.hUI.chkLinkAnchor, 'Value') && S.dynamicAnchor.isCalculated;
        
        im1 = getProcessedFrame(1);
        [imH, imW] = size(im1);
        [X, Y] = meshgrid(1:imW, 1:imH);
        
        for i = 1:S.N
            im = getProcessedFrame(i); 
            
            shiftX = 0; shiftY = 0;
            if useAnchor && i <= size(S.dynamicAnchor.localShifts, 1)
                shiftX = S.dynamicAnchor.localShifts(i, 1);
                shiftY = S.dynamicAnchor.localShifts(i, 2);
            end
            
            if strcmp(roiType, 'Point')
                x_cur = coords(1) + shiftX;
                y_cur = coords(2) + shiftY;
                val = interp2(X, Y, im, x_cur, y_cur, 'linear', NaN);
                if isnan(val), history(i) = 0; else, history(i) = val; end
            elseif strcmp(roiType, 'Rect')
                [xq, yq] = meshgrid(coords(1):coords(1)+coords(3), coords(2):coords(2)+coords(4));
                xq = xq + shiftX;
                yq = yq + shiftY;
                vals = interp2(X, Y, im, xq, yq, 'linear', NaN);
                history(i) = mean(vals(:), 'omitnan');
                if isnan(history(i)), history(i) = 0; end
            end
            if ~isvalid(hWait) || getappdata(hWait, 'canceling'), if isvalid(hWait), delete(hWait); end; return; end
            if mod(i, 10) == 0 && isvalid(hWait), waitbar(i/S.N, hWait); end
        end
        if isvalid(hWait), delete(hWait); end
    end
    
    function processAnalysisData(history, labelType)
        pIdx = length(S.pointDataCell) + 1; S.pointDataCell{pIdx} = history;
        [pVal, pIdx_f] = max(history);
        Ts_v = readPositiveScalar(S.hUI.efTStart, 1000, 'Ts Threshold', true);
        Te_v = readPositiveScalar(S.hUI.efTEnd, 600, 'Te Threshold', true);
        postD = history(pIdx_f:end);
        fTs = find(postD <= Ts_v, 1, 'first'); fTe = find(postD <= Te_v, 1, 'first');
        iTs = pIdx_f + (fTs-1); iTe = pIdx_f + (fTe-1);
        if isempty(fTs), iTs = pIdx_f; end; if isempty(fTe), iTe = min(S.N, iTs+1); end
        [~, nextP] = findpeaks(history(pIdx_f+1:end), 'MinPeakHeight', pVal * 0.7);
        if ~isempty(nextP), p2 = pIdx_f + nextP(1); [~, r_idx] = min(history(pIdx_f:p2)); iTr = pIdx_f + r_idx - 1;
        else, [~, r_idx] = min(history(pIdx_f:end)); iTr = pIdx_f + r_idx - 1; end
        S.allMarkerFrames{pIdx} = [pIdx_f, iTs, iTe, iTr];
        names = {' '}; for k=1:pIdx, names{end+1} = sprintf('ID %d', k); end
        set(S.hUI.selFocus, 'String', names, 'Value', pIdx + 1);
        performReport(pIdx, labelType); refreshPointPlot();
    end
    function performReport(idx, modeLabel)
        history = S.pointDataCell{idx}; f = S.allMarkerFrames{idx}; fps = syncFPS(true);
        T_Peak = history(f(1)); T_Ts = history(f(2)); T_Te = history(f(3)); T_Tr = history(f(4));
        dt_TsTe = (f(3)-f(2))/fps; rate_TsTe = (T_Ts - T_Te) / max(0.001, dt_TsTe);
        dt_PeakTr = (f(4)-f(1))/fps; rate_PeakTr = (T_Peak - T_Tr) / max(0.001, dt_PeakTr);
        report = { sprintf('>>> [ID %d %sAnalysis Report] <<<', idx, modeLabel); ...
            sprintf('Global Peak: %.1f  C (Frame:%d)', T_Peak, f(1)); sprintf('Ts Position: %.1f  C (Frame:%d)', T_Ts, f(2)); ...
            sprintf('Te Position: %.1f  C (Frame:%d)', T_Te, f(3)); ...
            sprintf('Ts-Te Duration: %.4f s', dt_TsTe); sprintf('Ts-Te Rate: %.2f  C/s', rate_TsTe); ...
            sprintf('Trough: %.1f  C (Frame:%d)', T_Tr, f(4)); ...
            sprintf('Peak-TroughDuration: %.4f s', dt_PeakTr); sprintf('Peak-Trough Rate: %.2f  C/s', rate_PeakTr); ...
            '-----------------------------------' };
        set(S.hUI.resBox, 'String', [report; get(S.hUI.resBox, 'String')]);
    end
    function onMouseMoveGlobal(~, ~)
        if ~S.isLoaded, return; end
        cp_m = get(axMain, 'CurrentPoint'); x = round(cp_m(1,1)); y = round(cp_m(1,2));
        if ~isempty(S.hImg) && isgraphics(S.hImg)
            sz = size(S.hImg.CData); 
            if x>0 && x<=sz(2) && y>0 && y<=sz(1)
                lblProbe.String = sprintf('X:%d Y:%d | T:%.1f °C', x,y,S.hImg.CData(y,x)); 
            end
        end
        if ~isempty(S.draggingLine) && isgraphics(S.draggingLine.handle)
            cp = get(axPoint, 'CurrentPoint'); 
            rawVal = cp(1,1);
            if strcmp(S.plotXMode, 'Time'), rawVal = rawVal * S.fps; end
            newVal = max(1, min(S.N, round(rawVal))); 
            if strcmp(S.plotXMode, 'Time'), S.draggingLine.handle.Value = newVal / S.fps; else, S.draggingLine.handle.Value = newVal; end
        end
        if S.selectMode && ~isempty(S.currentROI)
            pIdx = findClosestLine();
            if pIdx > 0
                if ~isempty(S.hHoverHighlight), delete(S.hHoverHighlight); end
                fR = S.currentROI(1):S.currentROI(2); yD = S.pointDataCell{pIdx}(fR);
                hold(axPoint, 'on'); S.hHoverHighlight = plot(axPoint, fR, yD, 'Color', [1 0.84 0], 'LineWidth', 3.5, 'HitTest', 'off');
                if ~isempty(S.hHoverHighlight) && isgraphics(S.hHoverHighlight)
                    S.hHoverHighlight.Annotation.LegendInformation.IconDisplayStyle = 'off';
                end
            else
                if ~isempty(S.hHoverHighlight), delete(S.hHoverHighlight); S.hHoverHighlight = []; end
            end
        end
    end
    function idx = findClosestLine()
        idx = 0; cp = get(axPoint, 'CurrentPoint'); 
        rawX = cp(1,1); if strcmp(S.plotXMode, 'Time'), currF = round(rawX * S.fps); else, currF = round(rawX); end
        mouseT = cp(1,2);
        if currF < 1 || currF > S.N || isempty(S.pointDataCell), return; end
        yL = axPoint.YLim; tol = (yL(2) - yL(1)) * 0.08; minDist = tol;
        for i = 1:length(S.pointDataCell), dist = abs(S.pointDataCell{i}(currF) - mouseT); if dist < minDist, minDist = dist; idx = i; end; end
    end
    function onMouseDown(src, ~)
        if S.selectMode
            sel = get(src, 'SelectionType');
            if strcmp(sel, 'normal')
                pIdx = findClosestLine();
                if pIdx > 0 && ~ismember(pIdx, S.selectedIndices)
                    S.selectedIndices(end+1) = pIdx; 
                    fR = S.currentROI(1):S.currentROI(2); yD = S.pointDataCell{pIdx}(fR); xData = fR;
                    if strcmp(S.plotXMode, 'Time'), xData = xData / S.fps; end
                    hold(axPoint, 'on'); lineColor = get(S.hPlotLines(pIdx), 'Color');
                    h = plot(axPoint, xData, yD, 'Color', lineColor, 'LineWidth', 3.5, 'HitTest', 'off');
                    if ~isempty(h) && isgraphics(h)
                        h.Annotation.LegendInformation.IconDisplayStyle = 'off'; S.hPermanentHighlights(end+1) = h;
                    end
                    if length(S.selectedIndices) == length(S.pointDataCell), finalizeMultiBox(); end
                end
            elseif strcmp(sel, 'alt'), finalizeMultiBox(); end
        elseif S.vapor.isPicking
            cp = get(axMain, 'CurrentPoint'); x = round(cp(1,1)); y = round(cp(1,2));
            img = getProcessedFrame(S.frameIdx); [H,W] = size(img); if x>0 && x<=W && y>0 && y<=H, val = img(y,x); addVaporAnchorPoint(S.frameIdx, val); end
        end
    end
    function finalizeMultiBox()
        fps = syncFPS(true); f1 = S.currentROI(1); f2 = S.currentROI(2);
        for i = 1:length(S.selectedIndices)
            idx = S.selectedIndices(i); activeData = S.pointDataCell{idx};
            sub = activeData(f1:f2); [Tp, ri] = max(sub); fp = f1 + ri - 1; dtH = (fp-f1)/fps; dtC = (f2-fp)/fps;
            report = { sprintf('>>> [ID %d Box-Select Report] <<<', idx); sprintf('Peak: %.1f  C (Frame:%d)', Tp, fp); ...
                sprintf('Heating Phase: %.1f -> %.1f  C | Rate: %.2f  C/s', sub(1), Tp, (Tp-sub(1))/max(0.01,dtH)); ...
                sprintf('Cooling Phase: %.1f -> %.1f  C | Rate: %.2f  C/s', Tp, sub(end), (Tp-sub(end))/max(0.01,dtC)); '-----------------------------------' };
            set(S.hUI.resBox, 'String', [report; get(S.hUI.resBox, 'String')]);
        end
        S.selectMode = false; if isgraphics(S.hBoxObj), delete(S.hBoxObj); end
        if ~isempty(S.hHoverHighlight), delete(S.hHoverHighlight); end
        if ~isempty(S.hPermanentHighlights), delete(S.hPermanentHighlights(isgraphics(S.hPermanentHighlights))); end
        tGroup.SelectedTab = tabLog;
    end
    function onMouseUp(~, ~)
        if ~isempty(S.draggingLine)
            tag = S.draggingLine.tag; rawVal = get(S.hLines.(tag),'Value');
            if strcmp(S.plotXMode, 'Time'), newVal = round(rawVal * S.fps); else, newVal = round(rawVal); end
            fIdx = get(S.hUI.selFocus, 'Value');
            if fIdx > 1
                actualIdx = fIdx - 1;
                switch tag, case 'Ts', S.allMarkerFrames{actualIdx}(2) = newVal; case 'Te', S.allMarkerFrames{actualIdx}(3) = newVal; case 'Tr', S.allMarkerFrames{actualIdx}(4) = newVal; end
                set(S.draggingLine.handle, 'LineWidth', 1.5); S.draggingLine = []; performReport(actualIdx, 'Manual Adjustment');
            end
        end
    end
    function refreshPointPlot()
        cla(axPoint); hold(axPoint, 'on'); colors = lines(max(7, length(S.pointDataCell))); 
        S.hPlotLines = gobjects(length(S.pointDataCell), 1);
        xData = 1:S.N; xLabelStr = 'Frame'; if strcmp(S.plotXMode, 'Time'), xData = xData / S.fps; xLabelStr = 'Time (s)'; end
        xlabel(axPoint, xLabelStr); ylabel(axPoint, 'T (°C)');
        if isempty(S.pointDataCell), return; end
        for i = 1:length(S.pointDataCell), S.hPlotLines(i) = plot(axPoint, xData, S.pointDataCell{i}, 'Color', colors(i,:), 'LineWidth', 1, 'DisplayName', sprintf('ID %d', i)); end
        refreshMarkers(); grid(axPoint, 'on'); legend(axPoint, 'show', 'Location', 'best');
    end
    function refreshMarkers()
        delete(findall(axPoint,'Type','ConstantLine')); 
        
        if S.showProgressLine
            S.hProgressLine = xline(axPoint, 1, 'k-', 'LineWidth', 1.2, 'HitTest', 'off');
            S.hProgressLine.Annotation.LegendInformation.IconDisplayStyle = 'off';
            currentX = S.frameIdx; if strcmp(S.plotXMode, 'Time'), currentX = currentX / S.fps; end
            set(S.hProgressLine, 'Value', currentX, 'Visible', 'on');
        end
        
        if isempty(S.pointDataCell), return; end
        selIdx = get(S.hUI.selFocus, 'Value'); if selIdx == 1, return; end
        actualIdx = selIdx - 1; f = S.allMarkerFrames{actualIdx};
        pTs = f(2); pTe = f(3); pTr = f(4); if strcmp(S.plotXMode, 'Time'), pTs = pTs / S.fps; pTe = pTe / S.fps; pTr = pTr / S.fps; end
        hold(axPoint, 'on');
        S.hLines.Ts = xline(axPoint, pTs, 'g-', 'Ts Pos', 'LineWidth', 1.5, 'ButtonDownFcn', @(h,e) startDraggingLine(h, 'Ts'));
        S.hLines.Te = xline(axPoint, pTe, 'm--', 'Te Pos', 'ButtonDownFcn', @(h,e) startDraggingLine(h, 'Te'));
        S.hLines.Tr = xline(axPoint, pTr, 'r:', 'Trough-Min', 'Visible', get(S.hUI.chkShowTrough,'Value'), 'ButtonDownFcn', @(h,e) startDraggingLine(h, 'Tr'));
        [S.hLines.Ts.Annotation.LegendInformation.IconDisplayStyle, S.hLines.Te.Annotation.LegendInformation.IconDisplayStyle, S.hLines.Tr.Annotation.LegendInformation.IconDisplayStyle] = deal('off');
    end
    function startDraggingLine(hObj, tag)
        if ~strcmp(get(fig,'SelectionType'), 'normal'), return; end
        S.draggingLine = struct('handle', hObj, 'tag', tag); set(hObj, 'LineWidth', 2.5);
    end
    
    function addROI(type)
        if ~S.isLoaded, return; end
        
        useAnchor = get(S.hUI.chkLinkAnchor, 'Value') && S.dynamicAnchor.isCalculated;
        shiftX = 0; shiftY = 0;
        if useAnchor && S.frameIdx <= size(S.dynamicAnchor.localShifts, 1)
            shiftX = S.dynamicAnchor.localShifts(S.frameIdx, 1);
            shiftY = S.dynamicAnchor.localShifts(S.frameIdx, 2);
        end
        
        switch type
            case 'point'
                h = drawpoint(axMain, 'Color', 'g'); if isempty(h) || ~isgraphics(h), return; end
                pos = h.Position; 
                
                basePos = [pos(1) - shiftX, pos(2) - shiftY];
                data = extractTimeProfile('Point', basePos);
                
                pIdx = length(S.pointDataCell) + 1; hold(axMain, 'on');
                S.analysisBaseCoords{pIdx} = struct('type', 'Point', 'coords', basePos);
                
                S.hPointMarkers(end+1) = plot(axMain, pos(1), pos(2), 'go', 'MarkerSize', 8, 'LineWidth', 1.5, 'HitTest', 'off');
                S.hPointTexts(end+1) = text(axMain, pos(1)+5, pos(2)-5, num2str(pIdx), 'Color', 'g', 'FontWeight', 'bold', 'HitTest', 'off');
                
                delete(h);
                processAnalysisData(data, 'Point');
                
            case 'rect_mean'
                h = drawrectangle(axMain, 'Color', 'g', 'FaceAlpha', 0.1); if isempty(h) || ~isgraphics(h), return; end
                pos = h.Position; 
                
                basePos = [pos(1) - shiftX, pos(2) - shiftY, pos(3), pos(4)];
                data = extractTimeProfile('Rect', basePos);
                pIdx = length(S.pointDataCell) + 1; hold(axMain, 'on');
                S.analysisBaseCoords{pIdx} = struct('type', 'Rect', 'coords', basePos);
                
                S.hRectOutlines(end+1) = rectangle(axMain, 'Position', pos, 'EdgeColor', 'g', 'FaceColor', 'none', 'HitTest', 'off');
                S.hPointTexts(end+1) = text(axMain, pos(1), pos(2)-10, ['Area ' num2str(pIdx)], 'Color', 'g', 'FontWeight', 'bold', 'HitTest', 'off');
                
                delete(h);
                processAnalysisData(data, 'Area');
                
            case 'line'
                h = drawline(axMain, 'Color', 'cyan'); if isempty(h) || ~isgraphics(h), return; end
                S.roiLines = h.Position; addlistener(h, 'MovingROI', @(src,ev) updateLineROI(src.Position)); addlistener(h, 'ROIMoved', @(src,ev) updateLineROI(src.Position));
                tGroup.SelectedTab = tabLine; updateFrame(S.frameIdx);
                
            case 'box_select'
                if isempty(S.pointDataCell), return; end
                syncFPS(true);
                tGroup.SelectedTab = tabPoint;
                hBox = drawrectangle(axPoint, 'Color', [0.5 0.5 0.5], 'FaceAlpha', 0.1);
                if isempty(hBox.Position) || length(hBox.Position) < 3, if isgraphics(hBox), delete(hBox); end; return; end
                set(hBox, 'InteractionsAllowed', 'none'); try set(hBox, 'HitTest', 'off'); catch; end
                p1 = hBox.Position(1); p3 = hBox.Position(3);
                if strcmp(S.plotXMode, 'Time'), f1 = round(p1 * S.fps); f2 = round((p1+p3) * S.fps); else, f1 = round(p1); f2 = round(p1+p3); end
                S.currentROI = [max(1,f1), min(S.N,f2)]; S.hBoxObj = hBox; S.selectMode = true; S.selectedIndices = []; title(axPoint, 'Select lines to analyze...', 'Color', [0.8 0.4 0]);
        end
    end
    function updateLineROI(newPos), S.roiLines = newPos; updateFrame(S.frameIdx); end
    function onPlayToggle(src, ~)
        if get(src, 'Value'), set(src, 'String', '| Pause'); start(S.playTimer); else, set(src, 'String', '> Play'); stop(S.playTimer); end
    end
    function exportToCSV(~,~)
        syncFPS(true);
        choice = questdlg('Select Data to Export:', 'Export CSV', 'Thermal Cycles (Points/Areas)', 'Current Line Profile', 'Cancel', 'Thermal Cycles (Points/Areas)');
        switch choice
            case 'Thermal Cycles (Points/Areas)'
                if isempty(S.pointDataCell), errordlg('No thermal cycle data available.'); return; end
                numCurves = length(S.pointDataCell); listStr = cell(1, numCurves); for i = 1:numCurves, listStr{i} = sprintf('ID %d', i); end
                [indx, tf] = listdlg('ListString', listStr, 'SelectionMode', 'multiple', 'Name', 'Select Curves', 'PromptString', 'Select curves to export:');
                if ~tf, return; end
                Frames = (1:S.N)'; Time = Frames / S.fps; T = table(Frames, Time, 'VariableNames', {'Frame', 'Time_s'});
                for k = 1:length(indx), id = indx(k); data = S.pointDataCell{id}; varName = sprintf('Temp_ID%d', id); T.(varName) = data; end
                [f, p] = uiputfile('thermal_cycles.csv'); if f, writetable(T, fullfile(p,f)); end
            case 'Current Line Profile'
                if isempty(S.roiLines), errordlg('No line ROI defined.'); return; end
                imgData = getProcessedFrame(S.frameIdx); [~,~,c] = improfile(imgData, S.roiLines(:,1), S.roiLines(:,2));
                p1 = S.roiLines(1,:); p2 = S.roiLines(2,:); len = sqrt(sum((p2-p1).^2)); unit = 'Px'; if S.area.isCalibrated, len = len / S.area.pxPerMm; unit = 'mm'; end
                distAxis = linspace(0, len, length(c))'; T = table(distAxis, c, 'VariableNames', {['Distance_' unit], 'Temperature'});
                [f, p] = uiputfile('line_profile.csv'); if f, writetable(T, fullfile(p,f)); end
            case 'Cancel', return;
        end
    end
    function clearROIs(~,~)
        delete(findall(axMain, 'Type', 'images.roi.Point')); delete(findall(axMain, 'Type', 'images.roi.Rectangle')); delete(findall(axMain, 'Type', 'images.roi.Line'));
        if ~isempty(S.hPointMarkers), delete(S.hPointMarkers(isgraphics(S.hPointMarkers))); end
        if ~isempty(S.hPointTexts), delete(S.hPointTexts(isgraphics(S.hPointTexts))); end
        if ~isempty(S.hRectOutlines), delete(S.hRectOutlines(isgraphics(S.hRectOutlines))); end
        delete(findall(axMain, 'Tag', 'AnalysisOverlay'));
        
        if ~isempty(S.hProgressLine) && isgraphics(S.hProgressLine), delete(S.hProgressLine); S.hProgressLine=[]; end
        if ~isempty(S.hProgressLineArea) && isgraphics(S.hProgressLineArea), delete(S.hProgressLineArea); S.hProgressLineArea=[]; end
        if ~isempty(S.hProgressLineH) && isgraphics(S.hProgressLineH), delete(S.hProgressLineH); S.hProgressLineH=[]; end
        if ~isempty(S.hProgressLineL) && isgraphics(S.hProgressLineL), delete(S.hProgressLineL); S.hProgressLineL=[]; end
        
        delete(findall(axMain, 'Type', 'Text')); S.pointDataCell = {}; S.allMarkerFrames = {}; 
        S.analysisBaseCoords = {}; S.roiLines = [];
        S.hPointMarkers = []; S.hPointTexts = []; S.hRectOutlines = [];
        set(S.hUI.selFocus, 'String', {' '}, 'Value', 1); cla(axPoint); cla(axLine); set(S.hUI.resBox, 'String', ''); title(axPoint, 'Cleared'); drawnow;
    end
    function shiftFrame(st), n=S.frameIdx+st; if n>=1&&n<=S.N, set(S.hUI.sld, 'Value', n); updateFrame(n); end; end
    function updateVisuals(~,~), updateFrame(S.frameIdx); end
    
    %% --- [v8.76] NDT Assessment Core Functions (A2 FREE ANCHOR MODE) ---
    
    function handleLineDoubleClick(~, evt, hFig)
        if strcmp(evt.SelectionType, 'double')
            uiresume(hFig);
        end
    end
    
    function onSetBaseline(~, ~)
        if ~S.isLoaded, return; end
        msgbox('Draw a line along the global reference plane (e.g., substrate). Serves as origin for Layer 1.', 'Set Baseline');
        h = drawline(axMain, 'Color', 'm', 'LineWidth', 2);
        if isempty(h) || ~isgraphics(h), return; end
        
        title(axMain, '[Adjust] Drag endpoints freely. Double-click to confirm!', 'Color', 'm', 'FontWeight', 'bold');
        
        L = addlistener(h, 'ROIClicked', @(src, evt) handleLineDoubleClick(src, evt, fig));
        uiwait(fig);
        
        if ~isgraphics(h)
            return;
        end
        
        S.ndt.baselinePos = h.Position;
        delete(L);
        
        delete(findall(axMain, 'Tag', 'BaselineLine'));
        h.Tag = 'BaselineLine';
        h.InteractionsAllowed = 'none'; 
        
        set(S.hUI.lblBaselineStatus, 'String', 'Status: Baseline Set', 'ForegroundColor', [0 .6 0]);
        title(axMain, 'Baseline registered successfully!', 'Color', 'g');
    end

    function onGenerateNDTReport(~, ~)
        if ~S.isLoaded
            errordlg('Error: Load a valid .MAT video dataset first.', 'NDT Module Error'); 
            return; 
        end
        syncFPS(true);
        
        isDehazeOn = S.vapor.enabled;
        isStabOn = get(S.hUI.chkStabApply, 'Value') && S.stab.enabled;
        
        if ~isDehazeOn && ~isStabOn
            warndlg(' Warning: “De-haze”or“stabilization” algorithms are inactive. Raw and Processed data will be identical, rendering comparison physically meaningless.', 'NDT Pre-flight Warning');
        end
        
        if strcmp(S.playTimer.Running, 'on')
            stop(S.playTimer);
            set(S.hUI.btnPlay, 'String', '> Play', 'Value', 0);
        end
        updateFrame(1); 
        
        msgbox('Step 1/3: Draw target ROI around the high-temperature region (e.g., melt pool track).', 'NDT Spatial Anchor');
        hT = imrect(axMain); posTarget = wait(hT);
        if isempty(posTarget), if isgraphics(hT), delete(hT); end; return; end
        delete(hT);
        
        msgbox('Step 2/3: Draw background ROI on a uniform cold region far from heat source.', 'NDT Spatial Anchor');
        hB = imrect(axMain); posBg = wait(hB);
        if isempty(posBg), if isgraphics(hB), delete(hB); end; return; end
        delete(hB);
        
        uiwait(msgbox('Step 3/3: Click on a fixed feature edge (e.g., substrate edge) to track baseline drift. (Click “OK”to close this dialog）', 'NDT Temporal Anchor', 'modal'));
        axes(axMain); 
        [pt_x, pt_y] = ginput(1);
        if isempty(pt_x), return; end
        
        function out = safeCrop(im, r)
            [H, W] = size(im);
            x1 = max(1, round(r(1))); y1 = max(1, round(r(2)));
            x2 = min(W, round(r(1) + r(3))); y2 = min(H, round(r(2) + r(4)));
            if x1 > x2 || y1 > y2, out = 0; else, out = im(y1:y2, x1:x2); end
        end
        hWait = waitbar(0, 'Scanning full life-cycle data for extrema and extracting core metrics...');
        
        [imgH, imgW] = size(getProcessedFrame(1));
        pt_x = max(1, min(imgW, round(pt_x))); pt_y = max(1, min(imgH, round(pt_y)));
        
        T_pt_raw = zeros(S.N, 1); T_pt_proc = zeros(S.N, 1);
        bg_mean_raw = zeros(S.N, 1); bg_mean_proc = zeros(S.N, 1);
        target_max_raw = zeros(S.N, 1); 
        
        try
            for i = 1:S.N
                raw = double(S.matObj.(S.dataName)(:,:,i)); proc = getProcessedFrame(i);
                T_pt_raw(i) = raw(pt_y, pt_x); T_pt_proc(i) = proc(pt_y, pt_x);
                b_raw = safeCrop(raw, posBg); b_proc = safeCrop(proc, posBg);
                bg_mean_raw(i) = mean(b_raw(:), 'omitnan'); bg_mean_proc(i) = mean(b_proc(:), 'omitnan');
                t_raw = safeCrop(raw, posTarget); target_max_raw(i) = max(t_raw(:), [], 'omitnan');
                if mod(i, 20) == 0 && isvalid(hWait), waitbar(i/S.N, hWait); end
            end
            
            [~, peakF] = max(target_max_raw);
            if peakF < 1 || peakF > S.N, peakF = round(S.N/2); end
            
            raw_peak = double(S.matObj.(S.dataName)(:,:,peakF)); proc_peak = getProcessedFrame(peakF);
            t_raw_peak = safeCrop(raw_peak, posTarget); b_raw_peak = safeCrop(raw_peak, posBg);
            t_proc_peak = safeCrop(proc_peak, posTarget); b_proc_peak = safeCrop(proc_peak, posBg);
            
            sensorFloor = str2double(get(S.hUI.efLow, 'String'));
            if isnan(sensorFloor) || sensorFloor < 0, sensorFloor = 500; end
            
            mu_T_raw_peak = mean(t_raw_peak(:), 'omitnan'); mu_B_raw_peak = mean(b_raw_peak(:), 'omitnan');
            mu_T_proc_peak = mean(t_proc_peak(:), 'omitnan'); mu_B_proc_peak = mean(b_proc_peak(:), 'omitnan');
            
            TTC_raw = max(0, mu_T_raw_peak - sensorFloor) / max(1, mu_B_raw_peak - sensorFloor);
            TTC_proc = max(0, mu_T_proc_peak - sensorFloor) / max(1, mu_B_proc_peak - sensorFloor);
            
            [~, maxIdx] = max(t_raw_peak(:)); [r_loc, c_loc] = ind2sub(size(t_raw_peak), maxIdx);
            global_x = max(1, round(posTarget(1)) + c_loc - 1); global_y = max(1, round(posTarget(2)) + r_loc - 1);
            roi_width = max(50, round(posTarget(3))); 
            x_start = max(1, global_x - roi_width); x_end = min(imgW, global_x + roi_width);
            
            line_raw = raw_peak(global_y, x_start:x_end); line_proc = proc_peak(global_y, x_start:x_end);
            dist_axis = (x_start:x_end) - global_x;
            
            Dev_raw = std(bg_mean_raw, 'omitnan'); Dev_proc = std(bg_mean_proc, 'omitnan');
            
        catch ME
            if isvalid(hWait), delete(hWait); end
            errordlg(['NDT data extraction engine error: ' ME.message]); return;
        end
        if isvalid(hWait), delete(hWait); end
        
        figNDT = figure('Name', 'NDT Academic Evaluation Report (Fixed Substrate)', 'NumberTitle', 'off', 'Color', 'w', 'Position', [150 150 1200 800]);
        ax1 = subplot(2,2,1, 'Parent', figNDT); b1 = bar(ax1, [1, 2], [TTC_raw, TTC_proc], 0.5);
        b1.FaceColor = 'flat'; b1.CData(1,:) = [0.85 0.32 0.09]; b1.CData(2,:) = [0.46 0.67 0.18]; 
        set(ax1, 'XTick', [1, 2], 'XTickLabel', {'Raw', 'Processed'}); ylabel(ax1, 'True Thermal Contrast (TTC)'); title(ax1, sprintf('De-haze Power (TTC) at Peak Frame %d', peakF)); grid(ax1, 'on');
        
        ax2 = subplot(2,2,2, 'Parent', figNDT); plot(ax2, dist_axis, line_raw, 'Color', [0.85 0.32 0.09], 'LineWidth', 1.5, 'DisplayName', 'Raw Profile'); hold(ax2, 'on');
        plot(ax2, dist_axis, line_proc, 'Color', [0.46 0.67 0.18], 'LineWidth', 1.5, 'DisplayName', 'Processed Profile');
        xlabel(ax2, 'Distance from Heat Center (pixels)'); ylabel(ax2, 'Temperature (\circC)'); title(ax2, 'Core-Centered Transverse Profile'); legend(ax2, 'Location', 'best'); grid(ax2, 'on');
        
        ax3 = subplot(2,2,3, 'Parent', figNDT); timeAxis = (1:S.N) / S.fps; plot(ax3, timeAxis, T_pt_raw, 'Color', [0.85 0.32 0.09, 0.6], 'LineWidth', 1.5, 'DisplayName', 'Raw Fixed Point'); hold(ax3, 'on');
        plot(ax3, timeAxis, T_pt_proc, 'Color', [0.46 0.67 0.18], 'LineWidth', 1.5, 'DisplayName', 'Vapor-Compensated Point');
        xlabel(ax3, 'Time (s)'); ylabel(ax3, 'Temperature (\circC)'); title(ax3, 'Temporal Thermal Cycles (True Physics Tracking)'); legend(ax3, 'Location', 'best'); grid(ax3, 'on');
        
        ax4 = subplot(2,2,4, 'Parent', figNDT); b4 = bar(ax4, [1, 2], [Dev_raw, Dev_proc], 0.5);
        b4.FaceColor = 'flat'; b4.CData(1,:) = [0.85 0.32 0.09]; b4.CData(2,:) = [0.46 0.67 0.18];
        set(ax4, 'XTick', [1, 2], 'XTickLabel', {'Raw', 'Processed'}); ylabel(ax4, 'Baseline Deviation (\sigma_{BG})'); title(ax4, 'Temporal Baseline Stability (Lower Means No Vapor Drift)'); grid(ax4, 'on');
        
        msgbox('High-resolution quantitative charts generated.', 'Report Ready');
    end

    function z_span = getMeltPoolZ(img, Tm, morphK)
        max_val = max(img(:));
        if isempty(max_val) || isnan(max_val) || max_val == 0
            z_span = 0; return; 
        end
        actual_Tm = Tm;
        if max_val < (Tm + 10), actual_Tm = max_val * 0.9; end
        bw = img >= actual_Tm;
        if morphK > 0, bw = imopen(bw, strel('disk', morphK)); end
        
        CC = bwconncomp(bw);
        if CC.NumObjects > 0
            numPixels = cellfun(@numel, CC.PixelIdxList);
            [~, maxIdx] = max(numPixels); 
            [r, ~] = ind2sub(size(img), CC.PixelIdxList{maxIdx});
            z_span = max(r) - min(r) + 1;
        else
            z_span = 0;
        end
    end
    
    function onExtractZDepth(~, ~)
        if ~S.isLoaded, errordlg('Please load data first.'); return; end
        syncFPS(true);
        if ~S.area.isCalibrated
            userChoice = questdlg('Spatial scale not calibrated (Pixels/mm). Z-depth in pixel units. Continue?', ...
                'Calibration Missing', 'Continue (Pixels)', 'Cancel', 'Continue (Pixels)');
            if strcmp(userChoice, 'Cancel'), return; end
        end
        
        T_m = readPositiveScalar(S.hUI.efAreaMP, S.area.T_melt, 'Melt Pool Threshold', true);
        
        hWait = waitbar(0, 'Extracting dynamic Z-axis melt penetration...');
        z_raw = zeros(S.N, 1); z_proc = zeros(S.N, 1);
        
        try
            for i = 1:S.N
                raw = double(S.matObj.(S.dataName)(:,:,i));
                proc = getProcessedFrame(i);
                z_raw(i) = getMeltPoolZ(raw, T_m, S.area.morphKernel);
                z_proc(i) = getMeltPoolZ(proc, T_m, S.area.morphKernel);
                if mod(i, 20) == 0 && isvalid(hWait), waitbar(i/S.N, hWait); end
            end
        catch ME
            if isvalid(hWait), delete(hWait); end
            errordlg(['Z-depth extraction failed: ' ME.message]); return;
        end
        if isvalid(hWait), delete(hWait); end
        
        if get(S.hUI.chkZStartupFilter, 'Value')
            startupN = round(str2double(get(S.hUI.efZStartupN, 'String')));
            if isnan(startupN) || startupN < 0, startupN = 50; set(S.hUI.efZStartupN, 'String', '50'); end
            limitPx = str2double(get(S.hUI.efZLimit, 'String'));
            if isnan(limitPx) || limitPx <= 0, limitPx = 50; set(S.hUI.efZLimit, 'String', '50'); end
            actualN = min(startupN, S.N);
            if actualN > 0
                head_raw = z_raw(1:actualN); head_proc = z_proc(1:actualN);
                head_raw(head_raw > limitPx) = NaN; head_proc(head_proc > limitPx) = NaN;
                z_raw(1:actualN) = head_raw; z_proc(1:actualN) = head_proc;
                try
                    z_raw = fillmissing(z_raw, 'next'); z_raw = fillmissing(z_raw, 'nearest'); 
                    z_proc = fillmissing(z_proc, 'next'); z_proc = fillmissing(z_proc, 'nearest'); 
                catch 
                end
            end
        end
        
        yUnit = 'Pixels';
        if S.area.isCalibrated, z_raw = z_raw / S.area.pxPerMm; z_proc = z_proc / S.area.pxPerMm; yUnit = 'mm'; end
        
        timeAxis = (1:S.N)' / S.fps;
        figZ = figure('Name', 'Dynamic Z-Depth Tracking', 'NumberTitle', 'off', 'Color', 'w', 'Position', [200 200 800 400]);
        axZ = axes('Parent', figZ);
        plot(axZ, timeAxis, z_raw, 'Color', [0.85 0.32 0.09, 0.6], 'LineWidth', 1, 'DisplayName', 'Raw Apparent Z-Depth (Auto)');
        hold(axZ, 'on');
        plot(axZ, timeAxis, z_proc, 'Color', [0.46 0.67 0.18], 'LineWidth', 1.5, 'DisplayName', 'Processed True Z-Depth');
        xlabel(axZ, 'Time (s)'); ylabel(axZ, sprintf('Maximum Melt Pool Z-Span (%s)', yUnit));
        title(axZ, 'Phase 3: Dynamic Z-Depth Correction (Targeted Startup Filtering)'); 
        legend(axZ, 'Location', 'best'); grid(axZ, 'on');
    end
    
    function onGtCellEdit(~, ev)
        r = ev.Indices(1); c = ev.Indices(2); 
        S.ndt.gtTable{r, c} = ev.NewData;
    end
    
    function onGtCellSelect(~, ev)
        if ~isempty(ev.Indices)
            S.ndt.selectedRow = ev.Indices(1, 1);
        end
    end
    
    function onAddGTRow(~, ~)
        newID = size(S.ndt.gtTable, 1) + 1; 
        S.ndt.gtTable(end+1, :) = {newID, NaN, NaN, NaN}; 
        S.ndt.layerLinesRaw{end+1} = [];
        S.ndt.layerLinesProc{end+1} = [];
        set(S.hUI.tblGT, 'Data', S.ndt.gtTable);
    end
    
    function onDelGTRow(~, ~)
        if ~isempty(S.ndt.gtTable)
            if isempty(S.ndt.selectedRow) || S.ndt.selectedRow > size(S.ndt.gtTable, 1)
                delIdx = size(S.ndt.gtTable, 1); 
            else
                delIdx = S.ndt.selectedRow;
            end
            S.ndt.gtTable(delIdx, :) = [];
            S.ndt.layerLinesRaw(delIdx) = [];
            S.ndt.layerLinesProc(delIdx) = [];
            
            for i = 1:size(S.ndt.gtTable, 1)
                S.ndt.gtTable{i, 1} = i;
            end
            set(S.hUI.tblGT, 'Data', S.ndt.gtTable);
            S.ndt.selectedRow = []; 
        end
    end
    
    function onDrawSectionLine(~, ~)
        if ~S.isLoaded, errordlg('Please load data first.'); return; end
        
        if isempty(S.ndt.baselinePos)
            errordlg('No origin! Draw global baseline in Step 0 first.', 'No Baseline'); return;
        end
        
        if isempty(S.ndt.selectedRow)
            errordlg('Error: Select target layer in Phase 4 table first!', 'No Target Selected'); return;
        end
        
        if ~S.area.isCalibrated
            warndlg(' Spatial scale not calibrated! Pixel values cannot align with metallurgical truth (mm).', 'Scale Not Calibrated');
        end
        
        r = S.ndt.selectedRow;
        vMode = S.viewMode;
        
        if strcmp(S.playTimer.Running, 'on')
            stop(S.playTimer);
            set(S.hUI.btnPlay, 'String', '> Play', 'Value', 0);
        end
        
        hLine = drawline(axMain, 'Color', 'y', 'LineWidth', 1.5);
        if isempty(hLine) || ~isgraphics(hLine), return; end
        
        title(axMain, '[Adjust] Drag endpoints freely. Double-click yellow line to confirm!', 'Color', 'y', 'FontWeight', 'bold');
        evtListener = addlistener(hLine, 'ROIClicked', @(src, evt) handleLineDoubleClick(src, evt, fig));
        
        uiwait(fig); 
        
        if ~isgraphics(hLine)
            return; 
        end
        
        drawnPos = hLine.Position;
        
        delete(evtListener);
        delete(hLine);
        plot(axMain, [drawnPos(1,1) drawnPos(2,1)], [drawnPos(1,2) drawnPos(2,2)], 'y--', 'LineWidth', 1.5, 'Tag', 'TempLayerLine');
        
        if strcmp(vMode, 'RAW')
            S.ndt.layerLinesRaw{r} = drawnPos;
        else
            S.ndt.layerLinesProc{r} = drawnPos;
        end
        
        refLine = [];
        if r == 1
            refLine = S.ndt.baselinePos;
        else
            if strcmp(vMode, 'RAW')
                refLine = S.ndt.layerLinesRaw{r-1};
            else
                refLine = S.ndt.layerLinesProc{r-1};
            end
            
            if isempty(refLine)
                ansW = questdlg(sprintf('Layer %d %s section line not yet drawn!\nNet height cannot be computed. Use global baseline as temporary reference?', r-1, vMode), ...
                    'Missing Reference', 'Use Global Baseline', 'Cancel Mapping', 'Use Global Baseline');
                if strcmp(ansW, 'Cancel Mapping')
                    return;
                else
                    refLine = S.ndt.baselinePos;
                end
            end
        end
        
        midX = (drawnPos(1,1) + drawnPos(2,1)) / 2;
        midY = (drawnPos(1,2) + drawnPos(2,2)) / 2;
        
        x1 = refLine(1,1); y1 = refLine(1,2);
        x2 = refLine(2,1); y2 = refLine(2,2);
        dx = x2 - x1; dy = y2 - y1;
        
        L = sqrt(dx^2 + dy^2);
        if L == 0
            distPx = 0;
        else
            distPx = abs(dx * (y1 - midY) - dy * (x1 - midX)) / L;
        end
        
        scale = 1.0; 
        if S.area.isCalibrated, scale = 1.0 / S.area.pxPerMm; end
        distReal = distPx * scale;
        
        if strcmp(vMode, 'RAW')
            S.ndt.gtTable{r, 3} = distReal;
        else
            S.ndt.gtTable{r, 4} = distReal;
        end
        set(S.hUI.tblGT, 'Data', S.ndt.gtTable);
        
        title(axMain, sprintf('[Layer %d %s Mapped] | Net Height: %.2f | Advance slider to continue...', r, vMode, distReal), 'Color', [1 0.6 0]);
    end
    
    function onPlotParity(~, ~)
        currentUIData = get(S.hUI.tblGT, 'Data');
        numRows = size(currentUIData, 1); 
        if numRows == 0, return; end
        
        gt_arr = zeros(numRows, 1); raw_arr = zeros(numRows, 1); proc_arr = zeros(numRows, 1);
        valid_idx = false(numRows, 1);
        for i = 1:numRows
            gt_val = currentUIData{i, 2}; rw_val = currentUIData{i, 3}; pr_val = currentUIData{i, 4};
            if isnumeric(gt_val) && isnumeric(rw_val) && isnumeric(pr_val) && ~isnan(gt_val) && ~isnan(rw_val) && ~isnan(pr_val)
                gt_arr(i) = gt_val; raw_arr(i) = rw_val; proc_arr(i) = pr_val; valid_idx(i) = true;
            end
        end
        gt_arr = gt_arr(valid_idx); raw_arr = raw_arr(valid_idx); proc_arr = proc_arr(valid_idx);
        layer_nums = find(valid_idx);  
        
        if isempty(gt_arr), errordlg('No valid paired data (all three columns required) for plotting.'); return; end
        
        figP = figure('Name', 'Layer Thickness Analysis', 'NumberTitle', 'off', 'Color', 'w', 'Position', [300 200 800 600]);
        axP = axes('Parent', figP); hold(axP, 'on');
        
        scatter(axP, layer_nums, gt_arr, 80, [0.2 0.5 0.8], 'o', 'filled', 'MarkerEdgeColor', 'k', 'DisplayName', 'True Z (Metallurgy)');
        scatter(axP, layer_nums, raw_arr, 80, [0.85 0.32 0.09], 'x', 'LineWidth', 2, 'DisplayName', 'Raw Z (Manual Extraction)');
        scatter(axP, layer_nums, proc_arr, 80, [0.46 0.67 0.18], 'o', 'filled', 'MarkerEdgeColor', 'k', 'DisplayName', 'Proc Z (Manual Extraction)');
        
        if length(layer_nums) >= 2
            p_gt = polyfit(layer_nums, gt_arr, 1);
            p_raw = polyfit(layer_nums, raw_arr, 1);
            p_proc = polyfit(layer_nums, proc_arr, 1);
            
            x_fit = linspace(min(layer_nums), max(layer_nums), 100);
            plot(axP, x_fit, polyval(p_gt, x_fit), 'b--', 'LineWidth', 1.5, 'DisplayName', sprintf('True Z Fit (y=%.2fx+%.2f)', p_gt(1), p_gt(2)));
            plot(axP, x_fit, polyval(p_raw, x_fit), 'Color', [0.85 0.32 0.09], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', sprintf('Raw Z Fit (y=%.2fx+%.2f)', p_raw(1), p_raw(2)));
            plot(axP, x_fit, polyval(p_proc, x_fit), 'Color', [0.46 0.67 0.18], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', sprintf('Proc Z Fit (y=%.2fx+%.2f)', p_proc(1), p_proc(2)));
            
            ss_res_raw = sum((raw_arr - gt_arr).^2);  
            ss_tot_gt = sum((gt_arr - mean(gt_arr)).^2);  
            if ss_tot_gt > 0, r2_raw = 1 - ss_res_raw/ss_tot_gt; else, r2_raw = NaN; end
            rmse_raw = sqrt(mean((raw_arr - gt_arr).^2));  
            
            ss_res_proc = sum((proc_arr - gt_arr).^2);  
            if ss_tot_gt > 0, r2_proc = 1 - ss_res_proc/ss_tot_gt; else, r2_proc = NaN; end
            rmse_proc = sqrt(mean((proc_arr - gt_arr).^2));  
            
            title(axP, sprintf('Layer Thickness Correlation | Raw vs True: R²=%.4f, RMSE=%.4f | Proc vs True: R²=%.4f, RMSE=%.4f', r2_raw, rmse_raw, r2_proc, rmse_proc), 'FontWeight', 'bold');
        else
            title(axP, 'Layer Thickness (Requires >= 2 layers for R-Squared curve fitting)', 'FontWeight', 'bold');
        end
        
        xlabel(axP, 'Layer Number', 'FontWeight', 'bold');
        ylabel(axP, 'Layer Thickness (mm)', 'FontWeight', 'bold');
        legend(axP, 'Location', 'best'); grid(axP, 'on');
    end
end