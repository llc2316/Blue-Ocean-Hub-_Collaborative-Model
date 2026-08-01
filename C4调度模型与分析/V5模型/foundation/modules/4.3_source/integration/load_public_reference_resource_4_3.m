function data=load_public_reference_resource_4_3(dataRoot)
%LOAD_PUBLIC_REFERENCE_RESOURCE_4_3 Normalize optional public proxy resources.
% This loader reads raw NASA POWER and Open-Meteo files from somedata.
% It does not infer hub-height wind, split GHI into DNI/DHI, create tidal
% current, or convert resources to electrical power.
if nargin<1 || isempty(dataRoot)
    moduleRoot=fileparts(fileparts(mfilename('fullpath')));
    projectRoot=fileparts(fileparts(fileparts(moduleRoot)));
    dataRoot=fullfile(projectRoot,'somedata');
end
assert(ischar(dataRoot) || (isstring(dataRoot) && isscalar(dataRoot)), ...
    'dataRoot must be scalar text.');
dataRoot=char(dataRoot);
nasaPath=fullfile(dataRoot,'nasa_power_hourly_gd_offshore_20250601_20250607_utc.csv');
marinePath=fullfile(dataRoot,'open_meteo_marine_gd_offshore_20250601_20250607.csv');
assert(exist(nasaPath,'file')==2,'Missing NASA POWER public proxy: %s',nasaPath);
assert(exist(marinePath,'file')==2,'Missing Open-Meteo public proxy: %s',marinePath);

nasa=read_nasa(nasaPath);
marine=read_marine(marinePath);
assert(numel(nasa.timeUTC)==numel(marine.timeUTC) && ...
    all(nasa.timeUTC==marine.timeUTC), ...
    'NASA POWER and marine proxy timestamps are not aligned.');

N=numel(nasa.timeUTC);
nasaValid=all(isfinite([nasa.wind50MS,nasa.wind10MS,nasa.airTempC, ...
    nasa.shortwaveWhM2]),2) & all([nasa.wind50MS,nasa.wind10MS, ...
    nasa.airTempC,nasa.shortwaveWhM2]~=-999,2);
marineValid=all(isfinite([marine.waveHeightM,marine.waveDirectionDeg, ...
    marine.wavePeriodS]),2);

data=struct;
data.timeUTC=nasa.timeUTC;
data.timeH=(0:N-1)';
data.resource=table(nasa.timeUTC,nasa.wind50MS,nasa.wind10MS, ...
    nasa.airTempC,nasa.shortwaveWhM2,marine.waveHeightM, ...
    marine.waveDirectionDeg,marine.wavePeriodS,nasaValid,marineValid, ...
    nan(N,1),false(N,1), ...
    'VariableNames',{'timestampUTC','windSpeed50mMS','windSpeed10mMS', ...
    'airTemperature2mC','shortwaveDownwardWhM2','waveHeightM', ...
    'waveDirectionDeg','wavePeriodS','meteorologyQualityFlag', ...
    'marineQualityFlag','tidalCurrentMS','tidalCurrentQualityFlag'});
data.meta=struct( ...
    'siteId','GD_OFFSHORE_PUBLIC_PROXY', ...
    'latitudeDeg',21.5, ...
    'longitudeDeg',114.5, ...
    'periodUTC','2025-06-01T00:00Z/2025-06-07T23:00Z', ...
    'dataStatus','PUBLIC_PROXY_NOT_PROJECT_MEASUREMENT', ...
    'tidalStatus','MISSING_NO_CURRENT_VELOCITY_IN_SOMEDATA', ...
    'parameterNotice','[假设值，待企业调研校准]');
data.audit=struct( ...
    'nasaSourceType','政府科研数据接口（NASA POWER；MERRA-2/CERES网格数据）', ...
    'nasaURL','https://power.larc.nasa.gov/docs/services/api/temporal/hourly/', ...
    'marineSourceType','公开数据网站（Open-Meteo；非项目海测）', ...
    'marineURL','https://open-meteo.com/en/docs/marine-weather-api', ...
    'conversionStatus','RESOURCE_ONLY_NO_POWER_CONVERSION', ...
    'formulaStatus','No hub-height extrapolation, irradiance decomposition or tidal synthesis performed.');
end

function out=read_nasa(path)
fid=fopen(path,'rt');
assert(fid>=0,'Cannot open %s',path);
cleaner=onCleanup(@()fclose(fid)); %#ok<NASGU>
for k=1:13
    assert(ischar(fgetl(fid)),'Unexpected end of NASA POWER header.');
end
c=textscan(fid,repmat('%f',1,8),'Delimiter',',','CollectOutput',true);
x=c{1};
assert(size(x,2)==8 && ~isempty(x),'NASA POWER data rows are invalid.');
out.timeUTC=datetime(x(:,1),x(:,2),x(:,3),x(:,4),0,0,'TimeZone','UTC');
out.wind50MS=x(:,5);
out.wind10MS=x(:,6);
out.airTempC=x(:,7);
out.shortwaveWhM2=x(:,8);
end

function out=read_marine(path)
fid=fopen(path,'rt');
assert(fid>=0,'Cannot open %s',path);
cleaner=onCleanup(@()fclose(fid)); %#ok<NASGU>
for k=1:4
    assert(ischar(fgetl(fid)),'Unexpected end of marine-data header.');
end
c=textscan(fid,'%s%f%f%f%f%f%f','Delimiter',',');
assert(~isempty(c{1}),'Marine data rows are invalid.');
out.timeUTC=datetime(c{1},'InputFormat','yyyy-MM-dd''T''HH:mm','TimeZone','UTC');
out.waveHeightM=c{2};
out.waveDirectionDeg=c{3};
out.wavePeriodS=c{4};
end
