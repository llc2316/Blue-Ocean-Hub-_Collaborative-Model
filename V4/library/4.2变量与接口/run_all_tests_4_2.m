function report=run_all_tests_4_2()
%RUN_ALL_TESTS_4_2 Acceptance tests for the frozen Chapter 4 contract.

tests={@test_common_config,@test_unsigned_engineering_blocked, ...
    @test_module_packets,@test_schema_mismatch_rejected, ...
    @test_negative_port_rejected,@test_response_nan_rejected};
names=["公共配置","工程模式阻断","4.3—4.7数据包","版本不匹配阻断","负端口阻断","响应缺值阻断"];
passed=false(numel(tests),1); message=strings(numel(tests),1);
for i=1:numel(tests)
    try
        tests{i}(); passed(i)=true; message(i)="PASS";
    catch ME
        message(i)=string(ME.identifier)+": "+string(ME.message);
    end
end
report=table(names',passed,message,'VariableNames',{'Test','Passed','Message'});
disp(report);
assert(all(passed),'BLUEHUB:SchemaAcceptanceFailed','Frozen 4.2 acceptance tests failed.');
fprintf('CHAPTER 4.1-4.2 FROZEN CONTRACT: ALL TESTS PASSED\n');
end

function test_common_config()
cfg=common_config_4_2('interface_smoke');
r=validate_common_schema_4_2(cfg,true); assert(r.ok);
assert(strcmp(cfg.meta.status,'FROZEN_INTERFACE'));
assert(cfg.meta.schemaFrozen);
end

function test_unsigned_engineering_blocked()
cfg=common_config_4_2('engineering_base');
r=validate_common_schema_4_2(cfg,false); assert(~r.ok);
end

function test_module_packets()
cfg=common_config_4_2('interface_smoke'); t=(0:2)';

p=common_packet_4_2('4.3',t,cfg,'RESPONSE');
p.ports.source=valid_port(t,cfg.meter.sourcePOI);
p.loss=struct('pCollectionLossMW',zeros(3,1),'pSourceAuxLoadMW',zeros(3,1), ...
    'collectionLossAlreadyDeducted',true);
validate_module_packet_4_2(p,'4.3',cfg,true);

p=common_packet_4_2('4.4',t,cfg,'LEDGER');
p.state=struct('pBusResidualMW',zeros(3,1),'pSpillActualMW',zeros(3,1), ...
    'pUnservedMW',zeros(3,1),'balanceStatus',repmat("BALANCED",3,1));
validate_module_packet_4_2(p,'4.4',cfg,true);

p=common_packet_4_2('4.5',t,cfg,'RESPONSE');
p.ports.bessCharge=valid_port(t,cfg.meter.commonBus);
p.ports.bessDischarge=valid_port(t,cfg.meter.commonBus);
p.ports.electrolyzer=valid_port(t,cfg.meter.electrolyzer);
p.state=struct('bessSOC',0.5*ones(3,1),'bessEnergyMWh',50*ones(3,1), ...
    'h2InventoryKg',30000*ones(3,1));
p.product=struct('h2ProductionKg',ones(3,1),'h2AvailableForDeliveryKg',ones(3,1));
validate_module_packet_4_2(p,'4.5',cfg,true);

p=common_packet_4_2('4.6',t,cfg,'RESPONSE');
p.ports.dcFacility=valid_port(t,cfg.meter.dcFacility);
p.state=struct('computeQueueMWhCS',zeros(3,1));
p.service=struct('computeServedMWhCS',ones(3,1),'pITActualMW',ones(3,1), ...
    'pDCAuxActualMW',zeros(3,1));
validate_module_packet_4_2(p,'4.6',cfg,true);

p=common_packet_4_2('4.7',t,cfg,'RESPONSE');
p.ports.exportSend=valid_port(t,cfg.meter.cableSend);
p.ports.gridImport=zero_port(t,cfg.meter.cableSend);
p.ports.marine=valid_port(t,cfg.meter.commonBus);
p.product=struct('h2DeliveredKg',ones(3,1));
p.service=struct('pCableReceiveMW',ones(3,1),'cableLossMW',zeros(3,1), ...
    'computeDeliveredMWhCS',ones(3,1),'marineUnservedMW',zeros(3,1));
validate_module_packet_4_2(p,'4.7',cfg,true);
end

function test_schema_mismatch_rejected()
cfg=common_config_4_2('interface_smoke'); p=common_packet_4_2('4.4',0,cfg,'LEDGER');
p.meta.schemaVersion='1.0.0'; p.state=struct('pBusResidualMW',0,'pSpillActualMW',0, ...
    'pUnservedMW',0,'balanceStatus',"BALANCED");
r=validate_module_packet_4_2(p,'4.4',cfg,false); assert(~r.ok);
end

function test_negative_port_rejected()
cfg=common_config_4_2('interface_smoke'); p=common_packet_4_2('4.3',0,cfg,'RESPONSE');
p.ports.source=valid_port(0,cfg.meter.sourcePOI); p.ports.source.actualMW=-1;
p.loss=struct('pCollectionLossMW',0,'pSourceAuxLoadMW',0,'collectionLossAlreadyDeducted',true);
r=validate_module_packet_4_2(p,'4.3',cfg,false); assert(~r.ok);
end

function test_response_nan_rejected()
cfg=common_config_4_2('interface_smoke'); p=common_packet_4_2('4.6',0,cfg,'RESPONSE');
p.ports.dcFacility=valid_port(0,cfg.meter.dcFacility); p.ports.dcFacility.actualMW=NaN;
p.state=struct('computeQueueMWhCS',0);
p.service=struct('computeServedMWhCS',0,'pITActualMW',0,'pDCAuxActualMW',0);
r=validate_module_packet_4_2(p,'4.6',cfg,false); assert(~r.ok);
end

function p=valid_port(t,meter)
p=common_dispatch_port_4_2(t,meter); N=numel(t);
p.requestedMW=ones(N,1); p.acceptedMW=ones(N,1); p.actualMW=ones(N,1);
p.minMW=zeros(N,1); p.maxMW=2*ones(N,1);
p.upCapabilityMW=ones(N,1); p.downCapabilityMW=ones(N,1);
end

function p=zero_port(t,meter)
p=common_dispatch_port_4_2(t,meter); N=numel(t);
p.requestedMW=zeros(N,1); p.acceptedMW=zeros(N,1); p.actualMW=zeros(N,1);
p.minMW=zeros(N,1); p.maxMW=zeros(N,1);
p.upCapabilityMW=zeros(N,1); p.downCapabilityMW=zeros(N,1);
end
