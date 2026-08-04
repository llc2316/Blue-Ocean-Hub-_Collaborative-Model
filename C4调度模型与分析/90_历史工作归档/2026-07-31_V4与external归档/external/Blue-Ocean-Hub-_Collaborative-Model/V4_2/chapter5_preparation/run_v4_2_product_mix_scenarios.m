function [summary,allKpi,designTable]=run_v4_2_product_mix_scenarios()
%RUN_V4_2_PRODUCT_MIX_SCENARIOS Product-channel design cases for V4_2.
%
% The cases use one 420 MW equivalent product-channel capacity pool:
% power export MW + electrolyzer MW + data-center facility MW = 420 MW.
% This is a scenario-comparison convention, not an engineering optimum.
%
% Outputs are written to outputs/product_mix_scenarios/.

here=fileparts(mfilename('fullpath'));
v4Root=fileparts(here);
add_required_paths(v4Root);

totalProductCapacityMW=420;
specs=product_mix_specs(totalProductCapacityMW);
baseOutDir=fullfile(v4Root,'outputs','product_mix_scenarios');
if ~isfolder(baseOutDir), mkdir(baseOutDir); end

n=numel(specs);
scenarioId=strings(n,1);
scenarioLabel=strings(n,1);
shareElectricity=zeros(n,1);
shareHydrogen=zeros(n,1);
shareCompute=zeros(n,1);
productCapacityMW=zeros(n,1);
powerCableMW=zeros(n,1);
electrolyzerMW=zeros(n,1);
computeFacilityRequestMW=zeros(n,1);
computeInstalledFacilityMW=zeros(n,1);
computeUnitCount=zeros(n,1);
h2DeliveryKgPerH=zeros(n,1);
electricityDeliveredMWh=zeros(n,1);
h2DeliveredKg=zeros(n,1);
computeDeliveredMWhCS=zeros(n,1);
spillEnergyMWh=zeros(n,1);
renewableUtilization=zeros(n,1);
totalRevenueCNY=zeros(n,1);
totalCostCNY=zeros(n,1);
economicNetCostCNY=zeros(n,1);
lifecycleNPVAfterPenaltyCNY=zeros(n,1);
grossCapexCNY=zeros(n,1);
EENSMWh=zeros(n,1);
maxAbsBusResidualMW=zeros(n,1);

allKpi=table();
for i=1:n
    spec=specs(i);
    cfg=build_product_mix_cfg(spec);
    outDir=fullfile(baseOutDir,char(spec.scenarioId));
    dispatchOptions=struct( ...
        'computeRequestMW',spec.computeFacilityMW, ...
        'computeFirmRequestMW',0, ...
        'h2DeliveryCapKgPerH',spec.h2DeliveryKgPerH, ...
        'h2SalePriceCNYPerKg',cfg.hydrogen.referenceSalePriceCNYPerKg, ...
        'h2VariableCostCNYPerKg',cfg.hydrogen.variableCostCNYPerKg, ...
        'electricityPriceCNYPerMWh', ...
            cfg.economics.referenceElectricityPriceCNYPerMWh);
    options=struct( ...
        'cfg',cfg, ...
        'dispatchOptions',dispatchOptions, ...
        'computeMode','sla', ...
        'useUnifiedCapacity',false, ...
        'outputMode','M', ...
        'scenarioId',char(spec.scenarioId), ...
        'outputDir',outDir);
    run_v4_integration(options);

    kpi=readtable(fullfile(outDir,'v4_kpi_summary.csv'), ...
        'VariableNamingRule','preserve');
    if i==1, allKpi=kpi; else, allKpi=[allKpi;kpi]; end %#ok<AGROW>

    scenarioId(i)=spec.scenarioId;
    scenarioLabel(i)=spec.label;
    shareElectricity(i)=spec.shareElectricity;
    shareHydrogen(i)=spec.shareHydrogen;
    shareCompute(i)=spec.shareCompute;
    productCapacityMW(i)=spec.totalProductCapacityMW;
    powerCableMW(i)=spec.powerCableMW;
    electrolyzerMW(i)=spec.electrolyzerMW;
    computeFacilityRequestMW(i)=spec.computeFacilityMW;
    computeInstalledFacilityMW(i)=cfg.capacity.installed.computeFacilityMW;
    computeUnitCount(i)=cfg.capacity.installed.computeUnitCount;
    h2DeliveryKgPerH(i)=spec.h2DeliveryKgPerH;
    electricityDeliveredMWh(i)=kpi_value(kpi,'electricityDeliveredMWh');
    h2DeliveredKg(i)=kpi_value(kpi,'h2DeliveredKg');
    computeDeliveredMWhCS(i)=kpi_value(kpi,'computeDeliveredMWhCS');
    spillEnergyMWh(i)=kpi_value(kpi,'spillEnergyMWh');
    renewableUtilization(i)=kpi_value(kpi,'renewableUtilization');
    totalRevenueCNY(i)=kpi_value(kpi,'totalRevenueCNY');
    totalCostCNY(i)=kpi_value(kpi,'totalCostCNY');
    economicNetCostCNY(i)=kpi_value(kpi,'economicNetCostCNY');
    lifecycleNPVAfterPenaltyCNY(i)= ...
        kpi_value(kpi,'lifecycleNPVAfterPenaltyCNY');
    grossCapexCNY(i)=kpi_value(kpi,'grossCapexCNY');
    EENSMWh(i)=kpi_value(kpi,'EENSMWh');
    maxAbsBusResidualMW(i)=kpi_value(kpi,'maxAbsBusResidualMW');
end

summary=table(scenarioId,scenarioLabel,shareElectricity,shareHydrogen, ...
    shareCompute,productCapacityMW,powerCableMW,electrolyzerMW, ...
    computeFacilityRequestMW,computeInstalledFacilityMW,computeUnitCount, ...
    h2DeliveryKgPerH,electricityDeliveredMWh,h2DeliveredKg, ...
    computeDeliveredMWhCS,spillEnergyMWh,renewableUtilization, ...
    totalRevenueCNY,totalCostCNY,economicNetCostCNY, ...
    lifecycleNPVAfterPenaltyCNY,grossCapexCNY,EENSMWh, ...
    maxAbsBusResidualMW);

designTable=specs_to_table(specs);
writetable(designTable,fullfile(baseOutDir, ...
    'v4_2_product_mix_design.csv'));
writetable(summary,fullfile(baseOutDir, ...
    'v4_2_product_mix_summary.csv'));
writetable(allKpi,fullfile(baseOutDir, ...
    'v4_2_product_mix_kpis_long.csv'));
write_markdown_report(summary,designTable,baseOutDir);
end

function add_required_paths(v4Root)
lib42=dir(fullfile(v4Root,'library','4.2*'));
assert(~isempty(lib42),'Cannot locate V4_2 library/4.2* directory.');
addpath(v4Root, ...
    fullfile(lib42(1).folder,lib42(1).name), ...
    fullfile(v4Root,'integration','common'));
end

function specs=product_mix_specs(totalMW)
specs=struct('scenarioId',{},'label',{}, ...
    'shareElectricity',{},'shareHydrogen',{},'shareCompute',{}, ...
    'totalProductCapacityMW',{},'powerCableMW',{}, ...
    'electrolyzerMW',{},'computeFacilityMW',{}, ...
    'h2DeliveryKgPerH',{});
% Single-product controls.
specs(end+1)=make_spec("mix_E100", ...
    "Power only",1.00,0.00,0.00,totalMW);
specs(end+1)=make_spec("mix_H100", ...
    "Hydrogen only",0.00,1.00,0.00,totalMW);
specs(end+1)=make_spec("mix_C100", ...
    "Compute only",0.00,0.00,1.00,totalMW);

% Power + hydrogen controls.
specs(end+1)=make_spec("mix_E80_H20", ...
    "Power + hydrogen, power-led",0.80,0.20,0.00,totalMW);
specs(end+1)=make_spec("mix_E60_H40", ...
    "Power + hydrogen",0.60,0.40,0.00,totalMW);
specs(end+1)=make_spec("mix_E40_H60", ...
    "Power + hydrogen, H2-led",0.40,0.60,0.00,totalMW);
specs(end+1)=make_spec("mix_E20_H80", ...
    "Power + hydrogen, high-H2",0.20,0.80,0.00,totalMW);

% Power + compute controls.
specs(end+1)=make_spec("mix_E80_C20", ...
    "Power + compute, power-led",0.80,0.00,0.20,totalMW);
specs(end+1)=make_spec("mix_E60_C40", ...
    "Power + compute, moderate compute",0.60,0.00,0.40,totalMW);
specs(end+1)=make_spec("mix_E40_C60", ...
    "Power + compute, compute-led",0.40,0.00,0.60,totalMW);
specs(end+1)=make_spec("mix_E20_C80", ...
    "Power + compute, high-compute",0.20,0.00,0.80,totalMW);

% Hydrogen + compute controls.
specs(end+1)=make_spec("mix_H80_C20", ...
    "Hydrogen + compute, H2-led",0.00,0.80,0.20,totalMW);
specs(end+1)=make_spec("mix_H60_C40", ...
    "Hydrogen + compute, moderate compute",0.00,0.60,0.40,totalMW);
specs(end+1)=make_spec("mix_H40_C60", ...
    "Hydrogen + compute, compute-led",0.00,0.40,0.60,totalMW);
specs(end+1)=make_spec("mix_H20_C80", ...
    "Hydrogen + compute, high-compute",0.00,0.20,0.80,totalMW);

% Three-product controls.
specs(end+1)=make_spec("mix_E60_H20_C20", ...
    "Triplex power-biased",0.60,0.20,0.20,totalMW);
specs(end+1)=make_spec("mix_E50_H30_C20", ...
    "Triplex power-led",0.50,0.30,0.20,totalMW);
specs(end+1)=make_spec("mix_E40_H30_C30", ...
    "Triplex balanced",0.40,0.30,0.30,totalMW);
specs(end+1)=make_spec("mix_E30_H30_C40", ...
    "Triplex compute-led",0.30,0.30,0.40,totalMW);
specs(end+1)=make_spec("mix_E20_H40_C40", ...
    "Triplex H2/compute-led",0.20,0.40,0.40,totalMW);
specs(end+1)=make_spec("mix_E20_H60_C20", ...
    "Triplex H2-biased",0.20,0.60,0.20,totalMW);
specs(end+1)=make_spec("mix_E20_H20_C60", ...
    "Triplex high-compute",0.20,0.20,0.60,totalMW);
end

function spec=make_spec(id,label,eShare,hShare,cShare,totalMW)
secKWhPerKg=56.77;
spec=struct;
spec.scenarioId=id;
spec.label=label;
spec.shareElectricity=eShare;
spec.shareHydrogen=hShare;
spec.shareCompute=cShare;
spec.totalProductCapacityMW=totalMW;
spec.powerCableMW=totalMW*eShare;
spec.electrolyzerMW=totalMW*hShare;
spec.computeFacilityMW=totalMW*cShare;
spec.h2DeliveryKgPerH=1000*spec.electrolyzerMW/secKWhPerKg;
end

function cfg=build_product_mix_cfg(spec)
cfg=common_config_4_2('interface_smoke');
cfg=v4_apply_unified_capacity_case_4_2(cfg,'M');
cfg.scenario.outputMode=char(spec.scenarioId);
cfg.meta.parameterVersion=[cfg.meta.parameterVersion '_' char(spec.scenarioId)];
cfg.capacity.status.capacityCase=['PRODUCT_MIX_' char(spec.scenarioId)];
cfg.capacity.status.capacityPoolMW=spec.totalProductCapacityMW;
cfg.capacity.status.capacityPoolMeaning=[ ...
    'power export MW + electrolyzer MW + data-center facility MW; ', ...
    'scenario-comparison convention'];

cfg=apply_power_design(cfg,spec.powerCableMW);
cfg=apply_hydrogen_design(cfg,spec.electrolyzerMW,spec.h2DeliveryKgPerH);
cfg=apply_compute_design(cfg,spec.computeFacilityMW);
end

function cfg=apply_power_design(cfg,powerMW)
enabled=powerMW>1e-9;
cfg.assetEnabled.powerExportCable=enabled;
cfg.assetEnabled.converterAndSubstation=enabled;
cfg.capacity.interfaceLimit.powerCableMW=powerMW;
cfg.capacity.installed.powerCableMW=powerMW;
cfg.output.cableSendCapacityMW=powerMW;
cfg.output.gridAcceptMaxMW=powerMW;
end

function cfg=apply_hydrogen_design(cfg,electrolyzerMW,h2DeliveryKgPerH)
enabled=electrolyzerMW>1e-9;
cfg.assetEnabled.PEMElectrolyzer=enabled;
cfg.assetEnabled.hydrogenStorage=enabled;
cfg.capacity.dispatchRequest.hydrogenDeliveryKgPerH= ...
    h2DeliveryKgPerH*double(enabled);
cfg.hydrogen.deliveryDemandKgPerH= ...
    h2DeliveryKgPerH*double(enabled);
cfg.hydrogen.pipeCapacityKgPerH= ...
    min(1800,h2DeliveryKgPerH)*double(enabled);
cfg.hydrogen.shipCapacityKgPerH= ...
    max(0,h2DeliveryKgPerH-cfg.hydrogen.pipeCapacityKgPerH)* ...
    double(enabled);
if enabled
    moduleCount=max(1,ceil(electrolyzerMW/20));
    moduleRatedMW=electrolyzerMW/moduleCount;
    cfg.hydrogen.electrolyzerRatedMW=electrolyzerMW;
    cfg.hydrogen.electrolyzerMinMW=min(20,electrolyzerMW);
    cfg.hydrogen.electrolyzerModuleCount=moduleCount;
    cfg.hydrogen.electrolyzerModuleRatedMW=moduleRatedMW;
    cfg.hydrogen.electrolyzerModuleMinMW=min(4,moduleRatedMW);
    cfg.hydrogen.moduleIndependentCommitment=true;
    cfg.capacity.interfaceLimit.electrolyzerMW=electrolyzerMW;
    cfg.capacity.installed.electrolyzerMW=electrolyzerMW;
else
    cfg.capacity.interfaceLimit.electrolyzerMW=0;
    cfg.capacity.installed.electrolyzerMW=0;
end
end

function cfg=apply_compute_design(cfg,computeMW)
enabled=computeMW>1e-9;
cfg.assetEnabled.subseaCompute=enabled;
cfg.assetEnabled.fiberCable=enabled;
unitFacilityMaxMW=cfg.capacity.installed.computeUnitFacilityMaxMW;
unitITMaxMW=cfg.capacity.installed.computeUnitITMaxMW;
if enabled
    unitCount=max(1,ceil(computeMW/unitFacilityMaxMW));
    cfg.capacity.interfaceLimit.computeFacilityMW=computeMW;
    cfg.capacity.interfaceLimit.fiberServiceMWhCSPerH=computeMW;
    cfg.capacity.installed.computeUnitCount=unitCount;
    cfg.capacity.installed.computeFacilityMW=unitCount*unitFacilityMaxMW;
    cfg.capacity.installed.computeITMW=unitCount*unitITMaxMW;
    cfg.compute.facilityMaxMW=computeMW;
    cfg.compute.itCapacityMW=cfg.capacity.installed.computeITMW;
    cfg.compute.fiberServiceCapacityMWhCSPerH=computeMW;
    cfg.capacity.dispatchRequest.computeMW=computeMW;
else
    cfg.capacity.interfaceLimit.computeFacilityMW=0;
    cfg.capacity.interfaceLimit.fiberServiceMWhCSPerH=0;
    cfg.capacity.installed.computeUnitCount=0;
    cfg.capacity.installed.computeFacilityMW=0;
    cfg.capacity.installed.computeITMW=0;
    cfg.compute.facilityMaxMW=0;
    cfg.compute.facilityMinMW=0;
    cfg.compute.itCapacityMW=0;
    cfg.compute.fiberServiceCapacityMWhCSPerH=0;
    cfg.capacity.dispatchRequest.computeMW=0;
end
end

function value=kpi_value(kpi,indicator)
idx=strcmp(string(kpi.indicator),indicator);
assert(sum(idx)==1,'Missing or duplicate KPI indicator: %s',indicator);
raw=kpi.value(idx);
if isnumeric(raw)
    value=double(raw(1));
else
    value=str2double(string(raw(1)));
end
end

function T=specs_to_table(specs)
n=numel(specs);
scenarioId=strings(n,1);
scenarioLabel=strings(n,1);
shareElectricity=zeros(n,1);
shareHydrogen=zeros(n,1);
shareCompute=zeros(n,1);
totalProductCapacityMW=zeros(n,1);
powerCableMW=zeros(n,1);
electrolyzerMW=zeros(n,1);
computeFacilityMW=zeros(n,1);
h2DeliveryKgPerH=zeros(n,1);
for i=1:n
    scenarioId(i)=specs(i).scenarioId;
    scenarioLabel(i)=specs(i).label;
    shareElectricity(i)=specs(i).shareElectricity;
    shareHydrogen(i)=specs(i).shareHydrogen;
    shareCompute(i)=specs(i).shareCompute;
    totalProductCapacityMW(i)=specs(i).totalProductCapacityMW;
    powerCableMW(i)=specs(i).powerCableMW;
    electrolyzerMW(i)=specs(i).electrolyzerMW;
    computeFacilityMW(i)=specs(i).computeFacilityMW;
    h2DeliveryKgPerH(i)=specs(i).h2DeliveryKgPerH;
end
T=table(scenarioId,scenarioLabel,shareElectricity,shareHydrogen, ...
    shareCompute,totalProductCapacityMW,powerCableMW,electrolyzerMW, ...
    computeFacilityMW,h2DeliveryKgPerH);
end

function write_markdown_report(summary,designTable,outDir)
path=fullfile(outDir,'v4_2_product_mix_report.md');
fid=fopen(path,'w','n','UTF-8');
assert(fid>0,'Cannot write product mix report.');
cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'# V4_2 product mix scenario report\n\n');
fprintf(fid,['All cases use the same 420 MW equivalent product-channel ', ...
    'capacity pool. This is a scenario-comparison convention, not an ', ...
    'engineering optimum.\n\n']);
fprintf(fid,'Scenario count: %d\n\n',height(summary));
fprintf(fid,'## Design cases\n\n');
fprintf(fid,['| Scenario | Label | E share | H2 share | Compute share | ', ...
    'Cable MW | Electrolyzer MW | Compute request MW |\n']);
fprintf(fid,'|---|---|---:|---:|---:|---:|---:|---:|\n');
for i=1:height(designTable)
    fprintf(fid,'| %s | %s | %.0f%% | %.0f%% | %.0f%% | %.1f | %.1f | %.1f |\n', ...
        char(designTable.scenarioId(i)),char(designTable.scenarioLabel(i)), ...
        100*designTable.shareElectricity(i), ...
        100*designTable.shareHydrogen(i), ...
        100*designTable.shareCompute(i), ...
        designTable.powerCableMW(i),designTable.electrolyzerMW(i), ...
        designTable.computeFacilityMW(i));
end
fprintf(fid,'\n## Simulation summary\n\n');
fprintf(fid,['| Scenario | Electricity MWh | H2 kg | Compute MWh-CS | ', ...
    'Spill MWh | Utilization | Revenue CNY | Net cost CNY | ', ...
    'Lifecycle NPV CNY | Residual MW |\n']);
fprintf(fid,'|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for i=1:height(summary)
    fprintf(fid,['| %s | %.1f | %.1f | %.1f | %.1f | %.1f%% | ', ...
        '%.0f | %.0f | %.0f | %.3e |\n'], ...
        char(summary.scenarioId(i)), ...
        summary.electricityDeliveredMWh(i), ...
        summary.h2DeliveredKg(i), ...
        summary.computeDeliveredMWhCS(i), ...
        summary.spillEnergyMWh(i), ...
        100*summary.renewableUtilization(i), ...
        summary.totalRevenueCNY(i), ...
        summary.economicNetCostCNY(i), ...
        summary.lifecycleNPVAfterPenaltyCNY(i), ...
        summary.maxAbsBusResidualMW(i));
end
fprintf(fid,['\nNote: 4.8 values remain public-proxy / uncalibrated ', ...
    'scenario outputs. Do not use them as bankable NPV, LCOE or LCOH.\n']);
end
