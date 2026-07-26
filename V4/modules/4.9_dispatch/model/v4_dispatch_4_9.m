function [packet,dispatch]=v4_dispatch_4_9(cfg,p43Boundary,p46Boundary,options,p45Boundary)
%V4_DISPATCH_4_9 Deterministic feasible-rule coordinator for V4.
%
% 4.9 owns cross-module allocation, while 4.5 owns storage physics. The
% coordinator therefore consumes the explicit 4.5 BOUNDARY state and
% applies the same published limits; it must not reset SOC/H2 to cfg values
% inside rolling runs.
%
% This remains a deterministic feasible rule, not a Pareto optimizer.

if nargin<4 || isempty(options), options=struct; end
assert(nargin>=5 && ~isempty(p45Boundary), ...
    '4.9 requires an explicit 4.5 BOUNDARY packet; implicit cfg reset is forbidden.');
timeH=p43Boundary.axis.timeH(:); N=numel(timeH); dt=cfg.time.dispatchStepH;
assert(strcmp(p46Boundary.meta.phase,'BOUNDARY'), ...
    '4.6 must publish BOUNDARY before 4.9.');
assert(strcmp(p45Boundary.meta.moduleId,'4.5') && ...
    strcmp(p45Boundary.meta.phase,'BOUNDARY'), ...
    '4.5 must publish BOUNDARY before 4.9.');
assert(numel(p46Boundary.axis.timeH)==N && ...
    all(abs(p46Boundary.axis.timeH(:)-timeH)<1e-12), ...
    '4.3 and 4.6 time axes must match.');
assert(numel(p45Boundary.axis.timeH)==N && ...
    all(abs(p45Boundary.axis.timeH(:)-timeH)<1e-12), ...
    '4.3 and 4.5 time axes must match.');

state0=struct( ...
    'bessEnergyMWh',double(p45Boundary.state.bessEnergyMWh(1)), ...
    'h2InventoryKg',double(p45Boundary.state.h2InventoryKg(1)));
reservePowerMW=first_or_default(p45Boundary.state, ...
    'gfmReservePowerMW',NaN);
reserveEnergyMWh=first_or_default(p45Boundary.state, ...
    'gfmReserveEnergyMWh',NaN);
assert(isfinite(reservePowerMW) && isfinite(reserveEnergyMWh), ...
    '4.5 BOUNDARY must publish finite GFM power and energy reserves.');
bessRule=string(first_or_default(p45Boundary.service, ...
    'bessTerminalRule',""));
h2Rule=string(first_or_default(p45Boundary.service, ...
    'h2TerminalRule',""));
bessTerminalTargetMWh=first_or_default(p45Boundary.service, ...
    'bessTerminalTargetMWh',NaN);
h2TerminalTargetKg=first_or_default(p45Boundary.service, ...
    'h2TerminalTargetKg',NaN);
bessStandingLossFractionPerH=first_or_default(p45Boundary.service, ...
    'bessStandingLossFractionPerH',NaN);
assert(strlength(bessRule)>0 && strlength(h2Rule)>0 && ...
    all(isfinite([bessTerminalTargetMWh h2TerminalTargetKg ...
    bessStandingLossFractionPerH])), ...
    '4.5 BOUNDARY must publish terminal rules, targets and BESS retention data.');
bessPhysicalFloorMWh=cfg.bess.socMin*cfg.bess.energyMWh+reserveEnergyMWh;
bessDispatchFloorMWh=bessPhysicalFloorMWh;
h2DispatchFloorKg=0;
assert(bessDispatchFloorMWh<=cfg.bess.socMax*cfg.bess.energyMWh+1e-9);
assert(h2DispatchFloorKg<=cfg.hydrogen.storageMaxKg+1e-9);
assert(any(strcmpi(bessRule,{'free','free_with_terminal_value', ...
    'minimum','cyclic'})),'Unsupported BESS terminal rule from 4.5 BOUNDARY.');
assert(any(strcmpi(h2Rule,{'free','free_with_terminal_value', ...
    'minimum','cyclic','cyclic_or_minimum'})), ...
    'Unsupported H2 terminal rule from 4.5 BOUNDARY.');

marineDemand=series_option(options,'marineDemandMW', ...
    cfg.output.marineBaseLoadMW+cfg.output.marineDesalLoadMW+ ...
    cfg.output.marineEquipmentLoadMW,N);
marineRigid=marineDemand*(1-cfg.output.marineFlexibleFraction);
computeDesired=series_option(options,'computeRequestMW',10,N); % [假设值，待企业调研校准]
computeDesired=min(computeDesired,p46Boundary.ports.dcFacility.maxMW);
computeOnlineMin=cfg.compute.facilityMinMW;
positiveCompute=computeDesired>0;
computeDesired(positiveCompute)=max(computeDesired(positiveCompute), ...
    computeOnlineMin);
computeFirm=series_option(options,'computeFirmRequestMW',0,N);
computeFirm=min(computeFirm,computeDesired);
positiveFirm=computeFirm>0;
computeFirm(positiveFirm)=max(computeFirm(positiveFirm),computeOnlineMin);
h2Rate=series_option(options,'h2DeliveryCapKgPerH', ...
    cfg.hydrogen.deliveryDemandKgPerH,N);
h2SalePrice=series_option(options,'h2SalePriceCNYPerKg', ...
    cfg.hydrogen.referenceSalePriceCNYPerKg,N);
h2VariableCost=series_option(options,'h2VariableCostCNYPerKg', ...
    cfg.hydrogen.variableCostCNYPerKg,N);
electricityPrice=series_option(options,'electricityPriceCNYPerMWh', ...
    cfg.economics.referenceElectricityPriceCNYPerMWh,N);
h2ValuePerMWh=1000*(h2SalePrice-h2VariableCost)/ ...
    cfg.hydrogen.secKWhPerKg;
electricityValuePerSendMWh=electricityPrice* ...
    (1-cfg.output.cableLossFraction);

independentCommitment=logical(first_or_default(p45Boundary.service, ...
    'electrolyzerIndependentCommitment',false));
if independentCommitment
    electrolyzerMinimumMW=first_or_default(p45Boundary.service, ...
        'electrolyzerModuleMinimumMW',NaN);
    electrolyzerMode='MODULAR_INDEPENDENT';
else
    electrolyzerMinimumMW=first_or_default(p45Boundary.service, ...
        'electrolyzerAggregateMinimumMW',NaN);
    electrolyzerMode='AGGREGATE_SYNCHRONOUS';
end
assert(isfinite(electrolyzerMinimumMW) && electrolyzerMinimumMW>0, ...
    '4.5 BOUNDARY must publish the active electrolyzer minimum.');
activeExportCapMW=min(cfg.output.cableSendCapacityMW, ...
    cfg.output.gridAcceptMaxMW);
h2ChannelCapKgPerH=cfg.hydrogen.pipeCapacityKgPerH+ ...
    cfg.hydrogen.shipCapacityKgPerH;

marineAllocated=zeros(N,1); computeReq=zeros(N,1);
elyReq=zeros(N,1); chReq=zeros(N,1); disReq=zeros(N,1);
exportReq=zeros(N,1); spill=zeros(N,1);
marineUnserved=zeros(N,1); computeUnserved=zeros(N,1);
computeDeferred=zeros(N,1); energyPlan=zeros(N,1);
commonUnserved=zeros(N,1); h2InventoryPlan=zeros(N,1);
h2DeliveryPlan=zeros(N,1); hydrogenPriority=false(N,1);
h2DeliveryTargetKg=zeros(N,1);
ePrev=state0.bessEnergyMWh; hPrev=state0.h2InventoryKg;
sourceNet=p43Boundary.ports.source.actualMW ...
    -p43Boundary.loss.pSourceAuxLoadMW ...
    -cfg.commonBus.commonAuxMW-cfg.commonBus.postPOILossMW;
retentionBess=(1-bessStandingLossFractionPerH)^dt;
retentionH2=(1-cfg.hydrogen.storageLossFractionPerH)^dt;

for t=1:N
    ePrev=ePrev*retentionBess;
    availableBattery=max(0,ePrev-bessDispatchFloorMWh);
    maxDis=min(max(0,cfg.bess.dischargeMaxMW-reservePowerMW), ...
        availableBattery*cfg.bess.etaDischarge/dt);
    criticalLoad=marineRigid(t)+computeFirm(t);
    disReq(t)=min(maxDis,max(0,criticalLoad-sourceNet(t)));
    if disReq(t)>0
        ePrev=ePrev-disReq(t)*dt/cfg.bess.etaDischarge;
    end
    remaining=sourceNet(t)+disReq(t);
    commonUnserved(t)=max(0,-remaining);
    remaining=max(0,remaining);

    if computeFirm(t)>0 && ...
            remaining>=computeFirm(t)-cfg.commonBus.balanceToleranceMW
        computeReq(t)=computeFirm(t);
        remaining=max(0,remaining-computeReq(t));
    end
    rigidServed=min(marineRigid(t),remaining);
    remaining=remaining-rigidServed;
    flexibleDemand=marineDemand(t)-marineRigid(t);
    flexibleServed=min(flexibleDemand,remaining);
    remaining=remaining-flexibleServed;
    marineAllocated(t)=rigidServed+flexibleServed;
    marineUnserved(t)=marineDemand(t)-marineAllocated(t);

    room=max(0,cfg.bess.socMax*cfg.bess.energyMWh-ePrev);
    if disReq(t)<=cfg.commonBus.balanceToleranceMW
        chReq(t)=min([remaining,cfg.bess.chargeMaxMW, ...
            room/(cfg.bess.etaCharge*dt)]);
    end
    ePrev=ePrev+cfg.bess.etaCharge*chReq(t)*dt;
    remaining=remaining-chReq(t);

    computeExtraCap=max(0,computeDesired(t)-computeReq(t));
    minimumStart=max(0,computeOnlineMin-computeReq(t));
    if computeExtraCap>0 && ...
            remaining>=minimumStart-cfg.commonBus.balanceToleranceMW
        computeExtra=min(computeExtraCap,remaining);
        if computeReq(t)+computeExtra>= ...
                computeOnlineMin-cfg.commonBus.balanceToleranceMW
            computeReq(t)=computeReq(t)+computeExtra;
            remaining=remaining-computeExtra;
        end
    end
    computeUnserved(t)=max(0,computeFirm(t)-computeReq(t));
    computeDeferred(t)=max(0,computeDesired(t)-computeReq(t));

    hPrev=hPrev*retentionH2;
    deliveryTargetKg=min(h2Rate(t),h2ChannelCapKgPerH)*dt;
    h2DeliveryTargetKg(t)=deliveryTargetKg;
    productionRoomKg=max(0,cfg.hydrogen.storageMaxKg-hPrev ...
        +deliveryTargetKg);
    tankPowerCap=productionRoomKg*cfg.hydrogen.secKWhPerKg/(1000*dt);
    makeUpKg=max(0,deliveryTargetKg+h2DispatchFloorKg-hPrev);
    makeUpMW=makeUpKg*cfg.hydrogen.secKWhPerKg/(1000*dt);
    if makeUpMW>0 && remaining>=electrolyzerMinimumMW
        requiredMW=max(electrolyzerMinimumMW,makeUpMW);
        elyReq(t)=min([requiredMW,cfg.hydrogen.electrolyzerRatedMW, ...
            tankPowerCap,remaining]);
        elyReq(t)=project_electrolyzer_power( ...
            elyReq(t),electrolyzerMinimumMW);
        remaining=remaining-elyReq(t);
    end

    hydrogenPriority(t)=h2ValuePerMWh(t)>= ...
        electricityValuePerSendMWh(t);
    if hydrogenPriority(t)
        [elyReq(t),remaining]=add_electrolyzer_load( ...
            elyReq(t),remaining,tankPowerCap, ...
            cfg.hydrogen.electrolyzerRatedMW,electrolyzerMinimumMW);
        exportReq(t)=min(remaining,activeExportCapMW);
        remaining=remaining-exportReq(t);
    else
        exportReq(t)=min(remaining,activeExportCapMW);
        remaining=remaining-exportReq(t);
        [elyReq(t),remaining]=add_electrolyzer_load( ...
            elyReq(t),remaining,tankPowerCap, ...
            cfg.hydrogen.electrolyzerRatedMW,electrolyzerMinimumMW);
    end

    producedPlanKg=1000*elyReq(t)*dt/cfg.hydrogen.secKWhPerKg;
    availablePlanKg=hPrev+producedPlanKg;
    deliverableKg=max(0,availablePlanKg-h2DispatchFloorKg);
    h2DeliveryPlan(t)=min(deliveryTargetKg,deliverableKg);
    hPrev=availablePlanKg-h2DeliveryPlan(t);
    assert(hPrev<=cfg.hydrogen.storageMaxKg+1e-6);
    h2InventoryPlan(t)=hPrev;
    spill(t)=max(0,remaining);
    energyPlan(t)=ePrev;
end

[chReq,energyPlan,exportReq,spill,bessTerminalOK]= ...
    enforce_bess_terminal(chReq,disReq,exportReq,spill, ...
    cfg,state0.bessEnergyMWh,bessTerminalTargetMWh, ...
    bessDispatchFloorMWh,bessRule,activeExportCapMW,dt, ...
    bessStandingLossFractionPerH);
[h2DeliveryPlan,h2InventoryPlan,h2TerminalOK]= ...
    enforce_h2_terminal(elyReq,h2DeliveryPlan, ...
    h2DeliveryTargetKg,cfg,state0.h2InventoryKg, ...
    h2TerminalTargetKg,h2Rule,dt);

dispatch=struct;
dispatch.req45=struct( ...
    'bessChargeMW',chReq, ...
    'bessDischargeMW',disReq, ...
    'electrolyzerMW',elyReq);
dispatch.state0=state0;
dispatch.computeRequestedMW=computeReq;
dispatch.computeNominalMW=computeDesired;
dispatch.computeFirmMW=computeFirm;
dispatch.marineRequestedMW=marineDemand;
dispatch.marineAllocatedMW=marineAllocated;
dispatch.exportRequestedMW=exportReq;
dispatch.h2DeliveryCapKgPerH=h2Rate;
dispatch.h2DeliveryCapKg=h2Rate*dt;
dispatch.h2DeliveryPlanKg=h2DeliveryPlan;
dispatch.h2DeliveryTargetKg=h2DeliveryTargetKg;
dispatch.h2DeliveryShortfallKg=max(0,h2DeliveryTargetKg-h2DeliveryPlan);
dispatch.h2InventoryPlanKg=h2InventoryPlan;
dispatch.h2MarginalValueCNYPerMWh=h2ValuePerMWh;
dispatch.electricityMarginalValueAtSendCNYPerMWh= ...
    electricityValuePerSendMWh;
dispatch.hydrogenPriority=hydrogenPriority;
dispatch.spillPlannedMW=spill;
dispatch.marineUnservedPlannedMW=marineUnserved;
dispatch.computeUnservedPlannedMW=computeUnserved;
dispatch.computeDeferredPlannedMW=computeDeferred;
dispatch.commonAuxUnservedPlannedMW=commonUnserved;
dispatch.unservedPlannedMW=marineUnserved+computeUnserved+commonUnserved;
dispatch.bessEnergyPlanMWh=energyPlan;
dispatch.bessStandingLossFractionPerH=bessStandingLossFractionPerH;
dispatch.gfmReservePowerMW=reservePowerMW;
dispatch.gfmReserveEnergyMWh=reserveEnergyMWh;
dispatch.bessTerminalRule=char(bessRule);
dispatch.bessTerminalTargetMWh=bessTerminalTargetMWh;
dispatch.bessTerminalOK=bessTerminalOK;
dispatch.h2TerminalRule=char(h2Rule);
dispatch.h2TerminalTargetKg=h2TerminalTargetKg;
dispatch.h2TerminalOK=h2TerminalOK;
dispatch.electrolyzerCommitmentMode=electrolyzerMode;
dispatch.electrolyzerOperatingMinimumMW=electrolyzerMinimumMW;

packet=common_packet_4_2('4.9',timeH,cfg,'REQUEST');
packet.state.dispatchStatus=repmat("FEASIBLE",N,1);
packet.state.bessEnergyPlanMWh=energyPlan;
packet.state.pSpillPlannedMW=spill;
packet.state.pUnservedPlannedMW=dispatch.unservedPlannedMW;
packet.state.h2InventoryPlanKg=h2InventoryPlan;
packet.state.bessTerminalConstraintOK=repmat(bessTerminalOK,N,1);
packet.state.h2TerminalConstraintOK=repmat(h2TerminalOK,N,1);
packet.service.computeNominalMW=computeDesired;
packet.service.computeRequestedMW=computeReq;
packet.service.computeFirmMW=computeFirm;
packet.service.computeOnlineMinMW=repmat(computeOnlineMin,N,1);
packet.service.computeDeferredPlannedMW=computeDeferred;
packet.service.marineRequestedMW=marineDemand;
packet.service.marineAllocatedMW=marineAllocated;
packet.service.bessChargeRequestedMW=chReq;
packet.service.bessDischargeRequestedMW=disReq;
packet.service.electrolyzerRequestedMW=elyReq;
packet.service.exportRequestedMW=exportReq;
packet.service.gfmReservePowerMW=repmat(reservePowerMW,N,1);
packet.service.gfmReserveEnergyMWh=repmat(reserveEnergyMWh,N,1);
packet.product.h2DeliveryCapKgPerH=h2Rate;
packet.product.h2DeliveryCapKg=dispatch.h2DeliveryCapKg;
packet.product.h2DeliveryPlanKg=h2DeliveryPlan;
packet.service.h2MarginalValueCNYPerMWh=h2ValuePerMWh;
packet.service.electricityMarginalValueAtSendCNYPerMWh= ...
    electricityValuePerSendMWh;
packet.service.hydrogenPriority=hydrogenPriority;
packet.quality.dataSourceType="RULE_BASED_FEASIBLE_DISPATCH";
packet.quality.calibrationVersion="UNCALIBRATED";
packet.audit.schedulerId='FEASIBILITY_RULE_V4_4_9';
packet.audit.coordinationPattern= ...
    '4.3_4.5_4.6_BOUNDARY_REQUEST_RESPONSE_REDISPATCH_COMMIT';
packet.audit.solverClass='DETERMINISTIC_RULE_NO_OPTIMALITY_CLAIM';
packet.audit.stateOrigin='EXPLICIT_4.5_BOUNDARY_NO_CFG_RESET';
packet.audit.preferenceNotice= ...
    'Contract quantities and non-public costs are [假设值，待企业调研校准].';
packet.audit.valueRule= ...
    'CONTRACT_MAKEUP_THEN_COMPARE_H2_NET_VALUE_WITH_DELIVERED_ELECTRICITY_VALUE';
packet.audit.hydrogenPriceSourceType= ...
    '数据网站（上海环境能源交易所绿色氢能价格指数）';
packet.audit.electricityPriceSourceType= ...
    '政府官网（国家能源局2024年度中国电力市场发展报告）';
packet.audit.dynamicValidationStatus= ...
    '4.5_WECC_REGFM_B1_REDUCED_ORDER_PROXY_PASSED; EMT_HIL_NOT_PERFORMED';
packet.audit.computePolicy= ...
    'FLEXIBLE_BY_DEFAULT; only computeFirmRequestMW is electrically must-serve';
packet.audit.electrolyzerCommitmentStatus= ...
    '[假设值，待OEM/BOP确认模块独立启停]';
v4_validate_dispatch_4_9( ...
    packet,dispatch,cfg,p43Boundary,p46Boundary,true);
end

function [ely,remaining]=add_electrolyzer_load( ...
        ely,remaining,tankCap,ratedMW,minimumMW)
additionalCap=min(ratedMW-ely,max(0,tankCap-ely));
if additionalCap<=0, return; end
minimumAdditional=max(0,minimumMW-ely);
if remaining<minimumAdditional-1e-12, return; end
addMW=min(additionalCap,remaining);
candidate=ely+addMW;
candidate=project_electrolyzer_power(candidate,minimumMW);
used=max(0,candidate-ely);
ely=candidate;
remaining=remaining-used;
end

function powerMW=project_electrolyzer_power(powerMW,minimumMW)
if powerMW>0 && powerMW<minimumMW-1e-12, powerMW=0; end
end

function [charge,energy,exportMW,spill,ok]=enforce_bess_terminal( ...
        charge,discharge,exportMW,spill,cfg,initialEnergy,target, ...
        floorEnergy,rule,exportCap,dt,standingLossFractionPerH)
retention=(1-standingLossFractionPerH)^dt;
N=numel(charge);
energy=recompute_bess_energy(initialEnergy,charge,discharge,cfg, ...
    retention,dt);
if any(strcmpi(rule,{'free','free_with_terminal_value'}))
    ok=true;
    return;
end
assert(target>=0 && target<=cfg.bess.socMax*cfg.bess.energyMWh+1e-9);
if strcmpi(rule,'cyclic')
    assert(target>=floorEnergy-1e-9, ...
        'Cyclic BESS target is below the physical SOC/GFM reserve floor.');
end

deficit=max(0,target-energy(end));
for t=N:-1:1
    if deficit<=1e-9, break; end
    if discharge(t)>1e-9, continue; end
    transferablePower=spill(t)+exportMW(t);
    chargeHeadroom=max(0,cfg.bess.chargeMaxMW-charge(t));
    if transferablePower<=1e-12 || chargeHeadroom<=1e-12, continue; end
    coefficients=retention.^((0:N-t)');
    suffixSlack=cfg.bess.socMax*cfg.bess.energyMWh-energy(t:N);
    maxInjectionBySlack=max(0,min(suffixSlack./max(coefficients,eps)));
    terminalCoefficient=coefficients(end);
    injectionForTerminal=deficit/max(terminalCoefficient,eps);
    injectionByPower=cfg.bess.etaCharge*dt* ...
        min(transferablePower,chargeHeadroom);
    addInjection=max(0,min([maxInjectionBySlack, ...
        injectionForTerminal,injectionByPower]));
    if addInjection<=1e-12, continue; end
    addedPower=addInjection/(cfg.bess.etaCharge*dt);
    charge(t)=charge(t)+addedPower;
    energy(t:N)=energy(t:N)+addInjection*coefficients;
    spillUsed=min(spill(t),addedPower);
    spill(t)=spill(t)-spillUsed;
    exportMW(t)=exportMW(t)-(addedPower-spillUsed);
    deficit=max(0,target-energy(end));
end

if strcmpi(rule,'cyclic')
    excess=max(0,energy(end)-target);
    for t=N:-1:1
        if excess<=1e-9, break; end
        if charge(t)<=1e-12, continue; end
        coefficients=retention.^((0:N-t)');
        suffixSlack=energy(t:N)-floorEnergy;
        maxInjectionBySlack=max(0,min( ...
            suffixSlack./max(coefficients,eps)));
        injectionAtT=cfg.bess.etaCharge*charge(t)*dt;
        terminalCoefficient=coefficients(end);
        injectionForTerminal=excess/max(terminalCoefficient,eps);
        removeInjection=max(0,min([injectionAtT, ...
            maxInjectionBySlack,injectionForTerminal]));
        if removeInjection<=1e-12, continue; end
        removedPower=removeInjection/(cfg.bess.etaCharge*dt);
        charge(t)=charge(t)-removedPower;
        energy(t:N)=energy(t:N)-removeInjection*coefficients;
        exportAdded=min(removedPower,max(0,exportCap-exportMW(t)));
        exportMW(t)=exportMW(t)+exportAdded;
        spill(t)=spill(t)+removedPower-exportAdded;
        excess=max(0,energy(end)-target);
    end
end
energy=recompute_bess_energy(initialEnergy,charge,discharge,cfg, ...
    retention,dt);
if strcmpi(rule,'cyclic')
    ok=abs(energy(end)-target)<=1e-7;
else
    ok=energy(end)>=target-1e-7;
end
assert(all(charge>=-1e-9) && all(discharge>=-1e-9));
assert(all(exportMW>=-1e-9) && all(spill>=-1e-9));
end

function energy=recompute_bess_energy(initialEnergy,charge,discharge, ...
        cfg,retention,dt)
N=numel(charge); energy=zeros(N,1); e=initialEnergy;
for t=1:N
    e=e*retention+cfg.bess.etaCharge*charge(t)*dt ...
        -discharge(t)*dt/cfg.bess.etaDischarge;
    energy(t)=e;
end
end

function [delivery,inventory,ok]=enforce_h2_terminal( ...
        electrolyzerMW,delivery,deliveryTarget,cfg, ...
        initialInventory,target,rule,dt)
retention=(1-cfg.hydrogen.storageLossFractionPerH)^dt;
N=numel(delivery);
inventory=recompute_h2_inventory(initialInventory,electrolyzerMW, ...
    delivery,cfg,retention,dt);
if any(strcmpi(rule,{'free','free_with_terminal_value'}))
    ok=true;
    return;
end
assert(target>=0 && target<=cfg.hydrogen.storageMaxKg+1e-9);

deficit=max(0,target-inventory(end));
for t=N:-1:1
    if deficit<=1e-6, break; end
    if delivery(t)<=1e-9, continue; end
    coefficients=retention.^((0:N-t)');
    suffixSlack=cfg.hydrogen.storageMaxKg-inventory(t:N);
    maxAdditionBySlack=max(0,min(suffixSlack./max(coefficients,eps)));
    terminalCoefficient=coefficients(end);
    reduceKg=min([delivery(t),maxAdditionBySlack, ...
        deficit/max(terminalCoefficient,eps)]);
    if reduceKg<=1e-9, continue; end
    delivery(t)=delivery(t)-reduceKg;
    inventory(t:N)=inventory(t:N)+reduceKg*coefficients;
    deficit=max(0,target-inventory(end));
end

if strcmpi(rule,'cyclic')
    excess=max(0,inventory(end)-target);
    for t=N:-1:1
        if excess<=1e-6, break; end
        headroom=max(0,deliveryTarget(t)-delivery(t));
        if headroom<=1e-9, continue; end
        coefficients=retention.^((0:N-t)');
        maxRemovalByInventory=max(0,min( ...
            inventory(t:N)./max(coefficients,eps)));
        terminalCoefficient=coefficients(end);
        addKg=min([headroom,maxRemovalByInventory, ...
            excess/max(terminalCoefficient,eps)]);
        if addKg<=1e-9, continue; end
        delivery(t)=delivery(t)+addKg;
        inventory(t:N)=inventory(t:N)-addKg*coefficients;
        excess=max(0,inventory(end)-target);
    end
end
inventory=recompute_h2_inventory(initialInventory,electrolyzerMW, ...
    delivery,cfg,retention,dt);
if strcmpi(rule,'cyclic')
    ok=abs(inventory(end)-target)<=1e-6;
else
    ok=inventory(end)>=target-1e-6;
end
assert(all(delivery>=-1e-9) && all(delivery<=deliveryTarget+1e-9));
end

function inventory=recompute_h2_inventory(initialInventory, ...
        electrolyzerMW,delivery,cfg,retention,dt)
N=numel(delivery); inventory=zeros(N,1); h=initialInventory;
for t=1:N
    h=h*retention+1000*electrolyzerMW(t)*dt/ ...
        cfg.hydrogen.secKWhPerKg-delivery(t);
    inventory(t)=h;
end
end

function x=series_option(options,name,defaultValue,N)
if isfield(options,name), x=options.(name); else, x=defaultValue; end
if isscalar(x), x=repmat(double(x),N,1); else, x=double(x(:)); end
assert(numel(x)==N && all(isfinite(x)) && all(x>=0), ...
    '4.9 option %s must be nonnegative scalar or N-by-1.',name);
end

function value=first_or_default(s,name,defaultValue)
if isfield(s,name)
    x=s.(name);
    if isstring(x) || ischar(x)
        sx=string(x);
        value=sx(1);
    else
        value=double(x(1));
    end
else
    if isstring(defaultValue) || ischar(defaultValue)
        value=string(defaultValue);
    else
        value=double(defaultValue);
    end
end
end
