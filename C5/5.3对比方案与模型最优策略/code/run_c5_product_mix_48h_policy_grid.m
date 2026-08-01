function grid = run_c5_product_mix_48h_policy_grid( ...
    caseIds,ensLimitsMWh,utilizationMinimums,outputDir)
%RUN_C5_PRODUCT_MIX_48H_POLICY_GRID Screen ENS/utilization epsilon limits.
%
% This is a short-horizon feasibility and trade-off grid. Environmental
% epsilon is intentionally disabled for the 48 h mechanism test.

thisDir=fileparts(mfilename('fullpath'));
c5Root=fileparts(fileparts(thisDir));

if nargin<1 || isempty(caseIds)
    caseIds=["mix_E100","mix_H100","mix_C100", ...
        "mix_E60_H20_C20","mix_E40_H30_C30"];
end
if nargin<2 || isempty(ensLimitsMWh), ensLimitsMWh=[0 1]; end
if nargin<3 || isempty(utilizationMinimums)
    utilizationMinimums=[0 0.4 0.6 0.8];
end
if nargin<4 || strlength(string(outputDir))==0
    outputDir=fullfile(c5Root,'5.3对比方案与模型最优策略', ...
        'results','policy_grid');
end

ensLimitsMWh=double(ensLimitsMWh(:));
utilizationMinimums=double(utilizationMinimums(:));
assert(all(ensLimitsMWh>=0 & isfinite(ensLimitsMWh)), ...
    'ENS limits must be finite and nonnegative.');
assert(all(utilizationMinimums>=0 & utilizationMinimums<=1), ...
    'Utilization minimums must be in [0,1].');

records=cell(numel(ensLimitsMWh)*numel(utilizationMinimums),1);
r=0;
for i=1:numel(ensLimitsMWh)
    for j=1:numel(utilizationMinimums)
        r=r+1;
        policy=struct( ...
            'shareTolerance',0.02, ...
            'minimumAllocatedInputMWh',1, ...
            'maxENSMWh',ensLimitsMWh(i), ...
            'minRenewableUtilization',utilizationMinimums(j), ...
            'temporalTieBreak','none');
        [records{r},~,~]=run_c5_product_mix_48h_scenarios( ...
            caseIds,"",policy);
    end
end
grid=vertcat(records{:});

if strlength(string(outputDir))>0
    outputDir=char(string(outputDir));
    if ~isfolder(outputDir), mkdir(outputDir); end
    writetable(grid,fullfile(outputDir, ...
        'v5_product_mix_48h_policy_grid.csv'));
    save(fullfile(outputDir,'v5_product_mix_48h_policy_grid.mat'), ...
        'grid','caseIds','ensLimitsMWh','utilizationMinimums');
end
end
