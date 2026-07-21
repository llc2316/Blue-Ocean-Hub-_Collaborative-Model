function [packet,dispatch]=v4_dispatch_4_9(cfg,p43Boundary,p46Boundary,options)
%V4_DISPATCH_4_9 Cross-module feasibility dispatch for the V4 smoke case.
% This is a deterministic feasible-rule coordinator, not a Pareto optimizer.
% Numerical preferences are [假设值，待企业调研校准].

if nargin<4 || isempty(options), options=struct; end
timeH=p43Boundary.axis.timeH(:); N=numel(timeH); dt=cfg.time.dispatchStepH;
assert(strcmp(p46Boundary.meta.phase,'BOUNDARY'),'4.6 must publish BOUNDARY before 4.9.');
assert(numel(p46Boundary.axis.timeH)==N && ...
    all(abs(p46Boundary.axis.timeH(:)-timeH)<1e-12), ...
    '4.3 and 4.6 time axes must match.');

marineDemand=series_option(options,'marineDemandMW', ...
    cfg.output.marineBaseLoadMW+cfg.output.marineDesalLoadMW+ ...
    cfg.output.marineEquipmentLoadMW,N);
marineRigid=marineDemand*(1-cfg.output.marineFlexibleFraction);
computeDesired=series_option(options,'computeRequestMW',10,N); % [假设值，待企业调研校准]
computeDesired=min(computeDesired,p46Boundary.ports.dcFacility.maxMW);
computeDesired=max(computeDesired,cfg.compute.facilityMinMW);
h2Rate=series_option(options,'h2DeliveryCapKgPerH',1000,N); % [假设值，待企业调研校准]

marineAllocated=zeros(N,1); computeReq=zeros(N,1);
elyReq=zeros(N,1); chReq=zeros(N,1); disReq=zeros(N,1);
exportReq=zeros(N,1); spill=zeros(N,1);
marineUnserved=zeros(N,1); computeUnserved=zeros(N,1); energyPlan=zeros(N,1);
ePrev=cfg.bess.socInitial*cfg.bess.energyMWh;
sourceNet=p43Boundary.ports.source.actualMW-p43Boundary.loss.pSourceAuxLoadMW ...
    -cfg.commonBus.commonAuxMW-cfg.commonBus.postPOILossMW;

for t=1:N
    availableBattery=max(0,ePrev-cfg.bess.socMin*cfg.bess.energyMWh);
    maxDis=min(cfg.bess.dischargeMaxMW,availableBattery*cfg.bess.etaDischarge/dt);
    desiredLoad=marineDemand(t)+computeDesired(t);
    disReq(t)=min(maxDis,max(0,desiredLoad-sourceNet(t)));
    if disReq(t)>0
        ePrev=ePrev-disReq(t)*dt/cfg.bess.etaDischarge;
    end
    remaining=sourceNet(t)+disReq(t);
    assert(remaining>=-cfg.commonBus.balanceToleranceMW, ...
        'Source and battery cannot cover fixed common auxiliary demand at t=%d.',t);
    remaining=max(0,remaining);

    assert(remaining>=computeDesired(t)-cfg.commonBus.balanceToleranceMW, ...
        'Source and battery cannot support the online compute minimum at t=%d.',t);
    computeReq(t)=computeDesired(t); remaining=max(0,remaining-computeReq(t));
    rigidServed=min(marineRigid(t),remaining); remaining=remaining-rigidServed;
    flexibleDemand=marineDemand(t)-marineRigid(t);
    flexibleServed=min(flexibleDemand,remaining); remaining=remaining-flexibleServed;
    marineAllocated(t)=rigidServed+flexibleServed;
    marineUnserved(t)=marineDemand(t)-marineAllocated(t);
    computeUnserved(t)=computeDesired(t)-computeReq(t);

    if remaining>=cfg.hydrogen.electrolyzerMinMW
        elyReq(t)=min(cfg.hydrogen.electrolyzerMinMW,remaining);
        remaining=remaining-elyReq(t);
    end
    room=max(0,cfg.bess.socMax*cfg.bess.energyMWh-ePrev);
    chReq(t)=min([remaining,cfg.bess.chargeMaxMW,room/(cfg.bess.etaCharge*dt)]);
    ePrev=ePrev+cfg.bess.etaCharge*chReq(t)*dt;
    remaining=remaining-chReq(t);
    exportReq(t)=min([remaining,cfg.output.cableSendCapacityMW,cfg.output.gridAcceptMaxMW]);
    remaining=remaining-exportReq(t);
    spill(t)=max(0,remaining);
    energyPlan(t)=ePrev;
end

dispatch=struct;
dispatch.req45=struct('bessChargeMW',chReq,'bessDischargeMW',disReq, ...
    'electrolyzerMW',elyReq);
dispatch.computeRequestedMW=computeReq;
dispatch.computeNominalMW=computeDesired;
dispatch.marineRequestedMW=marineDemand;
dispatch.marineAllocatedMW=marineAllocated;
dispatch.exportRequestedMW=exportReq;
dispatch.h2DeliveryCapKgPerH=h2Rate;
dispatch.h2DeliveryCapKg=h2Rate*dt;
dispatch.spillPlannedMW=spill;
dispatch.marineUnservedPlannedMW=marineUnserved;
dispatch.computeUnservedPlannedMW=computeUnserved;
dispatch.unservedPlannedMW=marineUnserved+computeUnserved;
dispatch.bessEnergyPlanMWh=energyPlan;

packet=common_packet_4_2('4.9',timeH,cfg,'REQUEST');
packet.state.dispatchStatus=repmat("FEASIBLE",N,1);
packet.state.bessEnergyPlanMWh=energyPlan;
packet.state.pSpillPlannedMW=spill;
packet.state.pUnservedPlannedMW=dispatch.unservedPlannedMW;
packet.service.computeNominalMW=computeDesired;
packet.service.computeRequestedMW=computeReq;
packet.service.marineRequestedMW=marineDemand;
packet.service.marineAllocatedMW=marineAllocated;
packet.service.bessChargeRequestedMW=chReq;
packet.service.bessDischargeRequestedMW=disReq;
packet.service.electrolyzerRequestedMW=elyReq;
packet.service.exportRequestedMW=exportReq;
packet.product.h2DeliveryCapKgPerH=h2Rate;
packet.product.h2DeliveryCapKg=dispatch.h2DeliveryCapKg;
packet.quality.dataSourceType="RULE_BASED_INTERFACE_SMOKE";
packet.quality.calibrationVersion="UNCALIBRATED";
packet.audit.schedulerId='FEASIBILITY_RULE_V4_4_9';
packet.audit.solverClass='DETERMINISTIC_RULE_NO_OPTIMALITY_CLAIM';
packet.audit.preferenceNotice='[假设值，待企业调研校准]';
packet.audit.dynamicValidationStatus='NOT_PERFORMED';
v4_validate_dispatch_4_9(packet,dispatch,cfg,p43Boundary,p46Boundary,true);
end

function x=series_option(options,name,defaultValue,N)
if isfield(options,name), x=options.(name); else, x=defaultValue; end
if isscalar(x), x=repmat(double(x),N,1); else, x=double(x(:)); end
assert(numel(x)==N && all(isfinite(x)) && all(x>=0), ...
    '4.9 option %s must be nonnegative scalar or N-by-1.',name);
end
