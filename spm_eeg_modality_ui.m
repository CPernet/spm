function modality = spm_eeg_modality_ui(D, scalp)
% spm_eeg_modality_ui - tries to determine the main modality
% of an meeg object. If confused, asks the user.
% _________________________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging

% Vladimir Litvak
% $Id: spm_eeg_modality_ui.m 1491 2008-04-28 16:46:35Z vladimir $

if nargin == 1
    scalp = 0;
end

% indices of EEG channel (excluding bad channels)
%--------------------------------------------------------------------------
% At the moment only the 3 modalities relevant for DCM and 3D source
% reconstruction are probed.
if scalp
    modalities = {'EEG', 'MEG'};
else
    modalities = {'EEG', 'MEG', 'LFP'};
end

modind = sort(unique(spm_match_str(modalities, D.chantype)));

if length(modind)> 1
    qstr = [];
    for i = 1:length(modind)
        if ~isempty(qstr)
            qstr = [qstr '|'];
        end
        qstr = [qstr modalities{modind(i)}];
    end
    modality = spm_input('Which modality?','+1',qstr);
elseif length(modind) == 1
    modality = modalities{modind};
else
    error('Could not determine the modality');
end