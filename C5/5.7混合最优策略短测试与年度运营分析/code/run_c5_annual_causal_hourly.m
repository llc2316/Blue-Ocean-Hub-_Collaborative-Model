function [summary,eventSummary,hourlyLedger,results] = ...
    run_c5_annual_causal_hourly(outputDir,horizonH,parallelWorkers,caseIds)
%RUN_C5_ANNUAL_CAUSAL_HOURLY Causal annual verification; online policy by default.
%
% The full 8760 h run contains the assumed warning/passage/recovery event
% embedded in the annual scenario. Every hour is solved sequentially. BESS,
% hydrogen, electrolyzer and compute states are carried from the preceding
% hour; no state is reset or externally replenished before the event.

thisDir=fileparts(mfilename('fullpath'));
c5Root=fileparts(fileparts(thisDir));
addpath(fullfile(c5Root,'5.1场景设计','code'),thisDir);
c5_add_v5_model_paths();
if nargin<1 || strlength(string(outputDir))==0
    outputDir=fullfile(c5Root, ...
        '5.7混合最优策略短测试与年度运营分析', ...
        'results','annual_8760h_online_strategy_extreme');
end
if nargin<2 || isempty(horizonH), horizonH=8760; end
if nargin<3 || isempty(parallelWorkers), parallelWorkers=1; end
if nargin<4 || isempty(caseIds)
    caseIds="model_online_prior_posterior_event_aware";
end
assert(isscalar(horizonH) && horizonH==round(horizonH) && ...
    horizonH>=1 && horizonH<=8760,'horizonH must be in [1,8760].');
assert(isscalar(parallelWorkers) && parallelWorkers==round(parallelWorkers) && ...
    parallelWorkers>=1,'parallelWorkers must be a positive integer.');

scenario=c5_build_annual_2025_multisource_scenario();
cfg=scenario.config;
cfg.h2Power.enabled=true;
cfg.h2Power.ratedMW=30; % [假设值，待企业调研校准]
[sourceInput,sourceDetail]=v5_source_adapter(cfg,scenario.input.sourceCase);
base=rmfield(scenario.input,'sourceCase');
base=merge_input(base,sourceInput);
base.pWindAvailableMW=sourceDetail.availableBySourceMW(:,1);
base.pPVAvailableMW=sourceDetail.availableBySourceMW(:,2);
base.pTidalAvailableMW=sourceDetail.availableBySourceMW(:,3);
base.availability.h2Power=ones(numel(base.timeH),1);
initialStateAudit=base.initial;
if horizonH<8760
    base=c5_slice_input_horizon(base,1:horizonH);
end
eventCode=scenario.hourly.eventCode(1:horizonH);

strategies=c5_four_strategy_specs();
strategies=select_strategies(strategies,caseIds);
[summary,hourlyLedger,results]=run_strategy_set( ...
    base,cfg,strategies,eventCode,parallelWorkers);
onlineId="model_online_prior_posterior_event_aware";
if numel(strategies)==4
    comparisonSet="THREE_ASSET_BASELINES_PLUS_ONE_ONLINE_PRIOR_POSTERIOR";
elseif isscalar(strategies) && string(strategies{1}.id)==onlineId
    comparisonSet="ONLINE_PRIOR_POSTERIOR_ONLY";
else
    comparisonSet="SELECTED_SUBSET_OF_CANONICAL_FOUR_STRATEGIES";
end
summary.comparisonSet=repmat(comparisonSet,height(summary),1);
summary.scenarioId=repmat(string(scenario.meta.scenarioId),height(summary),1);
summary.extremeEventIncluded=repmat(any(eventCode~="NORMAL"), ...
    height(summary),1);
summary.stateCarryRule=repmat( ...
    "PREVIOUS_HOUR_TERMINAL_STATE; NO_EVENT_RESET_OR_INJECTION", ...
    height(summary),1);
summary.h2InventoryMinimumPolicy=repmat( ...
    "PHYSICAL_NONNEGATIVITY_ONLY; NO_OPERATIONAL_FLOOR",height(summary),1);
summary.h2PowerRatedMW=repmat(cfg.h2Power.ratedMW,height(summary),1);
summary.initialBessEnergyMWh=repmat(initialStateAudit.bessEnergyMWh, ...
    height(summary),1);
summary.initialH2InventoryKg=repmat(initialStateAudit.h2InventoryKg, ...
    height(summary),1);
baseForDemandAudit=v5_validate_and_normalize_input(cfg,base);
demandAudit=summarize_demand_by_event(baseForDemandAudit,eventCode);
totalCriticalDemandMWh=sum(demandAudit.totalCriticalDemandMWh);
summary.totalCriticalDemandMWh=repmat( ...
    totalCriticalDemandMWh,height(summary),1);
summary.criticalServiceRate=1-summary.ensMWh/totalCriticalDemandMWh;
eventSummary=summarize_by_event(hourlyLedger);
eventSummary=attach_critical_service_rate(eventSummary,demandAudit);

if ~isfolder(outputDir), mkdir(outputDir); end
if comparisonSet=="ONLINE_PRIOR_POSTERIOR_ONLY"
    resultStem='c5_annual_online_strategy';
else
    resultStem='c5_annual_four_strategy';
end
writetable(summary,fullfile(outputDir,[resultStem '_summary.csv']));
writetable(eventSummary,fullfile(outputDir, ...
    [resultStem '_event_summary.csv']));
writetable(demandAudit,fullfile(outputDir, ...
    [resultStem '_demand_audit.csv']));
writetable(hourlyLedger,fullfile(outputDir,[resultStem '_hourly.csv']));
scenarioMeta=scenario.meta;
scenarioEvidence=scenario.evidence;
sourceAudit=rmfield(sourceDetail,'raw');
save(fullfile(outputDir,[resultStem '_results.mat']), ...
    'summary','eventSummary','demandAudit','hourlyLedger','strategies', ...
    'scenarioMeta','scenarioEvidence','sourceAudit', ...
    'initialStateAudit','horizonH','-v7.3');
end

function demandAudit=summarize_demand_by_event(base,eventCode)
events=unique(eventCode,'stable');
rows=cell(numel(events),1);
for i=1:numel(events)
    idx=eventCode==events(i);
    rows{i}=table(events(i),nnz(idx), ...
        sum(base.pInternalDemandMW(idx)), ...
        sum(base.pMarineDemandMW(idx)), ...
        sum(base.pComputeBaseDemandMW(idx)), ...
        'VariableNames',{'eventCode','hours','internalDemandMWh', ...
        'marineDemandMWh','computeBaseDemandMWh'});
end
demandAudit=vertcat(rows{:});
demandAudit.totalCriticalDemandMWh=demandAudit.internalDemandMWh+ ...
    demandAudit.marineDemandMWh+demandAudit.computeBaseDemandMWh;
end

function eventSummary=attach_critical_service_rate(eventSummary,demandAudit)
eventSummary.totalCriticalDemandMWh=zeros(height(eventSummary),1);
eventSummary.criticalServiceRate=zeros(height(eventSummary),1);
for i=1:height(eventSummary)
    idx=find(demandAudit.eventCode==eventSummary.eventCode(i),1);
    assert(~isempty(idx),'Missing demand audit row for event %s.', ...
        eventSummary.eventCode(i));
    demand=demandAudit.totalCriticalDemandMWh(idx);
    eventSummary.totalCriticalDemandMWh(i)=demand;
    if demand>0
        eventSummary.criticalServiceRate(i)= ...
            1-eventSummary.ensMWh(i)/demand;
    else
        eventSummary.criticalServiceRate(i)=1;
    end
end
end

function [summary,hourlyLedger,results]=run_strategy_set( ...
    base,cfg,strategies,eventCode,parallelWorkers)
n=numel(strategies);
summaryRows=cell(n,1);
ledgerRows=cell(n,1);
results=cell(n,1);
if parallelWorkers>1
    pool=gcp('nocreate');
    if isempty(pool) || pool.NumWorkers~=parallelWorkers
        if ~isempty(pool), delete(pool); end
        parpool('Processes',parallelWorkers);
    end
    parfor i=1:n
        [summaryRows{i},ledgerRows{i},results{i}]= ...
            c5_run_sequential_hourly( ...
            base,cfg,strategies{i},eventCode,false);
    end
else
    for i=1:n
        fprintf('C5 annual strategy %d/%d: %s\n', ...
            i,n,strategies{i}.id);
        [summaryRows{i},ledgerRows{i},results{i}]= ...
            c5_run_sequential_hourly( ...
            base,cfg,strategies{i},eventCode,false);
    end
end
summary=vertcat(summaryRows{:});
hourlyLedger=vertcat(ledgerRows{:});
end

function eventSummary=summarize_by_event(hourlyLedger)
strategies=unique(hourlyLedger.strategyId,'stable');
rows=cell(0,1);
for i=1:numel(strategies)
    strategyIdx=hourlyLedger.strategyId==strategies(i);
    events=unique(hourlyLedger.eventCode(strategyIdx),'stable');
    for j=1:numel(events)
        idx=strategyIdx & hourlyLedger.eventCode==events(j);
        rows{end+1,1}=table(strategies(i),events(j),nnz(idx), ...
            sum(hourlyLedger.eAvailableMWh(idx)), ...
            sum(hourlyLedger.eSourceUsedMWh(idx)), ...
            sum(hourlyLedger.eCurtailmentMWh(idx)), ...
            sum(hourlyLedger.ensMWh(idx)), ...
            sum(hourlyLedger.eElectricityInputMWh(idx)), ...
            sum(hourlyLedger.eHydrogenInputMWh(idx)), ...
            sum(hourlyLedger.eFlexibleComputeInputMWh(idx)), ...
            min(hourlyLedger.bessSOC(idx)), ...
            min(hourlyLedger.h2InventoryKg(idx)), ...
            nnz(hourlyLedger.planFallbackUsed(idx)), ...
            nnz(hourlyLedger.reserveConstraintRelaxationUsed(idx)), ...
            nnz(hourlyLedger.reliabilityRelaxationUsed(idx)), ...
            'VariableNames',{'strategyId','eventCode','hours', ...
            'eAvailableMWh','eSourceUsedMWh','eCurtailmentMWh','ensMWh', ...
            'eElectricityInputMWh','eHydrogenInputMWh', ...
            'eFlexibleComputeInputMWh','minimumBessSOC', ...
            'minimumH2InventoryKg','planFallbackHours', ...
            'reserveConstraintRelaxationHours', ...
            'reliabilityRelaxationHours'}); %#ok<AGROW>
    end
end
eventSummary=vertcat(rows{:});
end

function out=merge_input(out,addition)
names=fieldnames(addition);
for k=1:numel(names), out.(names{k})=addition.(names{k}); end
end

function selected=select_strategies(strategies,caseIds)
if ischar(caseIds)
    requested=string(caseIds);
elseif isstring(caseIds)
    requested=caseIds(:);
else
    requested=string(caseIds(:));
end
if isscalar(requested) && strcmpi(requested,"all")
    selected=strategies;
    return
end
ids=string(cellfun(@(s)s.id,strategies,'UniformOutput',false));
missing=setdiff(requested,ids,'stable');
assert(isempty(missing),'Unknown C5 strategy IDs: %s',strjoin(missing,", "));
selected=strategies(ismember(ids,requested));
end
