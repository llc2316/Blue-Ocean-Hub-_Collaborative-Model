function [summary,hourlyLedger,results] = ...
    c5_run_sequential_hourly(base,cfg,strategy,eventCode,retainResults)
%C5_RUN_SEQUENTIAL_HOURLY Causal one-interval-at-a-time V5 execution.
%
% Forecast planning uses only information available before hour t. The
% settlement pass uses current physical availability and carries only the
% preceding terminal physical state. The online prior-posterior strategy
% filters E/H/C share changes before applying the real-hour constraint.

if nargin<4 || isempty(eventCode)
    eventCode=repmat("NORMAL",numel(base.timeH),1);
else
    eventCode=string(eventCode(:));
end
if nargin<5 || isempty(retainResults), retainResults=false; end
N=numel(base.timeH);
assert(numel(eventCode)==N,'eventCode must align with base.timeH.');
strategy=normalize_strategy(strategy);
strategy=apply_default_normal_state_floor(strategy,base,cfg);

cfg.objective.primary=strategy.objectivePrimary;
cfg.objective.maxENSMWh=strategy.maxENSMWh;
cfg.objective.maxNetGHGKgCO2e=Inf;
cfg.objective.minRenewableUtilization=0;
cfg.objective.tieBreak=strategy.tieBreak;
cfg.objective.temporalTieBreak='none';
cfg.solver.maxTimeS=min(cfg.solver.maxTimeS,30);
cfg.bess.terminalRule='none';
cfg.hydrogen.terminalRule='none';

forecastState=[];
if strategy.forecastMode=="KALMAN_PRIOR_POSTERIOR"
    [~,forecastState]=c5_kalman_prior_posterior_policy( ...
        'initialize',[],base,cfg,strategy,eventCode,1);
end

state=base.initial;
planMemory=struct('share',[NaN NaN NaN]);
dispatchRows=cell(N,1);
resultRows=cell(N,1);
if retainResults, results=cell(N,1); else, results={}; end

plannedShare=nan(N,3);
rawPlannedShare=nan(N,3);
plannedActive=false(N,1);
planHeldByDeadband=false(N,1);
planShareChangeL1=nan(N,1);
planningAvailableMW=nan(N,1);
priorAvailableMW=nan(N,1);
posteriorAvailableMW=nan(N,1);
forecastSigmaMW=nan(N,1);
forecastErrorMW=nan(N,1);
plannedWindowH=nan(N,1);
plannedFirstHourAllocatedMW=nan(N,1);
plannedFirstHourHydrogenMW=nan(N,1);
plannedWindowHydrogenMWh=nan(N,1);
plannedMinimumAllocatedInputMW=nan(N,1);
eventRiskLevel=zeros(N,1);
riskQuantile=0.50*ones(N,1);
bessReserveTargetSOC=nan(N,1);
h2ReserveTargetKg=nan(N,1);
bessReserveShortfallMWh=nan(N,1);
h2ReserveShortfallKg=nan(N,1);
reserveMode=strings(N,1);
planStatus=strings(N,1);
planFallbackUsed=false(N,1);
planFallbackMessage=strings(N,1);
reserveConstraintRelaxationUsed=false(N,1);
reliabilityRelaxationUsed=false(N,1);
minimumFeasibleENSMWh=nan(N,1);
reserveTargetEnforced=false(N,1);
reserveTargetFallbackUsed=false(N,1);
normalStateFloorEnforced=false(N,1);
normalBessFloorShortfallMWh=nan(N,1);
normalH2FloorShortfallKg=nan(N,1);
surplusRedispatchUsed=false(N,1);
surplusRedispatchHydrogenMWh=nan(N,1);
surplusRedispatchCurtailmentReductionMWh=nan(N,1);
surplusRedispatchTriggerMW=nan(N,1);
hourRunStatus=strings(N,1);
hourStrictPass=false(N,1);
hourRelaxedPass=false(N,1);

for t=1:N
    plan=build_planning_decision( ...
        base,cfg,strategy,eventCode,t,state,forecastState);
    if strategy.forecastMode=="KALMAN_PRIOR_POSTERIOR"
        forecastState=plan.forecastState;
    end
    [plan,planMemory]=stabilize_planned_share( ...
        plan,planMemory,strategy,eventCode(t));

    in=slice_hour(base,t,state);
    in=apply_asset_switches(in,strategy);
    [in,eventDecision]=apply_event_rule(in,eventCode(t),strategy,cfg);
    [in,plan]=apply_product_mix(in,cfg,strategy,plan);

    cfg.meta.parameterVersion=sprintf('%s_h%04d',strategy.id,t);
    [result,fallbackUsed,fallbackMessage,reserveRelaxed, ...
        reliabilityRelaxed,minFeasibleENS,redispatchUsed, ...
        redispatchHydrogenMWh,redispatchCurtailmentReductionMWh, ...
        redispatchTriggerMW]= ...
        run_actual_dispatch(in,cfg,strategy,plan,eventDecision,t);
    assert(result.audit.pass, ...
        'Hourly audit failed for %s at hour %d.',strategy.id,t);
    hourRunStatus(t)=dispatch_run_status(result,fallbackUsed, ...
        reserveRelaxed || reliabilityRelaxed);
    hourStrictPass(t)=hourRunStatus(t)=="PASS_STRICT";
    hourRelaxedPass(t)=hourRunStatus(t)=="PASS_RELAXED";
    state=terminal_state(result);

    if strategy.forecastMode=="KALMAN_PRIOR_POSTERIOR"
        [~,forecastState]=c5_kalman_prior_posterior_policy( ...
            'update',forecastState,base,cfg,strategy,eventCode,t);
    end

    d=result.dispatch;
    d.timeH=base.timeH(t);
    strategyId=repmat(string(strategy.id),height(d),1);
    event=repmat(eventCode(t),height(d),1);
    dispatchRows{t}=addvars(d,strategyId,event,'Before',1, ...
        'NewVariableNames',{'strategyId','eventCode'});
    k=result.kpi;
    h2ProducedKg=max(0,sum(d.h2ProducedKg));
    h2InventoryDeltaKg=d.h2InventoryKg(end)-in.initial.h2InventoryKg;
    resultRows{t}=table(base.timeH(t),eventCode(t), ...
        k.eAvailableMWh,k.eSourceUsedMWh,k.eElectricityInputMWh, ...
        k.eHydrogenInputMWh,k.eFlexibleComputeInputMWh, ...
        k.eCableReceivedMWh,h2ProducedKg,k.h2PipeDeliveredKg, ...
        k.h2ShipDeliveredKg,k.h2DeliveredKg,h2InventoryDeltaKg, ...
        k.eComputeServiceMWhCS, ...
        k.eCurtailmentMWh,k.ensMWh,k.outputRevenueCNY, ...
        k.operatingCostCNY,k.economicNetCostCNY, ...
        result.meta.exitflag,result.audit.pass,hourRunStatus(t), ...
        hourStrictPass(t),hourRelaxedPass(t), ...
        'VariableNames',{'timeH','eventCode','eAvailableMWh', ...
        'eSourceUsedMWh','eElectricityInputMWh','eHydrogenInputMWh', ...
        'eFlexibleComputeInputMWh','eCableReceivedMWh', ...
        'h2ProducedKg','h2PipeDeliveredKg','h2ShipDeliveredKg', ...
        'h2DeliveredKg', ...
        'h2InventoryDeltaKg','eComputeServiceMWhCS', ...
        'eCurtailmentMWh','ensMWh', ...
        'outputRevenueCNY','operatingCostCNY','economicNetCostCNY', ...
        'exitflag','auditPass','runStatus','strictPass','relaxedPass'});
    if retainResults, results{t}=result; end

    plannedShare(t,:)=plan.share;
    rawPlannedShare(t,:)=plan.rawShare;
    plannedActive(t)=plan.productMixEnabled;
    planHeldByDeadband(t)=plan.heldByDeadband;
    planShareChangeL1(t)=plan.shareChangeL1;
    planningAvailableMW(t)=plan.planningAvailableMW;
    priorAvailableMW(t)=plan.priorAvailableMW;
    posteriorAvailableMW(t)=plan.posteriorAvailableMW;
    forecastSigmaMW(t)=plan.forecastSigmaMW;
    forecastErrorMW(t)=in.pSourceAvailableMW-plan.planningAvailableMW;
    plannedWindowH(t)=plan.windowH;
    plannedFirstHourAllocatedMW(t)=plan.firstHourAllocatedMW;
    plannedFirstHourHydrogenMW(t)=plan.firstHourHydrogenMW;
    plannedWindowHydrogenMWh(t)=plan.windowHydrogenMWh;
    plannedMinimumAllocatedInputMW(t)=plan.minimumAllocatedInputMW;
    eventRiskLevel(t)=eventDecision.eventRiskLevel;
    riskQuantile(t)=plan.riskQuantile;
    bessReserveTargetSOC(t)=eventDecision.bessReserveTargetSOC;
    h2ReserveTargetKg(t)=eventDecision.h2ReserveTargetKg;
    [bessReserveShortfallMWh(t),h2ReserveShortfallKg(t)]= ...
        reserve_shortfall(result,cfg,eventDecision);
    reserveMode(t)=eventDecision.reserveMode;
    planStatus(t)=plan.status;
    planFallbackUsed(t)=fallbackUsed;
    planFallbackMessage(t)=fallbackMessage;
    reserveConstraintRelaxationUsed(t)=reserveRelaxed;
    reliabilityRelaxationUsed(t)=reliabilityRelaxed;
    minimumFeasibleENSMWh(t)=minFeasibleENS;
    reserveTargetEnforced(t)=eventDecision.enforceReserveTarget;
    reserveTargetFallbackUsed(t)=reserveRelaxed;
    normalStateFloorEnforced(t)=eventDecision.normalStateFloorEnforced;
    if normalStateFloorEnforced(t)
        normalBessFloorShortfallMWh(t)=bessReserveShortfallMWh(t);
        normalH2FloorShortfallKg(t)=h2ReserveShortfallKg(t);
    end
    surplusRedispatchUsed(t)=redispatchUsed;
    surplusRedispatchHydrogenMWh(t)=redispatchHydrogenMWh;
    surplusRedispatchCurtailmentReductionMWh(t)= ...
        redispatchCurtailmentReductionMWh;
    surplusRedispatchTriggerMW(t)=redispatchTriggerMW;
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
elseif is_plan_forecast(strategy) && any(active & plannedActive)
    idx=active & plannedActive;
    maxHourlyShareDeviation=max(abs(realized(idx,:)-plannedShare(idx,:)), ...
        [],'all');
else
    maxHourlyShareDeviation=NaN;
end
eE=sum(hourlyLedger.eElectricityInputMWh);
eH=sum(hourlyLedger.eHydrogenInputMWh);
eC=sum(hourlyLedger.eFlexibleComputeInputMWh);
den=eE+eH+eC;
if den>0, annualShare=[eE,eH,eC]/den; else, annualShare=[0 0 0]; end
summaryRunStatus=summarize_run_status(hourRunStatus);
summaryStrictPass=summaryRunStatus=="PASS_STRICT";
summaryRelaxedPass=summaryRunStatus=="PASS_RELAXED";
summaryMainConclusionEligible=summaryStrictPass && ...
    all(hourlyLedger.auditPass) && all(hourlyLedger.exitflag>0);
summaryMainConclusionStatus=main_conclusion_status(summaryRunStatus);
summary=table(string(strategy.id),string(strategy.strategyClass),N, ...
    strategy.productMixEnabled,strategy.eShare,strategy.hShare, ...
    strategy.cShare,strategy.planningWindowH, ...
    strategy.plannedMinimumAllocationFactor, ...
    nnz(active),maxHourlyShareDeviation, ...
    sum(hourlyLedger.eAvailableMWh),sum(hourlyLedger.eSourceUsedMWh), ...
    eE,eH,eC,annualShare(1),annualShare(2),annualShare(3), ...
    sum(hourlyLedger.eCableReceivedMWh), ...
    sum(hourlyLedger.h2ProducedKg), ...
    sum(hourlyLedger.h2PipeDeliveredKg), ...
    sum(hourlyLedger.h2ShipDeliveredKg), ...
    sum(hourlyLedger.h2DeliveredKg), ...
    sum(hourlyLedger.h2InventoryDeltaKg), ...
    sum(hourlyLedger.eComputeServiceMWhCS), ...
    sum(hourlyLedger.eCurtailmentMWh),sum(hourlyLedger.ensMWh), ...
    sum(hourlyLedger.outputRevenueCNY),sum(hourlyLedger.operatingCostCNY), ...
    sum(hourlyLedger.economicNetCostCNY), ...
    all(hourlyLedger.auditPass),all(hourlyLedger.exitflag>0), ...
    summaryRunStatus,summaryStrictPass,summaryRelaxedPass, ...
    summaryMainConclusionEligible,summaryMainConclusionStatus, ...
    information_boundary(strategy), ...
    "[假设值，待企业调研校准]", ...
    string(strategy.forecastMode),mean(abs(forecastErrorMW),'omitnan'), ...
    mean(forecastSigmaMW,'omitnan'), ...
    max(bessReserveShortfallMWh,[],'omitnan'), ...
    max(h2ReserveShortfallKg,[],'omitnan'), ...
    mean(planShareChangeL1,'omitnan'), ...
    max(planShareChangeL1,[],'omitnan'),nnz(planHeldByDeadband), ...
    nnz(planFallbackUsed),nnz(reserveConstraintRelaxationUsed), ...
    nnz(reliabilityRelaxationUsed), ...
    nnz(normalStateFloorEnforced), ...
    max(normalBessFloorShortfallMWh,[],'omitnan'), ...
    max(normalH2FloorShortfallKg,[],'omitnan'), ...
    nnz(reserveTargetFallbackUsed), ...
    nnz(surplusRedispatchUsed), ...
    sum(surplusRedispatchHydrogenMWh,'omitnan'), ...
    sum(surplusRedispatchCurtailmentReductionMWh,'omitnan'), ...
    'VariableNames',{'strategyId','strategyClass','horizonH', ...
    'productMixEnabled','targetElectricityShare','targetHydrogenShare', ...
    'targetComputeShare','planningWindowH', ...
    'plannedMinimumAllocationFactor', ...
    'activeRatioHours','maxHourlyShareDeviation', ...
    'eAvailableMWh','eSourceUsedMWh','eElectricityInputMWh', ...
    'eHydrogenInputMWh','eFlexibleComputeInputMWh', ...
    'realizedElectricityInputShare','realizedHydrogenInputShare', ...
    'realizedComputeInputShare','eCableReceivedMWh', ...
    'h2ProducedKg','h2PipeDeliveredKg','h2ShipDeliveredKg', ...
    'h2DeliveredKg','h2InventoryDeltaKg', ...
    'eComputeServiceMWhCS','eCurtailmentMWh','ensMWh', ...
    'outputRevenueCNY','operatingCostCNY','economicNetCostCNY', ...
    'auditPass','allHoursOptimal','runStatus','strictPass', ...
    'relaxedPass','mainConclusionEligible','mainConclusionStatus', ...
    'informationBoundary', ...
    'parameterStatus','forecastMode','meanAbsForecastErrorMW', ...
    'meanForecastSigmaMW', ...
    'maxBessReserveShortfallMWh','maxH2ReserveShortfallKg', ...
    'meanPlanShareChangeL1', ...
    'maxPlanShareChangeL1','planDeadbandHoldHours', ...
    'planFallbackHours','reserveConstraintRelaxationHours', ...
    'reliabilityRelaxationHours','normalStateFloorEnforcedHours', ...
    'maxNormalBessFloorShortfallMWh','maxNormalH2FloorShortfallKg', ...
    'reserveTargetFallbackHours','surplusRedispatchHours', ...
    'surplusRedispatchHydrogenMWh','surplusRedispatchCurtailmentReductionMWh'});
hourlyLedger.strategyId=repmat(string(strategy.id),N,1);
hourlyLedger.realizedElectricityShare=realized(:,1);
hourlyLedger.realizedHydrogenShare=realized(:,2);
hourlyLedger.realizedComputeShare=realized(:,3);
hourlyLedger.ratioActive=active;
hourlyLedger.forecastMode=repmat(string(strategy.forecastMode),N,1);
hourlyLedger.priorAvailableMW=priorAvailableMW;
hourlyLedger.posteriorAvailableMW=posteriorAvailableMW;
hourlyLedger.forecastSigmaMW=forecastSigmaMW;
hourlyLedger.planningAvailableMW=planningAvailableMW;
hourlyLedger.forecastErrorMW=forecastErrorMW;
hourlyLedger.planningWindowH=plannedWindowH;
hourlyLedger.plannedFirstHourAllocatedMW=plannedFirstHourAllocatedMW;
hourlyLedger.plannedFirstHourHydrogenMW=plannedFirstHourHydrogenMW;
hourlyLedger.plannedWindowHydrogenMWh=plannedWindowHydrogenMWh;
hourlyLedger.plannedMinimumAllocatedInputMW= ...
    plannedMinimumAllocatedInputMW;
hourlyLedger.plannedElectricityShare=plannedShare(:,1);
hourlyLedger.plannedHydrogenShare=plannedShare(:,2);
hourlyLedger.plannedComputeShare=plannedShare(:,3);
hourlyLedger.rawPlannedElectricityShare=rawPlannedShare(:,1);
hourlyLedger.rawPlannedHydrogenShare=rawPlannedShare(:,2);
hourlyLedger.rawPlannedComputeShare=rawPlannedShare(:,3);
hourlyLedger.plannedRatioActive=plannedActive;
hourlyLedger.planHeldByDeadband=planHeldByDeadband;
hourlyLedger.planShareChangeL1=planShareChangeL1;
hourlyLedger.eventRiskLevel=eventRiskLevel;
hourlyLedger.riskQuantile=riskQuantile;
hourlyLedger.bessReserveTargetSOC=bessReserveTargetSOC;
hourlyLedger.h2ReserveTargetKg=h2ReserveTargetKg;
hourlyLedger.bessReserveShortfallMWh=bessReserveShortfallMWh;
hourlyLedger.h2ReserveShortfallKg=h2ReserveShortfallKg;
hourlyLedger.reserveMode=reserveMode;
hourlyLedger.planStatus=planStatus;
hourlyLedger.planFallbackUsed=planFallbackUsed;
hourlyLedger.planFallbackMessage=planFallbackMessage;
hourlyLedger.reserveConstraintRelaxationUsed= ...
    reserveConstraintRelaxationUsed;
hourlyLedger.reliabilityRelaxationUsed=reliabilityRelaxationUsed;
hourlyLedger.minimumFeasibleENSMWh=minimumFeasibleENSMWh;
hourlyLedger.reserveTargetEnforced=reserveTargetEnforced;
hourlyLedger.reserveTargetFallbackUsed=reserveTargetFallbackUsed;
hourlyLedger.normalStateFloorEnforced=normalStateFloorEnforced;
hourlyLedger.normalBessFloorShortfallMWh=normalBessFloorShortfallMWh;
hourlyLedger.normalH2FloorShortfallKg=normalH2FloorShortfallKg;
hourlyLedger.surplusRedispatchUsed=surplusRedispatchUsed;
hourlyLedger.surplusRedispatchHydrogenMWh=surplusRedispatchHydrogenMWh;
hourlyLedger.surplusRedispatchCurtailmentReductionMWh= ...
    surplusRedispatchCurtailmentReductionMWh;
hourlyLedger.surplusRedispatchTriggerMW=surplusRedispatchTriggerMW;
hourlyLedger.runStatus=hourRunStatus;
hourlyLedger.strictPass=hourStrictPass;
hourlyLedger.relaxedPass=hourRelaxedPass;
hourlyLedger.mainConclusionEligible=hourlyLedger.strictPass & ...
    hourlyLedger.auditPass & hourlyLedger.exitflag>0;
hourlyLedger.mainConclusionStatus=strings(N,1);
for t=1:N
    hourlyLedger.mainConclusionStatus(t)= ...
        main_conclusion_status(hourlyLedger.runStatus(t));
end
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
hourlyLedger.pComputeBaseUnservedMW=dispatch.pComputeBaseUnservedMW;
hourlyLedger.pMarineUnservedMW=dispatch.pMarineUnservedMW;
hourlyLedger.pInternalUnservedMW=dispatch.pInternalUnservedMW;
hourlyLedger=append_optional_source_columns(hourlyLedger,base,N);
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
strategy.plannedShareTolerance=double(field_or( ...
    strategy,'plannedShareTolerance',max(strategy.shareTolerance,0.10)));
strategy.planMaxTimeS=double(field_or(strategy,'planMaxTimeS',10));
strategy.planningWindowH=double(field_or(strategy,'planningWindowH',1));
strategy.plannedMinimumAllocationFactor=double(field_or( ...
    strategy,'plannedMinimumAllocationFactor',0));
strategy.initialPlanningCapacityFactor=double(field_or( ...
    strategy,'initialPlanningCapacityFactor',0.25));
strategy.allowPlanFallback=logical(field_or( ...
    strategy,'allowPlanFallback',true));
strategy.allowReliabilityRelaxation=logical(field_or( ...
    strategy,'allowReliabilityRelaxation',true));
strategy.strictReliabilityMaxTimeS=double(field_or( ...
    strategy,'strictReliabilityMaxTimeS',0.5));
strategy.surplusRedispatchEnabled=logical(field_or( ...
    strategy,'surplusRedispatchEnabled',false));
strategy.surplusRedispatchMinCurtailmentMW=double(field_or( ...
    strategy,'surplusRedispatchMinCurtailmentMW',1e-6));
strategy.electricityEnabled=logical(field_or( ...
    strategy,'electricityEnabled',true));
strategy.hydrogenEnabled=logical(field_or( ...
    strategy,'hydrogenEnabled',true));
strategy.computeEnabled=logical(field_or(strategy,'computeEnabled',true));
strategy.eventReserveRule=logical(field_or( ...
    strategy,'eventReserveRule',true));
strategy.robustEventReserveRule=logical(field_or( ...
    strategy,'robustEventReserveRule',false));
strategy.normalStateFloorRule=logical(field_or( ...
    strategy,'normalStateFloorRule',true));
strategy.normalBessReserveTargetSOC=double(field_or( ...
    strategy,'normalBessReserveTargetSOC',NaN));
strategy.normalH2ReserveTargetKg=double(field_or( ...
    strategy,'normalH2ReserveTargetKg',NaN));
strategy.warningBessReserveTargetSOC=double(field_or( ...
    strategy,'warningBessReserveTargetSOC',0.80));
strategy.warningH2ReserveTargetKg=double(field_or( ...
    strategy,'warningH2ReserveTargetKg',0));
strategy.recoveryBessReserveTargetSOC=double(field_or( ...
    strategy,'recoveryBessReserveTargetSOC',0.60));
strategy.recoveryH2ReserveTargetKg=double(field_or( ...
    strategy,'recoveryH2ReserveTargetKg',0));
strategy.normalLowReserveOptionalLimitFactor=double(field_or( ...
    strategy,'normalLowReserveOptionalLimitFactor',0));
strategy.recoveryOptionalLimitFactor=double(field_or( ...
    strategy,'recoveryOptionalLimitFactor',0.25));
strategy.planShareFilterAlpha=double(field_or( ...
    strategy,'planShareFilterAlpha',0.35));
strategy.planShareMaxDeltaPerHour=double(field_or( ...
    strategy,'planShareMaxDeltaPerHour',0.10));
strategy.planShareDeadband=double(field_or( ...
    strategy,'planShareDeadband',0.02));
strategy.recoveryShareFilterAlpha=double(field_or( ...
    strategy,'recoveryShareFilterAlpha',0.20));
strategy.recoveryShareMaxDeltaPerHour=double(field_or( ...
    strategy,'recoveryShareMaxDeltaPerHour',0.05));
strategy.forecastMode=upper(string(field_or( ...
    strategy,'forecastMode','CURRENT_OBSERVATION')));
allowed=["CURRENT_OBSERVATION","PREVIOUS_HOUR_PERSISTENCE", ...
    "KALMAN_PRIOR_POSTERIOR"];
assert(any(strategy.forecastMode==allowed), ...
    'strategy.forecastMode must be CURRENT_OBSERVATION, PREVIOUS_HOUR_PERSISTENCE or KALMAN_PRIOR_POSTERIOR.');
assert(strategy.shareTolerance>=0 && strategy.shareTolerance<0.5, ...
    'strategy.shareTolerance must be in [0,0.5).');
assert(strategy.plannedShareTolerance>=0 && ...
    strategy.plannedShareTolerance<0.5, ...
    'strategy.plannedShareTolerance must be in [0,0.5).');
assert(strategy.planMaxTimeS>0 && isfinite(strategy.planMaxTimeS), ...
    'strategy.planMaxTimeS must be positive.');
assert(strategy.planningWindowH>=1 && ...
    strategy.planningWindowH==round(strategy.planningWindowH) && ...
    any(strategy.planningWindowH==[1 6 12 24 48]), ...
    'strategy.planningWindowH must be one of 1, 6, 12, 24 or 48.');
assert(strategy.plannedMinimumAllocationFactor>=0 && ...
    strategy.plannedMinimumAllocationFactor<=1, ...
    'strategy.plannedMinimumAllocationFactor must be in [0,1].');
assert(strategy.strictReliabilityMaxTimeS>0 && ...
    isfinite(strategy.strictReliabilityMaxTimeS), ...
    'strategy.strictReliabilityMaxTimeS must be positive.');
assert(strategy.surplusRedispatchMinCurtailmentMW>=0 && ...
    isfinite(strategy.surplusRedispatchMinCurtailmentMW), ...
    'strategy.surplusRedispatchMinCurtailmentMW must be nonnegative.');
assert(strategy.initialPlanningCapacityFactor>=0 && ...
    strategy.initialPlanningCapacityFactor<=1, ...
    'strategy.initialPlanningCapacityFactor must be in [0,1].');
assert(strategy.recoveryOptionalLimitFactor>=0 && ...
    strategy.recoveryOptionalLimitFactor<=1, ...
    'strategy.recoveryOptionalLimitFactor must be in [0,1].');
assert(strategy.normalLowReserveOptionalLimitFactor>=0 && ...
    strategy.normalLowReserveOptionalLimitFactor<=1, ...
    'strategy.normalLowReserveOptionalLimitFactor must be in [0,1].');
assert(all([strategy.warningBessReserveTargetSOC, ...
    strategy.recoveryBessReserveTargetSOC]>=0) && ...
    all([strategy.warningBessReserveTargetSOC, ...
    strategy.recoveryBessReserveTargetSOC]<=1) && ...
    (isnan(strategy.normalBessReserveTargetSOC) || ...
    (strategy.normalBessReserveTargetSOC>=0 && ...
     strategy.normalBessReserveTargetSOC<=1)), ...
    'BESS reserve SOC targets must be within the normalized SOC range.');
assert(isnan(strategy.normalH2ReserveTargetKg) || ...
    strategy.normalH2ReserveTargetKg>=0, ...
    'normalH2ReserveTargetKg must be NaN or nonnegative.');
assert(strategy.warningH2ReserveTargetKg>=0 && ...
    strategy.recoveryH2ReserveTargetKg>=0, ...
    'Hydrogen reserve targets must be nonnegative.');
assert(strategy.planShareFilterAlpha>0 && ...
    strategy.planShareFilterAlpha<=1, ...
    'strategy.planShareFilterAlpha must be in (0,1].');
assert(strategy.recoveryShareFilterAlpha>0 && ...
    strategy.recoveryShareFilterAlpha<=1, ...
    'strategy.recoveryShareFilterAlpha must be in (0,1].');
assert(strategy.planShareMaxDeltaPerHour>0 && ...
    strategy.planShareMaxDeltaPerHour<=1, ...
    'strategy.planShareMaxDeltaPerHour must be in (0,1].');
assert(strategy.recoveryShareMaxDeltaPerHour>0 && ...
    strategy.recoveryShareMaxDeltaPerHour<=1, ...
    'strategy.recoveryShareMaxDeltaPerHour must be in (0,1].');
assert(strategy.planShareDeadband>=0 && strategy.planShareDeadband<1, ...
    'strategy.planShareDeadband must be in [0,1).');
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

function strategy=apply_default_normal_state_floor(strategy,base,cfg)
if ~strategy.normalStateFloorRule
    return
end
if ~isfinite(strategy.normalBessReserveTargetSOC)
    strategy.normalBessReserveTargetSOC= ...
        base.initial.bessEnergyMWh/cfg.bess.energyMWh;
end
strategy.normalBessReserveTargetSOC=min(cfg.bess.socMax, ...
    max(cfg.bess.socMin,strategy.normalBessReserveTargetSOC));
if ~isfinite(strategy.normalH2ReserveTargetKg)
    strategy.normalH2ReserveTargetKg=base.initial.h2InventoryKg;
end
strategy.normalH2ReserveTargetKg=min(cfg.hydrogen.storageMaxKg, ...
    max(0,strategy.normalH2ReserveTargetKg));
end

function plan=build_planning_decision( ...
    base,cfg,strategy,eventCode,t,state,forecastState)
plan=default_plan(strategy);
if ~is_plan_forecast(strategy)
    plan.status="NOT_APPLICABLE_CURRENT_OBSERVATION";
    return
end

switch strategy.forecastMode
    case "PREVIOUS_HOUR_PERSISTENCE"
        plan.planningAvailableMW=previous_hour_planning_available( ...
            base,cfg,strategy,t);
        plan.planningWindowAvailableMW=repmat( ...
            plan.planningAvailableMW, ...
            min(strategy.planningWindowH,numel(base.timeH)-t+1),1);
        plan.priorAvailableMW=plan.planningAvailableMW;
        plan.posteriorAvailableMW=plan.planningAvailableMW;
        plan.riskQuantile=event_quantile(eventCode(t));
    case "KALMAN_PRIOR_POSTERIOR"
        [forecastPlan,forecastState]=c5_kalman_prior_posterior_policy( ...
            'plan',forecastState,base,cfg,strategy,eventCode,t);
        plan.forecastState=forecastState;
        plan.planningAvailableMW=forecastPlan.planningAvailableMW;
        plan.priorAvailableMW=forecastPlan.priorAvailableMW;
        plan.posteriorAvailableMW=forecastPlan.posteriorAvailableMW;
        plan.forecastSigmaMW=forecastPlan.forecastSigmaMW;
        plan.planningWindowAvailableMW= ...
            forecastPlan.planningWindowAvailableMW;
        plan.riskQuantile=forecastPlan.riskQuantile;
        plan.eventRiskLevel=forecastPlan.eventRiskLevel;
    otherwise
        error('Unsupported forecast mode: %s',char(strategy.forecastMode));
end

windowH=min(strategy.planningWindowH,numel(base.timeH)-t+1);
plan.windowH=windowH;
planIn=slice_window(base,t,windowH,state);
planIn.pSourceAvailableMW=min( ...
    cfg.source.installedMW,max(0, ...
    plan.planningWindowAvailableMW(1:windowH)));
if isfield(planIn,'pSourceAuxMW')
    planIn.pSourceAuxMW=repmat(previous_hour_source_aux(base,t), ...
        windowH,1);
end
planIn=apply_asset_switches(planIn,strategy);
planIn=apply_event_rule_window(planIn,eventCode(t:t+windowH-1), ...
    strategy,cfg);
planIn.productMix=struct('enabled',false);
cfgPlan=cfg;
cfgPlan.objective.primary='economicNetCostCNY';
cfgPlan.objective.maxENSMWh=Inf;
cfgPlan.objective.maxNetGHGKgCO2e=Inf;
cfgPlan.objective.minRenewableUtilization=0;
cfgPlan.objective.tieBreak='none';
cfgPlan.solver.maxTimeS=min(cfgPlan.solver.maxTimeS, ...
    strategy.planMaxTimeS);
cfgPlan.bess.terminalRule='none';
cfgPlan.hydrogen.terminalRule='none';
cfgPlan.meta.parameterVersion=sprintf('%s_plan_h%04d',strategy.id,t);

try
    planResult=run_hour_kernel(planIn,cfgPlan);
    if ~planResult.audit.pass
        plan.status="PLAN_AUDIT_FAILED";
        return
    end
    firstHourInput=[planResult.dispatch.pCableSendMW(1), ...
        planResult.dispatch.pElectrolyzerMW(1), ...
        planResult.dispatch.pComputeFlexibleMW(1)];
    allocated=sum(firstHourInput);
    plan.firstHourAllocatedMW=allocated;
    plan.firstHourHydrogenMW=firstHourInput(2);
    plan.windowHydrogenMWh=planResult.kpi.eHydrogenInputMWh;
    plan.minimumAllocatedInputMW= ...
        strategy.plannedMinimumAllocationFactor*allocated;
    if allocated>1e-8
        plan.share=firstHourInput/allocated;
        plan.productMixEnabled=true;
        plan.status="PLAN_SOLVED";
    else
        plan.status="PLAN_SOLVED_NO_OPTIONAL_PRODUCT";
    end
catch ME
    plan.status="PLAN_SOLVE_FAILED";
    plan.message=regexprep(strtrim(string(ME.message)),'\s+',' ');
end
end

function [plan,memory]=stabilize_planned_share( ...
    plan,memory,strategy,eventCode)
% Exponential smoothing + deadband + bounded hourly ramp.
% The ramp-constraint idea follows Teleke et al., Renewable Energy 2010,
% DOI 10.1016/j.renene.2009.11.030. Controller parameters are
% [假设值，待企业调研校准].
plan.rawShare=plan.share;
plan.heldByDeadband=false;
plan.shareChangeL1=NaN;
if ~plan.productMixEnabled || ...
        strategy.forecastMode~="KALMAN_PRIOR_POSTERIOR"
    return
end
raw=max(0,double(plan.share));
raw=raw/sum(raw);
previous=memory.share;
if any(~isfinite(previous))
    plan.share=raw;
    plan.shareChangeL1=0;
    memory.share=raw;
    return
end

if max(abs(raw-previous))<=strategy.planShareDeadband
    filtered=previous;
    plan.heldByDeadband=true;
else
    eventText=char(eventCode);
    if strcmpi(eventText,'TYPHOON_RECOVERY')
        alpha=strategy.recoveryShareFilterAlpha;
        maxDelta=strategy.recoveryShareMaxDeltaPerHour;
    else
        alpha=strategy.planShareFilterAlpha;
        maxDelta=strategy.planShareMaxDeltaPerHour;
    end
    candidate=(1-alpha)*previous+alpha*raw;
    lower=max(0,previous-maxDelta);
    upperBound=min(1,previous+maxDelta);
    filtered=project_bounded_simplex(candidate,lower,upperBound);
end
plan.share=filtered;
plan.shareChangeL1=sum(abs(filtered-previous));
memory.share=filtered;
end

function x=project_bounded_simplex(value,lower,upper)
% Euclidean projection onto sum(x)=1 with component bounds.
assert(sum(lower)<=1+1e-12 && sum(upper)>=1-1e-12, ...
    'Share ramp bounds do not intersect the unit simplex.');
lo=min(value-upper)-1;
hi=max(value-lower)+1;
for k=1:80
    lambda=(lo+hi)/2;
    x=min(upper,max(lower,value-lambda));
    if sum(x)>1
        lo=lambda;
    else
        hi=lambda;
    end
end
x=min(upper,max(lower,value-(lo+hi)/2));
x=x/sum(x);
end

function plan=default_plan(strategy)
plan=struct( ...
    'forecastState',[], ...
    'windowH',1, ...
    'planningAvailableMW',NaN, ...
    'planningWindowAvailableMW',NaN, ...
    'priorAvailableMW',NaN, ...
    'posteriorAvailableMW',NaN, ...
    'forecastSigmaMW',NaN, ...
    'riskQuantile',0.50, ...
    'eventRiskLevel',0, ...
    'share',[NaN NaN NaN], ...
    'rawShare',[NaN NaN NaN], ...
    'heldByDeadband',false, ...
    'shareChangeL1',NaN, ...
    'firstHourAllocatedMW',NaN, ...
    'firstHourHydrogenMW',NaN, ...
    'windowHydrogenMWh',NaN, ...
    'minimumAllocatedInputMW',0, ...
    'productMixEnabled',false, ...
    'status',"NOT_PLANNED", ...
    'message',"");
if strategy.forecastMode=="CURRENT_OBSERVATION"
    plan.planningAvailableMW=NaN;
end
end

function [in,plan]=apply_product_mix(in,cfg,strategy,plan)
if strategy.productMixEnabled
    in.productMix=struct('enabled',true,'mode','hourly', ...
        'targetElectricityShare',strategy.eShare, ...
        'targetHydrogenShare',strategy.hShare, ...
        'targetComputeShare',strategy.cShare, ...
        'shareTolerance',strategy.shareTolerance, ...
        'minimumAllocatedInputMWh',0, ...
        'minimumAllocatedInputMW',0);
elseif plan.productMixEnabled
    plan.minimumAllocatedInputMW=planned_minimum_allocated_input( ...
        in,cfg,plan);
    in.productMix=struct('enabled',true,'mode','hourly', ...
        'targetElectricityShare',plan.share(1), ...
        'targetHydrogenShare',plan.share(2), ...
        'targetComputeShare',plan.share(3), ...
        'shareTolerance',strategy.plannedShareTolerance, ...
        'minimumAllocatedInputMWh',0, ...
        'minimumAllocatedInputMW',plan.minimumAllocatedInputMW);
else
    in.productMix=struct('enabled',false);
    plan.minimumAllocatedInputMW=0;
end
end

function value=planned_minimum_allocated_input(in,cfg,plan)
requested=max(0,double(plan.minimumAllocatedInputMW));
if requested<=0 || ~isfinite(requested)
    value=0;
    return
end
internal=scalar_input(in,'pSourceAuxMW',0)+ ...
    scalar_input(in,'pCommonAuxDemandMW',0)+ ...
    scalar_input(in,'pPostPOILossMW',0);
critical=internal+scalar_input(in,'pMarineDemandMW', ...
    cfg.output.marineDemandMW)+ ...
    scalar_input(in,'pComputeBaseDemandMW',0);
sourceSurplus=max(0,scalar_input(in,'pSourceAvailableMW',0)-critical);
cableCap=scalar_input(in,'cableSendLimitMW',0)* ...
    availability_scalar(in,'cable',1);
elyCap=cfg.hydrogen.electrolyzerRatedMW* ...
    availability_scalar(in,'electrolyzer',1);
computeCap=scalar_input(in,'pComputeFlexibleMaxMW',0)* ...
    availability_scalar(in,'compute',1);
deviceCap=cableCap+elyCap+computeCap;
value=min([requested,sourceSurplus,deviceCap]);
if value<1e-8
    value=0;
end
end

function value=scalar_input(s,name,defaultValue)
if isstruct(s) && isfield(s,name)
    x=double(s.(name));
else
    x=double(defaultValue);
end
if isempty(x)
    value=double(defaultValue);
else
    value=x(1);
end
end

function value=availability_scalar(in,name,defaultValue)
if isfield(in,'availability') && isfield(in.availability,name)
    x=double(in.availability.(name));
    value=x(1);
else
    value=defaultValue;
end
end

function [result,fallbackUsed,fallbackMessage,reserveRelaxed, ...
    reliabilityRelaxed,minFeasibleENS,surplusUsed, ...
    surplusHydrogenMWh,surplusCurtailmentReductionMWh, ...
    surplusTriggerMW]= ...
    run_actual_dispatch(in,cfg,strategy,plan,eventDecision,t)
fallbackUsed=false;
fallbackMessage="";
reserveRelaxed=false;
reliabilityRelaxed=false;
minFeasibleENS=NaN;
surplusUsed=false;
surplusHydrogenMWh=NaN;
surplusCurtailmentReductionMWh=NaN;
surplusTriggerMW=NaN;
[cfgActive,reserveActive]=apply_bess_reserve_target(cfg,eventDecision);
inActive=in;
try
    result=run_strict_reliability_attempt(inActive,cfgActive,strategy,t);
    [result,surplusUsed,surplusHydrogenMWh, ...
        surplusCurtailmentReductionMWh,surplusTriggerMW]= ...
        maybe_surplus_redispatch(result,inActive,cfgActive, ...
        strategy,t);
catch ME
    strictFailureMessage=regexprep(strtrim(string(ME.message)), ...
        '\s+',' ');
    if plan.productMixEnabled && strategy.allowPlanFallback
        fallbackUsed=true;
        fallbackMessage=strictFailureMessage;
        inActive.productMix=struct('enabled',false);
        cfgActive.meta.parameterVersion=sprintf('%s_h%04d_plan_fallback', ...
            strategy.id,t);
        try
            result=run_strict_reliability_attempt( ...
                inActive,cfgActive,strategy,t);
            [result,surplusUsed,surplusHydrogenMWh, ...
                surplusCurtailmentReductionMWh,surplusTriggerMW]= ...
                maybe_surplus_redispatch(result,inActive,cfgActive, ...
                strategy,t);
            return
        catch MEfree
            fallbackMessage=fallbackMessage+" | FREE_STRICT: "+ ...
                regexprep(strtrim(string(MEfree.message)),'\s+',' ');
            ME=MEfree;
        end
    end
    if reserveActive
        reserveRelaxed=true;
        fallbackMessage=append_status(fallbackMessage, ...
            "STRICT_FAILED: "+strictFailureMessage);
        cfgNoReserve=cfg;
        cfgNoReserve.bess.terminalRule='none';
        cfgNoReserve.hydrogen.terminalRule='none';
        cfgNoReserve.meta.parameterVersion=sprintf( ...
            '%s_h%04d_reserve_fallback',strategy.id,t);
        try
            result=run_strict_reliability_attempt( ...
                inActive,cfgNoReserve,strategy,t);
            [result,surplusUsed,surplusHydrogenMWh, ...
                surplusCurtailmentReductionMWh,surplusTriggerMW]= ...
                maybe_surplus_redispatch(result,inActive,cfgNoReserve, ...
                strategy,t);
            fallbackMessage=append_status(fallbackMessage, ...
                "BESS_RESERVE_TARGET_RELAXED_FOR_ZERO_ENS");
            return
        catch MEreserve
            fallbackMessage=append_status(fallbackMessage, ...
                "BESS_RESERVE_TARGET_RELAXED; "+ ...
                regexprep(strtrim(string(MEreserve.message)),'\s+',' '));
            ME=MEreserve;
        end
    else
        cfgNoReserve=cfg;
    end
    if strategy.allowReliabilityRelaxation && ...
            cfgNoReserve.objective.maxENSMWh<=1e-12
        [result,minFeasibleENS]=run_reliability_relaxation( ...
            inActive,cfgNoReserve,t,strategy);
        [result,surplusUsed,surplusHydrogenMWh, ...
            surplusCurtailmentReductionMWh,surplusTriggerMW]= ...
            maybe_surplus_redispatch(result,inActive,cfgNoReserve, ...
            strategy,t);
        reliabilityRelaxed=true;
        if strlength(fallbackMessage)==0
            fallbackMessage="STRICT_ZERO_ENS_INFEASIBLE; RELAXED_TO_MINIMUM_ENS";
        else
            fallbackMessage=fallbackMessage+ ...
                " | STRICT_ZERO_ENS_INFEASIBLE; RELAXED_TO_MINIMUM_ENS";
        end
    else
        rethrow(ME)
    end
end
end

function [result,used,h2IncreaseMWh,curtailmentReductionMWh, ...
    triggerMW]=maybe_surplus_redispatch(primary,in,cfg,strategy,t)
result=primary;
used=false;
h2IncreaseMWh=NaN;
curtailmentReductionMWh=NaN;
triggerMW=primary.dispatch.pCurtailmentMW(1);
if ~strategy.surplusRedispatchEnabled || ...
        triggerMW<strategy.surplusRedispatchMinCurtailmentMW || ...
        in.availability.electrolyzer<=0 || ...
        cfg.hydrogen.electrolyzerRatedMW<=0
    return
end

primaryDispatch=primary.dispatch;
primaryCurtailment=primary.kpi.eCurtailmentMWh;
redispatchIn=in;
redispatchIn.productMix=struct('enabled',false);
redispatchCfg=cfg;
redispatchCfg.objective.primary='curtailmentMWh';
redispatchCfg.objective.tieBreak='none';
redispatchCfg.objective.temporalTieBreak='none';
redispatchCfg.meta.parameterVersion=sprintf( ...
    '%s_h%04d_surplus_bess',strategy.id,t);

% Pass 1: use only otherwise-unused BESS charging headroom. All
% already-committed service remains anchored to the primary schedule.
redispatchIn.redispatch=redispatch_anchor(primaryDispatch,false);
redispatchIn.redispatch.pBessChargeMaxMW= ...
    cfg.bess.chargeMaxMW*double(in.availability.bess>0);
try
    bessPass=run_hour_kernel(redispatchIn,redispatchCfg);
catch
    return
end
if bessPass.meta.exitflag<=0 || ~bessPass.audit.pass
    return
end

candidate=bessPass;
if bessPass.dispatch.pCurtailmentMW(1)>1e-8
    % Pass 2: keep the BESS result fixed and expose only the residual
    % curtailment to PEM. This is a same-hour causal correction, not
    % hindsight re-optimization of the full schedule.
    redispatchCfg.meta.parameterVersion=sprintf( ...
        '%s_h%04d_surplus_pem',strategy.id,t);
    redispatchIn.redispatch=redispatch_anchor( ...
        bessPass.dispatch,true);
    try
        pemPass=run_hour_kernel(redispatchIn,redispatchCfg);
    catch
        pemPass=[];
    end
    if ~isempty(pemPass) && pemPass.meta.exitflag>0 && ...
            pemPass.audit.pass && ...
            pemPass.kpi.eCurtailmentMWh<= ...
                bessPass.kpi.eCurtailmentMWh+1e-8
        candidate=pemPass;
    end
end

curtailmentReductionMWh=max(0, ...
    primaryCurtailment-candidate.kpi.eCurtailmentMWh);
h2IncreaseMWh=max(0, ...
    candidate.kpi.eHydrogenInputMWh-primary.kpi.eHydrogenInputMWh);
used=curtailmentReductionMWh>1e-8 || h2IncreaseMWh>1e-8;
if used
    result=candidate;
    result.meta.surplusRedispatchUsed=true;
    result.meta.surplusRedispatchTriggerMW=triggerMW;
    result.meta.surplusRedispatchHydrogenMWh=h2IncreaseMWh;
    result.meta.surplusRedispatchCurtailmentReductionMWh= ...
        curtailmentReductionMWh;
else
    result=primary;
    h2IncreaseMWh=0;
    curtailmentReductionMWh=0;
end
end

function r=redispatch_anchor(d,allowAdditionalElectrolyzer)
r=struct( ...
    'enabled',true, ...
    'pBessChargeMinMW',d.pBessChargeMW, ...
    'pBessChargeMaxMW',d.pBessChargeMW, ...
    'pBessDischargeMinMW',d.pBessDischargeMW, ...
    'pBessDischargeMaxMW',d.pBessDischargeMW, ...
    'pElectrolyzerMinMW',d.pElectrolyzerMW, ...
    'pH2PowerMinMW',d.pH2PowerMW, ...
    'pH2PowerMaxMW',d.pH2PowerMW, ...
    'pComputeBaseServedMinMW',d.pComputeBaseServedMW, ...
    'pComputeBaseServedMaxMW',d.pComputeBaseServedMW, ...
    'pComputeFlexibleMinMW',d.pComputeFlexibleMW, ...
    'pComputeFlexibleMaxMW',d.pComputeFlexibleMW, ...
    'pCableSendMinMW',d.pCableSendMW, ...
    'pCableSendMaxMW',d.pCableSendMW, ...
    'pMarineServedMinMW',d.pMarineServedMW, ...
    'pMarineServedMaxMW',d.pMarineServedMW, ...
    'pMarineUnservedMaxMW',d.pMarineUnservedMW, ...
    'pInternalUnservedMaxMW',d.pInternalUnservedMW, ...
    'pComputeBaseUnservedMaxMW',d.pComputeBaseUnservedMW, ...
    'h2PipeWithdrawnMinKg',d.h2PipeWithdrawnKg, ...
    'h2PipeWithdrawnMaxKg',d.h2PipeWithdrawnKg, ...
    'h2ShipWithdrawnMinKg',d.h2ShipWithdrawnKg, ...
    'h2ShipWithdrawnMaxKg',d.h2ShipWithdrawnKg, ...
    'pCurtailmentMaxMW',d.pCurtailmentMW);
if ~allowAdditionalElectrolyzer
    r.pElectrolyzerMaxMW=d.pElectrolyzerMW;
end
end

function [cfgOut,active]=apply_bess_reserve_target(cfg,eventDecision)
cfgOut=cfg;
targetSOC=eventDecision.bessReserveTargetSOC;
targetH2=eventDecision.h2ReserveTargetKg;
active=isfinite(targetSOC) || isfinite(targetH2);
if isfinite(targetSOC)
    cfgOut.bess.terminalRule='target';
    cfgOut.bess.terminalTargetSOC=max(cfg.bess.socMin,targetSOC);
else
    cfgOut.bess.terminalRule='none';
end
if isfinite(targetH2)
    cfgOut.hydrogen.terminalRule='target';
    cfgOut.hydrogen.terminalTargetKg=max(0,targetH2);
else
    cfgOut.hydrogen.terminalRule='none';
end
end

function value=append_status(value,addition)
if strlength(value)==0
    value=addition;
else
    value=value+" | "+addition;
end
end

function result=run_strict_reliability_attempt(in,cfg,strategy,t)
cfgStrict=cfg;
if cfgStrict.objective.maxENSMWh<=1e-12
    cfgStrict.solver.maxTimeS=min(cfgStrict.solver.maxTimeS, ...
        strategy.strictReliabilityMaxTimeS);
end
result=run_hour_kernel(in,cfgStrict);
if result.meta.exitflag<=0
    error('C5:StrictReliabilityNotProven', ...
        ['Strict zero-ENS solve did not prove optimality at hour %d; ', ...
         'continue with minimum-ENS hierarchy.'],t);
end
end

function [result,minFeasibleENS]=run_reliability_relaxation( ...
    in,cfg,t,strategy)
% Epsilon-constraint hierarchy: minimize ENS, then optimize economics
% without degrading minimum ENS beyond numerical tolerance. Method source:
% Mavrotas (2009), Applied Mathematics and Computation 213(2):455-465.
cfgEns=cfg;
cfgEns.objective.primary='ensMWh';
cfgEns.objective.maxENSMWh=Inf;
cfgEns.objective.tieBreak='none';
cfgEns.meta.parameterVersion=sprintf('%s_h%04d_min_ens',strategy.id,t);
ensResult=run_hour_kernel(in,cfgEns);
minFeasibleENS=max(0,ensResult.kpi.ensMWh);

cfgEconomic=cfg;
cfgEconomic.objective.primary='economicNetCostCNY';
cfgEconomic.objective.maxENSMWh=minFeasibleENS+ ...
    cfg.objective.primaryRelativeTolerance*(1+minFeasibleENS);
cfgEconomic.objective.tieBreak='none';
cfgEconomic.meta.parameterVersion=sprintf( ...
    '%s_h%04d_min_ens_then_economic',strategy.id,t);
result=run_hour_kernel(in,cfgEconomic);
end

function result=run_hour_kernel(in,cfg)
% C5 annual loops call the frozen V5 validation/solve kernel directly.
% Rebuilding the foundation registry and bus cross-check for every single
% hour is redundant; the standalone foundation gate is run separately.
in=v5_validate_and_normalize_input(cfg,in);
result=v5_solve_dispatch(cfg,in);
result.config=cfg;
result.input=in;
end

function in=apply_asset_switches(in,strategy)
in.availability.cable=in.availability.cable*strategy.electricityEnabled;
in.availability.electrolyzer= ...
    in.availability.electrolyzer*strategy.hydrogenEnabled;
in.availability.h2Storage= ...
    in.availability.h2Storage*strategy.hydrogenEnabled;
in.availability.h2Pipe=in.availability.h2Pipe*strategy.hydrogenEnabled;
in.availability.h2Ship=in.availability.h2Ship*strategy.hydrogenEnabled;
in.availability.h2Power=in.availability.h2Power*strategy.hydrogenEnabled;
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
    in.initial.h2PowerMW=0;
end
end

function [in,decision]=apply_event_rule(in,eventCode,strategy,cfg)
decision=event_decision_defaults();
if ~strategy.eventReserveRule, return; end
event=upper(char(eventCode));
switch event
    case {'LOW_RESOURCE_WATCH','WATCH'}
        decision.eventRiskLevel=1;
        decision.riskQuantile=0.30;
    case 'TYPHOON_WARNING'
        decision.eventRiskLevel=2;
        decision.riskQuantile=0.10;
        decision.bessReserveTargetSOC=strategy.warningBessReserveTargetSOC;
        decision.h2ReserveTargetKg=strategy.warningH2ReserveTargetKg;
        decision.enforceReserveTarget=true;
        % Warning is known at the current interval. Suspend optional product
        % conversion/export so current renewable can restore BESS reserve.
        % Hydrogen remains a nonnegative flexible inventory with no target
        % lower bound.
        in.cableSendLimitMW=0;
        in.pComputeFlexibleMaxMW=0;
        in.availability.electrolyzer=0;
        in.availability.h2Pipe=0;
        in.availability.h2Ship=0;
    case 'TYPHOON_PASSAGE'
        decision.eventRiskLevel=3;
        decision.riskQuantile=0.05;
        decision.bessReserveTargetSOC=cfg.bess.socMin;
        decision.h2ReserveTargetKg=0;
        decision.enforceReserveTarget=true;
        in.cableSendLimitMW=0;
        in.pComputeFlexibleMaxMW=0;
        in.availability.electrolyzer=0;
        in.availability.h2Pipe=0;
        in.availability.h2Ship=0;
        in.availability.compute=0;
    case 'TYPHOON_RECOVERY'
        decision.eventRiskLevel=1;
        decision.riskQuantile=0.20;
        decision.bessReserveTargetSOC=strategy.recoveryBessReserveTargetSOC;
        decision.h2ReserveTargetKg=strategy.recoveryH2ReserveTargetKg;
        if strategy.robustEventReserveRule && reserve_below_target(in,cfg,decision)
            decision.enforceReserveTarget=true;
            f=strategy.recoveryOptionalLimitFactor;
            in.cableSendLimitMW=in.cableSendLimitMW*f;
            in.pComputeFlexibleMaxMW=in.pComputeFlexibleMaxMW*f;
            in.availability.electrolyzer=in.availability.electrolyzer*f;
            decision.reserveMode="RECOVERY_THROTTLE_OPTIONAL_PRODUCTS";
        end
    otherwise
        % Normal operation also protects a causal working reserve. When the
        % inherited SOC is below target, optional products are throttled so
        % contemporaneous renewable surplus can restore the BESS. The
        % target itself is applied as a relaxable terminal constraint by
        % run_actual_dispatch; it can never take priority over current ENS.
        if strategy.normalStateFloorRule
            decision.bessReserveTargetSOC= ...
                strategy.normalBessReserveTargetSOC;
            decision.h2ReserveTargetKg= ...
                strategy.normalH2ReserveTargetKg;
            decision.enforceReserveTarget=true;
            decision.normalStateFloorEnforced=true;
            if reserve_below_target(in,cfg,decision)
                f=strategy.normalLowReserveOptionalLimitFactor;
                in.cableSendLimitMW=in.cableSendLimitMW*f;
                in.pComputeFlexibleMaxMW=in.pComputeFlexibleMaxMW*f;
                in.availability.electrolyzer= ...
                    in.availability.electrolyzer*f;
                decision.reserveMode= ...
                    "NORMAL_RESTORE_RESERVE_THROTTLE_OPTIONAL_PRODUCTS";
            end
        end
end
end

function decision=event_decision_defaults()
decision=struct( ...
    'eventRiskLevel',0, ...
    'riskQuantile',0.50, ...
    'bessReserveTargetSOC',NaN, ...
    'h2ReserveTargetKg',NaN, ...
    'enforceReserveTarget',false, ...
    'normalStateFloorEnforced',false, ...
    'reserveMode',"NONE");
end

function tf=reserve_below_target(in,cfg,decision)
tf=false;
if isfinite(decision.bessReserveTargetSOC)
    tf=tf || in.initial.bessEnergyMWh< ...
        decision.bessReserveTargetSOC*cfg.bess.energyMWh-1e-9;
end
if isfinite(decision.h2ReserveTargetKg) && ...
        isfield(in.initial,'h2InventoryKg')
    tf=tf || in.initial.h2InventoryKg< ...
        decision.h2ReserveTargetKg-1e-9;
end
end

function [bessShortfall,h2Shortfall]=reserve_shortfall(result,cfg,decision)
d=result.dispatch;
if isfinite(decision.bessReserveTargetSOC)
    bessShortfall=max(0, ...
        decision.bessReserveTargetSOC*cfg.bess.energyMWh- ...
        d.bessEnergyMWh(end));
else
    bessShortfall=NaN;
end
if isfinite(decision.h2ReserveTargetKg)
    h2Shortfall=max(0, ...
        decision.h2ReserveTargetKg-d.h2InventoryKg(end));
else
    h2Shortfall=NaN;
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

function in=slice_window(base,t,windowH,state)
in=struct;
names=fieldnames(base);
N=numel(base.timeH);
idx=t:(t+windowH-1);
for k=1:numel(names)
    name=names{k};
    if any(strcmp(name,{'availability','initial'})), continue; end
    value=base.(name);
    if (isnumeric(value)||islogical(value)) && isvector(value) && ...
            numel(value)==N
        value=value(idx);
    end
    in.(name)=value;
end
in.timeH=base.timeH(idx);
in.availability=struct;
names=fieldnames(base.availability);
for k=1:numel(names)
    value=base.availability.(names{k});
    if ~isscalar(value), value=value(idx); end
    in.availability.(names{k})=value;
end
in.initial=state;
end

function in=apply_event_rule_window(in,eventWindow,strategy,cfg)
W=numel(in.timeH);
eventWindow=string(eventWindow(:));
if ~isfield(in,'cableSendLimitMW')
    in.cableSendLimitMW=cfg.output.cableSendCapacityMW;
end
if ~isfield(in,'pComputeFlexibleMaxMW')
    in.pComputeFlexibleMaxMW=0;
end
in.availability=ensure_availability_default( ...
    in.availability,'electrolyzer',1);
in.availability=ensure_availability_default(in.availability,'h2Pipe',1);
in.availability=ensure_availability_default(in.availability,'h2Ship',1);
in.availability=ensure_availability_default(in.availability,'compute',1);
in=ensure_input_series(in,'cableSendLimitMW',W);
in=ensure_input_series(in,'pComputeFlexibleMaxMW',W);
in.availability=ensure_availability_series( ...
    in.availability,'electrolyzer',W);
in.availability=ensure_availability_series(in.availability,'h2Pipe',W);
in.availability=ensure_availability_series(in.availability,'h2Ship',W);
in.availability=ensure_availability_series(in.availability,'compute',W);

normalDecision=event_decision_defaults();
normalDecision.bessReserveTargetSOC=strategy.normalBessReserveTargetSOC;
normalDecision.h2ReserveTargetKg=strategy.normalH2ReserveTargetKg;
normalReserveBelow=strategy.normalStateFloorRule && ...
    reserve_below_target(in,cfg,normalDecision);
recoveryDecision=event_decision_defaults();
recoveryDecision.bessReserveTargetSOC=strategy.recoveryBessReserveTargetSOC;
recoveryDecision.h2ReserveTargetKg=strategy.recoveryH2ReserveTargetKg;
recoveryReserveBelow=strategy.robustEventReserveRule && ...
    reserve_below_target(in,cfg,recoveryDecision);

for j=1:W
    switch upper(char(eventWindow(j)))
        case 'TYPHOON_WARNING'
            in.cableSendLimitMW(j)=0;
            in.pComputeFlexibleMaxMW(j)=0;
            in.availability.electrolyzer(j)=0;
            in.availability.h2Pipe(j)=0;
            in.availability.h2Ship(j)=0;
        case 'TYPHOON_PASSAGE'
            in.cableSendLimitMW(j)=0;
            in.pComputeFlexibleMaxMW(j)=0;
            in.availability.electrolyzer(j)=0;
            in.availability.h2Pipe(j)=0;
            in.availability.h2Ship(j)=0;
            in.availability.compute(j)=0;
        case 'TYPHOON_RECOVERY'
            if recoveryReserveBelow
                f=strategy.recoveryOptionalLimitFactor;
                in.cableSendLimitMW(j)=in.cableSendLimitMW(j)*f;
                in.pComputeFlexibleMaxMW(j)= ...
                    in.pComputeFlexibleMaxMW(j)*f;
                in.availability.electrolyzer(j)= ...
                    in.availability.electrolyzer(j)*f;
            end
        otherwise
            if normalReserveBelow
                f=strategy.normalLowReserveOptionalLimitFactor;
                in.cableSendLimitMW(j)=in.cableSendLimitMW(j)*f;
                in.pComputeFlexibleMaxMW(j)= ...
                    in.pComputeFlexibleMaxMW(j)*f;
                in.availability.electrolyzer(j)= ...
                    in.availability.electrolyzer(j)*f;
            end
    end
end
end

function availability=ensure_availability_default( ...
    availability,name,defaultValue)
if ~isfield(availability,name)
    availability.(name)=defaultValue;
end
end

function in=ensure_input_series(in,name,W)
if ~isfield(in,name), return; end
value=double(in.(name)(:));
if isscalar(value)
    value=repmat(value,W,1);
end
assert(numel(value)==W, ...
    'Planning-window field %s must be scalar or W-by-1.',name);
in.(name)=value;
end

function availability=ensure_availability_series(availability,name,W)
if ~isfield(availability,name), return; end
value=double(availability.(name)(:));
if isscalar(value)
    value=repmat(value,W,1);
end
assert(numel(value)==W, ...
    'Planning-window availability.%s must be scalar or W-by-1.',name);
availability.(name)=value;
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

function tf=is_plan_forecast(strategy)
tf=strategy.forecastMode=="PREVIOUS_HOUR_PERSISTENCE" || ...
    strategy.forecastMode=="KALMAN_PRIOR_POSTERIOR";
end

function value=previous_hour_planning_available(base,cfg,strategy,t)
if t>1
    value=double(base.pSourceAvailableMW(t-1));
else
    value=strategy.initialPlanningCapacityFactor*cfg.source.installedMW;
end
end

function value=previous_hour_source_aux(base,t)
if isfield(base,'pSourceAuxMW') && t>1
    value=double(base.pSourceAuxMW(t-1));
else
    value=0;
end
end

function status=dispatch_run_status(result,planFallbackUsed, ...
    relaxedConstraintUsed)
if ~result.audit.pass
    status="FAIL_AUDIT";
elseif result.meta.exitflag<=0
    status="FEASIBLE_NOT_PROVEN";
elseif planFallbackUsed || relaxedConstraintUsed
    status="PASS_RELAXED";
else
    status="PASS_STRICT";
end
end

function status=summarize_run_status(hourStatus)
hourStatus=string(hourStatus(:));
if any(startsWith(hourStatus,"FAIL"))
    status="FAIL";
elseif any(hourStatus=="FEASIBLE_NOT_PROVEN")
    status="FEASIBLE_NOT_PROVEN";
elseif any(hourStatus=="PASS_RELAXED")
    status="PASS_RELAXED";
elseif all(hourStatus=="PASS_STRICT")
    status="PASS_STRICT";
else
    status="UNKNOWN";
end
end

function status=main_conclusion_status(runStatus)
runStatus=string(runStatus);
if runStatus=="PASS_STRICT"
    status="MAIN_CONCLUSION_ELIGIBLE";
elseif runStatus=="PASS_RELAXED"
    status="EXCLUDED_RELAXED_FALLBACK";
elseif runStatus=="FEASIBLE_NOT_PROVEN"
    status="EXCLUDED_NOT_PROVEN_OPTIMAL";
elseif startsWith(runStatus,"FAIL")
    status="EXCLUDED_FAILED";
else
    status="EXCLUDED_UNKNOWN_STATUS";
end
end

function q=event_quantile(eventCode)
switch upper(char(eventCode))
    case {'LOW_RESOURCE_WATCH','WATCH'}
        q=0.30;
    case 'TYPHOON_WARNING'
        q=0.10;
    case 'TYPHOON_PASSAGE'
        q=0.05;
    case 'TYPHOON_RECOVERY'
        q=0.20;
    otherwise
        q=0.50;
end
end

function boundary=information_boundary(strategy)
windowText=sprintf('%dH_ROLLING_FIRST_HOUR_EXECUTION', ...
    strategy.planningWindowH);
switch strategy.forecastMode
    case "CURRENT_OBSERVATION"
        boundary="CAUSAL_CURRENT_OBSERVATION_PLUS_PREVIOUS_TERMINAL_STATE";
    case "PREVIOUS_HOUR_PERSISTENCE"
        boundary="CAUSAL_PREVIOUS_HOUR_GENERATION_PLUS_PREVIOUS_TERMINAL_STATE";
    case "KALMAN_PRIOR_POSTERIOR"
        boundary="CAUSAL_KALMAN_PRIOR_POSTERIOR_PREVIOUS_OBSERVATION_AND_EVENT_STATE";
    otherwise
        boundary="UNKNOWN";
end
boundary=boundary+"; "+windowText;
end

function hourlyLedger=append_optional_source_columns(hourlyLedger,base,N)
fields=["pWindAvailableMW","pPVAvailableMW","pTidalAvailableMW"];
for k=1:numel(fields)
    name=fields(k);
    if isfield(base,name)
        value=double(base.(name));
        if isscalar(value), value=repmat(value,N,1); end
        if numel(value)==N
            hourlyLedger.(char(name))=value(:);
        end
    end
end
end

function value=field_or(s,name,defaultValue)
if isfield(s,name), value=s.(name); else, value=defaultValue; end
end
