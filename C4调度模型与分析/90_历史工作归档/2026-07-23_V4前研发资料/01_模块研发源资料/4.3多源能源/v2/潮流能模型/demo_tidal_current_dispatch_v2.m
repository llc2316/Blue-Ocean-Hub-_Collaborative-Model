% 蓝海枢纽：潮流能调度级模型 V2 演示
% 注意：本文件所有设备曲线、阈值和场景均为[假设值，待企业调研校准]。
clear; clc;

%% 48 h、5 min时间步；3台同型机组
dt = 300;
t = (0:dt:48*3600)';
N = numel(t); M = 3;
hour = t / 3600;

% 有符号潮流：半日分潮 + 日分潮 + 小幅残差，仅用于演示。
uBase = 2.65*sin(2*pi*hour/12.42) + 0.22*sin(2*pi*hour/24.0 + 0.6);
u = repmat(uBase, 1, M);

% 演示阵列方向相关尾流。真实项目须由ADCP、CFD/水动力阵列模型标定。
wake = ones(N, M);
flood = uBase >= 0;
wake(flood,2) = 0.95; wake(flood,3) = 0.90;
wake(~flood,1) = 0.90; wake(~flood,2) = 0.95;

availability = ones(N, M);
availability(hour >= 30 & hour < 34, 2) = 0; % 演示检修
derate = ones(N, M);
derate(hour >= 18 & hour < 22,:) = 0.85;
bio = repmat(linspace(1.00, 0.97, N)', 1, M);

Hs = 1.2 + 0.25*sin(2*pi*hour/9);
Hs(hour >= 38 & hour < 40) = 4.8; % 演示环境停机

farmReference = inf(N,1);
farmReference(hour >= 10 & hour < 14) = 2.4e6;

in = struct;
in.time = t;
in.axialVelocity = u;
in.platformAxialVelocity = 0;
in.wakeVelocityFactor = wake;
in.availabilityState = logical(availability);
in.derateFactor = derate;
in.biofoulingFactor = bio;
in.significantWaveHeight = Hs;
in.farmPowerReference = farmReference;

%% 参数：均为演示假设，不代表LHD、“奋进号”或其他厂家实机
p.ratedPower = 1.0e6 * ones(1,M);
p.ratedApparentPower = 1.10e6 * ones(1,M);

% 机组端电功率标幺曲线；项目应用时替换为GB/T 41342-2022测试曲线。
p.floodCurveSpeed = [0; 0.7; 1.0; 1.3; 1.6; 1.9; 2.2; 2.5; 3.0; 3.5];
p.floodCurvePowerPu = [0; 0; 0.04; 0.14; 0.31; 0.55; 0.80; 1.00; 1.00; 0];
p.ebbCurveSpeed = p.floodCurveSpeed;
p.ebbCurvePowerPu = [0; 0; 0.035; 0.13; 0.29; 0.52; 0.78; 0.98; 1.00; 0];

p.cutInSpeed = 0.7;
p.directionDeadband = 0.15;
p.reorientationDelay = 10*60;
p.maxOperatingSpeed = 3.5;
p.restartSpeed = 3.1;
p.maxOperatingWave = 4.5;
p.restartWave = 3.8;
p.restartDelay = 20*60;
p.rampUpRate = 1.0e6/(10*60);
p.auxiliaryPowerRun = 12e3;
p.auxiliaryPowerStandby = 3e3;
p.collectionLossFraction = 0.025;

out = tidal_current_dispatch_v2(in, p);

%% 结果
figure('Color','w','Name','潮流能调度级模型V2');
tiledlayout(4,1,'TileSpacing','compact');

nexttile;
plot(hour, uBase, 'LineWidth', 1.2); yline(0,'k:');
ylabel('流速 (m/s)'); title('有符号涨落潮输入'); grid on;

nexttile;
plot(hour, Hs, 'LineWidth', 1.1); yline(p.maxOperatingWave,'r--');
ylabel('H_s (m)'); title('波高与停机阈值'); grid on;

nexttile;
plot(hour, out.deviceGrossPower/1e6, 'LineWidth', 1.0);
ylabel('单机 (MW)'); title('各机组端输出'); grid on;

nexttile;
plot(hour, out.farmGrossPower/1e6, 'Color',[0.2 0.5 0.9], 'LineWidth',1.2); hold on;
plot(hour, out.farmNetPower/1e6, 'Color',[0.85 0.25 0.2], 'LineWidth',1.2);
plot(hour, min(farmReference, sum(p.ratedPower))/1e6, 'k--');
ylabel('场站 (MW)'); xlabel('时间 (h)');
legend('毛功率','POI发电注入（辅机独立）','场站指令','Location','best');
title('场站功率接口'); grid on;

fprintf('毛发电量：%.2f MWh\n', out.diagnostics.grossEnergyWh/1e6);
fprintf('POI发电注入电量：%.2f MWh\n', out.diagnostics.netInjectionEnergyWh/1e6);
fprintf('限发电量：%.2f MWh\n', out.diagnostics.curtailedEnergyWh/1e6);
fprintf('辅机用电量：%.2f MWh\n', out.diagnostics.auxiliaryEnergyWh/1e6);
