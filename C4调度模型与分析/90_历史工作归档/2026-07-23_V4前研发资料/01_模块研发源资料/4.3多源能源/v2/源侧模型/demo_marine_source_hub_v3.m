% Blue Hub V3 interface demo. Every numerical value is
% [ASSUMPTION - CALIBRATE WITH OEM/PROJECT DATA].
clear; clc; rng(7);
thisDir=fileparts(mfilename('fullpath'));
complementarityDir=fullfile(fileparts(thisDir),'互补体系模型');
assert(isfolder(complementarityDir), ...
    'Cannot locate sibling folder: v2/互补体系模型.');
addpath(thisDir,complementarityDir);

dt=300; t=(0:dt:24*3600)'; h=t/3600; N=numel(t);
cap=[85 10 5]*1e6;

wind=max(0,min(1,0.55+0.22*sin(2*pi*h/17)+0.05*randn(N,1)))*cap(1);
pv=max(0,sin(pi*mod(h-6,24)/12))*cap(2);
tidal=abs(sin(2*pi*h/12.42)).^3*cap(3);
p=[wind,pv,tidal];

K=10; common=0.02*randn(N,K); sourceType={'wind','pv','tidal'};
sourceCell=cell(1,3);
for j=1:3
    raw=p(:,j); collectionLoss=0.01*raw;
    av=max(0,raw-collectionLoss); % available generation at the common POI
    requested=1.03*av; accepted=av; actual=0.995*accepted;
    actualLoss=(actual/(1-0.01))*0.01;
    q=sqrt(max(0,(1.05*cap(j)).^2-actual.^2));
    sc=max(0,av.*(1+common+0.03*randn(N,K)));
    sourceCell{j}=struct('time',t,'sourceId',sprintf('S%d',j), ...
        'sourceType',sourceType{j},'meterPoint','source_collection_bus', ...
        'pAvailableGross',raw,'pAvailableAtPOI',av, ...
        'pRequested',requested,'pAccepted',accepted, ...
        'pActualAtPOI',actual,'pAuxLoad',0.003*cap(j)*ones(N,1), ...
        'pCollectionLoss',collectionLoss,'pActualCollectionLoss',actualLoss, ...
        'pForecastAvailable',0.99*av, ...
        'qMinAtPOI',-q,'qMaxAtPOI',q,'qualityFlag',true(N,1), ...
        'scenarioAvailable',sc);
end
sources=[sourceCell{:}];

ports=struct('pExport',45e6,'pElectrolyzer',12e6,'pCompute',8e6, ...
    'pMarine',1e6,'pCommonAux',0.5e6,'pPostPOILoss',0.5e6);
cfg=struct('capacity',cap,'metricWindowsSeconds',[dt 3600 6*3600], ...
    'lowOutputFraction',0.2,'scenarioProbability',ones(1,K)/K, ...
    'parameterSetId','DEMO_ASSUMPTION_V3', ...
    'units','P=W; Q=var; time=s');

first=marine_source_hub_v3(sources,ports,struct(),cfg);
required=first.bus.balance.storageRequired;
storage.actual=min(18e6,max(-15e6,required)); % mock 4.5 response only
out=marine_source_hub_v3(sources,ports,storage,cfg);

assert(max(abs(out.bus.balance.closedMismatch- ...
    (out.source.aggregate.actual+storage.actual- ...
    out.bus.ports.servedDemand)))<1e-6);
assert(all(out.source.source.actual<=out.source.source.available+1e-6,'all'));
assert(isequal(out.source.meta.meterPoint,"source_collection_bus"));
assert(abs(sum(out.source.scenario.probability)-1)<1e-12);
assert(isequal(out.source.interface.toBus4_4.pSourceActual, ...
    out.source.aggregate.actual));
assert(isequal(out.interface.busToStorage4_5.pRequired, ...
    out.bus.balance.storageRequired));
fprintf('V3 interface demo completed. MATLAB/Simulink dynamic validation is still required.\n');
