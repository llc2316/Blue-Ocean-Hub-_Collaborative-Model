function adjustment=v4_redispatch_after_compute_4_9(cfg,dispatch,computeActualMW)
%V4_REDISPATCH_AFTER_COMPUTE_4_9 Reallocate unused DC request before 4.7.
% 4.6 may consume less than its accepted cap because the task/SLA feasible
% set is tighter than the electrical boundary. Released power is offered to
% marine demand, cable headroom and then same-hour flow-through hydrogen.
% The hydrogen top-up adds identical same-hour production and withdrawal,
% so the planned H2 inventory path and its terminal constraint do not move.
req=dispatch.computeRequestedMW(:);
actual=double(computeActualMW(:));
assert(numel(actual)==numel(req) && all(isfinite(actual)) && all(actual>=0), ...
    '4.6 actual response must be a finite nonnegative series.');
assert(all(actual<=req+cfg.commonBus.balanceToleranceMW), ...
    '4.6 actual power exceeds the 4.9 request.');

released=max(0,req-actual);
marineGap=max(0,dispatch.marineRequestedMW(:)-dispatch.marineAllocatedMW(:));
marineTopUp=min(released,marineGap);
remaining=released-marineTopUp;
exportLimit=min(cfg.output.cableSendCapacityMW,cfg.output.gridAcceptMaxMW);
exportHeadroom=max(0,exportLimit-dispatch.exportRequestedMW(:));
exportTopUp=min(remaining,exportHeadroom);
remaining=remaining-exportTopUp;

baseElectrolyzerMW=dispatch.req45.electrolyzerMW(:);
deliveryHeadroomKg=max(0,dispatch.h2DeliveryTargetKg(:)- ...
    dispatch.h2DeliveryPlanKg(:));
flowThroughPowerCapMW=deliveryHeadroomKg* ...
    cfg.hydrogen.secKWhPerKg/(1000*cfg.time.dispatchStepH);
electrolyzerHeadroomMW=max(0,cfg.hydrogen.electrolyzerRatedMW- ...
    baseElectrolyzerMW);
electrolyzerTopUpMW=min([remaining,electrolyzerHeadroomMW, ...
    flowThroughPowerCapMW],[],2);
starting=baseElectrolyzerMW<=cfg.commonBus.balanceToleranceMW;
belowStartMinimum=starting & electrolyzerTopUpMW>0 & ...
    electrolyzerTopUpMW<dispatch.electrolyzerOperatingMinimumMW- ...
    cfg.commonBus.balanceToleranceMW;
electrolyzerTopUpMW(belowStartMinimum)=0;
h2FlowThroughTopUpKg=1000*electrolyzerTopUpMW* ...
    cfg.time.dispatchStepH/cfg.hydrogen.secKWhPerKg;
remaining=remaining-electrolyzerTopUpMW;

req45Effective=dispatch.req45;
req45Effective.electrolyzerMW= ...
    baseElectrolyzerMW+electrolyzerTopUpMW;
h2DeliveryPlanEffective=dispatch.h2DeliveryPlanKg(:)+ ...
    h2FlowThroughTopUpKg;

adjustment=struct;
adjustment.computeReleasedMW=released;
adjustment.computeCommittedMW=actual;
adjustment.marineTopUpMW=marineTopUp;
adjustment.marineAllocatedMW=dispatch.marineAllocatedMW(:)+marineTopUp;
adjustment.exportTopUpMW=exportTopUp;
adjustment.exportRequestedMW=dispatch.exportRequestedMW(:)+exportTopUp;
adjustment.electrolyzerTopUpMW=electrolyzerTopUpMW;
adjustment.electrolyzerRequestedMW=req45Effective.electrolyzerMW;
adjustment.h2FlowThroughTopUpKg=h2FlowThroughTopUpKg;
adjustment.h2DeliveryPlanKg=h2DeliveryPlanEffective;
adjustment.h2InventoryPlanKg=dispatch.h2InventoryPlanKg(:);
adjustment.req45=req45Effective;
adjustment.remainingReleasedMW=remaining;
adjustment.committedSpillPlannedMW= ...
    dispatch.spillPlannedMW(:)+remaining;
adjustment.redispatchPass="AFTER_4.6_BEFORE_4.7";
adjustment.allocationOrder= ...
    "MARINE_GAP_THEN_CABLE_HEADROOM_THEN_SAME_HOUR_FLOW_THROUGH_H2";
adjustment.powerClosureResidualMW=released-marineTopUp-exportTopUp- ...
    electrolyzerTopUpMW-remaining;
assert(max(abs(adjustment.powerClosureResidualMW))<=1e-9, ...
    'Post-compute redispatch power identity is inconsistent.');
assert(all(h2DeliveryPlanEffective<=dispatch.h2DeliveryTargetKg+1e-6), ...
    'Post-compute H2 flow-through exceeds the delivery/channel target.');
end
