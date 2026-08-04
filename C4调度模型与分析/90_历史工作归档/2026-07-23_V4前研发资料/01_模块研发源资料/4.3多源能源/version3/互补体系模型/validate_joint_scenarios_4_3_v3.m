function out=validate_joint_scenarios_4_3_v3(actualBySource,scenarioBySource,probability,capacity)
%VALIDATE_JOINT_SCENARIOS_4_3_V3 Quality diagnostics for external scenarios.
% This function validates, but does not invent, joint renewable scenarios.
[N,S]=size(actualBySource); K=size(scenarioBySource,3);
assert(isequal(size(scenarioBySource),[N,S,K]),'scenarioBySource must be N-by-S-by-K.');
probability=double(probability(:))'; capacity=reshape(double(capacity),1,[]);
assert(numel(probability)==K && all(probability>=0) && abs(sum(probability)-1)<1e-10, ...
    'Scenario probabilities must be nonnegative and sum to one.');
assert(numel(capacity)==S && all(capacity>0),'capacity must be positive 1-by-S.');
assert(all(isfinite(scenarioBySource),'all') && all(scenarioBySource>=0,'all'), ...
    'Scenarios must be finite and nonnegative.');
cap3=reshape(capacity,1,S,1);
assert(all(scenarioBySource<=cap3+max(1,1e-9*cap3),'all'), ...
    'Scenario power cannot exceed installed capacity.');

actualCF=actualBySource./capacity;
actualCorr=corrcoef(actualCF);
scenarioCorr=zeros(S,S,K); scenarioRampPersistence=zeros(1,K);
for k=1:K
    cf=scenarioBySource(:,:,k)./capacity;
    scenarioCorr(:,:,k)=corrcoef(cf);
    total=sum(cf,2);
    if N>=3
        scenarioRampPersistence(k)=corr(total(1:end-1),total(2:end),'Rows','complete');
    else
        scenarioRampPersistence(k)=NaN;
    end
end
weightedCorr=sum(scenarioCorr.*reshape(probability,1,1,K),3);
out=struct('actualCorrelation',actualCorr,'weightedScenarioCorrelation',weightedCorr, ...
    'correlationAbsoluteError',abs(weightedCorr-actualCorr), ...
    'meanCorrelationAbsoluteError',mean(abs(weightedCorr-actualCorr),'all','omitnan'), ...
    'scenarioRampPersistence',scenarioRampPersistence, ...
    'probability',probability,'scenarioCount',K);
end
