function out = floating_pv_dispatch_v2(in, p)
%FLOATING_PV_DISPATCH_V2 Dispatch-level offshore floating PV proxy.
%
% Each signal column represents an independently tracked MPPT subarray.
% This model does not resolve series-string mismatch or bypass diodes.
%
% Required inputs:
%   t             N-by-1 time [s]
%   dni,dhi,ghi   N-by-1 irradiance components [W/m^2]
%   sunVector     N-by-3 unit vector in ENU coordinates
%   ambientTemp   N-by-1 ambient air temperature [degC]
%   windSpeed     N-by-1 local wind speed at module height [m/s]
% Optional N-by-M inputs:
%   roll,pitch,yaw       platform rotations [rad]
%   availabilityState   logical status (preferred)
%   availability        legacy logical status
%   derate,soilingFactor,degradationFactor,mismatchFactor [0,1]
%   rearPOA              rear-side plane irradiance [W/m^2]
%   moduleTemperature    measured/high-fidelity module temperature [degC]
%   waveHeight           significant/operational wave metric [m]
%   powerReference       plant POI active-power request [W], N-by-1 or scalar
%   stateIn              rolling state returned by a previous call
%
% Required parameters:
%   baseNormal           M-by-3 static module normals in ENU
%   pdcRated             M-by-1 subarray STC DC ratings [W]
%   pacRated             plant AC rating [W]
%   apparentPowerRated   plant converter rating [VA]
%   gstc,tstc,gammaP     STC irradiance, temperature, Pmax coefficient
%   U0,U1                calibrated Faiman coefficients
%   albedo,bifaciality,iamB0
%   invLoadFraction,invEfficiency
%   auxiliaryPower,cableLossFraction
%   auxiliaryPowerStandby optional plant standby demand [W], default 0
%   maxOperatingWind,maxOperatingWave,restartWind,restartWave,restartDelay
%   rampUp
%
% Optional IEC 61853 matrix parameters:
%   powerMatrixIrradiance, powerMatrixTemperature, powerMatrixPu

validate_inputs(in, p);

t = in.t(:);
nStep = numel(t);
nSub = size(p.baseNormal, 1);

dni = column_signal(in.dni, nStep, 'dni');
dhi = column_signal(in.dhi, nStep, 'dhi');
ghi = column_signal(in.ghi, nStep, 'ghi');
ta = column_signal(in.ambientTemp, nStep, 'ambientTemp');
ws = column_signal(in.windSpeed, nStep, 'windSpeed');
sun = in.sunVector;
sun = sun ./ sqrt(sum(sun.^2, 2));

roll = optional_signal(in, 'roll', 0, nStep, nSub);
pitch = optional_signal(in, 'pitch', 0, nStep, nSub);
yaw = optional_signal(in, 'yaw', 0, nStep, nSub);
if isfield(in,'availabilityState')
    availabilityRaw=optional_signal(in,'availabilityState',1,nStep,nSub);
else
    availabilityRaw=optional_signal(in,'availability',1,nStep,nSub);
end
assert(all(availabilityRaw(:)==0 | availabilityRaw(:)==1), ...
    'availabilityState must be logical/binary; do not use 1-FOR as a multiplier.');
available = availabilityRaw > 0.5;
derate = bound01(optional_signal(in, 'derate', 1, nStep, nSub));
soil = bound01(optional_signal(in, 'soilingFactor', 1, nStep, nSub));
degradation = bound01(optional_signal(in, 'degradationFactor', 1, nStep, nSub));
mismatch = bound01(optional_signal(in, 'mismatchFactor', 1, nStep, nSub));
rearPOA = max(0, optional_signal(in, 'rearPOA', 0, nStep, nSub));
waveHeight = max(0, optional_signal(in, 'waveHeight', 0, nStep, nSub));
powerReference = optional_signal(in, 'powerReference', inf, nStep, 1);

normal = zeros(nStep, nSub, 3);
cosIncidence = zeros(nStep, nSub);
gBeam = zeros(nStep, nSub);
gDiffuse = zeros(nStep, nSub);
gReflected = zeros(nStep, nSub);
gEffective = zeros(nStep, nSub);
gEffectiveStatic = zeros(nStep, nSub);

for k = 1:nStep
    for j = 1:nSub
        r = rotation_zyx(roll(k,j), pitch(k,j), yaw(k,j));
        n = r * p.baseNormal(j,:).';
        n = n ./ norm(n);
        normal(k,j,:) = reshape(n, 1, 1, 3);

        c = max(0, dot(sun(k,:), n.'));
        cosIncidence(k,j) = c;
        nz = min(max(n(3), -1), 1);

        gBeam(k,j) = dni(k) * c;
        gDiffuse(k,j) = dhi(k) * (1 + nz) / 2;
        gReflected(k,j) = ghi(k) * p.albedo * (1 - nz) / 2;

        if c > 1e-6
            iam = max(0, 1 - p.iamB0 * (1/c - 1));
        else
            iam = 0;
        end
        gEffective(k,j) = gBeam(k,j) * iam + gDiffuse(k,j) + ...
            gReflected(k,j) + p.bifaciality * rearPOA(k,j);

        % Waveless reference with the same weather and electrical inputs.
        n0 = p.baseNormal(j,:).' ./ norm(p.baseNormal(j,:));
        c0 = max(0, dot(sun(k,:), n0.'));
        nz0 = min(max(n0(3), -1), 1);
        if c0 > 1e-6
            iam0 = max(0, 1 - p.iamB0 * (1/c0 - 1));
        else
            iam0 = 0;
        end
        gEffectiveStatic(k,j) = dni(k)*c0*iam0 + ...
            dhi(k)*(1+nz0)/2 + ghi(k)*p.albedo*(1-nz0)/2 + ...
            p.bifaciality*rearPOA(k,j);
    end
end

if isfield(in, 'moduleTemperature')
    tModule = expand_signal(in.moduleTemperature, nStep, nSub, ...
        'moduleTemperature', false);
else
    denominator = p.U0 + p.U1 .* repmat(ws, 1, nSub);
    tModule = repmat(ta, 1, nSub) + gEffective ./ denominator;
end

qualityFlag = true(nStep, nSub);
if all(isfield(p, {'powerMatrixIrradiance','powerMatrixTemperature','powerMatrixPu'}))
    pdcPu = interp2(p.powerMatrixTemperature(:).', ...
        p.powerMatrixIrradiance(:), p.powerMatrixPu, ...
        tModule, gEffective, 'linear', NaN);
    qualityFlag = ~isnan(pdcPu);
    pdcPu(~qualityFlag) = 0;
    pdcIdeal = pdcPu .* repmat(p.pdcRated(:).', nStep, 1);
else
    tempFactor = max(0, 1 + p.gammaP .* (tModule - p.tstc));
    pdcIdeal = repmat(p.pdcRated(:).', nStep, 1) .* ...
        (gEffective ./ p.gstc) .* tempFactor;
end
pdcIdeal = max(0, pdcIdeal);

MODE_NORMAL = uint8(1);
MODE_STOPPED = uint8(2);
MODE_RESTART_WAIT = uint8(3);
MODE_UNAVAILABLE = uint8(4);

mode = repmat(MODE_NORMAL, nStep, nSub);
pdcNet = zeros(nStep, nSub);
[initialMode,safeTime,previousPacGross]=initial_state(in,nSub,MODE_NORMAL);

for j = 1:nSub
    currentMode = initialMode(j);
    for k = 1:nStep
        if k == 1
            dt = 0;
        else
            dt = t(k) - t(k-1);
        end

        severe = ws(k) >= p.maxOperatingWind || ...
            waveHeight(k,j) >= p.maxOperatingWave;
        restartSafe = ws(k) <= p.restartWind && ...
            waveHeight(k,j) <= p.restartWave;

        if ~available(k,j)
            currentMode = MODE_UNAVAILABLE;
            safeTime(j) = 0;
        elseif severe
            currentMode = MODE_STOPPED;
            safeTime(j) = 0;
        elseif currentMode == MODE_UNAVAILABLE
            currentMode = MODE_RESTART_WAIT;
            safeTime(j) = 0;
        elseif currentMode == MODE_STOPPED || currentMode == MODE_RESTART_WAIT
            if restartSafe
                safeTime(j) = safeTime(j) + dt;
                currentMode = MODE_RESTART_WAIT;
                if safeTime(j) >= p.restartDelay
                    currentMode = MODE_NORMAL;
                end
            else
                safeTime(j) = 0;
                currentMode = MODE_STOPPED;
            end
        else
            currentMode = MODE_NORMAL;
        end

        mode(k,j) = currentMode;
        if currentMode == MODE_NORMAL
            pdcNet(k,j) = pdcIdeal(k,j) * derate(k,j) * soil(k,j) * ...
                degradation(k,j) * mismatch(k,j);
        end
    end
end

pdcPlant = sum(pdcNet, 2);
loadFraction = pdcPlant ./ max(p.pacRated, eps);
etaInv = interp1(p.invLoadFraction(:), p.invEfficiency(:), ...
    loadFraction, 'linear', 'extrap');
etaInv = min(max(etaInv, 0), 1);

pacBeforeClip = pdcPlant .* etaInv;
clippingLoss = max(0, pacBeforeClip - p.pacRated);
pAvailableGross=min(pacBeforeClip,p.pacRated);
pAvailableCollectionLoss=pAvailableGross.*p.cableLossFraction;
pAvailableAtPOI=max(0,pAvailableGross-pAvailableCollectionLoss);
pReferenceGross=powerReference/max(1-p.cableLossFraction,eps);
pRequestedGross=min(pAvailableGross,pReferenceGross);
pacRaw=pRequestedGross;

pacGross = zeros(nStep, 1);
for k = 1:nStep
    if k == 1
        upper=previousPacGross+p.rampUp*0;
        if isfield(in,'stateIn') && ~isempty(in.stateIn)
            pacGross(k)=min(pacRaw(k),upper);
        else
            pacGross(k)=pacRaw(k);
        end
    else
        dt = t(k) - t(k-1);
        upper = pacGross(k-1) + p.rampUp * dt;
        % Upward ramp can be curtailed. A resource-driven decrease cannot
        % be prevented without storage, so output is never held above the
        % available PV power.
        pacGross(k) = min(pacRaw(k), upper);
    end
end
pActualCollectionLoss=pacGross.*p.cableLossFraction;
pac=max(0,pacGross-pActualCollectionLoss);
if isfield(p,'auxiliaryPowerStandby')
    auxiliaryPowerStandby=p.auxiliaryPowerStandby;
else
    auxiliaryPowerStandby=0;
end
assert(isscalar(auxiliaryPowerStandby) && isfinite(auxiliaryPowerStandby) && ...
    auxiliaryPowerStandby>=0,'auxiliaryPowerStandby must be a nonnegative scalar.');
pAuxLoad=auxiliaryPowerStandby*ones(nStep,1);
pAuxLoad(any(mode==MODE_NORMAL,2))=p.auxiliaryPower;

pacRamp = [0; diff(pac)./diff(t)];
wilIrradiance = zeros(nStep, nSub);
validStatic = gEffectiveStatic > 1;
wilIrradiance(validStatic) = 1 - ...
    gEffective(validStatic)./gEffectiveStatic(validStatic);

qMax = sqrt(max(0, p.apparentPowerRated.^2 - pac.^2));

out.t = t;
out.normalENU = normal;
out.cosIncidence = cosIncidence;
out.gBeam = gBeam;
out.gDiffuse = gDiffuse;
out.gReflected = gReflected;
out.gEffective = gEffective;
out.gEffectiveStatic = gEffectiveStatic;
out.wilIrradiance = wilIrradiance;
out.moduleTemperature = tModule;
out.pdcIdeal = pdcIdeal;
out.pdcNet = pdcNet;
out.pdcPlant = pdcPlant;
out.inverterEfficiency = etaInv;
out.clippingLoss = clippingLoss;
out.pacRaw = pacRaw;
out.pac = pac;
out.pAvailableGross=pAvailableGross;
out.pAvailableCollectionLoss=pAvailableCollectionLoss;
out.pAvailableAtPOI=pAvailableAtPOI;
pRequestedRaw=powerReference;
pRequestedRaw(~isfinite(pRequestedRaw))=pAvailableAtPOI(~isfinite(pRequestedRaw));
out.pRequested=pRequestedRaw;
out.pAccepted=pRequestedGross.*(1-p.cableLossFraction);
out.pActualGross=pacGross;
out.pActualCollectionLoss=pActualCollectionLoss;
out.pActualAtPOI=pac;
out.pAuxLoad=pAuxLoad;
out.pacRamp = pacRamp;
out.qMin = -qMax;
out.qMax = qMax;
out.mode = mode;
out.modeLegend = struct('normal', MODE_NORMAL, ...
    'stopped', MODE_STOPPED, 'restartWait', MODE_RESTART_WAIT, ...
    'unavailable', MODE_UNAVAILABLE);
out.qualityFlag = qualityFlag;
out.stateOut=struct('currentMode',mode(end,:), ...
    'safeTime',safeTime,'previousPacGross',pacGross(end));
end

function validate_inputs(in, p)
requiredIn = {'t','dni','dhi','ghi','sunVector','ambientTemp','windSpeed'};
requiredP = {'baseNormal','pdcRated','pacRated','apparentPowerRated', ...
    'gstc','tstc','gammaP','U0','U1','albedo','bifaciality','iamB0', ...
    'invLoadFraction','invEfficiency','auxiliaryPower','cableLossFraction', ...
    'maxOperatingWind','maxOperatingWave','restartWind','restartWave', ...
    'restartDelay','rampUp'};
for k = 1:numel(requiredIn)
    assert(isfield(in, requiredIn{k}), 'Missing input field: %s', requiredIn{k});
end
for k = 1:numel(requiredP)
    assert(isfield(p, requiredP{k}), 'Missing parameter field: %s', requiredP{k});
end

t = in.t(:);
assert(numel(t) >= 2 && all(isfinite(t)) && all(diff(t) > 0), ...
    'in.t must be finite and strictly increasing.');
assert(size(in.sunVector,1) == numel(t) && size(in.sunVector,2) == 3, ...
    'sunVector must be N-by-3.');
assert(all(isfinite(in.sunVector(:))) && ...
    all(sqrt(sum(in.sunVector.^2,2)) > 0), ...
    'sunVector rows must be finite and nonzero.');
assert(size(p.baseNormal,2) == 3 && all(isfinite(p.baseNormal(:))) && ...
    all(sqrt(sum(p.baseNormal.^2,2)) > 0), ...
    'baseNormal must contain finite, nonzero ENU vectors.');
assert(numel(p.pdcRated) == size(p.baseNormal,1) && all(p.pdcRated(:) > 0), ...
    'pdcRated must have one positive value per subarray.');
assert(p.pacRated > 0 && p.apparentPowerRated >= p.pacRated, ...
    'Invalid AC/apparent power ratings.');
assert(p.U0 > 0 && p.U1 >= 0, 'Faiman coefficients must be nonnegative.');
assert(p.albedo >= 0 && p.albedo <= 1 && ...
    p.bifaciality >= 0 && p.bifaciality <= 1, ...
    'albedo and bifaciality must be in [0,1].');
assert(numel(p.invLoadFraction) == numel(p.invEfficiency) && ...
    all(diff(p.invLoadFraction(:)) > 0) && ...
    all(p.invEfficiency(:) >= 0 & p.invEfficiency(:) <= 1), ...
    'Invalid inverter efficiency curve.');
assert(p.cableLossFraction >= 0 && p.cableLossFraction < 1, ...
    'cableLossFraction must be in [0,1).');
assert(p.restartWind <= p.maxOperatingWind && ...
    p.restartWave <= p.maxOperatingWave, ...
    'Restart thresholds must not exceed operating limits.');
assert(p.restartDelay >= 0 && p.rampUp >= 0, ...
    'Delay and upward ramp limit must be nonnegative.');
end

function x = column_signal(x, nStep, fieldName)
x = x(:);
assert(numel(x) == nStep && all(isfinite(x)), ...
    '%s must be a finite N-by-1 signal.', fieldName);
if any(strcmp(fieldName, {'dni','dhi','ghi','windSpeed'}))
    assert(all(x >= 0), '%s must be nonnegative.', fieldName);
end
end

function x = optional_signal(s, fieldName, defaultValue, nStep, nCol)
if isfield(s, fieldName)
    allowInf = strcmp(fieldName, 'powerReference');
    x = expand_signal(s.(fieldName), nStep, nCol, fieldName, allowInf);
else
    x = repmat(defaultValue, nStep, nCol);
end
end

function x = expand_signal(x, nStep, nCol, fieldName, allowInf)
if isscalar(x)
    x = repmat(x, nStep, nCol);
elseif isvector(x) && numel(x) == nStep
    x = repmat(x(:), 1, nCol);
elseif size(x,1) == nStep && size(x,2) == nCol
    % Already correctly shaped.
else
    error('%s must be scalar, N-by-1, or N-by-M.', fieldName);
end
if allowInf
    assert(all(~isnan(x(:))), '%s contains NaN values.', fieldName);
else
    assert(all(isfinite(x(:))), '%s contains nonfinite values.', fieldName);
end
end

function y = bound01(x)
y = min(max(x, 0), 1);
end

function [mode,safeTime,previousPacGross]=initial_state(in,nSub,defaultMode)
mode=repmat(defaultMode,1,nSub); safeTime=zeros(1,nSub); previousPacGross=0;
if ~isfield(in,'stateIn') || isempty(in.stateIn), return; end
s=in.stateIn;
required={'currentMode','safeTime','previousPacGross'};
for k=1:numel(required), assert(isfield(s,required{k}),'stateIn missing %s.',required{k}); end
mode=reshape(uint8(s.currentMode),1,[]);
safeTime=reshape(double(s.safeTime),1,[]);
previousPacGross=double(s.previousPacGross);
assert(numel(mode)==nSub && numel(safeTime)==nSub && isscalar(previousPacGross), ...
    'stateIn dimensions are inconsistent with the PV model.');
assert(all(safeTime>=0) && previousPacGross>=0,'stateIn contains invalid values.');
end

function r = rotation_zyx(phi, theta, psi)
rx = [1 0 0; 0 cos(phi) -sin(phi); 0 sin(phi) cos(phi)];
ry = [cos(theta) 0 sin(theta); 0 1 0; -sin(theta) 0 cos(theta)];
rz = [cos(psi) -sin(psi) 0; sin(psi) cos(psi) 0; 0 0 1];
r = rz * ry * rx;
end
