function report=run_all_tests_v4()
%RUN_ALL_TESTS_V4 Acceptance tests for the Chapter 4.1--4.9 V4 integration.
here=fileparts(mfilename('fullpath'));
addpath(fullfile(here,'library','4.2变量与接口'), ...
    fullfile(here,'integration','common'), ...
    fullfile(here,'modules','4.3_source','integration'), ...
    fullfile(here,'modules','4.4_bus','integration'), ...
    fullfile(here,'modules','4.5_storage_hydrogen','integration'), ...
    fullfile(here,'modules','4.8_objectives','model'), ...
    fullfile(here,'modules','4.9_dispatch','model'));
tests={@test_snapshot_hashes,@test_frozen_schema,@test_4_3_existing, ...
    @test_joint_run,@test_4_9_dispatch,@test_shortage_accounting, ...
    @test_4_8_evaluation,@test_no_duplicate_ledger};
names=["V4包内相对哈希","4.1-4.2冻结Schema","4.3既有模型", ...
    "4.3-4.9联合链路","4.9调度约束","缺供与海洋刚性负荷", ...
    "4.8三目标评价","损耗与总账去重"];
passed=false(numel(tests),1); message=strings(numel(tests),1);
for k=1:numel(tests)
    try, tests{k}(); passed(k)=true; message(k)="PASS";
    catch ME, message(k)=string(ME.identifier)+": "+string(ME.message); end
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
function test_joint_run()
o=get_joint_output(); cfg=o.cfg;
for id={'4.3','4.4','4.5','4.6','4.7'}
    p=o.(['packet' strrep(id{1},'.','_')]); validate_module_packet_4_2(p,id{1},cfg,true);
end
assert(max(abs(o.packet4_4.state.pBusResidualMW))<=cfg.commonBus.balanceToleranceMW);
assert(strcmp(o.packet4_8.meta.phase,'EVALUATION'));
assert(strcmp(o.packet4_9.meta.phase,'REQUEST'));
end
function test_4_9_dispatch()
o=get_joint_output();
p46b=v4_compute_boundary_4_6(o.cfg,o.packet4_3.axis.timeH);
p43b=o.packet4_3; p43b.meta.phase='BOUNDARY';
[p49,d]=v4_dispatch_4_9(o.cfg,p43b,p46b);
r=v4_validate_dispatch_4_9(p49,d,o.cfg,p43b,p46b,false);
assert(r.ok && strcmp(p49.audit.schedulerId,'FEASIBILITY_RULE_V4_4_9'));
assert(strcmp(p49.audit.solverClass,'DETERMINISTIC_RULE_NO_OPTIMALITY_CLAIM'));
assert(max(abs(o.packet4_6.ports.dcFacility.requestedMW- ...
    o.packet4_9.service.computeRequestedMW))<1e-9);
end
function test_shortage_accounting()
o=get_joint_output(); cfg=o.cfg; cfg.bess.socInitial=cfg.bess.socMin;
p43b=o.packet4_3; p43b.meta.phase='BOUNDARY';
p43b.ports.source.actualMW(:)=24;
p46b=v4_compute_boundary_4_6(cfg,p43b.axis.timeH);
[p49,d]=v4_dispatch_4_9(cfg,p43b,p46b);
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
end
function test_no_duplicate_ledger()
o=get_joint_output();
assert(o.packet4_3.loss.collectionLossAlreadyDeducted);
assert(all(o.packet4_7.service.pCableReceiveMW<=o.packet4_7.ports.exportSend.actualMW+1e-12));
assert(all(o.packet4_6.ports.dcFacility.actualMW- ...
    o.packet4_6.service.pITActualMW-o.packet4_6.service.pDCAuxActualMW<1e-8));
assert(strcmp(o.packet4_5.audit.h2DeliverySequence, ...
    '4.5_AVAILABLE_THEN_4.7_ACTUAL_THEN_4.5_COMMIT'));
end

function o=get_joint_output()
persistent cached
if isempty(cached), cached=run_v4_integration(); end
o=cached;
end
