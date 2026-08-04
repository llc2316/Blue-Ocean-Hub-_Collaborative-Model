function out = bus_balance_4_4_v3(source, ports, storage)
%BUS_BALANCE_4_4_V3 Pure Chapter 4.4 active-power conservation.
%
% Positive injections: source generation, other generation, storage
% discharge and permitted grid import. Positive consumptions: export,
% electrolyzer, compute, marine use, auxiliary loads, post-POI losses and
% spill/dump load. Storage charge is represented by storage.actual < 0.

if nargin<3, storage=struct; end
assert(isfield(source,'time') && isfield(source,'aggregate'), ...
    'source must be the output of source_aggregation_4_3_v3.');
t=source.time(:); N=numel(t);

pExport=sig(ports,'pExport',0,N);
pElectrolyzer=sig(ports,'pElectrolyzer',0,N);
pCompute=sig(ports,'pCompute',0,N);
pMarine=sig(ports,'pMarine',0,N);
pCommonAux=sig(ports,'pCommonAux',0,N);
pPostPOILoss=sig(ports,'pPostPOILoss',0,N);
pOther=sig(ports,'pOtherInjection',0,N);
pGridImport=sig(ports,'pGridImport',0,N);
pSpill=sig(ports,'pSpill',0,N);
pUnserved=sig(ports,'pUnservedLoad',0,N); % reliability accounting only

allNonnegative=[pExport,pElectrolyzer,pCompute,pMarine,pCommonAux, ...
    pPostPOILoss,pOther,pGridImport,pSpill,pUnserved];
assert(all(allNonnegative>=0,'all'),'All port magnitudes must be nonnegative.');

pSource=source.aggregate.actual;
pSourceAux=source.aggregate.sourceAuxLoad;
servedDemand=pExport+pElectrolyzer+pCompute+pMarine+pSourceAux+ ...
    pCommonAux+pPostPOILoss+pSpill;
injectionWithoutStorage=pSource+pOther+pGridImport;
storageRequired=servedDemand-injectionWithoutStorage;

storageProvided=isfield(storage,'actual') && ~isempty(storage.actual);
if storageProvided
    pStorage=sig(storage,'actual',0,N);
    closedMismatch=injectionWithoutStorage+pStorage-servedDemand;
else
    pStorage=[]; closedMismatch=[];
end

residualScenario=[];
if isfield(source,'scenario') && ...
        ~isempty(source.scenario.availableAggregate)
    residualScenario=servedDemand-pOther-pGridImport- ...
        source.scenario.availableAggregate;
end

out=struct;
out.time=t;
out.ports=struct('export',pExport,'electrolyzer',pElectrolyzer, ...
    'compute',pCompute,'marine',pMarine,'sourceAux',pSourceAux, ...
    'commonAux',pCommonAux,'postPOILoss',pPostPOILoss, ...
    'otherInjection',pOther,'gridImport',pGridImport,'spill',pSpill, ...
    'unservedLoad',pUnserved,'servedDemand',servedDemand);
out.balance=struct('injectionWithoutStorage',injectionWithoutStorage, ...
    'storageRequired',storageRequired,'storageActualProvided',storageProvided, ...
    'storageActual',pStorage,'closedMismatch',closedMismatch, ...
    'netLoadResidualScenario',residualScenario);
out.diagnostics=struct('servedDemandEnergyMWh',trapz(t,servedDemand)/3.6e9, ...
    'unservedEnergyMWh',trapz(t,pUnserved)/3.6e9, ...
    'spillEnergyMWh',trapz(t,pSpill)/3.6e9);
if storageProvided
    out.diagnostics.absoluteMismatchEnergyMWh=trapz(t,abs(closedMismatch))/3.6e9;
else
    out.diagnostics.absoluteMismatchEnergyMWh=NaN;
end
end

function x=sig(s,name,default,N)
if isfield(s,name), x=s.(name); else, x=default; end
if isscalar(x), x=repmat(double(x),N,1); else, x=double(x(:)); end
assert(numel(x)==N && all(isfinite(x)),'%s must be scalar or finite N-by-1.',name);
end
