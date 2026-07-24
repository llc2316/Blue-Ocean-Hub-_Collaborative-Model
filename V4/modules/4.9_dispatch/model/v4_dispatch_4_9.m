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
computeOnlineMin=cfg.compute.facilityMinMW;
computeCritical=min(computeDesired,computeOnlineMin);
h2Rate=series_option(options,'h2DeliveryCapKgPerH',1000,N); % [假设值，待企业调研校准]

marineAllocated=zeros(N,1); computeReq=zeros(N,1);
elyReq=zeros(N,1); chReq=zeros(N,1); disReq=zeros(N,1);
exportReq=zeros(N,1); spill=zeros(N,1);
marineUnserved=zeros(N,1); computeUnserved=zeros(N,1); computeDeferred=zeros(N,1); energyPlan=zeros(N,1);
commonUnserved=zeros(N,1);
ePrev=cfg.bess.socInitial*cfg.bess.energyMWh;
sourceNet=p43Boundary.ports.source.actualMW-p43Boundary.loss.pSourceAuxLoadMW ...
    -cfg.commonBus.commonAuxMW-cfg.commonBus.postPOILossMW;

for t=1:N
    availableBattery=max(0,ePrev-cfg.bess.socMin*cfg.bess.energyMWh);
    maxDis=min(cfg.bess.dischargeMaxMW,availableBattery*cfg.bess.etaDischarge/dt);
    criticalLoad=marineRigid(t)+computeCritical(t);
    disReq(t)=min(maxDis,max(0,criticalLoad-sourceNet(t)));
    if disReq(t)>0
        ePrev=ePrev-disReq(t)*dt/cfg.bess.etaDischarge;
    end
    remaining=sourceNet(t)+disReq(t);
    commonUnserved(t)=max(0,-remaining);
    remaining=max(0,remaining);

    % Online DC is a disjunctive boundary: request either zero or at least
    % its online minimum.  A partial request below the minimum is forbidden.
    if remaining>=computeCritical(t)-cfg.commonBus.balanceToleranceMW
        computeReq(t)=computeCritical(t);
        remaining=max(0,remaining-computeReq(t));
    end
    rigidServed=min(marineRigid(t),remaining); remaining=remaining-rigidServed;
    flexibleDemand=marineDemand(t)-marineRigid(t);
    flexibleServed=min(flexibleDemand,remaining); remaining=remaining-flexibleServed;
    marineAllocated(t)=rigidServed+flexibleServed;
    marineUnserved(t)=marineDemand(t)-marineAllocated(t);

    % After contracted marine demand, first absorb surplus into the battery,
    % then activate flexible compute.
    room=max(0,cfg.bess.socMax*cfg.bess.energyMWh-ePrev);
    if disReq(t)<=cfg.commonBus.balanceToleranceMW
        chReq(t)=min([remaining,cfg.bess.chargeMaxMW,room/(cfg.bess.etaCharge*dt)]);
    end
    ePrev=ePrev+cfg.bess.etaCharge*chReq(t)*dt;
    remaining=remaining-chReq(t);

    computeExtra=min(max(0,computeDesired(t)-computeReq(t)),remaining);
    computeReq(t)=computeReq(t)+computeExtra; remaining=remaining-computeExtra;
    computeUnserved(t)=max(0,computeCritical(t)-computeReq(t));
    computeDeferred(t)=max(0,computeDesired(t)-max(computeCritical(t),computeReq(t)));

    exportReq(t)=min([remaining,cfg.output.cableSendCapacityMW,cfg.output.gridAcceptMaxMW]);
    remaining=remaining-exportReq(t);
    % Electrolyzer is off below minimum, otherwise it uses all residual
    % power up to rated capacity instead of staying at the minimum point.
    if remaining>=cfg.hydrogen.electrolyzerMinMW
        elyReq(t)=min(cfg.hydrogen.electrolyzerRatedMW,remaining);
        remaining=remaining-elyReq(t);
    end
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
dispatch.computeDeferredPlannedMW=computeDeferred;
dispatch.commonAuxUnservedPlannedMW=commonUnserved;
dispatch.unservedPlannedMW=marineUnserved+computeUnserved+commonUnserved;
dispatch.bessEnergyPlanMWh=energyPlan;

packet=common_packet_4_2('4.9',timeH,cfg,'REQUEST');
packet.state.dispatchStatus=repmat("FEASIBLE",N,1);
packet.state.bessEnergyPlanMWh=energyPlan;
packet.state.pSpillPlannedMW=spill;
packet.state.pUnservedPlannedMW=dispatch.unservedPlannedMW;
packet.service.computeNominalMW=computeDesired;
packet.service.computeRequestedMW=computeReq;
packet.service.computeOnlineMinMW=repmat(computeOnlineMin,N,1);
packet.service.computeDeferredPlannedMW=computeDeferred;
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
packet.audit.coordinationPattern='BOUNDARY_REQUEST_RESPONSE_REDISPATCH_COMMIT';
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
