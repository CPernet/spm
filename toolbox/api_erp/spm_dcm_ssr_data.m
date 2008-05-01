function DCM = spm_dcm_ssr_data(DCM)
% gets cross-spectral density data-features using a VAR model
% FORMAT DCM = spm_dcm_ssr_data(DCM)
% DCM    -  DCM structure
% requires
%
%    DCM.xY.Dfile        - name of data file
%    DCM.M.U             - channel subspace
%    DCM.options.trials  - trial to evaluate
%    DCM.options.Tdcm    - time limits
%    DCM.options.Fdcm    - frequency limits
%    DCM.options.D       - Down-sampling
%
% sets
%
%    DCM.xY.pst     - Peristimulus Time [ms] sampled
%    DCM.xY.dt      - sampling in seconds [s] (down-sampled)
%    DCM.xY.U       - channel subspace
%    DCM.xY.y       - cross spectral density over sources
%    DCM.xY.csd     - cross spectral density over sources
%    DCM.xY.It      - Indices of time bins
%    DCM.xY.Ic      - Indices of good channels
%    DCM.xY.Hz      - Frequency bins
%    DCM.xY.code    - trial codes evaluated
%__________________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging
 
% Karl Friston
% $Id: spm_dcm_ssr_data.m 1536 2008-05-01 18:32:41Z vladimir $
 
% Set defaults and Get D filename
%-------------------------------------------------------------------------
try
    Dfile = DCM.xY.Dfile;
catch
    errordlg('Please specify data and trials');
    error('')
end

% load D
%--------------------------------------------------------------------------
try
    D = spm_eeg_load(Dfile);
catch
    try
        [p,f]        = fileparts(Dfile);
        D            = spm_eeg_load(f);
        DCM.xY.Dfile = fullfile(pwd,f);
    catch
        try
            [f,p]        = uigetfile('*.mat','please select data file');
            name         = fullfile(p,f);
            D            = spm_eeg_load(name);
            DCM.xY.Dfile = fullfile(name);
        catch
            warndlg([Dfile ' could not be found'])
            return
        end
    end
end

 
% indices of EEG channel (excluding bad channels)
%--------------------------------------------------------------------------
if ~isfield(DCM.xY, 'modality')
    DCM.xY.modality = spm_eeg_modality_ui(D);
end

modality = DCM.xY.modality;
channels = D.chanlabels;

if ~isfield(DCM.xY, 'Ic')
    Ic = strmatch(modality, D.chantype);
    Ic = setdiff(Ic, D.badchannels);
    DCM.xY.Ic       = Ic;
end

Ic = DCM.xY.Ic;

Nc        = length(Ic);
Nm        = size(DCM.M.U,2);
DCM.xY.Ic = Ic;

% options
%--------------------------------------------------------------------------
try
    DT    = DCM.options.D;
catch
    DT    = 1;
end
try
    trial = DCM.options.trials;
catch
    trial = D.nconditions;
end
 
% check data are not oversampled (< 4ms)
%--------------------------------------------------------------------------
if DT/D.fsample < 0.004
    DT            = ceil(0.004*D.fsample);
    DCM.options.D = DT;
end
 
 
% get peristimulus times
%--------------------------------------------------------------------------
try
    
    % time window and bins for modelling
    %----------------------------------------------------------------------
    DCM.xY.Time = 1000*D.time; % ms
    T1          = DCM.options.Tdcm(1);
    T2          = DCM.options.Tdcm(2);
    [i, T1]     = min(abs(DCM.xY.Time - T1));
    [i, T2]     = min(abs(DCM.xY.Time - T2));
    % Time [ms] of down-sampled data
    %----------------------------------------------------------------------
    It          = [T1:DT:T2]';               % indices - bins
    DCM.xY.pst  = DCM.xY.Time(It);           % PST
    DCM.xY.It   = It;                        % Indices of time bins
    DCM.xY.dt   = DT/D.fsample;              % sampling in seconds
    Nb          = length(It);                % number of bins
    
catch
    errordlg('Please specify time window');
    error('')
end
 
% get frequency range
%--------------------------------------------------------------------------
try
    Hz1     = DCM.options.Fdcm(1);          % lower frequency
    Hz2     = DCM.options.Fdcm(2);          % upper frequency
catch
    pst     = DCM.xY.pst(end) - DCM.xY.pst(1);
    Hz1     = max(ceil(2*1000/pst),4);
    if Hz1 < 8;
        Hz2 = 48;
    else
        Hz2 = 128;
    end
end

 
% Frequencies
%--------------------------------------------------------------------------
DCM.xY.Hz  = fix(Hz1:Hz2);             % Frequencies
Nf         = length(DCM.xY.Hz);        % number of frequencies
Ne         = length(trial);            % number of ERPs
 
% get induced responses (use previous CSD results if possible) 
%==========================================================================
try
    if size(DCM.xY.csd,2) == Ne;
        if size(DCM.xY.csd{1},1) == Nf;
            if size(DCM.xY.csd{1},2) == Nm;
                DCM.xY.y  = spm_cond_units(DCM.xY.csd);
                return
            end
        end
    end
end
 
% Cross spectral density for each trial type
%==========================================================================
condlabels = unique(D.conditions);
for i = 1:Ne;
   
    % trial indices
    %----------------------------------------------------------------------
    c = D.pickconditions(condlabels{i});
    
    % use only the first 512 trial
    %----------------------------------------------------------------------
    try c = c(1:512); end
    Nt    = length(c);

    
    % Get data
    %----------------------------------------------------------------------
    P     = zeros(Nf,Nm,Nm);
    for j = 1:Nt
        
        fprintf('\nevaluating condition %i (trial %i)',i,j)
        Y   = D(Ic,It,c(j))'*DCM.M.U;
        mar = spm_mar(Y,8);
        mar = spm_mar_spectra(mar,DCM.xY.Hz,1/DCM.xY.dt);
        P   = P + abs(mar.P);
    end
       P   = P/Nt;
  
    % store
    %----------------------------------------------------------------------
    DCM.xY.csd{i} = P;
   
    
end
 
% place cross-spectral density in xY.y
%==========================================================================
DCM.xY.y    =spm_cond_units(DCM.xY.csd); 
DCM.xY.U    = DCM.M.U;
DCM.xY.code = condlabels(trial);