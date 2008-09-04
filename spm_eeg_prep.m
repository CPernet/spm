function D = spm_eeg_prep(S)
% spm_eeg_prep function performs several tasks
% for preparation of converted MEEG data for further analysis
% FORMAT spm_eeg_prep(S)
%   S - configuration struct (obligatory)
% _______________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging

% Vladimir Litvak
% $Id: spm_eeg_prep.m 2041 2008-09-04 13:39:40Z jean $

if nargin==0;
    spm_eeg_prep_ui;
    return
end
D = S.D;

switch S.task
    case 'settype'
        D = chantype(D, S.ind, S.type);
    case {'loadtemplate', 'setcoor2d', 'project3D'}
        switch S.task
            case 'loadtemplate'
                template = load(S.P); % must contain Cpos, Cnames
                xy = template.Cpos;
                label = template.Cnames;
            case 'setcoor2d'
                xy = S.xy;
                label = S.label;
            case 'project3D'
                [xy, label] = spm_eeg_project3D(D.sensors(S.modality), S.modality);
        end

        [sel1, sel2] = spm_match_str(lower(D.chanlabels), lower(label));

        if ~isempty(sel1)

            megind = strmatch('MEG', chantype(D), 'exact');
            eegind = strmatch('EEG', chantype(D), 'exact');

            if ~isempty(intersect(megind, sel1)) && ~isempty(setdiff(megind, sel1))
                error('2D locations not found for all MEG channels');
            end

            if ~isempty(intersect(eegind, sel1)) && ~isempty(setdiff(eegind, sel1))
                warning(['2D locations not found for all EEG channels, changing type of channels', ...
                    num2str(setdiff(eegind, sel1)) ' to ''Other''']);

                D = chantype(D, setdiff(eegind, sel1), 'Other');
            end

            if any(any(coor2D(D, sel1) - xy(:, sel2)))
                D = coor2D(D, sel1, num2cell(xy(:, sel2)));
            end
        end
    case 'loadeegsens'
        switch S.source
            case 'mat'
                senspos = load(S.sensfile);
                name    = fieldnames(senspos);
                senspos = getfield(senspos,name{1});

                label = chanlabels(D, sort(strmatch('EEG', D.chantype, 'exact')));

                if size(senspos, 1) ~= length(label)
                    error('To read sensor positions without labels the numbers of sensors and EEG channels should match.');
                end

                elec = [];
                elec.pnt = senspos;
                elec.label = label;                
            case 'locfile'
                label = chanlabels(D, sort(strmatch('EEG', D.chantype, 'exact')));

                elec = fileio_read_sens(S.sensfile);

                % This handles FIL Polhemus case and other possible cases
                % when no proper labels are available.
                if isempty(intersect(label, elec.label))
                    ind = str2num(strvcat(elec.label));
                    if length(ind) == length(label)
                        elec.label = label(ind);
                    else
                        error('To read sensor positions without labels the numbers of sensors and EEG channels should match.');
                    end
                end

        end

        elec = forwinv_convert_units(elec, 'mm');
        
        D = sensors(D, 'EEG', elec);
        
        fid = [];
        fid.fid = elec;
        fid.pnt = elec.pnt;
        
        D = fiducials(D, fid);

    case 'sens2chan'
        montage = S.montage;
        
        eeglabel = D.chanlabels(strmatch('EEG',D.chantype));
        meglabel = D.chanlabels(strmatch('MEG',D.chantype));
        
        if ~isempty(intersect(eeglabel, montage.labelnew))
            sens = sensors(D, 'EEG');
            if isempty(sens)
                error('The montage cannod be applied - no EEG sensors specified');
            end
            sens = forwinv_apply_montage(sens, montage, 'keepunused', 'no');
            D = sensors(D, 'EEG', sens);
        elseif ~isempty(intersect(meglabel, montage.labelnew))
            sens = sensors(D, 'MEG');
            if isempty(sens)
                error('The montage cannod be applied - no MEG sensors specified');
            end
            sens = forwinv_apply_montage(sens, montage, 'keepunused', 'no');
            D = sensors(D, 'MEG', sens);
        else
            error('The montage cannot be applied to the sensors');
        end         
        
    case 'headshape'
        switch S.source
            case 'mat'
                headshape = load(S.headshapefile);
                name    = fieldnames(headshape);
                headshape = getfield(headshape,name{1});

                shape = [];

                fidnum = 0;
                while ~all(isspace(S.fidlabel))
                    fidnum = fidnum+1;
                    [shape.fid.label{fidnum} S.fidlabel] = strtok(S.fidlabel);
                end

                if (fidnum < 3)  || (size(headshape, 1) < fidnum)
                    error('At least 3 labeled fiducials are necessary');
                end

                shape.fid.pnt = headshape(1:fidnum, :);

                if size(headshape, 1) > fidnum
                    shape.pnt = headshape((fidnum+1):end, :);
                else
                    shape.pnt = [];
                end
            otherwise
                shape = fileio_read_headshape(S.headshapefile);
                
                % In case electrode file is used for fiducials, the
                % electrodes can be used as headshape
                if ~isfield(shape, 'pnt') || isempty(shape.pnt) && ...
                        size(shape.fid.pnt, 1) > 3
                    shape.pnt = shape.fid.pnt;
                end
        end

        shape = forwinv_convert_units(shape, 'mm');

        fid = D.fiducials;
        if ~isempty(fid) && ~isempty(S.regfid)
            sel1 = spm_match_str(S.regfid(:, 1), fid.fid.label);
            sel2 = spm_match_str(S.regfid(:, 2), shape.fid.label);

            M1 = spm_eeg_inv_rigidreg(fid.fid.pnt(sel1, :)', shape.fid.pnt(sel2, :)');

            shape = forwinv_transform_headshape(M1, shape);
        end

        D = fiducials(D, shape);

    case 'coregister'
        [ok, D] = check(D, 'sensfid');

        if ~ok
            error('Coregistration cannot be performed due to missing data');
        end
        
        try
            val = D.val;
            Msize = D.inv{val}.mesh.Msize;
        catch
            val = 0;
            Msize = 1;
        end
        D = spm_eeg_inv_mesh_ui(D, val, 1, Msize);
        D = spm_eeg_inv_datareg_ui(D, 1, S.modality);
        
        if strcmp(S.modality, 'EEG')
            D = sensors(D, 'EEG', D.inv{1}.datareg.sensors);
            D = fiducials(D, D.inv{1}.datareg.fid_eeg);
        end

    case 'prepvolsens'
        % bookkeeping to ensures that the volume conductor model and the 
        % sensor array are appropriate. Furthermore it takes care of 
        % pre-computations that can be done efficiently prior to the
        % leadfield calculations.
%         vol_i = D.inv{D.val}.forward.vol;
%         sens_i = D.inv{D.val}.sensors;
        [D.inv{D.val}.forward.vol, D.inv{D.val}.datareg.sensors] = ...
            forwinv_prepare_vol_sens(D.inv{D.val}.forward.vol, ...
                                     D.inv{D.val}.datareg.sensors);

    otherwise
        fprintf('Nothing done ''cos I did not understant the instructions');
end