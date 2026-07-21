function packet=v4_evaluate_objectives_4_8(cfg,p43,p44,p45,p46,p47,p49,params)
%V4_EVALUATE_OBJECTIVES_4_8 Evaluate economic, environmental and reliability objectives.
% It reads committed actual results only and never changes dispatch/state.
if nargin<8 || isempty(params), params=v4_objective_parameters_4_8(); end
timeH=p44.axis.timeH(:); N=numel(timeH); dt=cfg.time.dispatchStepH;
assert(numel(p43.axis.timeH)==N && numel(p45.axis.timeH)==N && ...
    numel(p46.axis.timeH)==N && numel(p47.axis.timeH)==N, ...
    '4.3--4.7 time axes must have the same length.');

sourceMWh=sum(p43.ports.source.actualMW)*dt;
chargeMWh=sum(p45.ports.bessCharge.actualMW)*dt;
dischargeMWh=sum(p45.ports.bessDischarge.actualMW)*dt;
electrolyzerMWh=sum(p45.ports.electrolyzer.actualMW)*dt;
spillMWh=sum(p44.state.pSpillActualMW)*dt;
criticalUnservedMWh=sum(p44.state.pUnservedMW)*dt;
marineUnservedMWh=sum(p47.service.marineUnservedMW)*dt;
electricityDeliveredMWh=sum(p47.service.pCableReceiveMW)*dt;
h2DeliveredKg=sum(p47.product.h2DeliveredKg);
computeDeliveredMWhCS=sum(p47.service.computeDeliveredMWhCS);
marineServedMWh=sum(p47.ports.marine.actualMW)*dt;
gridImportMWh=sum(p47.ports.gridImport.actualMW)*dt;

e=params.economic;
cost=e.annualizedCapitalCNY ...
    +e.sourceVariableOMCNYPerMWh*sourceMWh ...
    +e.bessThroughputCostCNYPerMWh*(chargeMWh+dischargeMWh) ...
    +e.electrolyzerVariableOMCNYPerMWh*electrolyzerMWh ...
    +e.spillPenaltyCNYPerMWh*spillMWh ...
    +e.unservedPenaltyCNYPerMWh*(criticalUnservedMWh+marineUnservedMWh);
revenue=e.electricityRevenueCNYPerMWh*electricityDeliveredMWh ...
    +e.hydrogenRevenueCNYPerKg*h2DeliveredKg ...
    +e.computeRevenueCNYPerMWhCS*computeDeliveredMWhCS ...
    +e.marineServiceRevenueCNYPerMWh*marineServedMWh;
economicNetCostCNY=cost-revenue;

g=params.environment;
lifecycleEmissionKgCO2e=g.annualizedEmbodiedKgCO2e ...
    +g.sourceKgCO2ePerMWh*sourceMWh ...
    +g.bessThroughputKgCO2ePerMWh*(chargeMWh+dischargeMWh) ...
    +g.gridImportKgCO2ePerMWh*gridImportMWh ...
    +g.hydrogenDeliveryKgCO2ePerKg*h2DeliveredKg;
r=params.reliability;
eensMWh=r.criticalUnservedWeight*criticalUnservedMWh ...
    +r.marineUnservedWeight*marineUnservedMWh;

availableMWh=sum(p43.ports.source.maxMW)*dt;
renewableUtilization=NaN;
if availableMWh>0, renewableUtilization=max(0,min(1,1-spillMWh/availableMWh)); end

packet=common_packet_4_2('4.8',timeH,cfg,'EVALUATION');
packet.state.objectiveVectorRaw=[economicNetCostCNY,lifecycleEmissionKgCO2e,eensMWh];
packet.state.objectiveNames={'economicNetCostCNY','lifecycleEmissionKgCO2e','EENSMWh'};
packet.state.normalizedObjectiveVector=[NaN NaN NaN];
packet.product.economicNetCostCNY=economicNetCostCNY;
packet.product.lifecycleEmissionKgCO2e=lifecycleEmissionKgCO2e;
packet.product.EENSMWh=eensMWh;
packet.service.totalCostCNY=cost;
packet.service.totalRevenueCNY=revenue;
packet.service.sourceEnergyMWh=sourceMWh;
packet.service.spillEnergyMWh=spillMWh;
packet.service.criticalUnservedMWh=criticalUnservedMWh;
packet.service.marineUnservedMWh=marineUnservedMWh;
packet.service.electricityDeliveredMWh=electricityDeliveredMWh;
packet.service.h2DeliveredKg=h2DeliveredKg;
packet.service.computeDeliveredMWhCS=computeDeliveredMWhCS;
packet.service.marineServedMWh=marineServedMWh;
packet.service.renewableUtilization=renewableUtilization;
packet.quality.dataSourceType="INTERFACE_SMOKE_EVALUATION";
packet.quality.calibrationVersion=string(params.meta.calibrationStatus);
packet.audit.parameterNotice=params.meta.notice;
packet.audit.formulaStatus=params.meta.formulaStatus;
packet.audit.capitalBoundary='annualizedCapitalCNY=0 in smoke test; no project NPV/IRR claim';
packet.audit.normalizationStatus='NOT_AVAILABLE_WITHOUT_IDEAL_AND_NADIR_CASES';
packet.audit.dispatchSource=p49.audit.schedulerId;
v4_validate_evaluation_4_8(packet,cfg,true);
end
