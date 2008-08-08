function [D] = spm_eeg_review_switchDisplay(D)
%__________________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging

% Jean Daunizeau
% $Id: spm_eeg_review_switchDisplay.m 1988 2008-08-08 18:25:14Z jean $

try % only if already displayed stuffs
    handles = rmfield(D.PSD.handles,'PLOT');
    D.PSD.handles = handles;
end


if strcmp(D.PSD.VIZU.modality,'source')
    delete(findobj('tag','plotEEG'));
    [D] = visuRecon(D);

elseif strcmp(D.PSD.VIZU.modality,'info')
    delete(findobj('tag','plotEEG'));
    [D] = DataInfo(D);
    set(D.PSD.handles.hfig,'userdata',D)

else % EEG/MEG/OTHER

    try
        y = D.data.y(:,D.PSD.VIZU.xlim(1):D.PSD.VIZU.xlim(2));
    catch
        D.PSD.VIZU.xlim = [1,min([5e2,D.Nsamples])];
    end   
    switch  D.PSD.VIZU.type

        case 1
            delete(findobj('tag','plotEEG'))
            [D] = standardData(D);
            rotate3d off

        case 2
            delete(findobj('tag','plotEEG'))
            [D] = scalpData(D);
            rotate3d off

    end

end



%% Standard EEG/MEG data plot
function [D] = standardData(D)

POS = get(D.PSD.handles.hfig,'position');

switch D.PSD.VIZU.modality
    case 'eeg'
        I = D.PSD.EEG.I;
    case 'meg'
        I = D.PSD.MEG.I;
    case 'other'
        I = D.PSD.other.I;
end

if isempty(I)

    uicontrol('style','text','Position',[0.14 0.84 0.7 0.04].*repmat(POS(3:4),1,2),...
        'string','No channel of this type in the data !',...
        'BackgroundColor',0.95*[1 1 1],...
        'tag','plotEEG')

else

    if ~strcmp(D.transform.ID,'time')

        uicontrol('style','text','Position',[0.14 0.84 0.7 0.04].*repmat(POS(3:4),1,2),...
            'string','Not for time-frequency data !',...
            'BackgroundColor',0.95*[1 1 1],...
            'tag','plotEEG')

    else
        

        D.PSD.VIZU.type = 1;

        % add axes
        object.type = 'axes';
        object.what = 'standard';
        D = spm_eeg_review_uis(D,object);

        % add buttons
        object.type = 'buttons';
        object.options.multSelect = 0;
        object.list = [1;2;3;4;5;6];
        switch D.PSD.type
            case 'continuous'
                object.list = [object.list;9];
            case 'epoched'
                object.list = [object.list;7;11];
                if strcmp(D.type,'single')
                    object.list = [object.list;13];
                end
        end
        D = spm_eeg_review_uis(D,object);

        
    end

end

%% 'SPM-like' EEG/MEG data plot
function [D] = scalpData(D)

POS = get(D.PSD.handles.hfig,'position');

switch D.PSD.VIZU.modality
    case 'eeg'
        I = D.PSD.EEG.I;
    case 'meg'
        I = D.PSD.MEG.I;
    case 'other'
        I = D.PSD.other.I;
end

if isempty(I)

    uicontrol('style','text','Position',[0.14 0.84 0.7 0.04].*repmat(POS(3:4),1,2),...
        'string','No channel of this type in the data !',...
        'BackgroundColor',0.95*[1 1 1],...
        'tag','plotEEG')

else

    if strcmp(D.PSD.type,'continuous')

        uicontrol('style','text','Position',[0.14 0.84 0.7 0.04].*repmat(POS(3:4),1,2),...
            'string','Only for epoched data !',...
            'BackgroundColor',0.95*[1 1 1],...
            'tag','plotEEG')

    else
        
        D.PSD.VIZU.type = 2;
        % add buttons
        object.type = 'buttons';
        object.list = [1;5;7];
        if strcmp(D.transform.ID,'time') % only for time data!
            object.options.multSelect = 1;
            object.list = [object.list;4;6;11];
        else
            object.options.multSelect = 0;
        end
        if strcmp(D.type,'single')
            object.list = [object.list;13];
        end
        D = spm_eeg_review_uis(D,object);

        % add axes (!!give channels!!)
        switch D.PSD.VIZU.modality
            case 'eeg'
                I = D.PSD.EEG.I;
            case 'meg'
                I = D.PSD.MEG.I;
            case 'other'
                I = D.PSD.other.I;
        end
        object.type = 'axes';
        object.what = 'scalp';
        object.options.channelPlot = I;
        D = spm_eeg_review_uis(D,object);

    end

end

%% RENDERING OF INVERSE SOLUTIONS
function [D] = visuRecon(D)
POS = get(D.PSD.handles.hfig,'position');

if D.PSD.source.VIZU.current ~= 0
    
    isInv = D.PSD.source.VIZU.isInv;
    Ninv = length(isInv);
    invN = isInv(D.PSD.source.VIZU.current);
    pst = D.PSD.source.VIZU.pst;
    F = D.PSD.source.VIZU.F;
    
    % create uitabs for inverse solutions
    hInv = D.PSD.handles.tabs.hp;
    [h] = spm_uitab(hInv,D.PSD.source.VIZU.labels,...
        D.PSD.source.VIZU.callbacks,'plotEEG',find(isInv==invN));
    D.PSD.handles.SubTabs_inv = h;

    trN = D.PSD.trials.current(1);
    model = D.other.inv{isInv(1)}.inverse;
    D.PSD.source.VIZU.J = zeros(model.Nd,size(model.T,1));
    D.PSD.source.VIZU.J(model.Is,:) = model.J{trN}*model.T';
    D.PSD.source.VIZU.miJ = min(min(D.PSD.source.VIZU.J));
    D.PSD.source.VIZU.maJ = max(max(D.PSD.source.VIZU.J));

    J = D.PSD.source.VIZU.J;
    miJ = D.PSD.source.VIZU.miJ;
    maJ = D.PSD.source.VIZU.maJ;
    time = (model.pst-0).^2;
    indTime = find(time==min(time));
    gridTime = model.pst(indTime);

    % create axes
    object.type = 'axes';
    object.what = 'source';
    object.options.Ninv = Ninv;
    object.options.miJ = miJ;
    object.options.maJ = maJ;
    object.options.pst = pst;
    D = spm_eeg_review_uis(D,object);

    % plot BMC free energies in appropriate axes
    if Ninv>1
        D.PSD.handles.hbar = bar(D.PSD.handles.BMCplot,1:Ninv,F-min(F),...
            'barwidth',0.5,...
            'FaceColor',0.5*[1 1 1],...
            'tag','plotEEG');
        set(D.PSD.handles.BMCplot,'nextplot','add');
        D.PSD.handles.BMCcurrent = plot(D.PSD.handles.BMCplot,...
            find(isInv==invN),0,'ro');
        set(D.PSD.handles.BMCplot,'xtick',1:Ninv,'xticklabel',...
            D.PSD.source.VIZU.labels,'tag','plotEEG','nextplot','replace',...
            'ygrid','on','xlim',[0,Ninv+1]);
        set(get(D.PSD.handles.BMCplot,'xlabel'),'string','Inversion models');
        set(get(D.PSD.handles.BMCplot,'ylabel'),'string','Relative (to min) model free energies')
        set(get(D.PSD.handles.BMCplot,'title'),'string','Variational Bayesian model comparison',...
            'FontWeight','bold')
        drawnow
    end

    % Create mesh and related objects
    mesh.vertices = D.other.inv{invN}.mesh.tess_mni.vert;
    mesh.faces = D.other.inv{invN}.mesh.tess_mni.face;
    options.texture = J(:,indTime);
    options.hfig = D.PSD.handles.hfig;
    options.ParentAxes = D.PSD.handles.axes;
    options.tag = 'plotEEG';
    options.visible = 'off';
    [out] = spm_eeg_render(mesh,options);
    D.PSD.handles.mesh = out.handles.p;
    D.PSD.handles.BUTTONS.transp = out.handles.transp;
    D.PSD.handles.colorbar = out.handles.hc;
    D.PSD.handles.BUTTONS.ct1 = out.handles.s1;
    D.PSD.handles.BUTTONS.ct2 = out.handles.s2;
    % add spheres if constrained inverse solution
    if isfield(D.other.inv{invN}.inverse,'dipfit')...
            || ~isequal(D.other.inv{invN}.inverse.xyz,zeros(1,3))
        try
            xyz = D.other.inv{invN}.inverse.dipfit.Lpos;
            radius = D.other.inv{invN}.inverse.dipfit.radius;
        catch
            xyz = D.other.inv{invN}.inverse.xyz';
            radius = D.other.inv{invN}.inverse.rad(1);
        end
        Np  = size(xyz,2);
        [x,y,z] = sphere(20);
        axes(D.PSD.handles.axes)
        for i=1:Np
            fvc = surf2patch(x.*radius+xyz(1,i),...
                y.*radius+xyz(2,i),z.*radius+xyz(3,i));
            D.PSD.handles.dipSpheres(i) = patch(fvc);
            set(D.PSD.handles.dipSpheres(i),'facecolor',[1 1 1],...
                'edgecolor','none','facealpha',0.5,...
                'tag','dipSpheres');
        end
        axis tight
    end
    
    % plot time courses
    switch D.PSD.source.VIZU.timeCourses
        case 1
            D.PSD.source.VIZU.plotTC = plot(D.PSD.handles.axes2,...
                model.pst,J');
    end
    set(D.PSD.handles.axes2,'nextplot','add');
    D.PSD.source.VIZU.lineTime = line('parent',D.PSD.handles.axes2,...
        'xdata',[gridTime;gridTime],'ydata',[miJ;maJ]);
    set(D.PSD.handles.axes2,'nextplot','replace',...
        'ylim',[miJ;maJ],'tag','plotEEG');
    grid(D.PSD.handles.axes2,'on')
    box(D.PSD.handles.axes2,'on')
    xlabel(D.PSD.handles.axes2,'peri-stimulus time (ms)')
    ylabel(D.PSD.handles.axes2,'sources intensity')

    set(D.PSD.handles.mesh,'visible','on')
    set(D.PSD.handles.colorbar,'visible','on')
    set(D.PSD.handles.BMCplot,'visible','on')
    set(D.PSD.handles.axes2,'visible','on')

    % create buttons
    object.type = 'buttons';
    object.list = [1;7;8;10];
    object.options.multSelect = 0;
    object.options.pst = pst;
    object.options.gridTime = gridTime;
    D = spm_eeg_review_uis(D,object);

    % create info text
    object.type = 'text';
    object.what = 'source';
    D = spm_eeg_review_uis(D,object);

    set(D.PSD.handles.hfig,'userdata',D)



else

    uicontrol('style','text','Position',[0.14 0.84 0.7 0.04].*repmat(POS(3:4),1,2),...
        'string','There is no (imaging) inverse source reconstruction in this data file !',...
        'BackgroundColor',0.95*[1 1 1],...
        'tag','plotEEG')
    labels{1} = '1';
    callbacks{1} = [];
    hInv = D.PSD.handles.tabs.hp;
    spm_uitab(hInv,labels,callbacks,'plotEEG');


end



%% GET DATA INFO
function [D] = DataInfo(D)
% create info text
object.type = 'text';
object.what = 'data';
D = spm_eeg_review_uis(D,object);

try
    D.PSD.VIZU.info;
catch
    D.PSD.VIZU.info = 1;
end

% Create uitabs for channels and trials
labels = {'channels','trials','inv'};
callbacks = {'spm_eeg_review_callbacks(''visu'',''main'',''info'',1)',...,...
    'spm_eeg_review_callbacks(''visu'',''main'',''info'',2)'...
    'spm_eeg_review_callbacks(''visu'',''main'',''info'',3)'};
[h] = spm_uitab(D.PSD.handles.tabs.hp,labels,callbacks,'plotEEG',D.PSD.VIZU.info,0.9);
D.PSD.handles.infoTabs = h;

% add table and buttons
object.type = 'buttons';
object.list = 1;

switch D.PSD.VIZU.info

    case 1 % channels info
        object.list = [object.list;12;14];
        nc = length(D.channels);
        table = cell(nc,5);
        for i=1:nc
            table{i,1} = D.channels(i).label;
            table{i,2} = D.channels(i).type;
            if D.channels(i).bad
                table{i,3} = 'yes';
            else
                table{i,3} = 'no';
            end
            if ~isempty(D.channels(i).X_plot2D)
                table{i,4} = 'yes';
            else
                table{i,4} = 'no';
            end
            table{i,5} = D.channels(i).units;
        end
        colnames = {'label','type','bad','position','units'};
        [ht,hc] = spm_uitable(table,colnames);
        set(ht,'units','normalized');
        set(hc,'position',[0.1 0.05 0.55 0.7],...
            'tag','plotEEG');
        D.PSD.handles.infoUItable = ht;
        D = spm_eeg_review_uis(D,object); % this adds the buttons

    case 2 % trials info
        
        object.list = [object.list;12];
        if strcmp(D.type,'continuous')
            ne = length(D.trials(1).events);
            table = cell(ne,3);
            for i=1:ne
                table{i,1} = D.trials(1).label;
                table{i,2} = D.trials(1).events(i).type;
                table{i,3} = num2str(D.trials(1).events(i).value);
                if ~isempty(D.trials(1).events(i).duration)
                    table{i,4} = num2str(D.trials(1).events(i).duration);
                else
                    table{i,4} = [];
                end
                table{i,5} = num2str(D.trials(1).events(i).time);
                table{i,6} = 'Undefined';
                table{i,7} = num2str(D.trials(1).onset);
            end
            colnames = {'label','type','value','duration','time','bad','onset'};
            [ht,hc] = spm_uitable(table,colnames);
            set(ht,'units','normalized');
            set(hc,'position',[0.1 0.05 0.74 0.7],...
                'tag','plotEEG');
        else
            nt = length(D.trials);
            table = cell(nt,3);
            if strcmp(D.type,'single')
                for i=1:nt
                    table{i,1} = D.trials(i).label;
                    ne = length(D.trials(i).events);
                    if ne >1
                        table{i,2} = 'multiple events';
                        table{i,3} = 'multiple events';
                        table{i,4} = 'multiple events';
                        table{i,5} = 'multiple events';
                    else
                        table{i,2} = D.trials(i).events.type;
                        table{i,3} = num2str(D.trials(i).events.value);
                        if ~isempty(D.trials(i).events.duration)
                            table{i,4} = num2str(D.trials(i).events.duration);
                        else
                            table{i,4} = 'Undefined';
                        end
                        table{i,5} = num2str(D.trials(i).events.time);
                    end
                    if D.trials(i).bad
                        table{i,6} = 'yes';
                    else
                        table{i,6} = 'no';
                    end
                    table{i,7} = num2str(D.trials(i).onset);
                end
                colnames = {'label','type','value','duration','time','bad','onset'};
                [ht,hc] = spm_uitable(table,colnames);
                set(ht,'units','normalized');
                set(hc,'position',[0.1 0.05 0.74 0.7],...
                    'tag','plotEEG');

            else
                for i=1:nt
                    table{i,1} = D.trials(i).label;
                    table{i,2} = num2str(D.trials(i).repl);
                    if D.trials(i).bad
                        table{i,3} = 'yes';
                    else
                        table{i,3} = 'no';
                    end
                end
                colnames = {'label','nb of repl','bad'};
                [ht,hc] = spm_uitable(table,colnames);
                set(ht,'units','normalized');
                set(hc,'position',[0.1 0.05 0.32 0.7],...
                    'tag','plotEEG');
            end
        end
        D.PSD.handles.infoUItable = ht;
        D = spm_eeg_review_uis(D,object); % this adds the buttons
        
    case 3 % inv info
        
        object.list = [object.list;12];
        if D.PSD.source.VIZU.current ~= 0  
            isInv = D.PSD.source.VIZU.isInv;
            Ninv = length(isInv);
            table = cell(Ninv,12);
            for i=1:Ninv
                table{i,1} = [D.other.inv{isInv(i)}.comment{1}];
                table{i,2} = [D.other.inv{isInv(i)}.date(1,:)];
                table{i,3} = [D.other.inv{isInv(i)}.modality];
                table{i,4} = [D.other.inv{isInv(i)}.method];
                table{i,5} = [num2str(length(D.other.inv{isInv(i)}.inverse.Is))];
                table{i,6} = [D.other.inv{isInv(i)}.inverse.type];
                try
                    table{i,7} = [num2str(floor(D.other.inv{isInv(i)}.inverse.woi(1))),...
                        ' to ',num2str(floor(D.other.inv{isInv(i)}.inverse.woi(2))),' ms'];
                catch
                    table{i,7} = [num2str(floor(D.other.inv{isInv(i)}.inverse.pst(1))),...
                        ' to ',num2str(floor(D.other.inv{isInv(i)}.inverse.pst(end))),' ms'];
                end
                try
                    if D.other.inv{isInv(i)}.inverse.Han
                        han = 'yes';
                    else
                        han = 'no';
                    end
                    table{i,8} = [han];
                catch
                    table{i,8} = ['?'];
                end
                if isfield(D.other.inv{isInv(i)}.inverse,'lpf')
                    table{i,9} = [num2str(D.other.inv{isInv(i)}.inverse.lpf),...
                        ' to ',num2str(D.other.inv{isInv(i)}.inverse.hpf), 'Hz'];
                else
                    table{i,9} = ['default'];
                end
                table{i,10} = [num2str(size(D.other.inv{isInv(i)}.inverse.T,2))];
                table{i,11} = [num2str(D.other.inv{isInv(i)}.inverse.R2)];
                table{i,12} = [num2str(D.other.inv{isInv(i)}.inverse.F)];
            end
            colnames = {'label','date','modality','model','#dipoles','method',...
                'pst','hanning','band pass','#modes','%var','log[p(y|m)]'};
            [ht,hc] = spm_uitable(table,colnames);
            set(ht,'units','normalized');
            set(hc,'position',[0.1 0.05 0.8 0.7],...
                'tag','plotEEG');
            D.PSD.handles.infoUItable = ht;
            D = spm_eeg_review_uis(D,object); % this adds the buttons
        else
            POS = get(D.PSD.handles.infoTabs.hp,'position');
            uicontrol('style','text','units','normalized',...
                'Position',[0.14 0.84 0.7 0.04].*repmat(POS(3:4),1,2),...
            'string','There is no inverse source reconstruction in this data file !',...
            'BackgroundColor',0.95*[1 1 1],...
            'tag','plotEEG')

        end
        
end


