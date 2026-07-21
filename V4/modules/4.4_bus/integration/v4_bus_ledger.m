function packet=v4_bus_ledger(cfg,timeH,p43,p45,p46,p47,pSpill,pUnserved)
%V4_BUS_LEDGER Frozen 4.4 actual-only common-bus ledger.
N=numel(timeH); caux=repmat(cfg.commonBus.commonAuxMW,N,1);
post=repmat(cfg.commonBus.postPOILossMW,N,1);
pSpill=double(pSpill(:)); pUnserved=double(pUnserved(:));
assert(numel(pSpill)==N && numel(pUnserved)==N && ...
    all(pSpill>=0) && all(pUnserved>=0), ...
    'Actual spill and critical unserved series must be nonnegative N-by-1.');
r=p43.ports.source.actualMW+p45.ports.bessDischarge.actualMW+ ...
    p47.ports.gridImport.actualMW ...
    -p45.ports.bessCharge.actualMW-p45.ports.electrolyzer.actualMW ...
    -p46.ports.dcFacility.actualMW-p47.ports.exportSend.actualMW ...
    -p47.ports.marine.actualMW-p43.loss.pSourceAuxLoadMW ...
    -caux-post-pSpill;
status=repmat("BALANCED",N,1);
status(abs(r)>cfg.commonBus.balanceToleranceMW)="INFEASIBLE";
packet=common_packet_4_2('4.4',timeH,cfg,'LEDGER');
packet.state.pBusResidualMW=r;
packet.state.pSpillActualMW=pSpill;
packet.state.pUnservedMW=pUnserved;
packet.state.balanceStatus=status;
packet.loss.pCommonAuxMW=caux;
packet.loss.pPostPOILossMW=post;
packet.audit.lossLedger=struct('sourceCollectionUpstream',true, ...
    'sourceAuxBookedOnce',true,'commonLossOwner','4.4','cableLossDownstream',true);
packet.audit.unservedAccounting='pUnservedMW is unmet demand KPI and never a physical bus injection; marine unserved remains in 4.7.';
validate_module_packet_4_2(packet,'4.4',cfg,true);
end
