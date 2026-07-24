function packet=v4_compute_boundary_4_6(cfg,timeH)
%V4_COMPUTE_BOUNDARY_4_6 Publish the 4.6 feasible power boundary before 4.9.
N=numel(timeH);
packet=common_packet_4_2('4.6',timeH,cfg,'BOUNDARY');
packet.ports.dcFacility=v4_fill_port(timeH,cfg.meter.dcFacility,0,0,0, ...
    0,cfg.compute.facilityMaxMW,"4.6_BOUNDARY","AVAILABLE");
packet.state.computeQueueMWhCS=repmat(cfg.compute.queueInitialMWhCS,N,1);
packet.service.computeServedMWhCS=zeros(N,1);
packet.service.pITActualMW=zeros(N,1);
packet.service.pDCAuxActualMW=zeros(N,1);
packet.service.pDCOnlineMinMW=repmat(cfg.compute.facilityMinMW,N,1);
packet.service.computeModelMode=repmat("SLA_ELASTIC_PRIMARY",N,1);
packet.quality.dataSourceType="4.6_DECLARED_BOUNDARY";
packet.quality.calibrationVersion="UNCALIBRATED";
packet.audit.boundaryMeaning='Maximum facility power available to 4.9; no dispatch performed.';
packet.audit.onlineMinimumMeaning=['dcFacility.minMW remains the unconditional lower bound (zero when shutdown is allowed); ' ...
    'pDCOnlineMinMW is the conditional minimum after the facility is online.'];
validate_module_packet_4_2(packet,'4.6',cfg,true);
end
