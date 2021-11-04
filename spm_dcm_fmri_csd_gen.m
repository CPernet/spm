function [y] = spm_dcm_fmri_csd_gen(x,v,P)
% Conversion routine for DEM inversion of DCM for CSD (fMRI)
% FORMAT [y] = spm_dcm_fmri_csd_gen(x,v,P)
%
% This routine computes the spectral response of a network of regions
% driven by  endogenous fluctuations and exogenous (experimental) inputs.
% It returns the complex cross spectra of regional responses as a
% three-dimensional array. The endogenous innovations or fluctuations are
% parameterised in terms of a (scale free) power law, in frequency space.
%
%
%__________________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging

% Karl Friston
% $Id: spm_dcm_fmri_csd_gen.m 8183 2021-11-04 15:25:19Z guillaume $


% global DCM and evaluate original generative model
%==========================================================================
global GLOBAL_DCM

% conditional prediction
%--------------------------------------------------------------------------
y  = feval(GLOBAL_DCM.M.IS,v,GLOBAL_DCM.M,GLOBAL_DCM.U);
y  = feval(GLOBAL_DCM.M.FS,y,GLOBAL_DCM.M);
y  = spm_vec(y);

