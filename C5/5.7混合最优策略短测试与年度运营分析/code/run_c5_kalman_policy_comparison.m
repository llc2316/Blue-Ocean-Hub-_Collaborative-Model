function [summary,hourlyLedger,results] = ...
    run_c5_kalman_policy_comparison(outputDir,horizonH,parallelWorkers)
%RUN_C5_KALMAN_POLICY_COMPARISON Compatibility entry for the four cases.
%
% The former six-policy comparison has been retired. A 48 h request runs
% the normal typical-window comparison; any other horizon calls the annual
% causal runner. In both cases the set is three asset baselines plus the
% single online prior-posterior strategy.

thisDir=fileparts(mfilename('fullpath'));
c5Root=fileparts(fileparts(thisDir));
comparisonCode=fullfile(c5Root,'5.3对比方案与模型最优策略','code');
addpath(comparisonCode,thisDir);
if nargin<1, outputDir=''; end
if nargin<2 || isempty(horizonH), horizonH=48; end
if nargin<3 || isempty(parallelWorkers), parallelWorkers=1; end
if horizonH==48
    [summary,hourlyLedger,~,results]= ...
        run_c5_typical48_causal_comparison(outputDir,parallelWorkers);
else
    [summary,~,hourlyLedger,results]= ...
        run_c5_annual_causal_hourly(outputDir,horizonH,parallelWorkers);
end
end
