function out = floating_wind_dispatch_v2(in, p)
%FLOATING_WIND_DISPATCH_V2 Dispatch-level floating wind turbine/farm proxy.
%
% This model is intended for source-storage-compute-use dispatch studies.
% It is not a replacement for OpenFAST load or certification analysis.
%
% Required input fields (N-by-M unless noted):
%   t              N-by-1 time [s], strictly increasing
%   windSpeed      hub-height along-rotor wind speed [m/s]
% Optional input fields:
%   surgeVelocity  platform fore-aft velocity [m/s]
%   pitchRate      platform pitch rate [rad/s]
%   platformPitch  platform pitch angle [rad]
%   waveHeight     significant/operational wave metric [m]
%   availabilityState logical availability flag (preferred)
%   availability   legacy logical availability flag
%   derate         multiplier in [0,1]
%   powerReference per-turbine active-power cap [W]
%   farmPowerReference source-level POI request [W] (preferred EMS input)
%   stateIn        rolling state returned by a previous call
%
% Required parameter fields:
%   powerCurveWind K-by-1 wind-speed breakpoints [m/s]
%   powerCurveP    K-by-1 electrical power curve [W]
%   ratedPower     rated active power per turbine [W]
%   ratedApparentPower rated converter apparent power [VA]
%   hubHeight      hub height above platform reference [m]
%   cutOutWind     high-wind stop threshold [m/s]
%   restartWind    restart threshold below cutOutWind [m/s]
%   maxOperatingWave/restartWave wave stop/restart thresholds [m]
%   maxOperatingPitch/restartPitch absolute pitch stop/restart [rad]
%   restartDelay   continuous safe time required before restart [s]
%   rampUp         maximum active-power ramp [W/s]
%   auxiliaryPower auxiliary demand per operating turbine [W]
%   auxiliaryPowerStandby optional standby demand per turbine [W], default 0
%   arrayLossFraction explicit collection/array loss fraction [0,1)
%
% Sign convention for the small-angle correction:
% positive surgeVelocity/pitchRate moves the hub downwind, reducing
% relative wind: Urel = U - surgeVelocity - hubHeight*pitchRate.

validate_inputs(in, p);

t = in.t(:);
nStep = numel(t);
nTurb = size(in.windSpeed, 2);

wind = expand_signal(in.windSpeed, nStep, nTurb, 'windSpeed');
surgeVel = optional_signal(in, 'surgeVelocity', 0, nStep, nTurb);
pitchRate = optional_signal(in, 'pitchRate', 0, nStep, nTurb);
if isfield(in,'availabilityState')
    availabilityRaw=optional_signal(in,'availabilityState',1,nStep,nTurb);
else
    availabilityRaw=optional_signal(in,'availability',1,nStep,nTurb);
end
assert(all(availabilityRaw(:)==0 | availabilityRaw(:)==1), ...
    'availabilityState must be logical/binary; do not use 1-FOR as a multiplier.');
available = availabilityRaw > 0.5;
derate = min(max(optional_signal(in, 'derate', 1, nStep, nTurb), 0), 1);
powerRef = optional_signal(in, 'powerReference', inf, nStep, nTurb);
waveHeight=max(0,optional_signal(in,'waveHeight',0,nStep,nTurb));
platformPitch=optional_signal(in,'platformPitch',0,nStep,nTurb);

uRel = max(0, wind - surgeVel - p.hubHeight .* pitchRate);

% The supplied curve is electrical power at turbine terminals. Do not
% multiply by a generator efficiency again.
pCurve = interp1(p.powerCurveWind(:), p.powerCurveP(:), uRel, 'linear', 0);
pCurve = min(max(pCurve, 0), p.ratedPower);

MODE_NORMAL = uint8(1);
MODE_STOPPED = uint8(2);
MODE_RESTART_WAIT = uint8(3);
MODE_UNAVAILABLE = uint8(4);

mode = repmat(MODE_NORMAL, nStep, nTurb);
pRaw = zeros(nStep, nTurb);
pTurbine = zeros(nStep, nTurb);
pAvailableDevice=zeros(nStep,nTurb);
pAuxDevice=zeros(nStep,nTurb);
if isfield(p,'auxiliaryPowerStandby')
    auxiliaryPowerStandby=p.auxiliaryPowerStandby;
else
    auxiliaryPowerStandby=0;
end
assert(isscalar(auxiliaryPowerStandby) && isfinite(auxiliaryPowerStandby) && ...
    auxiliaryPowerStandby>=0,'auxiliaryPowerStandby must be a nonnegative scalar.');

[initialMode,safeTime,previousPower0]=initial_state(in,nTurb,MODE_NORMAL);

for j = 1:nTurb
    currentMode = initialMode(j);
    previousPower = previousPower0(j);

    for k = 1:nStep
        if k == 1
            dt = 0;
        else
            dt = t(k) - t(k-1);
        end

        severe = uRel(k,j) >= p.cutOutWind || ...
            waveHeight(k,j) >= p.maxOperatingWave || ...
            abs(platformPitch(k,j)) >= p.maxOperatingPitch;
        restartSafe = uRel(k,j) <= p.restartWind && ...
            waveHeight(k,j) <= p.restartWave && ...
            abs(platformPitch(k,j)) <= p.restartPitch;

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
        pAuxDevice(k,j)=auxiliaryPowerStandby;
        if currentMode == MODE_NORMAL
            pAvailableDevice(k,j)=min(pCurve(k,j)*derate(k,j),p.ratedPower);
            requested = min([pAvailableDevice(k,j), powerRef(k,j), p.ratedPower]);
            pRaw(k,j) = max(0, requested);
            pAuxDevice(k,j)=p.auxiliaryPower;
        else
            pRaw(k,j) = 0;
        end

        % Only upward ramp is limited. Resource/command decreases and
        % emergency stops must be followed immediately without storage.
        if currentMode ~= MODE_NORMAL
            limited = 0;
        elseif k == 1
            if isfield(in,'stateIn') && ~isempty(in.stateIn)
                limited=min(pRaw(k,j),previousPower);
            else
                limited = pRaw(k,j);
            end
        else
            upper = previousPower + p.rampUp * dt;
            limited = min(pRaw(k,j), upper);
        end

        pTurbine(k,j) = min(max(limited, 0), p.ratedPower);
        previousPower = pTurbine(k,j);
    end
end

% Optional source-level request is allocated proportionally as downward
% curtailment after device feasibility. It is not repeated per turbine.
farmReference=optional_column(in,'farmPowerReference',inf,nStep);
pAcceptedGross=sum(pRaw,2);
for k=1:nStep
    grossCap=farmReference(k)/max(1-p.arrayLossFraction,eps);
    if pAcceptedGross(k)>grossCap && pAcceptedGross(k)>0
        scale=grossCap/pAcceptedGross(k);
        pRaw(k,:)=pRaw(k,:)*scale;
        pTurbine(k,:)=pTurbine(k,:)*scale;
        pAcceptedGross(k)=grossCap;
    end
end

pAvailableGross=sum(pAvailableDevice,2);
pAvailableCollectionLoss=pAvailableGross.*p.arrayLossFraction;
pAvailableAtPOI=max(0,pAvailableGross-pAvailableCollectionLoss);
pFarmGross = sum(pTurbine, 2);
pActualCollectionLoss=pFarmGross.*p.arrayLossFraction;
pActualAtPOI=max(0,pFarmGross-pActualCollectionLoss);
pAuxLoad=sum(pAuxDevice,2);
pFarmNet = pActualAtPOI; % Generation injection only; auxiliary load is separate.

% Symmetric converter P-Q circle. Plant-level controls or grid-code limits
% may impose a tighter boundary and should be applied downstream.
qMax = sqrt(max(0, p.ratedApparentPower.^2 - pTurbine.^2));
qMin = -qMax;

out.t = t;
out.relativeWind = uRel;
out.curvePower = pCurve;
out.rawPower = pRaw;
out.availableDevicePower=pAvailableDevice;
out.turbinePower = pTurbine;
out.pAvailableGross=pAvailableGross;
out.pAvailableCollectionLoss=pAvailableCollectionLoss;
out.pAvailableAtPOI=pAvailableAtPOI;
pReferenceFinite=powerRef;
pReferenceFinite(~isfinite(pReferenceFinite))=pAvailableDevice(~isfinite(pReferenceFinite));
pRequestedFromDevices=sum(max(0,pReferenceFinite),2).*(1-p.arrayLossFraction);
pRequestedRaw=farmReference;
pRequestedRaw(~isfinite(pRequestedRaw))=pRequestedFromDevices(~isfinite(pRequestedRaw));
out.pRequested=pRequestedRaw;
out.pAccepted=pAcceptedGross.*(1-p.arrayLossFraction);
out.pActualGross=pFarmGross;
out.pActualCollectionLoss=pActualCollectionLoss;
out.pActualAtPOI=pActualAtPOI;
out.pAuxLoad=pAuxLoad;
out.farmGrossPower = pFarmGross;
out.farmNetPower = pFarmNet;
out.qMin = qMin;
out.qMax = qMax;
out.mode = mode;
out.modeLegend = struct('normal', MODE_NORMAL, ...
    'stopped', MODE_STOPPED, 'restartWait', MODE_RESTART_WAIT, ...
    'unavailable', MODE_UNAVAILABLE);
out.qualityFlag = true(nStep, nTurb);
out.stateOut=struct('currentMode',mode(end,:), ...
    'safeTime',safeTime,'previousPower',pTurbine(end,:));
end

function validate_inputs(in, p)
requiredIn = {'t','windSpeed'};
requiredP = {'powerCurveWind','powerCurveP','ratedPower', ...
    'ratedApparentPower','hubHeight','cutOutWind','restartWind', ...
    'maxOperatingWave','restartWave','maxOperatingPitch','restartPitch', ...
    'restartDelay','rampUp','auxiliaryPower', ...
    'arrayLossFraction'};

for k = 1:numel(requiredIn)
    assert(isfield(in, requiredIn{k}), 'Missing input field: %s', requiredIn{k});
end
for k = 1:numel(requiredP)
    assert(isfield(p, requiredP{k}), 'Missing parameter field: %s', requiredP{k});
end

t = in.t(:);
assert(numel(t) >= 2 && all(isfinite(t)) && all(diff(t) > 0), ...
    'in.t must be finite and strictly increasing.');
assert(size(in.windSpeed,1) == numel(t), ...
    'windSpeed must have one row per time step.');
assert(numel(p.powerCurveWind) == numel(p.powerCurveP), ...
    'Power-curve arrays must have equal length.');
assert(all(diff(p.powerCurveWind(:)) > 0), ...
    'powerCurveWind must be strictly increasing.');
assert(all(isfinite(p.powerCurveP(:))) && all(p.powerCurveP(:) >= 0), ...
    'powerCurveP must contain finite, nonnegative values.');
assert(isscalar(p.ratedPower) && p.ratedPower > 0 && ...
    isscalar(p.ratedApparentPower) && p.ratedApparentPower > 0, ...
    'Rated powers must be positive scalars.');
assert(p.restartWind < p.cutOutWind, ...
    'restartWind must be lower than cutOutWind for hysteresis.');
assert(p.restartWave < p.maxOperatingWave && ...
    p.restartPitch < p.maxOperatingPitch, ...
    'Wave and platform-pitch restart thresholds must be below stop thresholds.');
assert(p.restartDelay >= 0 && p.rampUp >= 0, ...
    'Delay and upward ramp limit must be nonnegative.');
assert(p.arrayLossFraction >= 0 && p.arrayLossFraction < 1, ...
    'arrayLossFraction must be in [0,1).');
assert(p.ratedApparentPower >= p.ratedPower, ...
    'ratedApparentPower must be at least ratedPower.');
end

function [mode,safeTime,previousPower]=initial_state(in,nTurb,defaultMode)
mode=repmat(defaultMode,1,nTurb); safeTime=zeros(1,nTurb); previousPower=zeros(1,nTurb);
if ~isfield(in,'stateIn') || isempty(in.stateIn), return; end
s=in.stateIn;
required={'currentMode','safeTime','previousPower'};
for k=1:numel(required), assert(isfield(s,required{k}),'stateIn missing %s.',required{k}); end
mode=reshape(uint8(s.currentMode),1,[]);
safeTime=reshape(double(s.safeTime),1,[]);
previousPower=reshape(double(s.previousPower),1,[]);
assert(numel(mode)==nTurb && numel(safeTime)==nTurb && numel(previousPower)==nTurb, ...
    'stateIn fields must contain one value per turbine.');
assert(all(safeTime>=0) && all(previousPower>=0),'stateIn contains invalid values.');
end

function x = optional_signal(s, fieldName, defaultValue, nStep, nTurb)
if isfield(s, fieldName)
    x = expand_signal(s.(fieldName), nStep, nTurb, fieldName);
else
    x = repmat(defaultValue, nStep, nTurb);
end
end


function x=optional_column(s,fieldName,defaultValue,nStep)
if isfield(s,fieldName), x=s.(fieldName); else, x=defaultValue; end
if isscalar(x), x=repmat(double(x),nStep,1); else, x=double(x(:)); end
assert(numel(x)==nStep && all(~isnan(x)) && all(x>=0), ...
    '%s must be scalar or a nonnegative N-by-1 signal.',fieldName);
end

function x = expand_signal(x, nStep, nTurb, fieldName)
if isscalar(x)
    x = repmat(x, nStep, nTurb);
elseif isvector(x) && numel(x) == nStep
    x = repmat(x(:), 1, nTurb);
elseif size(x,1) == nStep && size(x,2) == nTurb
    % Already in the required shape.
else
    error('%s must be scalar, N-by-1, or N-by-M.', fieldName);
end
if strcmp(fieldName, 'powerReference')
    assert(all(~isnan(x(:))), '%s contains NaN values.', fieldName);
else
    assert(all(isfinite(x(:))), '%s contains nonfinite values.', fieldName);
end
end
