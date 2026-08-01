function [summary,eventSummary,hourlyLedger] = ...
    run_c5_extreme_event_causal_window(outputDir)
%RUN_C5_EXTREME_EVENT_CAUSAL_WINDOW Typhoon warning/passage/recovery test.
%
% This is an event-window resilience test, not the annual result. Initial
% reserve targets, H2-to-power capacity and event dates are
% [假设值，待企业调研校准].

thisDir=fileparts(mfilename('fullpath'));
c5Root=fileparts(fileparts(thisDir));
addpath(fullfile(c5Root,'5.1场景设计','code'),thisDir);
c5_add_v5_model_paths();
if nargin<1 || strlength(string(outputDir))==0
    outputDir=fullfile(c5Root, ...
        '5.7混合最优策略短测试与年度运营分析', ...
        'results','extreme_event_causal_v2');
end

scenario=c5_build_annual_2025_multisource_scenario();
cfg=scenario.config;
cfg.h2Power.enabled=true;
cfg.h2Power.ratedMW=30; % [假设值，待企业调研校准]
[sourceInput,sourceDetail]= ...
    v5_source_adapter(cfg,scenario.input.sourceCase);
base=rmfield(scenario.input,'sourceCase');
base=merge_input(base,sourceInput);
eventAll=scenario.hourly.eventCode;
eventIdx=find(eventAll~="NORMAL");
assert(~isempty(eventIdx),'Annual scenario contains no extreme event.');
idx=max(1,eventIdx(1)-12):min(8760,eventIdx(end)+12);
base=c5_slice_input_horizon(base,idx);
eventCode=eventAll(idx);

% Pre-event reserve state. H2-to-power is enabled only for this declared
% resilience configuration; it is not silently added to normal comparison.
base.initial.bessEnergyMWh=0.80*cfg.bess.energyMWh;
base.initial.h2InventoryKg=40000;
base.initial.h2PowerMW=0;
base.availability.h2Power=ones(numel(idx),1);
strategy=struct('id','model_causal_typhoon_reserve_1h', ...
    'strategyClass','MODEL_CAUSAL_EXTREME_EVENT', ...
    'productMixEnabled',false,'eventReserveRule',true, ...
    'maxENSMWh',Inf,'objectivePrimary','economicNetCostCNY');
[summary,hourlyLedger]=c5_run_sequential_hourly( ...
    base,cfg,strategy,eventCode,false);
summary.scenarioId=string(scenario.meta.scenarioId);
summary.eventWindowStartUTC=string(scenario.hourly.timeUTC(idx(1)));
summary.eventWindowEndUTC=string(scenario.hourly.timeUTC(idx(end)));
summary.h2PowerRatedMW=cfg.h2Power.ratedMW;
summary.initialH2ReserveKg=base.initial.h2InventoryKg;
summary.initialBessSOC=base.initial.bessEnergyMWh/cfg.bess.energyMWh;

bySource=sourceDetail.availableBySourceMW(idx,:);
hourlyLedger.timeUTC=scenario.hourly.timeUTC(idx);
hourlyLedger.pWindAvailableMW=bySource(:,1);
hourlyLedger.pPVAvailableMW=bySource(:,2);
hourlyLedger.pTidalAvailableMW=bySource(:,3);
names=unique(eventCode,'stable');
rows=cell(numel(names),1);
for k=1:numel(names)
    active=eventCode==names(k);
    rows{k}=table(names(k),nnz(active), ...
        sum(hourlyLedger.eAvailableMWh(active)), ...
        sum(hourlyLedger.eSourceUsedMWh(active)), ...
        sum(hourlyLedger.eCurtailmentMWh(active)), ...
        sum(hourlyLedger.ensMWh(active)), ...
        'VariableNames',{'eventCode','hours','eAvailableMWh', ...
        'eSourceUsedMWh','eCurtailmentMWh','ensMWh'});
end
eventSummary=vertcat(rows{:});

if ~isfolder(outputDir), mkdir(outputDir); end
writetable(summary,fullfile(outputDir, ...
    'c5_extreme_event_causal_summary.csv'));
writetable(eventSummary,fullfile(outputDir, ...
    'c5_extreme_event_phase_summary.csv'));
writetable(hourlyLedger,fullfile(outputDir, ...
    'c5_extreme_event_hourly_ledger.csv'));
save(fullfile(outputDir,'c5_extreme_event_causal_results.mat'), ...
    'summary','eventSummary','hourlyLedger','strategy','idx','-v7.3');
end

function out=merge_input(out,addition)
names=fieldnames(addition);
for k=1:numel(names), out.(names{k})=addition.(names{k}); end
end
