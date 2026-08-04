function out = demo_public_baseline_v2(doPlot)
%DEMO_PUBLIC_BASELINE_V2 End-to-end public baseline smoke test.
%
% Chain:
%   wind/PV/tidal device models
%     -> device_output_to_source_4_3_v3
%     -> source_aggregation_4_3_v3 + complementarity metrics
%     -> bus_balance_4_4_v3
%     -> ideal external storage-response interface (4.5 placeholder)
%
% All numerical inputs are [ASSUMPTION - CALIBRATE WITH OEM/PROJECT DATA].
% Passing this demo proves interface consistency only; it does not validate
% equipment performance, storage sizing, frequency stability or economics.

if nargin<1, doPlot=true; end
assert(isscalar(doPlot),'doPlot must be scalar logical/numeric.');

thisDir=fileparts(mfilename('fullpath'));
moduleRoot=fileparts(thisDir);
addpath(fullfile(moduleRoot,'model','wind'),fullfile(moduleRoot,'model','pv'), ...
    fullfile(moduleRoot,'model','tidal'),fullfile(moduleRoot,'model','aggregation'), ...
    fullfile(moduleRoot,'model','demo_support'));

rng(20260716);
dt=300;
t=(0:dt:24*3600)';
hour=t/3600;
N=numel(t);
K=12;
meterPoint='source_collection_bus';

%% 1. Floating wind device model: 34 MW = 85% of the 40 MW test system
[windIn,windP]=wind_case(t,hour);
windOut=floating_wind_dispatch_v2(windIn,windP);

%% 2. Floating PV device model: 4 MW = 10%
[pvIn,pvP]=pv_case(t,hour);
pvOut=floating_pv_dispatch_v2(pvIn,pvP);

%% 3. Tidal-current device model: 2 MW = 5%
[tidalIn,tidalP]=tidal_case(t,hour);
tidalOut=tidal_current_dispatch_v2(tidalIn,tidalP);

%% 4. External forecasts/scenarios and unified 4.3 adapters
deviceOut={windOut,pvOut,tidalOut};
sourceId={'WIND_BASELINE','PV_BASELINE','TIDAL_BASELINE'};
sourceType={'wind','pv','tidal'};
rawRequest={windIn.farmPowerReference,pvIn.powerReference, ...
    tidalIn.farmPowerReference};
capacity=[34 4 2]*1e6;
poiCapacity=capacity.*[1-windP.arrayLossFraction, ...
    1-pvP.cableLossFraction,1-tidalP.collectionLossFraction];
commonScenarioError=0.015*randn(N,K);
sourceCell=cell(1,3);
for j=1:3
    available=deviceOut{j}.pAvailableAtPOI;

    % Synthetic external forecast/scenarios for interface verification only.
    forecast=max(0,0.98*available);
    scenario=min(poiCapacity(j), ...
        max(0,available.*(1+commonScenarioError+0.02*randn(N,K))));
    adapterCfg=struct('sourceId',sourceId{j},'sourceType',sourceType{j}, ...
        'meterPoint',meterPoint,'pRequested',rawRequest{j}, ...
        'pForecastAvailable',forecast,'scenarioAvailable',scenario);
    sourceCell{j}=device_output_to_source_4_3_v3(deviceOut{j},adapterCfg);
end
sources=[sourceCell{:}];

hubCfg=struct('capacity',capacity, ...
    'metricWindowsSeconds',[dt 3600 6*3600], ...
    'lowOutputFraction',0.20, ...
    'scenarioProbability',ones(1,K)/K, ...
    'parameterSetId','PUBLIC_BASELINE_V2_ASSUMPTIONS', ...
    'units','P=W; Q=var; time=s');

%% 5. Explicit 4.4 ports and ideal 4.5 interface response
ports=struct;
ports.pExport=16e6+3e6*(hour>=8 & hour<22);
ports.pElectrolyzer=4e6*ones(N,1);
ports.pCompute=3e6*ones(N,1);
ports.pMarine=0.4e6*ones(N,1);
ports.pCommonAux=0.25e6*ones(N,1);
ports.pPostPOILoss=0.20e6*ones(N,1);
ports.pOtherInjection=zeros(N,1);
ports.pGridImport=zeros(N,1);
ports.pSpill=zeros(N,1);
ports.pUnservedLoad=zeros(N,1);

withoutStorage=marine_source_hub_v3(sources,ports,struct(),hubCfg);

% Ideal, unconstrained storage response used only to verify the 4.4/4.5
% sign convention. Replace with the actual 4.5 model for sizing/control.
storage=struct('actual',withoutStorage.bus.balance.storageRequired);
out=marine_source_hub_v3(sources,ports,storage,hubCfg);
out.device=struct('wind',windOut,'pv',pvOut,'tidal',tidalOut);
out.assumptionNotice='All numerical values require OEM/project calibration.';

%% 6. Public-baseline acceptance checks
tolW=max(1e-3,1e-12*max(out.bus.ports.servedDemand));
assert(max(abs(out.source.aggregate.actual- ...
    sum(out.source.perSource.actual,2)))<tolW,'Aggregate actual-power mismatch.');
assert(max(abs(out.source.aggregate.available- ...
    sum(out.source.perSource.available,2)))<tolW,'Aggregate available-power mismatch.');
assert(all(out.source.perSource.accepted<=out.source.perSource.requested+tolW,'all'), ...
    'Accepted power exceeds raw EMS request.');
assert(all(out.source.perSource.accepted<=out.source.perSource.available+tolW,'all'), ...
    'Accepted power exceeds available power.');
assert(all(out.source.perSource.actual<=out.source.perSource.available+tolW,'all'), ...
    'Actual power exceeds available power.');
assert(all(out.source.aggregate.sourceAuxLoad>=0), ...
    'Source auxiliary load must be a separate nonnegative port.');
assert(abs(sum(out.source.scenario.probability)-1)<1e-12, ...
    'Scenario probabilities do not sum to one.');
assert(max(abs(out.bus.balance.closedMismatch))<tolW, ...
    'Ideal storage response failed to close the 4.4 power balance.');
windMode=windOut.mode(:,1);
assert(any(windMode==windOut.modeLegend.stopped), ...
    'Wind state-machine test did not trigger protective stop.');
assert(any(windMode==windOut.modeLegend.restartWait), ...
    'Wind state-machine test did not trigger restart waiting.');
assert(all(windOut.turbinePower(windMode~=windOut.modeLegend.normal,1)==0), ...
    'Wind turbine produced power in a non-normal state.');
assert(~isfield(out.source,'ports') && ~isfield(out.source,'balance'), ...
    'Chapter 4.3 output contains forbidden downstream decisions.');

fprintf('\nPUBLIC BASELINE V2: INTERFACE SMOKE TEST PASSED\n');
fprintf('Aggregate renewable energy: %.3f MWh\n', ...
    trapz(t,out.source.aggregate.actual)/3.6e9);
fprintf('Source auxiliary energy: %.3f MWh\n', ...
    trapz(t,out.source.aggregate.sourceAuxLoad)/3.6e9);
fprintf('Maximum ideal storage discharge request: %.3f MW\n', ...
    max(out.interface.busToStorage4_5.pRequired)/1e6);
fprintf('Maximum ideal storage charge request: %.3f MW\n', ...
    max(max(0,-out.interface.busToStorage4_5.pRequired))/1e6);
fprintf('All values are assumptions pending OEM/project calibration.\n\n');

if doPlot
    plot_baseline(out,windP,tidalP,hour);
end
end

function [in,p]=wind_case(t,hour)
N=numel(t); M=2;
in=struct; in.t=t;
base=10.8+1.8*sin(2*pi*hour/8)+0.7*sin(2*pi*hour/2.7);
in.windSpeed=[base,base+0.35*sin(2*pi*hour/1.9+0.4)];
in.windSpeed(hour>=7 & hour<7.5,:)=26;
in.surgeVelocity=[0.12*sin(2*pi*t/25),0.10*sin(2*pi*t/27+0.3)];
in.pitchRate=deg2rad([0.10*sin(2*pi*t/30),0.09*sin(2*pi*t/32+0.2)]);
in.platformPitch=deg2rad([1.2*sin(2*pi*t/30),1.1*sin(2*pi*t/32+0.2)]);
in.waveHeight=1.5*ones(N,M);
in.waveHeight(hour>=15 & hour<16,:)=6.5;
in.availabilityState=true(N,M);
in.availabilityState(hour>=20 & hour<21,2)=false;
in.derate=ones(N,M);
in.powerReference=inf(N,M);
in.farmPowerReference=32e6*ones(N,1);

p=struct;
p.ratedPower=17e6; p.ratedApparentPower=18.5e6; p.hubHeight=155;
p.powerCurveWind=[0 3 5 7 9 11 13 24.99 25 60]';
p.powerCurveP=[0 0 0.8 3.8 9.5 15.0 17 17 0 0]'*1e6;
p.cutOutWind=25; p.restartWind=20;
p.maxOperatingWave=6; p.restartWave=4;
p.maxOperatingPitch=deg2rad(8); p.restartPitch=deg2rad(4);
p.restartDelay=30*60; p.rampUp=0.5e6/60;
p.auxiliaryPower=0.06e6; p.auxiliaryPowerStandby=0.015e6;
p.arrayLossFraction=0.02;
end

function [in,p]=pv_case(t,hour)
N=numel(t);
day=hour>=6 & hour<=18;
elevation=-0.08*ones(N,1);
elevation(day)=(pi/2)*sin(pi*(hour(day)-6)/12);
azimuth=pi/2+pi*(hour-6)/12;
in=struct; in.t=t;
in.sunVector=[cos(elevation).*sin(azimuth), ...
    cos(elevation).*cos(azimuth),sin(elevation)];
in.dni=zeros(N,1); in.dni(day)=800*sin(pi*(hour(day)-6)/12);
in.dhi=zeros(N,1); in.dhi(day)=120;
in.ghi=max(0,in.dni.*max(0,in.sunVector(:,3))+in.dhi);
in.ambientTemp=19+5*sin(2*pi*(hour-8)/24);
in.windSpeed=6+1.2*sin(2*pi*hour/7);
in.roll=deg2rad(1.0)*sin(2*pi*t/10);
in.pitch=deg2rad(1.3)*sin(2*pi*t/12+0.3);
in.yaw=zeros(N,1); in.waveHeight=1.2*ones(N,1);
in.waveHeight(hour>=15 & hour<16)=4.5;
in.availabilityState=true(N,1);
in.powerReference=3.8e6*ones(N,1);

p=struct; p.baseNormal=[0 0 1]; p.pdcRated=4.8e6;
p.pacRated=4e6; p.apparentPowerRated=4.4e6;
p.gstc=1000; p.tstc=25; p.gammaP=-0.0035;
p.U0=25; p.U1=6.84; p.albedo=0.06; p.bifaciality=0; p.iamB0=0.05;
p.invLoadFraction=[0 0.05 0.10 0.20 0.50 1.00 1.30]';
p.invEfficiency=[0 0.90 0.95 0.97 0.985 0.985 0.98]';
p.auxiliaryPower=8e3; p.auxiliaryPowerStandby=2e3;
p.cableLossFraction=0.015;
p.maxOperatingWind=30; p.maxOperatingWave=4;
p.restartWind=20; p.restartWave=2.5; p.restartDelay=30*60;
p.rampUp=0.3e6/60;
end

function [in,p]=tidal_case(t,hour)
N=numel(t); M=2;
uBase=2.6*sin(2*pi*hour/12.42)+0.15*sin(2*pi*hour/24+0.5);
in=struct; in.time=t; in.axialVelocity=repmat(uBase,1,M);
in.platformAxialVelocity=0;
in.wakeVelocityFactor=[ones(N,1),0.94*ones(N,1)];
in.availabilityState=true(N,M);
in.availabilityState(hour>=11 & hour<12,2)=false;
in.derateFactor=ones(N,M); in.biofoulingFactor=ones(N,M);
in.significantWaveHeight=1.3*ones(N,1);
in.significantWaveHeight(hour>=15 & hour<16)=4.8;
in.farmPowerReference=1.8e6*ones(N,1);

p=struct; p.ratedPower=1e6*ones(1,M);
p.ratedApparentPower=1.1e6*ones(1,M);
p.floodCurveSpeed=[0 0.7 1.0 1.3 1.6 1.9 2.2 2.5 3.0 3.5]';
p.floodCurvePowerPu=[0 0 0.04 0.14 0.31 0.55 0.80 1 1 0]';
p.ebbCurveSpeed=p.floodCurveSpeed;
p.ebbCurvePowerPu=[0 0 0.035 0.13 0.29 0.52 0.78 0.98 1 0]';
p.cutInSpeed=0.7; p.directionDeadband=0.15;
p.reorientationDelay=10*60; p.maxOperatingSpeed=3.5; p.restartSpeed=3.1;
p.maxOperatingWave=4.5; p.restartWave=3.8; p.restartDelay=20*60;
p.rampUpRate=1e6/(10*60); p.auxiliaryPowerRun=12e3;
p.auxiliaryPowerStandby=3e3; p.collectionLossFraction=0.025;
end

function plot_baseline(out,windP,tidalP,hour)
figure('Color','w','Name','公共基线：功率曲线与状态机');
tiledlayout(2,1,'TileSpacing','compact');
nexttile;
plot(windP.powerCurveWind,windP.powerCurveP/1e6,'o-','LineWidth',1.3);
xline(windP.cutOutWind,'r--','切出');
xline(windP.restartWind,'g--','复归阈值');
xlabel('轮毂相对风速 (m/s)'); ylabel('单机功率 (MW)');
title('漂浮式风机公共基线功率曲线 [假设值，待企业调研校准]'); grid on;
nexttile;
stairs(hour,double(out.device.wind.mode(:,1)),'LineWidth',1.3);
yticks([1 2 3 4]); yticklabels({'正常','保护停机','复归等待','不可用'});
xlabel('时间 (h)'); ylabel('运行状态'); title('漂浮式风机状态机'); grid on;

figure('Color','w','Name','公共基线：多源聚合与平衡');
tiledlayout(3,1,'TileSpacing','compact');
nexttile;
plot(hour,out.source.perSource.actual/1e6,'LineWidth',1.0);
legend('风电','漂浮光伏','潮流能','Location','best');
ylabel('P (MW)'); title('三类电源POI实际注入'); grid on;
nexttile;
plot(hour,out.source.aggregate.available/1e6,'--','LineWidth',1.1); hold on;
plot(hour,out.source.aggregate.actual/1e6,'k','LineWidth',1.3);
legend('聚合可用','聚合实际','Location','best'); ylabel('P (MW)');
title('4.3多源聚合'); grid on;
nexttile;
plot(hour,out.interface.busToStorage4_5.pRequired/1e6,'LineWidth',1.2); hold on;
plot(hour,out.bus.balance.closedMismatch/1e6,'k--','LineWidth',1.0);
yline(0,'k:'); legend('储能所需功率','闭环不平衡','Location','best');
xlabel('时间 (h)'); ylabel('P (MW)'); title('4.4—4.5接口'); grid on;

figure('Color','w','Name','潮流能涨落潮功率曲线');
plot(tidalP.floodCurveSpeed,tidalP.floodCurvePowerPu,'o-','LineWidth',1.2); hold on;
plot(tidalP.ebbCurveSpeed,tidalP.ebbCurvePowerPu,'s--','LineWidth',1.2);
xlabel('流速绝对值 (m/s)'); ylabel('功率 (p.u.)');
legend('涨潮','落潮','Location','best'); title('潮流能双向功率曲线 [假设值]'); grid on;
end
