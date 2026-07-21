function out = source_aggregation_4_3_v3(sources,cfg)
%SOURCE_AGGREGATION_4_3_V3 Aggregate source models at one common meter point.
%
% This function implements Chapter 4.3 only. It does not clip EMS requests,
% dispatch storage, allocate loads, or implement grid-forming controls.
%
% sources is a nonempty struct array. Required fields for every source:
%   time                 N-by-1 time [s]
%   sourceId             text identifier
%   sourceType           text identifier: wind, pv, tidal, ...
%   meterPoint           must be identical for all sources
%   pAvailableGross      N-by-1 available generation before collection loss [W]
%   pAvailableAtPOI      N-by-1 available nonnegative generation [W]
%   pRequested           N-by-1 EMS request [W]
%   pAccepted            N-by-1 device-accepted setpoint [W]
%   pActualAtPOI         N-by-1 actual nonnegative generation [W]
%   pAuxLoad             N-by-1 source auxiliary consumption [W]
%   pCollectionLoss      N-by-1 loss upstream of the POI [W]
%   pForecastAvailable   N-by-1 forecast available generation [W]
%   qMinAtPOI/qMaxAtPOI  N-by-1 reactive capability [var]
%   qualityFlag          N-by-1 logical
%
% Optional fields:
%   pUpCapability/pDownCapability N-by-1 feasible regulation capability [W]
%   scenarioAvailable            N-by-K correlated available-power scenarios [W]
%   operatingState/constraintCode N-by-1 diagnostic codes
%
% cfg is optional:
%   scenarioProbability          1-by-K nonnegative probabilities (sum = 1)
%   parameterSetId               traceable parameter/version identifier
%   units                        defaults to P=W, Q=var, time=s

if nargin<2, cfg=struct; end
assert(isstruct(sources) && ~isempty(sources), 'sources must be a nonempty struct array.');
required = {'time','sourceId','sourceType','meterPoint','pAvailableGross','pAvailableAtPOI', ...
    'pRequested','pAccepted','pActualAtPOI','pAuxLoad','pCollectionLoss', ...
    'pForecastAvailable','qMinAtPOI','qMaxAtPOI','qualityFlag'};

for j = 1:numel(sources)
    for r = 1:numel(required)
        assert(isfield(sources(j), required{r}), ...
            'Source %d is missing field %s.', j, required{r});
    end
end

t = sources(1).time(:);
N = numel(t);
S = numel(sources);
assert(N >= 2 && all(isfinite(t)) && all(diff(t) > 0), ...
    'time must be finite and strictly increasing.');
meterPoint = string(sources(1).meterPoint);

names = strings(1,S);
types = strings(1,S);
pGross = zeros(N,S); pAv = zeros(N,S); pReq = zeros(N,S); pAcc = zeros(N,S);
pAct = zeros(N,S); pAux = zeros(N,S); pLoss = zeros(N,S);
pActualLoss=zeros(N,S);
pFcst = zeros(N,S); qMin = zeros(N,S); qMax = zeros(N,S);
quality = false(N,S); pUp = zeros(N,S); pDown = zeros(N,S);
states = cell(1,S); constraints = cell(1,S);

scenarioK = [];
scenarioBySource = cell(1,S);
for j = 1:S
    assert(isequal(sources(j).time(:), t), 'All sources must share the same time axis.');
    assert(string(sources(j).meterPoint) == meterPoint, ...
        'All P/Q values must be converted to the same meterPoint before aggregation.');
    names(j) = string(sources(j).sourceId);
    types(j) = string(sources(j).sourceType);
    pGross(:,j) = col(sources(j).pAvailableGross,N,'pAvailableGross');
    pAv(:,j) = col(sources(j).pAvailableAtPOI,N,'pAvailableAtPOI');
    pReq(:,j) = col(sources(j).pRequested,N,'pRequested');
    pAcc(:,j) = col(sources(j).pAccepted,N,'pAccepted');
    pAct(:,j) = col(sources(j).pActualAtPOI,N,'pActualAtPOI');
    pAux(:,j) = col(sources(j).pAuxLoad,N,'pAuxLoad');
    pLoss(:,j) = col(sources(j).pCollectionLoss,N,'pCollectionLoss');
    if isfield(sources(j),'pActualCollectionLoss')
        pActualLoss(:,j)=col(sources(j).pActualCollectionLoss,N,'pActualCollectionLoss');
    else
        pActualLoss(:,j)=pLoss(:,j); % Legacy contract fallback.
    end
    pFcst(:,j) = col(sources(j).pForecastAvailable,N,'pForecastAvailable');
    qMin(:,j) = col(sources(j).qMinAtPOI,N,'qMinAtPOI');
    qMax(:,j) = col(sources(j).qMaxAtPOI,N,'qMaxAtPOI');
    quality(:,j) = logical(col(sources(j).qualityFlag,N,'qualityFlag'));

    assert(all(pGross(:,j)>=0) && all(pAv(:,j)>=0) && all(pReq(:,j)>=0) && ...
        all(pAct(:,j)>=0) && all(pAux(:,j)>=0) && ...
        all(pLoss(:,j)>=0) && all(pActualLoss(:,j)>=0) && all(pFcst(:,j)>=0), ...
        'Generation, request, auxiliary load, losses and forecast must be nonnegative.');
    assert(all(pLoss(:,j)<=pGross(:,j)+tol(pGross(:,j))), ...
        'pCollectionLoss cannot exceed pAvailableGross.');
    assert(all(abs(pAv(:,j)-max(0,pGross(:,j)-pLoss(:,j)))<=tol(pGross(:,j))), ...
        'pAvailableAtPOI must equal pAvailableGross minus upstream collection loss.');
    assert(all(pAcc(:,j)>=-eps) && all(pAcc(:,j)<=pAv(:,j)+tol(pAv(:,j))), ...
        'pAccepted must lie inside the available-power boundary.');
    assert(all(pAcc(:,j)<=pReq(:,j)+tol(pReq(:,j))), ...
        'pAccepted cannot exceed the raw EMS request.');
    assert(all(pAct(:,j)<=pAv(:,j)+tol(pAv(:,j))), ...
        'pActualAtPOI cannot exceed current available generation without an explicit energy state.');
    assert(all(pActualLoss(:,j)<=pLoss(:,j)+tol(pLoss(:,j))), ...
        'Actual collection loss cannot exceed available-power collection loss.');
    assert(all(qMin(:,j)<=qMax(:,j)), 'qMinAtPOI cannot exceed qMaxAtPOI.');

    if isfield(sources(j),'pUpCapability')
        pUp(:,j) = col(sources(j).pUpCapability,N,'pUpCapability');
    else
        pUp(:,j) = max(0,pAv(:,j)-pAct(:,j));
    end
    if isfield(sources(j),'pDownCapability')
        pDown(:,j) = col(sources(j).pDownCapability,N,'pDownCapability');
    else
        pDown(:,j) = max(0,pAct(:,j));
    end
    assert(all(pUp(:,j)>=0) && all(pDown(:,j)>=0), ...
        'Regulation capability must be nonnegative.');

    if isfield(sources(j),'operatingState'), states{j}=sources(j).operatingState; end
    if isfield(sources(j),'constraintCode'), constraints{j}=sources(j).constraintCode; end

    if isfield(sources(j),'scenarioAvailable') && ~isempty(sources(j).scenarioAvailable)
        sc = double(sources(j).scenarioAvailable);
        assert(size(sc,1)==N && all(isfinite(sc),'all') && all(sc>=0,'all'), ...
            'scenarioAvailable must be a finite nonnegative N-by-K matrix.');
        if isempty(scenarioK), scenarioK=size(sc,2); end
        assert(size(sc,2)==scenarioK, 'All sources must use the same scenario count.');
        scenarioBySource{j}=sc;
    elseif ~isempty(scenarioK)
        error('All sources must provide scenarios when any source provides them.');
    end
end

% Catch a missing scenario on a source appearing before the first scenario-bearing source.
if ~isempty(scenarioK)
    assert(all(~cellfun(@isempty,scenarioBySource)), ...
        'All sources must provide scenarioAvailable.');
end

scenarioAggregate = [];
scenarioProbability = [];
if ~isempty(scenarioK)
    scenarioAggregate = zeros(N,scenarioK);
    for j=1:S, scenarioAggregate=scenarioAggregate+scenarioBySource{j}; end
    if isfield(cfg,'scenarioProbability') && ~isempty(cfg.scenarioProbability)
        scenarioProbability=double(cfg.scenarioProbability(:))';
        assert(numel(scenarioProbability)==scenarioK && ...
            all(isfinite(scenarioProbability)) && all(scenarioProbability>=0), ...
            'scenarioProbability must be a finite nonnegative 1-by-K vector.');
        assert(abs(sum(scenarioProbability)-1)<=1e-10, ...
            'scenarioProbability must sum to one.');
    else
        scenarioProbability=ones(1,scenarioK)/scenarioK;
    end
end

out = struct;
out.time = t;
out.sourceId = names;
out.sourceType = types;
out.meterPoint = meterPoint;
perSource = struct('availableGross',pGross,'available',pAv,'requested',pReq,'accepted',pAcc, ...
    'actual',pAct,'auxLoad',pAux,'collectionLoss',pLoss, ...
    'actualCollectionLoss',pActualLoss, ...
    'forecastAvailable',pFcst,'qMin',qMin,'qMax',qMax, ...
    'qualityFlag',quality,'upCapability',pUp,'downCapability',pDown, ...
    'operatingState',{states},'constraintCode',{constraints});
aggregate = struct('available',sum(pAv,2),'requested',sum(pReq,2), ...
    'accepted',sum(pAcc,2),'actual',sum(pAct,2), ...
    'sourceAuxLoad',sum(pAux,2), ...
    'availableCollectionLoss',sum(pLoss,2), ...
    'actualCollectionLoss',sum(pActualLoss,2), ...
    'forecastAvailable',sum(pFcst,2),'qMin',sum(qMin,2), ...
    'qMax',sum(qMax,2),'upCapability',sum(pUp,2), ...
    'downCapability',sum(pDown,2),'validRow',all(quality,2));
out.meta = struct('time',t,'meterPoint',meterPoint,'sourceId',names, ...
    'sourceType',types,'parameterSetId',textcfg(cfg,'parameterSetId','UNSPECIFIED'), ...
    'units',textcfg(cfg,'units','P=W; Q=var; time=s'));
out.perSource = perSource;
out.source = perSource; % Backward-compatible alias; prefer perSource in new code.
out.aggregate = aggregate;
out.losses = struct('commandCurtailment',max(0,pAv-pAcc), ...
    'trackingDifference',pAct-pAcc, ...
    'unacceptedRequest',max(0,pReq-pAcc), ...
    'availableCollectionLoss',pLoss,'actualCollectionLoss',pActualLoss, ...
    'forecastError',pAct-pFcst);
out.scenario = struct('availableBySource',{scenarioBySource}, ...
    'availableAggregate',scenarioAggregate,'probability',scenarioProbability);
out.state = struct('operatingState',{states},'constraintCode',{constraints}, ...
    'qualityFlag',quality);
out.interface = struct( ...
    'toBus4_4',struct('pSourceActual',aggregate.actual, ...
        'pSourceAuxLoad',aggregate.sourceAuxLoad, ...
        'actualCollectionLossAlreadyDeducted',aggregate.actualCollectionLoss, ...
        'meterPoint',meterPoint,'qualityFlag',aggregate.validRow), ...
    'toStorage4_5',struct('pUpCapability',aggregate.upCapability, ...
        'pDownCapability',aggregate.downCapability,'qMin',aggregate.qMin, ...
        'qMax',aggregate.qMax,'forecastError',aggregate.actual-aggregate.forecastAvailable), ...
    'toEMS4_8_4_9',struct('pAvailable',pAv,'pForecast',pFcst, ...
        'pAccepted',pAcc,'pActual',pAct,'pUpCapability',pUp, ...
        'pDownCapability',pDown,'scenarioAggregate',scenarioAggregate, ...
        'scenarioProbability',scenarioProbability,'qualityFlag',quality));
out.metrics = [];
end

function x = col(x,N,name)
x = double(x(:));
assert(numel(x)==N && all(isfinite(x)), '%s must be a finite N-by-1 signal.',name);
end

function y = tol(x)
y = max(1e-6,1e-9*max(1,abs(x)));
end

function x = textcfg(cfg,name,default)
if isfield(cfg,name)
    candidate=string(cfg.(name));
    assert(isscalar(candidate),'%s must be scalar text.',name);
else
    candidate="";
end
if strlength(candidate)>0
    x=candidate;
else
    x=string(default);
end
end
