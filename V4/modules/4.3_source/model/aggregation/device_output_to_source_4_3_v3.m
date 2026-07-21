function source = device_output_to_source_4_3_v3(deviceOut,cfg)
%DEVICE_OUTPUT_TO_SOURCE_4_3_V3 Convert one device/farm model to 4.3 contract.
%
% Required cfg fields:
%   sourceId, sourceType, meterPoint, pRequested, pForecastAvailable
% Optional cfg fields:
%   scenarioAvailable, operatingState, constraintCode, qualityFlag
%
% Forecasts and scenarios are external inputs. This adapter never creates a
% forecast by perturbing actual power.

requiredCfg={'sourceId','sourceType','meterPoint','pRequested','pForecastAvailable'};
for k=1:numel(requiredCfg)
    assert(isfield(cfg,requiredCfg{k}),'cfg is missing %s.',requiredCfg{k});
end
requiredOut={'pAvailableGross','pAvailableCollectionLoss','pAvailableAtPOI', ...
    'pRequested','pAccepted','pActualAtPOI','pActualCollectionLoss','pAuxLoad'};
for k=1:numel(requiredOut)
    assert(isfield(deviceOut,requiredOut{k}), ...
        'Device output is missing standardized field %s.',requiredOut{k});
end

if isfield(deviceOut,'time'), t=deviceOut.time(:);
elseif isfield(deviceOut,'t'), t=deviceOut.t(:);
else, error('Device output must contain time or t.');
end
N=numel(t);

source=struct;
source.time=t;
source.sourceId=cfg.sourceId;
source.sourceType=cfg.sourceType;
source.meterPoint=cfg.meterPoint;
source.pAvailableGross=signal(deviceOut.pAvailableGross,N,'pAvailableGross');
source.pCollectionLoss=signal(deviceOut.pAvailableCollectionLoss,N,'pAvailableCollectionLoss');
source.pActualCollectionLoss=signal(deviceOut.pActualCollectionLoss,N,'pActualCollectionLoss');
source.pAvailableAtPOI=signal(deviceOut.pAvailableAtPOI,N,'pAvailableAtPOI');
source.pRequested=signal(cfg.pRequested,N,'pRequested');
source.pAccepted=signal(deviceOut.pAccepted,N,'pAccepted');
source.pActualAtPOI=signal(deviceOut.pActualAtPOI,N,'pActualAtPOI');
source.pAuxLoad=signal(deviceOut.pAuxLoad,N,'pAuxLoad');
source.pForecastAvailable=signal(cfg.pForecastAvailable,N,'pForecastAvailable');

[qMin,qMax]=reactive_capability(deviceOut,N);
% Dispatch-level approximation: device converter capability is summed and
% labelled at the common point. Network voltage/current and reactive losses
% still require a separate AC power-flow check before engineering use.
source.qMinAtPOI=qMin;
source.qMaxAtPOI=qMax;

if isfield(cfg,'qualityFlag')
    qualityRaw=signal(cfg.qualityFlag,N,'qualityFlag');
    assert(all(qualityRaw==0 | qualityRaw==1),'qualityFlag must be binary.');
    source.qualityFlag=logical(qualityRaw);
elseif isfield(deviceOut,'qualityFlag')
    q=deviceOut.qualityFlag;
    if isvector(q), source.qualityFlag=logical(signal(q,N,'qualityFlag'));
    else
        assert(size(q,1)==N,'qualityFlag row count mismatch.');
        source.qualityFlag=all(logical(q),2);
    end
else
    source.qualityFlag=true(N,1);
end

% These are instantaneous headroom estimates, not guaranteed reserve.
source.pUpCapability=max(0,source.pAvailableAtPOI-source.pActualAtPOI);
source.pDownCapability=max(0,source.pActualAtPOI);
source.scenarioAvailable=[];
if isfield(cfg,'scenarioAvailable')
    source.scenarioAvailable=cfg.scenarioAvailable;
end
if isfield(cfg,'operatingState')
    source.operatingState=cfg.operatingState;
elseif isfield(deviceOut,'mode')
    source.operatingState=aggregate_state(deviceOut.mode,N);
else
    source.operatingState=repmat("unknown",N,1);
end
if isfield(cfg,'constraintCode')
    source.constraintCode=cfg.constraintCode;
else
    source.constraintCode=repmat("device_model",N,1);
end
source.stateOut=struct;
if isfield(deviceOut,'stateOut'), source.stateOut=deviceOut.stateOut; end
end

function x=signal(x,N,name)
x=double(x(:));
assert(numel(x)==N && all(isfinite(x)),'%s must be a finite N-by-1 signal.',name);
end

function [qMin,qMax]=reactive_capability(out,N)
if isfield(out,'qMin') && isfield(out,'qMax')
    q0=out.qMin; q1=out.qMax;
elseif isfield(out,'reactivePowerMin') && isfield(out,'reactivePowerMax')
    q0=out.reactivePowerMin; q1=out.reactivePowerMax;
else
    error('Device output lacks reactive-power capability fields.');
end
assert(size(q0,1)==N && size(q1,1)==N,'Reactive capability row count mismatch.');
if isvector(q0), qMin=double(q0(:)); else, qMin=sum(double(q0),2); end
if isvector(q1), qMax=double(q1(:)); else, qMax=sum(double(q1),2); end
assert(all(isfinite(qMin)) && all(isfinite(qMax)) && all(qMin<=qMax), ...
    'Invalid reactive-power capability.');
end

function state=aggregate_state(mode,N)
assert(size(mode,1)==N,'Operating-state row count mismatch.');
if isvector(mode)
    state=string(mode(:));
    return;
end
state=strings(N,1);
for i=1:N
    row=string(mode(i,:));
    u=unique(row);
    if numel(u)==1, state(i)=u; else, state(i)="mixed"; end
end
end
