function [summary,windowSummary,results] = ...
    run_c5_annual_48h_block_rolling(v5Root,outputDir)
%RUN_C5_ANNUAL_48H_BLOCK_ROLLING 2025 free E/H/C economic dispatch.
% Uses 182 non-overlapping 48 h blocks plus one final 24 h block. States
% are passed between blocks; BESS/H2 inventory is cyclic per block. This is
% a conservative rolling-block approximation, not an annual global optimum.

if nargin<1 || strlength(string(v5Root))==0, v5Root=locate_v5(); end
if nargin<2, outputDir=""; end
c5Root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(v5Root,fullfile(v5Root,'config'),fullfile(v5Root,'model'), ...
    fullfile(v5Root,'source'), ...
    fullfile(c5Root,'5.1场景设计','source_snapshot'));
scenario=v5_build_annual_2025_normal_scenario();
cfgBase=scenario.config;
cfgBase.compute.facilityMaxMW=120; % [假设值，待企业调研校准]
cfgBase.compute.moduleCount=16;
cfgBase.compute.rampUpMWPerH=120;
cfgBase.compute.rampDownMWPerH=120;
cfgBase.objective.primary='economicNetCostCNY';
cfgBase.objective.maxENSMWh=Inf;
cfgBase.objective.maxNetGHGKgCO2e=Inf;
cfgBase.objective.minRenewableUtilization=0;
cfgBase.objective.tieBreak='none';
cfgBase.objective.temporalTieBreak='none';
cfgBase.solver.maxTimeS=60;
cfgBase.bess.terminalRule='cyclic';
cfgBase.hydrogen.terminalRule='cyclic';
[sourceInput,~]=v5_source_adapter(cfgBase,scenario.input.sourceCase);
base=rmfield(scenario.input,'sourceCase');
base=merge_input(base,sourceInput);
base.pComputeBaseDemandMW=zeros(8760,1);
base.pComputeFlexibleMaxMW=120*ones(8760,1);
base.availability.compute=1;
base.availability.cable=1;
base.availability.electrolyzer=1;
base.availability.h2Storage=1;
base.availability.h2Pipe=1;
base.availability.h2Ship=1;
base.availability.h2Power=0;
base.initial.computePowerMW=0;

starts=(1:48:8760)';
n=numel(starts);
results=cell(n,1);
rows=cell(n,1);
state=base.initial;
for w=1:n
    idx=starts(w):min(starts(w)+47,8760);
    in=slice_input(base,idx,state);
    in.productMix=struct('enabled',false);
    cfg=cfgBase;
    cfg.meta.parameterVersion=sprintf('c5_annual_48h_block_%03d',w);
    result=run_v5_model(in,cfg);
    assert(result.meta.exitflag>0 && result.audit.pass);
    results{w}=result;
    state=terminal_state(result);
    k=result.kpi;
    rows{w}=table(w,idx(1),idx(end),numel(idx), ...
        k.eAvailableMWh,k.eSourceUsedMWh,k.eElectricityInputMWh, ...
        k.eHydrogenInputMWh,k.eFlexibleComputeInputMWh, ...
        k.eCableReceivedMWh,k.h2DeliveredKg,k.eComputeServiceMWhCS, ...
        k.eCurtailmentMWh,k.ensMWh,k.outputRevenueCNY, ...
        k.operatingCostCNY,k.economicNetCostCNY,result.meta.exitflag, ...
        result.audit.pass,'VariableNames',{'window','startHourIndex', ...
        'endHourIndex','hours','eAvailableMWh','eSourceUsedMWh', ...
        'eElectricityInputMWh','eHydrogenInputMWh', ...
        'eFlexibleComputeInputMWh','eCableReceivedMWh','h2DeliveredKg', ...
        'eComputeServiceMWhCS','eCurtailmentMWh','ensMWh', ...
        'outputRevenueCNY','operatingCostCNY','economicNetCostCNY', ...
        'exitflag','auditPass'});
end
windowSummary=vertcat(rows{:});
eE=sum(windowSummary.eElectricityInputMWh);
eH=sum(windowSummary.eHydrogenInputMWh);
eC=sum(windowSummary.eFlexibleComputeInputMWh);
den=eE+eH+eC;
summary=table("OPT_FREE_ECON_48H_BLOCK_ROLLING",8760,n, ...
    sum(windowSummary.eAvailableMWh),sum(windowSummary.eSourceUsedMWh), ...
    eE,eH,eC,eE/den,eH/den,eC/den, ...
    sum(windowSummary.eCableReceivedMWh), ...
    sum(windowSummary.h2DeliveredKg), ...
    sum(windowSummary.eComputeServiceMWhCS), ...
    sum(windowSummary.eCurtailmentMWh), ...
    sum(windowSummary.eSourceUsedMWh)/sum(windowSummary.eAvailableMWh), ...
    sum(windowSummary.ensMWh),sum(windowSummary.outputRevenueCNY), ...
    sum(windowSummary.operatingCostCNY), ...
    sum(windowSummary.economicNetCostCNY), ...
    -sum(windowSummary.economicNetCostCNY), ...
    all(windowSummary.auditPass),all(windowSummary.exitflag>0), ...
    "[模型仿真结果；48h分块循环库存；参数为假设值，待企业调研校准]", ...
    'VariableNames',{'scenarioId','horizonH','windowCount', ...
    'eAvailableMWh','eSourceUsedMWh','eElectricityInputMWh', ...
    'eHydrogenInputMWh','eFlexibleComputeInputMWh', ...
    'realizedElectricityInputShare','realizedHydrogenInputShare', ...
    'realizedComputeInputShare','eCableReceivedMWh','h2DeliveredKg', ...
    'eComputeServiceMWhCS','eCurtailmentMWh','renewableUtilization', ...
    'ensMWh','outputRevenueCNY','operatingCostCNY', ...
    'economicNetCostCNY','operatingNetBenefitCNY','auditPass', ...
    'allWindowsOptimal','evidenceStatus'});
if strlength(string(outputDir))>0
    if ~isfolder(outputDir), mkdir(outputDir); end
    writetable(summary,fullfile(outputDir,'c5_annual_48h_rolling_summary.csv'));
    writetable(windowSummary,fullfile(outputDir, ...
        'c5_annual_48h_rolling_windows.csv'));
    save(fullfile(outputDir,'c5_annual_48h_rolling_results.mat'), ...
        'summary','windowSummary','results','-v7.3');
end
end

function in=slice_input(base,idx,state)
in=struct;
names=fieldnames(base);
N=numel(base.timeH);
for k=1:numel(names)
    name=names{k};
    if any(strcmp(name,{'availability','initial'})), continue; end
    value=base.(name);
    if (isnumeric(value)||islogical(value)) && isvector(value) && ...
            numel(value)==N
        value=value(idx);
    end
    in.(name)=value;
end
in.availability=struct;
names=fieldnames(base.availability);
for k=1:numel(names)
    value=base.availability.(names{k});
    if ~isscalar(value), value=value(idx); end
    in.availability.(names{k})=value;
end
in.initial=state;
end

function state=terminal_state(result)
d=result.dispatch;
state=struct('bessEnergyMWh',max(0,d.bessEnergyMWh(end)), ...
    'h2InventoryKg',max(0,d.h2InventoryKg(end)), ...
    'electrolyzerOnlineModules',max(0,round(d.nElectrolyzerOnline(end))), ...
    'electrolyzerPowerMW',max(0,d.pElectrolyzerMW(end)), ...
    'computePowerMW',max(0,d.pComputeFacilityMW(end)), ...
    'h2PowerMW',max(0,d.pH2PowerMW(end)));
end

function root=locate_v5()
here=fileparts(mfilename('fullpath'));
candidates={fullfile(pwd,'V5模型'), ...
    fullfile(here,'..','..','..','V5模型'), ...
    fullfile(here,'..','..','..','C4调度模型与分析','V5模型')};
for k=1:numel(candidates)
    candidate=char(java.io.File(candidates{k}).getCanonicalPath());
    if isfile(fullfile(candidate,'run_v5_model.m')), root=candidate; return; end
end
error('C5 cannot locate the V5 model root.');
end

function out=merge_input(out,addition)
names=fieldnames(addition);
for k=1:numel(names), out.(names{k})=addition.(names{k}); end
end
