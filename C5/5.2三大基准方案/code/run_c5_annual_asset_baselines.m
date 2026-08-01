function [summary,monthlySummary,results] = ...
    run_c5_annual_asset_baselines( ...
    caseIds,outputDir,policy)
%RUN_C5_ANNUAL_ASSET_BASELINES Monthly rolling pure E/H/C baselines.
%
% All 8760 hourly records are retained. BESS energy, hydrogen inventory,
% electrolyzer commitment/power and compute power are passed between
% months. BESS and hydrogen inventory are cyclic within every calendar
% month, so the rolling approximation cannot create artificial year-end
% inventory value. Legacy share-policy cases enforce product shares every
% month. Asset-level baseline/comparison cases instead switch product
% assets explicitly and use unconstrained economic product allocation.
% The secondary min-curtailment solve is disabled; the economic primary
% objective is solved once per month.

thisDir=fileparts(mfilename('fullpath'));
c5Root=fileparts(fileparts(thisDir));
addpath(fullfile(c5Root,'5.1场景设计','code'), ...
    fullfile(c5Root,'5.3对比方案与模型最优策略','code'),thisDir);
c5_add_v5_model_paths();

if nargin<1 || isempty(caseIds)
    caseIds=["baseline_E_asset_only","baseline_H_asset_only", ...
        "baseline_C_asset_only"];
end
if nargin<2 || strlength(string(outputDir))==0
    outputDir=fullfile(c5Root,'5.2三大基准方案', ...
        'results','recomputed');
end
if nargin<3 || isempty(policy), policy=struct; end
policy=normalize_policy(policy);

designTable=select_cases(c5_product_mix_specs(),caseIds);
scenario=c5_build_annual_2025_scenario();
cfgBase=scenario.config;
cfgBase.objective.maxENSMWh=policy.maxENSMWh;
cfgBase.objective.minRenewableUtilization=0;
cfgBase.objective.maxNetGHGKgCO2e=Inf;
cfgBase.objective.tieBreak='none';
cfgBase.objective.temporalTieBreak='none';
cfgBase.solver.maxTimeS=policy.maxTimeS;
cfgBase.bess.terminalRule='cyclic';
cfgBase.hydrogen.terminalRule='cyclic';

[sourceInput,sourceDetail]= ...
    v5_source_adapter(cfgBase,scenario.input.sourceCase);
baseInput=rmfield(scenario.input,'sourceCase');
baseInput=merge_input(baseInput,sourceInput);
timeUTC=scenario.hourly.timeUTC;
monthNumber=month(timeUTC);

annualInput=scenario.hourly;
annualInput.pSourceAvailableMW=sourceInput.pSourceAvailableMW;
annualInput.pSourceAuxMW=sourceInput.pSourceAuxMW;

n=height(designTable);
results=cell(n,1);
monthlyTables=cell(n,1);
status=strings(n,1);
auditPass=false(n,1);
allMonthsOptimal=false(n,1);
runtimeS=zeros(n,1);
eAvailableMWh=zeros(n,1);
eSourceUsedMWh=zeros(n,1);
eElectricityInputMWh=zeros(n,1);
eHydrogenInputMWh=zeros(n,1);
eFlexibleComputeInputMWh=zeros(n,1);
eCableReceivedMWh=zeros(n,1);
h2DeliveredKg=zeros(n,1);
eComputeServiceMWhCS=zeros(n,1);
eCurtailmentMWh=zeros(n,1);
ensMWh=zeros(n,1);
outputRevenueCNY=zeros(n,1);
operatingCostCNY=zeros(n,1);
economicNetCostCNY=zeros(n,1);
netGHGKgCO2e=zeros(n,1);
minimumGfmUpwardPowerHeadroomMW=nan(n,1);
minimumGfmUpwardEnergyHeadroomMWh=nan(n,1);
minimumGfmDownwardPowerHeadroomMW=nan(n,1);
minimumGfmDownwardEnergyHeadroomMWh=nan(n,1);
simultaneousCurtailmentCriticalENSCount=zeros(n,1);
terminalBessEnergyMWh=nan(n,1);
terminalH2InventoryKg=nan(n,1);

for i=1:n
    spec=designTable(i,:);
    state=baseInput.initial;
    monthResults=cell(12,1);
    monthRows=cell(12,1);
    caseTimer=tic;
    caseFailed=false;
    for m=1:12
        idx=find(monthNumber==m);
        cfg=apply_strategy_config(cfgBase,spec);
        cfg.meta.parameterVersion=['v5_annual_2025_rolling_' ...
            char(spec.scenarioId) '_m' sprintf('%02d',m)];
        in=slice_input(baseInput,idx,state);
        in=apply_strategy_input(in,spec,cfg);
        if spec.productMixEnabled
            in.productMix=struct( ...
                'enabled',true, ...
                'targetElectricityShare', ...
                    spec.targetElectricityInputShare, ...
                'targetHydrogenShare', ...
                    spec.targetHydrogenInputShare, ...
                'targetComputeShare',spec.targetComputeInputShare, ...
                'shareTolerance',policy.shareTolerance, ...
                'minimumAllocatedInputMWh', ...
                    policy.minimumAllocatedInputMWh);
        else
            in.productMix=struct('enabled',false);
        end
        monthTimer=tic;
        try
            result=run_v5_model(in,cfg);
            monthRuntimeS=toc(monthTimer);
            monthResults{m}=result;
            policyPass=result.audit.pass && ...
                result.audit.simultaneousCurtailmentCriticalENSCount==0;
            monthStatus="PASS";
            if ~(result.meta.exitflag>0 && policyPass)
                if policyPass
                    monthStatus="FEASIBLE_NOT_PROVEN";
                else
                    monthStatus="FAIL_AUDIT_OR_POLICY";
                end
            end
            state=terminal_state(result);
            monthRows{m}=month_row(result,spec.scenarioId,m, ...
                nnz(idx),monthRuntimeS,monthStatus);
        catch ME
            monthRuntimeS=toc(monthTimer);
            errorId=string(ME.identifier);
            if strlength(errorId)==0
                errorId="UNIDENTIFIED_ERROR";
            end
            errorMessage=regexprep(strtrim(string(ME.message)),'\s+',' ');
            monthStatus="FAIL: "+errorId+" "+errorMessage;
            monthRows{m}=failed_month_row( ...
                spec.scenarioId,m,nnz(idx),monthRuntimeS,monthStatus);
            monthResults{m}=ME;
            caseFailed=true;
            break
        end
    end
    runtimeS(i)=toc(caseTimer);
    results{i}=monthResults;
    populated=~cellfun(@isempty,monthRows);
    monthlyTables{i}=vertcat(monthRows{populated});
    if caseFailed || height(monthlyTables{i})<12
        status(i)="FAIL";
        continue
    end

    mt=monthlyTables{i};
    auditPass(i)=all(mt.auditPass);
    allMonthsOptimal(i)=all(mt.exitflag>0);
    if auditPass(i) && allMonthsOptimal(i) && ...
            all(startsWith(mt.status,"PASS"))
        status(i)="PASS";
    elseif auditPass(i)
        status(i)="FEASIBLE_NOT_PROVEN";
    else
        status(i)="FAIL_AUDIT_OR_POLICY";
    end
    eAvailableMWh(i)=sum(mt.eAvailableMWh);
    eSourceUsedMWh(i)=sum(mt.eSourceUsedMWh);
    eElectricityInputMWh(i)=sum(mt.eElectricityInputMWh);
    eHydrogenInputMWh(i)=sum(mt.eHydrogenInputMWh);
    eFlexibleComputeInputMWh(i)=sum(mt.eFlexibleComputeInputMWh);
    eCableReceivedMWh(i)=sum(mt.eCableReceivedMWh);
    h2DeliveredKg(i)=sum(mt.h2DeliveredKg);
    eComputeServiceMWhCS(i)=sum(mt.eComputeServiceMWhCS);
    eCurtailmentMWh(i)=sum(mt.eCurtailmentMWh);
    ensMWh(i)=sum(mt.ensMWh);
    outputRevenueCNY(i)=sum(mt.outputRevenueCNY);
    operatingCostCNY(i)=sum(mt.operatingCostCNY);
    economicNetCostCNY(i)=sum(mt.economicNetCostCNY);
    netGHGKgCO2e(i)=sum(mt.netGHGKgCO2e);
    minimumGfmUpwardPowerHeadroomMW(i)= ...
        min(mt.minimumGfmUpwardPowerHeadroomMW);
    minimumGfmUpwardEnergyHeadroomMWh(i)= ...
        min(mt.minimumGfmUpwardEnergyHeadroomMWh);
    minimumGfmDownwardPowerHeadroomMW(i)= ...
        min(mt.minimumGfmDownwardPowerHeadroomMW);
    minimumGfmDownwardEnergyHeadroomMWh(i)= ...
        min(mt.minimumGfmDownwardEnergyHeadroomMWh);
    simultaneousCurtailmentCriticalENSCount(i)= ...
        sum(mt.simultaneousCurtailmentCriticalENSCount);
    terminalBessEnergyMWh(i)=mt.terminalBessEnergyMWh(end);
    terminalH2InventoryKg(i)=mt.terminalH2InventoryKg(end);
end

eAllocated=eElectricityInputMWh+eHydrogenInputMWh+ ...
    eFlexibleComputeInputMWh;
realizedElectricityInputShare=eElectricityInputMWh./eAllocated;
realizedHydrogenInputShare=eHydrogenInputMWh./eAllocated;
realizedComputeInputShare=eFlexibleComputeInputMWh./eAllocated;
maxShareDeviation=max(abs([ ...
    realizedElectricityInputShare- ...
        designTable.targetElectricityInputShare, ...
    realizedHydrogenInputShare- ...
        designTable.targetHydrogenInputShare, ...
    realizedComputeInputShare- ...
        designTable.targetComputeInputShare]),[],2);
maxShareDeviation(~designTable.productMixEnabled)=NaN;
renewableUtilization=eSourceUsedMWh./eAvailableMWh;
curtailmentRate=eCurtailmentMWh./eAvailableMWh;
operatingNetBenefitCNY=-economicNetCostCNY;
testScenarioId=repmat(string(scenario.meta.scenarioId),n,1);
horizonH=repmat(8760,n,1);
rollingRule=repmat( ...
    "CALENDAR_MONTH; STATE_CARRY; MONTHLY_CYCLIC_INVENTORY; MONTHLY_PRODUCT_SHARE", ...
    n,1);
rollingRule(~designTable.productMixEnabled)= ...
    "CALENDAR_MONTH; STATE_CARRY; MONTHLY_CYCLIC_INVENTORY; ASSET_SWITCH; ECONOMIC_DISPATCH";
shareTolerance=repmat(policy.shareTolerance,n,1);
maxENSLimitMWhPerMonth=repmat(policy.maxENSMWh,n,1);
summary=[designTable,table(testScenarioId,horizonH,rollingRule, ...
    shareTolerance,maxENSLimitMWhPerMonth,status,auditPass, ...
    allMonthsOptimal,runtimeS,eAvailableMWh,eSourceUsedMWh, ...
    eElectricityInputMWh,eHydrogenInputMWh, ...
    eFlexibleComputeInputMWh,realizedElectricityInputShare, ...
    realizedHydrogenInputShare,realizedComputeInputShare, ...
    maxShareDeviation,eCableReceivedMWh,h2DeliveredKg, ...
    eComputeServiceMWhCS,eCurtailmentMWh,curtailmentRate, ...
    renewableUtilization,ensMWh,outputRevenueCNY,operatingCostCNY, ...
    economicNetCostCNY,operatingNetBenefitCNY,netGHGKgCO2e, ...
    minimumGfmUpwardPowerHeadroomMW, ...
    minimumGfmUpwardEnergyHeadroomMWh, ...
    minimumGfmDownwardPowerHeadroomMW, ...
    minimumGfmDownwardEnergyHeadroomMWh, ...
    simultaneousCurtailmentCriticalENSCount, ...
    terminalBessEnergyMWh,terminalH2InventoryKg)];

populatedMonthly=~cellfun(@isempty,monthlyTables);
if any(populatedMonthly)
    monthlySummary=vertcat(monthlyTables{populatedMonthly});
else
    monthlySummary=table;
end

if strlength(string(outputDir))>0
    outputDir=char(string(outputDir));
    if ~isfolder(outputDir), mkdir(outputDir); end
    writetable(summary,fullfile(outputDir, ...
        'v5_product_mix_annual_2025_rolling_summary.csv'));
    writetable(monthlySummary,fullfile(outputDir, ...
        'v5_product_mix_annual_2025_rolling_monthly.csv'));
    writetable(annualInput,fullfile(outputDir, ...
        'v5_annual_2025_common_input_audit.csv'));
    scenarioMeta=scenario.meta;
    scenarioEvidence=scenario.evidence;
    sourceAudit=rmfield(sourceDetail,'raw');
    save(fullfile(outputDir, ...
        'v5_product_mix_annual_2025_rolling_results.mat'), ...
        'summary','monthlySummary','results','designTable', ...
        'scenarioMeta','scenarioEvidence','sourceAudit','policy','-v7.3');
end
end

function cfg=apply_strategy_config(cfg,spec)
if isfinite(spec.computeFacilityCapacityMW)
    cfg.compute.facilityMaxMW=spec.computeFacilityCapacityMW;
    cfg.compute.rampUpMWPerH=spec.computeFacilityCapacityMW;
    cfg.compute.rampDownMWPerH=spec.computeFacilityCapacityMW;
end
if isfinite(spec.computeModuleCount)
    cfg.compute.moduleCount=spec.computeModuleCount;
end
end

function in=apply_strategy_input(in,spec,cfg)
N=numel(in.timeH);
in.availability.cable=double(spec.assetElectricityEnabled)*ones(N,1);
in.availability.electrolyzer= ...
    double(spec.assetHydrogenEnabled)*ones(N,1);
in.availability.h2Storage= ...
    double(spec.assetHydrogenEnabled)*ones(N,1);
in.availability.h2Pipe=double(spec.assetHydrogenEnabled)*ones(N,1);
in.availability.h2Ship=double(spec.assetHydrogenEnabled)*ones(N,1);
in.availability.h2Power=zeros(N,1);
in.availability.compute=double(spec.assetComputeEnabled)*ones(N,1);

if spec.computeScenarioMode=="FULL_FLEXIBLE_TASK_POOL"
    % External flexible task pool is assumed sufficient in every hour.
    % Capacity and task availability are [假设值，待企业调研校准].
    in.pComputeBaseDemandMW=zeros(N,1);
    if spec.assetComputeEnabled
        in.pComputeFlexibleMaxMW=cfg.compute.facilityMaxMW*ones(N,1);
    else
        in.pComputeFlexibleMaxMW=zeros(N,1);
        in.initial.computePowerMW=0;
    end
end
if ~spec.assetHydrogenEnabled
    in.initial.h2InventoryKg=0;
    in.initial.electrolyzerOnlineModules=0;
    in.initial.electrolyzerPowerMW=0;
    in.initial.h2PowerMW=0;
end
end

function policy=normalize_policy(policy)
policy=struct( ...
    'shareTolerance',field_or(policy,'shareTolerance',0.02), ...
    'minimumAllocatedInputMWh',field_or( ...
        policy,'minimumAllocatedInputMWh',1), ...
    'maxENSMWh',field_or(policy,'maxENSMWh',0), ...
    'maxTimeS',field_or(policy,'maxTimeS',120));
assert(policy.shareTolerance>=0 && policy.shareTolerance<0.5);
assert(policy.minimumAllocatedInputMWh>=0);
assert(policy.maxENSMWh>=0);
assert(policy.maxTimeS>0 && isfinite(policy.maxTimeS));
end

function designTable=select_cases(designTable,caseIds)
if ischar(caseIds) || (isstring(caseIds) && isscalar(caseIds))
    if strcmpi(string(caseIds),"all"), return; end
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

function in=slice_input(base,idx,state)
in=struct;
names=fieldnames(base);
N=numel(base.timeH);
skip=["availability","initial"];
for k=1:numel(names)
    name=names{k};
    if any(strcmp(name,skip)), continue; end
    value=base.(name);
    if isnumeric(value) || islogical(value)
        if isvector(value) && numel(value)==N
            value=value(idx);
        end
    end
    in.(name)=value;
end
in.availability=struct;
availabilityNames=fieldnames(base.availability);
for k=1:numel(availabilityNames)
    name=availabilityNames{k};
    value=base.availability.(name);
    if isscalar(value)
        in.availability.(name)=value;
    else
        in.availability.(name)=value(idx);
    end
end
in.initial=state;
end

function state=terminal_state(result)
d=result.dispatch;
state=struct( ...
    'bessEnergyMWh',clean_terminal_value( ...
        d.bessEnergyMWh(end),'bessEnergyMWh',false), ...
    'h2InventoryKg',clean_terminal_value( ...
        d.h2InventoryKg(end),'h2InventoryKg',false), ...
    'electrolyzerOnlineModules',clean_terminal_value( ...
        d.nElectrolyzerOnline(end),'electrolyzerOnlineModules',true), ...
    'electrolyzerPowerMW',clean_terminal_value( ...
        d.pElectrolyzerMW(end),'electrolyzerPowerMW',false), ...
    'computePowerMW',clean_terminal_value( ...
        d.pComputeFacilityMW(end),'computePowerMW',false), ...
    'h2PowerMW',clean_terminal_value( ...
        d.pH2PowerMW(end),'h2PowerMW',false));
end

function value=clean_terminal_value(rawValue,name,isInteger)
% MILP solutions may contain O(1e-15) bound or integrality residuals.
% Clean only solver-tolerance residue at the rolling-horizon interface.
value=double(rawValue);
if ~isscalar(value) || ~isfinite(value)
    error('V5:AnnualRolling:InvalidTerminalState', ...
        'Terminal state %s must be a finite scalar.',name);
end
if value < -1e-7
    error('V5:AnnualRolling:NegativeTerminalState', ...
        'Terminal state %s is materially negative: %.17g.',name,value);
end
value=max(0,value);
if isInteger
    roundedValue=round(value);
    if abs(value-roundedValue) > 1e-6
        error('V5:AnnualRolling:NonintegerTerminalState', ...
            'Terminal state %s violates integrality: %.17g.',name,value);
    end
    value=roundedValue;
end
end

function row=month_row(result,scenarioId,monthNumber,hours, ...
    runtimeS,status)
k=result.kpi;
a=result.audit;
row=table(scenarioId,monthNumber,hours,status, ...
    logical(a.pass),double(result.meta.exitflag),runtimeS, ...
    k.eAvailableMWh,k.eSourceUsedMWh,k.eElectricityInputMWh, ...
    k.eHydrogenInputMWh,k.eFlexibleComputeInputMWh, ...
    k.eCableReceivedMWh,k.h2DeliveredKg,k.eComputeServiceMWhCS, ...
    k.eCurtailmentMWh,k.ensMWh,k.outputRevenueCNY, ...
    k.operatingCostCNY,k.economicNetCostCNY,k.netGHGKgCO2e, ...
    a.minimumGfmUpwardPowerHeadroomMW, ...
    a.minimumGfmUpwardEnergyHeadroomMWh, ...
    a.minimumGfmDownwardPowerHeadroomMW, ...
    a.minimumGfmDownwardEnergyHeadroomMWh, ...
    a.simultaneousCurtailmentCriticalENSCount, ...
    result.dispatch.bessEnergyMWh(end), ...
    result.dispatch.h2InventoryKg(end), ...
    'VariableNames',{'scenarioId','month','hours','status', ...
    'auditPass','exitflag','runtimeS','eAvailableMWh', ...
    'eSourceUsedMWh','eElectricityInputMWh','eHydrogenInputMWh', ...
    'eFlexibleComputeInputMWh','eCableReceivedMWh','h2DeliveredKg', ...
    'eComputeServiceMWhCS','eCurtailmentMWh','ensMWh', ...
    'outputRevenueCNY','operatingCostCNY','economicNetCostCNY', ...
    'netGHGKgCO2e','minimumGfmUpwardPowerHeadroomMW', ...
    'minimumGfmUpwardEnergyHeadroomMWh', ...
    'minimumGfmDownwardPowerHeadroomMW', ...
    'minimumGfmDownwardEnergyHeadroomMWh', ...
    'simultaneousCurtailmentCriticalENSCount', ...
    'terminalBessEnergyMWh','terminalH2InventoryKg'});
end

function row=failed_month_row( ...
    scenarioId,monthNumber,hours,runtimeS,status)
nanValues=num2cell(nan(1,21));
row=table(scenarioId,monthNumber,hours,status,false,NaN,runtimeS, ...
    nanValues{:},'VariableNames',{'scenarioId','month','hours', ...
    'status','auditPass','exitflag','runtimeS','eAvailableMWh', ...
    'eSourceUsedMWh','eElectricityInputMWh','eHydrogenInputMWh', ...
    'eFlexibleComputeInputMWh','eCableReceivedMWh','h2DeliveredKg', ...
    'eComputeServiceMWhCS','eCurtailmentMWh','ensMWh', ...
    'outputRevenueCNY','operatingCostCNY','economicNetCostCNY', ...
    'netGHGKgCO2e','minimumGfmUpwardPowerHeadroomMW', ...
    'minimumGfmUpwardEnergyHeadroomMWh', ...
    'minimumGfmDownwardPowerHeadroomMW', ...
    'minimumGfmDownwardEnergyHeadroomMWh', ...
    'simultaneousCurtailmentCriticalENSCount', ...
    'terminalBessEnergyMWh','terminalH2InventoryKg'});
end

function out=merge_input(out,addition)
names=fieldnames(addition);
for k=1:numel(names), out.(names{k})=addition.(names{k}); end
end

function value=field_or(s,name,defaultValue)
if isfield(s,name), value=s.(name); else, value=defaultValue; end
end
