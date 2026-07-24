function adjustment=v4_redispatch_after_compute_4_9(cfg,dispatch,computeActualMW)
%V4_REDISPATCH_AFTER_COMPUTE_4_9 Reallocate unused DC request before 4.7.
% 4.6 may consume less than its accepted cap because the task/SLA feasible
% set is tighter than the electrical boundary.  The released power is first
% offered to already-declared marine demand.  Remaining power stays visible
% to the later actual reconciliation and may become spill only when no
% dispatchable shortfall remains.
req=dispatch.computeRequestedMW(:);
actual=double(computeActualMW(:));
assert(numel(actual)==numel(req) && all(isfinite(actual)) && all(actual>=0), ...
    '4.6 actual response must be a finite nonnegative series.');
assert(all(actual<=req+cfg.commonBus.balanceToleranceMW), ...
    '4.6 actual power exceeds the 4.9 request.');

released=max(0,req-actual);
marineGap=max(0,dispatch.marineRequestedMW(:)-dispatch.marineAllocatedMW(:));
marineTopUp=min(released,marineGap);

adjustment=struct;
adjustment.computeReleasedMW=released;
adjustment.marineTopUpMW=marineTopUp;
adjustment.marineAllocatedMW=dispatch.marineAllocatedMW(:)+marineTopUp;
adjustment.remainingReleasedMW=released-marineTopUp;
adjustment.redispatchPass="AFTER_4.6_BEFORE_4.7";
end
