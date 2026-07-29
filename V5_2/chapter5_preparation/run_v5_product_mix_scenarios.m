function [summary,designTable,results] = ...
    run_v5_product_mix_scenarios(caseIds,hours,outputDir,scenarioMode)
%RUN_V5_PRODUCT_MIX_SCENARIOS V5 adapter for the Chapter-5 mix grid.
%
% This runner compares OPERATING DISPATCH under one common synthetic
% resource sequence and common price assumptions. It does not calculate
% lifecycle CAPEX, NPV, IRR, LCOE/LCOH, dynamic GFM stability, ammonia
% shipping, or weather-window vessel logistics.
%
% Examples:
%   run_v5_product_mix_scenarios(["mix_E100","mix_H100"],24)
%   run_v5_product_mix_scenarios("all",168,"outputs/chapter5_mix")
%   run_v5_product_mix_scenarios("all",48,"outputs/chapter5_mix_48h", ...
%       "all_channel_weather_task_48h")
%
% Project-scale capacities and prices used by mechanism_test are
% [假设值，待企业调研校准].

thisDir=fileparts(mfilename('fullpath'));
v5Root=fileparts(thisDir);
addpath(v5Root,fullfile(v5Root,'config'),fullfile(v5Root,'source'));

if nargin<1 || isempty(caseIds)
    caseIds=["mix_E100","mix_H100","mix_C100","mix_E40_H30_C30"];
end
if nargin<2 || isempty(hours)
    hours=24;
end
if nargin<3
    outputDir="";
end
if nargin<4 || isempty(scenarioMode)
    scenarioMode="baseline_snapshot";
end
scenarioMode=lower(string(scenarioMode));
validateattributes(hours,{'numeric'}, ...
    {'scalar','real','finite','integer','positive'});

designTable=v5_product_mix_specs(420);
if ischar(caseIds) || (isstring(caseIds) && isscalar(caseIds))
    if strcmpi(string(caseIds),"all")
        selected=true(height(designTable),1);
    else
        selected=designTable.scenarioId==string(caseIds);
    end
else
    requested=string(caseIds(:));
    selected=ismember(designTable.scenarioId,requested);
    missing=setdiff(requested,designTable.scenarioId,'stable');
    assert(isempty(missing),'Unknown product-mix case(s): %s', ...
        strjoin(missing,", "));
end
designTable=designTable(selected,:);
assert(~isempty(designTable),'No product-mix case selected.');

[baseCfg,baseInput,sourceDetail,testScenarioId]= ...
    build_common_scenario(v5Root,scenarioMode,hours);

n=height(designTable);
results=cell(n,1);
status=strings(n,1);
auditPass=false(n,1);
exitflag=nan(n,1);
eAvailableMWh=nan(n,1);
eCableReceivedMWh=nan(n,1);
h2DeliveredKg=nan(n,1);
eComputeServiceMWhCS=nan(n,1);
eCurtailmentMWh=nan(n,1);
curtailmentRate=nan(n,1);
renewableUtilization=nan(n,1);
ensMWh=nan(n,1);
outputRevenueCNY=nan(n,1);
operatingCostCNY=nan(n,1);
economicNetCostCNY=nan(n,1);
netGHGKgCO2e=nan(n,1);
minimumGfmPowerHeadroomMW=nan(n,1);
minimumGfmEnergyHeadroomMWh=nan(n,1);

for i=1:n
    spec=designTable(i,:);
    cfg=apply_design(baseCfg,spec);
    in=adapt_scenario_input(cfg,baseInput,spec,scenarioMode);
    try
        result=run_v5_model(in,cfg);
        result.chapter5=struct( ...
            'design',spec, ...
            'sourceDetail',sourceDetail, ...
            'testScenarioId',testScenarioId, ...
            'comparisonScope','OPERATING_DISPATCH_MECHANISM_ONLY', ...
            'parameterStatus','[假设值，待企业调研校准]');
        results{i}=result;
        status(i)="PASS";
        auditPass(i)=logical(result.audit.pass);
        exitflag(i)=result.meta.exitflag;
        eAvailableMWh(i)=result.kpi.eAvailableMWh;
        eCableReceivedMWh(i)=result.kpi.eCableReceivedMWh;
        h2DeliveredKg(i)=result.kpi.h2DeliveredKg;
        eComputeServiceMWhCS(i)=result.kpi.eComputeServiceMWhCS;
        eCurtailmentMWh(i)=result.kpi.eCurtailmentMWh;
        curtailmentRate(i)=result.kpi.curtailmentRate;
        renewableUtilization(i)=result.kpi.renewableUtilization;
        ensMWh(i)=result.kpi.ensMWh;
        outputRevenueCNY(i)=result.kpi.outputRevenueCNY;
        operatingCostCNY(i)=result.kpi.operatingCostCNY;
        economicNetCostCNY(i)=result.kpi.economicNetCostCNY;
        netGHGKgCO2e(i)=result.kpi.netGHGKgCO2e;
        minimumGfmPowerHeadroomMW(i)= ...
            result.audit.minimumGfmPowerHeadroomMW;
        minimumGfmEnergyHeadroomMWh(i)= ...
            result.audit.minimumGfmEnergyHeadroomMWh;
    catch ME
        status(i)="FAIL: "+string(ME.identifier)+" "+string(ME.message);
        results{i}=ME;
    end
end

testScenarioId=repmat(string(testScenarioId),n,1);
horizonH=repmat(double(hours),n,1);
summary=[designTable,table(testScenarioId,horizonH,status,auditPass, ...
    exitflag,eAvailableMWh, ...
    eCableReceivedMWh,h2DeliveredKg,eComputeServiceMWhCS, ...
    eCurtailmentMWh,curtailmentRate,renewableUtilization,ensMWh, ...
    outputRevenueCNY,operatingCostCNY,economicNetCostCNY, ...
    netGHGKgCO2e,minimumGfmPowerHeadroomMW, ...
    minimumGfmEnergyHeadroomMWh)];

if strlength(string(outputDir))>0
    outputDir=char(string(outputDir));
    if ~isfolder(outputDir), mkdir(outputDir); end
    writetable(designTable,fullfile(outputDir,'v5_product_mix_design.csv'));
    writetable(summary,fullfile(outputDir,'v5_product_mix_summary.csv'));
    save(fullfile(outputDir,'v5_product_mix_results.mat'), ...
        'summary','designTable','results','sourceDetail');
end
end

function [baseCfg,baseInput,sourceDetail,testScenarioId]= ...
    build_common_scenario(v5Root,scenarioMode,hours)
switch scenarioMode
    case "baseline_snapshot"
        baseCfg=v5_default_config('mechanism_test');
        sourceCase=struct( ...
            'mode','v4_public_baseline_snapshot', ...
            'hours',double(hours), ...
            'startTimeH',0, ...
            'parameterSetId', ...
                'V5_CH5_COMMON_SYNTHETIC_RESOURCE_ASSUMPTION_V1');
        [baseInput,sourceDetail]=v5_source_adapter(baseCfg,sourceCase);
        testScenarioId="V5_PRODUCT_MIX_BASELINE_SNAPSHOT_"+hours+"H";
    case "all_channel_weather_task_48h"
        assert(hours==48, ...
            'all_channel_weather_task_48h requires a 48 h horizon.');
        addpath(fullfile(v5Root,'scenarios'));
        scenario=v5_build_all_channel_weather_task_scenario();
        baseCfg=scenario.config;
        rawInput=scenario.input;
        [sourceInput,sourceDetail]= ...
            v5_source_adapter(baseCfg,rawInput.sourceCase);
        rawInput=rmfield(rawInput,'sourceCase');
        baseInput=merge_input(rawInput,sourceInput);
        testScenarioId=string(scenario.meta.scenarioId);
    otherwise
        error('Unsupported product-mix scenarioMode: %s',scenarioMode);
end
end

function cfg=apply_design(baseCfg,spec)
cfg=baseCfg;
cfg.meta.parameterVersion=['v5_ch5_product_mix_' char(spec.scenarioId)];
cfg.objective.temporalTieBreak='none';
% Hold firm-load reliability constant across product-channel designs.
% Otherwise a high-value flexible channel can make small ENS differences
% appear in an operating-value comparison and confound the attribution.
cfg.objective.maxENSMWh=0;

cfg.output.cableSendCapacityMW=spec.powerCableMW;
cfg.output.gridAcceptCapacityMW=spec.powerCableMW;

if spec.electrolyzerMW>1e-9
    moduleCount=max(1,ceil(spec.electrolyzerMW/20));
    moduleRatedMW=spec.electrolyzerMW/moduleCount;
    cfg.hydrogen.electrolyzerRatedMW=spec.electrolyzerMW;
    cfg.hydrogen.moduleCount=moduleCount;
    cfg.hydrogen.moduleRatedMW=moduleRatedMW;
    cfg.hydrogen.moduleMinMW=min(4,moduleRatedMW);
    cfg.hydrogen.rampUpMWPerH=266.4*spec.electrolyzerMW;
    cfg.hydrogen.rampDownMWPerH=266.4*spec.electrolyzerMW;
    cfg.hydrogen.pipeCapacityKgPerH= ...
        min(1800,spec.h2RatedProductionKgPerH);
    cfg.hydrogen.shipCapacityKgPerH= ...
        max(0,spec.h2RatedProductionKgPerH- ...
        cfg.hydrogen.pipeCapacityKgPerH);
else
    % Current V5 validation requires positive electrolysis nameplate data.
    % The zero-asset alternative is represented by zero input availability
    % and zero delivery limits; this is dispatch-equivalent but not a
    % lifecycle-CAPEX representation.
    cfg.hydrogen.pipeCapacityKgPerH=0;
    cfg.hydrogen.shipCapacityKgPerH=0;
end

if spec.computeFacilityMW>1e-9
    unitMax=baseCfg.compute.moduleFacilityMaxMW;
    cfg.compute.moduleCount=max(1,ceil(spec.computeFacilityMW/unitMax));
    cfg.compute.facilityMaxMW=spec.computeFacilityMW;
    cfg.compute.rampUpMWPerH=spec.computeFacilityMW;
    cfg.compute.rampDownMWPerH=spec.computeFacilityMW;
end
end

function in=adapt_scenario_input(cfg,baseInput,spec,scenarioMode)
N=numel(baseInput.timeH);
powerEnabled=double(spec.powerCableMW>1e-9);
hydrogenEnabled=double(spec.electrolyzerMW>1e-9);
computeEnabled=double(spec.computeFacilityMW>1e-9);

in=baseInput;
if scenarioMode=="baseline_snapshot"
    in.pCommonAuxDemandMW=cfg.internal.commonAuxDemandMW;
    in.pPostPOILossMW=cfg.internal.postPOILossMW;
    in.pMarineDemandMW=cfg.output.marineDemandMW;
    in.pComputeBaseDemandMW=zeros(N,1);
    in.pComputeFlexibleMaxMW=spec.computeFacilityMW*ones(N,1);
    in.electricityPriceCNYPerMWh= ...
        cfg.economic.electricityPriceCNYPerMWhReceived*ones(N,1);
    in.hydrogenPriceCNYPerKg= ...
        cfg.economic.hydrogenPriceCNYPerKgDelivered*ones(N,1);
    in.computePriceCNYPerMWhCS= ...
        cfg.economic.computePriceCNYPerMWhCS*ones(N,1);
    in.marineServiceValueCNYPerMWh= ...
        cfg.economic.marineServiceValueCNYPerMWh*ones(N,1);
    in.cableSendLimitMW=spec.powerCableMW*ones(N,1);
    in.gridAcceptLimitMW=spec.powerCableMW*ones(N,1);
    in.h2PipeLimitKgPerH= ...
        cfg.hydrogen.pipeCapacityKgPerH*ones(N,1);
    in.h2ShipLimitKgPerH= ...
        cfg.hydrogen.shipCapacityKgPerH*ones(N,1);
    in.h2PipeMinimumKgPerH=zeros(N,1);
    in.h2ShipMinimumKgPerH=zeros(N,1);
    in.pue=cfg.compute.pue*ones(N,1);
    in.availability=struct( ...
        'bess',1, ...
        'electrolyzer',hydrogenEnabled, ...
        'h2Storage',hydrogenEnabled, ...
        'compute',computeEnabled, ...
        'cable',powerEnabled, ...
        'h2Pipe', ...
            hydrogenEnabled*double(cfg.hydrogen.pipeCapacityKgPerH>0), ...
        'h2Ship', ...
            hydrogenEnabled*double(cfg.hydrogen.shipCapacityKgPerH>0), ...
        'h2Power',0);
    in.initial=struct( ...
        'bessEnergyMWh',cfg.bess.socInitial*cfg.bess.energyMWh, ...
        'h2InventoryKg',0, ...
        'electrolyzerOnlineModules',0, ...
        'electrolyzerPowerMW',0, ...
        'computePowerMW',0, ...
        'h2PowerMW',0);
else
    originalBase=in.pComputeBaseDemandMW;
    in.pComputeBaseDemandMW= ...
        computeEnabled*min(originalBase,spec.computeFacilityMW);
    remainingCompute=max(0,spec.computeFacilityMW- ...
        in.pComputeBaseDemandMW);
    in.pComputeFlexibleMaxMW=computeEnabled* ...
        min(in.pComputeFlexibleMaxMW,remainingCompute);
    in.cableSendLimitMW=powerEnabled* ...
        min(in.cableSendLimitMW,spec.powerCableMW);
    in.gridAcceptLimitMW=powerEnabled* ...
        min(in.gridAcceptLimitMW,spec.powerCableMW);
    in.h2PipeLimitKgPerH=hydrogenEnabled* ...
        min(in.h2PipeLimitKgPerH,cfg.hydrogen.pipeCapacityKgPerH);
    in.h2ShipLimitKgPerH=hydrogenEnabled* ...
        min(in.h2ShipLimitKgPerH,cfg.hydrogen.shipCapacityKgPerH);
    in.h2PipeMinimumKgPerH=zeros(N,1);
    in.h2ShipMinimumKgPerH=zeros(N,1);
    in.availability.electrolyzer= ...
        in.availability.electrolyzer*hydrogenEnabled;
    in.availability.h2Storage= ...
        in.availability.h2Storage*hydrogenEnabled;
    in.availability.compute=in.availability.compute*computeEnabled;
    in.availability.cable=in.availability.cable*powerEnabled;
    in.availability.h2Pipe=in.availability.h2Pipe* ...
        hydrogenEnabled*double(cfg.hydrogen.pipeCapacityKgPerH>0);
    in.availability.h2Ship=in.availability.h2Ship* ...
        hydrogenEnabled*double(cfg.hydrogen.shipCapacityKgPerH>0);
    in.availability.h2Power(:)=0;
    if ~hydrogenEnabled
        in.initial.electrolyzerOnlineModules=0;
        in.initial.electrolyzerPowerMW=0;
        in.initial.h2InventoryKg=0;
    end
    if ~computeEnabled
        in.initial.computePowerMW=0;
    end
end
end

function out=merge_input(out,addition)
names=fieldnames(addition);
for k=1:numel(names)
    out.(names{k})=addition.(names{k});
end
end
