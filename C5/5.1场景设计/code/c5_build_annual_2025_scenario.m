function scenario = c5_build_annual_2025_scenario()
%C5_BUILD_ANNUAL_2025_SCENARIO Build the 8760 h normal-operation case.
%
% Public/reanalysis inputs:
%   - ERA5 2025 hourly 10 m u/v wind over the declared offshore box.
%   - Copernicus Marine 2025 daily potential temperature near 50 m.
%
% Important boundary:
%   ERA5 10 m speed is sent directly to the existing V5 wind power curve,
%   following the supplied scenario report. No hub-height extrapolation is
%   applied because no supported shear model/roughness parameter was
%   supplied. The resulting wind energy is a scenario proxy, not a bankable
%   resource assessment. [需查证文献支撑]
%
% Workload, PUE coefficients, prices and all project capacities remain
% [假设值，待企业调研校准].

paths=c5_add_v5_model_paths();
dataRoot=paths.annualDataDir;
computeRoot=paths.computeInputDir;

windFile=fullfile(dataRoot,'ff31187b331bcb4c38a793470892d53e.nc');
temperatureFile=fullfile(dataRoot, ...
    'cmems_mod_glo_phy_my_0.083deg_P1D-m_1785375573011.nc');
workloadFile=fullfile(computeRoot,'green_compute_v1_168h.csv');
itParameterFile=fullfile(computeRoot,'it_system_parameters.csv');
coolingParameterFile=fullfile(computeRoot,'cooling_parameters.csv');
required={windFile,temperatureFile,workloadFile, ...
    itParameterFile,coolingParameterFile};
assert(all(cellfun(@isfile,required)), ...
    'Annual scenario is missing a required data file.');

cfg=v5_default_config('mechanism_test');
cfg.meta.parameterVersion='v5_annual_2025_normal_proxy_v1';
cfg.objective.maxENSMWh=0;
cfg.objective.minRenewableUtilization=0;
cfg.objective.temporalTieBreak='none';
cfg.solver.maxTimeS=900;

% The supplied annual scenario declares one 7.08 MW IT cluster. Convert it
% to the existing 8.20 MW facility interface used by the copied 4.6 model.
% This is not the V5 120 MW multi-cluster project design.
cfg.compute.facilityMaxMW=8.20;
cfg.compute.moduleCount=2;
cfg.compute.rampUpMWPerH=8.20;
cfg.compute.rampDownMWPerH=8.20;

% ERA5 dimensions are longitude × latitude × valid_time.
eraTimeS=double(ncread(windFile,'valid_time'));
u10=double(ncread(windFile,'u10'));
v10=double(ncread(windFile,'v10'));
latitude=double(ncread(windFile,'latitude'));
longitude=double(ncread(windFile,'longitude'));
assert(numel(eraTimeS)==8760 && all(diff(eraTimeS)==3600), ...
    'ERA5 file must contain the complete hourly 2025 UTC sequence.');
assert(all(isfinite(u10),'all') && all(isfinite(v10),'all'), ...
    'ERA5 u10/v10 contains missing or invalid values.');
eraDateTime=datetime(eraTimeS,'ConvertFrom','posixtime','TimeZone','UTC');
assert(year(eraDateTime(1))==2025 && month(eraDateTime(1))==1 && ...
    day(eraDateTime(1))==1 && hour(eraDateTime(1))==0 && ...
    year(eraDateTime(end))==2025 && month(eraDateTime(end))==12 && ...
    day(eraDateTime(end))==31 && hour(eraDateTime(end))==23, ...
    'ERA5 time coverage is not 2025-01-01 00:00 to 12-31 23:00 UTC.');
windSpeedGrid=reshape(hypot(u10,v10),[],numel(eraTimeS))';
nWind=size(windSpeedGrid,2);

% Append one endpoint because the 4.3 interval-start adapter excludes the
% final endpoint. Each ERA5 grid cell is represented as an equal-capacity
% equivalent sub-farm; this is a regional proxy, not a turbine layout.
t=(0:8760)'*3600;
windSpeed=[windSpeedGrid;windSpeedGrid(end,:)];
N=numel(t);
equivalentSubfarmRatedW=680e6/nWind;
scaleFrom17MW=equivalentSubfarmRatedW/17e6;
waveHeight=1.5*ones(N,1); % [假设值，待场址海况数据校准]

windIn=struct;
windIn.t=t;
windIn.windSpeed=windSpeed;
windIn.surgeVelocity=zeros(N,1);
windIn.pitchRate=zeros(N,1);
windIn.platformPitch=zeros(N,1);
windIn.waveHeight=waveHeight;
windIn.availabilityState=true(N,nWind);
windIn.derate=ones(N,nWind);
windIn.powerReference=inf(N,nWind);
windIn.farmPowerReference=680e6*ones(N,1);

windP=struct;
windP.ratedPower=equivalentSubfarmRatedW;
windP.ratedApparentPower=18.5e6*scaleFrom17MW;
windP.hubHeight=155;
windP.powerCurveWind=[0 3 5 7 9 11 13 24.99 25 60]';
windP.powerCurveP=[0 0 0.8 3.8 9.5 15.0 17 17 0 0]'* ...
    1e6*scaleFrom17MW;
windP.cutOutWind=25;
windP.restartWind=20;
windP.maxOperatingWave=6;
windP.restartWave=4;
windP.maxOperatingPitch=deg2rad(8);
windP.restartPitch=deg2rad(4);
windP.restartDelay=30*60;
windP.rampUp=(0.5e6/60)*scaleFrom17MW;
windP.auxiliaryPower=0.06e6*scaleFrom17MW;
windP.auxiliaryPowerStandby=0.015e6*scaleFrom17MW;
windP.arrayLossFraction=0.02;

sourceCase=struct;
sourceCase.mode='device_inputs';
sourceCase.hours=8760;
sourceCase.startTimeH=0;
sourceCase.parameterSetId='ERA5_2025_10M_DIRECT_NORMAL_PROXY_V1';
sourceCase.wind=struct( ...
    'sourceId','ERA5_2025_WIND_680MW_PROXY', ...
    'input',windIn, ...
    'parameters',windP);

% Select the nearest all-year-valid Copernicus grid point to the 4.6
% reference point (113.0 E, 21.2 N) and the depth nearest 50 m.
temperatureTimeS=double(ncread(temperatureFile,'time'));
depth=double(ncread(temperatureFile,'depth'));
temperatureLatitude=double(ncread(temperatureFile,'latitude'));
temperatureLongitude=double(ncread(temperatureFile,'longitude'));
thetao=double(ncread(temperatureFile,'thetao'));
assert(numel(temperatureTimeS)==365 && ...
    all(diff(temperatureTimeS)==86400), ...
    'Copernicus file must contain 365 daily 2025 records.');
[~,depthIndex]=min(abs(depth-50));
layer=squeeze(thetao(:,:,depthIndex,:));
validCell=all(isfinite(layer),3);
[lonGrid,latGrid]=ndgrid(temperatureLongitude,temperatureLatitude);
distance2=(lonGrid-113.0).^2+(latGrid-21.2).^2;
distance2(~validCell)=Inf;
[~,linearIndex]=min(distance2,[],'all');
assert(isfinite(distance2(linearIndex)), ...
    'No all-year-valid Copernicus cell exists near the target point.');
[lonIndex,latIndex]=ind2sub(size(validCell),linearIndex);
dailySeaTemperature=squeeze(layer(lonIndex,latIndex,:));
seaTemperature=interp1(temperatureTimeS,dailySeaTemperature, ...
    eraTimeS,'linear',NaN);
seaTemperature(eraTimeS>temperatureTimeS(end))= ...
    dailySeaTemperature(end);
assert(all(isfinite(seaTemperature)), ...
    'Hourly sea-temperature interpolation produced invalid values.');

% Expand the internal 168 h workload with the fixed seed declared in the
% scenario report. Perturbation magnitudes were not supplied and are
% explicit assumptions here.
workloadOptions=detectImportOptions(workloadFile,'Delimiter',',', ...
    'VariableNamingRule','preserve');
workload=readtable(workloadFile,workloadOptions);
assert(height(workload)==168, ...
    'The internal workload shape must contain 168 hourly rows.');
baseIndex=mod((0:8759)',168)+1;
rigidIT=0.20*double(workload.("rigid_compute_arrival")(baseIndex));
flexIT=0.20*double(workload.("flex_compute_arrival")(baseIndex));
randomState=rng;
restoreRandom=onCleanup(@()rng(randomState));
rng(2025,'twister');
weekIndex=ceil((1:8760)'/168);
weekFactor=1+0.05*randn(max(weekIndex),1);
weekFactor=min(1.15,max(0.85,weekFactor));
hourFactor=1+0.03*randn(8760,1);
hourFactor=min(1.10,max(0.90,hourFactor));
loadFactor=weekFactor(weekIndex).*hourFactor;
clear restoreRandom
rigidIT=rigidIT.*loadFactor;
flexIT=flexIT.*loadFactor;

itParams=parameter_map(itParameterFile);
coolingParams=parameter_map(coolingParameterFile);
itCapacity=itParams.it_capacity;
overflow=max(1,(rigidIT+flexIT)/itCapacity);
rigidIT=rigidIT./overflow;
flexIT=flexIT./overflow;
[pComputeBase,pueBase]=facility_power_proxy( ...
    rigidIT,seaTemperature,itParams,coolingParams);
[pComputeTotal,~]=facility_power_proxy( ...
    rigidIT+flexIT,seaTemperature,itParams,coolingParams);
[pComputeFull,pueFull]=facility_power_proxy( ...
    itCapacity*ones(8760,1),seaTemperature,itParams,coolingParams);
pComputeFlexible=max(0,pComputeTotal-pComputeBase);
assert(all(pComputeTotal<=cfg.compute.facilityMaxMW+1e-9), ...
    'Derived task power exceeds the annual compute facility boundary.');

% Repeat the common 168 h price shape. Hydrogen/compute/marine values use
% V5 mechanism-test proxies because no signed annual contract is supplied.
electricityPrice=double(workload.("electricity_price")(baseIndex));
hydrogenPrice=cfg.economic.hydrogenPriceCNYPerKgDelivered*ones(8760,1);
computePrice=cfg.economic.computePriceCNYPerMWhCS*ones(8760,1);
marineValue=cfg.economic.marineServiceValueCNYPerMWh*ones(8760,1);

in=struct;
in.sourceCase=sourceCase;
in.pCommonAuxDemandMW=cfg.internal.commonAuxDemandMW;
in.pPostPOILossMW=cfg.internal.postPOILossMW;
in.pMarineDemandMW=cfg.output.marineDemandMW;
in.pComputeBaseDemandMW=pComputeBase;
in.pComputeFlexibleMaxMW=pComputeFlexible;
in.electricityPriceCNYPerMWh=electricityPrice;
in.hydrogenPriceCNYPerKg=hydrogenPrice;
in.computePriceCNYPerMWhCS=computePrice;
in.marineServiceValueCNYPerMWh=marineValue;
in.cableSendLimitMW=cfg.output.cableSendCapacityMW;
in.gridAcceptLimitMW=cfg.output.gridAcceptCapacityMW;
in.h2PipeLimitKgPerH=cfg.hydrogen.pipeCapacityKgPerH;
in.h2ShipLimitKgPerH=cfg.hydrogen.shipCapacityKgPerH;
in.h2PipeMinimumKgPerH=0;
in.h2ShipMinimumKgPerH=0;
in.pue=pueFull;
in.gfmRequired=1;
in.availability=struct( ...
    'bess',1,'electrolyzer',1,'h2Storage',1,'compute',1, ...
    'cable',1,'h2Pipe',1,'h2Ship',1,'h2Power',0);
in.initial=struct( ...
    'bessEnergyMWh',cfg.bess.socInitial*cfg.bess.energyMWh, ...
    'h2InventoryKg',cfg.hydrogen.storageInitialKg, ...
    'electrolyzerOnlineModules',0, ...
    'electrolyzerPowerMW',0, ...
    'computePowerMW',0, ...
    'h2PowerMW',0);

scenario=struct;
scenario.meta=struct( ...
    'scenarioId','V5_ANNUAL_2025_NORMAL_PROXY_V1', ...
    'startUTC',char(string(eraDateTime(1))), ...
    'endUTC',char(string(eraDateTime(end))), ...
    'hours',8760, ...
    'operatingState','NORMAL_NO_FORCED_OUTAGE', ...
    'parameterStatus','[假设值，待企业调研校准]');
scenario.input=in;
scenario.config=cfg;
scenario.hourly=table(eraDateTime,mean(windSpeedGrid,2), ...
    min(windSpeedGrid,[],2),max(windSpeedGrid,[],2), ...
    seaTemperature,rigidIT,flexIT,pComputeBase,pComputeFlexible, ...
    pComputeFull,pueBase,pueFull,electricityPrice, ...
    'VariableNames',{'timeUTC','windSpeedMean10mMS', ...
    'windSpeedMin10mMS','windSpeedMax10mMS','seaTemperatureC', ...
    'rigidComputeArrivalMWIT','flexComputeArrivalMWIT', ...
    'computeBaseFacilityDemandMW','computeFlexibleFacilityMaxMW', ...
    'computeFullLoadFacilityMW','baseLoadPUEProxy', ...
    'fullLoadPUEProxy','electricityPriceCNYPerMWh'});
scenario.evidence=struct( ...
    'windFile',windFile, ...
    'windSourceType','EU_PUBLIC_REANALYSIS_ERA5; NOT_PROJECT_MEASUREMENT', ...
    'windRegion',struct( ...
        'west',min(longitude), ...
        'east',max(longitude), ...
        'south',min(latitude), ...
        'north',max(latitude), ...
        'gridCellCount',nWind), ...
    'windHeightBoundary','10_M_SPEED_DIRECT_TO_CURVE; [需查证文献支撑]', ...
    'temperatureFile',temperatureFile, ...
    'temperatureSourceType', ...
        'COPERNICUS_PUBLIC_REANALYSIS; NOT_PROJECT_MEASUREMENT', ...
    'temperatureSelection',struct( ...
        'targetLongitude',113.0, ...
        'targetLatitude',21.2, ...
        'selectedLongitude',temperatureLongitude(lonIndex), ...
        'selectedLatitude',temperatureLatitude(latIndex), ...
        'selectedDepthM',depth(depthIndex)), ...
    'workloadFile',workloadFile, ...
    'workloadSourceType','PROJECT_INTERNAL_168H_SHAPE', ...
    'workloadExpansion', ...
        'SEED_2025; WEEK_SIGMA_5PCT; HOUR_SIGMA_3PCT; ASSUMPTION', ...
    'pueBoundary', ...
        'FULL_LOAD_TIME_SERIES_PROXY_IN_V5; LOAD_DEPENDENCE_NOT_ENDOGENOUS');
end

function values=parameter_map(file)
options=detectImportOptions(file,'Delimiter',',', ...
    'VariableNamingRule','preserve');
options=setvartype(options,{'parameter','value'},'string');
raw=readtable(file,options);
values=struct;
for i=1:height(raw)
    values.(matlab.lang.makeValidName(raw.parameter(i)))= ...
        str2double(raw.value(i));
end
end

function [facility,pue]=facility_power_proxy( ...
    serviceMWIT,seaTemperature,it,cooling)
capacity=it.it_capacity;
loadRatio=min(1,max(0,serviceMWIT/capacity));
pIT=capacity*(it.idle_power_ratio+ ...
    (1-it.idle_power_ratio).*loadRatio.^it.power_curve_exponent);
rawCooling=cooling.cooling_fixed_power+ ...
    cooling.cooling_linear_coeff*pIT+ ...
    cooling.cooling_quadratic_coeff*pIT.^2+ ...
    cooling.temperature_coefficient*pIT.* ...
        (seaTemperature-cooling.reference_sea_temperature);
pCooling=max(cooling.cooling_power_min,rawCooling);
facility=(pIT+pCooling+cooling.fixed_auxiliary_power)/ ...
    it.distribution_efficiency;
pue=facility./max(pIT,1e-9);
end
