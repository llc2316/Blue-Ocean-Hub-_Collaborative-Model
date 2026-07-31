function [summary,designTable,results] = ...
    run_c5_product_mix_48h_scenarios(caseIds,outputDir,policy)
%RUN_C5_PRODUCT_MIX_48H_SCENARIOS Run 22 C5 allocation strategies.
%
% All cases share the same 48 h weather/task sequence and the same physical
% V5 asset capacities. E/H/C specify full-horizon cable-send,
% electrolyzer-input and flexible-compute-input energy shares. Firm/base
% compute is outside the ratio denominator. These are not
% nameplate-capacity shares. This short test excludes annual fixed O&M,
% CAPEX, lifetime degradation and lifecycle environmental optimization.
%
% Examples:
%   run_c5_product_mix_48h_scenarios("all")
%   p=struct('maxENSMWh',0,'minRenewableUtilization',0.6);
%   run_c5_product_mix_48h_scenarios( ...
%       ["mix_E60_C40","mix_E40_H30_C30"],"",p)

thisDir=fileparts(mfilename('fullpath'));
c5Root=fileparts(fileparts(thisDir));
addpath(fullfile(c5Root,'5.1场景设计','code'),thisDir);
c5_add_v5_model_paths();

if nargin<1 || isempty(caseIds), caseIds="all"; end
if nargin<2 || strlength(string(outputDir))==0
    outputDir=fullfile(c5Root,'5.3对比方案与模型最优策略', ...
        'results','legacy_22');
end
if nargin<3 || isempty(policy), policy=struct; end
policy=normalize_policy(policy);

designTable=c5_product_mix_specs();
% The 48 h suite remains the frozen 22-case operating-share study.
% Asset-level annual baselines are handled only by the annual runner.
designTable=designTable( ...
    designTable.strategyClass=="DISPATCH_SHARE_POLICY",:);
designTable=select_cases(designTable,caseIds);

scenario=c5_build_all_channel_48h_scenario();
baseCfg=scenario.config;
baseCfg.objective.maxENSMWh=policy.maxENSMWh;
baseCfg.objective.maxNetGHGKgCO2e=Inf;
baseCfg.objective.minRenewableUtilization= ...
    policy.minRenewableUtilization;
baseCfg.objective.temporalTieBreak=policy.temporalTieBreak;

[sourceInput,sourceDetail]= ...
    v5_source_adapter(baseCfg,scenario.input.sourceCase);
baseInput=rmfield(scenario.input,'sourceCase');
baseInput=merge_input(baseInput,sourceInput);

n=height(designTable);
results=cell(n,1);
gfmGateTables=cell(n,1);
status=strings(n,1);
auditPass=false(n,1);
exitflag=nan(n,1);
commonCableCapacityMW=zeros(n,1);
commonElectrolyzerCapacityMW=zeros(n,1);
commonComputeCapacityMW=zeros(n,1);
eAvailableMWh=nan(n,1);
eElectricityInputMWh=nan(n,1);
eHydrogenInputMWh=nan(n,1);
eTotalComputeInputMWh=nan(n,1);
eFlexibleComputeInputMWh=nan(n,1);
realizedElectricityInputShare=nan(n,1);
realizedHydrogenInputShare=nan(n,1);
realizedComputeInputShare=nan(n,1);
maxShareDeviation=nan(n,1);
eCableReceivedMWh=nan(n,1);
h2DeliveredKg=nan(n,1);
eComputeServiceMWhCS=nan(n,1);
eCurtailmentMWh=nan(n,1);
renewableUtilization=nan(n,1);
ensMWh=nan(n,1);
outputRevenueCNY=nan(n,1);
operatingCostCNY=nan(n,1);
economicNetCostCNY=nan(n,1);
minimumGfmUpwardPowerHeadroomMW=nan(n,1);
minimumGfmUpwardEnergyHeadroomMWh=nan(n,1);
minimumGfmDownwardPowerHeadroomMW=nan(n,1);
minimumGfmDownwardEnergyHeadroomMWh=nan(n,1);
simultaneousCurtailmentCriticalENSCount=nan(n,1);
actualPeakCableSendMW=nan(n,1);
actualPeakElectrolyzerMW=nan(n,1);
actualPeakComputeFacilityMW=nan(n,1);

for i=1:n
    spec=designTable(i,:);
    cfg=baseCfg;
    cfg.meta.parameterVersion=['v5_48h_energy_mix_' ...
        char(spec.scenarioId)];
    in=apply_strategy(baseInput,cfg,spec,policy);
    commonCableCapacityMW(i)=cfg.output.cableSendCapacityMW;
    commonElectrolyzerCapacityMW(i)= ...
        cfg.hydrogen.electrolyzerRatedMW;
    commonComputeCapacityMW(i)=cfg.compute.facilityMaxMW;
    try
        result=run_v5_model(in,cfg);
        result.chapter5=struct( ...
            'design',spec, ...
            'policy',policy, ...
            'sourceDetailLocation','TOP_LEVEL_MAT_SOURCE_DETAIL', ...
            'testScenarioId',scenario.meta.scenarioId, ...
            'comparisonScope','48H_OPERATING_DISPATCH_ONLY', ...
            'parameterStatus','[假设值，待企业调研校准]');
        results{i}=result;
        auditPass(i)=logical(result.audit.pass);
        exitflag(i)=result.meta.exitflag;
        eAvailableMWh(i)=result.kpi.eAvailableMWh;
        eElectricityInputMWh(i)=result.kpi.eElectricityInputMWh;
        eHydrogenInputMWh(i)=result.kpi.eHydrogenInputMWh;
        eTotalComputeInputMWh(i)=result.kpi.eTotalComputeInputMWh;
        eFlexibleComputeInputMWh(i)= ...
            result.kpi.eFlexibleComputeInputMWh;
        realizedElectricityInputShare(i)= ...
            result.kpi.realizedElectricityInputShare;
        realizedHydrogenInputShare(i)= ...
            result.kpi.realizedHydrogenInputShare;
        realizedComputeInputShare(i)= ...
            result.kpi.realizedComputeInputShare;
        maxShareDeviation(i)=max(abs([ ...
            realizedElectricityInputShare(i)- ...
                spec.targetElectricityInputShare, ...
            realizedHydrogenInputShare(i)- ...
                spec.targetHydrogenInputShare, ...
            realizedComputeInputShare(i)- ...
                spec.targetComputeInputShare]));
        eCableReceivedMWh(i)=result.kpi.eCableReceivedMWh;
        h2DeliveredKg(i)=result.kpi.h2DeliveredKg;
        eComputeServiceMWhCS(i)=result.kpi.eComputeServiceMWhCS;
        eCurtailmentMWh(i)=result.kpi.eCurtailmentMWh;
        renewableUtilization(i)=result.kpi.renewableUtilization;
        ensMWh(i)=result.kpi.ensMWh;
        outputRevenueCNY(i)=result.kpi.outputRevenueCNY;
        operatingCostCNY(i)=result.kpi.operatingCostCNY;
        economicNetCostCNY(i)=result.kpi.economicNetCostCNY;
        minimumGfmUpwardPowerHeadroomMW(i)= ...
            result.audit.minimumGfmUpwardPowerHeadroomMW;
        minimumGfmUpwardEnergyHeadroomMWh(i)= ...
            result.audit.minimumGfmUpwardEnergyHeadroomMWh;
        minimumGfmDownwardPowerHeadroomMW(i)= ...
            result.audit.minimumGfmDownwardPowerHeadroomMW;
        minimumGfmDownwardEnergyHeadroomMWh(i)= ...
            result.audit.minimumGfmDownwardEnergyHeadroomMWh;
        simultaneousCurtailmentCriticalENSCount(i)= ...
            result.audit.simultaneousCurtailmentCriticalENSCount;
        actualPeakCableSendMW(i)=max(result.dispatch.pCableSendMW);
        actualPeakElectrolyzerMW(i)= ...
            max(result.dispatch.pElectrolyzerMW);
        actualPeakComputeFacilityMW(i)= ...
            max(result.dispatch.pComputeFacilityMW);
        gate=c5_select_gfm_dynamic_gate_points(result);
        strategyId=repmat(spec.scenarioId,height(gate),1);
        gfmGateTables{i}=addvars(gate,strategyId,'Before',1);
        policyPass=simultaneousCurtailmentCriticalENSCount(i)==0 && ...
            maxShareDeviation(i)<=policy.shareTolerance+1e-6;
        if exitflag(i)>0 && auditPass(i) && policyPass
            status(i)="PASS";
        elseif auditPass(i) && policyPass
            status(i)="FEASIBLE_NOT_PROVEN";
        else
            status(i)="FAIL_AUDIT_OR_POLICY";
        end
    catch ME
        errorId=string(ME.identifier);
        if strlength(errorId)==0, errorId="UNIDENTIFIED_ERROR"; end
        errorMessage=regexprep(strtrim(string(ME.message)),'\s+',' ');
        status(i)="FAIL: "+errorId+" "+errorMessage;
        results{i}=ME;
    end
end

testScenarioId=repmat(string(scenario.meta.scenarioId),n,1);
horizonH=repmat(48,n,1);
shareTolerance=repmat(policy.shareTolerance,n,1);
maxENSLimitMWh=repmat(policy.maxENSMWh,n,1);
minRenewableUtilizationLimit=repmat( ...
    policy.minRenewableUtilization,n,1);
summary=[designTable,table(testScenarioId,horizonH,shareTolerance, ...
    maxENSLimitMWh,minRenewableUtilizationLimit, ...
    commonCableCapacityMW,commonElectrolyzerCapacityMW, ...
    commonComputeCapacityMW,status,auditPass, ...
    exitflag,eAvailableMWh,eElectricityInputMWh,eHydrogenInputMWh, ...
    eTotalComputeInputMWh,eFlexibleComputeInputMWh, ...
    realizedElectricityInputShare, ...
    realizedHydrogenInputShare,realizedComputeInputShare, ...
    maxShareDeviation,eCableReceivedMWh,h2DeliveredKg, ...
    eComputeServiceMWhCS,eCurtailmentMWh,renewableUtilization, ...
    ensMWh,outputRevenueCNY,operatingCostCNY,economicNetCostCNY, ...
    minimumGfmUpwardPowerHeadroomMW, ...
    minimumGfmUpwardEnergyHeadroomMWh, ...
    minimumGfmDownwardPowerHeadroomMW, ...
    minimumGfmDownwardEnergyHeadroomMWh, ...
    simultaneousCurtailmentCriticalENSCount,actualPeakCableSendMW, ...
    actualPeakElectrolyzerMW,actualPeakComputeFacilityMW)];
phaseSummary=c5_summarize_product_mix_48h_phases( ...
    results,designTable,scenario);

if strlength(string(outputDir))>0
    outputDir=char(string(outputDir));
    if ~isfolder(outputDir), mkdir(outputDir); end
    writetable(designTable, ...
        fullfile(outputDir,'v5_product_mix_48h_design.csv'));
    writetable(summary, ...
        fullfile(outputDir,'v5_product_mix_48h_summary.csv'));
    writetable(phaseSummary, ...
        fullfile(outputDir,'v5_product_mix_48h_phase_summary.csv'));
    populated=~cellfun(@isempty,gfmGateTables);
    if any(populated)
        gfmDynamicGatePoints=vertcat(gfmGateTables{populated});
        writetable(gfmDynamicGatePoints,fullfile(outputDir, ...
            'v5_product_mix_48h_gfm_dynamic_gate_points.csv'));
    else
        gfmDynamicGatePoints=table;
    end
    save(fullfile(outputDir,'v5_product_mix_48h_results.mat'), ...
        'summary','designTable','results','sourceDetail','scenario', ...
        'policy','phaseSummary','gfmDynamicGatePoints','-v7.3');
end
end

function policy=normalize_policy(policy)
policy=struct( ...
    'shareTolerance',field_or(policy,'shareTolerance',0.02), ...
    'minimumAllocatedInputMWh',field_or( ...
        policy,'minimumAllocatedInputMWh',1), ...
    'maxENSMWh',field_or(policy,'maxENSMWh',0), ...
    'minRenewableUtilization',field_or( ...
        policy,'minRenewableUtilization',0), ...
    'temporalTieBreak',string(field_or( ...
        policy,'temporalTieBreak','none')));
assert(policy.shareTolerance>=0 && policy.shareTolerance<0.5, ...
    'shareTolerance must be in [0,0.5).');
assert(policy.minimumAllocatedInputMWh>=0, ...
    'minimumAllocatedInputMWh must be nonnegative.');
assert(policy.maxENSMWh>=0, ...
    'maxENSMWh must be nonnegative.');
assert(policy.minRenewableUtilization>=0 && ...
    policy.minRenewableUtilization<=1, ...
    'minRenewableUtilization must be in [0,1].');
assert(any(strcmpi(policy.temporalTieBreak,["none","deferCurtailment"])), ...
    'Unsupported temporalTieBreak.');
end

function designTable=select_cases(designTable,caseIds)
if ischar(caseIds) || (isstring(caseIds) && isscalar(caseIds))
    if strcmpi(string(caseIds),"all")
        return
    end
    selected=designTable.scenarioId==string(caseIds);
else
    requested=string(caseIds(:));
    selected=ismember(designTable.scenarioId,requested);
    missing=setdiff(requested,designTable.scenarioId,'stable');
    assert(isempty(missing),'Unknown product-mix case(s): %s', ...
        strjoin(missing,", "));
end
designTable=designTable(selected,:);
assert(~isempty(designTable),'No product-mix case selected.');
end

function in=apply_strategy(baseInput,cfg,spec,policy)
in=baseInput;
in.pComputeBaseDemandMW=min( ...
    in.pComputeBaseDemandMW,cfg.compute.facilityMaxMW);
remaining=max(0,cfg.compute.facilityMaxMW- ...
    in.pComputeBaseDemandMW);
in.pComputeFlexibleMaxMW=min(in.pComputeFlexibleMaxMW,remaining);
in.cableSendLimitMW=min( ...
    in.cableSendLimitMW,cfg.output.cableSendCapacityMW);
in.gridAcceptLimitMW=min( ...
    in.gridAcceptLimitMW,cfg.output.gridAcceptCapacityMW);
in.h2PipeLimitKgPerH=min( ...
    in.h2PipeLimitKgPerH,cfg.hydrogen.pipeCapacityKgPerH);
in.h2ShipLimitKgPerH=min( ...
    in.h2ShipLimitKgPerH,cfg.hydrogen.shipCapacityKgPerH);
in.h2PipeMinimumKgPerH(:)=0;
in.h2ShipMinimumKgPerH(:)=0;
in.availability.h2Power(:)=0;

in.productMix=struct( ...
    'enabled',true, ...
    'targetElectricityShare',spec.targetElectricityInputShare, ...
    'targetHydrogenShare',spec.targetHydrogenInputShare, ...
    'targetComputeShare',spec.targetComputeInputShare, ...
    'shareTolerance',policy.shareTolerance, ...
    'minimumAllocatedInputMWh', ...
        policy.minimumAllocatedInputMWh);
end

function out=merge_input(out,addition)
names=fieldnames(addition);
for k=1:numel(names)
    out.(names{k})=addition.(names{k});
end
end

function value=field_or(s,name,defaultValue)
if isfield(s,name), value=s.(name); else, value=defaultValue; end
end
