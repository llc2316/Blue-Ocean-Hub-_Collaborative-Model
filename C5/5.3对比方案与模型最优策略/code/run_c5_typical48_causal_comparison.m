function [summary,hourlyLedger,eventSummary,results] = ...
    run_c5_typical48_causal_comparison(outputDir,parallelWorkers)
%RUN_C5_TYPICAL48_CAUSAL_COMPARISON Four-strategy normal 48 h test.
%
% The all-channel synthetic 48 h case remains a mechanism-validation case.
% Ranking uses a normal typical 48 h sample selected from the annual
% multi-source scenario. The comparison set contains only three asset
% baselines and one online prior-posterior causal strategy.

thisDir=fileparts(mfilename('fullpath'));
c5Root=fileparts(fileparts(thisDir));
annualCode=fullfile(c5Root, ...
    '5.7混合最优策略短测试与年度运营分析','code');
addpath(fullfile(c5Root,'5.1场景设计','code'),annualCode,thisDir);
c5_add_v5_model_paths();
if nargin<1 || strlength(string(outputDir))==0
    outputDir=fullfile(c5Root,'5.3对比方案与模型最优策略', ...
        'results','typical_normal_48h_four_strategy');
end
if nargin<2 || isempty(parallelWorkers), parallelWorkers=1; end
assert(isscalar(parallelWorkers) && parallelWorkers==round(parallelWorkers) && ...
    parallelWorkers>=1,'parallelWorkers must be a positive integer.');

annualScenario=c5_build_annual_2025_multisource_scenario();
sample=c5_select_typical_normal_48h(annualScenario);
assert(all(sample.hourly.eventCode=="NORMAL"), ...
    'The 48 h comparison sample must contain normal hours only.');

cfg=sample.config;
cfg.h2Power.enabled=true;
cfg.h2Power.ratedMW=30; % [假设值，待企业调研校准]
base=sample.input;
base.pWindAvailableMW=sample.sourceDetail.availableBySourceMW(:,1);
base.pPVAvailableMW=sample.sourceDetail.availableBySourceMW(:,2);
base.pTidalAvailableMW=sample.sourceDetail.availableBySourceMW(:,3);
base.availability.h2Power=ones(numel(base.timeH),1);
% Keep scenario-provided initial BESS/H2 states. No external inventory is
% added to the selected window.
initialStateAudit=base.initial;

strategies=c5_four_strategy_specs();
startIdx=sample.meta.startIndex;
if startIdx>1
    [annualSourceInput,annualSourceDetail]=v5_source_adapter( ...
        annualScenario.config,annualScenario.input.sourceCase);
    historyIdx=(1:startIdx-1)';
    history=struct( ...
        'timeH',annualSourceInput.timeH(historyIdx), ...
        'eventCode',annualScenario.hourly.eventCode(historyIdx), ...
        'pWindAvailableMW', ...
            annualSourceDetail.availableBySourceMW(historyIdx,1), ...
        'pPVAvailableMW', ...
            annualSourceDetail.availableBySourceMW(historyIdx,2), ...
        'pTidalAvailableMW', ...
            annualSourceDetail.availableBySourceMW(historyIdx,3));
    strategies{4}.onlinePriorHistory=history;
end

[summary,hourlyLedger,results]=run_strategy_set( ...
    base,cfg,strategies,sample.hourly.eventCode,parallelWorkers);
summary.comparisonSet=repmat( ...
    "THREE_ASSET_BASELINES_PLUS_ONE_ONLINE_PRIOR_POSTERIOR", ...
    height(summary),1);
summary.scenarioId=repmat(string(sample.meta.scenarioId),height(summary),1);
summary.extremeEventIncluded=false(height(summary),1);
summary.h2InventoryMinimumPolicy=repmat( ...
    "PHYSICAL_NONNEGATIVITY_ONLY; NO_OPERATIONAL_FLOOR",height(summary),1);
summary.initialBessEnergyMWh=repmat(initialStateAudit.bessEnergyMWh, ...
    height(summary),1);
summary.initialH2InventoryKg=repmat(initialStateAudit.h2InventoryKg, ...
    height(summary),1);
summary.rankingEligible=summary.mainConclusionEligible & ...
    summary.strictPass;
summary.rankingExclusionReason=eligibility_reason( ...
    summary.rankingEligible,summary.mainConclusionStatus);
summary.comparisonEligible=summary.rankingEligible;
summary.comparisonExclusionReason=summary.rankingExclusionReason;
eventSummary=summarize_by_event(hourlyLedger);

if ~isfolder(outputDir), mkdir(outputDir); end
writetable(summary,fullfile(outputDir, ...
    'c5_typical48_four_strategy_summary.csv'));
writetable(hourlyLedger,fullfile(outputDir, ...
    'c5_typical48_four_strategy_hourly.csv'));
writetable(eventSummary,fullfile(outputDir, ...
    'c5_typical48_four_strategy_event_summary.csv'));
writetable(sample.hourly,fullfile(outputDir, ...
    'c5_typical48_selected_scenario_input.csv'));
sourceOutput=table(sample.hourly.timeUTC, ...
    sample.sourceDetail.availableBySourceMW(:,1), ...
    sample.sourceDetail.availableBySourceMW(:,2), ...
    sample.sourceDetail.availableBySourceMW(:,3), ...
    sample.sourceDetail.aggregateAvailableMW, ...
    'VariableNames',{'timeUTC','pWindAvailableMW','pPVAvailableMW', ...
    'pTidalAvailableMW','pTotalSourceAvailableMW'});
writetable(sourceOutput,fullfile(outputDir, ...
    'c5_typical48_multisource_available_output.csv'));
writetable(sample.selectionAudit,fullfile(outputDir, ...
    'c5_typical48_selection_audit.csv'));
save(fullfile(outputDir,'c5_typical48_four_strategy_results.mat'), ...
    'summary','hourlyLedger','eventSummary','strategies','sample', ...
    'sourceOutput','initialStateAudit','-v7.3');
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
            'VariableNames',{'strategyId','eventCode','hours', ...
            'eAvailableMWh','eSourceUsedMWh','eCurtailmentMWh','ensMWh'}); %#ok<AGROW>
    end
end
eventSummary=vertcat(rows{:});
end

function reason=eligibility_reason(eligible,status)
eligible=logical(eligible(:));
status=string(status(:));
reason=repmat("ELIGIBLE",numel(eligible),1);
reason(~eligible)=status(~eligible);
end
