function [D,L,P] = spm_mesh_geodesic(M,i)
% Compute geodesic distances on a triangle mesh - a compiled routine
% FORMAT [D,L,P] = spm_mesh_geodesic(M,i)
% M      - a patch structure with n vertices
% i      - index of source vertices
%
% D      - a [nx1] vector of geodesic distances from i
% L      - a [nx1] vector of index of the nearest source (Voronoi)
% P      - a [nx1] cell vector of [px3] coordinates of geodesic lines
%__________________________________________________________________________
%
% Based on C++ library: https://code.google.com/archive/p/geodesic/
% Copyright (C) 2008 Danil Kirsanov, MIT License
% [1] J.S.B. Mitchell, D.M. Mount, and C.H. Papadimitriou, The discrete
%     geodesic problem, SIAM Journal on Computing,16(4) (1987), 647–66.
% [2] J. O'Rourke, Computational Geometry Column 35, SIGACT News, 30(2)
%     Issue #111 (1999
%__________________________________________________________________________
% Copyright (C) 2010-2020 Wellcome Centre for Human Neuroimaging

% Guillaume Flandin
% $Id: spm_mesh_geodesic.m 7886 2020-07-03 16:06:55Z guillaume $

% % A previous version of this function was computing approximate
% % geodesic distances using Dijkstra algorithm
% % FORMAT D = spm_mesh_geodesic(M,i,order)
% % M        - a patch structure or an adjacency matrix
% % i        - indices of starting points
% % order    - type of distance for 1st order neighbours {0, [1]}
% %
% % D        - a [nx1] vector of geodesic distances from i
%
% if nargin < 3, order = 1; end
%
% [N, D] = spm_mesh_neighbours(M,order);
%
% D      = spm_mesh_utils('dijkstra',N,D,i,Inf);

%-This is merely the help file for the compiled routine
error('spm_mesh_geodesic.cpp not compiled - see Makefile')