% End-to-end smoke test: three device models -> adapter -> Chapter 4.3.
% All curves, limits and environmental inputs are assumptions for testing.
clear; clc; rng(16);

thisDir=fileparts(mfilename('fullpath'));
v2Dir=fileparts(thisDir);
addpath(thisDir,fullfile(v2Dir,'风电模型'),fullfile(v2Dir,'光伏模型'), ...
    fullfile(v2Dir,'潮流能模型'));

dt=300; t=(0:dt:6*3600)'; N=numel(t); h=t/3600; K=4;
meter='source_collection_bus';

%% Floating wind: two turbines
wi=struct;
wi.t=t;
wi.windSpeed=[11+sin(2*pi*h/2),10.5+0.8*sin(2*pi*h/2.3)];
wi.surgeVelocity=zeros(N,2); wi.pitchRate=zeros(N,2);
wi.platformPitch=zeros(N,2); wi.waveHeight=1.5*ones(N,2);
wi.availabilityState=true(N,2); wi.derate=ones(N,2);
wi.powerReference=12e6*ones(N,2);
wi.farmPowerReference=23e6*ones(N,1);
wp=struct('powerCurveWind',[0 3 5 7 9 11 25 60]', ...
    'powerCurveP',[0 0 1 4 9 15 15 0]'*1e6,'ratedPower',15e6, ...
    'ratedApparentPower',16.5e6,'hubHeight',150,'cutOutWind',25, ...
    'restartWind',20,'maxOperatingWave',6,'restartWave',4, ...
    'maxOperatingPitch',deg2rad(8),'restartPitch',deg2rad(4), ...
    'restartDelay',600,'rampUp',0.3e6, ...
    'auxiliaryPower',0.05e6,'arrayLossFraction',0.02);
wo=floating_wind_dispatch_v2(wi,wp);

%% Floating PV: one independently tracked subarray
pvi=struct; pvi.t=t;
elev=max(0,(pi/3)*sin(pi*h/6));
pvi.sunVector=[cos(elev),zeros(N,1),sin(elev)];
pvi.dni=800*(elev>0).*sin(min(pi/2,elev)); pvi.dhi=100*(elev>0);
pvi.ghi=max(0,pvi.dni.*pvi.sunVector(:,3)+pvi.dhi);
pvi.ambientTemp=20*ones(N,1); pvi.windSpeed=6*ones(N,1);
pvi.roll=zeros(N,1); pvi.pitch=zeros(N,1); pvi.yaw=zeros(N,1);
pvi.waveHeight=1.2*ones(N,1); pvi.availabilityState=true(N,1);
pvi.powerReference=0.8e6*ones(N,1);
pp=struct('baseNormal',[0 0 1],'pdcRated',1e6,'pacRated',0.9e6, ...
    'apparentPowerRated',1e6,'gstc',1000,'tstc',25,'gammaP',-0.0035, ...
    'U0',25,'U1',6.84,'albedo',0.06,'bifaciality',0,'iamB0',0.05, ...
    'invLoadFraction',[0 0.05 0.2 0.5 1 1.3]', ...
    'invEfficiency',[0 0.90 0.97 0.985 0.985 0.98]', ...
    'auxiliaryPower',2e3,'cableLossFraction',0.015, ...
    'maxOperatingWind',30,'maxOperatingWave',4,'restartWind',20, ...
    'restartWave',2.5,'restartDelay',1800,'rampUp',0.1e6);
po=floating_pv_dispatch_v2(pvi,pp);

%% Tidal current: two devices
ti=struct; ti.time=t;
ti.axialVelocity=repmat(2.3*sin(2*pi*h/12.42),1,2);
ti.availabilityState=true(N,2); ti.significantWaveHeight=1.3*ones(N,1);
ti.farmPowerReference=1.5e6*ones(N,1);
tp=struct('ratedPower',1e6*ones(1,2),'ratedApparentPower',1.1e6*ones(1,2), ...
    'floodCurveSpeed',[0 0.7 1.2 1.8 2.5 3.5]', ...
    'floodCurvePowerPu',[0 0 0.1 0.5 1 0]', ...
    'ebbCurveSpeed',[0 0.7 1.2 1.8 2.5 3.5]', ...
    'ebbCurvePowerPu',[0 0 0.1 0.5 1 0]', ...
    'cutInSpeed',0.7,'directionDeadband',0.15,'reorientationDelay',600, ...
    'maxOperatingSpeed',3.5,'restartSpeed',3.1,'maxOperatingWave',4.5, ...
    'restartWave',3.8,'restartDelay',1200,'rampUpRate',1e6/600, ...
    'auxiliaryPowerRun',12e3,'auxiliaryPowerStandby',3e3, ...
    'collectionLossFraction',0.025);
to=tidal_current_dispatch_v2(ti,tp);

%% External forecast/scenario inputs and standardized adapters
device={wo,po,to}; ids={'WIND','PV','TIDAL'}; types={'wind','pv','tidal'};
rawRequest={wi.farmPowerReference, ...
    pvi.powerReference,ti.farmPowerReference};
sourceCell=cell(1,3); common=0.01*randn(N,K);
for j=1:3
    available=device{j}.pAvailableAtPOI;
    cfg=struct('sourceId',ids{j},'sourceType',types{j},'meterPoint',meter, ...
        'pRequested',rawRequest{j},'pForecastAvailable',0.98*available, ...
        'scenarioAvailable',max(0,available.*(1+common+0.01*randn(N,K))));
    sourceCell{j}=device_output_to_source_4_3_v3(device{j},cfg);
end
sources=[sourceCell{:}];

agg=source_aggregation_4_3_v3(sources,struct( ...
    'scenarioProbability',ones(1,K)/K,'parameterSetId','SMOKE_TEST_ONLY'));

assert(max(abs(agg.aggregate.actual-sum(agg.perSource.actual,2)))<1e-6);
assert(all(agg.perSource.actual<=agg.perSource.available+1e-6,'all'));
assert(all(agg.perSource.accepted<=agg.perSource.available+1e-6,'all'));
assert(all(agg.aggregate.sourceAuxLoad>=0));
assert(abs(sum(agg.scenario.probability)-1)<1e-12);
fprintf('Three device models -> unified adapter -> Chapter 4.3 passed.\n');
