function [stat] = sourcestatistics_parametric(cfg, varargin)

% SOURCESTATISTICS_PARAMETRIC performs statistical analysis of the
% beamformer source reconstruction results using parametric methods.
%
% Use as
%   [stat] = sourcestatistics(cfg, source1, source2, source3, ...)
% where cfg is a structure with the configuration details and sourceN
% is the source reconstruction for a particular active, baseline or
% noise condition.
%
% The general configuration items are
%   cfg.method     = 'randomization'
%   cfg.statistic  = string, see below
%   cfg.parameter  = string, describing the functional data to be processed, e.g. 'pow', 'nai' or 'coh'
%   cfg.bonferoni  = 'yes' or 'no', use Bonferoni correction for multiple comparisons
%   cfg.threshold  = the p-value with respect to the reference distribution at which
%                    an observed difference will be considered significant (default = 0.05)
%
% cfg.statistic = 'zero-baseline' performs t-test against the assumption of the signal being zero
%   [stat] = sourcestatistics(cfg, active)
% This requires a variance estimate for the source parameters
%
% cfg.statistic = 'difference' performs t-test on the difference
%   [stat] = sourcestatistics(cfg, condition1, condition2)
% This compares condition1 and condition2, and requires a variance estimate for the
% source parameters.
%
% cfg.statistic = 'anova1'
%   [stat] = sourcestatistics(cfg, condition1, condition2, ...)
% This performs a one-way ANOVA for comparing the means of two or more
% source reconstructions. It requires the source reconstruction to contain
% single trials.
%
% cfg.statistic = 'kruskalwallis'
%   [stat] = sourcestatistics(cfg, condition1, condition2, ...)
% This performs a non-parametric one-way ANOVA for comparing the means of two
% or more source reconstructions. It requires the source reconstruction to
% contain single trials.

% FIXME this function should use parameterselection and getsubfield
%
% Undocumented local options:
% cfg.equalvar
% cfg.tscore

% Copyright (C) 2003, Robert Oostenveld
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
% $Id: sourcestatistics_parametric.m 948 2010-04-21 18:02:21Z roboos $

fieldtripdefs

% check if the input data is valid for this function
for i=1:length(varargin)
  varargin{i} = checkdata(varargin{i}, 'datatype', {'source', 'volume'}, 'feedback', 'no', 'inside', 'index');
end

% set the defaults
if ~isfield(cfg, 'threshold'),   cfg.threshold = 0.05;    end
if ~isfield(cfg, 'bonferoni'),   cfg.bonferoni = 'no';    end
if ~isfield(cfg, 'equalvar'),    cfg.equalvar ='no';      end

% for backward comparibility
if isfield(cfg, 'method') && ~strcmp(cfg.method, 'parametric')
  warning('the configuration options cfg.method has been renamed in cfg.statistic, please read the documentation');
  cfg.statistic = cfg.method;
  cfg.method = 'parametric';
end

% check for potential backward incomparibilities
if isfield(cfg, 'zscore')
  warning('transformation from t-score to zcore is not supported any more');
end

% check for potential backward incomparibilities
if isfield(cfg, 'tscore')
  warning('the option cfg.tscore is not used, please check your configuration');
end

% check for potential backward incomparibilities
if isfield(cfg, 'threshold') && cfg.threshold>0.5
  cfg.threshold = 1 - cfg.threshold;
  warning('the interpretation of cfg.threshold has changed from (1-P) to P, for consistency with other functions')
  warning(sprintf('assuming that you want to test your null-hypothesis with an alpha of %f', cfg.threshold));
end

% check whether a valid statistical test has been selected
if ~isfield(cfg, 'method')
  error('no method specified for the statistical test');
elseif strcmp(cfg.statistic, 'descriptive')
  error('descriptive is not supported any more, use SOURCEDESCRIPTIVES');
elseif strcmp(cfg.statistic, 'nai')
  error('pseudostatistics such as neural activity index are not supported any more, use SOURCEDESCRIPTIVES');
elseif strcmp(cfg.statistic, 'pseudo-t')
  error('pseudostatistics such as pseudo-t are not supported any more, use SOURCEDESCRIPTIVES');
elseif ~(strcmp(cfg.statistic, 'zero-baseline') || ...
    strcmp(cfg.statistic, 'difference')    || ...
    strcmp(cfg.statistic, 'anova1')        || ...
    strcmp(cfg.statistic, 'kruskalwallis'))
  error('unsupported statistical method');
end

% remember the definition of the volume, assume that they are identical for all input arguments
try, stat.dim       = varargin{1}.dim;        end
try, stat.xgrid     = varargin{1}.xgrid;      end
try, stat.ygrid     = varargin{1}.ygrid;      end
try, stat.zgrid     = varargin{1}.zgrid;      end
try, stat.inside    = varargin{1}.inside;     end
try, stat.outside   = varargin{1}.outside;    end
try, stat.pos       = varargin{1}.pos;        end
try, stat.transform = varargin{1}.transform;  end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% preprocess the input data and extract the parameter of interest
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% count the dimensions of all items that we might loop over
Nconditions = length(varargin);
Nvoxels     = prod(varargin{1}.dim);
if isfield(varargin{1}, 'trial')
  for condition=1:Nconditions
    Ntrials(condition) = length(varargin{condition}.trial);
  end
else
  Ntrials(1:Nconditions) = 0;
end

% collect the data to perform the statistics on, the resulting array will contain
%   source(i).df
%   source(i).avg
%   source(i).var       optionally
%   source(i).sem       optionally
%   source(i).trial     optionally

for condition=1:Nconditions
  % source.df contains the number of repetitions used in computing the average and variance
  source(condition).avg     = getfield(varargin{condition}.avg, cfg.parameter);
  try, source(condition).df = varargin{condition}.df; end
  if isfield(varargin{condition}, 'var') && isfield(varargin{condition}.var, cfg.parameter)
    source(condition).var   = getfield(varargin{condition}.var, cfg.parameter);
  end
  if isfield(varargin{condition}, 'sem') && isfield(varargin{condition}.sem, cfg.parameter)
    source(condition).sem   = getfield(varargin{condition}.sem, cfg.parameter);
  end
  for trloop=1:Ntrials(condition)
    % if trial data for this parameter is not present, Ntrials will be zero
    % reformat all the trials into a matrix, each column is a trial
    source(condition).trial(trloop,:) = getfield(varargin{condition}.trial(trloop), cfg.parameter);
  end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% perform the statistical test, this is the method specific part
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

switch lower(cfg.statistic)

  case 'zero-baseline'
    % compute difference between source parameter and zero, using Students t-score
    if Nconditions>1
      error('only one source reconstruction allowed for zero-baseline comparison');
    end
    tscore     = source.avg./(source.var./source.df).^0.5;
    combineddf = source.df - 1;
    prob       = 1-tcdf(tscore, combineddf);

  case 'difference'
    % compute difference between two conditions using Students t-score
    if Nconditions~=2
      error('exactly two source reconstructions required to compute difference statistic');
    end
    condition1 = source(1);
    condition2 = source(2);
    difference = condition1.avg - condition2.avg;
    v1 = condition1.var;
    N1 = condition1.df;
    v2 = condition2.var;
    N2 = condition2.df;
    if strcmp(cfg.equalvar, 'yes')
      % assume equal variances for both conditions
      combinedvar = ((N1-1)*v1 + (N2-1)*v2)/(N1 + N2 - 2);
      combineddf  = N1 + N2 - 2;
      tscore      = difference ./ sqrt(combinedvar*(1/N1 + 1/N2));
    else
      % do not assume equal variances
      tscore = difference ./ sqrt(v1./N1 + v2./N2);
      % use Welch-Satterthwaite approximation for the combined degrees of freedom (see NIST handbook)
      % FIXME this leads to a different df for each source location
      combineddf = (v1./N1 + v2./N2).^2./((v1.^2)./(N1.^2.*(N1-1)) + (v2.^2)./(N2.^2.*(N2-1)));
    end
    prob = 1-tcdf(tscore, combineddf);

  case 'anova1'
    if Nconditions<2
      error('at least two source inputs required for one-way Anova test');
    end
    for voxel=1:Nvoxels
      % perform a one-way Anova test for each voxel
      value = [];
      group = [];
      for condition=1:Nconditions
        N = size(source(condition).trial,2);    % number of resamplings or single trials
        value = [value; source(condition).trial(voxel,:)];
        group = [group; condition * ones(N,1)];
      end
      % use a function from the Matlab statistics toolbox for the computation
      prob(voxel) = anova1(value, group, 'off');
    end
    prob = 1 - prob;

  case 'kruskalwallis'
    if Nconditions<2
      error('at least two source inputs required for Kruskal-Wallis test');
    end
    for voxel=1:Nvoxels
      % perform a Kruskal-Wallis test for each voxel
      value = [];
      group = [];
      for condition=1:Nconditions
        tmp = source(condition).trial(:,voxel);
        value = [value; tmp(:)];
        group = [group; condition * ones(Ntrials(condition),1)];
      end
      % use a function from the Matlab statistics toolbox for the computation
      prob(voxel) = kruskalwallis(value, group, 'off');
    end
    prob = 1 - prob;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% ready with the method specific part
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% compute the significance as boolean value
if exist('prob', 'var')
  if strcmp(cfg.bonferoni, 'no')
    fprintf('not correcting for multiple comparisons\n');
    mask = prob < cfg.threshold;
  else
    fprintf('performing Bonferoni correction for multiple comparisons\n');
    mask = prob < (cfg.threshold/length(stat.inside));
  end
else
  warning('no statistical probablity value was computed');
end

% collect the non-descriptive statistics, probability and significance
if exist('tscore', 'var'), stat.tscore = tscore; end
if exist('prob', 'var'),   stat.prob = prob;     end
if exist('nai', 'var'),    stat.nai = nai;       end
if exist('mask', 'var'),   stat.mask = mask;     end

% add version information to the configuration
try
  % get the full name of the function
  cfg.version.name = mfilename('fullpath');
catch
  % required for compatibility with Matlab versions prior to release 13 (6.5)
  [st, i] = dbstack;
  cfg.version.name = st(i);
end
cfg.version.id = '$Id: sourcestatistics_parametric.m 948 2010-04-21 18:02:21Z roboos $';
% remember the configuration details of the input data
cfg.previous = [];
for i=1:length(varargin)
  try, cfg.previous{i} = varargin{i}.cfg; end
end
% remember the exact configuration details in the output
stat.cfg = cfg;

