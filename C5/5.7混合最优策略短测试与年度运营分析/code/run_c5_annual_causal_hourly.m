function [summary,eventSummary,hourlyLedger] = ...
    run_c5_annual_causal_hourly(outputDir,horizonH,resilienceMode)
%RUN_C5_ANNUAL_CAUSAL_HOURLY Annual causal V5 strategy verification.
%
% This replaces perfect-foresight/non-overlapping 48 h block dispatch for
% the principal annual test. Each solve sees one current hour plus states
% carried from the prior hour. The assumed typhoon warning invokes the
% explicit reserve rule in c5_run_sequential_hourly.

thisDir=fileparts(mfilename('fullpath'));
c5Root=fileparts(fileparts(thisDir));
addpath(fullfile(c5Root,'5.1场景设计','code'),thisDir);
c5_add_v5_model_paths();
if nargin<1 || strlength(string(outputDir))==0
    outputDir=fullfile(c5Root, ...
        '5.7混合最优策略短测试与年度运营分析', ...
        'results','annual_causal_hourly_v2');
end
if nargin<2 || isempty(horizonH), horizonH=8760; end
if nargin<3 || isempty(resilienceMode), resilienceMode=false; end
resilienceMode=logical(resilienceMode);
assert(isscalar(horizonH) && horizonH==round(horizonH) && ...
    horizonH>=1 && horizonH<=8760,'horizonH must be in [1,8760].');

scenario=c5_build_annual_2025_multisource_scenario();
cfg=scenario.config;
if resilienceMode
    cfg.h2Power.enabled=true;
    cfg.h2Power.ratedMW=30; % [假设值，待企业调研校准]
end
[sourceInput,sourceDetail]= ...
    v5_source_adapter(cfg,scenario.input.sourceCase);
base=rmfield(scenario.input,'sourceCase');
base=merge_input(base,sourceInput);
if resilienceMode
    base.initial.bessEnergyMWh=0.80*cfg.bess.energyMWh;
    base.initial.h2InventoryKg=40000;
    base.initial.electrolyzerOnlineModules=1;
    base.initial.electrolyzerPowerMW=4;
    base.availability.h2Power=ones(numel(base.timeH),1);
end
if horizonH<8760
    base=slice_horizon(base,1:horizonH);
end
eventCode=scenario.hourly.eventCode(1:horizonH);
if resilienceMode
    strategyId='model_causal_reserve_1h_annual';
    strategyClass='MODEL_CAUSAL_RESERVE_ANNUAL';
else
    strategyId='model_causal_myopic_1h_annual';
    strategyClass='MODEL_CAUSAL_MYOPIC_ANNUAL';
end
strategy=struct('id',strategyId, ...
    'strategyClass',strategyClass, ...
    'productMixEnabled',false,'eventReserveRule',true, ...
    'maxENSMWh',Inf);
[summary,hourlyLedger]=c5_run_sequential_hourly( ...
    base,cfg,strategy,eventCode,false);
summary.scenarioId=string(scenario.meta.scenarioId);
summary.extremeEventIncluded=any(eventCode~="NORMAL");
summary.resilienceMode=resilienceMode;
summary.h2PowerRatedMW=cfg.h2Power.ratedMW;
summary.initialH2ReserveKg=base.initial.h2InventoryKg;
summary.comparisonBoundary= ...
    "MODEL_ONLY; NOT_RANKED_WITH_22_FIXED_POLICIES";

bySource=sourceDetail.availableBySourceMW(1:horizonH,:);
hourlyLedger.pWindAvailableMW=bySource(:,1);
hourlyLedger.pPVAvailableMW=bySource(:,2);
hourlyLedger.pTidalAvailableMW=bySource(:,3);
eventNames=unique(eventCode,'stable');
eventRows=cell(numel(eventNames),1);
for k=1:numel(eventNames)
    idx=eventCode==eventNames(k);
    eventRows{k}=table(eventNames(k),nnz(idx), ...
        sum(hourlyLedger.eAvailableMWh(idx)), ...
        sum(hourlyLedger.eSourceUsedMWh(idx)), ...
        sum(hourlyLedger.eCurtailmentMWh(idx)), ...
        sum(hourlyLedger.ensMWh(idx)), ...
        sum(hourlyLedger.eElectricityInputMWh(idx)), ...
        sum(hourlyLedger.eHydrogenInputMWh(idx)), ...
        sum(hourlyLedger.eFlexibleComputeInputMWh(idx)), ...
        'VariableNames',{'eventCode','hours','eAvailableMWh', ...
        'eSourceUsedMWh','eCurtailmentMWh','ensMWh', ...
        'eElectricityInputMWh','eHydrogenInputMWh', ...
        'eFlexibleComputeInputMWh'});
end
eventSummary=vertcat(eventRows{:});

if ~isfolder(outputDir), mkdir(outputDir); end
writetable(summary,fullfile(outputDir, ...
    'c5_annual_causal_hourly_summary.csv'));
writetable(eventSummary,fullfile(outputDir, ...
    'c5_annual_causal_hourly_event_summary.csv'));
writetable(hourlyLedger,fullfile(outputDir, ...
    'c5_annual_causal_hourly_ledger.csv'));
scenarioMeta=scenario.meta;
scenarioEvidence=scenario.evidence;
sourceAudit=rmfield(sourceDetail,'raw');
save(fullfile(outputDir,'c5_annual_causal_hourly_results.mat'), ...
    'summary','eventSummary','hourlyLedger','strategy', ...
    'scenarioMeta','scenarioEvidence','sourceAudit','-v7.3');
end

function base=slice_horizon(base,idx)
N=numel(base.timeH);
names=fieldnames(base);
for k=1:numel(names)
    name=names{k};
    if any(strcmp(name,{'availability','initial'})), continue; end
    value=base.(name);
    if (isnumeric(value)||islogical(value)) && isvector(value) && ...
            numel(value)==N
        base.(name)=value(idx);
    end
end
names=fieldnames(base.availability);
for k=1:numel(names)
    value=base.availability.(names{k});
    if ~isscalar(value), base.availability.(names{k})=value(idx); end
end
end

function out=merge_input(out,addition)
names=fieldnames(addition);
for k=1:numel(names), out.(names{k})=addition.(names{k}); end
end
