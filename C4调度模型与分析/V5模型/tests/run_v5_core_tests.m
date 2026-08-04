function report=run_v5_core_tests()
%RUN_V5_CORE_TESTS Regression tests for the V5 dispatch entry point.

testRoot=fileparts(mfilename('fullpath'));
v5Root=fileparts(testRoot);
addpath(v5Root);

tests={@test_dispatch_smoke,@test_no_implicit_flexible_compute, ...
    @test_no_simultaneous_curtailment_and_critical_ens, ...
    @test_rejects_invalid_initial_h2_power};
names=["dispatch smoke","no implicit flexible compute", ...
    "no simultaneous curtailment and critical ENS", ...
    "invalid initial H2-to-power state"];
passed=false(size(tests));
messages=strings(size(tests));
for k=1:numel(tests)
    try
        tests{k}();
        passed(k)=true;
        messages(k)="PASS";
    catch ME
        messages(k)=string(ME.identifier)+": "+string(ME.message);
    end
end
report=table(names',passed',messages', ...
    'VariableNames',{'Test','Passed','Message'});
disp(report);
assert(all(passed),'V5 core regression tests failed.');
end

function test_dispatch_smoke()
in=struct('timeH',(1:2)','pSourceAvailableMW',[100;0]);
result=run_v5_model(in,'mechanism_test');
assert(result.audit.pass,'V5 smoke result must pass its algebraic audit.');
assert(result.meta.selectedSolutionExitflag>0, ...
    'V5 smoke result must be proven optimal.');
end

function test_no_implicit_flexible_compute()
in=struct('timeH',1,'pSourceAvailableMW',200);
result=run_v5_model(in,'mechanism_test');
assert(all(result.input.pComputeFlexibleMaxMW==0), ...
    'Omitted flexible-compute demand must default to zero.');
assert(abs(result.kpi.eFlexibleComputeInputMWh)<=1e-9, ...
    'V5 must not create flexible-compute service from an omitted task pool.');
assert(strcmp(result.input.meta.computeFlexibleTaskPoolSource, ...
    'DEFAULT_ZERO_NO_FLEXIBLE_TASK_POOL'), ...
    'Normalized input must identify the zero default task-pool boundary.');
end

function test_no_simultaneous_curtailment_and_critical_ens()
in=struct( ...
    'timeH',1, ...
    'pSourceAvailableMW',500, ...
    'pMarineDemandMW',1000, ...
    'pComputeFlexibleMaxMW',0);
result=run_v5_model(in,'mechanism_test');
assert(result.audit.pass, ...
    'High critical-demand case must pass algebraic audit.');
assert(result.audit.simultaneousCurtailmentCriticalENSCount==0, ...
    'Critical ENS and curtailment must not occur in the same interval.');
assert(result.kpi.ensMWh>0, ...
    'The test case must actually exercise critical ENS.');
end

function test_rejects_invalid_initial_h2_power()
in=struct( ...
    'timeH',1, ...
    'pSourceAvailableMW',100, ...
    'initial',struct('h2PowerMW',1));
didFail=false;
try
    run_v5_model(in,'mechanism_test');
catch ME
    didFail=contains(string(ME.message), ...
        "Initial H2-to-power output must be zero");
end
assert(didFail, ...
    'Disabled H2-to-power must reject a nonzero initial output.');
end
