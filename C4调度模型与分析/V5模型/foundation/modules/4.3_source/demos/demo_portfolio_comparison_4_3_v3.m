function result=demo_portfolio_comparison_4_3_v3(doPlot)
%DEMO_PORTFOLIO_COMPARISON_4_3_V3 Equal-capacity diagnostic comparison.
% All resource trajectories and capacity shares are synthetic assumptions.
if nargin<1, doPlot=true; end
rng(43); dt=300; t=(0:dt:30*24*3600)'; h=t/3600; N=numel(t);
weather=0.08*sin(2*pi*h/(24*5))+0.04*randn(N,1);
wind=min(1,max(0,0.58+0.20*sin(2*pi*h/17)+weather));
solar=max(0,sin(pi*mod(h-6,24)/12));
cloud=min(0.65,max(0,0.25-1.5*weather)); solar=solar.*(1-cloud);
tidal=abs(sin(2*pi*h/12.42)).^3;
pu=[wind solar tidal]; quality=true(N,3);
share=[0.85 0.10 0.05]; windows=[dt 3600 6*3600];
result=compare_source_portfolios_4_3_v3(t,pu,quality,share,windows,0.2);

summary=table(strings(3,1),zeros(3,1),zeros(3,1),zeros(3,1),zeros(3,1), ...
    'VariableNames',{'Portfolio','CV_1h','P05_1h_pu','LowFraction_1h','MaxLowDuration_1h_h'});
for j=1:3
    m=result(j).metrics; summary.Portfolio(j)=result(j).name;
    summary.CV_1h(j)=m.coefficientVariation(2);
    summary.P05_1h_pu(j)=m.empiricalLowQuantileP05(2);
    summary.LowFraction_1h(j)=m.lowOutputFraction(2);
    summary.MaxLowDuration_1h_h(j)=m.maxLowDurationSeconds(2)/3600;
end
result(1).comparisonSummary=summary;
disp(summary);
fprintf('All numerical results are [假设值，待企业调研校准].\n');
if doPlot
    figure('Color','w','Name','4.3 Version3 portfolio comparison');
    tiledlayout(2,1);
    nexttile; plot(h/24,[result.power],'LineWidth',1); grid on;
    xlabel('Day'); ylabel('Per-unit power'); legend([result.name],'Location','best');
    nexttile; bar(categorical(summary.Portfolio),summary.CV_1h); grid on;
    ylabel('1 h coefficient of variation');
end
end
