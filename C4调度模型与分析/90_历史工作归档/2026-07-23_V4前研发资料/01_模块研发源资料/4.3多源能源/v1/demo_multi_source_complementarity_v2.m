% 蓝海枢纽：4.3多源供给—4.4母线平衡—4.5储能接口演示
% 所有容量、曲线、误差、负荷、端口计划和储能功率限值均为
% [假设值，待企业调研校准]，不代表实际项目设备参数。
clear; clc; rng(21);

%% 1. 4.2 集合、参数、变量与统一测点
dt = 300;                         % 5 min [假设值]
t = (0:dt:7*24*3600)';            % 7 d演示
hour = t/3600;
N = numel(t); S = 3;
capacity = [85 10 5]*1e6;         % 风85%+、光10%、潮5% [假设值]

%% 2. 4.3 多源能源供给模型输出
% 三类功率均已换算至“源侧公共汇集点净注入”口径。
windCF = min(1,max(0,0.58 + 0.22*sin(2*pi*hour/31) + ...
    0.12*sin(2*pi*hour/5.5) + 0.05*randn(N,1)));
solarShape = max(0,sin(pi*mod(hour-6,24)/12));
cloud = min(1,max(0.25,0.88 + 0.10*sin(2*pi*hour/37) ...
    - 0.12*randn(N,1)));
pvCF = solarShape.*cloud;
tidalCF = min(1,max(0,abs(sin(2*pi*hour/12.42)).^3));

pAvailable = [windCF*capacity(1),pvCF*capacity(2), ...
    tidalCF*capacity(3)];

% 上层EMS逐源指令。这里仅演示风电高出力时限发，不在本层求最优比例。
pCommand = pAvailable;
highWind = pAvailable(:,1)>72e6;
pCommand(highWind,1) = 72e6;

% 实际出力由指令跟踪和设备状态形成；以下跟踪系数仅为演示假设。
pActual = pCommand;
pActual(:,1) = 0.995*pActual(:,1);
pActual(:,2) = 0.992*pActual(:,2);
pActual(:,3) = 0.990*pActual(:,3);

% 点预测及保持相关性的联合场景。工程版必须由统一概率预测模块提供。
pForecast = max(0,pAvailable.*(1 + [0.03*sin(2*pi*hour/19), ...
    -0.05*sin(2*pi*hour/11),0.015*sin(2*pi*hour/25)]));
K = 20;
scenarioPower = zeros(N,S,K);
commonError = 0.025*randn(N,K);
for k = 1:K
    sourceError = [0.04*randn(N,1),0.08*randn(N,1), ...
        0.02*randn(N,1)];
    scenarioPower(:,:,k) = max(0,pForecast.* ...
        (1+commonError(:,k)+sourceError));
end

% 当前运行点的示意P-Q包络 [假设值，待厂家P-Q能力图校准]。
Sratio = 1.08;
qMax = sqrt(max(0,(Sratio*capacity).^2-pActual.^2));

%% 3. 4.4 能源岛各端口计划
% 下列端口由4.8/4.9智能调度大脑给出，本演示不进行经济优化。
pExport = 45e6 + 7e6*sin(2*pi*hour/24);                 % 电力外送
pElectrolyzer = 10e6 + 5e6*(sin(2*pi*(hour-3)/24)>0);  % 制氢用电
pCompute = 8e6 + 1.5e6*sin(2*pi*(hour-8)/24);          % 算力总用电
pMarine = 1.2e6*ones(N,1);                              % 海洋综合用能
pAuxiliary = 0.8e6*ones(N,1);                           % 公共辅机
pBusLoss = 0.015*(pExport+pElectrolyzer+pCompute+pMarine); % [假设值]
pOtherInjection = zeros(N,1);                           % 未配置燃料电池/外购电

in = struct;
in.time = t;
in.pAvailable = pAvailable;
in.pActual = pActual;
in.pForecast = pForecast;
in.pCommand = pCommand;
in.qMin = -qMax;
in.qMax = qMax;
in.qualityFlag = true(N,S);
in.scenarioPower = scenarioPower;
in.pExport = pExport;
in.pElectrolyzer = pElectrolyzer;
in.pCompute = pCompute;
in.pMarine = pMarine;
in.pAuxiliary = pAuxiliary;
in.pBusLoss = pBusLoss;
in.pOtherInjection = pOtherInjection;

p.sourceCapacity = capacity;
p.metricWindowsSeconds = [dt 3600 6*3600 24*3600];
p.longDurationWindowSeconds = 6*3600;  % [假设值，待储能路线校准]
p.firmThresholdFraction = 0.20;        % [假设值，待可靠性目标校准]

% 第一次计算：只得到4.4对4.5提出的储能功率需求。
outRequirement = multi_source_complementarity_v2(in,p);

%% 4. 4.5构网型混合储能接口（仅演示外部模型回传）
% 下面的饱和器不是完整储能模型，不含SOC、SOH、效率、寿命、VSG或黑启动。
% 它只模拟“外部4.5模型”受功率上限约束后向4.4回传的实际注入。
pStorageDischargeMax = 18e6;   % [假设值]
pStorageChargeMax = 15e6;      % [假设值]
required = outRequirement.balance.storageRequired;
pStorageActual = min(pStorageDischargeMax, ...
    max(-pStorageChargeMax,required));

in.pStorageActual = pStorageActual;
out = multi_source_complementarity_v2(in,p);

%% 5. 守恒与接口检查
assert(all(out.aggregate.available>=0));
assert(all(out.aggregate.qMin<=out.aggregate.qMax));
assert(size(out.scenario.aggregate,2)==K);
reconstructedMismatch = out.aggregate.actual + in.pOtherInjection + ...
    in.pStorageActual - out.ports.totalDemand;
assert(max(abs(reconstructedMismatch-out.balance.mismatchAfterStorage))<1e-6);

%% 6. 可视化
figure('Color','w','Name','多能源互补体系V2：章节接口');
tiledlayout(4,1,'TileSpacing','compact');

nexttile;
area(hour,pActual/1e6); ylabel('MW');
legend('漂浮式风电','漂浮式光伏','潮流能','Location','eastoutside');
title('4.3 源侧统一汇集点实际净功率'); grid on;

nexttile;
plot(hour,out.aggregate.available/1e6,'Color',[0.2 0.55 0.85]); hold on;
plot(hour,out.aggregate.actual/1e6,'k','LineWidth',1.1);
plot(hour,out.aggregate.forecast/1e6,'--','LineWidth',1.0);
ylabel('MW'); legend('可用','实际','预测');
title('4.3 面向4.4的源侧边界'); grid on;

nexttile;
plot(hour,out.ports.totalDemand/1e6,'k','LineWidth',1.1); hold on;
plot(hour,out.aggregate.actual/1e6,'Color',[0.15 0.55 0.25]);
plot(hour,out.balance.storageRequired/1e6,'Color',[0.85 0.25 0.2]);
ylabel('MW'); legend('总需求','源侧实际注入','所需储能注入');
title('4.4 公共母线功率平衡'); grid on;

nexttile;
plot(hour,out.balance.storageRequired/1e6,'Color',[0.4 0.4 0.4]); hold on;
plot(hour,out.balance.storageActual/1e6,'Color',[0.1 0.45 0.85]);
plot(hour,out.balance.mismatchAfterStorage/1e6,'Color',[0.85 0.25 0.2]);
ylabel('MW'); xlabel('时间 (h)');
legend('4.4所需储能功率','4.5回传实际功率','平衡偏差');
title('4.4—4.5 双向接口（正值为储能放电）'); grid on;

fprintf('源侧实际电量：%.2f MWh\n',out.diagnostics.actualEnergyMWh);
fprintf('端口总需求电量：%.2f MWh\n',out.diagnostics.demandEnergyMWh);
fprintf('所需储能放电电量：%.2f MWh\n', ...
    out.diagnostics.storageDischargeRequirementMWh);
fprintf('可供储能吸收电量：%.2f MWh\n', ...
    out.diagnostics.storageChargeOpportunityMWh);
fprintf('受外部储能功率限值影响的绝对失衡电量：%.2f MWh\n', ...
    out.diagnostics.absoluteMismatchEnergyMWh);
fprintf(['注意：storageRequired是4.4提出的耦合需求；storageActual必须由' ...
    '4.5结合SOC和构网约束求解。\n']);
