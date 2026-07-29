function scenario = v5_build_all_channel_weather_task_scenario()
%V5_BUILD_ALL_CHANNEL_WEATHER_TASK_SCENARIO Build the 48 h V5 mechanism case.
%
% The case is derived from the V4 48 h all-channel stress-test concept, but
% supplies explicit 5 min wind-field, irradiance, temperature, wave and
% tidal-current inputs to the embedded 4.3 device models. It is designed to
% activate interfaces in a traceable order; it is not a hindcast, resource
% assessment or engineering design.
%
% All numerical values in this file are:
% [假设值，待企业调研校准]

hours=48;
sourceStepS=300;
t=(0:sourceStepS:hours*3600)';
hour=t/3600;
N=numel(t);
dispatchTimeH=(0:hours-1)';

phase=repmat("",hours,1);
phase(1:6)="P1_SHORTAGE_DISCHARGE";
phase(7:12)="P2_PV_RISE_CHARGE";
phase(13:18)="P3_COMPUTE_START";
phase(19:24)="P4_CABLE_SATURATION";
phase(25:30)="P5_ELECTROLYSIS_START";
phase(31:36)="P6_ALL_CHANNELS_CURTAIL";
phase(37:40)="P7_RENEWABLE_DROP";
phase(41:48)="P8_RECOVERY_TERMINAL";

phaseName=[ ...
    "新能源不足与电池放电"; ...
    "光伏上升与电池充电"; ...
    "算力任务到达并启动"; ...
    "受端放开且海缆达到上限"; ...
    "氢价窗口打开并启动制氢"; ...
    "储能满、算氢缆满载后弃电"; ...
    "风光骤降、柔性负荷削减与电池放电"; ...
    "资源恢复并回补期末电量"];
phaseCode=["P1_SHORTAGE_DISCHARGE";"P2_PV_RISE_CHARGE"; ...
    "P3_COMPUTE_START";"P4_CABLE_SATURATION"; ...
    "P5_ELECTROLYSIS_START";"P6_ALL_CHANNELS_CURTAIL"; ...
    "P7_RENEWABLE_DROP";"P8_RECOVERY_TERMINAL"];
startH=[0;6;12;18;24;30;36;40];
endH=[5;11;17;23;29;35;39;47];
scenario.phaseTable=table(phaseCode,phaseName,startH,endH);

% Hourly mechanism-test weather states. Values are held over each source
% interval so the hour-36 wind/irradiance collapse is a true step event.
windMeanHour=[ ...
    4.3 4.2 4.1 4.0 4.2 4.3, ...
    4.0 4.0 3.9 3.9 3.8 4.2, ...
    6.0 6.5 7.0 7.4 7.8 8.3, ...
    8.55 8.60 8.65 8.70 8.75 8.80, ...
    9.15 9.30 9.45 9.55 9.55 9.55, ...
    12.2 12.4 12.6 12.8 13.0 13.0, ...
    4.2 4.0 4.1 4.3, ...
    6.4 6.6 6.8 7.0 7.2 7.4 7.5 7.6]';
dniHour=[ ...
    zeros(1,6), ...
    0 10 20 40 80 400, ...
    850 800 650 450 200 50, ...
    zeros(1,12), ...
    20 100 250 450 650 800, ...
    40 30 50 20, ...
    zeros(1,8)]';
dhiHour=[ ...
    zeros(1,6), ...
    0 2 5 10 20 80, ...
    125 120 100 75 40 15, ...
    zeros(1,12), ...
    10 25 45 70 95 120, ...
    25 20 25 15, ...
    zeros(1,8)]';
ambientTempHour=[ ...
    20 19.5 19 18.5 18.5 19, ...
    20 21 22 23 24 25, ...
    26 27 27.5 27 26 25, ...
    24 23 22 21.5 21 20.5, ...
    20 19.5 19 18.5 18.5 19, ...
    20 21 22 23 24 25, ...
    23 22 21 20.5, ...
    20 19.5 19 18.5 18.5 19 19.5 20]';
seaTempHour=[ ...
    linspace(20.0,20.6,24),linspace(20.5,20.0,24)]';
waveHeightHour=[ ...
    1.8*ones(1,12),1.6*ones(1,12), ...
    1.7*ones(1,6),2.0*ones(1,6), ...
    3.5 3.7 3.4 3.0, ...
    2.6 2.4 2.2 2.0 1.9 1.8 1.8 1.8]';
tidalSpeedHour=[ ...
    0.30 0.35 0.40 0.45 0.50 0.55, ...
    0.45 0.50 0.55 0.60 0.65 0.80, ...
    1.20 1.30 1.40 1.50 1.40 1.20, ...
    0.55 0.50 0.45 0.40 0.45 0.55, ...
    0.90 1.00 1.10 1.20 1.30 1.40, ...
    1.80 1.90 2.00 2.10 2.20 2.20, ...
    0.35 0.30 0.40 0.50, ...
    1.10 1.20 1.30 1.40 1.50 1.50 1.40 1.30]';

windMean=hour_hold(windMeanHour,hour);
dni=hour_hold(dniHour,hour);
dhi=hour_hold(dhiHour,hour);
ambientTemp=hour_hold(ambientTempHour,hour);
seaTemp=hour_hold(seaTempHour,hour);
waveHeight=hour_hold(waveHeightHour,hour);
tidalSpeed=hour_hold(tidalSpeedHour,hour);

% Spatially coherent wind field for forty 17 MW turbines. Small offsets and
% deterministic gusts test aggregation without changing the phase order.
nWind=40;
spatial=linspace(-0.25,0.25,nWind);
gust=0.10*sin(2*pi*t/(35*60))+0.05*sin(2*pi*t/(11*60));
windField=max(0,windMean+gust+spatial);
surgeVelocity=0.10*sin(2*pi*t/25);
pitchRate=deg2rad(0.08)*sin(2*pi*t/30);
platformPitch=deg2rad(0.8+0.15*waveHeight).* ...
    sin(2*pi*t/32);

windIn=struct;
windIn.t=t;
windIn.windSpeed=windField;
windIn.surgeVelocity=surgeVelocity;
windIn.pitchRate=pitchRate;
windIn.platformPitch=platformPitch;
windIn.waveHeight=waveHeight;
windIn.availabilityState=true(N,nWind);
windIn.derate=ones(N,nWind);
windIn.powerReference=inf(N,nWind);
windIn.farmPowerReference=680e6*ones(N,1);

windP=struct;
windP.ratedPower=17e6;
windP.ratedApparentPower=18.5e6;
windP.hubHeight=155;
windP.powerCurveWind=[0 3 5 7 9 11 13 24.99 25 60]';
windP.powerCurveP=[0 0 0.8 3.8 9.5 15.0 17 17 0 0]'*1e6;
windP.cutOutWind=25;
windP.restartWind=20;
windP.maxOperatingWave=6;
windP.restartWave=4;
windP.maxOperatingPitch=deg2rad(8);
windP.restartPitch=deg2rad(4);
windP.restartDelay=30*60;
windP.rampUp=0.5e6/60;
windP.auxiliaryPower=0.06e6;
windP.auxiliaryPowerStandby=0.015e6;
windP.arrayLossFraction=0.02;

% Sun position is used only for incidence geometry. The explicit DNI/DHI
% series creates the day-2 cloud-collapse event.
localHour=mod(hour,24);
daylight=localHour>=6 & localHour<=18;
elevation=-0.08*ones(N,1);
elevation(daylight)=(pi/2)*sin(pi*(localHour(daylight)-6)/12);
azimuth=pi/2+pi*(localHour-6)/12;
sunVector=[cos(elevation).*sin(azimuth), ...
    cos(elevation).*cos(azimuth),sin(elevation)];
ghi=max(0,dni.*max(0,sunVector(:,3))+dhi);

pvIn=struct;
pvIn.t=t;
pvIn.dni=dni;
pvIn.dhi=dhi;
pvIn.ghi=ghi;
pvIn.sunVector=sunVector;
pvIn.ambientTemp=ambientTemp;
pvIn.windSpeed=max(2,0.55*windMean);
pvIn.roll=deg2rad(0.6*waveHeight).*sin(2*pi*t/10);
pvIn.pitch=deg2rad(0.8*waveHeight).*sin(2*pi*t/12+0.3);
pvIn.yaw=zeros(N,1);
pvIn.waveHeight=waveHeight;
pvIn.availabilityState=true(N,1);
pvIn.powerReference=80e6*ones(N,1);

pvP=struct;
pvP.baseNormal=[0 0 1];
pvP.pdcRated=96e6;
pvP.pacRated=80e6;
pvP.apparentPowerRated=88e6;
pvP.gstc=1000;
pvP.tstc=25;
pvP.gammaP=-0.0035;
pvP.U0=25;
pvP.U1=6.84;
pvP.albedo=0.06;
pvP.bifaciality=0;
pvP.iamB0=0.05;
pvP.invLoadFraction=[0 0.05 0.10 0.20 0.50 1.00 1.30]';
pvP.invEfficiency=[0 0.90 0.95 0.97 0.985 0.985 0.98]';
pvP.auxiliaryPower=0.16e6;
pvP.auxiliaryPowerStandby=0.04e6;
pvP.cableLossFraction=0.015;
pvP.maxOperatingWind=30;
pvP.maxOperatingWave=4;
pvP.restartWind=20;
pvP.restartWave=2.5;
pvP.restartDelay=30*60;
pvP.rampUp=6e6/60;

nTidal=40;
tidalIn=struct;
tidalIn.time=t;
tidalIn.axialVelocity=tidalSpeed+linspace(-0.04,0.04,nTidal);
tidalIn.platformAxialVelocity=0;
tidalIn.wakeVelocityFactor=linspace(1.00,0.94,nTidal);
tidalIn.availabilityState=true(N,nTidal);
tidalIn.derateFactor=ones(N,nTidal);
tidalIn.biofoulingFactor=ones(N,nTidal);
tidalIn.significantWaveHeight=waveHeight;
tidalIn.farmPowerReference=40e6*ones(N,1);

tidalP=struct;
tidalP.ratedPower=1e6*ones(1,nTidal);
tidalP.ratedApparentPower=1.1e6*ones(1,nTidal);
tidalP.floodCurveSpeed=[0 0.7 1.0 1.3 1.6 1.9 2.2 2.5 3.0 3.5]';
tidalP.floodCurvePowerPu=[0 0 0.04 0.14 0.31 0.55 0.80 1 1 0]';
tidalP.ebbCurveSpeed=tidalP.floodCurveSpeed;
tidalP.ebbCurvePowerPu=[0 0 0.035 0.13 0.29 0.52 0.78 0.98 1 0]';
tidalP.cutInSpeed=0.7;
tidalP.directionDeadband=0.15;
tidalP.reorientationDelay=10*60;
tidalP.maxOperatingSpeed=3.5;
tidalP.restartSpeed=3.1;
tidalP.maxOperatingWave=4.5;
tidalP.restartWave=3.8;
tidalP.restartDelay=20*60;
tidalP.rampUpRate=1e6/(10*60);
tidalP.auxiliaryPowerRun=12e3;
tidalP.auxiliaryPowerStandby=3e3;
tidalP.collectionLossFraction=0.025;

sourceCase=struct;
sourceCase.mode='device_inputs';
sourceCase.hours=hours;
sourceCase.startTimeH=0;
sourceCase.parameterSetId='V5_ALL_CHANNEL_WEATHER_TASK_48H_ASSUMPTION_V1';
sourceCase.wind=struct('sourceId','WIND_680MW_MECHANISM', ...
    'input',windIn,'parameters',windP);
sourceCase.pv=struct('sourceId','FPV_80MW_MECHANISM', ...
    'input',pvIn,'parameters',pvP);
sourceCase.tidal=struct('sourceId','TIDAL_40MW_MECHANISM', ...
    'input',tidalIn,'parameters',tidalP);

% Workload and value windows are declared inputs, not hard-coded dispatch
% priorities. Firm compute appears at hour 12; flexible batches remain
% deferrable and are removed from the recovery window.
pComputeBase=zeros(hours,1);
pComputeBase(13:end)=20;
pComputeFlex=zeros(hours,1);
pComputeFlex(13:40)=100;

electricityPrice=zeros(hours,1);
electricityPrice(13:18)=250;
electricityPrice(19:36)=700;
electricityPrice(37:40)=200;
hydrogenPrice=zeros(hours,1);
hydrogenPrice(25:36)=50;
computePrice=zeros(hours,1);
computePrice(13:36)=900;
computePrice(37:40)=100;

in=struct;
in.sourceCase=sourceCase;
in.pCommonAuxDemandMW=0.25;
in.pPostPOILossMW=0.20;
in.pMarineDemandMW=18;
in.pComputeBaseDemandMW=pComputeBase;
in.pComputeFlexibleMaxMW=pComputeFlex;
in.electricityPriceCNYPerMWh=electricityPrice;
in.hydrogenPriceCNYPerKg=hydrogenPrice;
in.computePriceCNYPerMWhCS=computePrice;
in.marineServiceValueCNYPerMWh=300;
in.cableSendLimitMW=200;
in.gridAcceptLimitMW=200;
in.h2PipeLimitKgPerH=900;
in.h2ShipLimitKgPerH=900;
in.h2PipeMinimumKgPerH=0;
in.h2ShipMinimumKgPerH=0;
in.pue=1.076;
electrolyzerAvailability=[zeros(24,1);ones(24,1)];
in.availability=struct('bess',1, ...
    'electrolyzer',electrolyzerAvailability,'h2Storage',1, ...
    'compute',1,'cable',1,'h2Pipe',1,'h2Ship',1,'h2Power',0);
in.initial=struct( ...
    'bessEnergyMWh',112, ...
    'h2InventoryKg',0, ...
    'electrolyzerOnlineModules',0, ...
    'electrolyzerPowerMW',0, ...
    'computePowerMW',0, ...
    'h2PowerMW',0);

cfg=v5_default_config('mechanism_test');
cfg.meta.parameterVersion='v5_all_channel_weather_task_48h_assumption_v1';
cfg.bess.socInitial=in.initial.bessEnergyMWh/cfg.bess.energyMWh;
cfg.objective.temporalTieBreak='deferCurtailment';

hourlyWind=interval_mean(windMean,sourceStepS,hours);
hourlyDni=interval_mean(dni,sourceStepS,hours);
hourlyDhi=interval_mean(dhi,sourceStepS,hours);
hourlyGhi=interval_mean(ghi,sourceStepS,hours);
hourlyAmbient=interval_mean(ambientTemp,sourceStepS,hours);
hourlySea=interval_mean(seaTemp,sourceStepS,hours);
hourlyWave=interval_mean(waveHeight,sourceStepS,hours);
hourlyTidal=interval_mean(tidalSpeed,sourceStepS,hours);
scenario.hourly=table(dispatchTimeH,phase,hourlyWind,hourlyDni, ...
    hourlyDhi,hourlyGhi,hourlyAmbient,hourlySea,hourlyWave, ...
    hourlyTidal,pComputeBase,pComputeFlex,electricityPrice, ...
    hydrogenPrice,computePrice, ...
    'VariableNames',{'timeH','phase','windMeanMS','dniWPerM2', ...
    'dhiWPerM2','ghiWPerM2','ambientTempC','seaWaterTempC', ...
    'waveHeightM','tidalSpeedMS','computeBaseDemandMW', ...
    'computeFlexibleMaxMW','electricityPriceCNYPerMWh', ...
    'hydrogenPriceCNYPerKg','computePriceCNYPerMWhCS'});
scenario.input=in;
scenario.config=cfg;
scenario.meta=struct( ...
    'scenarioId','V5_ALL_CHANNEL_WEATHER_TASK_48H', ...
    'horizonH',hours, ...
    'sourceResolutionMin',sourceStepS/60, ...
    'dispatchResolutionH',cfg.time.dispatchStepH, ...
    'referenceType','V4 internal all-channel mechanism-test prototype', ...
    'dataSourceType','synthetic mechanism-test sequence', ...
    'dataStatus','[假设值，待企业调研校准]', ...
    'formulaStatus',[ ...
        '4.3 device formulas inherited from foundation evidence; ', ...
        'no new physical formula introduced']);
end

function value=hour_hold(hourlyValue,hour)
knots=(0:numel(hourlyValue))';
extended=[hourlyValue(:);hourlyValue(end)];
value=interp1(knots,extended,hour,'previous');
end

function y=interval_mean(x,stepS,hours)
samplesPerHour=round(3600/stepS);
usable=x(1:hours*samplesPerHour);
y=mean(reshape(usable,samplesPerHour,hours),1)';
end
