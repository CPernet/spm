function DCM = spm_dcm_erp(DCM)   
% Estimate parameters of a DCM model (Newton's methods)
% FORMAT DCM = spm_dcm_erp(DCM)   
%
% DCM     
%    name: name string
%       Lpos:  Source locations
%       xY:    data   [1x1 struct]
%       xU:    design [1x1 struct]
%
%   Sname: cell of source name strings
%       A: {[nr x nr double]  [nr x nr double]  [nr x nr double]}
%       B: {[nr x nr double], ...}   Connection constraints
%       C: [nr x 1 double]
%
%   options.trials       - indices of trials
%   options.Lpos         - source location priors
%   options.Tdcm         - [start end] time window in ms
%   options.D            - time bin decimation       (usually 1 or 2)
%   options.h            - number of DCT drift terms (usually 1 or 2)
%   options.Nmodes       - number of spatial models to invert
%   options.model        - 'ERP', 'SEP' or 'NMM'
%   options.onset        - stimulus onset (ms)
%   options.type         - 'ECD' or 'Imaging'
%__________________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging
 
% Karl Friston
% $Id: spm_dcm_erp.m 1582 2008-05-08 18:03:54Z stefan $
 
% check options 
%==========================================================================
clear spm_erp_L
 
% Filename and options
%--------------------------------------------------------------------------
try, DCM.name;                   catch, DCM.name  = 'DCM_ERP'; end
try, h     = DCM.options.h;      catch, h         = 1;         end
try, Nm    = DCM.options.Nmodes; catch, Nm        = 8;         end
try, onset = DCM.options.onset;  catch, onset     = 60;        end
try, model = DCM.options.model;  catch, model     = 'ERP';     end
try, lock  = DCM.options.lock;   catch, lock      = 0;         end
 
 
 
% Data and spatial model (use h only for de-trending data)
%==========================================================================
DCM    = spm_dcm_erp_data(DCM,h);
DCM    = spm_dcm_erp_dipfit(DCM);
xY     = DCM.xY;
xU     = DCM.xU;
M      = DCM.M;
 
% dimensions
%--------------------------------------------------------------------------
Nt     = length(xY.xy);                 % number of trials
Nr     = size(DCM.C,1);                 % number of sources
Nu     = size(DCM.C,2);                 % number of exogenous inputs
Ns     = size(xY.xy{1},1);              % number of time bins
Nc     = size(xY.xy{1},2);              % number of channels
Nx     = size(xU.X,2);                  % number of trial-specific effects
 
% check the number of modes is greater or equal to the number of sources
%--------------------------------------------------------------------------
Nm     = max(Nm,Nr);
 
% confounds - DCT: (force a parameter per channel = activity under x = 0)
%--------------------------------------------------------------------------
% X0     = spm_dctmtx(Ns,1);
if h == 0
    X0 = zeros(Ns, h);
else
    X0     = spm_dctmtx(Ns, h);
end
T0     = speye(Ns) - X0*inv(X0'*X0)*X0';
xY.X0  = X0;
 
% Serial correlations (precision components) AR(1/4) model
%--------------------------------------------------------------------------
xY.Q   = {spm_Q(1/4,Ns,1)};
 
 
%-Inputs
%==========================================================================
 
% between-trial effects
%--------------------------------------------------------------------------
try
    if size(xU.X,2) - length(DCM.B)
        warndlg({'please ensure number of trial specific effects', ...
                 'encoded by DCM.xU.X & DCM.B are the same'})
    end
catch
    DCM.B = {};
end
 
% within-trial effects: adjust onset relative to PST
%--------------------------------------------------------------------------
M.ons  = onset - xY.pst(1);
xU.dt  = xY.dt;
 
 
%-Model specification and nonlinear system identification
%==========================================================================
try, M = rmfield(M,'g'); end
 
switch lower(model)
    
    % linear David et al model (linear in states)
    %======================================================================
    case{'erp'}
 
        % prior moments on parameters
        %------------------------------------------------------------------
        [pE,gE,pC,gC] = spm_erp_priors(DCM.A,DCM.B,DCM.C,M.dipfit);
 
        % inital states and equations of motion
        %------------------------------------------------------------------
        M.x  =  spm_x_erp(pE);
        M.f  = 'spm_fx_erp';
        M.G  = 'spm_lx_erp';
 
   % linear David et al model (linear in states), can employ symmetrypriors
   %=======================================================================
    case{'erpsymm'}
 
        % prior moments on parameters
        %------------------------------------------------------------------
        [pE,gE,pC,gC] = spm_erpsymm_priors(DCM.A,DCM.B,DCM.C,M.dipfit,M.pC,M.gC);
 
        % inital states and equations of motion
        %-------------------------------------------------------------------
        M.x  =  spm_x_erp(pE);
        M.f  = 'spm_fx_erp';
        M.G  = 'spm_lx_erp';
 
 
    % linear David et al model (linear in states) - fast version for SEPs
    %======================================================================
    case{'sep'}
 
        % prior moments on parameters
        %------------------------------------------------------------------
        [pE,gE,pC,gC] = spm_sep_priors(DCM.A,DCM.B,DCM.C,M.dipfit);
 
        % inital states
        %------------------------------------------------------------------
        M.x  = spm_x_erp(pE);
        M.f  = 'spm_fx_erp';
        M.G  = 'spm_lx_sep';
        
    % Neural mass model (nonlinear in states)
    %======================================================================
    case{'nmm'}
 
        % prior moments on parameters
        %------------------------------------------------------------------
        [pE,gE,pC,gC] = spm_nmm_priors(DCM.A,DCM.B,DCM.C,M.dipfit);
 
        % inital states
        %------------------------------------------------------------------
        [x N] = spm_x_nmm(pE);
        M.x   = x;
        M.GE  = N.GE;
        M.GI  = N.GI;
        M.Cx  = N.Cx;
        M.f   = 'spm_fx_mfm';
        M.G   = 'spm_lx_erp';
        
            % Neural mass model (nonlinear in states)
    %======================================================================
    case{'mfm'}
 
        % prior moments on parameters
        %------------------------------------------------------------------
        [pE,gE,pC,gC] = spm_nmm_priors(DCM.A,DCM.B,DCM.C,M.dipfit);
 
        % inital states
        %------------------------------------------------------------------
        [x N] = spm_x_mfm(pE);
        M.x   = x;
        M.GE  = N.GE;
        M.GI  = N.GI;
        M.f   = 'spm_fx_mfm';
        M.G   = 'spm_lx_erp'; 
        
        
    otherwise
        warndlg('Unknown model')
end
 
% lock experimental effects by introducing prior correlations
%--------------------------------------------------------------------------
if lock
    pV    = spm_unvec(diag(pC),pE);
    for i = 1:Nx
       pB      = pV;
       pB.B{i} = pB.B{i} - pB.B{i};
       pB      = spm_vec(pV)  - spm_vec(pB);
       pB      = sqrt(pB*pB') - diag(pB);
       pC      = pC + pB;
    end
end
 
 
% likelihood model
%--------------------------------------------------------------------------
M.FS  = 'spm_fy_erp';
M.IS  = 'spm_gen_erp';
M.pE  = pE;
M.pC  = pC;
M.gE  = gE;
M.gC  = gC;
M.m   = Nu;
M.n   = length(spm_vec(M.x));
M.l   = Nc;
M.ns  = Ns;
 
%-Feature selection using principal components (U) of lead-field
%==========================================================================
 
% Spatial modes
%--------------------------------------------------------------------------
if ~isfield(M, 'E')
    dGdg  = spm_diff(M.G,gE,M,1);
    L     = spm_cat(dGdg);
    U     = spm_svd(L*L',exp(-8));
    try
        U = U(:,1:Nm);
    end
    Nm    = size(U,2);
    M.E   = U;
else
    U = M.E;
end
 
% EM: inversion
%==========================================================================
[Qp,Qg,Cp,Cg,Ce,F] = spm_nlsi_N(M,xU,xY);
 
 
% Bayesian inference {threshold = prior; for A,B  and C this is exp(0) = 1)
%--------------------------------------------------------------------------
warning('off','SPM:negativeVariance');
dp  = spm_vec(Qp) - spm_vec(pE);
Pp  = spm_unvec(1 - spm_Ncdf(0,abs(dp),diag(Cp)),Qp);
warning('on','SPM:negativeVariance');
 
% neuronal and sensor responses (x and y)
%==========================================================================

% expansion point for states
%--------------------------------------------------------------------------
L   = feval(M.G, Qg,M);                 % get gain matrix
x   = feval(M.IS,Qp,M,xU);              % prediction (source space)
 
% trial-specific responses (in mode, channel and source space)
%--------------------------------------------------------------------------
for i = 1:Nt
    y{i}  = T0*x{i}*L'*M.E;             % prediction (sensor space)
    r{i}  = T0*(xY.y{i}*M.E - y{i});    % residuals  (sensor space)
    x{i}  = x{i}(:,find(any(L)));       % sources contributing to y
end
 
 
% store estimates in DCM
%--------------------------------------------------------------------------
DCM.M  = M;                    % model specification
DCM.xY = xY;                   % data structure
DCM.xU = xU;                   % input structure
DCM.Ep = Qp;                   % conditional expectation f(x,u,p)
DCM.Cp = Cp;                   % conditional covariances G(g)
DCM.Eg = Qg;                   % conditional expectation
DCM.Cg = Cg;                   % conditional covariances
DCM.Pp = Pp;                   % conditional probability
DCM.H  = y;                    % conditional responses (y), projected space
DCM.K  = x;                    % conditional responses (x)
DCM.R  = r;                    % conditional residuals (y)
DCM.F  = F;                    % Laplace log evidence
 
DCM.options.h      = h;
DCM.options.Nmodes = Nm;
DCM.options.onset  = onset;
DCM.options.model  = model;
DCM.options.lock   = lock;
 
% store estimates in D
%--------------------------------------------------------------------------
if strcmp(M.dipfit.type,'Imaging')
    
    % Assess accuracy; signal to noise (over sources), SSE and log-evidence
    %----------------------------------------------------------------------
    for i = 1:Nt
        SSR(i) = sum(var(r{i}));
        SST(i) = sum(var(y{i} + r{i}));
    end
    R2    = 100*(sum(SST - SSR))/sum(SST);
    
    
    % reconstruct sources in dipole space
    %----------------------------------------------------------------------
    Nd    = M.dipfit.Nd;
    G     = sparse(Nd,0);
    
    % one dipole per subpopulation (p)
    %----------------------------------------------------------------------
    if iscell(Qg.L)
        for p = 1:length(Qg.L)
            for i = 1:Nr
                G(M.dipfit.Ip{i},end + 1) = M.dipfit.U{i}*Qg.L{p}(:,i);
            end
        end

    % one dipole per source (i)
    %----------------------------------------------------------------------
    else
        for i = 1:Nr
            G(M.dipfit.Ip{i},end + 1) = M.dipfit.U{i}*Qg.L(:,i);
        end
        G = kron(Qg.J,G);
    end
    Is    = find(any(G,2));
    Ix    = find(any(G,1));
    G     = G(Is,Ix);
    for i = 1:Nt
        J{i} = G*x{i}';
    end

    % get dipole space lead field
    %----------------------------------------------------------------------
    L     = load(M.dipfit.gainmat);
    name  = fieldnames(L);
    L     = sparse(getfield(L, name{1}));
    L     = spm_cond_units(L);
    L     = U'*L(:,Is);
    
    % reduced data (for each trial
    %----------------------------------------------------------------------
    for i = 1:Nt
        Y{i} = U'*xY.y{i}'*T0;
    end
 
    inverse.trials = DCM.options.trials;   % trial or condition
    inverse.type   = 'DCM';                % inverse model
 
    inverse.J      = J;                    % Conditional expectation
    inverse.L      = L;                    % Lead field (reduced)
    inverse.R      = speye(Nc,Nc);         % Re-referencing matrix
    inverse.T      = T0;                   % temporal subspace
    inverse.U      = U;                    % spatial subspace
    inverse.Is     = Is;                   % Indices of active dipoles
    inverse.It     = DCM.xY.It;            % Indices of time bins
    inverse.Ic     = DCM.xY.Ic;            % Indices of good channels
    inverse.Y      = Y;                    % reduced data
    inverse.Nd     = Nd;                   % number of dipoles
    inverse.Nt     = Nt;                   % number of trials
    inverse.pst    = xY.pst;               % peri-stimulus time
    inverse.F      = DCM.F;                % log-evidence
    inverse.R2     = R2;                   % variance accounted for (%)
    inverse.dipfit = M.dipfit;             % forward model for DCM
 
    % append DCM results and save in structure
    %----------------------------------------------------------------------
    try, val = DCM.val;  catch, val = 1; end
    D        = spm_eeg_load(DCM.xY.Dfile);
    
    D.inv{end + 1}      = D.inv{val};
    D.inv{end}.date     = date;
    D.inv{end}.comment  = {'DCM'};
    D.inv{end}.inverse  = inverse;
    D.val               = length(D.inv);
    try
        D.inv{end}      = rmfield(D.inv{end},'contrast');
    end
    save(D);
end
 
% and save
%--------------------------------------------------------------------------
if spm_matlab_version_chk('7.1') >= 0
    save(DCM.name, '-V6', 'DCM');
else
    save(DCM.name, 'DCM');
end
assignin('base','DCM',DCM)
return
