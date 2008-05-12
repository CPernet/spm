function D = spm_eeg_tf(S)
% compute instantaneous power and phase in peri-stimulus time and frequency
% FORMAT D = spm_eeg_tf(S)
%
% D     - filename of EEG-data file or EEG data struct
% stored in struct D.events:
% fmin          - minimum frequency
% fmax          - maximum frequency
% rm_baseline   - baseline removal (1/0) yes/no
% Mfactor       - Morlet wavelet factor (can not be accessed by GUI)
%
% D             - EEG data struct with time-frequency data (also written to files)
%_______________________________________________________________________
%
% spm_eeg_tf estimates instantaneous power and phase of data using the
% continuous Morlet wavelet transform.
%_______________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging

% Stefan Kiebel
% $Id: spm_eeg_tf.m 1598 2008-05-12 12:06:54Z stefan $


[Finter,Fgraph,CmdLine] = spm('FnUIsetup','EEG time-frequency setup',0);

try
    D = S.D;
catch
    D = spm_select(1, 'mat', 'Select EEG mat file');
end

P = spm_str_manip(D, 'H');

try
    D = spm_eeg_load(D);
catch
    error(sprintf('Trouble reading file %s', D));
end

try
    tf.frequencies = S.tf.frequencies;
catch
    tf.frequencies = ...
        spm_input('Frequencies (Hz)', '+1', 'r', '', [1, inf]);
end

try
    tf.rm_baseline = S.tf.rm_baseline;
catch
    tf.rm_baseline = ...
        spm_input('Removal of baseline', '+1', 'y/n', [1,0], 2);
end

if tf.rm_baseline
    try
        tf.Sbaseline = S.tf.Sbaseline;
    catch
        tf.Sbaseline = ...
            spm_input('Start and stop of baseline [ms]', '+1', 'i', '', 2);
    end
end

try
    tf.Mfactor = S.tf.Mfactor;
catch
    tf.Mfactor = ...
        spm_input('Which Morlet wavelet factor?', '+1', 'r', '7', 1);
end

try
    tf.channels = S.tf.channels;
catch
    tf.channels = ...
        spm_input('Select channels', '+1', 'i', num2str([1:D.nchannels]));
end

try
    tf.phase = S.tf.phase; % 1: compute phase, 0: don't
catch
    tf.phase = ...
        spm_input('Compute phase?', '+1', 'y/n', [1,0], 2);
end

try
    tf.pow = S.tf.pow;    % 1 = power, 0 = magnitude
catch
    tf.pow = 1;
end

if length(tf.channels) > 1
    try
        tf.collchans = S.tf.collchans;    % 1 = collapse across channels, 0 = do not
    catch
        tf.collchans = spm_input('Collapse channels?', '+1', 'y/n', [1,0], 2);
    end
else
    tf.collchans = 0;
end

% ?
try S.tf.circularise_phase
    tf.circularise = S.tf.circularise_phase;
catch
    tf.circularise = 0;
end

spm('Pointer', 'Watch'); drawnow;

M = spm_eeg_morlet(tf.Mfactor, 1000/D.fsample, tf.frequencies);

if tf.collchans
    Nchannels = 1;
else
    Nchannels = length(tf.channels);
end

Nfrequencies = length(tf.frequencies);

Dtf = clone(D, ['tf1_' D.fnamedat], [Nchannels Nfrequencies D.nsamples D.ntrials]);
Dtf = frequencies(Dtf, tf.frequencies);

% fix all channels
sD = struct(Dtf);

for i = 1:length(tf.channels)
    sD.channels(i).label = D.chanlabels(tf.channels(i));
    if D.badchannels(tf.channels(i))
        sD.channels(i).bad = 1;
    end
    sD.channels(i).type = D.chantype(tf.channels(i));
    Dtf = coor2D(Dtf, i, coor2D(D, tf.channels(i)));
    % units?

end
Dtf = meeg(sD);
Dtf = coor2D(Dtf,[1:length(tf.channels)], coor2D(D,tf.channels));

if tf.phase == 1
    Dtf2 = clone(D, ['tf2_' D.fnamedat], [Nchannels Nfrequencies D.nsamples D.ntrials]);
    Dtf2 = frequencies(Dtf2, tf.frequencies);

    % fix all channels
    sD = struct(Dtf2);

    for i = 1:length(tf.channels)
        sD.channels(i).label = D.chanlabels(tf.channels(i));
        if D.badchannels(tf.channels(i))
            sD.channels(i).bad = 1;
        end
        sD.channels(i).type = D.chantype(tf.channels(i));
        % units?


    end
    Dtf2 = meeg(sD);
    Dtf2 = coor2D(Dtf2,[1:length(tf.channels)], coor2D(D,tf.channels));
end


spm_progress_bar('Init', D.ntrials, 'trials done'); drawnow;
if D.ntrials > 100, Ibar = floor(linspace(1, D.ntrials, 100));
else Ibar = [1:D.ntrials]; end

for k = 1:D.ntrials

    d = zeros(length(tf.channels), Nfrequencies, D.nsamples);

    if tf.phase
        d2 = zeros(length(tf.channels), Nfrequencies, D.nsamples);
    end

    for j = 1:length(tf.channels)
        for i = 1 : Nfrequencies
            tmp = conv(squeeze(D(tf.channels(j), :, k)), M{i});

            % time shift to remove delay
            tmp = tmp([1:D.nsamples] + (length(M{i})-1)/2);

            % power
            if tf.pow
                d(j, i, :) = tmp.*conj(tmp);
            else
                d(j, i, :) = abs(tmp);
            end

            % phase
            if tf.phase
                d2(j, i, :) = angle(tmp);
            end

        end
    end

    if tf.collchans
        d = mean(d, 1);

        if tf.phase
            if tf.circularise
                tmp = cos(d2) + sqrt(-1)*sin(d2);
                d2 = double(abs(mean(tmp,1))./mean(abs(tmp),1));
            else
                d2 = mean(d2,1);
            end
        end
    end

    Dtf(:, :, :, k) = d;

    if tf.phase
        Dtf2(:, :, :, k) = d2;
    end

    if ismember(k, Ibar)
        spm_progress_bar('Set', k);
        drawnow;
    end

end

spm_progress_bar('Clear');

% Remove baseline over frequencies and trials (do later)
if tf.rm_baseline == 1
    Dtf = spm_eeg_bc(Dtf, tf.Sbaseline);
end

save(Dtf);
if tf.phase
    save(Dtf2);
end

spm('Pointer', 'Arrow');
