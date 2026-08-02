function [summary,eventSummary,hourlyLedger] = ...
    run_c5_annual_asset_baselines(outputDir,horizonH,parallelWorkers)
%RUN_C5_ANNUAL_ASSET_BASELINES Run only the three canonical baselines.
%
% This wrapper uses the same causal hourly runner, annual multi-source
% scenario, initial state and extreme-event timeline as the new strategy.
% It does not create or enforce any fixed E/H/C share policy.

thisDir=fileparts(mfilename('fullpath'));
c5Root=fileparts(fileparts(thisDir));
annualCode=fullfile(c5Root, ...
    '5.7混合最优策略短测试与年度运营分析','code');
addpath(annualCode,thisDir);
if nargin<1 || strlength(string(outputDir))==0
    outputDir=fullfile(c5Root,'5.2三大基准方案', ...
        'results','annual_asset_baselines_causal');
end
if nargin<2 || isempty(horizonH), horizonH=8760; end
if nargin<3 || isempty(parallelWorkers), parallelWorkers=1; end
caseIds=["baseline_E_asset_only","baseline_H_asset_only", ...
    "baseline_C_asset_only"];
[summary,eventSummary,hourlyLedger]=run_c5_annual_causal_hourly( ...
    outputDir,horizonH,parallelWorkers,caseIds);
end
