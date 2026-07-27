function report=run_all_tests_v4()
%RUN_ALL_TESTS_V4 Acceptance tests for the Chapter 4.1--4.9 V4 integration.
here=fileparts(mfilename('fullpath'));
addpath(fullfile(here,'library','4.2变量与接口'), ...
    fullfile(here,'integration','common'), ...
    fullfile(here,'modules','4.3_source','integration'), ...
    fullfile(here,'modules','4.4_bus','integration'), ...
    fullfile(here,'modules','4.5_storage_hydrogen','integration'), ...
    fullfile(here,'modules','4.5_storage_hydrogen','model'), ...
    fullfile(here,'modules','4.5_storage_hydrogen','tests'), ...
    fullfile(here,'modules','4.8_objectives','model'), ...
    fullfile(here,'modules','4.9_dispatch','model'), ...
    fullfile(here,'chapter5_preparation'));
tests={@test_snapshot_hashes,@test_frozen_schema,@test_4_3_existing, ...
    @test_4_5_multiscale,@test_joint_run,@test_4_9_dispatch, ...
    @test_terminal_path_rules,@test_post_compute_redispatch, ...
    @test_shortage_accounting, ...
    @test_4_8_evaluation,@test_asset_switch_cost_gating, ...
    @test_no_duplicate_ledger,@test_all_channel_48h};
names=["V4包内相对哈希","4.1-4.2冻结Schema","4.3既有模型", ...
    "4.5三时标独立模型","4.3-4.9联合链路","4.9调度约束", ...
    "4.9 TERMINAL-ONLY PATH RULES","4.6 RELEASE TO H2 REDISPATCH", ...
    "缺供与海洋刚性负荷","4.8三目标评价", ...
    "E/H/C/M ASSET SWITCH COST GATING","损耗与总账去重","48h全通道行为"];
passed=false(numel(tests),1); message=strings(numel(tests),1);
for k=1:numel(tests)
    try
        tests{k}(); passed(k)=true; message(k)="PASS";
    catch ME
        message(k)=string(ME.identifier)+": "+string(ME.message);
    end
end
report=table(names',passed,message,'VariableNames',{'Test','Passed','Message'}); disp(report);
assert(all(passed),'V4 integration acceptance failed.');
save(fullfile(here,'outputs','v4_test_report.mat'),'report');
fprintf('BLUE HUB CH4 V4: ALL TESTS PASSED\n');
end

function test_snapshot_hashes()
here=fileparts(mfilename('fullpath'));
script=fullfile(here,'build_v4_snapshot.ps1');
cmd=sprintf('powershell -ExecutionPolicy Bypass -File "%s" -VerifyOnly',script);
[status,msg]=system(cmd); assert(status==0,'V4 portable-package mismatch: %s',msg);
end

function test_frozen_schema()
here=fileparts(mfilename('fullpath')); addpath(fullfile(here,'library','4.2变量与接口'));
r=run_all_tests_4_2(); assert(all(r.Passed));
end
function test_4_3_existing()
here=fileparts(mfilename('fullpath'));
addpath(fullfile(here,'modules','4.3_source','tests'));
r=run_all_tests_4_3_v3(); assert(all(r.Passed));
end
function test_4_5_multiscale()
r=run_all_tests_4_5(); assert(all(r.passed));
end
function test_joint_run()
o=get_joint_output(); cfg=o.cfg;
for id={'4.3','4.4','4.5','4.6','4.7'}
    p=o.(['packet' strrep(id{1},'.','_')]); validate_module_packet_4_2(p,id{1},cfg,true);
end
assert(max(abs(o.packet4_4.state.pBusResidualMW))<=cfg.commonBus.balanceToleranceMW);
assert(strcmp(o.packet4_8.meta.phase,'EVALUATION'));
assert(strcmp(o.packet4_9.meta.phase,'REQUEST'));
assert(all(isfield(o.storageFinalState, ...
    {'bessEnergyMWh','h2InventoryKg','electrolyzerOn', ...
    'electrolyzerPowerMW','electrolyzerFLEH'})), ...
    'Joint output must expose the complete rolling 4.5 final state.');
here=fileparts(mfilename('fullpath'));
for name={'v4_hourly_detail.csv','v4_kpi_summary.csv', ...
        'v4_economic_breakdown.csv','v4_lifecycle_asset_ledger.csv', ...
        'v4_lifecycle_summary.csv','v4_capacity_audit.csv', ...
        'v4_environment_breakdown.csv'}
    assert(isfile(fullfile(here,'outputs',name{1})), ...
        'Missing unified result output: %s',name{1});
end
D=readtable(fullfile(here,'outputs','v4_hourly_detail.csv'), ...
    'VariableNamingRule','preserve');
assert(height(D)==numel(o.packet4_3.axis.timeH));
assert(max(abs(D.sourceActualMW-o.packet4_3.ports.source.actualMW))<1e-9);
assert(all(ismember({'computeRequestedMW','h2InventoryKg','marineUnservedMW', ...
    'computeReleasedMW','busResidualMW'},D.Properties.VariableNames)));
end
function test_4_9_dispatch()
o=get_joint_output();
p46b=v4_compute_boundary_4_6(o.cfg,o.packet4_3.axis.timeH);
p43b=o.packet4_3; p43b.meta.phase='BOUNDARY';
[p49,d]=v4_dispatch_4_9(o.cfg,p43b,p46b,struct,o.packet4_5Boundary);
r=v4_validate_dispatch_4_9(p49,d,o.cfg,p43b,p46b,false);
assert(r.ok && strcmp(p49.audit.schedulerId,'FEASIBILITY_RULE_V4_4_9'));
assert(strcmp(p49.audit.solverClass,'DETERMINISTIC_RULE_NO_OPTIMALITY_CLAIM'));
assert(max(abs(o.packet4_6.ports.dcFacility.requestedMW- ...
    o.packet4_9.service.computeRequestedMW))<1e-9);
end
function test_post_compute_redispatch()
r=test_v4_post_compute_redispatch_4_9();
assert(all(r.passed));
end
function test_terminal_path_rules()
r=test_v4_terminal_path_rules_4_9();
assert(all(r.passed));
end
function test_shortage_accounting()
o=get_joint_output(); cfg=o.cfg; cfg.bess.socInitial=cfg.bess.socMin;
cfg.bess.gfmReserveEnergyMWh=0;
p43b=o.packet4_3; p43b.meta.phase='BOUNDARY';
p43b.ports.source.actualMW(:)=8;
p46b=v4_compute_boundary_4_6(cfg,p43b.axis.timeH);
state0=struct('bessEnergyMWh',cfg.bess.socInitial*cfg.bess.energyMWh, ...
    'h2InventoryKg',cfg.hydrogen.storageInitialKg);
[p45b,~]=v4_storage_hydrogen_boundary_4_5(cfg,p43b.axis.timeH,state0, ...
    struct('gfmReservePowerMW',cfg.bess.gfmReservePowerMW, ...
    'gfmReserveEnergyMWh',cfg.bess.gfmReserveEnergyMWh, ...
    'blackStartSOCMin',cfg.bess.blackStartSOCMin));
[p49,d]=v4_dispatch_4_9(cfg,p43b,p46b,struct,p45b);
r=v4_validate_dispatch_4_9(p49,d,cfg,p43b,p46b,false); assert(r.ok);
assert(any(d.marineUnservedPlannedMW>0),'Stress case must expose marine unserved demand.');
assert(all(d.marineAllocatedMW<=d.marineRequestedMW+1e-12));
assert(max(abs(o.packet4_7.ports.marine.requestedMW-o.packet4_7.ports.marine.actualMW- ...
    o.packet4_7.service.marineUnservedMW))<1e-9);
assert(any(o.packet4_7.service.marineUnservedMW>0), ...
    'Integrated case must preserve nonzero marine unserved demand.');
end
function test_4_8_evaluation()
o=get_joint_output(); p=o.packet4_8;
r=v4_validate_evaluation_4_8(p,o.cfg,false); assert(r.ok);
assert(numel(p.state.objectiveVectorRaw)==3 && all(isfinite(p.state.objectiveVectorRaw)));
assert(p.product.lifecycleEmissionKgCO2e>=0 && p.product.EENSMWh>=0);
assert(strcmp(p.audit.normalizationStatus,'NOT_AVAILABLE_WITHOUT_IDEAL_AND_NADIR_CASES'));
assert(abs(sum(p.service.costComponentsCNY)-p.service.totalCostCNY)<1e-6);
assert(abs(sum(p.service.revenueComponentsCNY)-p.service.totalRevenueCNY)<1e-6);
assert(abs(sum(p.service.emissionComponentsKgCO2e)- ...
    p.product.lifecycleEmissionKgCO2e)<1e-6);
l=p.service.lifecycle;
assert(l.grossCapexCNY>0 && l.constructionFinancingCNY>0 && ...
    l.financedCapexCNY>l.grossCapexCNY && l.annualFixedOMCNY>0 && ...
    l.replacementPresentValueCNY>0);
assert(l.lifecycleNPVBeforePenaltyCNY>=l.lifecycleNPVAfterPenaltyCNY);
assert(height(p.service.lifecycleAssetTable)==10);
assert(all(p.service.lifecycleAssetTable.capexCNY( ...
    ~p.service.lifecycleAssetTable.enabled)==0));
capitalPeriod=l.periodDepreciationCNY+l.periodFinancingCostCNY+ ...
    l.periodFixedOMCNY+l.periodReplacementReserveCNY;
assert(abs(p.service.totalCostCNY-p.service.operatingCostCNY-capitalPeriod)< ...
    1e-8*max(1,p.service.totalCostCNY));
assert(isfield(p.service,'capacityAuditTable') && ...
    height(p.service.capacityAuditTable)==10);
computeRow=p.service.capacityAuditTable.assetName=="subseaCompute";
assert(abs(p.service.capacityAuditTable.installedCapacity(computeRow)- ...
    o.cfg.capacity.installed.computeFacilityMW)<1e-9);
h2Row=p.service.capacityAuditTable.assetName=="hydrogenStorage";
assert(p.service.capacityAuditTable.installedCapacity(h2Row)>0);
assert(p.service.capacityAuditTable.capexCNY(h2Row)>0);
assert(p.service.hydrogenStorageDesign.minimumProcessBufferKg>0);
end
function test_asset_switch_cost_gating()
cfg0=common_config_4_2('interface_smoke');
for mode=["E","H","C","M"]
    cfg=v4_apply_unified_capacity_case_4_2(cfg0,mode);
    storageDesign=v4_hydrogen_storage_sizing_4_8(cfg,0);
    context=struct('hydrogenStorageInstalledKg',storageDesign.installedKg);
    params=v4_objective_parameters_4_8();
    [~,assetTable]=v4_lifecycle_economics_4_8(cfg,params,0,0,0,24,context);
    assert(all(assetTable.capexCNY(~assetTable.scenarioEnabled)==0));
    assert(all(assetTable.fixedOMAnnualCNY(~assetTable.scenarioEnabled)==0));
    assert(all(assetTable.replacementPVCNY(~assetTable.scenarioEnabled)==0));
    h2=assetTable.assetName=="hydrogenStorage";
    if any(mode==["H","M"])
        assert(assetTable.capexCNY(h2)>0, ...
            'Enabled H2 chain must carry process-buffer tank CAPEX.');
    else
        assert(assetTable.capexCNY(h2)==0);
    end
end
cfgC=v4_apply_unified_capacity_case_4_2(cfg0,"C");
expectedIT=cfgC.capacity.installed.computeUnitCount* ...
    cfgC.capacity.installed.computeUnitITMaxMW;
assert(abs(cfgC.capacity.installed.computeITMW-expectedIT)<1e-9);
end
function test_no_duplicate_ledger()
o=get_joint_output();
assert(o.packet4_3.loss.collectionLossAlreadyDeducted);
assert(all(o.packet4_7.service.pCableReceiveMW<=o.packet4_7.ports.exportSend.actualMW+1e-12));
assert(all(o.packet4_6.ports.dcFacility.actualMW- ...
    o.packet4_6.service.pITActualMW-o.packet4_6.service.pDCAuxActualMW<1e-8));
assert(strcmp(o.packet4_5.audit.h2DeliverySequence, ...
    '4.5_AVAILABLE_THEN_4.7_ACTUAL_THEN_4.5_COMMIT'));
assert(o.cfg.hydrogen.storageInitialKg==0, ...
    'Default smoke case must not create free opening hydrogen inventory.');
assert(sum(o.packet4_7.ports.exportSend.actualMW)>0, ...
    'Compute-response release must reach available cable capacity.');
coexist=(o.dispatchActual.spillMW>1e-7) & ...
    ((o.packet4_7.service.marineUnservedMW>1e-7) | ...
    (o.dispatchActual.criticalUnservedMW>1e-7));
assert(~any(coexist),'Spill and electrical/marine unserved energy coexist.');
end

function test_all_channel_48h()
[~,r]=run_all_channel_validation_v4();
assert(all(r.passed),'The 48 h all-channel behavior scenario must pass.');
end

function o=get_joint_output()
persistent cached
if isempty(cached), cached=run_v4_integration(); end
o=cached;
end
