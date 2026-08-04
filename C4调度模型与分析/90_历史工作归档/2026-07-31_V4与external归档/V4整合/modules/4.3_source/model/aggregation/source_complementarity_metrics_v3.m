function out = source_complementarity_metrics_v3(time,pActual,quality,capacity,windows,lowFraction)
%SOURCE_COMPLEMENTARITY_METRICS_V3 Multi-timescale diagnostics for 4.3.
% P05 is reported as an empirical low quantile, not capacity credit/ELCC.

t=time(:); [N,S]=size(pActual); quality=logical(quality);
assert(numel(t)==N && all(diff(t)>0),'Invalid time axis.');
assert(isequal(size(quality),[N,S]),'quality must match pActual.');
capacity=reshape(double(capacity),1,[]);
assert(numel(capacity)==S && all(capacity>0),'capacity must be positive 1-by-S.');
assert(all(pActual>=0,'all') && all(windows>0),'Power and windows must be nonnegative/positive.');
dt=median(diff(t));
assert(max(abs(diff(t)-dt))<=max(1e-6,0.01*dt),'Time axis must be approximately uniform.');

L=numel(windows); corrPower=nan(S,S,L); corrRamp=nan(S,S,L);
cv=nan(1,L); p05=nan(1,L); low=nan(1,L); coverage=zeros(1,L);
rampP01=nan(1,L); rampP99=nan(1,L);
lowEventCount=zeros(1,L); maxLowDuration=zeros(1,L); lowEnergyDeficit=zeros(1,L);

for ell=1:L
    n=max(1,round(windows(ell)/dt));
    pWin=movmean(pActual,[n-1 0],1,'Endpoints','shrink');
    complete=(1:N)'>=n;
    validCount=movsum(all(quality,2),[n-1 0],1,'Endpoints','shrink');
    rows=complete & validCount==n;
    coverage(ell)=mean(rows);
    if nnz(rows)<3, continue; end
    cf=pWin./capacity;
    corrPower(:,:,ell)=corrcoef(cf(rows,:));
    total=sum(pWin,2); x=total(rows);
    cv(ell)=std(x)/max(eps,mean(x));
    p05(ell)=qntl(x,0.05);
    threshold=lowFraction*sum(capacity);
    isLow=rows & total<threshold;
    low(ell)=mean(x<threshold);
    [lowEventCount(ell),maxLowDuration(ell)]=event_stats(isLow,dt);
    lowEnergyDeficit(ell)=sum(max(0,threshold-total(isLow)))*dt/3600;

    % Only adjacent valid rows are differenced; data gaps cannot create ramps.
    pair=rows(2:end)&rows(1:end-1);
    rampTotal=diff(total)/dt;
    if nnz(pair)>=2
        rampP01(ell)=qntl(rampTotal(pair),0.01);
        rampP99(ell)=qntl(rampTotal(pair),0.99);
        r=diff(cf,1,1)/dt;
        corrRamp(:,:,ell)=corrcoef(r(pair,:));
    end
end

out=struct('scaleSeconds',reshape(windows,1,[]),'powerCorrelation',corrPower, ...
    'rampCorrelation',corrRamp,'coefficientVariation',cv, ...
    'empiricalLowQuantileP05',p05,'lowOutputFraction',low, ...
    'rampP01WPerS',rampP01,'rampP99WPerS',rampP99,'coverage',coverage);
out.lowEventCount=lowEventCount;
out.maxLowDurationSeconds=maxLowDuration;
out.lowEnergyDeficitWh=lowEnergyDeficit;
end

function [count,maxDuration]=event_stats(flag,dt)
flag=logical(flag(:)); edge=diff([false;flag;false]);
starts=find(edge==1); stops=find(edge==-1)-1;
count=numel(starts);
if count==0, maxDuration=0; else, maxDuration=max(stops-starts+1)*dt; end
end

function q=qntl(x,p)
x=sort(x(isfinite(x))); assert(~isempty(x),'No finite samples.');
z=1+(numel(x)-1)*p; a=floor(z); b=ceil(z);
if a==b, q=x(a); else, q=x(a)+(z-a)*(x(b)-x(a)); end
end
