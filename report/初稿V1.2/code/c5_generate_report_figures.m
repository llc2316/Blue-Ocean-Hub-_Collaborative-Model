function c5_generate_report_figures()
%C5_GENERATE_REPORT_FIGURES Generate Chapter 5 report figures from frozen CSV outputs.
% This script only visualizes existing simulation results. It does not rerun
% the dispatch model or modify any result ledger.

scriptDir = fileparts(mfilename('fullpath'));
reportDir = fileparts(scriptDir);
rootDir = fileparts(reportDir);
outDir = fullfile(reportDir, 'figures', 'chapter5');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

shortDir = fullfile(rootDir, 'C5', '5.3对比方案与模型最优策略', 'results', ...
    'typical_normal_48h_four_strategy');
annualDir = fullfile(rootDir, 'C5', '5.7混合最优策略短测试与年度运营分析', 'results', ...
    'annual_8760h_online_strategy_extreme');

source48 = readtable(fullfile(shortDir, 'c5_typical48_multisource_available_output.csv'), ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
hourly48 = readtable(fullfile(shortDir, 'c5_typical48_four_strategy_hourly.csv'), ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
summary48 = readtable(fullfile(shortDir, 'c5_typical48_four_strategy_summary.csv'), ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
annual = readtable(fullfile(annualDir, 'c5_annual_online_strategy_hourly.csv'), ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');

set(groot, 'defaultAxesFontName', 'Microsoft YaHei');
set(groot, 'defaultTextFontName', 'Microsoft YaHei');
set(groot, 'defaultAxesFontSize', 9);
set(groot, 'defaultLegendFontSize', 8.5);
set(groot, 'defaultLineLineWidth', 1.45);
set(groot, 'defaultFigureColor', 'white');
set(groot, 'defaultAxesColor', 'white');
set(groot, 'defaultAxesXColor', [0.15, 0.16, 0.18]);
set(groot, 'defaultAxesYColor', [0.15, 0.16, 0.18]);
set(groot, 'defaultTextColor', [0.15, 0.16, 0.18]);
set(groot, 'defaultLegendColor', 'white');
set(groot, 'defaultLegendTextColor', [0.15, 0.16, 0.18]);

colors.blue = [0.08, 0.36, 0.66];
colors.cyan = [0.14, 0.62, 0.70];
colors.green = [0.20, 0.58, 0.36];
colors.orange = [0.93, 0.53, 0.16];
colors.red = [0.78, 0.22, 0.20];
colors.purple = [0.48, 0.32, 0.68];
colors.gray = [0.45, 0.48, 0.52];
colors.lightgray = [0.82, 0.84, 0.86];

%% Figure 5-1: multisource availability in the representative 48 h window
x48 = (0:height(source48)-1)';
f = newFigure([100, 100, 1240, 520]);
ax = axes(f);
a = area(ax, x48, [source48.pWindAvailableMW, source48.pPVAvailableMW, ...
    source48.pTidalAvailableMW], 'LineStyle', 'none');
a(1).FaceColor = colors.blue;
a(2).FaceColor = colors.orange;
a(3).FaceColor = colors.cyan;
hold(ax, 'on');
totalLine = plot(ax, x48, source48.pTotalSourceAvailableMW, '-', ...
    'Color', [0.12, 0.13, 0.15], 'LineWidth', 1.8);
styleAxes(ax);
xlabel(ax, '典型窗口小时');
ylabel(ax, '可用功率 / MW');
xlim(ax, [0, 47]);
xticks(ax, 0:6:47);
legend(ax, [a(:); totalLine], {'风电', '光伏', '潮流能', '多源合计'}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off');
exportFigure(f, outDir, 'fig5-1_typical48_multisource.png');

%% Figure 5-2: four-strategy energy and operating-value comparison
order = ["baseline_E_asset_only", "baseline_H_asset_only", ...
    "baseline_C_asset_only", "model_online_prior_posterior_event_aware"];
labels = {'纯电资产', '纯氢资产', '纯算资产', '在线协同'};
rowOrder = zeros(numel(order), 1);
for i = 1:numel(order)
    rowOrder(i) = find(string(summary48.strategyId) == order(i), 1, 'first');
end
s48 = summary48(rowOrder, :);
usedGWh = s48.eSourceUsedMWh / 1000;
curtGWh = s48.eCurtailmentMWh / 1000;
utilPct = 100 * s48.eSourceUsedMWh ./ s48.eAvailableMWh;
benefitMCNY = -s48.economicNetCostCNY / 1e6;

f = newFigure([100, 100, 1320, 570]);
tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl, 1);
b = bar(ax1, 1:4, [usedGWh, curtGWh], 0.68, 'stacked');
b(1).FaceColor = colors.blue;
b(2).FaceColor = colors.lightgray;
styleAxes(ax1);
set(ax1, 'XTick', 1:4, 'XTickLabel', labels);
ylabel(ax1, '48 h电量 / GWh');
title(ax1, '(a) 新能源利用与弃电');
legend(ax1, {'已利用', '弃电'}, 'Location', 'northoutside', ...
    'Orientation', 'horizontal', 'Box', 'off');
ylim(ax1, [0, max(usedGWh + curtGWh) * 1.18]);
for i = 1:4
    text(ax1, i, usedGWh(i) + curtGWh(i) + 0.22, sprintf('%.1f%%', utilPct(i)), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontSize', 8.5);
end

ax2 = nexttile(tl, 2);
bars = bar(ax2, 1:4, benefitMCNY, 0.62, 'FaceColor', 'flat');
bars.CData = [colors.blue; colors.orange; colors.cyan; colors.green];
styleAxes(ax2);
set(ax2, 'XTick', 1:4, 'XTickLabel', labels);
ylabel(ax2, '运行层净收益 / 百万元');
title(ax2, '(b) 运行层净收益');
ylim(ax2, [0, max(benefitMCNY) * 1.20]);
for i = 1:4
    text(ax2, i, benefitMCNY(i) + max(benefitMCNY) * 0.025, ...
        sprintf('%.2f', benefitMCNY(i)), 'HorizontalAlignment', 'center', ...
        'FontWeight', 'bold', 'FontSize', 8.5);
end
exportFigure(f, outDir, 'fig5-2_typical48_strategy_comparison.png');

%% Figure 5-3: online strategy dispatch in the representative 48 h window
onlineMask = string(hourly48.strategyId) == "model_online_prior_posterior_event_aware";
online48 = sortrows(hourly48(onlineMask, :), 'timeH');
t = online48.timeH;
f = newFigure([100, 100, 1320, 900]);
tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl, 1);
plot(ax1, t, online48.pSourceAvailableMW, '-', 'Color', colors.gray, 'LineWidth', 1.5);
hold(ax1, 'on');
plot(ax1, t, online48.pSourceUsedMW, '-', 'Color', colors.blue, 'LineWidth', 1.8);
plot(ax1, t, online48.pCurtailmentMW, '-', 'Color', colors.red, 'LineWidth', 1.35);
styleAxes(ax1);
ylabel(ax1, '功率 / MW');
title(ax1, '(a) 可用出力、源侧利用与弃电');
legend(ax1, {'可用出力', '源侧利用', '弃电'}, 'Location', 'northoutside', ...
    'Orientation', 'horizontal', 'Box', 'off');

ax2 = nexttile(tl, 2);
prodArea = area(ax2, t, [online48.pCableSendMW, online48.pElectrolyzerMW, ...
    online48.pComputeFacilityMW], 'LineStyle', 'none');
prodArea(1).FaceColor = colors.blue;
prodArea(2).FaceColor = colors.green;
prodArea(3).FaceColor = colors.purple;
styleAxes(ax2);
ylabel(ax2, '产品通道功率 / MW');
title(ax2, '(b) 电力、制氢与算力通道');
legend(ax2, {'海缆送端', '电解制氢', '算力设施'}, 'Location', 'northoutside', ...
    'Orientation', 'horizontal', 'Box', 'off');

ax3 = nexttile(tl, 3);
chargeBar = bar(ax3, t, -online48.pBessChargeMW, 0.82, ...
    'FaceColor', colors.cyan, 'EdgeColor', 'none');
hold(ax3, 'on');
dischargeBar = bar(ax3, t, online48.pBessDischargeMW, 0.82, ...
    'FaceColor', colors.orange, 'EdgeColor', 'none');
yline(ax3, 0, '-', 'Color', [0.25, 0.25, 0.25], 'LineWidth', 0.8);
styleAxes(ax3);
ylabel(ax3, 'BESS功率 / MW');
yyaxis(ax3, 'right');
socLine = plot(ax3, t, 100 * online48.bessSOC, '-', 'Color', colors.red, 'LineWidth', 1.7);
ylabel(ax3, 'SOC / %');
ylim(ax3, [0, 100]);
ax3.YAxis(2).Color = colors.red;
title(ax3, '(c) BESS充放电与SOC');
xlabel(ax3, '典型窗口小时');
xlim(ax1, [0, 47]); xlim(ax2, [0, 47]); xlim(ax3, [0, 47]);
xticks(ax1, 0:6:47); xticks(ax2, 0:6:47); xticks(ax3, 0:6:47);
legend(ax3, [chargeBar, dischargeBar, socLine], {'充电（负值）', '放电（正值）', 'SOC'}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off');
exportFigure(f, outDir, 'fig5-3_typical48_online_dispatch.png');

%% Figure 5-4: causal forecast correction and anti-jitter plan
f = newFigure([100, 100, 1320, 710]);
tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl, 1);
plot(ax1, t, online48.pSourceAvailableMW, '-', 'Color', [0.10, 0.10, 0.10], 'LineWidth', 1.8);
hold(ax1, 'on');
plot(ax1, t, online48.priorAvailableMW, '--', 'Color', colors.gray, 'LineWidth', 1.25);
plot(ax1, t, online48.posteriorAvailableMW, '-', 'Color', colors.blue, 'LineWidth', 1.45);
plot(ax1, t, online48.planningAvailableMW, '-', 'Color', colors.red, 'LineWidth', 1.45);
styleAxes(ax1);
ylabel(ax1, '功率 / MW');
title(ax1, '(a) 真实值仅用于结算，计划由历史先验和后验形成');
legend(ax1, {'当前实际可用', '历史先验', '后验估计', '保守规划功率'}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off');

ax2 = nexttile(tl, 2);
stairs(ax2, t, 100 * online48.rawPlannedElectricityShare, '--', ...
    'Color', colors.blue, 'LineWidth', 1.0);
hold(ax2, 'on');
stairs(ax2, t, 100 * online48.plannedElectricityShare, '-', ...
    'Color', colors.blue, 'LineWidth', 1.75);
stairs(ax2, t, 100 * online48.rawPlannedComputeShare, '--', ...
    'Color', colors.purple, 'LineWidth', 1.0);
stairs(ax2, t, 100 * online48.plannedComputeShare, '-', ...
    'Color', colors.purple, 'LineWidth', 1.75);
holdMask = online48.planHeldByDeadband > 0.5;
scatter(ax2, t(holdMask), 3 * ones(nnz(holdMask), 1), 24, colors.orange, 'filled', ...
    'Marker', 'diamond');
styleAxes(ax2);
ylabel(ax2, '计划份额 / %');
xlabel(ax2, '典型窗口小时');
ylim(ax2, [0, 105]);
title(ax2, '(b) 原始计划、执行计划与死区保持小时');
legend(ax2, {'电力原始', '电力执行', '算力原始', '算力执行', '死区保持'}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off');
xlim(ax1, [0, 47]); xlim(ax2, [0, 47]);
xticks(ax1, 0:6:47); xticks(ax2, 0:6:47);
exportFigure(f, outDir, 'fig5-4_forecast_and_anti_jitter.png');

%% Figure 5-5: annual monthly energy balance and utilization
dt = datetime(2025, 1, 1, 0, 0, 0) + hours(annual.timeH);
monthNo = month(dt);
monthlyAvail = accumarray(monthNo, annual.eAvailableMWh, [12, 1], @sum, 0);
monthlyUsed = accumarray(monthNo, annual.eSourceUsedMWh, [12, 1], @sum, 0);
monthlyCurt = accumarray(monthNo, annual.eCurtailmentMWh, [12, 1], @sum, 0);
monthlyUtil = 100 * monthlyUsed ./ max(monthlyAvail, eps);
monthLabels = {'1月','2月','3月','4月','5月','6月', ...
    '7月','8月','9月','10月','11月','12月'};

f = newFigure([100, 100, 1320, 560]);
ax = axes(f);
yyaxis(ax, 'left');
b = bar(ax, 1:12, [monthlyUsed, monthlyCurt] / 1000, 0.75, 'stacked');
b(1).FaceColor = colors.blue;
b(2).FaceColor = colors.lightgray;
ylabel(ax, '月度新能源电量 / GWh');
yyaxis(ax, 'right');
uLine = plot(ax, 1:12, monthlyUtil, '-o', 'Color', colors.red, ...
    'MarkerFaceColor', 'white', 'LineWidth', 1.8, 'MarkerSize', 5);
ylabel(ax, '新能源利用率 / %');
ylim(ax, [0, 100]);
styleAxes(ax);
ax.YAxis(1).Color = [0.15, 0.16, 0.18];
ax.YAxis(2).Color = colors.red;
set(ax, 'XTick', 1:12, 'XTickLabel', monthLabels);
xlim(ax, [0.4, 12.6]);
legend(ax, [b(1), b(2), uLine], {'已利用', '弃电', '利用率'}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off');
exportFigure(f, outDir, 'fig5-5_annual_monthly_energy.png');

%% Figure 5-6: annual duration curve and monthly ENS composition
[availableSorted, sortIdx] = sort(annual.pSourceAvailableMW, 'descend');
usedSorted = annual.pSourceUsedMW(sortIdx);
curtSorted = annual.pCurtailmentMW(sortIdx);
durationPct = 100 * (0:height(annual)-1)' / (height(annual)-1);
monthlyMarineENS = accumarray(monthNo, annual.pMarineUnservedMW, [12, 1], @sum, 0);
monthlyInternalENS = accumarray(monthNo, annual.pInternalUnservedMW, [12, 1], @sum, 0);

f = newFigure([100, 100, 1320, 580]);
tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl, 1);
plot(ax1, durationPct, availableSorted, '-', 'Color', colors.gray, 'LineWidth', 1.6);
hold(ax1, 'on');
plot(ax1, durationPct, usedSorted, '-', 'Color', colors.blue, 'LineWidth', 1.7);
plot(ax1, durationPct, curtSorted, '-', 'Color', colors.red, 'LineWidth', 1.25);
styleAxes(ax1);
xlabel(ax1, '年度小时持续比例 / %');
ylabel(ax1, '功率 / MW');
title(ax1, '(a) 可用出力排序下的利用与弃电');
legend(ax1, {'可用出力', '源侧利用', '弃电'}, 'Location', 'northoutside', ...
    'Orientation', 'horizontal', 'Box', 'off');
xlim(ax1, [0, 100]);

ax2 = nexttile(tl, 2);
b = bar(ax2, 1:12, [monthlyMarineENS, monthlyInternalENS], 0.75, 'stacked');
b(1).FaceColor = colors.red;
b(2).FaceColor = colors.orange;
styleAxes(ax2);
set(ax2, 'XTick', 1:12, 'XTickLabel', monthLabels);
xlim(ax2, [0.4, 12.6]);
ylabel(ax2, '月度ENS / MWh');
title(ax2, '(b) 海洋刚性负荷与内部关键负荷ENS');
legend(ax2, {'海洋刚性负荷', '内部关键负荷'}, 'Location', 'northoutside', ...
    'Orientation', 'horizontal', 'Box', 'off');
exportFigure(f, outDir, 'fig5-6_annual_duration_and_ens.png');

%% Figure 5-7: typhoon warning, passage and recovery response
eventStart = 6168;
windowMask = annual.timeH >= eventStart - 12 & annual.timeH <= eventStart + 71;
event = annual(windowMask, :);
te = event.timeH - eventStart;
f = newFigure([100, 100, 1320, 920]);
tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl, 1);
plot(ax1, te, event.pSourceAvailableMW, '-', 'Color', [0.10, 0.10, 0.10], 'LineWidth', 1.8);
hold(ax1, 'on');
plot(ax1, te, event.posteriorAvailableMW, '-', 'Color', colors.blue, 'LineWidth', 1.35);
plot(ax1, te, event.planningAvailableMW, '-', 'Color', colors.red, 'LineWidth', 1.35);
styleAxes(ax1);
ylabel(ax1, '功率 / MW');
title(ax1, '(a) 极端事件前后的实际、后验与规划功率');
lg1 = legend(ax1, {'实际可用', '后验估计', '保守规划'}, 'Location', 'northoutside', ...
    'Orientation', 'horizontal', 'Box', 'off');
lg1.AutoUpdate = 'off';

ax2 = nexttile(tl, 2);
chargeBar = bar(ax2, te, -event.pBessChargeMW, 0.85, ...
    'FaceColor', colors.cyan, 'EdgeColor', 'none');
hold(ax2, 'on');
dischargeBar = bar(ax2, te, event.pBessDischargeMW, 0.85, ...
    'FaceColor', colors.orange, 'EdgeColor', 'none');
yline(ax2, 0, '-', 'Color', [0.25, 0.25, 0.25], 'LineWidth', 0.8);
styleAxes(ax2);
ylabel(ax2, 'BESS功率 / MW');
yyaxis(ax2, 'right');
socLine = plot(ax2, te, 100 * event.bessSOC, '-', 'Color', colors.red, 'LineWidth', 1.7);
hold(ax2, 'on');
reserveLine = plot(ax2, te, 100 * event.bessReserveTargetSOC, '--', ...
    'Color', colors.purple, 'LineWidth', 1.45);
ylabel(ax2, 'SOC / %');
ylim(ax2, [0, 100]);
ax2.YAxis(2).Color = colors.red;
title(ax2, '(b) 储备目标抬升、BESS充放电与SOC');
lg2 = legend(ax2, [chargeBar, dischargeBar, socLine, reserveLine], ...
    {'充电（负值）', '放电（正值）', 'SOC', '储备目标'}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off');
lg2.AutoUpdate = 'off';

ax3 = nexttile(tl, 3);
ensArea = area(ax3, te, [event.pMarineUnservedMW, event.pInternalUnservedMW], ...
    'LineStyle', 'none');
ensArea(1).FaceColor = colors.red;
ensArea(2).FaceColor = colors.orange;
styleAxes(ax3);
ylabel(ax3, '缺供功率 / MW');
xlabel(ax3, '相对预警起点小时');
title(ax3, '(c) 关键负荷缺供分解');
lg3 = legend(ax3, {'海洋刚性负荷', '内部关键负荷'}, 'Location', 'northoutside', ...
    'Orientation', 'horizontal', 'Box', 'off');
lg3.AutoUpdate = 'off';

allAxes = [ax1, ax2, ax3];
for k = 1:numel(allAxes)
    xlim(allAxes(k), [-12, 71]);
    xline(allAxes(k), 0, ':', '预警', 'LabelVerticalAlignment', 'bottom', ...
        'Color', colors.orange, 'LineWidth', 1.0);
    xline(allAxes(k), 12, ':', '过境', 'LabelVerticalAlignment', 'bottom', ...
        'Color', colors.red, 'LineWidth', 1.0);
    xline(allAxes(k), 36, ':', '恢复', 'LabelVerticalAlignment', 'bottom', ...
        'Color', colors.green, 'LineWidth', 1.0);
    xline(allAxes(k), 60, ':', '正常', 'LabelVerticalAlignment', 'bottom', ...
        'Color', colors.gray, 'LineWidth', 1.0);
end
exportFigure(f, outDir, 'fig5-7_typhoon_response.png');

fprintf('Generated 7 Chapter 5 figures in: %s\n', outDir);
end

function f = newFigure(position)
f = figure('Visible', 'off', 'Color', 'white', 'Units', 'pixels', ...
    'Position', position, 'Renderer', 'painters');
end

function styleAxes(ax)
grid(ax, 'on');
ax.Color = 'white';
ax.XColor = [0.15, 0.16, 0.18];
for i = 1:numel(ax.YAxis)
    ax.YAxis(i).Color = [0.15, 0.16, 0.18];
end
ax.GridAlpha = 0.14;
ax.MinorGridAlpha = 0.08;
ax.LineWidth = 0.8;
ax.Box = 'off';
ax.Layer = 'top';
ax.TickDir = 'out';
end

function exportFigure(f, outDir, fileName)
exportgraphics(f, fullfile(outDir, fileName), 'Resolution', 300, ...
    'BackgroundColor', 'white');
close(f);
end
