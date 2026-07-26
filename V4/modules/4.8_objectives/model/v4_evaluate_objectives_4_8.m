function packet=v4_evaluate_objectives_4_8(cfg,p43,p44,p45,p46,p47,p49,params)
%V4_EVALUATE_OBJECTIVES_4_8 Evaluate economic, environmental and reliability objectives.
% It reads committed actual results only and never changes dispatch/state.
if nargin<8 || isempty(params), params=v4_objective_parameters_4_8(); end
timeH=p44.axis.timeH(:); N=numel(timeH); dt=cfg.time.dispatchStepH;
assert(numel(p43.axis.timeH)==N && numel(p45.axis.timeH)==N && ...
    numel(p46.axis.timeH)==N && numel(p47.axis.timeH)==N, ...
    '4.3--4.7 time axes must have the same length.');

sourceMWh=sum(p43.ports.source.actualMW)*dt;
[sourceType,sourceEnergyByTypeMWh]=source_breakdown(p43,dt,sourceMWh);
chargeMWh=sum(p45.ports.bessCharge.actualMW)*dt;
dischargeMWh=sum(p45.ports.bessDischarge.actualMW)*dt;
electrolyzerMWh=sum(p45.ports.electrolyzer.actualMW)*dt;
h2ProducedKg=sum(p45.product.h2ProductionKg);
electrolyzerStarts=0;
if isfield(p45,'service') && isfield(p45.service,'electrolyzerStartEvent')
    electrolyzerStarts=sum(double(p45.service.electrolyzerStartEvent));
end
spillMWh=sum(p44.state.pSpillActualMW)*dt;
criticalUnservedMWh=sum(p44.state.pUnservedMW)*dt;
marineUnservedMWh=sum(p47.service.marineUnservedMW)*dt;
electricityDeliveredMWh=sum(p47.service.pCableReceiveMW)*dt;
h2DeliveredKg=sum(p47.product.h2DeliveredKg);
h2PipeWithdrawnKg=0; h2ShipWithdrawnKg=0;
if isfield(p47.audit,'h2PipeWithdrawnKg')
    h2PipeWithdrawnKg=sum(p47.audit.h2PipeWithdrawnKg);
end
if isfield(p47.audit,'h2ShipWithdrawnKg')
    h2ShipWithdrawnKg=sum(p47.audit.h2ShipWithdrawnKg);
end
computeDeliveredMWhCS=sum(p47.service.computeDeliveredMWhCS);
computeServedMWhCS=sum(p46.service.computeServedMWhCS);
marineServedMWh=sum(p47.ports.marine.actualMW)*dt;
gridImportMWh=sum(p47.ports.gridImport.actualMW)*dt;
bessOpeningMWh=cfg.bess.socInitial*cfg.bess.energyMWh;
bessClosingMWh=p45.state.bessEnergyMWh(end);
bessOpeningWithdrawalMWh=max(0,bessOpeningMWh-bessClosingMWh);
h2OpeningKg=cfg.hydrogen.storageInitialKg;
h2ClosingKg=p45.state.h2InventoryKg(end);
h2OpeningWithdrawalKg=max(0,h2OpeningKg-h2ClosingKg);

e=params.economic;
sourceVariableOMCostCNY=e.sourceVariableOMCNYPerMWh*sourceMWh;
sourceVariableOMCostByTypeCNY=nan(size(sourceEnergyByTypeMWh));
sourceCostStatus='AGGREGATE_FALLBACK_UNCALIBRATED';
if ~isempty(sourceType) && isfield(e,'sourceType') && ...
        isfield(e,'sourceVariableOMCNYPerMWhByType')
    configuredType=string(e.sourceType);
    configuredCost=double(e.sourceVariableOMCNYPerMWhByType(:))';
    [found,location]=ismember(sourceType,configuredType);
    if all(found) && numel(configuredCost)==numel(configuredType) && ...
            all(isfinite(configuredCost(location)))
        sourceVariableOMCostByTypeCNY= ...
            sourceEnergyByTypeMWh.*configuredCost(location);
        sourceVariableOMCostCNY=sum(sourceVariableOMCostByTypeCNY);
        sourceCostStatus='SOURCE_DIFFERENTIATED_CALIBRATED_CASE';
    end
end
computeRevenueSource='4.8_UNCALIBRATED_FALLBACK';
computeGrossRevenueCNY=e.computeRevenueCNYPerMWhCS*computeDeliveredMWhCS;
computeSLAPenaltyCNY=0;
computeVariableOMCNY=0;
computeElectricityTransferCNY=NaN;
computeDeliveryRatio=1;
if isfield(p46.service,'computeGrossRevenueCNY') && ...
        isfield(p46.service,'computeSLAPenaltyCNY') && ...
        isfield(p46.service,'computeVariableOMCNY')
    assert(numel(p46.service.computeGrossRevenueCNY)==N && ...
        numel(p46.service.computeSLAPenaltyCNY)==N && ...
        numel(p46.service.computeVariableOMCNY)==N, ...
        '4.6 compute-economic sequences must match the common time axis.');
    if computeServedMWhCS>0
        computeDeliveryRatio=max(0,min(1,computeDeliveredMWhCS/computeServedMWhCS));
    end
    computeGrossRevenueCNY=sum(p46.service.computeGrossRevenueCNY)*computeDeliveryRatio;
    computeSLAPenaltyCNY=sum(p46.service.computeSLAPenaltyCNY);
    computeVariableOMCNY=sum(p46.service.computeVariableOMCNY);
    if isfield(p46.service,'computeElectricityTransferCNY')
        computeElectricityTransferCNY=sum(p46.service.computeElectricityTransferCNY);
    end
    computeRevenueSource='4.6_TASK_PRICE_MARKET_REFERENCE';
end
bessDegradationCostCNY=e.bessDischargeDegradationCNYPerMWh*dischargeMWh;
bessOpeningInventoryCostCNY= ...
    e.bessOpeningInventoryCNYPerMWh*bessOpeningWithdrawalMWh;
hydrogenVariableCostCNY=e.hydrogenVariableCostCNYPerKg*h2ProducedKg;
hydrogenOpeningInventoryCostCNY= ...
    e.hydrogenOpeningInventoryCNYPerKg*h2OpeningWithdrawalKg;
hydrogenPipeTransportCostCNY= ...
    e.hydrogenPipeTransportCNYPerKg*h2PipeWithdrawnKg;
hydrogenShipTransportCostCNY= ...
    e.hydrogenShipTransportCNYPerKg*h2ShipWithdrawnKg;
electrolyzerStartCostCNY=e.electrolyzerStartCostCNYPerStart*electrolyzerStarts;
spillPenaltyCNY=e.spillPenaltyCNYPerMWh*spillMWh;
unservedPenaltyCNY= ...
    e.unservedPenaltyCNYPerMWh*(criticalUnservedMWh+marineUnservedMWh);
operatingCostComponentsCNY=[sourceVariableOMCostCNY, ...
    bessDegradationCostCNY,bessOpeningInventoryCostCNY, ...
    hydrogenVariableCostCNY,hydrogenOpeningInventoryCostCNY, ...
    hydrogenPipeTransportCostCNY,hydrogenShipTransportCostCNY, ...
    electrolyzerStartCostCNY,spillPenaltyCNY,unservedPenaltyCNY, ...
    computeSLAPenaltyCNY,computeVariableOMCNY];
operatingCostCNY=sum(operatingCostComponentsCNY);
penaltyCostCNY=spillPenaltyCNY+unservedPenaltyCNY+computeSLAPenaltyCNY;

electricityRevenueCNY=e.electricityRevenueCNYPerMWh*electricityDeliveredMWh;
hydrogenRevenueCNY=e.hydrogenRevenueCNYPerKg*h2DeliveredKg;
marineServiceRevenueCNY=e.marineServiceRevenueCNYPerMWh*marineServedMWh;
revenueComponentsCNY=[electricityRevenueCNY,hydrogenRevenueCNY, ...
    computeGrossRevenueCNY,marineServiceRevenueCNY];
revenue=sum(revenueComponentsCNY);
[lifecycle,lifecycleAssetTable]=v4_lifecycle_economics_4_8( ...
    cfg,params,operatingCostCNY,revenue,penaltyCostCNY,N*dt);
depreciationCostCNY=lifecycle.periodDepreciationCNY;
financingCostCNY=lifecycle.periodFinancingCostCNY;
fixedOMCostCNY=lifecycle.periodFixedOMCNY;
replacementReserveCostCNY=lifecycle.periodReplacementReserveCNY;
costComponentsCNY=[depreciationCostCNY,financingCostCNY,fixedOMCostCNY, ...
    replacementReserveCostCNY,operatingCostComponentsCNY];
cost=sum(costComponentsCNY);
economicNetCostCNY=cost-revenue;

g=params.environment;
annualizedEmbodiedEmissionKgCO2e=g.annualizedEmbodiedKgCO2e;
sourceEmissionKgCO2e=g.sourceKgCO2ePerMWh*sourceMWh;
bessThroughputEmissionKgCO2e= ...
    g.bessThroughputKgCO2ePerMWh*(chargeMWh+dischargeMWh);
gridImportEmissionKgCO2e=g.gridImportKgCO2ePerMWh*gridImportMWh;
hydrogenDeliveryEmissionKgCO2e= ...
    g.hydrogenDeliveryKgCO2ePerKg*h2DeliveredKg;
emissionComponentsKgCO2e=[annualizedEmbodiedEmissionKgCO2e, ...
    sourceEmissionKgCO2e,bessThroughputEmissionKgCO2e, ...
    gridImportEmissionKgCO2e,hydrogenDeliveryEmissionKgCO2e];
lifecycleEmissionKgCO2e=sum(emissionComponentsKgCO2e);
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
packet.service.costComponentNames={ ...
    'depreciationCostCNY','financingCostCNY','fixedOMCostCNY', ...
    'replacementReserveCostCNY','sourceVariableOMCostCNY', ...
    'bessDegradationCostCNY','bessOpeningInventoryCostCNY', ...
    'hydrogenVariableCostCNY','hydrogenOpeningInventoryCostCNY', ...
    'hydrogenPipeTransportCostCNY','hydrogenShipTransportCostCNY', ...
    'electrolyzerStartCostCNY','spillPenaltyCNY','unservedPenaltyCNY', ...
    'computeSLAPenaltyCNY','computeVariableOMCNY'};
packet.service.costComponentsCNY=costComponentsCNY;
packet.service.operatingCostCNY=operatingCostCNY;
packet.service.penaltyCostCNY=penaltyCostCNY;
packet.service.lifecycle=lifecycle;
packet.service.lifecycleAssetTable=lifecycleAssetTable;
packet.service.revenueComponentNames={ ...
    'electricityRevenueCNY','hydrogenRevenueCNY', ...
    'computeGrossRevenueCNY','marineServiceRevenueCNY'};
packet.service.revenueComponentsCNY=revenueComponentsCNY;
packet.service.emissionComponentNames={ ...
    'annualizedEmbodiedEmissionKgCO2e','sourceEmissionKgCO2e', ...
    'bessThroughputEmissionKgCO2e','gridImportEmissionKgCO2e', ...
    'hydrogenDeliveryEmissionKgCO2e'};
packet.service.emissionComponentsKgCO2e=emissionComponentsKgCO2e;
packet.service.sourceEnergyMWh=sourceMWh;
packet.service.sourceType=cellstr(sourceType);
packet.service.sourceEnergyByTypeMWh=sourceEnergyByTypeMWh;
packet.service.sourceVariableOMCostByTypeCNY=sourceVariableOMCostByTypeCNY;
packet.service.spillEnergyMWh=spillMWh;
packet.service.criticalUnservedMWh=criticalUnservedMWh;
packet.service.marineUnservedMWh=marineUnservedMWh;
packet.service.electricityDeliveredMWh=electricityDeliveredMWh;
packet.service.h2DeliveredKg=h2DeliveredKg;
packet.service.h2PipeWithdrawnKg=h2PipeWithdrawnKg;
packet.service.h2ShipWithdrawnKg=h2ShipWithdrawnKg;
packet.service.h2ProducedKg=h2ProducedKg;
packet.service.electrolyzerEnergyMWh=electrolyzerMWh;
packet.service.electrolyzerStarts=electrolyzerStarts;
packet.service.computeDeliveredMWhCS=computeDeliveredMWhCS;
packet.service.computeGrossRevenueCNY=computeGrossRevenueCNY;
packet.service.computeSLAPenaltyCNY=computeSLAPenaltyCNY;
packet.service.computeVariableOMCNY=computeVariableOMCNY;
packet.service.computeElectricityTransferCNY=computeElectricityTransferCNY;
packet.service.computeDeliveryRatio=computeDeliveryRatio;
packet.service.marineServedMWh=marineServedMWh;
packet.service.renewableUtilization=renewableUtilization;
packet.service.bessOpeningInventoryWithdrawalMWh=bessOpeningWithdrawalMWh;
packet.service.h2OpeningInventoryWithdrawalKg=h2OpeningWithdrawalKg;
packet.quality.dataSourceType="INTERFACE_SMOKE_EVALUATION";
packet.quality.calibrationVersion=string(params.meta.calibrationStatus);
packet.audit.parameterNotice=params.meta.notice;
packet.audit.formulaStatus=params.meta.formulaStatus;
packet.audit.sourceCostStatus=sourceCostStatus;
packet.audit.computeRevenueSource=computeRevenueSource;
packet.audit.computeElectricityCostBoundary='4.6 electricity charge is transfer/opportunity cost only and is not added again in 4.8';
packet.audit.bessDegradationCostBoundary='CNY/MWh of BESS discharge only; no charge-side double count';
packet.audit.hydrogenVariableCostBoundary='CNY/kg H2 produced; includes the 4.5 method-case variable-cost bundle';
packet.audit.openingInventoryCostBoundary= ...
    'Net depletion of opening BESS/H2 inventory is charged at explicit opportunity-cost parameters.';
packet.audit.hydrogenTransportCostBoundary= ...
    'Pipe and ship transport costs are charged separately on withdrawn hydrogen.';
packet.audit.electricityPriceSourceType=params.meta.electricityPriceSourceType;
packet.audit.hydrogenPriceSourceType=params.meta.hydrogenPriceSourceType;
packet.audit.capitalBoundary=[ ...
    'Initial CAPEX is represented once through straight-line depreciation plus ', ...
    'discount-rate capital recovery; replacement reserve is annualized from ', ...
    'discounted replacement events. Gross CAPEX is disclosure only and is not ', ...
    'added again to the dispatch-period objective.'];
packet.audit.lifecycleBoundary=[ ...
    'Short dispatch period is repeated to 8760 h for lifecycle NPV. This is ', ...
    '[假设值，待企业调研校准], not a bankable forecast. Tax, shared offshore ', ...
    'platform, converter station, insurance and decommissioning are excluded.'];
packet.audit.lifecycleParameterSourceType=params.lifecycle.meta;
packet.audit.normalizationStatus='NOT_AVAILABLE_WITHOUT_IDEAL_AND_NADIR_CASES';
packet.audit.dispatchSource=p49.audit.schedulerId;
v4_validate_evaluation_4_8(packet,cfg,true);
end

function [sourceType,energyMWh]=source_breakdown(p43,dt,totalMWh)
sourceType=strings(1,0);
energyMWh=zeros(1,0);
if ~isfield(p43,'service') || ~isfield(p43.service,'sourceType') || ...
        ~isfield(p43.service,'actualBySourceMW')
    return;
end
sourceType=string(p43.service.sourceType);
actual=double(p43.service.actualBySourceMW);
assert(size(actual,2)==numel(sourceType) && all(isfinite(actual),'all') && ...
    all(actual>=0,'all'),'Invalid 4.3 per-source actual-power breakdown.');
energyMWh=sum(actual,1)*dt;
assert(abs(sum(energyMWh)-totalMWh)<=max(1e-8,1e-9*max(1,totalMWh)), ...
    '4.3 aggregate and per-source energy are inconsistent.');
end
