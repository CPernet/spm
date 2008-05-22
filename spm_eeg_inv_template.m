function [eegvol, megvol, fid, mesh] = spm_eeg_inv_template(Msize)

% Build the head model (meshes) from the template.
% IN
%   Msize   - index for precalculated cortical mesh density
% OUT
%   vol     - FT format for volume meshes
%   fid     - fiducials as estiated on the template image
%   mesh    - structure containing more information about the meshes
%             created, including the cortical mesh !
%
% This cicumvents the need for a structural MRI and asumes the subject has, 
% roughly the same shaped head as the template head.
%
%__________________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging

% Jeremie Mattout & Christophe Phillips
% $Id: spm_eeg_inv_template.m 1712 2008-05-22 14:30:41Z vladimir $


% check for mesh size
%--------------------------------------------------------------------------
if nargin == 0
    str   = 'Mesh size (vertices)';
    Msize = spm_input(str,'+1','3000|4000|5000|7200',[1 2 3 4]);
end

mesh.Msize = Msize;

% SPM directory of canonical anatomy
%--------------------------------------------------------------------------
Cdir     = [spm('dir') filesep 'EEGtemplates'];

% fill in fields
%==========================================================================

% head model (sMRI)
%--------------------------------------------------------------------------
mesh.template   = 1;
mesh.sMRI       = fullfile(Cdir,'smri.nii');
mesh.msk_scalp  = fullfile(Cdir,'scalp.nii');
mesh.msk_oskull = fullfile(Cdir,'oskull.nii');
mesh.msk_iskull = fullfile(Cdir,'iskull.nii');
mesh.msk_cortex = []; % If using the template, then the standard cortical 
                      % mesh will be used.


% meshes
%--------------------------------------------------------------------------
switch mesh.Msize
    case 1
        Tmesh = load(fullfile(Cdir,'wmeshTemplate_3004d.mat'));
    case 2
        Tmesh = load(fullfile(Cdir,'wmeshTemplate_4004d.mat'));
    case 3
        Tmesh = load(fullfile(Cdir,'wmeshTemplate_5004d.mat'));
    case 4
        Tmesh = load(fullfile(Cdir,'wmeshTemplate_7204d.mat'));
end

% Canonical cortical mesh
%----------------------------------------------------------------------
mesh.tess_mni.vert    = Tmesh.vert;
mesh.tess_mni.face    = uint16(Tmesh.face);

% Cortical mesh from the template
%----------------------------------------------------------------------
mesh.tess_ctx.vert    = Tmesh.vert;
mesh.tess_ctx.face    = uint16(Tmesh.face);

% Scalp, out-skull, in-skull meshes from the template
%----------------------------------------------------------------------
tmp = load(fullfile(Cdir,'standard_vol.mat'));
megvol = tmp.megvol;
eegvol = tmp.eegvol;

% datareg
%--------------------------------------------------------------------------
fid = [];
fid.pnt = eegvol.bnd(1).pnt;
fid.fid = struct('pnt',[1 85  -41; -83 -20 -65; 83 -20 -65], ...
                    'label',{{'nas','lpa','rpa'}});
fid.unit = 'mm';                              