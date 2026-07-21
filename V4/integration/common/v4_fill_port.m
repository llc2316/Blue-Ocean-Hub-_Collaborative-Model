function p=v4_fill_port(timeH,meter,requested,accepted,actual,minMW,maxMW,code,state)
%V4_FILL_PORT Fill one BLUE_HUB_CH4_SCHEMA_V2 dispatch port.
p=common_dispatch_port_4_2(timeH,meter);
N=numel(timeH);
p.requestedMW=series(requested,N);
p.acceptedMW=series(accepted,N);
p.actualMW=series(actual,N);
p.minMW=series(minMW,N);
p.maxMW=series(maxMW,N);
p.upCapabilityMW=max(0,p.maxMW-p.actualMW);
p.downCapabilityMW=max(0,p.actualMW-p.minMW);
p.constraintCode=textseries(code,N);
p.operatingState=textseries(state,N);
p.qualityFlag=true(N,1);
end

function x=series(x,N)
if isscalar(x), x=repmat(double(x),N,1); else, x=double(x(:)); end
assert(numel(x)==N && all(isfinite(x)),'Port series must be finite N-by-1.');
assert(all(x>=0),'Public port magnitudes must be nonnegative.');
end

function x=textseries(x,N)
x=string(x);
if isscalar(x), x=repmat(x,N,1); else, x=x(:); end
assert(numel(x)==N,'Text series must have N rows.');
end

