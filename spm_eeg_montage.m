function [D, montage] = spm_eeg_montage(S)
% rereference EEG data to new reference channel(s)
% FORMAT [D, montage] = spm_eeg_montage(S)
%
% S         - struct (optional)
% (optional) fields of S:
% S.D         - meeg object of filename of SPM EEG file
% S.montage - (optional)
% A montage is specified as a structure with the fields
%   montage.tra      = MxN matrix
%   montage.labelnew = Mx1 cell-array - new labels
%   montage.labelorg = Nx1 cell-array - original labels
%   montage.keepothers = 'yes' - keep the channels not involved in the montage (default)
%                        'no' - discard the channels not involved in the montage 
% S.blocksize - size of blocks used internally to split large continuous files
%               default ~100Mb.
%
% Output:
% D         - MEEG data struct (also written to files)
% montage   - the montage applied
%_______________________________________________________________________
% spm_eeg_montage applies montage provided or specified by the user to 
% data and sensors of an MEEG file an produces a new file. It works
% correctly when no sensors are specified or when data and sensors are
% consistent (which is ensured by spm_eeg_prep_ui).
%_______________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging

% Vladimir Litvak, Robert Oostenveld, Stefan Kiebel
% $Id: spm_eeg_montage.m 1593 2008-05-11 13:37:50Z vladimir $

[Finter, Fgraph, CmdLine] = spm('FnUIsetup','EEG montage',0);

if nargin == 0
    S = [];
end

if ~isfield(S, 'blocksize'),       S.blocksize = 3276800;   end  %100 Mb

if isfield(S, 'D')
    D = S.D;
else
    D = spm_select(1, '\.mat$', 'Select MEEG mat file');
end

if ~isa(D, 'meeg')
    D = spm_eeg_load(D);
end

if isfield(S, 'montage')
    montage = S.montage;
else
    montage = [];
    montage.labelorg = D.chanlabels;
    error('GUI specification of montage is under development.');
    %montage = spm_eeg_montage_ui(montage);
end
    
if ~all(isfield(montage, {'labelnew', 'labelorg', 'tra'})) || ...
        any([isempty(montage.labelnew), isempty(montage.labelorg), isempty(montage.tra)]) || ...
        length(montage.labelnew) ~= size(montage.tra, 1) || length(montage.labelorg) ~= size(montage.tra, 2)

    error('Insufficient or illegal montage specification.');
end

if ~isfield(montage, 'keepothers')
    montage.keepothers = 'yes';
end

% apply montage to sensors
eegsens = D.sensors('EEG');
if ~isempty(eegsens) && length(intersect(eegsens.label, montage.labelorg))==length(eegsens.label)
    eegsens = forwinv_apply_montage(eegsens, montage);
end

megsens = D.sensors('MEG');
if ~isempty(megsens) && length(intersect(megsens.label, montage.labelorg))==length(megsens.label)
    megsens = forwinv_apply_montage(megsens, montage);
end

% select and discard the columns that are empty
selempty = find(~all(montage.tra==0, 1));
montage.tra      = montage.tra(:, selempty);
montage.labelorg = montage.labelorg(selempty);

% add columns for the channels that are not involved in the montage
[add, ind] = setdiff(D.chanlabels, montage.labelorg);
add = D.chanlabels(sort(ind));

m = size(montage.tra, 1);
n = size(montage.tra, 2);
k = length(add);
if strcmp(montage.keepothers, 'yes')
    montage.tra((m+(1:k)), (n+(1:k))) = eye(k);
    montage.labelnew = cat(1, montage.labelnew(:), add(:));
else
    montage.tra = [montage.tra zeros(m, k)];
end
montage.labelorg = cat(1, montage.labelorg(:), add(:));

% determine whether all channels are unique
m = size(montage.tra,1);
n = size(montage.tra,2);
if length(unique(montage.labelnew))~=m
  error('not all output channels of the montage are unique');
end
if length(unique(montage.labelorg))~=n
  error('not all input channels of the montage are unique');
end

% determine whether all channels that have to be rereferenced are available
if length(intersect(D.chanlabels, montage.labelorg)) ~= D.nchannels
  error('not all channels that are used in the montage are available');
end

% reorder the columns of the montage matrix
[selchan, selmont] = spm_match_str(D.chanlabels, montage.labelorg);
montage.tra        = montage.tra(:,selmont);
montage.labelorg   = montage.labelorg(selmont);

spm('Pointer', 'Watch');drawnow;

% generate new meeg object with new filenames
Dnew = clone(D, ['M' fnamedat(D)], [m D.nsamples D.ntrials]);

nblocksamples = floor(S.blocksize/max(D.nchannels, m));

if D.nsamples <= nblocksamples
    nblocks = 1;
    nblocksamples = D.nsamples;
else
    nblocks = floor(D.nsamples./nblocksamples);
end

if D.ntrials > 100, Ibar = floor(linspace(1, D.ntrials,100));
elseif  D.ntrials == 1, Ibar = [1:ceil(D.nsamples./nblocksamples)]; 
else Ibar = [1:D.ntrials]; end

spm_progress_bar('Init', Ibar(end), 'Applying montage'); drawnow;

for i = 1:D.ntrials
    for j = 1:nblocks

        Dnew(:, ((j-1)*nblocksamples +1) : (j*nblocksamples), i) = ...
            montage.tra * squeeze(D(:, ((j-1)*nblocksamples +1) : (j*nblocksamples), i));

        if D.ntrials == 1 && ismember(j, Ibar)
            spm_progress_bar('Set', j); drawnow;
        end
    end

    if mod(D.nsamples, nblocksamples) ~= 0
        Dnew(:, (nblocks*nblocksamples +1) : D.nsamples, i) = ...
            montage.tra * squeeze(D(:, (nblocks*nblocksamples +1) : D.nsamples, i));
    end


    if D.ntrials>1 && ismember(i, Ibar)
        spm_progress_bar('Set', i); drawnow;
    end
end

Dnew = chanlabels(Dnew, 1:Dnew.nchannels, montage.labelnew);

% Set channel types to default
Dnew = chantype(Dnew, [], []);

Dnew = sensors(Dnew, 'EEG', eegsens);
Dnew = sensors(Dnew, 'MEG', megsens);

spm_progress_bar('Clear');

save(Dnew);

spm('Pointer', 'Arrow');
