%% Blue Hub 电解制氢：24 h 调度、场景分析与论文插图
% 说明：
% 1) 若同目录存在 blue_hub_timeseries_input.csv，则读取用户数据；
% 2) 否则生成固定随机种子的24 h可复现演示数据，并导出输入模板；
% 3) 若可用 intlinprog，则求解简化MILP；否则使用公开、可复核的规则调度；
% 4) 所有结果与6幅图片写入本文件所在目录。
% 演示数据仅用于检查模型和排版，不代表项目实测值。

clear; clc; close all;
rng(20260716, 'twister');

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir)
    rootDir = pwd;
end
inputFile = fullfile(rootDir, 'blue_hub_timeseries_input.csv');
templateFile = fullfile(rootDir, 'blue_hub_timeseries_input_template.csv');

params = default_parameters();

if isfile(inputFile)
    inputData = readtable(inputFile, 'VariableNamingRule', 'preserve');
    dataSource = "USER_CSV";
else
    inputData = make_demo_input();
    writetable(inputData, templateFile);
    dataSource = "DEMO_FIXED_SEED";
end
inputData = validate_input(inputData);

[result, summaryTable] = run_dispatch(inputData, params);
result.data_source = repmat(dataSource, height(result), 1);

writetable(result, fullfile(rootDir, 'blue_hub_24h_results.csv'));
writetable(summaryTable, fullfile(rootDir, 'blue_hub_summary_table.csv'));

scenarioTable = run_scenarios(inputData, params);
writetable(scenarioTable, fullfile(rootDir, 'blue_hub_scenario_kpi.csv'));

sensitivityTable = build_sensitivity_table(params);
writetable(sensitivityTable, fullfile(rootDir, 'blue_hub_sensitivity_table.csv'));

make_all_figures(inputData, result, scenarioTable, sensitivityTable, params, rootDir);

fprintf('\nBlue Hub计算完成。\n');
fprintf('数据来源标记：%s\n', dataSource);
fprintf('求解模式：%s\n', result.solver_mode(1));
fprintf('额定产氢校核：%.2f kg/h；日满负荷产氢：%.2f t/d。\n', ...
    1000 * params.pRated / params.sec, 24 * params.pRated * 1000 / params.sec / 1000);
fprintf('最大功率平衡残差：%.3e MW。\n', max(abs(result.power_balance_residual_mw)));
fprintf('结果及6幅300 dpi图片已写入：%s\n', rootDir);


%% 参数
function p = default_parameters()
p.dt = 1;                       % h
p.pRated = 100;                 % MW
p.pMin = 20;                    % MW
p.sec = 56.77;                  % kWh/kg，Nel系统侧满负荷口径
p.waterLPerKg = 15.9;           % L/kg H2
p.cableCapacity = 500;          % MW，项目演示假设
p.h2Capacity = 72000;           % kg，项目演示假设
p.h2Initial = 30000;            % kg
p.h2Price = 30;                 % CNY/kg，经济情景
p.h2VariableCost = 2;           % CNY/kg，水与变动运维的合并演示值
p.bessEnergyCapacity = 100;     % MWh
p.bessInitial = 50;             % MWh
p.bessChargeMax = 50;           % MW
p.bessDischargeMax = 50;        % MW
p.etaCharge = 0.95;
p.etaDischarge = 0.95;
p.curtailPenalty = 30;          % CNY/MWh
p.shortPenalty = 120;           % CNY/kg
p.startCost = 2500;             % CNY/start
p.uInitial = 0;
end


%% 固定演示输入
function T = make_demo_input()
hour = (1:24)';
wind_power_mw = [430 410 390 380 420 480 560 650 720 760 800 820 ...
    780 730 690 640 600 570 610 680 740 700 600 500]';
critical_load_mw = [85 82 80 78 80 85 90 95 100 105 110 115 ...
    118 120 122 120 115 110 108 105 100 95 90 88]';
electricity_price_cny_mwh = [260 240 230 220 230 260 320 380 450 520 560 580 ...
    540 500 470 430 410 460 520 600 580 500 400 320]';
h2_demand_kg_h = [900 900 900 900 900 950 950 1000 1000 1050 1050 1100 ...
    1100 1100 1100 1050 1050 1000 1000 1000 950 950 900 900]';
tx_availability = ones(24, 1);
electrolyzer_availability = ones(24, 1);

T = table(hour, wind_power_mw, critical_load_mw, electricity_price_cny_mwh, ...
    h2_demand_kg_h, tx_availability, electrolyzer_availability);
end


%% 输入检查
function T = validate_input(T)
required = {'hour', 'wind_power_mw', 'critical_load_mw', ...
    'electricity_price_cny_mwh', 'h2_demand_kg_h', ...
    'tx_availability', 'electrolyzer_availability'};
missing = required(~ismember(required, T.Properties.VariableNames));
if ~isempty(missing)
    error('输入CSV缺少字段：%s', strjoin(missing, ', '));
end
T = T(:, required);
if height(T) < 2
    error('输入至少需要2个时段。');
end
numericBlock = T{:, :};
if any(ismissing(numericBlock), 'all')
    error('输入数据存在空值，请补齐后再运行。');
end
nonnegative = {'wind_power_mw', 'critical_load_mw', ...
    'electricity_price_cny_mwh', 'h2_demand_kg_h'};
for k = 1:numel(nonnegative)
    if any(T.(nonnegative{k}) < 0)
        error('%s不能为负数。', nonnegative{k});
    end
end
for name = {'tx_availability', 'electrolyzer_availability'}
    x = T.(name{1});
    if any(x < 0 | x > 1)
        error('%s应位于[0,1]。', name{1});
    end
end
if any(diff(T.hour) <= 0)
    error('hour必须严格递增。');
end
end


%% 自动选择MILP或规则调度
function [result, summaryTable] = run_dispatch(inputData, p)
canUseMilp = license('test', 'Optimization_Toolbox') && exist('intlinprog', 'file') == 2;
if canUseMilp
    try
        result = dispatch_milp(inputData, p);
        mode = "MILP";
    catch ME
        warning('MILP求解失败，改用规则备用模式。原因：%s', ME.message);
        result = dispatch_rule(inputData, p);
        mode = "RULE_FALLBACK_AFTER_MILP_ERROR";
    end
else
    result = dispatch_rule(inputData, p);
    mode = "RULE_FALLBACK_NO_TOOLBOX";
end
result.solver_mode = repmat(mode, height(result), 1);

summaryTable = make_summary(result, p, mode);
end


%% 简化MILP
function result = dispatch_milp(D, p)
n = height(D);
fields = {'pel','u','pexp','pch','pdis','energy','h2stock','hsale','hshort','pcurt','ystart','z'};
for k = 1:numel(fields)
    idx.(fields{k}) = (k-1)*n + (1:n);
end
nvar = numel(fields) * n;

lb = zeros(nvar, 1);
ub = inf(nvar, 1);
ub(idx.pel) = p.pRated .* D.electrolyzer_availability;
ub(idx.u) = D.electrolyzer_availability;
ub(idx.pexp) = p.cableCapacity .* D.tx_availability;
ub(idx.pch) = p.bessChargeMax;
ub(idx.pdis) = p.bessDischargeMax;
ub(idx.energy) = p.bessEnergyCapacity;
ub(idx.h2stock) = p.h2Capacity;
ub(idx.hsale) = D.h2_demand_kg_h * p.dt;
ub(idx.hshort) = D.h2_demand_kg_h * p.dt;
ub(idx.ystart) = 1;
ub(idx.z) = 1;

intcon = [idx.u idx.ystart idx.z];

f = zeros(nvar, 1);
f(idx.pel) = p.h2VariableCost * 1000 / p.sec;
f(idx.pexp) = -D.electricity_price_cny_mwh * p.dt;
f(idx.hsale) = -p.h2Price;
f(idx.hshort) = p.shortPenalty;
f(idx.pcurt) = p.curtailPenalty * p.dt;
f(idx.ystart) = p.startCost;

% 等式：电功率平衡、BESS状态、储氢状态、氢需求平衡。
Aeq = zeros(4*n, nvar);
beq = zeros(4*n, 1);
prodCoef = 1000 * p.dt / p.sec;
for t = 1:n
    r = t;
    Aeq(r, idx.pel(t)) = 1;
    Aeq(r, idx.pexp(t)) = 1;
    Aeq(r, idx.pch(t)) = 1;
    Aeq(r, idx.pdis(t)) = -1;
    Aeq(r, idx.pcurt(t)) = 1;
    beq(r) = D.wind_power_mw(t) - D.critical_load_mw(t);

    r = n + t;
    Aeq(r, idx.energy(t)) = 1;
    Aeq(r, idx.pch(t)) = -p.etaCharge * p.dt;
    Aeq(r, idx.pdis(t)) = p.dt / p.etaDischarge;
    if t == 1
        beq(r) = p.bessInitial;
    else
        Aeq(r, idx.energy(t-1)) = -1;
    end

    r = 2*n + t;
    Aeq(r, idx.h2stock(t)) = 1;
    Aeq(r, idx.pel(t)) = -prodCoef;
    Aeq(r, idx.hsale(t)) = 1;
    if t == 1
        beq(r) = p.h2Initial;
    else
        Aeq(r, idx.h2stock(t-1)) = -1;
    end

    r = 3*n + t;
    Aeq(r, idx.hsale(t)) = 1;
    Aeq(r, idx.hshort(t)) = 1;
    beq(r) = D.h2_demand_kg_h(t) * p.dt;
end

% 不等式：最小负荷、启停、BESS充放互斥与周期末状态。
A = zeros(5*n + 2, nvar);
b = zeros(5*n + 2, 1);
for t = 1:n
    r = t;
    A(r, idx.pel(t)) = 1;
    A(r, idx.u(t)) = -p.pRated;

    r = n + t;
    A(r, idx.pel(t)) = -1;
    A(r, idx.u(t)) = p.pMin;

    r = 2*n + t;
    A(r, idx.u(t)) = 1;
    A(r, idx.ystart(t)) = -1;
    if t == 1
        b(r) = p.uInitial;
    else
        A(r, idx.u(t-1)) = -1;
    end

    r = 3*n + t;
    A(r, idx.pch(t)) = 1;
    A(r, idx.z(t)) = -p.bessChargeMax;

    r = 4*n + t;
    A(r, idx.pdis(t)) = 1;
    A(r, idx.z(t)) = p.bessDischargeMax;
    b(r) = p.bessDischargeMax;
end
A(5*n + 1, idx.energy(end)) = -1;
b(5*n + 1) = -p.bessInitial;
A(5*n + 2, idx.h2stock(end)) = -1;
b(5*n + 2) = -p.h2Initial;

options = optimoptions('intlinprog', 'Display', 'off');
[x, ~, exitflag, output] = intlinprog(f, intcon, A, b, Aeq, beq, lb, ub, options);
if exitflag <= 0 || isempty(x)
    error('intlinprog未得到可行最优解，exitflag=%d，信息：%s', exitflag, output.message);
end

result = assemble_result(D, p, x(idx.pel), x(idx.u), x(idx.pexp), ...
    x(idx.pch), x(idx.pdis), x(idx.energy), x(idx.h2stock), ...
    x(idx.hsale), x(idx.hshort), x(idx.pcurt), x(idx.ystart));
end


%% 无工具箱时的透明规则调度
function result = dispatch_rule(D, p)
n = height(D);
pel = zeros(n,1); u = zeros(n,1); pexp = zeros(n,1);
pch = zeros(n,1); pdis = zeros(n,1); energy = zeros(n,1);
h2stock = zeros(n,1); hsale = zeros(n,1); hshort = zeros(n,1);
pcurt = zeros(n,1); ystart = zeros(n,1);

ePrev = p.bessInitial;
hPrev = p.h2Initial;
uPrev = p.uInitial;
prodCoef = 1000 * p.dt / p.sec;
h2MarginalValue = 1000 / p.sec * (p.h2Price - p.h2VariableCost);

for t = 1:n
    surplus = D.wind_power_mw(t) - D.critical_load_mw(t);
    if surplus < 0
        pdis(t) = min([p.bessDischargeMax, ePrev * p.etaDischarge / p.dt, -surplus]);
        surplus = surplus + pdis(t);
    end
    surplus = max(surplus, 0);

    maxProdByTank = max(0, p.h2Capacity - hPrev + D.h2_demand_kg_h(t) * p.dt);
    pelTankLimit = maxProdByTank / prodCoef;
    pelCap = min(p.pRated * D.electrolyzer_availability(t), pelTankLimit);
    exportCap = p.cableCapacity * D.tx_availability(t);
    preferHydrogen = h2MarginalValue >= D.electricity_price_cny_mwh(t) || exportCap == 0;

    if preferHydrogen
        pel(t) = min(pelCap, surplus);
        pel(t) = enforce_minimum_load(pel(t), pelCap, surplus, p.pMin);
        surplus = surplus - pel(t);
        pexp(t) = min(exportCap, surplus);
        surplus = surplus - pexp(t);
    else
        pexp(t) = min(exportCap, surplus);
        surplus = surplus - pexp(t);
        pel(t) = min(pelCap, surplus);
        pel(t) = enforce_minimum_load(pel(t), pelCap, surplus, p.pMin);
        surplus = surplus - pel(t);
    end

    if pel(t) < p.pMin
        surplus = surplus + pel(t);
        pel(t) = 0;
    end
    u(t) = pel(t) >= p.pMin - 1e-9;
    ystart(t) = max(0, u(t) - uPrev);

    pch(t) = min([p.bessChargeMax, ...
        (p.bessEnergyCapacity - ePrev) / (p.etaCharge * p.dt), surplus]);
    pch(t) = max(pch(t), 0);
    surplus = surplus - pch(t);
    pcurt(t) = max(surplus, 0);

    energy(t) = ePrev + p.etaCharge * pch(t) * p.dt ...
        - pdis(t) * p.dt / p.etaDischarge;
    production = prodCoef * pel(t);
    hsale(t) = min(D.h2_demand_kg_h(t) * p.dt, hPrev + production);
    hshort(t) = D.h2_demand_kg_h(t) * p.dt - hsale(t);
    h2stock(t) = hPrev + production - hsale(t);

    ePrev = energy(t);
    hPrev = h2stock(t);
    uPrev = u(t);
end

result = assemble_result(D, p, pel, u, pexp, pch, pdis, energy, ...
    h2stock, hsale, hshort, pcurt, ystart);
end


function pel = enforce_minimum_load(pel, pelCap, surplus, pMin)
if pel > 0 && pel < pMin
    if pelCap >= pMin && surplus >= pMin
        pel = pMin;
    else
        pel = 0;
    end
end
end


%% 统一结果表与校核
function R = assemble_result(D, p, pel, u, pexp, pch, pdis, energy, ...
    h2stock, hsale, hshort, pcurt, ystart)
n = height(D);
h2Production = 1000 * pel * p.dt / p.sec;
water = h2Production * p.waterLPerKg / 1000;
bessNet = pdis - pch;
powerResidual = D.wind_power_mw + pdis - D.critical_load_mw ...
    - pexp - pch - pel - pcurt;

h2Residual = zeros(n, 1);
for t = 1:n
    if t == 1
        hPrev = p.h2Initial;
    else
        hPrev = h2stock(t-1);
    end
    h2Residual(t) = hPrev + h2Production(t) - hsale(t) - h2stock(t);
end

operatingValue = D.electricity_price_cny_mwh .* pexp * p.dt ...
    + p.h2Price .* hsale - p.h2VariableCost .* h2Production ...
    - p.curtailPenalty .* pcurt * p.dt - p.shortPenalty .* hshort ...
    - p.startCost .* ystart;

R = table(D.hour, D.wind_power_mw, D.critical_load_mw, ...
    D.electricity_price_cny_mwh, D.h2_demand_kg_h, ...
    pel, u, pexp, pch, pdis, bessNet, energy, ...
    h2Production, hsale, hshort, h2stock, water, pcurt, ...
    powerResidual, h2Residual, operatingValue, ystart, ...
    'VariableNames', {'hour','wind_power_mw','critical_load_mw', ...
    'electricity_price_cny_mwh','h2_demand_kg_h', ...
    'electrolyzer_power_mw','electrolyzer_on','export_power_mw', ...
    'bess_charge_mw','bess_discharge_mw','bess_net_power_mw', ...
    'bess_energy_mwh','h2_production_kg','h2_sale_kg', ...
    'h2_shortage_kg','h2_inventory_kg','water_demand_m3', ...
    'curtailment_mw','power_balance_residual_mw', ...
    'h2_balance_residual_kg','operating_value_cny','start_event'});

if any((pel > 1e-8 & pel < p.pMin - 1e-8) | pel > p.pRated + 1e-8)
    error('电解槽功率违反0或20%%-100%%额定功率约束。');
end
if any(h2stock < -1e-6 | h2stock > p.h2Capacity + 1e-6)
    error('储氢库存越界。');
end
if any(energy < -1e-6 | energy > p.bessEnergyCapacity + 1e-6)
    error('BESS能量越界。');
end
if max(abs(powerResidual)) > 1e-6 || max(abs(h2Residual)) > 1e-6
    error('守恒残差超限：电力 %.3e MW，氢气 %.3e kg。', ...
        max(abs(powerResidual)), max(abs(h2Residual)));
end
end


function S = make_summary(R, p, mode)
metric = ["solver_mode"; "rated_h2_output"; "full_load_daily_h2"; ...
    "full_load_water"; "minimum_continuous_output"; "demo_h2_production"; ...
    "demo_h2_sold"; "demand_satisfaction"; "electrolyzer_utilization"; ...
    "export_energy"; "curtailment_energy"; "operating_value"; ...
    "max_power_balance_residual"];
value = [NaN; 1000*p.pRated/p.sec; 24*p.pRated/p.sec; ...
    1000*p.pRated/p.sec*p.waterLPerKg/1000; 1000*p.pMin/p.sec; ...
    sum(R.h2_production_kg)/1000; sum(R.h2_sale_kg)/1000; ...
    100*sum(R.h2_sale_kg)/(sum(R.h2_sale_kg)+sum(R.h2_shortage_kg)); ...
    100*sum(R.electrolyzer_power_mw)/(height(R)*p.pRated); ...
    sum(R.export_power_mw)*p.dt; sum(R.curtailment_mw)*p.dt; ...
    sum(R.operating_value_cny)/1000; max(abs(R.power_balance_residual_mw))];
unit = ["-"; "kg/h"; "t/d"; "m3/h"; "kg/h"; "t/24h"; "t/24h"; ...
    "%"; "%"; "MWh"; "MWh"; "kCNY/24h"; "MW"];
note = repmat("", numel(metric), 1);
note(1) = mode;
note(2) = "100 MW / 56.77 kWh/kg";
note(3) = "额定点理论值";
note(6:end) = "24 h演示结果，非实测";
S = table(metric, value, unit, note);
end


%% 五类场景
function S = run_scenarios(D, p)
names = ["基准运行"; "海缆停运"; "低风持续"; "电解槽故障"; "储氢满仓"];
ncase = numel(names);
h2ProductionT = zeros(ncase,1); h2SoldT = zeros(ncase,1);
satisfaction = zeros(ncase,1); curtailment = zeros(ncase,1);
exportEnergy = zeros(ncase,1); utilization = zeros(ncase,1);
operatingValue = zeros(ncase,1); solverMode = strings(ncase,1);

for k = 1:ncase
    Di = D;
    pi = p;
    switch k
        case 2
            Di.tx_availability(9:16) = 0;
        case 3
            Di.wind_power_mw = 0.65 * Di.wind_power_mw;
        case 4
            Di.electrolyzer_availability(10:15) = 0;
        case 5
            pi.h2Initial = 0.95 * pi.h2Capacity;
    end
    [R, ~] = run_dispatch(Di, pi);
    h2ProductionT(k) = sum(R.h2_production_kg) / 1000;
    h2SoldT(k) = sum(R.h2_sale_kg) / 1000;
    satisfaction(k) = 100 * sum(R.h2_sale_kg) / ...
        (sum(R.h2_sale_kg) + sum(R.h2_shortage_kg));
    curtailment(k) = sum(R.curtailment_mw) * pi.dt;
    exportEnergy(k) = sum(R.export_power_mw) * pi.dt;
    utilization(k) = 100 * sum(R.electrolyzer_power_mw) / ...
        (height(R) * pi.pRated);
    operatingValue(k) = sum(R.operating_value_cny) / 1000;
    solverMode(k) = R.solver_mode(1);
end

S = table(names, h2ProductionT, h2SoldT, satisfaction, curtailment, ...
    exportEnergy, utilization, operatingValue, solverMode, ...
    'VariableNames', {'scenario','h2_production_t','h2_sold_t', ...
    'demand_satisfaction_pct','curtailment_mwh','export_mwh', ...
    'electrolyzer_utilization_pct','operating_value_kcny','solver_mode'});
end


%% 电价-氢价敏感性
function S = build_sensitivity_table(p)
electricityPrice = (200:75:650)';
h2Price = (18:4:42)';
[E, H] = ndgrid(electricityPrice, h2Price);
h2Value = 1000 / p.sec .* (H - p.h2VariableCost);
difference = h2Value - E;
preferred = repmat("外送优先", size(difference));
preferred(difference >= 0) = "制氢优先";
S = table(E(:), H(:), h2Value(:), difference(:), preferred(:), ...
    'VariableNames', {'electricity_price_cny_mwh','h2_price_cny_kg', ...
    'h2_marginal_value_cny_mwh','value_difference_cny_mwh', ...
    'preferred_route'});
end


%% 六幅插图
function make_all_figures(D, R, S, sensitivity, p, rootDir)
set(groot, 'defaultAxesFontName', 'Microsoft YaHei');
set(groot, 'defaultAxesFontSize', 15);
set(groot, 'defaultTextFontName', 'Microsoft YaHei');
set(groot, 'defaultLineLineWidth', 2.0);

% 图1 系统耦合关系（固定坐标，避免自动布局造成标签倾斜或裁切）
f = figure('Color','w','Position',[100 100 1600 900]);
axes('Position',[0 0 1 1],'Visible','off');
titleBox = annotation(f,'textbox',[0.20 0.91 0.60 0.06], ...
    'String','Blue Hub 电—氢—储耦合关系', 'EdgeColor','none', ...
    'HorizontalAlignment','center','FontSize',20,'FontWeight','bold');
boxPos = [0.04 0.62 0.14 0.10; 0.25 0.62 0.14 0.10; ...
          0.48 0.78 0.14 0.10; 0.48 0.62 0.14 0.10; ...
          0.48 0.46 0.14 0.10; 0.48 0.28 0.14 0.10; ...
          0.25 0.28 0.14 0.10; 0.70 0.28 0.14 0.10; ...
          0.85 0.28 0.12 0.10; 0.48 0.10 0.14 0.10];
labels = {'风电/光伏','海上母线','关键负荷','海缆外送','BESS', ...
          'PEM电解槽','供水系统','储氢系统','氢气用户','弃电'};
for k = 1:numel(labels)
    annotation(f,'textbox',boxPos(k,:), 'String',labels{k}, ...
        'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'FontSize',16,'FontWeight','bold','LineWidth',1.8, ...
        'EdgeColor',[0.12 0.40 0.62],'BackgroundColor',[0.93 0.97 0.99]);
end
arrowStyle = {'LineWidth',2.2,'Color',[0.25 0.42 0.55],'HeadLength',12,'HeadWidth',12};
annotation(f,'arrow',[0.18 0.25],[0.67 0.67],arrowStyle{:});
annotation(f,'arrow',[0.39 0.48],[0.69 0.82],arrowStyle{:});
annotation(f,'arrow',[0.39 0.48],[0.67 0.67],arrowStyle{:});
annotation(f,'doublearrow',[0.39 0.48],[0.63 0.51], ...
    'LineWidth',2.2,'Color',[0.25 0.42 0.55]);
annotation(f,'arrow',[0.39 0.48],[0.63 0.33],arrowStyle{:});
annotation(f,'arrow',[0.39 0.48],[0.33 0.33],arrowStyle{:});
annotation(f,'arrow',[0.62 0.70],[0.33 0.33],arrowStyle{:});
annotation(f,'arrow',[0.84 0.85],[0.33 0.33],arrowStyle{:});
annotation(f,'arrow',[0.39 0.48],[0.62 0.15],arrowStyle{:});
annotation(f,'textbox',[0.30 0.74 0.14 0.04],'String','电力分配', ...
    'EdgeColor','none','FontSize',14,'Color',[0.25 0.35 0.45]);
annotation(f,'textbox',[0.62 0.35 0.08 0.04],'String','H_2', ...
    'Interpreter','tex','EdgeColor','none','FontSize',15,'Color',[0.25 0.35 0.45]);
exportgraphics(f, fullfile(rootDir,'fig01_system_coupling.png'),'Resolution',300);
close(f);

% 图2 电解槽可行域、产氢和用水
f = figure('Color','w','Position',[100 100 1500 900]);
P = linspace(0, p.pRated, 501);
feasible = P == 0 | P >= p.pMin;
h2 = nan(size(P)); water = nan(size(P));
h2(feasible) = 1000 * P(feasible) / p.sec;
water(feasible) = h2(feasible) * p.waterLPerKg / 1000;
yyaxis left;
patch([0 p.pMin p.pMin 0], [0 0 1900 1900], [0.90 0.92 0.94], ...
    'EdgeColor','none','FaceAlpha',0.85); hold on;
plot(P, h2, 'Color',[0.05 0.45 0.70], 'LineWidth',2.6);
ylabel('产氢量 / (kg·h^{-1})', 'FontSize',16);
ylim([0 1900]);
yyaxis right;
plot(P, water, '--', 'Color',[0.10 0.60 0.40], 'LineWidth',2.6);
ylabel('饮用水需求 / (m^3·h^{-1})', 'FontSize',16);
ylim([0 32]);
xline(p.pMin, ':', '20 MW最小连续负荷', 'FontSize',15, 'LineWidth',2);
text(7, 25, '不可连续运行区', 'FontSize',15, 'Color',[0.35 0.35 0.35]);
xlabel('电解槽交流侧功率 / MW', 'FontSize',16);
title('电解槽功率—产氢—用水关系及可行域', 'FontSize',19, 'FontWeight','bold');
legend({'0–20 MW不可连续运行','产氢量','饮用水需求'}, ...
    'Location','northwest','FontSize',15);
grid on; box on;
exportgraphics(f, fullfile(rootDir,'fig02_electrolyzer_envelope.png'),'Resolution',300);
close(f);

% 图3 24 h功率调度
f = figure('Color','w','Position',[100 100 1600 900]);
stairs(D.hour, D.wind_power_mw, '-', 'Color',[0.15 0.55 0.35], 'LineWidth',2.4); hold on;
stairs(D.hour, R.export_power_mw, '-', 'Color',[0.20 0.40 0.75], 'LineWidth',2.2);
stairs(D.hour, R.electrolyzer_power_mw, '-', 'Color',[0.85 0.35 0.16], 'LineWidth',2.4);
stairs(D.hour, R.bess_net_power_mw, '-', 'Color',[0.55 0.30 0.68], 'LineWidth',2.1);
stairs(D.hour, D.critical_load_mw, '--', 'Color',[0.20 0.20 0.20], 'LineWidth',2.0);
xlabel('时段 / h', 'FontSize',16); ylabel('功率 / MW', 'FontSize',16);
title('24 h 可再生能源分配与协同调度', 'FontSize',19, 'FontWeight','bold');
legend({'可再生能源','海缆外送','电解槽','BESS净放电','关键负荷'}, ...
    'Location','northoutside','NumColumns',3,'FontSize',15);
xlim([1 24]); xticks(1:2:24); grid on; box on;
exportgraphics(f, fullfile(rootDir,'fig03_24h_power_dispatch.png'),'Resolution',300);
close(f);

% 图4 产氢、需求与库存
f = figure('Color','w','Position',[100 100 1600 900]);
yyaxis left;
b = bar(D.hour, R.h2_production_kg, 0.68, 'FaceColor',[0.16 0.58 0.72], ...
    'EdgeColor','none'); hold on;
d = plot(D.hour, D.h2_demand_kg_h * p.dt, '--o', 'Color',[0.82 0.32 0.18], ...
    'MarkerSize',5,'LineWidth',2.2);
ylabel('产氢量与需求 / kg', 'FontSize',16);
yyaxis right;
invLine = plot(D.hour, R.h2_inventory_kg/1000, '-s', 'Color',[0.45 0.26 0.62], ...
    'MarkerSize',5,'LineWidth',2.4);
ylabel('储氢库存 / t', 'FontSize',16);
xlabel('时段 / h', 'FontSize',16);
title('24 h 产氢、需求与储氢库存', 'FontSize',19, 'FontWeight','bold');
legend([b d invLine], {'产氢量','氢需求','储氢库存'}, ...
    'Location','northoutside','NumColumns',3,'FontSize',15);
xlim([1 24]); xticks(1:2:24); grid on; box on;
exportgraphics(f, fullfile(rootDir,'fig04_hydrogen_inventory.png'),'Resolution',300);
close(f);

% 图5 场景对比
f = figure('Color','w','Position',[100 100 1700 1000]);
tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
nexttile; bar(S.h2_production_t, 'FaceColor',[0.12 0.52 0.66]);
title('产氢量 / t','FontSize',17); grid on;
nexttile; bar(S.demand_satisfaction_pct, 'FaceColor',[0.20 0.62 0.42]);
title('需求满足率 / %','FontSize',17); ylim([0 105]); grid on;
nexttile; bar(S.curtailment_mwh, 'FaceColor',[0.85 0.50 0.16]);
title('弃电量 / MWh','FontSize',17); grid on;
nexttile; bar(S.operating_value_kcny, 'FaceColor',[0.38 0.34 0.66]);
title('运行价值 / 千元','FontSize',17); grid on;
for ax = findall(f,'Type','axes')'
    ax.XTick = 1:height(S);
    ax.XTickLabel = S.scenario;
    ax.XTickLabelRotation = 18;
    ax.FontSize = 14;
end
title(tl, '五类运行场景的关键指标比较', 'FontSize',19, 'FontWeight','bold');
exportgraphics(f, fullfile(rootDir,'fig05_scenario_comparison.png'),'Resolution',300);
close(f);

% 图6 电价—氢价边际价值差
eVals = unique(sensitivity.electricity_price_cny_mwh);
hVals = unique(sensitivity.h2_price_cny_kg);
Z = reshape(sensitivity.value_difference_cny_mwh, numel(eVals), numel(hVals));
f = figure('Color','w','Position',[100 100 1500 950]);
imagesc(hVals, eVals, Z); set(gca,'YDir','normal');
colormap(turbo); cb = colorbar; cb.Label.String = '制氢相对外送的边际价值差 / (CNY·MWh^{-1})';
cb.Label.FontSize = 15;
hold on; contour(hVals, eVals, Z, [0 0], 'k-', 'LineWidth',3);
for i = 1:numel(eVals)
    for j = 1:numel(hVals)
        text(hVals(j), eVals(i), sprintf('%.0f', Z(i,j)), ...
            'HorizontalAlignment','center','FontSize',12,'Color','k');
    end
end
xlabel('氢价 / (CNY·kg^{-1})', 'FontSize',16);
ylabel('上网电价 / (CNY·MWh^{-1})', 'FontSize',16);
title('电价—氢价条件下的制氢/外送切换边界', 'FontSize',19, 'FontWeight','bold');
subtitle('黑线为边际价值相等；正值区域倾向制氢', 'FontSize',15);
exportgraphics(f, fullfile(rootDir,'fig06_economic_heatmap.png'),'Resolution',300);
close(f);
end
