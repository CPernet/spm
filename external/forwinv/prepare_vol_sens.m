function [vol, sens] = prepare_vol_sens(vol, sens, varargin)

% PREPARE_VOL_SENS does some bookkeeping to ensures that the volume
% conductor model and the sensor array are appropriate. Furthermore it
% takes care of pre-computations that can be done efficiently prior to the
% leadfield calculations.
%
% The prepare_vol_sens has different roles for EEG and for MEG and % for
% the different volume conductor models. it for example projects the 3D
% electrode positions onto the skin compartment of the volume conductor to
% ensure that they do not float above the surface with a few mm due to
% mis-alignment. Or for example for MEG gradiometer sensors with a
% multisphere volume conductor it ensured that each coil of the gradiometer
% array is associated with a sphere.
%
% Use as
%   [vol, sens] = prepare_vol_sens(vol, sens, ...)
% with input arguments
%   sens   structure with gradiometer or electrode definition
%   vol    structure with volume conductor definition
%
% The vol structure represents a volume conductor model, its contents
% depend on the type of model. The sens structure represents a sensor
% arary, i.e. EEG electrodes or MEG gradiometers.
%
% Additional options should be specified in key-value pairs and can be
%   'channel'    cell-array with strings (default = 'all')
%   'order'      number, for single shell "Nolte" model (default = 10)
%
% See also READ_VOL, READ_SENS, TRANSFORM_VOL, TRANSFORM_SENS, COMPUTE_LEADFIELD

% Copyright (C) 2004-2008, Robert Oostenveld
%
% $Log: prepare_vol_sens.m,v $
% Revision 1.2  2008/04/09 20:37:32  roboos
% copied code over from ft version, not yet tested
%
% Revision 1.1  2008/03/06 09:30:36  roboos
% Created skeleton implementation according to how it should be for the forwinv toolbox, i.e. fieldtrip independent, so that it can be included in spm8.
% The functionality should be moved from the existing fieldtrip/private/prepare_vol_sens.m function into this new function.
%

% get the options
% fileformat = keyval('fileformat',  varargin);
channel = keyval('channel',  varargin);  % cell-array with channel labels
order   = keyval('order',    varargin);  % order of expansion for Nolte method; 10 should be enough for real applications; in simulations it makes sense to go higher

% set the defaults
if isempty(channel),  channel = sens.label;   end
if isempty(order),    order = 10;             end

% determine whether the input contains EEG or MEG seosors
iseeg = senstype(sens, 'eeg');
ismeg = senstype(sens, 'meg');


if ismeg && iseeg
  % this is something that could be implemented relatively easily
  error('simultaneous EEG and MEG not yet supported');

elseif ~ismeg && ~iseeg
  error('the input does not look like EEG, nor like MEG');

elseif ismeg
  % select the desired magnetometer/gradiometer channels
  % first only modify the linear combination of coils into channels
  sel = match_str(sens.label);
  sens.label = sens.label(sel);
  sens.tra   = sens.tra(sel,:);

  % remove the coils from the grad.pnt and ori field that do not contribute to any channel's output
  selcoil = find(sum(sens.tra,1)~=0);
  sens.pnt = sens.pnt(selcoil,:);
  sens.ori = sens.ori(selcoil,:);
  sens.tra = sens.tra(:,selcoil);

  switch voltype(vol)
    case 'infinite'
      % nothing to do

    case 'singlesphere'
      % nothing to do

    case 'concentric'
      % nothing to do

    case 'neuromag'
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % if the forward model is computed using the external Neuromag toolbox,
      % we have to add a selection of the channels so that the channels
      % in the forward model correspond with those in the data.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      vol.chansel = match_str(sens.label, cfg.channel);

    case 'multisphere'
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % If the volume conduction model consists of multiple spheres then we
      % have to match the channels in the gradiometer array and the volume
      % conduction model.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

      % get the local spheres for the MEG channels, this will be ordered
      % according to the ordering of the gradiometer channels
      [selsens, selvol] = match_str(sens.label, vol.label);

      % the CTF way of storing the headmodel is one-sphere-per-channel
      % whereas the FieldTrip way is one-sphere-per-coil
      Nchans = size(sens.tra,1);
      Ncoils = size(sens.tra,2);
      multisphere = [];

      % for each coil in the MEG helmet, determine the corresponding local sphere
      for i=1:Ncoils
        coilindex = find(sens.tra(:,i)~=0); % to which channel does the coil belong
        if length(coilindex)>1
          % this indicates that there are multiple channels to which this coil contributes
          % which means that sens.tra describes a synthetic higher-order gradient
          error('synthetic gradients not supported during volume conductor setup');
        end
        coillabel = sens.label{coilindex};  % what is the label of the channel
        chanindex = strmatch(coillabel, vol.label, 'exact');
        multisphere.r(i,:) = vol.r(chanindex);
        multisphere.o(i,:) = vol.o(chanindex,:);
      end
      vol = multisphere;

    case 'nolte'
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % if the forward model is computed using the code from Guido Nolte, we
      % have to initialize the volume model using the gradiometer coil
      % locations
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

      % compute the surface normals for each vertex point
      if ~isfield(vol.bnd, 'nrm')
        fprintf('computing surface normals\n');
        vol.bnd.nrm = normals(vol.bnd.pnt, vol.bnd.tri);
      end
      % estimate center and radius
      [center,radius]=sphfit([vol.bnd.pnt vol.bnd.nrm]);
      % initialize the forward calculation (only if gradiometer coils are available)
      if size(sens.pnt,1)>0
        vol.forwpar = meg_ini([vol.bnd.pnt vol.bnd.nrm], center', cfg.order, [sens.pnt sens.ori]);
      end

    otherwise
      error('unsupported volume conductor model for MEG');
  end

elseif iseeg

  % select the desired electrodes
  sel = match_str(sens.label);
  sens.label = sens.label(sel);
  sens.pnt   = sens.pnt(sel);
  % create a 2D projection and triangulation
  sens.prj   = elproj(sens.pnt);
  sens.tri   = delaunay(sens.prj(:,1), sens.prj(:,2));

  switch voltype(vol)
    case 'infinite'
      % nothing to do

    case 'singlesphere'
      % nothing to do

    case 'concentric'
      % nothing to do

    case 'bem'
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % do postprocessing of volume and electrodes in case of BEM model
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

      % project the electrodes on the skin and determine bilinear
      % interpolation matrix "tra"
      if ~isfield(vol, 'tra')
        % determine boundary corresponding with skin and brain
        if ~isfield(vol, 'skin')
          vol.skin   = find_outermost_boundary(vol.bnd);
        end
        if ~isfield(vol, 'source')
          vol.source  = find_innermost_boundary(vol.bnd);
        end
        if size(vol.mat,1)~=size(vol.mat,2) && size(vol.mat,1)==length(elec.pnt)
          fprintf('electrode transfer and system matrix were already combined\n');
        else
          fprintf('projecting electrodes on skin surface\n');
          % compute linear interpolation from triangle vertices towards electrodes
          el   = project_elec(elec.pnt, vol.bnd(vol.skin).pnt, vol.bnd(vol.skin).tri);
          tra  = transfer_elec(vol.bnd(vol.skin).pnt, vol.bnd(vol.skin).tri, el);
          % construct the transfer from all vertices (also brain/skull) towards electrodes
          vol.tra = [];
          for i=1:length(vol.bnd)
            if i==vol.skin
              vol.tra = [vol.tra, tra];
            else
              vol.tra = [vol.tra, zeros(size(el,1), size(vol.bnd(i).pnt,1))];
            end
          end
          vol.tra    = sparse(vol.tra); % convert to sparse matrix to speed up multiplications
          % incorporate the transfer and the system matrix into one matrix
          % this speeds up the subsequent repeated leadfield computations
          fprintf('combining electrode transfer and system matrix\n');
          vol.mat = vol.tra * vol.mat;
          vol = rmfield(vol, 'tra');
        end
        % ensure that the model potential will be average referenced
        vol.mat = avgref(vol.mat);
      end

    otherwise
      error('unsupported volume conductor model for EEG');
  end

end % if iseeg or ismeg

% this makes them easier to recognise
sens.type = senstype(sens);
vol.type  = voltype(vol);

