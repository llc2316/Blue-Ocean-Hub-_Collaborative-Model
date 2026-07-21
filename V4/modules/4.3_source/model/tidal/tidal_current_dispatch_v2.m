function out = tidal_current_dispatch_v2(in, p)
%TIDAL_CURRENT_DISPATCH_V2 潮流能机组/阵列调度级代理模型（V2）
%
% 适用范围：5 min～1 h调度、容量配置、能量平衡与场景分析。
% 不适用范围：叶片载荷、轴系扭振、系泊/基础强度和变流器电磁暂态。
%
% 核心约定：
% 1) in.axialVelocity 是转子扫掠面等效、有符号轴向流速，正/负分别表示涨/落潮；
% 2) 功率曲线是按 IEC TS 62600-200 或 GB/T 41342-2022 获得的
%    “机组端电功率曲线”，因此不再重复乘以 Cp、发电机效率和变流器效率；
% 3) 涨潮和落潮允许采用不同曲线；
% 4) 尾流通过速度折减输入，不使用固定“桩基功率损失系数”；
% 5) 环境停机、换向、可用率、降额、寄生功耗、集电损耗和限发均显式输出。
%
% 必需输入 in：
%   time                  N×1，秒，严格递增
%   axialVelocity         N×M，m/s，场址转子等效轴向流速（有符号）
%
% 可选输入 in（标量、N×1、1×M或N×M均可，除特别说明）：
%   platformAxialVelocity 平台沿转子轴速度，m/s，默认0
%   wakeVelocityFactor    阵列尾流速度因子，默认1，须由水动力模型/实测标定
%   availabilityState     逻辑运行/故障状态，默认1（推荐）
%   availability          旧版逻辑状态字段；只允许0或1，不得传入1-FOR
%   derateFactor          环境/设备降额，0～1，默认1
%   biofoulingFactor      生物附着性能因子，0～1，默认1
%   significantWaveHeight N×1，有义波高，m，默认0
%   farmPowerReference    N×1，公共汇集点有功原始请求，W，默认Inf
%   collectionLossFraction N×1，集电损耗比例；默认使用p中的调度级近似值
%   stateIn               上一滚动周期返回的状态
%
% 参数 p：
%   ratedPower            1×M或标量，单机额定有功，W
%   ratedApparentPower    1×M或标量，单机额定视在功率，VA
%   floodCurveSpeed       K×1，涨潮功率曲线流速坐标，m/s
%   floodCurvePowerPu     K×1，涨潮机组端电功率标幺值
%   ebbCurveSpeed         L×1，落潮功率曲线流速坐标，m/s
%   ebbCurvePowerPu       L×1，落潮机组端电功率标幺值
%   cutInSpeed            切入流速，m/s
%   directionDeadband     换向判定死区，m/s
%   reorientationDelay    涨落潮换向/偏航时间，s
%   maxOperatingSpeed     保护停机流速，m/s
%   restartSpeed          环境停机后的流速复归阈值，m/s
%   maxOperatingWave      保护停机波高，m
%   restartWave           波高复归阈值，m
%   restartDelay          安全条件持续时间，s
%   rampUpRate            单机向上爬坡率，W/s；下降不受限，避免高估可用功率
%   auxiliaryPowerRun     运行寄生功耗，W/台
%   auxiliaryPowerStandby 待机/换向寄生功耗，W/台
%   collectionLossFraction 集电系统有功损耗比例，0～1
%
% 主要输出 out：
%   relativeVelocity, deviceGrossPower, farmGrossPower,
%   auxiliaryPower, collectionLoss, farmNetPower,
%   curtailedPower, mode, reactivePowerMin/Max, diagnostics
%
% 模式编码：0不可用，1静水/低于切入，2换向，3运行，4环境停机，
%           5复归等待，6限发。

arguments
    in struct
    p struct
end

t = in.time(:);
u = in.axialVelocity;
if isvector(u), u = u(:); end
[N, M] = size(u);
assert(numel(t) == N && N >= 2, 'time与axialVelocity行数不一致或样本不足。');
assert(all(isfinite(t)) && all(diff(t) > 0), 'time必须有限且严格递增。');
assert(all(isfinite(u), 'all'), 'axialVelocity包含非有限值。');

required = {'ratedPower','ratedApparentPower','floodCurveSpeed', ...
    'floodCurvePowerPu','ebbCurveSpeed','ebbCurvePowerPu','cutInSpeed', ...
    'directionDeadband','reorientationDelay','maxOperatingSpeed', ...
    'restartSpeed','maxOperatingWave','restartWave','restartDelay', ...
    'rampUpRate','auxiliaryPowerRun','auxiliaryPowerStandby', ...
    'collectionLossFraction'};
for k = 1:numel(required)
    assert(isfield(p, required{k}), '缺少参数 p.%s。', required{k});
end

Pr = expand1M(p.ratedPower, M, 'ratedPower');
Sr = expand1M(p.ratedApparentPower, M, 'ratedApparentPower');
assert(all(Pr > 0) && all(Sr >= Pr), 'ratedPower必须为正且ratedApparentPower不得小于ratedPower。');
validateCurve(p.floodCurveSpeed, p.floodCurvePowerPu, 'flood');
validateCurve(p.ebbCurveSpeed, p.ebbCurvePowerPu, 'ebb');
assert(p.cutInSpeed >= 0 && p.directionDeadband >= 0, '流速阈值不得为负。');
assert(p.maxOperatingSpeed > p.restartSpeed && p.restartSpeed >= p.cutInSpeed, ...
    '应满足 maxOperatingSpeed > restartSpeed >= cutInSpeed。');
assert(p.maxOperatingWave > p.restartWave && p.restartWave >= 0, ...
    '应满足 maxOperatingWave > restartWave >= 0。');
assert(p.reorientationDelay >= 0 && p.restartDelay >= 0 && p.rampUpRate >= 0, ...
    '延迟与爬坡率不得为负。');
assert(p.collectionLossFraction >= 0 && p.collectionLossFraction < 1, ...
    'collectionLossFraction应位于[0,1)。');

vPlatform = expandNM(getfieldDefault(in, 'platformAxialVelocity', 0), N, M, 'platformAxialVelocity'); %#ok<GFLD>
wake = expandNM(getfieldDefault(in, 'wakeVelocityFactor', 1), N, M, 'wakeVelocityFactor'); %#ok<GFLD>
if isfield(in,'availabilityState')
    availability=expandNM(in.availabilityState,N,M,'availabilityState');
else
    availability=expandNM(getfieldDefault(in,'availability',1),N,M,'availability'); %#ok<GFLD>
end
derate = expandNM(getfieldDefault(in, 'derateFactor', 1), N, M, 'derateFactor'); %#ok<GFLD>
bio = expandNM(getfieldDefault(in, 'biofoulingFactor', 1), N, M, 'biofoulingFactor'); %#ok<GFLD>
Hs = expandN1(getfieldDefault(in, 'significantWaveHeight', 0), N, 'significantWaveHeight'); %#ok<GFLD>
Pref = expandN1(getfieldDefault(in, 'farmPowerReference', inf), N, 'farmPowerReference'); %#ok<GFLD>
collectionLossFraction = expandN1(getfieldDefault(in, 'collectionLossFraction', ...
    p.collectionLossFraction), N, 'collectionLossFraction'); %#ok<GFLD>

assert(all(wake >= 0 & wake <= 1, 'all'), 'wakeVelocityFactor应位于[0,1]。');
assert(all(availability==0 | availability==1,'all'), ...
    'availabilityState必须为逻辑/二值状态，不得使用1-FOR逐时折减功率。');
assert(all(derate >= 0 & derate <= 1, 'all'), 'derateFactor应位于[0,1]。');
assert(all(bio >= 0 & bio <= 1, 'all'), 'biofoulingFactor应位于[0,1]。');
assert(all(Hs >= 0) && all(Pref >= 0), '波高和场站功率指令不得为负。');
assert(all(collectionLossFraction >= 0 & collectionLossFraction < 1), ...
    'collectionLossFraction应位于[0,1)。');

uRel = (u - vPlatform) .* wake;
potential = zeros(N, M);
devicePower = zeros(N, M);
mode = ones(N, M, 'uint8');
direction = zeros(N, M, 'int8');
aux = zeros(N, M);

[lastOperationalDirection,reorientElapsed,environmentStopped,restartElapsed, ...
    previousDevicePower]=initial_state(in,M);
requestedGross=zeros(N,1);

for i = 1:N
    if i == 1
        dt = 0;
    else
        dt = t(i) - t(i-1);
    end

    for j = 1:M
        speed = abs(uRel(i,j));
        if speed <= p.directionDeadband
            dirNow = int8(0);
        else
            dirNow = int8(sign(uRel(i,j)));
        end
        direction(i,j) = dirNow;

        if availability(i,j) <= 0
            mode(i,j) = uint8(0);
            aux(i,j) = p.auxiliaryPowerStandby;
            continue;
        end

        severe = speed >= p.maxOperatingSpeed || Hs(i) >= p.maxOperatingWave;
        safeToRestart = speed <= p.restartSpeed && Hs(i) <= p.restartWave;
        if severe
            environmentStopped(j) = true;
            restartElapsed(j) = 0;
            mode(i,j) = uint8(4);
            aux(i,j) = p.auxiliaryPowerStandby;
            continue;
        elseif environmentStopped(j)
            if safeToRestart
                restartElapsed(j) = restartElapsed(j) + dt;
            else
                restartElapsed(j) = 0;
            end
            if restartElapsed(j) < p.restartDelay
                mode(i,j) = uint8(5);
                aux(i,j) = p.auxiliaryPowerStandby;
                continue;
            end
            environmentStopped(j) = false;
            restartElapsed(j) = 0;
        end

        if speed < p.cutInSpeed || dirNow == 0
            mode(i,j) = uint8(1);
            reorientElapsed(j) = 0;
            aux(i,j) = p.auxiliaryPowerStandby;
            continue;
        end

        if lastOperationalDirection(j) == 0
            lastOperationalDirection(j) = dirNow;
        elseif dirNow ~= lastOperationalDirection(j)
            reorientElapsed(j) = reorientElapsed(j) + dt;
            if reorientElapsed(j) < p.reorientationDelay
                mode(i,j) = uint8(2);
                aux(i,j) = p.auxiliaryPowerStandby;
                continue;
            end
            lastOperationalDirection(j) = dirNow;
            reorientElapsed(j) = 0;
        else
            reorientElapsed(j) = 0;
        end

        if dirNow > 0
            pu = interp1(p.floodCurveSpeed(:), p.floodCurvePowerPu(:), speed, 'pchip', 0);
        else
            pu = interp1(p.ebbCurveSpeed(:), p.ebbCurvePowerPu(:), speed, 'pchip', 0);
        end
        pu = min(1, max(0, pu));
        potential(i,j) = Pr(j) * pu * derate(i,j) * bio(i,j);
        mode(i,j) = uint8(3);
        aux(i,j) = p.auxiliaryPowerRun;
    end

    % 场站限发按各机组当步可用功率同比例分配。
    sumPotential = sum(potential(i,:));
    grossReference=Pref(i)/max(1-collectionLossFraction(i),eps);
    if sumPotential > grossReference && sumPotential > 0
        commanded = potential(i,:) * grossReference / sumPotential;
        curtailedMask = commanded < potential(i,:) - 1e-9;
        mode(i,curtailedMask & (mode(i,:) == 3)) = uint8(6);
    else
        commanded = potential(i,:);
    end
    requestedGross(i)=sum(commanded);

    % 只限制向上爬坡；资源下降、保护停机和限发必须立即可用。
    if i == 1
        if isfield(in,'stateIn') && ~isempty(in.stateIn)
            devicePower(i,:)=min(commanded,previousDevicePower);
        else
            devicePower(i,:) = commanded;
        end
    else
        upLimit = devicePower(i-1,:) + p.rampUpRate * dt;
        devicePower(i,:) = min(commanded, upLimit);
    end
end

farmGross = sum(devicePower, 2);
auxTotal = sum(aux, 2);
pAvailableGross=sum(potential,2);
pAvailableCollectionLoss=collectionLossFraction.*pAvailableGross;
pAvailableAtPOI=max(0,pAvailableGross-pAvailableCollectionLoss);
collectionLoss = collectionLossFraction .* farmGross;
pActualAtPOI=max(0,farmGross-collectionLoss);
farmNet = pActualAtPOI; % Generation injection only; auxiliary load is separate.
curtailed = max(0, sum(potential, 2) - farmGross);

qMax = sqrt(max(0, Sr.^2 - devicePower.^2));

out = struct;
out.time = t;
out.relativeVelocity = uRel;
out.direction = direction;
out.potentialDevicePower = potential;
out.deviceGrossPower = devicePower;
out.farmAvailablePower = sum(potential, 2);
out.farmGrossPower = farmGross;
out.auxiliaryPower = auxTotal;
out.collectionLoss = collectionLoss;
out.farmNetPower = farmNet;
out.pAvailableGross=pAvailableGross;
out.pAvailableCollectionLoss=pAvailableCollectionLoss;
out.pAvailableAtPOI=pAvailableAtPOI;
pRequestedRaw=Pref;
pRequestedRaw(~isfinite(pRequestedRaw))=pAvailableAtPOI(~isfinite(pRequestedRaw));
out.pRequested=pRequestedRaw;
out.pAccepted=requestedGross.*(1-collectionLossFraction);
out.pActualGross=farmGross;
out.pActualCollectionLoss=collectionLoss;
out.pActualAtPOI=pActualAtPOI;
out.pAuxLoad=auxTotal;
out.curtailedPower = curtailed;
out.mode = mode;
out.modeLegend = {'不可用','静水/低于切入','换向','运行','环境停机','复归等待','限发'};
out.reactivePowerMax = qMax;
out.reactivePowerMin = -qMax;
out.qualityFlag=true(N,M);
out.stateOut=struct('lastOperationalDirection',lastOperationalDirection, ...
    'reorientElapsed',reorientElapsed,'environmentStopped',environmentStopped, ...
    'restartElapsed',restartElapsed,'previousDevicePower',devicePower(end,:));
out.diagnostics = struct( ...
    'negativeNetEnergyWh',0, ...
    'grossEnergyWh',trapz(t,farmGross)/3600, ...
    'netInjectionEnergyWh',trapz(t,pActualAtPOI)/3600, ...
    'auxiliaryEnergyWh',trapz(t,auxTotal)/3600, ...
    'curtailedEnergyWh',trapz(t,curtailed)/3600);
end

function [lastDirection,reorientElapsed,environmentStopped,restartElapsed,previousPower]=initial_state(in,M)
lastDirection=zeros(1,M,'int8'); reorientElapsed=zeros(1,M);
environmentStopped=false(1,M); restartElapsed=zeros(1,M); previousPower=zeros(1,M);
if ~isfield(in,'stateIn') || isempty(in.stateIn), return; end
s=in.stateIn;
required={'lastOperationalDirection','reorientElapsed','environmentStopped', ...
    'restartElapsed','previousDevicePower'};
for k=1:numel(required), assert(isfield(s,required{k}),'stateIn缺少%s。',required{k}); end
lastDirection=reshape(int8(s.lastOperationalDirection),1,[]);
reorientElapsed=reshape(double(s.reorientElapsed),1,[]);
environmentStopped=reshape(logical(s.environmentStopped),1,[]);
restartElapsed=reshape(double(s.restartElapsed),1,[]);
previousPower=reshape(double(s.previousDevicePower),1,[]);
assert(all([numel(lastDirection),numel(reorientElapsed),numel(environmentStopped), ...
    numel(restartElapsed),numel(previousPower)]==M),'stateIn尺寸与机组数量不一致。');
assert(all(reorientElapsed>=0) && all(restartElapsed>=0) && all(previousPower>=0), ...
    'stateIn包含非法值。');
end

function validateCurve(speed, powerPu, name)
speed = speed(:); powerPu = powerPu(:);
assert(numel(speed) >= 2 && numel(speed) == numel(powerPu), ...
    '%s功率曲线长度不一致或点数不足。', name);
assert(all(isfinite(speed)) && all(isfinite(powerPu)) && all(diff(speed) > 0), ...
    '%s功率曲线流速必须有限且严格递增。', name);
assert(all(powerPu >= 0 & powerPu <= 1), '%s功率曲线标幺值应位于[0,1]。', name);
end

function value = getfieldDefault(s, fieldName, defaultValue)
if isfield(s, fieldName)
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function y = expand1M(x, M, name)
if isscalar(x)
    y = repmat(double(x), 1, M);
elseif isvector(x) && numel(x) == M
    y = reshape(double(x), 1, M);
else
    error('%s必须为标量或1×M向量。', name);
end
end

function y = expandN1(x, N, name)
if isscalar(x)
    y = repmat(double(x), N, 1);
elseif isvector(x) && numel(x) == N
    y = reshape(double(x), N, 1);
else
    error('%s必须为标量或N×1向量。', name);
end
end

function y = expandNM(x, N, M, name)
if isscalar(x)
    y = repmat(double(x), N, M);
elseif isvector(x) && numel(x) == N
    y = repmat(reshape(double(x), N, 1), 1, M);
elseif isvector(x) && numel(x) == M
    y = repmat(reshape(double(x), 1, M), N, 1);
elseif isequal(size(x), [N M])
    y = double(x);
else
    error('%s尺寸必须为标量、N×1、1×M或N×M。', name);
end
end
