function ft_write_headshape(filename, bnd, varargin)

% FT_WRITE_HEADSHAPE writes a head surface, cortical sheet or
% geometrical descrition of the volume conduction model or source
% model to a file for further processing in external software.
%
% Use as
%   ft_write_headshape(filename, bnd, ...)
% or
%   ft_write_headshape(filename, pos, ...)
% where the bnd is a structure containing the vertices and triangles
% (bnd.pnt and bnd.tri), or where pnt describes the surface or source
% points.
%
% Optional input arguments should be specified as key-value pairs and
% should include
%   format		= string, see below
%
% Supported output formats are
%   'mne_tri'		MNE surface desciption in ascii format
%   'mne_pos'		MNE source grid in ascii format, described as 3D points
%
% See also FT_READ_HEADSHAPE

% Copyright (C) 2011, Lilla Magyari & Robert Oostenveld
%
% $Rev: 4781 $

fileformat = ft_getopt(varargin,'format','unknown');

if ~isstruct(bnd)
  bnd.pnt = bnd;
end

fid = fopen(filename, 'wt');

switch fileformat
  case 'mne_pos'
    % convert to milimeter
    bnd = ft_convert_units(bnd, 'mm');
    n=size(bnd.pnt,1);
    for line = 1:n
      num = bnd.pnt(line,1);
      fprintf(fid, '%-1.0f ',num);
      num = bnd.pnt(line,2);
      fprintf(fid, '%-1.0f ',num);
      num = bnd.pnt(line,3);
      fprintf(fid, '%-1.0f\n',num);
    end
    
  case 'mne_tri'
    % convert to milimeter
    bnd = ft_convert_units(bnd, 'mm');
    n=size(bnd.pnt,1);
    fprintf(fid, '%-1.0f\n',n);
    for line = 1:n
      num=bnd.pnt(line,1);
      fprintf(fid,'%g ', num);
      num = bnd.pnt(line,2);
      fprintf(fid, '%g ',num);
      num = bnd.pnt(line,3);
      fprintf(fid, '%g\n',num);
    end
    n=size(bnd.tri,1);
    fprintf(fid, '%-1.0f\n',n);
    for line = 1:n
      num=bnd.tri(line,1);
      fprintf(fid,'%-1.0f ', num);
      num = bnd.tri(line,2);
      fprintf(fid, '%-1.0f ',num);
      num = bnd.tri(line,3);
      fprintf(fid, '%-1.0f\n',num);
    end
    
  case 'off'
    write_off(filename,bnd.pnt,bnd.tri);
    
  case 'vista'
    if ft_hastoolbox('simbio',1)
      % no conversion needed (works in voxel coordinates)
      if isfield(bnd,'hex')
        write_vista_mesh(filename,bnd.pnt,bnd.hex,bnd.index); % bnd.tensor
      elseif isfield(bnd,'tet')
        write_vista_mesh(filename,bnd.pnt,bnd.tet,bnd.index);
      else
        error('unknown format')
      end
    else
      error('You need Simbio/Vista toolbox to write a .v file')
    end
    
  case 'tetgen'
    % the third argument is the element type. At the moment only type 302
    % (triangle) is supported
    surf_to_tetgen(filename, bnd.pnt, bnd.tri, 302*ones(size(bnd.tri,1),1),[],[]);
    
  case []
    error('you must specify the output format');
    
  otherwise
    error('unsupported output format "%s"');
end

fclose(fid);
