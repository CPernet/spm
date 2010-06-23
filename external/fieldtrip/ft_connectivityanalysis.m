function [stat] = ft_connectivityanalysis(cfg, data)

% FT_CONNECTIVITYANALYIS computes various measures of connectivity
% between MEG/EEG channels or between source-level signals.
%
% Use as
%   stat = ft_connectivityanalysis(cfg, data)
%   stat = ft_connectivityanalysis(cfg, timelock)
%   stat = ft_connectivityanalysis(cfg, freq)
%   stat = ft_connectivityanalysis(cfg, source)
% where the first input argument is a configuration structure (see
% below) and the second argument is the output of FT_PREPROCESSING,
% FT_TIMELOCKANLAYSIS or FT_FREQANALYSIS or FT_MVARANALYSIS or
% FT_SOURCEANALYSIS, depending on the connectivity metric that you
% want to compute.
%
% The configuration structure has to contain
%   cfg.method  = 'coh',       coherence, support for freq, freqmvar and
%                               source data. For partial coherence also
%                               specify cfg.partchannel
%                 'csd',       cross-spectral density matrix, can also
%                 calculate partial csds - 
%                               if cfg.partchannel is specified 
%                 'plv',       phase-locking value, support for freq and freqmvar data
%                 'corr',      correlation coefficient (Pearson)
%                 'xcorr',     cross correlation function
%                 'powcorr',   power correlation, support for freq and source data
%                 'amplcorr',  amplitude correlation, support for freq and source data
%                 'dtf',       directed transfer function, support for freq and freqmvar data
%                 'pdc',       partial directed coherence, support for freq and freqmvar data
%                 'granger',   granger causality, support for freq and freqmvar data
%                 'psi',       phaseslope index, support for freq and freqmvar data
%                 'pcd',       pairwise circular difference
%                 'di',        directionality index

% Copyright (C) 2009, Robert Oostenveld, Jan-Mathijs Schoffelen, Andre Bastos
%
% This file is part of FieldTrip, see http://www.ru.nl/neuroimaging/fieldtrip
% for the documentation and details.
%
%    FieldTrip is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    FieldTrip is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with FieldTrip. If not, see <http://www.gnu.org/licenses/>.
%
% $Id: ft_connectivityanalysis.m 1250 2010-06-18 09:29:44Z jansch $

fieldtripdefs

% check if the input cfg is valid for this function
cfg = checkconfig(cfg, 'trackconfig', 'on');

% set the defaults

%FIXME do method specific calls to checkconfig
if ~isfield(cfg, 'feedback'),   cfg.feedback   = 'none'; end
if ~isfield(cfg, 'channel'),    cfg.channel    = 'all'; end
if ~isfield(cfg, 'channelcmb'), cfg.channelcmb = {'all' 'all'};    end
if ~isfield(cfg, 'refindx'),    cfg.refindx    = [];    end
if ~isfield(cfg, 'trials'),     cfg.trials     = 'all'; end
if ~isfield(cfg, 'complex'),    cfg.complex    = 'abs'; end
if ~isfield(cfg, 'jackknife'),  cfg.jackknife  = 'no';  end
if ~isfield(cfg, 'removemean'), cfg.removemean = 'yes'; end
if ~isfield(cfg, 'partchannel'), cfg.partchannel = '';  end
if ~isfield(cfg, 'conditional'), cfg.conditional = [];  end
if ~isfield(cfg, 'blockindx'),   cfg.blockindx   = {};  end

hasjack = (isfield(data, 'method') && strcmp(data.method, 'jackknife')) || (isfield(data, 'dimord') && strcmp(data.dimord(1:6), 'rptjck'));
hasrpt  = (isfield(data, 'dimord') && ~isempty(strfind(data.dimord, 'rpt'))) || (isfield(data, 'avg') && isfield(data.avg, 'mom')); %FIXME old-fashioned pcc data
dojack  = strcmp(cfg.jackknife, 'yes');
normrpt = 0; % default, has to be overruled e.g. in plv, because of single replicate normalisation
normpow = 1; % default, has to be overruled e.g. in csd, 

% FIXME check which methods require hasrpt

% ensure that the input data is appropriate for the method
switch cfg.method
case {'coh' 'csd'}
    if ~isempty(cfg.partchannel)
        if hasrpt && ~hasjack, 
          error('partialisation on single trial observations is not supported'); 
        end
        try,
            data    = checkdata(data, 'datatype', {'freqmvar' 'freq'}, 'cmbrepresentation', 'full');
            inparam = 'crsspctrm';      
        catch
            error('partial coherence/csd is only supported for input allowing for a all-to-all csd representation');
        end
    else
        data    = checkdata(data, 'datatype', {'freqmvar' 'freq' 'source'});
        inparam = 'crsspctrm';  
    end
    
    if strcmp(cfg.method, 'csd'),
        normpow     = 0;
        warning('cfg.complex for requested csd is set to %s, do you really want this?', cfg.complex);
    end
    
    dtype   = datatype(data);
    switch dtype
    case 'source'
        if isempty(cfg.refindx), error('indices of reference voxels need to be specified'); end
        % if numel(cfg.refindx)>1, error('more than one reference voxel is not yet supported'); end
    otherwise
    end
    % FIXME think of accommodating partial coherence for source data with only a few references

case {'plv'}
    data    = checkdata(data, 'datatype', {'freqmvar' 'freq'});
    inparam = 'crsspctrm';  
    normrpt = 1;
case {'corr' 'xcorr'}
    data = checkdata(data, 'datatype', 'raw');
case {'amplcorr' 'powcorr'}
    data    = checkdata(data, 'datatype', {'freqmvar' 'freq' 'source'});
    dtype   = datatype(data);
    switch dtype
    case {'freq' 'freqmvar'}
        inparam = 'powcovspctrm';
    case 'source'
        inparam = 'powcov';
        if isempty(cfg.refindx), error('indices of reference voxels need to be specified'); end
        % if numel(cfg.refindx)>1, error('more than one reference voxel is not yet supported'); end
    otherwise
    end
case {'granger'}
    data    = checkdata(data, 'datatype', {'mvar' 'freqmvar' 'freq'});
    inparam = 'transfer';
    % FIXME could also work with time domain data
case {'instantaneous_causality'}
    data    = checkdata(data, 'datatype', {'mvar' 'freqmvar' 'freq'});
    inparam = 'transfer';  
case {'total_interdependence'}
    data    = checkdata(data, 'datatype', {'freqmvar' 'freq'});
    inparam = 'crsspctrm';            
case {'dtf' 'pdc'}
    data    = checkdata(data, 'datatype', {'freqmvar' 'freq'});
    inparam = 'transfer';
case {'psi'}
  if ~isfield(cfg, 'normalize'),  cfg.normalize  = 'no';  end
  data    = checkdata(data, 'datatype', {'freqmvar' 'freq'});
  inparam = 'crsspctrm';
case {'di'}
    %wat eigenlijk?
otherwise
    error('unknown method %s', cfg.method);
end
dtype = datatype(data);

% ensure that source data �is in 'new' representation
if strcmp(dtype, 'source'), 
  data = checkdata(data, 'sourcerepresentation', 'new'); 
end

% FIXME throw an error if cfg.complex~='abs', and dojack==1
% FIXME throw an error if no replicates and cfg.method='plv'
% FIXME trial selection has to be implemented still

if isfield(data, 'label'), 
    cfg.channel     = ft_channelselection(cfg.channel, data.label);
    if ~isempty(cfg.partchannel)
        cfg.partchannel = ft_channelselection(cfg.partchannel, data.label);
    end     
end

if isfield(data, 'label') && ~isempty(cfg.channelcmb),
    cfg.channelcmb = ft_channelcombination(cfg.channelcmb, cfg.channel, 1); 
end

% check whether the required inparam is present in the data
if ~isfield(data, inparam) || (~strcmp(dtype, 'freqmvar') && strcmp(inparam, 'crsspctrm') && isfield(data, 'crsspctrm')),
    switch dtype
    case 'freq'
        if strcmp(inparam, 'crsspctrm') 
            if isfield(data, 'fourierspctrm')
                [data, powindx, hasrpt] = univariate2bivariate(data, 'fourierspctrm', 'crsspctrm', dtype, 0, cfg.channelcmb);
            elseif strcmp(inparam, 'crsspctrm') && isfield(data, 'powspctrm')
                % if input data is old-fashioned, i.e. contains powandcsd
                [data, powindx, hasrpt] = univariate2bivariate(data, 'powandcsd', 'crsspctrm', dtype, 0, cfg.channelcmb);
            else
                powindx = labelcmb2indx(data.labelcmb);
            end
        elseif strcmp(inparam, 'powcovspctrm')
            if isfield(data, 'powspctrm'),
                [data, powindx] = univariate2bivariate(data, 'powspctrm', 'powcovspctrm', dtype, strcmp(cfg.removemean,'yes'), cfg.channelcmb, strcmp(cfg.method,'amplcorr'));    
            elseif isfield(data, 'fourierspctrm'),
                [data, powindx] = univariate2bivariate(data, 'fourierspctrm', 'powcovspctrm', dtype, strcmp(cfg.removemean,'yes'), cfg.channelcmb, strcmp(cfg.method,'amplcorr'));    
            end
        end
    case 'source'
        if strcmp(inparam, 'crsspctrm')
            [data, powindx, hasrpt] = univariate2bivariate(data, 'mom', 'crsspctrm', dtype, 0, cfg.refindx, [], 0);
            %[data, powindx, hasrpt] = univariate2bivariate(data, 'fourierspctrm', 'crsspctrm', dtype, 0, cfg.refindx, [], 1);
        elseif strcmp(inparam, 'powcov')
            data            = checkdata(data, 'haspow', 'yes');
            [data, powindx] = univariate2bivariate(data, 'pow', 'powcov', dtype, strcmp(cfg.removemean,'yes'), cfg.refindx, strcmp(cfg.method,'amplcorr'), 0); 
        end
    otherwise
    end
      
else 
    powindx = [];
end

% do some additional work if single trial normalisation is required
if normrpt && hasrpt,
    if strcmp(inparam, 'crsspctrm'),
        tmp  = getfield(data, inparam);
        nrpt = size(tmp,1);
        progress('init', cfg.feedback, 'normalising...');
        for k = 1:nrpt
            progress(k/nrpt, 'normalising amplitude of replicate %d from %d to 1\n', k, nrpt);
            tmp(k,:,:,:,:) = tmp(k,:,:,:,:)./abs(tmp(k,:,:,:,:));
        end
        progress('close');
        data = setfield(data, inparam, tmp);
    end
end

if ~isempty(cfg.partchannel)
    allchannel = ft_channelselection(cfg.channel, data.label);
    pchanindx  = match_str(allchannel,cfg.partchannel);
    kchanindx  = setdiff(1:numel(allchannel), pchanindx);
    keepchn    = allchannel(kchanindx);

    cfg.pchanindx   = pchanindx;
    cfg.allchanindx = kchanindx;
    partstr = '';
    for k = 1:numel(cfg.partchannel)
      partstr = [partstr,'-',cfg.partchannel{k}];
    end
    for k = 1:numel(keepchn)
      keepchn{k} = [keepchn{k},'\',partstr(2:end)];
    end
    data.label      = keepchn; % update labels to remove the partialed channels
    % FIXME consider keeping track of which channels have been partialised      
else
    cfg.pchanindx   = [];
    cfg.allchanindx = [];
end

% check if jackknife is required
if hasrpt && dojack && hasjack,
    % do nothing
elseif hasrpt && dojack,
    % compute leave-one-outs
    data    = selectdata(data, 'jackknife', 'yes');
    hasjack = 1;
elseif hasrpt 
    data   = selectdata(data, 'avgoverrpt', 'yes');
    hasrpt = 0;
else
  % nothing required
end

% compute the desired connectivity metric
switch cfg.method
case {'coh'}
  
  tmpcfg             = [];
  tmpcfg.complex     = cfg.complex;
  tmpcfg.feedback    = cfg.feedback;
  tmpcfg.dimord      = data.dimord;
  tmpcfg.powindx     = powindx;
  tmpcfg.pownorm     = normpow;  
  tmpcfg.pchanindx   = cfg.pchanindx;
  tmpcfg.allchanindx = cfg.allchanindx; 
  
  [datout, varout, nrpt] = coupling_corr(tmpcfg, data.(inparam), hasrpt, hasjack);
  outparam = 'cohspctrm';

case {'csd'}
  
  tmpcfg             = [];
  tmpcfg.complex     = cfg.complex;
  tmpcfg.feedback    = cfg.feedback;
  tmpcfg.dimord      = data.dimord;
  tmpcfg.powindx     = powindx;
  tmpcfg.pownorm     = normpow;  
  tmpcfg.pchanindx   = cfg.pchanindx;
  tmpcfg.allchanindx = cfg.allchanindx; 
  
  [datout, varout, nrpt] = coupling_corr(tmpcfg, data.(inparam), hasrpt, hasjack);
  outparam = 'crsspctrm';
 
case 'plv'
  %phase locking value

  tmpcfg           = [];
  tmpcfg.complex   = cfg.complex;
  tmpcfg.feedback  = cfg.feedback;
  tmpcfg.dimord    = data.dimord;
  tmpcfg.powindx   = powindx;
  tmpcfg.pownorm     = normpow;  
  tmpcfg.pchanindx   = cfg.pchanindx;
  tmpcfg.allchanindx = cfg.allchanindx; 
  [datout, varout, nrpt] = coupling_corr(tmpcfg, data.(inparam), hasrpt, hasjack);
  outparam         = 'plvspctrm';

case 'corr'
  % pearson's correlation coefficient
case 'xcorr'
  % cross-correlation function
case 'spearman'
  % spearman's rank correlation
case 'amplcorr'
  % amplitude correlation

  tmpcfg          = [];
  tmpcfg.feedback = cfg.feedback;
  tmpcfg.dimord   = data.dimord;
  tmpcfg.complex  = 'real';
  tmpcfg.powindx  = powindx;
  tmpcfg.pownorm  = 1;
  tmpcfg.pchanindx = [];
  [datout, varout, nrpt] = coupling_corr(tmpcfg, data.(inparam), hasrpt, hasjack);
  outparam        = 'amplcorrspctrm';   

case 'powcorr'
  % power correlation

  tmpcfg          = [];
  tmpcfg.feedback = cfg.feedback;
  tmpcfg.dimord   = data.dimord;
  tmpcfg.complex  = 'real';
  tmpcfg.powindx  = powindx;
  [datout, varout, nrpt] = coupling_corr(tmpcfg, data.(inparam), hasrpt, hasjack);
  outparam        = 'powcorrspctrm';   

case 'granger'
  % granger causality

  if sum(datatype(data, {'freq' 'freqmvar'})),
    hasrpt = ~isempty(strfind(data.dimord, 'rpt'));
    if hasrpt,
      nrpt = size(data.transfer,1);
    else
      nrpt = 1;
      siz  = size(data.transfer);
      data.transfer = reshape(data.transfer, [1 siz]);
      siz  = size(data.noisecov);
      data.noisecov = reshape(data.noisecov, [1 siz]);
      siz  = size(data.crsspctrm);
      data.crsspctrm = reshape(data.crsspctrm, [1 siz]);
    end

    if isfield(data, 'labelcmb') && isempty(cfg.conditional),
      % multiple pairwise non-parametric transfer functions
      % linearly indexed
      powindx = labelcmb2indx(data.labelcmb);
    elseif isfield(data, 'labelcmb')
      % conditional (blockwise) needs linearly represented cross-spectra 
      for k = 1:size(cfg.conditional,1)
        tmp{k,1} = cfg.conditional(k,:);
        tmp{k,2} = cfg.conditional(k,[1 3]);
      end
      [cmbindx, n] = blockindx2cmbindx(data.labelcmb, cfg.blockindx, tmp);
      powindx.cmbindx = cmbindx;
      powindx.n       = n;
    elseif isfield(cfg, 'block') && ~isempty(cfg.block)
      % blockwise granger
      powindx = cfg.block;
      for k = 1:2
        newlabel{k,1} = cat(2,powindx{k});
      end      
      data.label = newlabel;
    else
      % do nothing
    end
    %fs = cfg.fsample; %FIXME do we really need this, or is this related to how
    %noisecov is defined and normalised?
    fs = 1;
    [datout, varout, n] = coupling_granger(data.transfer, data.noisecov, data.crsspctrm, fs, hasjack, powindx);
    outparam = 'grangerspctrm';
  else
    error('granger for time domain data is not yet implemented');
  end

case 'instantaneous_causality'
  % instantaneous coupling between the series, requires the same elements as granger
 if sum(datatype(data, {'freq' 'freqmvar'})),
    hasrpt = ~isempty(strfind(data.dimord, 'rpt'));
    if hasrpt,
      nrpt = size(data.transfer,1);
    else
      nrpt = 1;
      siz  = size(data.transfer);
      data.transfer = reshape(data.transfer, [1 siz]);
      siz  = size(data.noisecov);
      data.noisecov = reshape(data.noisecov, [1 siz]);
      siz  = size(data.crsspctrm);
      data.crsspctrm = reshape(data.crsspctrm, [1 siz]);
    end

    if isfield(data, 'labelcmb'),
      % multiple pairwise non-parametric transfer functions
      % linearly indexed
      powindx = labelcmb2indx(data.labelcmb);
    elseif isfield(cfg, 'block') && ~isempty(cfg.block)
      % blockwise granger
      powindx = cfg.block;
      for k = 1:2
        newlabel{k,1} = cat(2,powindx{k});
      end      
      data.label = newlabel;
    else
      % do nothing
    end
    %fs = cfg.fsample; %FIXME do we really need this, or is this related to how
    %noisecov is defined and normalised?
    fs = 1;
    [datout, varout, n] = coupling_instantaneous(data.transfer, data.noisecov, data.crsspctrm, fs, hasjack, powindx);
    outparam = 'instantspctrm';
  else
    error('instantaneous causality for time domain data is not yet implemented');
  end

case 'total_interdependence'
  %total interdependence  

  tmpcfg           = [];
  tmpcfg.complex   = cfg.complex;
  tmpcfg.feedback  = cfg.feedback;
  tmpcfg.dimord    = data.dimord;
  tmpcfg.powindx   = powindx;
  tmpcfg.pownorm   = normpow;
  tmpcfg.pchanindx = cfg.pchanindx;
  tmpcfg.allchanindx = cfg.allchanindx;
  [datout, varout, nrpt] = coupling_toti(tmpcfg, data.(inparam), hasrpt, hasjack);
  outparam         = 'totispctrm';    

case 'dtf'
  % directed transfer function
  if isfield(data, 'labelcmb'), 
    powindx = labelcmb2indx(data.labelcmb);
  else
    powindx = [];
  end  

  tmpcfg          = [];
  tmpcfg.feedback = cfg.feedback;
  tmpcfg.powindx  = powindx;
  
  hasrpt = ~isempty(strfind(data.dimord, 'rpt'));
  if hasrpt,
    nrpt  = size(data.(inparam),1);
    datin = data.(inparam);
  else
    nrpt  = 1; 
    datin = reshape(data.(inparam), [1 size(data.(inparam))]);
  end
  [datout, varout, n] = coupling_dtf(tmpcfg, datin, hasjack);
  outparam = 'dtfspctrm';

case 'pdc' 
  % partial directed coherence
  if isfield(data, 'labelcmb'), 
    powindx = labelcmb2indx(data.labelcmb);
  else
    powindx = [];
  end  

  tmpcfg          = [];
  tmpcfg.feedback = cfg.feedback;
  tmpcfg.powindx  = powindx;
  
  hasrpt = ~isempty(strfind(data.dimord, 'rpt'));
  if hasrpt,
    nrpt  = size(data.(inparam),1);
    datin = data.(inparam);
  else
    nrpt  = 1;
    datin = reshape(data.(inparam), [1 size(data.(inparam))]);
  end
  
  [datout, varout, n] = coupling_pdc(tmpcfg, datin, hasjack);
  outparam = 'pdcspctrm';

case 'pcd'
  % pairwise circular distance
case 'psi'
  % phase slope index
  
  tmpcfg           = [];
  tmpcfg.feedback  = cfg.feedback;
  tmpcfg.dimord    = data.dimord;
  tmpcfg.powindx   = powindx;
  tmpcfg.pownorm   = normpow;
  tmpcfg.pchanindx = cfg.pchanindx;
  tmpcfg.allchanindx = cfg.allchanindx;
  tmpcfg.nbin      = nearest(data.freq, data.freq(1)+cfg.bandwidth)-1;
  tmpcfg.normalize = cfg.normalize;
  [datout, varout, nrpt] = coupling_psi(tmpcfg, data.(inparam), hasrpt, hasjack);
  outparam         = 'psispctrm';

case 'di'
  % directionality index
otherwise
  error('unknown method %s', cfg.method);
end

%remove the auto combinations if necessary
if ~isempty(powindx),
  switch dtype
  case {'freq' 'freqmvar'}
    if isfield(data, 'labelcmb') && ~isstruct(powindx),
      keepchn = powindx(:,1) ~= powindx(:,2);
      datout  = datout(keepchn,:,:,:,:);
      if ~isempty(varout),
        varout = varout(keepchn,:,:,:,:);
      end
      data.labelcmb = data.labelcmb(keepchn,:);
    end
  case 'source'
    nvox    = size(unique(data.pos(:,1:3),'rows'),1);
    ncmb    = size(data.pos,1)/nvox-1;
    remove  = (powindx(:,1) == powindx(:,2)) & ([1:size(powindx,1)]' > nvox*ncmb);
    keepchn = ~remove;
    
    datout = datout(keepchn,:,:,:,:);
    if ~isempty(varout),
      varout = varout(keepchn,:,:,:,:);
    end
    inside = logical(zeros(1,size(data.pos,1)));
    inside(data.inside) = true;
    inside = inside(keepchn);
    data.inside  = find(inside)';
    data.outside = find(inside==0)';
    data.pos     = data.pos(keepchn,:);
  end
end

%create output structure
switch dtype
case {'freq' 'freqmvar'},
  stat        = [];
  if isfield(data, 'label'),
    stat.label  = data.label;
  end
  if isfield(data, 'labelcmb'),
    stat.labelcmb = data.labelcmb;
  end
  stat.dimord = data.dimord; %FIXME adjust dimord (remove rpt in dojack && hasrpt case)
  stat        = setfield(stat, outparam, datout);
  if ~isempty(varout),
    stat   = setfield(stat, [outparam,'sem'], (varout/nrpt).^0.5);
  end
case 'source'
  stat         = [];
  stat.pos     = data.pos;
  stat.dim     = data.dim;
  stat.inside  = data.inside;
  stat.outside = data.outside;
  stat         = setfield(stat, outparam, datout);
  if ~isempty(varout),
    stat = setfield(stat, [outparam,'sem'], (varout/nrpt).^0.5);
  end
end

if isfield(data, 'freq'), stat.freq = data.freq; end
if isfield(data, 'frequency'), stat.frequency = data.frequency; end
if isfield(data, 'time'), stat.time = data.time; end
if isfield(data, 'grad'), stat.grad = data.grad; end
if isfield(data, 'elec'), stat.elec = data.elec; end
if exist('nrpt', 'var'),  stat.dof  = nrpt;      end
%FIXME this is not correct for TF-representations when trials have 
%different lengths

% get the output cfg
cfg = checkconfig(cfg, 'trackconfig', 'off', 'checksize', 'yes');

% add version information to the configuration
try
  % get the full name of the function
  cfg.version.name = mfilename('fullpath');
catch
  % required for compatibility with Matlab versions prior to release 13 (6.5)
  [st, i] = dbstack;
  cfg.version.name = st(i);
end
cfg.version.id = '$Id: ft_connectivityanalysis.m 1250 2010-06-18 09:29:44Z jansch $';
% remember the configuration details of the input data
try, cfg.previous = data.cfg; end
% remember the exact configuration details in the output 
stat.cfg = cfg;

%--------------------------------------------------------------
function [c, v, n] = coupling_corr(cfg, input, hasrpt, hasjack)

% takes in a square csd or cov matrix, calculates the partialised
% csd, or partialised cov, if specified, then either normalizes by power (in
% the case of coherence) or returns the partialized csd (if the goal is to
% calculate partial granger, for example.

if nargin==2,
  hasrpt   = 0;
  hasjack  = 0;
elseif nargin==3,
  hasjack  = 0;
end

siz = size(input);
if ~hasrpt,
siz   = [1 siz];
input = reshape(input, siz);
end

% do partialisation if necessary
if ~isempty(cfg.pchanindx),
    % partial spectra are computed as in Rosenberg JR et al (1998) J.
    % Neuroscience Methods, equation 38 

    chan   = cfg.allchanindx;
    nchan  = numel(chan);
    pchan  = cfg.pchanindx;
    npchan = numel(pchan);
    newsiz = siz;
    newsiz(2:3) = numel(chan); % size of partialised csd

    A  = zeros(newsiz);

    % FIXME this only works for data without time dimension
    if numel(siz)>4, error('this only works for data without time'); end
    for j = 1:siz(1) %rpt loop
        AA = reshape(input(j, chan,  chan, : ), [nchan  nchan  siz(4:end)]);
        AB = reshape(input(j, chan,  pchan,: ), [nchan  npchan siz(4:end)]);
        BA = reshape(input(j, pchan, chan, : ), [npchan nchan  siz(4:end)]);
        BB = reshape(input(j, pchan, pchan, :), [npchan npchan siz(4:end)]);
        for k = 1:siz(4) %freq loop
            A(j,:,:,k) = AA(:,:,k) - AB(:,:,k)*pinv(BB(:,:,k))*BA(:,:,k); 
        end
    end
    input = A;
    siz = size(input);
else
    % do nothing
end
    
if (length(strfind(cfg.dimord, 'chan'))~=2 || length(strfind(cfg.dimord, 'pos'))>0) && isfield(cfg, 'powindx') && ~isempty(cfg.powindx),
  %crossterms are not described with chan_chan_therest, but are linearly indexed
  outsum = zeros(siz(2:end));
  outssq = zeros(siz(2:end));

  progress('init', cfg.feedback, 'computing metric...');
  for j = 1:siz(1)
    progress(j/siz(1), 'computing metric for replicate %d from %d\n', j, siz(1));
    if cfg.pownorm 
        p1    = reshape(input(j,cfg.powindx(:,1),:,:,:), siz(2:end));
        p2    = reshape(input(j,cfg.powindx(:,2),:,:,:), siz(2:end));
        denom = sqrt(p1.*p2); clear p1 p2
    else
        denom = 1;
    end
    outsum = outsum + complexeval(reshape(input(j,:,:,:,:), siz(2:end))./denom, cfg.complex);
    outssq = outssq + complexeval(reshape(input(j,:,:,:,:), siz(2:end))./denom, cfg.complex).^2;
  end
  progress('close');  

elseif length(strfind(cfg.dimord, 'chan'))==2 || length(strfind(cfg.dimord, 'pos'))==2,
  %crossterms are described by chan_chan_therest 

  outsum = zeros(siz(2:end));
  outssq = zeros(siz(2:end));
  progress('init', cfg.feedback, 'computing metric...');
  for j = 1:siz(1)
    progress(j/siz(1), 'computing metric for replicate %d from %d\n', j, siz(1));
    if cfg.pownorm 
        p1  = zeros([siz(2) 1 siz(4:end)]);
        p2  = zeros([1 siz(3) siz(4:end)]);
        for k = 1:siz(2)
            p1(k,1,:,:,:,:) = input(j,k,k,:,:,:,:);
            p2(1,k,:,:,:,:) = input(j,k,k,:,:,:,:);
        end
        p1    = p1(:,ones(1,siz(3)),:,:,:,:);
        p2    = p2(ones(1,siz(2)),:,:,:,:,:);
        denom = sqrt(p1.*p2); clear p1 p2;
    else
        denom = 1;
    end
    outsum = outsum + complexeval(reshape(input(j,:,:,:,:,:,:), siz(2:end))./denom, cfg.complex);
    outssq = outssq + complexeval(reshape(input(j,:,:,:,:,:,:), siz(2:end))./denom, cfg.complex).^2;
  end
  progress('close');

end
n = siz(1);
c = outsum./n;

if hasrpt,
    if hasjack
        bias = (n-1).^2;
    else
        bias = 1;
    end
  
    v = bias*(outssq - (outsum.^2)./n)./(n - 1);
else 
    v = [];
end

%-------------------------------------------------------------
function [c, v, n] = coupling_toti(cfg, input, hasrpt, hasjack)

[c, v, n] = coupling_corr(cfg, input, hasrpt, hasjack);
c = -log(1-c.^2);
v = -log(1-v.^2); %FIXME this is probably not correct

%-------------------------------------------------------------
function [c, v, n] = coupling_psi(cfg, input, hasrpt, hasjack)

if nargin==2,
  hasrpt   = 0;
  hasjack  = 0;
elseif nargin==3,
  hasjack  = 0;
end

if (length(strfind(cfg.dimord, 'chan'))~=2 || length(strfind(cfg.dimord, 'pos'))>0) && isfield(cfg, 'powindx') && ~isempty(cfg.powindx),
  %crossterms are not described with chan_chan_therest, but are linearly indexed
  
  siz = size(input);
  if ~hasrpt,
    siz   = [1 siz];
    input = reshape(input, siz);
  end
  
  outsum = zeros(siz(2:end));
  outssq = zeros(siz(2:end));
  pvec   = [2 setdiff(1:numel(siz),2)];  

  progress('init', cfg.feedback, 'computing metric...');
  %first compute coherency and then phaseslopeindex
  for j = 1:siz(1)
    progress(j/siz(1), 'computing metric for replicate %d from %d\n', j, siz(1));
    c      = reshape(input(j,:,:,:,:), siz(2:end));
    p1     = abs(reshape(input(j,cfg.powindx(:,1),:,:,:), siz(2:end)));
    p2     = abs(reshape(input(j,cfg.powindx(:,2),:,:,:), siz(2:end)));
    
    p      = ipermute(phaseslope(permute(c./sqrt(p1.*p2), pvec), cfg.nbin, cfg.normalize), pvec);
    
    outsum = outsum + p;
    outssq = outssq + p.^2;
    avgcrsspctrm = squeeze(mean(input,1));
    phasediff = unwrap(angle(avgcrsspctrm),[],2);    
  end
  progress('close');  

elseif length(strfind(cfg.dimord, 'chan'))==2 || length(strfind(cfg.dimord, 'pos'))==2,
  %crossterms are described by chan_chan_therest 
 
  siz = size(input);
  if ~hasrpt,
    siz   = [1 siz];
    input = reshape(input, siz);
  end

  outsum = zeros(siz(2:end));
  outssq = zeros(siz(2:end));
  pvec   = [3 setdiff(1:numel(siz),3)];  
  
  progress('init', cfg.feedback, 'computing metric...');
  for j = 1:siz(1)
    progress(j/siz(1), 'computing metric for replicate %d from %d\n', j, siz(1));
    p1  = zeros([siz(2) 1 siz(4:end)]);
    p2  = zeros([1 siz(3) siz(4:end)]);
    for k = 1:siz(2)
      p1(k,1,:,:,:,:) = input(j,k,k,:,:,:,:);
      p2(1,k,:,:,:,:) = input(j,k,k,:,:,:,:);
    end
    c      = reshape(input(j,:,:,:,:,:,:), siz(2:end));
    p1     = p1(:,ones(1,siz(3)),:,:,:,:);
    p2     = p2(ones(1,siz(2)),:,:,:,:,:);
    p      = ipermute(phaseslope(permute(c./sqrt(p1.*p2),pvec),cfg.nbin, cfg.normalize),pvec);
    outsum = outsum + p;
    outssq = outssq + p.^2;
  end
  progress('close');

end

n = siz(1);
c = outsum./n;

if hasrpt,
  if hasjack
    bias = (n-1).^2;
  else
    bias = 1;
  end
  
  v = bias*(outssq - (outsum.^2)./n)./(n - 1);
else 
  v = [];
end

%------------------------------------------------------------
function [pdc, pdcvar, n] = coupling_pdc(cfg, input, hasjack)

if nargin==2,
  hasjack  = 0;
end

%crossterms are described by chan_chan_therest 
siz = size(input);
n   = siz(1);

outsum = zeros(siz(2:end));
outssq = zeros(siz(2:end));

%computing pdc is easiest on the inverse of the transfer function
pdim     = prod(siz(4:end));
tmpinput = reshape(input, [siz(1:3) pdim]);
progress('init', cfg.feedback, 'inverting the transfer function...');
for k = 1:n
  progress(k/n, 'inverting the transfer function for replicate %d from %d\n', k, n);
  tmp = reshape(tmpinput(k,:,:,:), [siz(2:3) pdim]);
  for m = 1:pdim
    tmp(:,:,m) = inv(tmp(:,:,m));
  end
  tmpinput(k,:,:,:) = tmp;
end
progress('close');
input = reshape(tmpinput, siz);

progress('init', cfg.feedback, 'computing metric...');
for j = 1:n
  progress(j/n, 'computing metric for replicate %d from %d\n', j, n);
  invh   = reshape(input(j,:,:,:,:), siz(2:end));
  den    = sum(abs(invh).^2,1);
  tmppdc = abs(invh)./sqrt(repmat(den, [siz(2) 1 1 1 1]));
  %if ~isempty(cfg.submethod), tmppdc = baseline(tmppdc, cfg.submethod, baselineindx); end
  outsum = outsum + tmppdc;
  outssq = outssq + tmppdc.^2;
end
progress('close');

pdc = outsum./n;

if n>1,
  if hasjack
    bias = (n-1).^2;
  else
    bias = 1;
  end
  pdcvar = bias*(outssq - (outsum.^2)./n)./(n - 1);
else 
  pdcvar = [];
end

%------------------------------------------------------------
function [dtf, dtfvar, n] = coupling_dtf(cfg, input, hasjack)

siz    = size(input);
n      = siz(1);
ncmb   = siz(2);
outsum = zeros(siz(2:end));
outssq = zeros(siz(2:end));

if isempty(cfg.powindx)
  % data are represented as chan_chan_therest
  for j = 1:n
    tmph   = reshape(input(j,:,:,:,:), siz(2:end));
    den    = sum(abs(tmph).^2,2);
    tmpdtf = abs(tmph)./sqrt(repmat(den, [1 siz(2) 1 1 1]));
    %if ~isempty(cfg.submethod), tmpdtf = baseline(tmpdtf, cfg.submethod, baselineindx); end
    outsum = outsum + tmpdtf;
    outssq = outssq + tmpdtf.^2;
    %tmp    = outsum; tmp(2,1,:,:) = outsum(1,2,:,:); tmp(1,2,:,:) = outsum(2,1,:,:); outsum = tmp;
    %tmp    = outssq; tmp(2,1,:,:) = outssq(1,2,:,:); tmp(1,2,:,:) = outssq(2,1,:,:); outssq = tmp;
    % swap the order of the cross-terms to achieve the convention such that 
    % labelcmb {'a' 'b'} represents: a->b
  end
else
  % data are linearly indexed
  sortindx = [0 0 0 0];
  for k = 1:ncmb
    iauto1  = find(sum(cfg.powindx==cfg.powindx(k,1),2)==2);
    iauto2  = find(sum(cfg.powindx==cfg.powindx(k,2),2)==2);
    icross1 = k;
    icross2 = find(sum(cfg.powindx==cfg.powindx(ones(ncmb,1)*k,[2 1]),2)==2);
    indx    = [iauto1 icross2 icross1 iauto2];
    
    if isempty(intersect(sortindx, sort(indx), 'rows')),
      sortindx = [sortindx;sort(indx)];     
      for j = 1:n
        tmph    = reshape(input(j,indx,:,:), [2 2 siz(3:end)]); 
        den     = sum(abs(tmph).^2,2);
        tmpdtf  = reshape(abs(tmph)./sqrt(repmat(den, [1 2 1 1])), [4 siz(3:end)]);
        outsum(indx,:) = outsum(indx,:) + tmpdtf([1 3 2 4],:);
        outssq(indx,:) = outssq(indx,:) + tmpdtf([1 3 2 4],:).^2;
        % swap the order of the cross-terms to achieve the convention such that
        % labelcmb {'a' 'b'} represents: a->b
      end
    end
  end
end
dtf = outsum./n;

if n>1, %FIXME this is strictly only true for jackknife, otherwise other bias is needed
  bias   = (n - 1).^2;
  dtfvar = bias.*(outssq - (outsum.^2)/n)./(n-1);
else
  dtfvar = [];
end

%-------------------------------------------------------------------------
function [granger, v, n] = coupling_granger(H, Z, S, fs, hasjack, powindx)

%Usage: causality = hz2causality(H,S,Z,fs);
%Inputs: transfer  = transfer function,
%        crsspctrm = 3-D spectral matrix;
%        noisecov  = noise covariance, 
%        fs        = sampling rate
%Outputs: granger (Granger causality between all channels)
%               : auto-causality spectra are set to zero
% Reference: Brovelli, et. al., PNAS 101, 9849-9854 (2004).
%M. Dhamala, UF, August 2006.

%FIXME speed up code and check
siz = size(H);
if numel(siz)==4,
  siz(5) = 1;
end
n   = siz(1);
Nc  = siz(2);

outsum = zeros(siz(2:end));
outssq = zeros(siz(2:end));

if isempty(powindx),
  % data are chan_chan_therest
  for kk = 1:n
    for ii = 1:Nc
      for jj = 1:Nc
        if ii ~=jj,
          zc     = reshape(Z(kk,jj,jj,:) - Z(kk,ii,jj,:).^2./Z(kk,ii,ii,:),[1 1 1 1 siz(5)]);
          zc     = repmat(zc,[1 1 1 siz(4) 1]);
          numer  = reshape(abs(S(kk,ii,ii,:,:)),[1 1 siz(4:end)]);
          denom  = reshape(abs(S(kk,ii,ii,:,:)-zc.*abs(H(kk,ii,jj,:,:)).^2./fs),[1 1 siz(4:end)]);
          outsum(jj,ii,:,:) = outsum(jj,ii,:,:) + log(numer./denom);
          outssq(jj,ii,:,:) = outssq(jj,ii,:,:) + (log(numer./denom)).^2;
        end
      end
      outsum(ii,ii,:,:) = 0;%self-granger set to zero
    end
  end
elseif ~iscell(powindx) && ~isstruct(powindx)
  % data are linearly indexed
  for k = 1:Nc
    for j = 1:n
      iauto1  = find(sum(powindx==powindx(k,1),2)==2);
      iauto2  = find(sum(powindx==powindx(k,2),2)==2);
      icross1 = k;
      icross2 = find(sum(powindx==powindx(ones(Nc,1)*k,[2 1]),2)==2);
      zc      = Z(j,iauto2,:) - Z(j,icross1,:).^2./Z(j,iauto1,:);
      numer   = abs(S(j,iauto1,:));
      denom   = abs(S(j,iauto1,:)-zc.*abs(H(j,icross1,:)).^2./fs);
      outsum(icross2,:) = outsum(icross2,:) + reshape(log(numer./denom), [1 siz(3:end)]);
      outssq(icross2,:) = outssq(icross2,:) + reshape((log(numer./denom)).^2, [1 siz(3:end)]);
    end
  end
elseif iscell(powindx)
  % blockwise granger
  % H = transfer function nchan x nchan x nfreq
  % Z = noise covariance  nchan x nchan
  % S = crosspectrum      nchan x nchan x nfreq
  % powindx{1} is a list of indices for block1 
  % powindx{2} is a list of indices for block2
 
  %FIXME rewrite to allow for multiple blocks
  %FIXME change cfg.block functionality in this case
  %cfg.blockindx = {{list of channel names} [list of block indices]} 
  block1 = powindx{1}(:);
  block2 = powindx{2}(:);
  
  n     = size(H,1); 
  nchan = size(H,2);
  nfreq = size(H,4);
  
  n1 = numel(block1);
  n2 = numel(block2);
  
  % reorder
  S = S(:,[block1;block2],[block1;block2],:);
  H = H(:,[block1;block2],[block1;block2],:);
  Z = Z(:,[block1;block2],[block1;block2]);
  
  indx1 = 1:n1;
  indx2 = (n1+1):(n1+n2);
 
  outsum = zeros(2,2,nfreq);
  outssq = zeros(2,2,nfreq); 
  for k = 1:n
    tmpZ = reshape(Z(k,:,:), [nchan nchan]);

    % projection matrix for block2 -> block1
    P1 = [eye(n1)                                zeros(n1,n2);
          -tmpZ(indx2,indx1)/tmpZ(indx1,indx1)     eye(n2)];
    
    % projection matrix for block1 -> block2
    P2 = [  eye(n1)    -tmpZ(indx1,indx2)/tmpZ(indx2,indx2);
          zeros(n2,n1) eye(n2)];
    
    % invert only once
    invP1 = inv(P1);
    invP2 = inv(P2);
    for jj = 1:nfreq
      % post multiply transfer matrix with the inverse of the projection matrix  
      % this is equivalent to time domain pre multiplication with P
      Sj = reshape(S(k,:,:,jj), [nchan nchan]);
      Zj = tmpZ(:,:);
      H1 = reshape(H(k,:,:,jj), [nchan nchan])*invP1;
      H2 = reshape(H(k,:,:,jj), [nchan nchan])*invP2;
      num1 = abs(det(Sj(indx1,indx1))); % numerical round off leads to tiny imaginary components
      num2 = abs(det(Sj(indx2,indx2))); % numerical round off leads to tiny imaginary components
      denom1 = abs(det(H1(indx1,indx1)*Zj(indx1,indx1)*H1(indx1,indx1)'));
      denom2 = abs(det(H2(indx2,indx2)*Zj(indx2,indx2)*H2(indx2,indx2)'));
      %rH1 = real(H1(indx1,indx1));
      %rH2 = real(H2(indx2,indx2));
      %iH1 = imag(H1(indx1,indx1));
      %iH2 = imag(H2(indx2,indx2));
      %h1 = rH1*Zj(indx1,indx1)*rH1' + iH1*Zj(indx1,indx1)*iH1';
      %h2 = rH2*Zj(indx2,indx2)*rH2' + iH2*Zj(indx2,indx2)*iH2';
      %denom1 = det(h1);
      %denom2 = det(h2);      

      outsum(2,1,jj) = log( num1./denom1 )    + outsum(2,1,jj);
      outsum(1,2,jj) = log( num2./denom2 )    + outsum(1,2,jj);
      outssq(2,1,jj) = log( num1./denom1 ).^2 + outssq(2,1,jj);
      outssq(1,2,jj) = log( num2./denom2 ).^2 + outssq(1,2,jj);
    end
  end
elseif isstruct(powindx)
  %blockwise conditional
  
  n     = size(H,1);
  ncmb  = size(H,2);
  nfreq = size(H,3);  
  ncnd  = size(powindx.cmbindx,1);
    
  outsum = zeros(ncnd, nfreq);
  outssq = zeros(ncnd, nfreq);
  for k = 1:n
    tmpS = reshape(S, [ncmb nfreq]);
    tmpH = reshape(H, [ncmb nfreq]);
    tmpZ = reshape(Z, [ncmb 1]);
    tmp  = blockwise_conditionalgranger(tmpS,tmpH,tmpZ,powindx.cmbindx,powindx.n);
    
    outsum = outsum + tmp;
    outssq = outssq + tmp.^2;
  end
end

granger = outsum./n;
if n>1,
  if hasjack
    bias = (n-1).^2;
  else
    bias = 1;
  end
  v = bias*(outssq - (outsum.^2)./n)./(n - 1);
else 
  v = [];
end

%----------------------------------------------------------------
function [instc, v, n] = coupling_instantaneous(H, Z, S, fs, hasjack,powindx)

%Usage: causality = hz2causality(H,S,Z,fs);
%Inputs: transfer  = transfer function,
%        crsspctrm = 3-D spectral matrix;
%        noisecov  = noise covariance, 
%        fs        = sampling rate
%Outputs: instantaneous causality spectrum between the channels.
%Total Interdependence = Granger (X->Y) + Granger (Y->X) + Instantaneous Causality
%               : auto-causality spectra are set to zero
% Reference: Brovelli, et. al., PNAS 101, 9849-9854 (2004), Rajagovindan
% and Ding, PLoS One Vol. 3, 11, 1-8 (2008)
%M. Dhamala, UF, August 2006.

%FIXME speed up code and check
siz = size(H);
if numel(siz)==4,
  siz(5) = 1;
end
n   = siz(1);
Nc  = siz(2);

outsum = zeros(siz(2:end));
outssq = zeros(siz(2:end));
if isempty(powindx)
    
%clear S; for k = 1:size(H,3), h = squeeze(H(:,:,k)); S(:,:,k) = h*Z*h'/fs; end;
for kk = 1:n
  for ii = 1:Nc
    for jj = 1:Nc
      if ii ~=jj,
        zc1     = reshape(Z(kk,jj,jj,:) - Z(kk,ii,jj,:).^2./Z(kk,ii,ii,:),[1 1 1 1 siz(5)]);
        zc1     = repmat(zc1,[1 1 1 siz(4) 1]);
        zc2     = reshape(Z(kk,ii,ii,:) - Z(kk,jj,ii,:).^2./Z(kk,jj,jj,:),[1 1 1 1 siz(5)]);
        zc2     = repmat(zc2,[1 1 1 siz(4) 1]);
        CTH1    = reshape(ctranspose(squeeze(H(kk,ii,jj,:,:))),1,1,1,siz(4));
        CTH2    = reshape(ctranspose(squeeze(H(kk,jj,ii,:,:))),1,1,1,siz(4));
        term1   = (S(kk,ii,ii,:,:) - H(kk,ii,jj,:,:).*zc1.*CTH1);
        term2   = (S(kk,jj,jj,:,:) - H(kk,jj,ii,:,:).*zc2.*CTH2);
        Sdet      = (S(kk,ii,ii,:,:).*S(kk,jj,jj,:,:)) - (S(kk,ii,jj,:,:).*S(kk,jj,ii,:,:));
        outsum(jj,ii,:) = outsum(jj,ii) + log((term1.*term2)./Sdet(kk,:,:,:));
        outssq(jj,ii,:) = outssq(jj,ii) + log((term1.*term2)./Sdet(kk,:,:,:)).^2;
      end
    end
    outsum(ii,ii,:,:) = 0;%self-granger set to zero
  end
end
elseif ~iscell(powindx)
 % data are linearly indexed
  for k = 1:Nc
    for j = 1:n 
      iauto1  = find(sum(powindx==powindx(k,1),2)==2);
      iauto2  = find(sum(powindx==powindx(k,2),2)==2);
      icross1 = k;
      icross2 = find(sum(powindx==powindx(ones(Nc,1)*k,[2 1]),2)==2);
      if iauto1 ~= iauto2
          zc1     = Z(j,iauto1) - Z(j,icross2).^2./Z(j,iauto2);
          zc1     = repmat(zc1,[1 1 siz(3)]);
          zc2     = Z(j,iauto2) - Z(j,icross1).^2./Z(j,iauto1);
          zc2     = repmat(zc2,[1 1 siz(3)]);
          CTH1    = reshape(ctranspose(squeeze(H(j,icross2,:))),1,1,siz(3));
          CTH2    = reshape(ctranspose(squeeze(H(j,icross1,:))),1,1,siz(3));
          term1   = (S(j,iauto2,:) - H(j,icross2,:).*zc1.*CTH1);
          term2   = (S(j,iauto1,:) - H(j,icross1,:).*zc2.*CTH2);
          Sdet      = (S(j,iauto2,:).*S(j,iauto1,:)) - (S(j,icross2,:).*S(j,icross1,:));
          outsum(k,:) = outsum(k) + log((term1.*term2)./Sdet(j,:,:));
          outssq(k,:) = outssq(k) + log((term1.*term2)./Sdet(j,:,:)).^2;      
      end
    end
  end

    
end
instc = outsum./n;

if n>1,
  if hasjack
    bias = (n-1).^2;
  else
    bias = 1;
  end
  v = bias*(outssq - (outsum.^2)./n)./(n - 1);
else 
  v = [];
end

%----------------------------------------
function [indx] = labelcmb2indx(labelcmb)

%identify the auto-combinations
ncmb = size(labelcmb,1);
indx = zeros(ncmb,2);

label = unique(labelcmb(:));
nchan = numel(label);
autoindx = zeros(nchan,1);
for k = 1:nchan
  sel1 = strcmp(label{k}, labelcmb(:,1));
  sel2 = strcmp(label{k}, labelcmb(:,2));
  autoindx = find(sel1 & sel2);
  
  indx(sel1,1) = autoindx;
  indx(sel2,2) = autoindx;
end

%----------------------------------
function [c] = complexeval(c, str);

switch str
  case 'complex'
    %do nothing
  case 'abs'
    c = abs(c);
  case 'angle'
    c = angle(c);
  case 'imag'
    c = imag(c);
  case 'real'
    c = real(c);
otherwise
  error('cfg.complex = ''%s'' not supported', cfg.complex);
end

%---------------------------------------
function [y] = phaseslope(x, n, norm)

m   = size(x, 1); %total number of frequency bins
y   = zeros(size(x));
x(1:end-1,:,:,:,:) = conj(x(1:end-1,:,:,:,:)).*x(2:end,:,:,:,:);

if strcmp(norm, 'yes')
  coh = zeros(size(x));
  coh(1:end-1,:,:,:,:) = (abs(x(1:end-1,:,:,:,:)) .* abs(x(2:end,:,:,:,:))) + 1;
  %FIXME why the +1? get the coherence 
  for k = 1:m
    begindx = max(1,k-n);
    endindx = min(m,k+n);
    y(k,:,:,:,:) = imag(sum(x(begindx:endindx,:,:,:,:)./coh(begindx:endindx,:,:,:,:)));
  end    
else
  for k = 1:m
    begindx = max(1,k-n);
    endindx = min(m,k+n);
    y(k,:,:,:,:) = imag(sum(x(begindx:endindx,:,:,:,:)));
  end
end

%------------------------------------------------------------------------------------------------------------------
function [data, powindx, hasrpt] = univariate2bivariate(data, inparam, outparam, dtype, demeanflag, cmb, sqrtflag, keeprpt)

if nargin<8, keeprpt    = 1;  end
if nargin<7, sqrtflag   = 0;  end
if nargin<6, cmb        = []; end
if nargin<5, demeanflag = 0;  end

switch dtype
case 'freq'
  ncmb  = size(cmb,1);
  nchan = numel(data.label);  
  getpowindx = 0;
  if ncmb==0,
    error('no channel combinations are specified');
  elseif ncmb==nchan.^2 || ncmb==(nchan+1)*nchan*0.5,
    dofull = 1;
  else
    dofull = 0;
  end
  
  if strcmp(inparam, 'fourierspctrm') && strcmp(outparam, 'crsspctrm'),
    %fourier coefficients -> cross-spectral density
    if dofull 
      data    = checkdata(data, 'cmbrepresentation', 'full');
    else
      data    = checkdata(data, 'cmbrepresentation', 'sparse', 'channelcmb', cmb);
    end
  elseif strcmp(inparam, 'powandcsd') && strcmp(outparam, 'crsspctrm'),
    if ~isempty(cmb),
      data    = checkdata(data, 'cmbrepresentation', 'sparse', 'channelcmb', cmb);
      
      %ensure getting powindx later on to prevent crash
      getpowindx = 1; 
    else
      %data    = checkdata(data, 'cmbrepresentation', 'full');
      %this should not be possible
      error('cannot convert to a full csd representation');
    
    
    end
  elseif strcmp(inparam, 'fourierspctrm') && strcmp(outparam, 'powcovspctrm'),
    %fourier coefficients -> power covariance
    data = checkdata(data, 'cmbrepresentation', 'sparsewithpow', 'channelcmb', {});

    if sqrtflag, data.powspctrm = sqrt(data.powspctrm); end 
 
    %get covariance by using checkdata
    if demeanflag,
      nrpt = size(data.powspctrm,1);
      mdat = nanmean(data.powspctrm,1);
      data.powspctrm = data.powspctrm - mdat(ones(1,nrpt),:,:,:,:,:);
    end
    data.fourierspctrm = data.powspctrm; %this is necessary for checkdata to work
    data.dimord        = ['rpttap',data.dimord(4:end)];
    data               = rmfield(data, 'powspctrm');
    data.cumtapcnt(:)  = 1;
    data.cumsumcnt(:)  = 1;
    if ncmb < (nchan-1)*nchan*0.5,
      data    = checkdata(data, 'cmbrepresentation', 'sparse', 'channelcmb', cmb);  
    else
      data    = checkdata(data, 'cmbrepresentation', 'full');
    end
    data.powcovspctrm = data.crsspctrm; 
    data              = rmfield(data, 'crsspctrm');
  elseif strcmp(inparam, 'powspctrm') && strcmp(outparam, 'powcovspctrm'),
    %power-spectral density -> power covariance

    if sqrtflag, data.powspctrm = sqrt(data.powspctrm); end    

    %get covariance by using checkdata
    if demeanflag,
      nrpt = size(data.powspctrm,1);
      mdat = nanmean(data.powspctrm,1);
      data.powspctrm = data.powspctrm - mdat(ones(1,nrpt),:,:,:,:,:);
    end
    data.fourierspctrm = data.powspctrm; %this is necessary for checkdata to work
    data.dimord        = ['rpttap',data.dimord(4:end)];
    data               = rmfield(data, 'powspctrm');
    data.cumtapcnt(:)  = 1;
    data.cumsumcnt(:)  = 1;
    if ncmb < (nchan-1)*nchan*0.5,
      data    = checkdata(data, 'cmbrepresentation', 'sparse', 'channelcmb', cmb);  
    else
      data    = checkdata(data, 'cmbrepresentation', 'full');
    end
    data.powcovspctrm = data.crsspctrm; 
    data = rmfield(data, 'crsspctrm');
  else
    error('unknown conversion from univariate to bivariate representation');
  end
  
  if ~isempty(cmb) && (ncmb < (nchan-1)*nchan*0.5 || getpowindx==1),
    powindx = labelcmb2indx(data.labelcmb);
  else
    powindx = [];
  end
case 'source'
  ncmb = numel(cmb);
  
  if strcmp(inparam, 'pow') && strcmp(outparam, 'powcov'),
    [nrpt,nvox] = size(data.pow);
    if sqrtflag, data.pow = sqrt(data.pow); end
    if demeanflag,
      mdat = nanmean(data.pow,1); 
      data.pow = data.pow - mdat(ones(1,nrpt),:); %FIXME only works for 1 frequency
    end
    
    data.powcov = [data.pow .* data.pow(:,ones(1,nvox)*cmb) data.pow.*data.pow];  
    data        = rmfield(data, 'pow');
    powindx     = [nvox+[1:nvox] nvox+[1:nvox]; cmb*ones(1,nvox) nvox+[1:nvox]]';
   
    data.pos    = [data.pos repmat(data.pos(cmb,:),[nvox 1]);data.pos data.pos]; 
    data.inside = [data.inside(:); data.inside(:)+nvox];
    data.outside = [data.outside(:); data.outside(:)+nvox];
    data.dim(2) = size(data.pos,1);
  elseif strcmp(inparam, 'mom') && strcmp(outparam, 'crsspctrm'),
    %get mom as rpttap_pos_freq matrix
    %FIXME this assumes only 1 freq bin
    mom = zeros(size(data.mom{data.inside(1)},1), size(data.pos,1));
    mom(:, data.inside) = cat(2, data.mom{data.inside});
    if keeprpt,
      [nrpt,nvox]    = size(mom);
      data.crsspctrm = [mom.*conj(mom(:,ones(1,nvox)*cmb)) abs(mom).^2];
      data           = rmfield(data, 'mom');
      data           = rmfield(data, 'momdimord');
      powindx     = [nvox+[1:nvox] nvox+[1:nvox]; cmb*ones(1,nvox) nvox+[1:nvox]]';

      data.pos    = [data.pos repmat(data.pos(cmb,:),[nvox 1]);data.pos data.pos]; 
      data.inside = [data.inside(:); data.inside(:)+nvox];
      data.outside = [data.outside(:); data.outside(:)+nvox];
    elseif ncmb<size(mom,2)
      %do it computationally more efficient
      [nrpt,nvox]    = size(mom);

      data.crsspctrm = reshape((transpose(mom)*conj(mom(:,cmb)))./nrpt, [nvox*ncmb 1]);
      tmppow         = mean(abs(mom).^2)';
      data.crsspctrm = cat(1, data.crsspctrm, tmppow);
      tmpindx1       = transpose(ncmb*nvox + ones(ncmb+1,1)*[1:nvox]);
      tmpindx2       = repmat(tmpindx1(cmb(:),end), [1 nvox])';
      tmpindx3       = repmat(cmb(:), [1 nvox])'; %expressed in original voxel indices
      powindx        = [tmpindx1(:) [tmpindx2(:);tmpindx1(:,end)]];

      data.pos       = [repmat(data.pos, [ncmb 1]) data.pos(tmpindx3(:),:); data.pos data.pos];    
      data.inside    = data.inside(:)*ones(1,ncmb+1) + (ones(length(data.inside),1)*nvox)*[0:ncmb];
      data.inside    = data.inside(:);
      data.outside   = setdiff([1:nvox*(ncmb+1)]', data.inside);
      if isfield(data, 'momdimord'), 
        data.crsspctrmdimord = ['pos_',data.momdimord(14:end)];%FIXME this assumes dimord to be 'rpttap_...'
      end
      data           = rmfield(data, 'mom');
      data           = rmfield(data, 'momdimord');
    else
      [nrpt,nvox]    = size(mom);
      data.crsspctrm = (transpose(mom)*conj(mom))./nrpt;
      data           = rmfield(data, 'mom');
      data           = rmfield(data, 'momdimord');
      powindx        = [];
      data.crsspctrmdimord = 'pos_pos_freq'; %FIXME hard coded
    end
    data.dimord = data.crsspctrmdimord;
    clear mom;
  else
    error('unknown conversion from univariate to bivariate representation');
  end
otherwise
end

hasrpt  = (isfield(data, 'dimord') && ~isempty(strfind(data.dimord, 'rpt')));

%if ~isfield(cfg, 'cohmethod'), cfg.cohmethod = 'coh';           end;
%if ~iscell(cfg.cohmethod),     cfg.cohmethod = {cfg.cohmethod}; end;
%if ~isfield(cfg, 'submethod'), cfg.submethod = '';              end;
%if ~isempty(cfg.submethod) && ~isfield(cfg, 'baseline'),
%  cfg.baseline = 'all';
%end
%
%if isfield(cfg, 'baseline') && strcmp(cfg.baseline, 'all'),
%  cfg.baseline = [freq.time(1) freq.time(end)];
%end
%
%if isfield(cfg, 'baseline'),
%  baselineindx = [nearest(freq.time, cfg.baseline(1)) nearest(freq.time, cfg.baseline(2))];
%end
%
%
%if hasrpt, 
%  nrpt = size(freq.cumtapcnt, 1); 
%else
%  nrpt = 1;
%  dum  = zeros([1 size(freq.crsspctrm)]); dum(1,:,:,:,:) = freq.crsspctrm; freq.crsspctrm = dum;
%  dum  = zeros([1 size(freq.powspctrm)]); dum(1,:,:,:,:) = freq.powspctrm; freq.powspctrm = dum;
%  dum  = zeros([1 size(freq.transfer) ]); dum(1,:,:,:,:) = freq.transfer;  freq.transfer  = dum;
%  dum  = zeros([1 size(freq.itransfer)]); dum(1,:,:,:,:) = freq.itransfer; freq.itransfer = dum;
%  dum  = zeros([1 size(freq.noisecov) ]); dum(1,:,:,:,:) = freq.noisecov;  freq.noisecov  = dum;
%  hasrpt = 1;
%end
%if hastim, 
%  ntoi = length(freq.time);       
%else
%  ntoi = 1;
%end
%nfoi  = length(freq.freq);
%nchan = length(freq.label);
%ncmb  = size(freq.labelcmb,1);
%ntap  = freq.cumtapcnt(1);
%
%for m = 1:length(cfg.cohmethod)
%  switch cfg.cohmethod{m}
%    case {'coh' 'coh2'}
%      for k = 1:ncmb
%        cmbindx(k,1) = match_str(freq.label,freq.labelcmb(k,1));
%        cmbindx(k,2) = match_str(freq.label,freq.labelcmb(k,2));
%      end
%
%      sumcohspctrm = zeros([ncmb  nfoi ntoi]);
%      sumpowspctrm = zeros([nchan nfoi ntoi]);
%      sqrcohspctrm = zeros([ncmb  nfoi ntoi]);
%      sqrpowspctrm = zeros([nchan nfoi ntoi]);
%      warning off;
%      for n = 1:nrpt
%        crsspctrm    = abs(reshape(mean(freq.crsspctrm(n,:,:,:,:),5), [ncmb  nfoi ntoi]));
%        tmppowspctrm = abs(reshape(mean(freq.powspctrm(n,:,:,:,:),5), [nchan nfoi ntoi]));
%        
%   if strcmp(cfg.cohmethod{m}, 'coh'),
%     tmpcohspctrm = crsspctrm./sqrt(abs(tmppowspctrm(cmbindx(:,1),:,:,:)).*abs(tmppowspctrm(cmbindx(:,2),:,:,:)));
%        else
%          tmph = reshape(freq.transfer(n,:,:,:,:), [nchan nchan nfoi ntoi ntap]);
%     for flop = 1:nfoi
%       for tlop = 1:ntoi
%         dum                       = tmph(:,:,flop,tlop)*tmph(:,:,flop,tlop)';
%         tmpcohspctrm(:,flop,tlop) = reshape(dum./sqrt(abs(diag(dum))*abs(diag(dum))'), [ncmb 1]);
%       end
%     end
%   end
%   
%   if ~isempty(cfg.submethod), tmpcohspctrm = baseline(tmpcohspctrm, cfg.submethod, baselineindx); end
%        if ~isempty(cfg.submethod), tmppowspctrm = baseline(tmppowspctrm, cfg.submethod, baselineindx); end
%   sumcohspctrm = tmpcohspctrm    + sumcohspctrm;
%   sqrcohspctrm = tmpcohspctrm.^2 + sqrcohspctrm;
%   sumpowspctrm = tmppowspctrm    + sumpowspctrm;
%   sqrpowspctrm = tmppowspctrm.^2 + sqrpowspctrm;
%      end
%      warning on;
%      cohspctrm = sumcohspctrm./nrpt;
%      powspctrm = sumpowspctrm./nrpt;
%
%      if nrpt>1,
%        bias         = (nrpt - 1)^2;
%        cohspctrmvar = bias.*(sqrcohspctrm - (sumcohspctrm.^2)/nrpt)./(nrpt-1);
%        powspctrmvar = bias.*(sqrpowspctrm - (sumpowspctrm.^2)/nrpt)./(nrpt-1);
%        cohspctrmsem = sqrt(cohspctrmvar./nrpt);
%        powspctrmsem = sqrt(powspctrmvar./nrpt);
%      end
%    case 'dtf'
%      sumdtf = zeros(ncmb, nfoi, ntoi, ntap);
%      sqrdtf = zeros(ncmb, nfoi, ntoi, ntap);
%      for n = 1:nrpt
%        tmph   = reshape(freq.transfer(n,:,:,:,:), [nchan nchan nfoi ntoi ntap]);
%        den    = sum(abs(tmph).^2,2);
%        tmpdtf = abs(tmph)./sqrt(repmat(den, [1 nchan 1 1 1]));
%        tmpdtf = reshape(tmpdtf, [ncmb nfoi ntoi ntap]);
%        if ~isempty(cfg.submethod), tmpdtf = baseline(tmpdtf, cfg.submethod, baselineindx); end
%        sumdtf = sumdtf + tmpdtf;
%   sqrdtf = sqrdtf + tmpdtf.^2;
%      end
%      dtf = sumdtf./nrpt;
%
%      if nrpt>1,
%        bias   = (nrpt - 1).^2;
%   dtfvar = bias.*(sqrdtf - (sumdtf.^2)/nrpt)./(nrpt-1);
%   dtfsem = sqrt(dtfvar./nrpt);
%      end
%    case 'pdc'
%      sumpdc = zeros(ncmb, nfoi, ntoi, ntap);
%      sqrpdc = zeros(ncmb, nfoi, ntoi, ntap);
%      for n = 1:nrpt
%        invh = reshape(freq.itransfer(n,:,:,:,:), [nchan nchan nfoi ntoi ntap]);
%        %invh = zeros(size(h));
%        %for j = 1:nfoi
%        %  for k = 1:ntoi
%   %    invh(:,:,j,k) = inv(h(:,:,j,k));
%   %  end
%        %end
%        den    = sum(abs(invh).^2,1);
%        tmp    = abs(invh)./sqrt(repmat(den, [nchan 1 1 1 1]));
%        tmppdc = reshape(tmp, [ncmb nfoi ntoi ntap]);
%        if ~isempty(cfg.submethod), tmppdc = baseline(tmppdc, cfg.submethod, baselineindx); end
%   sumpdc = sumpdc + tmppdc;
%   sqrpdc = sqrpdc + tmppdc.^2;
%      end
%      pdc = sumpdc./nrpt;
%      
%      if nrpt>1,
%        bias   = (nrpt - 1).^2;
%   pdcvar = bias.*(sqrpdc - (sumpdc.^2)/nrpt)./(nrpt-1);
%   pdcsem = sqrt(pdcvar./nrpt);
%      end
%    otherwise
%      error('unknown cohmethod specified in cfg.cohmethod');
%  end
%end
%
%%---create output-structure
%fd = [];
%fd.label = freq.label;
%fd.labelcmb = freq.labelcmb;
%fd.freq     = freq.freq;
%if hastim, fd.time = freq.time; end
%fd.nobs     = nrpt;
%fd.dimord   = 'chan_freq_time';
%
%try, fd.pdc       = pdc;       end
%try, fd.pdcsem    = pdcsem;    end
%try, fd.dtf       = dtf;       end
%try, fd.dtfsem    = dtfsem;    end
%try, fd.cohspctrm = cohspctrm; end
%try, fd.powspctrm = powspctrm; end
%try, fd.cohspctrmsem = cohspctrmsem; end
%try, fd.powspctrmsem = powspctrmsem; end
%try, cfg.previous    = freq.cfg;     end
%fd.cfg = cfg;
%
%%---subfunction to do baseline correction
%function [output] = baseline(input, method, baseline)
%
%switch method,
%  case 'relchange'
%    b      = mean(input(:,:,baseline(1):baseline(2)),3);
%    output = input./repmat(b, [1 1 size(input,3) 1]) - 1;
%  case 'diff'
%    b      = mean(input(:,:,baseline(1):baseline(2)),3);
%    output = input-repmat(b, [1 1 size(input,3) 1]);
%  otherwise
%    error('specified baseline-method is not yet implemented');
%end
