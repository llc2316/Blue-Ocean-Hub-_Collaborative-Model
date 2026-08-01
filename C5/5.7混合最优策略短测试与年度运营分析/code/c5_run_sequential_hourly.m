function [summary,hourlyLedger,results] = ...
    c5_run_sequential_hourly(base,cfg,strategy,eventCode,retainResults)
%C5_RUN_SEQUENTIAL_HOURLY Causal one-interval-at-a-time V5 execution.
%
% At hour t the solver receives only the current measured inputs and the
% terminal device states from t-1. It never receives later source, price,
% demand or total-energy records. This is a causal myopic controller, not
% an annual perfect-foresight optimum.

if nargin<4 || isempty(eventCode)
    eventCode=repmat("NORMAL",numel(base.timeH),1);
else
    eventCode=string(eventCode(:));
end
if nargin<5 || isempty(retainResults), retainResults=false; end
N=numel(base.timeH);
assert(numel(eventCode)==N,'eventCode must align with base.timeH.');
strategy=normalize_strategy(strategy);

cfg.objective.primary=strategy.objectivePrimary;
cfg.objective.maxENSMWh=strategy.maxENSMWh;
cfg.objective.maxNetGHGKgCO2e=Inf;
cfg.objective.minRenewableUtilization=0;
cfg.objective.tieBreak=strategy.tieBreak;
cfg.objective.temporalTieBreak='none';
cfg.solver.maxTimeS=min(cfg.solver.maxTimeS,30);
cfg.bess.terminalRule='none';
cfg.hydrogen.terminalRule='none';

state=base.initial;
dispatchRows=cell(N,1);
resultRows=cell(N,1);
if retainResults, results=cell(N,1); else, results={}; end
for t=1:N
    in=slice_hour(base,t,state);
    in=apply_asset_switches(in,strategy);
    in=apply_event_rule(in,eventCode(t),strategy);
    if strategy.productMixEnabled
        in.productMix=struct('enabled',true,'mode','hourly', ...
            'targetElectricityShare',strategy.eShare, ...
            'targetHydrogenShare',strategy.hShare, ...
            'targetComputeShare',strategy.cShare, ...
            'shareTolerance',strategy.shareTolerance, ...
            'minimumAllocatedInputMWh',0, ...
            'minimumAllocatedInputMW',0);
    else
        in.productMix=struct('enabled',false);
    end
    cfg.meta.parameterVersion=sprintf('%s_h%04d',strategy.id,t);
    result=run_v5_model(in,cfg);
    assert(result.audit.pass, ...
        'Hourly audit failed for %s at hour %d.',strategy.id,t);
    state=terminal_state(result);
    d=result.dispatch;
    d.timeH=base.timeH(t);
    strategyId=repmat(string(strategy.id),height(d),1);
    event=repmat(eventCode(t),height(d),1);
    dispatchRows{t}=addvars(d,strategyId,event,'Before',1, ...
        'NewVariableNames',{'strategyId','eventCode'});
    k=result.kpi;
    resultRows{t}=table(base.timeH(t),eventCode(t), ...
        k.eAvailableMWh,k.eSourceUsedMWh,k.eElectricityInputMWh, ...
        k.eHydrogenInputMWh,k.eFlexibleComputeInputMWh, ...
        k.eCableReceivedMWh,k.h2DeliveredKg,k.eComputeServiceMWhCS, ...
        k.eCurtailmentMWh,k.ensMWh,k.outputRevenueCNY, ...
        k.operatingCostCNY,k.economicNetCostCNY, ...
        result.meta.exitflag,result.audit.pass, ...
        'VariableNames',{'timeH','eventCode','eAvailableMWh', ...
        'eSourceUsedMWh','eElectricityInputMWh','eHydrogenInputMWh', ...
        'eFlexibleComputeInputMWh','eCableReceivedMWh','h2DeliveredKg', ...
        'eComputeServiceMWhCS','eCurtailmentMWh','ensMWh', ...
        'outputRevenueCNY','operatingCostCNY','economicNetCostCNY', ...
        'exitflag','auditPass'});
    if retainResults, results{t}=result; end
end

dispatch=vertcat(dispatchRows{:});
hourlyLedger=vertcat(resultRows{:});
allocated=dispatch.pCableSendMW+dispatch.pElectrolyzerMW+ ...
    dispatch.pComputeFlexibleMW;
active=allocated>1e-8;
realized=zeros(N,3);
inputs=[dispatch.pCableSendMW,dispatch.pElectrolyzerMW, ...
    dispatch.pComputeFlexibleMW];
for k=1:3
    realized(active,k)=inputs(active,k)./allocated(active);
end
if strategy.productMixEnabled && any(active)
    target=[strategy.eShare,strategy.hShare,strategy.cShare];
    maxHourlyShareDeviation=max(abs(realized(active,:)-target),[],'all');
else
    maxHourlyShareDeviation=NaN;
end
eE=sum(hourlyLedger.eElectricityInputMWh);
eH=sum(hourlyLedger.eHydrogenInputMWh);
eC=sum(hourlyLedger.eFlexibleComputeInputMWh);
den=eE+eH+eC;
if den>0, annualShare=[eE,eH,eC]/den; else, annualShare=[0 0 0]; end
summary=table(string(strategy.id),string(strategy.strategyClass),N, ...
    strategy.productMixEnabled,strategy.eShare,strategy.hShare, ...
    strategy.cShare,nnz(active),maxHourlyShareDeviation, ...
    sum(hourlyLedger.eAvailableMWh),sum(hourlyLedger.eSourceUsedMWh), ...
    eE,eH,eC,annualShare(1),annualShare(2),annualShare(3), ...
    sum(hourlyLedger.eCableReceivedMWh),sum(hourlyLedger.h2DeliveredKg), ...
    sum(hourlyLedger.eComputeServiceMWhCS), ...
    sum(hourlyLedger.eCurtailmentMWh),sum(hourlyLedger.ensMWh), ...
    sum(hourlyLedger.outputRevenueCNY),sum(hourlyLedger.operatingCostCNY), ...
    sum(hourlyLedger.economicNetCostCNY), ...
    all(hourlyLedger.auditPass),all(hourlyLedger.exitflag>0), ...
    "CAUSAL_1H_CURRENT_OBSERVATION_PLUS_PREVIOUS_TERMINAL_STATE", ...
    "[假设值，待企业调研校准]", ...
    'VariableNames',{'strategyId','strategyClass','horizonH', ...
    'productMixEnabled','targetElectricityShare','targetHydrogenShare', ...
    'targetComputeShare','activeRatioHours','maxHourlyShareDeviation', ...
    'eAvailableMWh','eSourceUsedMWh','eElectricityInputMWh', ...
    'eHydrogenInputMWh','eFlexibleComputeInputMWh', ...
    'realizedElectricityInputShare','realizedHydrogenInputShare', ...
    'realizedComputeInputShare','eCableReceivedMWh','h2DeliveredKg', ...
    'eComputeServiceMWhCS','eCurtailmentMWh','ensMWh', ...
    'outputRevenueCNY','operatingCostCNY','economicNetCostCNY', ...
    'auditPass','allHoursOptimal','informationBoundary', ...
    'parameterStatus'});
hourlyLedger.strategyId=repmat(string(strategy.id),N,1);
hourlyLedger.realizedElectricityShare=realized(:,1);
hourlyLedger.realizedHydrogenShare=realized(:,2);
hourlyLedger.realizedComputeShare=realized(:,3);
hourlyLedger.ratioActive=active;
% Key physical states/actions retained for resilience and causality audit.
hourlyLedger.pSourceAvailableMW=dispatch.pSourceAvailableMW;
hourlyLedger.pSourceUsedMW=dispatch.pSourceUsedMW;
hourlyLedger.pCurtailmentMW=dispatch.pCurtailmentMW;
hourlyLedger.pBessChargeMW=dispatch.pBessChargeMW;
hourlyLedger.pBessDischargeMW=dispatch.pBessDischargeMW;
hourlyLedger.bessSOC=dispatch.bessSOC;
hourlyLedger.pElectrolyzerMW=dispatch.pElectrolyzerMW;
hourlyLedger.h2InventoryKg=dispatch.h2InventoryKg;
hourlyLedger.pH2PowerMW=dispatch.pH2PowerMW;
hourlyLedger.pCableSendMW=dispatch.pCableSendMW;
hourlyLedger.pComputeFacilityMW=dispatch.pComputeFacilityMW;
hourlyLedger.pMarineUnservedMW=dispatch.pMarineUnservedMW;
hourlyLedger.pInternalUnservedMW=dispatch.pInternalUnservedMW;
end

function strategy=normalize_strategy(strategy)
strategy.id=char(string(field_or(strategy,'id','causal_myopic')));
strategy.strategyClass=char(string(field_or( ...
    strategy,'strategyClass','MODEL_CAUSAL_MYOPIC')));
strategy.productMixEnabled=logical(field_or( ...
    strategy,'productMixEnabled',false));
strategy.eShare=double(field_or(strategy,'eShare',NaN));
strategy.hShare=double(field_or(strategy,'hShare',NaN));
strategy.cShare=double(field_or(strategy,'cShare',NaN));
strategy.shareTolerance=double(field_or(strategy,'shareTolerance',0.02));
strategy.electricityEnabled=logical(field_or( ...
    strategy,'electricityEnabled',true));
strategy.hydrogenEnabled=logical(field_or( ...
    strategy,'hydrogenEnabled',true));
strategy.computeEnabled=logical(field_or(strategy,'computeEnabled',true));
strategy.eventReserveRule=logical(field_or( ...
    strategy,'eventReserveRule',true));
if isfield(strategy,'maxENSMWh')
    strategy.maxENSMWh=double(strategy.maxENSMWh);
elseif strategy.productMixEnabled || ...
        strcmp(strategy.strategyClass,'ASSET_BASELINE')
    strategy.maxENSMWh=Inf;
else
    strategy.maxENSMWh=0;
end
assert(strategy.maxENSMWh>=0, ...
    'strategy.maxENSMWh must be nonnegative.');
if isfield(strategy,'objectivePrimary')
    strategy.objectivePrimary=char(string(strategy.objectivePrimary));
elseif strategy.productMixEnabled || ...
        strcmp(strategy.strategyClass,'ASSET_BASELINE')
    strategy.objectivePrimary='ensMWh';
else
    strategy.objectivePrimary='economicNetCostCNY';
end
if isfield(strategy,'tieBreak')
    strategy.tieBreak=char(string(strategy.tieBreak));
elseif strategy.productMixEnabled || ...
        strcmp(strategy.strategyClass,'ASSET_BASELINE')
    strategy.tieBreak='minCurtailment';
else
    strategy.tieBreak='none';
end
if strategy.productMixEnabled
    assert(all(isfinite([strategy.eShare,strategy.hShare,strategy.cShare])) && ...
        abs(strategy.eShare+strategy.hShare+strategy.cShare-1)<=1e-10, ...
        'Fixed hourly E/H/C shares must sum to one.');
end
end

function in=apply_asset_switches(in,strategy)
in.availability.cable=in.availability.cable*strategy.electricityEnabled;
in.availability.electrolyzer= ...
    in.availability.electrolyzer*strategy.hydrogenEnabled;
in.availability.h2Storage= ...
    in.availability.h2Storage*strategy.hydrogenEnabled;
in.availability.h2Pipe=in.availability.h2Pipe*strategy.hydrogenEnabled;
in.availability.h2Ship=in.availability.h2Ship*strategy.hydrogenEnabled;
in.availability.compute=in.availability.compute*strategy.computeEnabled;
if ~strategy.computeEnabled
    in.pComputeBaseDemandMW=0;
    in.pComputeFlexibleMaxMW=0;
    in.initial.computePowerMW=0;
end
if ~strategy.hydrogenEnabled
    in.initial.h2InventoryKg=0;
    in.initial.electrolyzerOnlineModules=0;
    in.initial.electrolyzerPowerMW=0;
end
end

function in=apply_event_rule(in,eventCode,strategy)
if ~strategy.eventReserveRule, return; end
switch upper(char(eventCode))
    case 'TYPHOON_WARNING'
        % Warning is known at the current interval. Suspend optional product
        % conversion/export so current renewable can restore state of charge.
        in.cableSendLimitMW=0;
        in.pComputeFlexibleMaxMW=0;
        in.availability.electrolyzer=0;
        in.availability.h2Pipe=0;
        in.availability.h2Ship=0;
    case 'TYPHOON_PASSAGE'
        in.cableSendLimitMW=0;
        in.pComputeFlexibleMaxMW=0;
        in.availability.electrolyzer=0;
        in.availability.h2Pipe=0;
        in.availability.h2Ship=0;
        in.availability.compute=0;
    otherwise
        % Normal and recovery follow measured availability in the scenario.
end
end

function in=slice_hour(base,t,state)
in=struct;
names=fieldnames(base);
N=numel(base.timeH);
for k=1:numel(names)
    name=names{k};
    if any(strcmp(name,{'availability','initial'})), continue; end
    value=base.(name);
    if (isnumeric(value)||islogical(value)) && isvector(value) && ...
            numel(value)==N
        value=value(t);
    end
    in.(name)=value;
end
in.timeH=base.timeH(t);
in.availability=struct;
names=fieldnames(base.availability);
for k=1:numel(names)
    value=base.availability.(names{k});
    if ~isscalar(value), value=value(t); end
    in.availability.(names{k})=value;
end
in.initial=state;
end

function state=terminal_state(result)
d=result.dispatch;
state=struct('bessEnergyMWh',max(0,d.bessEnergyMWh(end)), ...
    'h2InventoryKg',max(0,d.h2InventoryKg(end)), ...
    'electrolyzerOnlineModules',max(0,round(d.nElectrolyzerOnline(end))), ...
    'electrolyzerPowerMW',max(0,d.pElectrolyzerMW(end)), ...
    'computePowerMW',max(0,d.pComputeFacilityMW(end)), ...
    'h2PowerMW',max(0,d.pH2PowerMW(end)));
end

function value=field_or(s,name,defaultValue)
if isfield(s,name), value=s.(name); else, value=defaultValue; end
end
