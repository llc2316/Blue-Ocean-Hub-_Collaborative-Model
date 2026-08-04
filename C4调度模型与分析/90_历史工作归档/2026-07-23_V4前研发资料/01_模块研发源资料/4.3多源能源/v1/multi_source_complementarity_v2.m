function out = multi_source_complementarity_v2(in, p)
%MULTI_SOURCE_COMPLEMENTARITY_V2 4.3源侧聚合 + 4.4母线平衡 + 4.5接口。
%
% 模型边界：
%   4.3 计算风/光/潮的可用、实际、预测、指令、互补指标与联合场景；
%   4.4 建立能源岛公共电母线的端口功率守恒；
%   4.5 只通过“储能向母线注入为正”的功率接口耦合，不计算SOC、SOH、
%       构网下垂、VSG、黑启动、电解槽或储氢状态；
%   4.8/4.9 上层EMS提供各端口计划与逐源指令，本函数不做经济调度。
%
% 统一符号：
%   发电源、其他电源和储能放电为母线正注入；
%   电力外送、储能充电、制氢、算力、海洋用能、辅机和损耗为母线消耗。
%   pStorageActual > 0：储能放电；pStorageActual < 0：储能充电。
%
% 必需输入 in（4.3）：
%   time        N×1，统一时间轴，s
%   pAvailable  N×S，各源在源侧公共汇集点的可用净有功，W
%   pActual     N×S，各源实际净有功，W
%   pForecast   N×S，各源点预测净有功，W
%
% 可选输入 in（4.3）：
%   pCommand    N×S，EMS逐源指令；默认等于pAvailable
%   qMin/qMax   N×S，各源当前运行点无功能力，var
%   qualityFlag N×S，数据质量标志；默认true
%   scenarioPower N×S×K，保持源间和时间相关性的联合场景，W
%
% 可选输入 in（4.4端口计划/实测）：均为标量或N×1，默认0
%   pExport          对外送电功率
%   pElectrolyzer    电解制氢用电
%   pCompute         算力中心总用电（含其定义口径内的冷却等用电）
%   pMarine          海洋综合用能
%   pAuxiliary       能源岛公共辅机用电
%   pBusLoss         公共母线后变压器/集电/变流等损耗
%   pOtherInjection  燃料电池、备用电源或允许的外部购电等其他注入
%   pStorageActual   4.5储能模型实际注入；若缺省，仅计算所需储能功率
%
% 必需参数 p（4.2）：
%   sourceCapacity              1×S，各源额定容量，W
%   metricWindowsSeconds        1×L，互补性评价尺度，s
%   longDurationWindowSeconds   快慢缺口诊断低通窗口，s
%   firmThresholdFraction       低出力阈值（总装机比例），0～1
%
% 关键输出：
%   4.3 out.source、out.aggregate、out.metrics、out.scenario；
%   4.4 out.ports、out.balance.storageRequired；
%   4.5 out.balance.storageActual/mismatchAfterStorage。

requiredIn = {'time','pAvailable','pActual','pForecast'};
requiredP = {'sourceCapacity','metricWindowsSeconds', ...
    'longDurationWindowSeconds','firmThresholdFraction'};
for k = 1:numel(requiredIn)
    assert(isfield(in, requiredIn{k}), '缺少输入 in.%s。', requiredIn{k});
end
for k = 1:numel(requiredP)
    assert(isfield(p, requiredP{k}), '缺少参数 p.%s。', requiredP{k});
end

t = in.time(:);
pAvailable = double(in.pAvailable);
pActual = double(in.pActual);
pForecast = double(in.pForecast);
[N, S] = size(pAvailable);

assert(N >= 3 && numel(t) == N && all(isfinite(t)) && all(diff(t) > 0), ...
    'time必须有限、严格递增且至少包含3个样本。');
assert(isequal(size(pActual), [N S]) && isequal(size(pForecast), [N S]), ...
    'pAvailable、pActual和pForecast尺寸必须一致。');
assert(all(isfinite(pAvailable), 'all') && all(isfinite(pActual), 'all') && ...
    all(isfinite(pForecast), 'all'), '功率输入包含非有限值。');

capacity = reshape(double(p.sourceCapacity), 1, []);
assert(numel(capacity) == S && all(capacity > 0), ...
    'sourceCapacity必须为长度S的正数向量。');
assert(all(p.metricWindowsSeconds > 0) && p.longDurationWindowSeconds > 0, ...
    '评价窗口必须为正。');
assert(p.firmThresholdFraction >= 0 && p.firmThresholdFraction <= 1, ...
    'firmThresholdFraction应位于[0,1]。');

dtVector = diff(t);
dt = median(dtVector);
assert(max(abs(dtVector-dt)) <= max(1e-6, 0.01*dt), ...
    '聚合函数要求近似等时间步；请先对齐和重采样。');

% ---------- 4.3 多源能源供给模型 ----------
% 负值通常意味着测点口径或数据清洗错误；不在聚合层静默截断。
assert(all(pAvailable >= 0,'all') && all(pActual >= 0,'all') && ...
    all(pForecast >= 0,'all'), ...
    'pAvailable、pActual和pForecast必须为非负源侧净注入。');
pCommandRaw = optionalNM(in, 'pCommand', pAvailable, N, S);
pCommand = min(max(pCommandRaw, 0), pAvailable);
qMin = optionalNM(in, 'qMin', zeros(N,S), N, S);
qMax = optionalNM(in, 'qMax', zeros(N,S), N, S);
quality = optionalNM(in, 'qualityFlag', true(N,S), N, S) > 0.5;
assert(all(qMin <= qMax, 'all'), 'qMin不得大于qMax。');

aggregateAvailable = sum(pAvailable, 2);
aggregateActual = sum(pActual, 2);
aggregateForecast = sum(pForecast, 2);
aggregateCommand = sum(pCommand, 2);
sourceCurtailmentCommand = max(0, pAvailable-pCommand);
sourceUnusedAvailableProxy = max(0, pAvailable-pActual);
sourceAvailabilityExcess = max(0, pActual-pAvailable);
sourceHeadroomUp = max(0, pAvailable-pCommand);
sourceHeadroomDown = max(0, pCommand);
sourceTrackingError = pActual-pCommand;
sourceRamp = [zeros(1,S); diff(pActual,1,1)./dt];
aggregateRamp = sum(sourceRamp,2);
forecastError = pActual-pForecast;
aggregateForecastError = sum(forecastError,2);
aggregateQMin = sum(qMin,2);
aggregateQMax = sum(qMax,2);
validRow = all(quality,2);

% 联合场景只做聚合，不在此独立抽样，避免破坏源间/时间相关性。
scenarioAggregate = [];
if isfield(in,'scenarioPower') && ~isempty(in.scenarioPower)
    scen = double(in.scenarioPower);
    assert(size(scen,1)==N && size(scen,2)==S, ...
        'scenarioPower必须为N×S×K。');
    assert(all(isfinite(scen),'all') && all(scen >= 0,'all'), ...
        'scenarioPower必须为有限的非负源侧净注入。');
    K = size(scen,3);
    scenarioAggregate = reshape(sum(scen,2),N,K);
end

% ---------- 4.4 能源岛公共母线端口和平衡 ----------
pExport = optionalN1(in,'pExport',0,N);
pElectrolyzer = optionalN1(in,'pElectrolyzer',0,N);
pCompute = optionalN1(in,'pCompute',0,N);
pMarine = optionalN1(in,'pMarine',0,N);
pAuxiliary = optionalN1(in,'pAuxiliary',0,N);
pBusLoss = optionalN1(in,'pBusLoss',0,N);
pOtherInjection = optionalN1(in,'pOtherInjection',0,N);

loads = [pExport,pElectrolyzer,pCompute,pMarine,pAuxiliary,pBusLoss];
assert(all(loads >= 0,'all'), ...
    '外送、制氢、算力、海洋用能、辅机和损耗端口必须为非负功率。');
assert(all(pOtherInjection >= 0), 'pOtherInjection必须为非负注入。');

totalDemand = sum(loads,2);
totalInjectionWithoutStorage = aggregateActual+pOtherInjection;

% 正值表示4.5储能需放电，负值表示可吸收充电；它是耦合需求而非控制指令。
pStorageRequired = totalDemand-totalInjectionWithoutStorage;
balanceMismatchWithoutStorage = totalInjectionWithoutStorage-totalDemand;
forecastStorageRequired = totalDemand-(aggregateForecast+pOtherInjection);

% 联合场景下的储能需求，用于备用/容量与机会约束，不是场景控制指令。
scenarioStorageRequired = [];
if ~isempty(scenarioAggregate)
    scenarioStorageRequired = totalDemand-pOtherInjection-scenarioAggregate;
end

% 快慢分解只是4.5选型/容量需求诊断，实际分配由储能模型和EMS完成。
nLong = max(1,round(p.longDurationWindowSeconds/dt));
residualSlow = movmean(pStorageRequired,[nLong-1 0],1,'Endpoints','shrink');
residualFast = pStorageRequired-residualSlow;

% ---------- 4.5 构网型混合储能接口 ----------
storageActualProvided = isfield(in,'pStorageActual') && ~isempty(in.pStorageActual);
if storageActualProvided
    pStorageActual = optionalN1(in,'pStorageActual',0,N);
    balanceMismatchAfterStorage = totalInjectionWithoutStorage+ ...
        pStorageActual-totalDemand;
else
    pStorageActual = [];
    balanceMismatchAfterStorage = [];
end

% ---------- 多时间尺度互补性诊断 ----------
scales = reshape(double(p.metricWindowsSeconds),1,[]);
L = numel(scales);
corrPower = nan(S,S,L);
corrRamp = nan(S,S,L);
rampSmoothingIndex = nan(1,L);
aggregateCV = nan(1,L);
firmPowerP05 = nan(1,L);
lowOutputFraction = nan(1,L);
cf = pActual./capacity;
totalCapacity = sum(capacity);
threshold = p.firmThresholdFraction*totalCapacity;

for ell = 1:L
    nWin = max(1,round(scales(ell)/dt));
    cfScale = movmean(cf,[nWin-1 0],1,'Endpoints','shrink');
    pScale = movmean(pActual,[nWin-1 0],1,'Endpoints','shrink');
    rows = validRow & all(isfinite(cfScale),2);
    if nnz(rows) < 3
        continue;
    end
    corrPower(:,:,ell) = corrcoef(cfScale(rows,:));
    rampScale = diff(cfScale(rows,:),1,1);
    if size(rampScale,1) >= 2
        corrRamp(:,:,ell) = corrcoef(rampScale);
    end

    rampIndividual = diff(pScale(rows,:),1,1);
    rampTotal = sum(rampIndividual,2);
    denom = 0;
    for s = 1:S
        denom = denom+stdFinite(rampIndividual(:,s));
    end
    if denom > 0
        rampSmoothingIndex(ell) = 1-stdFinite(rampTotal)/denom;
    end

    aggregateScale = sum(pScale(rows,:),2);
    mu = mean(aggregateScale);
    if abs(mu) > eps
        aggregateCV(ell) = stdFinite(aggregateScale)/abs(mu);
    end
    firmPowerP05(ell) = empiricalQuantile(aggregateScale,0.05);
    lowOutputFraction(ell) = mean(aggregateScale<threshold);
end

% ---------- 输出 ----------
out = struct;
out.time = t;

out.source = struct;
out.source.available = pAvailable;
out.source.actual = pActual;
out.source.forecast = pForecast;
out.source.command = pCommand;
out.source.commandCurtailment = sourceCurtailmentCommand;
out.source.unusedAvailableProxy = sourceUnusedAvailableProxy;
out.source.availabilityExcess = sourceAvailabilityExcess;
out.source.headroomUp = sourceHeadroomUp;
out.source.headroomDown = sourceHeadroomDown;
out.source.trackingError = sourceTrackingError;
out.source.ramp = sourceRamp;
out.source.qMin = qMin;
out.source.qMax = qMax;
out.source.qualityFlag = quality;

out.aggregate = struct;
out.aggregate.available = aggregateAvailable;
out.aggregate.actual = aggregateActual;
out.aggregate.forecast = aggregateForecast;
out.aggregate.command = aggregateCommand;
out.aggregate.forecastError = aggregateForecastError;
out.aggregate.ramp = aggregateRamp;
out.aggregate.qMin = aggregateQMin;
out.aggregate.qMax = aggregateQMax;
out.aggregate.validRow = validRow;

out.ports = struct('export',pExport,'electrolyzer',pElectrolyzer, ...
    'compute',pCompute,'marine',pMarine,'auxiliary',pAuxiliary, ...
    'busLoss',pBusLoss,'otherInjection',pOtherInjection, ...
    'totalDemand',totalDemand,'injectionWithoutStorage', ...
    totalInjectionWithoutStorage);

out.balance = struct;
out.balance.storageRequired = pStorageRequired;
out.balance.forecastStorageRequired = forecastStorageRequired;
out.balance.mismatchWithoutStorage = balanceMismatchWithoutStorage;
out.balance.storageActualProvided = storageActualProvided;
out.balance.storageActual = pStorageActual;
out.balance.mismatchAfterStorage = balanceMismatchAfterStorage;
out.balance.residualFast = residualFast;
out.balance.residualSlow = residualSlow;

out.scenario = struct('aggregate',scenarioAggregate, ...
    'storageRequired',scenarioStorageRequired);
out.metrics = struct('scaleSeconds',scales, ...
    'powerCorrelation',corrPower,'rampCorrelation',corrRamp, ...
    'rampSmoothingIndex',rampSmoothingIndex, ...
    'aggregateCoefficientVariation',aggregateCV, ...
    'firmPowerP05',firmPowerP05, ...
    'lowOutputFraction',lowOutputFraction);

out.diagnostics = struct( ...
    'availableEnergyMWh',trapz(t,aggregateAvailable)/3.6e9, ...
    'actualEnergyMWh',trapz(t,aggregateActual)/3.6e9, ...
    'commandCurtailmentMWh',trapz(t,sum(sourceCurtailmentCommand,2))/3.6e9, ...
    'unusedAvailableProxyMWh',trapz(t,sum(sourceUnusedAvailableProxy,2))/3.6e9, ...
    'availabilityExcessMWh',trapz(t,sum(sourceAvailabilityExcess,2))/3.6e9, ...
    'demandEnergyMWh',trapz(t,totalDemand)/3.6e9, ...
    'storageDischargeRequirementMWh',trapz(t,max(pStorageRequired,0))/3.6e9, ...
    'storageChargeOpportunityMWh',trapz(t,max(-pStorageRequired,0))/3.6e9, ...
    'commandSaturationMWh',trapz(t,sum(abs(pCommandRaw-pCommand),2))/3.6e9, ...
    'invalidFraction',1-mean(validRow));
if storageActualProvided
    out.diagnostics.absoluteMismatchEnergyMWh = ...
        trapz(t,abs(balanceMismatchAfterStorage))/3.6e9;
else
    out.diagnostics.absoluteMismatchEnergyMWh = NaN;
end
end

function value = optionalNM(s,fieldName,defaultValue,N,S)
if isfield(s,fieldName)
    value = s.(fieldName);
else
    value = defaultValue;
end
if isscalar(value)
    value = repmat(double(value),N,S);
elseif isvector(value) && numel(value)==N
    value = repmat(reshape(double(value),N,1),1,S);
elseif isvector(value) && numel(value)==S
    value = repmat(reshape(double(value),1,S),N,1);
elseif isequal(size(value),[N S])
    value = double(value);
else
    error('%s必须为标量、N×1、1×S或N×S。',fieldName);
end
assert(all(isfinite(value),'all'), '%s包含非有限值。',fieldName);
end

function value = optionalN1(s,fieldName,defaultValue,N)
if isfield(s,fieldName)
    value = s.(fieldName);
else
    value = defaultValue;
end
if isscalar(value)
    value = repmat(double(value),N,1);
elseif isvector(value) && numel(value)==N
    value = reshape(double(value),N,1);
else
    error('%s必须为标量或N×1。',fieldName);
end
assert(all(isfinite(value)), '%s包含非有限值。',fieldName);
end

function s = stdFinite(x)
x = x(isfinite(x));
if numel(x)<2
    s = NaN;
else
    s = std(x,0);
end
end

function q = empiricalQuantile(x,p)
x = sort(x(isfinite(x)));
if isempty(x)
    q = NaN;
    return;
end
position = 1+(numel(x)-1)*p;
lo = floor(position); hi = ceil(position);
if lo==hi
    q = x(lo);
else
    q = x(lo)+(position-lo)*(x(hi)-x(lo));
end
end
