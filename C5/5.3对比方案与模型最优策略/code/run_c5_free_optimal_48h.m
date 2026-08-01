function [summary,result] = run_c5_free_optimal_48h(outputDir)
%RUN_C5_FREE_OPTIMAL_48H Free E/H/C dispatch on the frozen 48 h case.
% The physical/task boundary is identical to the legacy 22-share test.
% No E/H/C share is imposed. The result is the scenario-specific economic
% optimum, with minimum curtailment as a lexicographic tie-break.

error('C5:RetiredPerfectForesight48h', ...
    ['Synthetic-48h free optimization is retired. Use ', ...
     'run_c5_typical48_causal_comparison; the causal model result is ', ...
     'reported separately from the fixed-policy ranking.']);

thisDir=fileparts(mfilename('fullpath'));
c5Root=fileparts(fileparts(thisDir));
addpath(fullfile(c5Root,'5.1场景设计','code'),thisDir);
c5_add_v5_model_paths();
if nargin<1 || strlength(string(outputDir))==0
    outputDir=fullfile(c5Root,'5.3对比方案与模型最优策略','results');
end
scenario=c5_build_all_channel_48h_scenario();
cfg=scenario.config;
cfg.objective.primary='economicNetCostCNY';
cfg.objective.maxENSMWh=0;
cfg.objective.maxNetGHGKgCO2e=Inf;
cfg.objective.minRenewableUtilization=0;
cfg.objective.tieBreak='minCurtailment';
cfg.objective.temporalTieBreak='none';
cfg.solver.maxTimeS=300;
[sourceInput,~]=v5_source_adapter(cfg,scenario.input.sourceCase);
in=rmfield(scenario.input,'sourceCase');
in=merge_input(in,sourceInput);
in.productMix=struct('enabled',false);
result=run_v5_model(in,cfg);
assert(result.meta.exitflag>0 && result.audit.pass);

k=result.kpi;
operatingNetBenefitCNY=-k.economicNetCostCNY;
summary=table( ...
    "OPT_FREE_ECON_48H","MODEL_DERIVED_OPTIMAL", ...
    k.realizedElectricityInputShare,k.realizedHydrogenInputShare, ...
    k.realizedComputeInputShare,k.eElectricityInputMWh, ...
    k.eHydrogenInputMWh,k.eFlexibleComputeInputMWh, ...
    k.renewableUtilization,k.eCurtailmentMWh,k.ensMWh, ...
    k.outputRevenueCNY,k.operatingCostCNY,k.economicNetCostCNY, ...
    operatingNetBenefitCNY,result.meta.exitflag,result.audit.pass, ...
    "[模型仿真结果；场景与参数为假设值，待企业调研校准]", ...
    'VariableNames',{'scenarioId','strategyType', ...
    'realizedElectricityInputShare','realizedHydrogenInputShare', ...
    'realizedComputeInputShare','eElectricityInputMWh', ...
    'eHydrogenInputMWh','eFlexibleComputeInputMWh', ...
    'renewableUtilization','eCurtailmentMWh','ensMWh', ...
    'outputRevenueCNY','operatingCostCNY','economicNetCostCNY', ...
    'operatingNetBenefitCNY','exitflag','auditPass','evidenceStatus'});
if strlength(string(outputDir))>0
    if ~isfolder(outputDir), mkdir(outputDir); end
    writetable(summary,fullfile(outputDir,'c5_free_optimal_48h_summary.csv'));
    save(fullfile(outputDir,'c5_free_optimal_48h_result.mat'), ...
        'summary','result','-v7.3');
end
end

function out=merge_input(out,addition)
names=fieldnames(addition);
for k=1:numel(names), out.(names{k})=addition.(names{k}); end
end
