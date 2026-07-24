function out=run_v4_integration()
%RUN_V4_INTEGRATION Non-invasive Chapter 4.3--4.9 integration smoke test.
here=fileparts(mfilename('fullpath'));
addpath(fullfile(here,'library','4.2变量与接口'), ...
    fullfile(here,'integration','common'), ...
    fullfile(here,'modules','4.3_source','integration'), ...
    fullfile(here,'modules','4.4_bus','integration'), ...
    fullfile(here,'modules','4.5_storage_hydrogen','integration'), ...
    fullfile(here,'modules','4.6_compute','integration'), ...
    fullfile(here,'modules','4.8_objectives','model'), ...
    fullfile(here,'modules','4.9_dispatch','model'));
cfg=common_config_4_2('interface_smoke'); validate_common_schema_4_2(cfg,true);
outDir=fullfile(here,'outputs'); if ~isfolder(outDir), mkdir(outDir); end

%% BOUNDARY: 4.3 source availability and 4.6 compute feasible range
[p43Boundary,sourceRaw]=v4_source_adapter(cfg,'BOUNDARY'); %#ok<NASGU>
timeH=p43Boundary.axis.timeH; N=numel(timeH);
p46Boundary=v4_compute_boundary_4_6(cfg,timeH);

%% 4.9 REQUEST: cross-module allocation before professional responses
[p49,dispatch]=v4_dispatch_4_9(cfg,p43Boundary,p46Boundary);

%% RESPONSE: 4.3 must-take source realization for the smoke case
p43=p43Boundary; p43.meta.phase='RESPONSE';
validate_module_packet_4_2(p43,'4.3',cfg,true);

%% RESPONSE: 4.6 existing DC-only model receives the hourly 4.9 request
computeCsv=fullfile(outDir,'v4_compute_response.csv');
computeRequestCsv=fullfile(outDir,'v4_compute_request.csv');
Tc=table(dispatch.computeRequestedMW,'VariableNames',{'compute_requested_mw'});
writetable(Tc,computeRequestCsv);
pyScript=fullfile(here,'modules','4.6_compute','integration','v4_compute_bridge.py');
dcRoot=fullfile(here,'modules','4.6_compute','DC_model_v2_1');
cmd=sprintf('python "%s" --module-root "%s" --output "%s" --request "%s" --hours %d --mode sla', ...
    pyScript,dcRoot,computeCsv,computeRequestCsv,N);
[status,msg]=system(cmd); assert(status==0,'4.6 bridge failed: %s',msg);
C=readtable(computeCsv,'VariableNamingRule','preserve'); assert(height(C)==N);
p46=common_packet_4_2('4.6',timeH,cfg,'RESPONSE');
p46.ports.dcFacility=v4_fill_port(timeH,cfg.meter.dcFacility,dispatch.computeRequestedMW, ...
    C.dc_power_mw,C.dc_power_mw,0,p46Boundary.ports.dcFacility.maxMW, ...
    "4.6_DC_ONLY","AVAILABLE");
p46.state.computeQueueMWhCS=C.compute_queue_mwh_cs;
p46.service.computeServedMWhCS=C.compute_served_mwh_cs;
p46.service.pITActualMW=C.it_power_mw;
p46.service.pDCAuxActualMW=C.dc_aux_power_mw;
p46.service.computeRigidUnservedMWhCS=C.rigid_unserved_mwh_cs;
p46.service.computeFlexOverdueMWhCS=C.flex_overdue_mwh_cs;
p46.service.computeSpotDroppedMWhCS=C.spot_dropped_mwh_cs;
p46.service.pDCOnlineMinMW=C.dc_online_min_mw;
p46.service.computeModelMode=string(C.compute_model_mode);
p46.audit.modelOrigin=dcRoot;
p46.audit.serviceNormalization='MWh-CS = GPUh * equivalent_gpu_it_power_kw / 1000 [假设值，待企业调研校准]';
validate_module_packet_4_2(p46,'4.6',cfg,true);

req45=dispatch.req45;
exportReq=dispatch.exportRequestedMW;
marineReq=dispatch.marineRequestedMW;
redispatch46=v4_redispatch_after_compute_4_9(cfg,dispatch,C.dc_power_mw);
marineAvailable=redispatch46.marineAllocatedMW;
state0=struct('bessEnergyMWh',cfg.bess.socInitial*cfg.bess.energyMWh, ...
    'h2InventoryKg',cfg.hydrogen.storageInitialKg);
prov45=v4_storage_hydrogen_response(cfg,timeH,req45,state0,zeros(N,1));

%% 4.7 existing channel functions; duplicated PUE/production/balance are bypassed
inputCsv=fullfile(outDir,'v4_output_request.csv'); outputCsv=fullfile(outDir,'v4_output_response.csv');
h2Req=min(prov45.h2AvailableForDeliveryKg,dispatch.h2DeliveryCapKg);
T=table(exportReq,marineReq,marineAvailable,prov45.h2AvailableForDeliveryKg,h2Req, ...
    p46.service.computeServedMWhCS,repmat(cfg.compute.fiberServiceCapacityMWhCSPerH,N,1), ...
    'VariableNames',{'export_requested_mw','marine_requested_mw','marine_available_mw','h2_available_kg', ...
    'h2_requested_kg','compute_served_mwh_cs','compute_delivery_cap_mwh_cs'});
writetable(T,inputCsv);
pyScript=fullfile(here,'modules','4.7_outputs','integration','v4_output_bridge.py');
mod47=fullfile(here,'modules','4.7_outputs','delivery_model');
cmd=sprintf(['python "%s" --module-root "%s" --input "%s" --output "%s" ' ...
    '--cable-cap %.12g --grid-cap %.12g --cable-loss %.12g --pipe-cap %.12g ' ...
    '--ship-cap %.12g --pipe-loss %.12g --ship-loss %.12g --marine-base %.12g ' ...
    '--marine-desal %.12g --marine-equipment %.12g --marine-flex %.12g'],pyScript,mod47,inputCsv,outputCsv, ...
    cfg.output.cableSendCapacityMW,cfg.output.gridAcceptMaxMW,cfg.output.cableLossFraction, ...
    cfg.hydrogen.pipeCapacityKgPerH,cfg.hydrogen.shipCapacityKgPerH, ...
    cfg.hydrogen.pipeLossFraction,cfg.hydrogen.shipLossFraction, ...
    cfg.output.marineBaseLoadMW,cfg.output.marineDesalLoadMW, ...
    cfg.output.marineEquipmentLoadMW,cfg.output.marineFlexibleFraction);
[status,msg]=system(cmd); assert(status==0,'4.7 bridge failed: %s',msg);
O=readtable(outputCsv,'VariableNamingRule','preserve');
p47=common_packet_4_2('4.7',timeH,cfg,'RESPONSE');
p47.ports.exportSend=v4_fill_port(timeH,cfg.meter.cableSend,exportReq,O.export_actual_mw,O.export_actual_mw,0, ...
    min(cfg.output.cableSendCapacityMW,cfg.output.gridAcceptMaxMW),"4.7_CABLE","AVAILABLE");
p47.ports.gridImport=v4_fill_port(timeH,cfg.meter.cableSend,0,0,0,0,0,"IMPORT_DISABLED","DISABLED");
p47.ports.marine=v4_fill_port(timeH,cfg.meter.commonBus,marineReq,O.marine_actual_mw,O.marine_actual_mw,0, ...
    cfg.output.marineBaseLoadMW+cfg.output.marineDesalLoadMW+cfg.output.marineEquipmentLoadMW,"4.7_MARINE","AVAILABLE");
p47.product.h2DeliveredKg=O.h2_delivered_kg;
p47.service.pCableReceiveMW=O.cable_receive_mw;
p47.service.cableLossMW=O.cable_loss_mw;
p47.service.computeDeliveredMWhCS=O.compute_delivered_mwh_cs;
p47.service.marineUnservedMW=O.marine_unserved_mw;
p47.service.marineBelowRigid=logical(O.marine_below_rigid);
p47.service.marineViolationCount=O.marine_violation_count;
p47.audit.h2WithdrawnKg=O.h2_withdrawn_kg;
p47.audit.bypassedLegacyFunctions={'compute_load.py PUE','hydrogen_output.py production/inventory', ...
    'balance.py system balance','objectives.py cross-channel objective'};
validate_module_packet_4_2(p47,'4.7',cfg,true);

%% STATE_COMMIT-equivalent state fields and actual-only 4.4 LEDGER
prov45=v4_storage_hydrogen_response(cfg,timeH,req45,state0,O.h2_withdrawn_kg);
p45=v4_finalize_4_5_packet(cfg,timeH,req45,prov45,O.h2_withdrawn_kg);
assert(all(h2Req<=p45.product.h2AvailableForDeliveryKg+1e-9), ...
    '4.7 hydrogen request exceeds committed 4.5 availability sequence.');
actual49=v4_reconcile_actuals_4_9(cfg,p43,p45,p46,p47,dispatch);
p44=v4_bus_ledger(cfg,timeH,p43,p45,p46,p47,actual49.spillMW,actual49.criticalUnservedMW);

assert(max(abs(p44.state.pBusResidualMW))<=cfg.commonBus.balanceToleranceMW, ...
    'V4 bus residual exceeds frozen tolerance.');
assert(all(p45.state.bessSOC>=cfg.bess.socMin-1e-9 & p45.state.bessSOC<=cfg.bess.socMax+1e-9));
assert(all(p45.state.h2InventoryKg>=-1e-9 & p45.state.h2InventoryKg<=cfg.hydrogen.storageMaxKg+1e-9));

%% 4.8 EVALUATION: committed actual quantities only
p48=v4_evaluate_objectives_4_8(cfg,p43,p44,p45,p46,p47,p49,[]);

out=struct('cfg',cfg,'packet4_3',p43,'packet4_4',p44,'packet4_5',p45, ...
    'packet4_6',p46,'packet4_7',p47,'packet4_8',p48,'packet4_9',p49, ...
    'dispatchActual',actual49,'redispatchAfterCompute',redispatch46, ...
    'schedulerId',p49.audit.schedulerId, ...
    'assumptionNotice','[假设值，待企业调研校准]');
save(fullfile(outDir,'v4_integration_result.mat'),'out');
S=table(timeH,p43.ports.source.actualMW,p45.ports.bessCharge.actualMW, ...
    p45.ports.bessDischarge.actualMW,p45.ports.electrolyzer.actualMW, ...
    p46.ports.dcFacility.actualMW,p47.ports.marine.actualMW, ...
    p47.ports.exportSend.actualMW,actual49.spillMW,p47.service.marineUnservedMW, ...
    p44.state.pBusResidualMW, ...
    'VariableNames',{'timeH','sourceMW','bessChargeMW','bessDischargeMW', ...
    'electrolyzerMW','dcFacilityMW','marineMW','exportSendMW','spillMW', ...
    'marineUnservedMW','busResidualMW'});
writetable(S,fullfile(outDir,'v4_hourly_summary.csv'));
J=table(p48.product.economicNetCostCNY,p48.product.lifecycleEmissionKgCO2e, ...
    p48.product.EENSMWh,string(p48.quality.calibrationVersion), ...
    string(p48.audit.normalizationStatus), ...
    'VariableNames',{'economicNetCostCNY','lifecycleEmissionKgCO2e','EENSMWh', ...
    'calibrationVersion','normalizationStatus'});
writetable(J,fullfile(outDir,'v4_objective_summary.csv'));
fprintf('BLUE HUB CH4 V4 INTEGRATION: PASSED\n');
fprintf('Maximum bus residual: %.3e MW\n',max(abs(p44.state.pBusResidualMW)));
fprintf('4.8 objective vector [CNY, kgCO2e, MWh]: [%.6g, %.6g, %.6g]\n', ...
    p48.state.objectiveVectorRaw);
end
