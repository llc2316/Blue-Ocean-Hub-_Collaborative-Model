function report=run_all_tests_4_3_v3()
%RUN_ALL_TESTS_4_3_V3 Automated acceptance checks for Chapter 4.3 Version3.
moduleRoot=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot,'model','wind'),fullfile(moduleRoot,'model','pv'), ...
    fullfile(moduleRoot,'model','tidal'),fullfile(moduleRoot,'model','aggregation'));
tests={@test_metrics,@test_portfolios,@test_scenarios,@test_scenario_coverage, ...
    @test_state_dictionary,@test_aggregation_contract};
names=["互补指标","三方案对照","联合场景校验","场景覆盖率", ...
    "状态与约束字典","聚合契约与边界"];
passed=false(size(tests)); messages=strings(size(tests));
for k=1:numel(tests)
    try, tests{k}(); passed(k)=true; messages(k)="PASS";
    catch err, messages(k)=string(err.identifier)+": "+string(err.message); end
end
report=table(names',passed',messages','VariableNames',{'Test','Passed','Message'});
disp(report);
assert(all(passed),'Chapter 4.3 Version3 acceptance tests failed.');
fprintf('CHAPTER 4.3 VERSION3: ALL ACCEPTANCE TESTS PASSED\n');
end

function test_metrics()
t=(0:300:6*3600)'; N=numel(t);
p=[0.5+0.1*sin(t/1800),max(0,sin(pi*t/(6*3600))),0.35+0.1*cos(t/1200)];
q=true(N,3); m=source_complementarity_metrics_v3(t,p,q,[0.85 0.10 0.05],[300 3600],0.2);
assert(all(isfinite(m.coefficientVariation)) && all(m.coverage>0));
assert(all(m.lowEventCount>=0) && all(m.maxLowDurationSeconds>=0));
assert(all(m.lowEnergyDeficitWh>=0));
end

function test_portfolios()
t=(0:300:24*3600)'; h=t/3600; N=numel(t);
pu=[0.55+0.2*sin(2*pi*h/17),max(0,sin(pi*(h-6)/12)),abs(sin(2*pi*h/12.42)).^3];
r=compare_source_portfolios_4_3_v3(t,pu,true(N,3),[0.85 0.10 0.05],[300 3600],0.2);
assert(numel(r)==3 && all([r.share],2)>-eps,'Portfolio comparison failed.');
assert(all(abs(arrayfun(@(x)sum(x.share),r)-1)<1e-12));
end

function test_scenarios()
rng(43); N=100; S=3; K=5; cap=[0.85 0.10 0.05];
actual=rand(N,S).*cap; scenarios=zeros(N,S,K);
for k=1:K, scenarios(:,:,k)=min(cap,max(0,actual.*(1+0.05*randn(N,S)))); end
o=validate_joint_scenarios_4_3_v3(actual,scenarios,ones(1,K)/K,cap);
assert(o.scenarioCount==K && isfinite(o.meanCorrelationAbsoluteError));
end

function test_scenario_coverage()
actual=(1:10)'; scenarios=[actual-1 actual actual+1 actual+2];
o=evaluate_scenario_coverage_4_3_v3(actual,scenarios,[0.5 0.8]);
assert(all(o.empiricalCoverage>=o.nominalCoverage));
assert(all(o.lower<=o.upper,'all') && all(o.meanIntervalWidth>=0));
end

function test_state_dictionary()
d=source_state_dictionary_4_3_v3();
assert(height(d.operatingState)>=7 && height(d.constraintReason)>=8);
assert(numel(unique(d.operatingState.Code))==height(d.operatingState));
assert(numel(unique(d.constraintReason.Key))==height(d.constraintReason));
end

function test_aggregation_contract()
N=8; t=(0:N-1)'*300; srcCell=cell(1,3);
for j=1:3
    gross=(1:N)'*j; loss=0.02*gross; av=gross-loss; act=0.9*av;
    srcCell{j}=struct('time',t,'sourceId',"S"+j,'sourceType',"type"+j, ...
        'meterPoint','source_collection_bus','pAvailableGross',gross, ...
        'pAvailableAtPOI',av,'pRequested',av,'pAccepted',act, ...
        'pActualAtPOI',act,'pAuxLoad',zeros(N,1),'pCollectionLoss',loss, ...
        'pActualCollectionLoss',0.9*loss,'pForecastAvailable',av, ...
        'qMinAtPOI',-ones(N,1),'qMaxAtPOI',ones(N,1),'qualityFlag',true(N,1));
end
src=[srcCell{:}];
o=source_aggregation_4_3_v3(src,struct('parameterSetId','TEST_V3'));
assert(max(abs(o.aggregate.actual-sum(o.perSource.actual,2)))<1e-12);
assert(~isfield(o,'ports') && ~isfield(o,'balance'));
bad=src; bad(1).meterPoint='wrong'; didFail=false;
try, source_aggregation_4_3_v3(bad,struct); catch, didFail=true; end
assert(didFail,'Meter-point mismatch must fail.');
end
