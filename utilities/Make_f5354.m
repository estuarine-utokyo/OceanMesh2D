function obj = Make_f5354( obj, tidalele, tidalvel, min_depth )
% obj = Make_f5354( obj, tidalele, tidalvel, min_depth )
% Takes a msh object and interpolates the TPXO solutions into the sponge
% tidalele and tidalvel are the filenames of TPXO ele and vel solutions
% respectively. Puts the result into the f5354 struct of the msh obj.   
%
%    min_depth [optional]: minimum depth to use for dividing the TPXO
%                          transport values by to get the velocity. 
%                          25-m by default.
% 
% Examples:
% 
% All constituents in one file for TPXO coarse solutions:
% m = Make_f5354( m, 'h_tpxo9.v1.nc', 'u_tpxo9.v1.nc' );
%
% Using ** wildcard for constituent name for the TPXO atlas: 
% m = Make_f5343( m, 'h_**_tpxo9_atlas_30_v5.nc', ...
%                    'u_**_tpxo9_atlas_30_v5.nc');
%
% Requires: m_map for projection 
%
% Created by William Pringle July 11 2018
% Updated by William Pringle June 20, 2023 for min_depth choice and update
% to the help with examples
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% check entry
if isempty(obj.b)
   error('Requires depths into the msh object to calculate the velocity') 
end

if isempty(obj.f15)
   error(['The msh object must have the f15 struct populated '...
          'with tidal boundary information']) 
end

if nargin < 4
    min_depth = 25;
end

% if we are using wildcard for each constituent in list of files 
cidx = strfind(tidalele,'**') ;
if ~isempty(cidx)
    tidalele(cidx:cidx+1) = lower(obj.f15.bountag(1).name);
    tidalvel(cidx:cidx+1) = lower(obj.f15.bountag(1).name);
end
if ~exist(tidalele,'file')
   error(['tidal database file does not exist: ' tidalele])        
end
if ~exist(tidalvel,'file')
   error(['tidal database file does not exist: ' tidalvel])        
end

ii = find(contains({obj.f13.defval.Atr(:).AttrName},'sponge'));
if isempty(ii)
   error('No sponge information to put the solutions onto')
end

% Select desired projection (using m_map)
proj = 'Mercator';
              
% Specify limits of grid
lat_min = min(obj.p(:,2)) - 1; lat_max = max(obj.p(:,2)) + 1;
lon_min = min(obj.p(:,1)) - 1; lon_max = max(obj.p(:,1)) + 1;

% doing the projection
m_proj(proj,'lon',[ lon_min lon_max],...
            'lat',[ lat_min lat_max])

%% Get sponge info
userval = obj.f13.userval.Atr(ii).Val;
nodes  = userval(1,:);
b_lon = obj.p(nodes,1); b_lat = obj.p(nodes,2);

% Do projection
[b_x,b_y] = m_ll2xy(b_lon,b_lat);             

%% Load tide data and make vectors
lon = ncread(tidalele,'lon_z');
lat = ncread(tidalele,'lat_z');
const_t = ncread(tidalele,'con');
lonu = double(ncread(tidalvel,'lon_u'));
latu = double(ncread(tidalvel,'lat_u'));
lonv = double(ncread(tidalvel,'lon_v'));
latv = double(ncread(tidalvel,'lat_v'));
L = size(lon); Lx = size(lonu); Ly = size(lonv);
if min(L) == 1
    [lon,lat] = meshgrid(lon,lat); 
end
if min(Lx) == 1
    [lonu,latu] = meshgrid(lonu,latu); 
end
if min(Ly) == 1
    [lonv,latv] = meshgrid(lonv,latv); 
end
if min(obj.p(:,1)) < 0
    % change longitude to -180-180 format if msh is in that format
    lon(lon > 180) = lon(lon > 180) - 360;
    lonu(lonu > 180) = lonu(lonu > 180) - 360;
    lonv(lonv > 180) = lonv(lonv > 180) - 360;
end
lon = reshape(lon,[],1);
lat = reshape(lat,[],1);
lonu = reshape(lonu,[],1);
latu = reshape(latu,[],1);
lonv = reshape(lonv,[],1);
latv = reshape(latv,[],1);

% Delete uncessecary portions
% First delete by square
I = find(lon < lon_min | lon > lon_max | ...
         lat < lat_min | lat > lat_max);
lon(I) = []; lat(I) = []; 
Iu = find(lonu < lon_min | lonu > lon_max | ...
          latu < lat_min | latu > lat_max);
lonu(Iu) = []; latu(Iu) = []; 
Iv = find(lonv < lon_min | lonv > lon_max | ...
          latv < lat_min | latv > lat_max);
lonv(Iv) = []; latv(Iv) = []; 

% Get 20 nearest neighbours
Kd = ourKNNsearch([lon,lat]',[b_lon, b_lat]',20);
Kd = unique(Kd);
Kdu = ourKNNsearch([lonu,latu]',[b_lon, b_lat]',20);
Kdu = unique(Kdu);
Kdv = ourKNNsearch([lonv,latv]',[b_lon, b_lat]',20);
Kdv = unique(Kdv);

% The new lon and lat vectors of data
lon = lon(Kd); lat = lat(Kd);
lonu = lonu(Kdu); latu = latu(Kdu);
lonv = lonv(Kdv); latv = latv(Kdv);

% Do the projection
[x,y] = m_ll2xy(lon,lat);        
[xu,yu] = m_ll2xy(lonu,latu);  
[xv,yv] = m_ll2xy(lonv,latv);  

% Initialize the f5354 struct
obj.f5354.nfreq = obj.f15.nbfr;
obj.f5354.ele = zeros(obj.f5354.nfreq,2,length(b_lon));
obj.f5354.vel = zeros(obj.f5354.nfreq,4,length(b_lon));
obj.f5354.nodes = nodes;

%% Now interpolate into f5354 struct
keep = true(obj.f5354.nfreq,1);
for j = 1:obj.f5354.nfreq
    % Read the current consituent
    if ~isempty(cidx)
        tidalele(cidx:cidx+1) = lower(obj.f15.bountag(j).name);
        tidalvel(cidx:cidx+1) = lower(obj.f15.bountag(j).name);
        if exist(tidalele,'file')
            const_t = ncread(tidalele,'con');
        end
    end
    % check this constituent exists
    k = find(startsWith(string(const_t'),lower(obj.f15.bountag(j).name)),1);
    if isempty(k)
       disp(['No tidal data in file for constituent ' ...
             obj.f15.bountag(1).name])
       keep(j) = false;  
       continue
    end
    % Put freqinfo into the f5354 struct
    obj.f5354.freqinfo(j).name = obj.f15.bountag(j).name;
    obj.f5354.freqinfo(j).val  = obj.f15.bountag(j).val;
    
    % Loop over ele and vel
    for loop = 1:2
        if loop == 1
            [amp_b, phs_b] = interp_h(tidalele,k,L,I,Kd,b_x,b_y,x,y);
            obj.f5354.ele(j,:,:) = [amp_b'; phs_b']; 
        elseif loop == 2
            [amp_u, phs_u, amp_v, phs_v] = interp_u(tidalvel,k,Lx,Ly,...
                                       Iu,Iv,Kdu,Kdv,b_x,b_y,xu,xv,yu,yv);
            % make amp into m/s by dividing by depth (limited to avoid high
            % values in nearshore depths)
            amp_u = amp_u./max(min_depth,obj.b(nodes'));
            amp_v = amp_v./max(min_depth,obj.b(nodes'));
            obj.f5354.vel(j,:,:) = [amp_u'; phs_u'; amp_v'; phs_v']; 
        end
    end
end
obj.f5354.nfreq = length(find(keep));
obj.f5354.ele = obj.f5354.ele(keep,:,:);
obj.f5354.vel = obj.f5354.vel(keep,:,:);
obj.f5354.freqinfo = obj.f5354.freqinfo(keep);
%EOF
end

function [amp_b, phs_b] = interp_h(fname,k,L,I,Kd,b_x,b_y,x,y)
    Re = 'hRe'; Im = 'hIm';
    try
       % Real part
       Re_now = ncread(fname,Re,[1 1 k],[L 1]);
       % Imaginary part
       Im_now = ncread(fname,Im,[1 1 k],[L 1]);
    catch
       % Real part - convert from mm to m
       Re_now = double(ncread(fname,Re))/1000;
       % Imaginary part - convert from mm to m
       Im_now = double(ncread(fname,Im))/1000;
    end
    % reshape to vector
    Re_now = reshape(Re_now,[],1);
    Im_now = reshape(Im_now,[],1);
    % Eliminate regions outside of search area and on land
    % Linear extrapolation of ocean values will be conducted where 
    % boundary nodes fall inside a land cell of the tidal data. 
    Re_now(I) = []; Re_now = Re_now(Kd); 
    K = find(Re_now == 0); Re_now(K) = []; 
    Im_now(I) = []; Im_now = Im_now(Kd); Im_now(K) = [];   
    xx = x; yy = y; xx(K) = []; yy(K) = []; 
    % Make into complex number
    Z = Re_now - Im_now*1i;
    % Do the scattered Interpolation
    F = scatteredInterpolant(xx,yy,Z,'natural');
    BZ = F(b_x,b_y);  
    % Convert real and imaginary parts to amplitude and phase
    amp_b = abs(BZ);  
    phs_b = angle(BZ)*180/pi;
    % Convert to 0 to 360;
    % phs_b that is positive 0 - 180 stays same.
    % phs_b that is negative -180 - 0 becomes 180 - 360
    phs_b(phs_b < 0) = phs_b(phs_b < 0) + 360;
end

function [amp_u, phs_u, amp_v, phs_v] = interp_u(fname,k,Lx,Ly,Iu,Iv,... 
                                               Kdu,Kdv,b_x,b_y,xu,xv,yu,yv)
    % % For U component of transport
    try 
       Re = 'URe'; Im = 'UIm';
       % For real part
       Re_now = ncread(fname,Re,[1 1 k],[Lx 1]);
       % For imaginary part
       Im_now = ncread(fname,Im,[1 1 k],[Lx 1]);
    catch
       Re = 'uRe'; Im = 'uIm';
       % For real part - convert from cm^2/s to m^2/s
       Re_now = double(ncread(fname,Re))/1e4;
       % For imaginary part - convert from cm^2/s to m^2/s
       Im_now = double(ncread(fname,Im))/1e4;
    end 
    % reshape to vector
    Re_now = reshape(Re_now,[],1);
    % reshape to vector    
    Im_now = reshape(Im_now,[],1);
    % Eliminate regions outside of search area and on land
    % Linear extrapolation of ocean values will be conducted where 
    % boundary nodes fall inside a land cell of the tidal data. 
    Re_now(Iu) = []; Re_now = Re_now(Kdu); 
    K = find(Re_now == 0); Re_now(K) = []; 
    Im_now(Iu) = []; Im_now = Im_now(Kdu); Im_now(K) = [];   
    xx = xu; yy = yu; xx(K) = []; yy(K) = []; 
    % Make into complex number
    Z = Re_now - Im_now*1i;
    % Do the scattered Interpolation
    F = scatteredInterpolant(xx,yy,Z,'natural');
    BZ = F(b_x,b_y);  
    % Convert real and imaginary parts to amplitude and phase
    amp_u = abs(BZ);  
    phs_u = angle(BZ)*180/pi;
    % Convert to 0 to 360;
    % phs_b that is positive 0 - 180 stays same.
    % phs_b that is negative -180 - 0 becomes 180 - 360
    phs_u(phs_u < 0) = phs_u(phs_u < 0) + 360;
    
    % % For the V-component of transport
    try 
       Re = 'VRe'; Im = 'VIm';
       % For real part
       Re_now = ncread(fname,Re,[1 1 k],[Ly 1]);
       % For imaginary part
       Im_now = ncread(fname,Im,[1 1 k],[Ly 1]);
    catch
       Re = 'vRe'; Im = 'vIm';
       % For real part - convert from cm^2/s to m^2/s
       Re_now = double(ncread(fname,Re))/1e4;
       % For imaginary part - convert from cm^2/s to m^2/s
       Im_now = double(ncread(fname,Im))/1e4;
    end 
    % reshape to vector
    Re_now = reshape(Re_now,[],1);
    % reshape to vector    
    Im_now = reshape(Im_now,[],1);
    % Eliminate regions outside of search area and on land
    % Linear extrapolation of ocean values will be conducted where 
    % boundary nodes fall inside a land cell of the tidal data. 
    Re_now(Iv) = []; Re_now = Re_now(Kdv); 
    K = find(Re_now == 0); Re_now(K) = []; 
    Im_now(Iv) = []; Im_now = Im_now(Kdv); Im_now(K) = [];   
    xx = xv; yy = yv; xx(K) = []; yy(K) = []; 
    % Make into complex number
    Z = Re_now - Im_now*1i;
    % Do the scattered Interpolation
    F = scatteredInterpolant(xx,yy,Z,'natural');
    BZ = F(b_x,b_y);  
    % Convert real and imaginary parts to amplitude and phase
    amp_v = abs(BZ);  
    phs_v = angle(BZ)*180/pi;
    % Convert to 0 to 360;
    % phs_b that is positive 0 - 180 stays same.
    % phs_b that is negative -180 - 0 becomes 180 - 360
    phs_v(phs_v < 0) = phs_v(phs_v < 0) + 360;
end
