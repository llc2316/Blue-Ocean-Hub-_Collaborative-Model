function out=demo_version3_4_3(doPlot)
%DEMO_VERSION3_4_3 Main entry for Chapter 4.3 Version3.
if nargin<1, doPlot=true; end
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'互补体系模型'),fullfile(root,'测试'));
out=struct;
out.tests=run_all_tests_4_3_v3();
out.portfolioComparison=demo_portfolio_comparison_4_3_v3(doPlot);
fprintf('CHAPTER 4.3 VERSION3: DEMO COMPLETED\n');
end
