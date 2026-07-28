function out=evaluate_scenario_coverage_4_3_v3(actual,scenarios,nominalCoverage)
%EVALUATE_SCENARIO_COVERAGE_4_3_V3 Empirical central-interval coverage diagnostics.
actual=double(actual(:)); scenarios=double(scenarios);
[N,K]=size(scenarios); nominalCoverage=double(nominalCoverage(:))';
assert(numel(actual)==N && K>=2,'actual/scenarios dimensions are inconsistent.');
assert(all(isfinite(actual)) && all(isfinite(scenarios),'all'),'Inputs must be finite.');
assert(all(nominalCoverage>0 & nominalCoverage<1),'Coverage levels must lie in (0,1).');
L=numel(nominalCoverage); lower=zeros(N,L); upper=zeros(N,L);
empirical=zeros(1,L); meanWidth=zeros(1,L);
for ell=1:L
    alpha=(1-nominalCoverage(ell))/2;
    lower(:,ell)=row_quantile(scenarios,alpha);
    upper(:,ell)=row_quantile(scenarios,1-alpha);
    empirical(ell)=mean(actual>=lower(:,ell) & actual<=upper(:,ell));
    meanWidth(ell)=mean(upper(:,ell)-lower(:,ell));
end
out=struct('nominalCoverage',nominalCoverage,'empiricalCoverage',empirical, ...
    'coverageError',empirical-nominalCoverage,'meanIntervalWidth',meanWidth, ...
    'lower',lower,'upper',upper,'median',row_quantile(scenarios,0.5));
end

function q=row_quantile(x,p)
x=sort(x,2); K=size(x,2); z=1+(K-1)*p; a=floor(z); b=ceil(z);
if a==b, q=x(:,a); else, q=x(:,a)+(z-a).*(x(:,b)-x(:,a)); end
end
