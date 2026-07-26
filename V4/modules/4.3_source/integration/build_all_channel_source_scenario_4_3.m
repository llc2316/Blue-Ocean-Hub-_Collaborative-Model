function packet=build_all_channel_source_scenario_4_3(cfg,hours)
%BUILD_ALL_CHANNEL_SOURCE_SCENARIO_4_3 Reuse 4.3 shapes in a stress scenario.
% The capacity expansion and phase multipliers are assumptions for Chapter 5
% interface validation, not an engineering resource or capacity conclusion.
if nargin<2 || isempty(hours), hours=48; end
assert(hours>=24 && hours==round(hours),'hours must be an integer >= 24.');
v4Root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(v4Root,'integration','common'));

baseCfg=common_config_4_2('interface_smoke');
[base,~]=v4_source_adapter(baseCfg,'BOUNDARY');
baseCapacity=[baseCfg.source.windCapacityMW,baseCfg.source.pvCapacityMW, ...
    baseCfg.source.tidalCapacityMW];
newCapacity=[cfg.source.windCapacityMW,cfg.source.pvCapacityMW, ...
    cfg.source.tidalCapacityMW];
assert(all(baseCapacity>0) && all(newCapacity>=0));

idx=mod((0:hours-1)',24)+1;
capacityScale=newCapacity./baseCapacity;
baseActual=base.service.actualBySourceMW(idx,:).*capacityScale;
baseAvailable=base.service.availableBySourceMW(idx,:).*capacityScale;
baseAux=base.service.auxiliaryBySourceMW(idx,:).*capacityScale;
baseLoss=base.service.collectionLossBySourceMW(idx,:).*capacityScale;

multiplier=0.4*ones(hours,1);
multiplier(1:min(6,hours))=0.03;
if hours>=12, multiplier(7:12)=linspace(0.10,0.25,6)'; end
if hours>=20, multiplier(13:20)=0.35; end
if hours>=30, multiplier(21:30)=0.75; end
if hours>=38, multiplier(31:38)=1.00; end
if hours>=44, multiplier(39:44)=0.02; end
if hours>=48, multiplier(45:48)=0.40; end

actualBy=min(baseActual.*multiplier,newCapacity);
availableBy=max(actualBy,min(baseAvailable.*multiplier,newCapacity));
auxBy=baseAux.*max(multiplier,0.10);
lossBy=baseLoss.*multiplier;
pActual=sum(actualBy,2);
pAvailable=sum(availableBy,2);
pAux=sum(auxBy,2);
pLoss=sum(lossBy,2);
timeH=(0:hours-1)';

packet=common_packet_4_2('4.3',timeH,cfg,'BOUNDARY');
packet.ports.source=v4_fill_port(timeH,cfg.meter.sourcePOI, ...
    pActual,pActual,pActual,zeros(hours,1),pAvailable, ...
    "4.3_ALL_CHANNEL_SCENARIO","AVAILABLE");
packet.loss.pCollectionLossMW=pLoss;
packet.loss.pSourceAuxLoadMW=pAux;
packet.loss.collectionLossAlreadyDeducted=true;
packet.service.sourceId=cfg.source.sourceId;
packet.service.sourceType=cfg.source.sourceType;
packet.service.installedCapacityMW=newCapacity;
packet.service.availableBySourceMW=availableBy;
packet.service.actualBySourceMW=actualBy;
packet.service.auxiliaryBySourceMW=auxBy;
packet.service.collectionLossBySourceMW=lossBy;
packet.service.qualityBySource=true(hours,3);
packet.service.validationPhaseMultiplier=multiplier;
packet.state.sourceOperatingState=repmat("SCENARIO_PROFILE",hours,1);
packet.state.sourceConstraintCode=repmat("4.3_STRESS_SEQUENCE",hours,1);
packet.state.stateOut=struct('source','4.3 baseline shapes scaled by validation multipliers');
packet.quality.dataSourceType="SYNTHETIC_ALL_CHANNEL_VALIDATION";
packet.quality.calibrationVersion="UNCALIBRATED";
packet.audit.sourceModelPath=base.audit.sourceModelPath;
packet.audit.scenarioStatus='[假设值，待企业调研校准]';
packet.audit.profileRule= ...
    '4.3 per-source 24 h model shapes repeated, capacity-scaled and phase-multiplied';
packet.audit.phaseDefinition= ...
    'shortage-rise-compute-export-hydrogen-saturation-drop-recovery';
validate_module_packet_4_2(packet,'4.3',cfg,true);
end
