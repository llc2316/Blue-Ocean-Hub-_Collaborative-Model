function [out,state] = c5_kalman_prior_posterior_policy( ...
    action,state,base,cfg,strategy,eventCode,t)
%C5_KALMAN_PRIOR_POSTERIOR_POLICY Causal online multi-source forecast.
%
% Information boundary: hour t planning never reads hour t generation.
% The dynamic posterior is updated only after settlement. Hour-of-day/event
% profiles contain earlier observations only. Because the dynamic estimate
% and profile use overlapping history, their unknown correlation is handled
% with covariance intersection rather than an independence assumption.
%
% Formula sources:
%   Kalman, 1960, Journal of Basic Engineering, DOI 10.1115/1.3662552.
%   Julier & Uhlmann, ACC 1997, DOI 10.1109/ACC.1997.609105.
% Noise fractions, CI weight and event quantiles are
% [假设值，待企业调研校准].

action=lower(char(string(action)));
switch action
    case 'initialize'
        out=[];
        state=initialize_state(base,cfg,strategy);
    case 'plan'
        assert(~isempty(state),'Forecast state must be initialized.');
        [out,state]=plan_hour(state,base,strategy,eventCode,t);
    case 'update'
        assert(~isempty(state),'Forecast state must be initialized.');
        state=update_hour(state,base,strategy,eventCode,t);
        out=[];
    otherwise
        error('Unsupported prior-posterior action: %s',action);
end
end

function state=initialize_state(base,cfg,strategy)
[names,caps]=source_metadata(base,cfg);
S=numel(names);
initialFactor=double(field_or(strategy, ...
    'initialPlanningCapacityFactor',0.25));
measurementNoiseFraction=double(field_or(strategy, ...
    'kalmanMeasurementNoiseFraction',0.10));
processNoiseFraction=double(field_or(strategy, ...
    'kalmanProcessNoiseFraction',0.20));
dynamicCIWeight=double(field_or(strategy,'kalmanDynamicCIWeight',0.65));
assert(measurementNoiseFraction>0 && processNoiseFraction>0, ...
    'Kalman noise fractions must be positive.');
assert(dynamicCIWeight>0 && dynamicCIWeight<1, ...
    'kalmanDynamicCIWeight must be strictly between zero and one.');

state=struct;
state.sourceNames=names;
state.sourceCaps=caps(:)';
state.posteriorMean=max(0,initialFactor*caps(:)');
state.posteriorVar=max(1e-6,(0.40*caps(:)').^2);
state.measurementNoiseVar=max(1e-6, ...
    (measurementNoiseFraction*caps(:)').^2);
state.processNoiseVar=max(1e-6,(processNoiseFraction*caps(:)').^2);
state.dynamicCIWeight=dynamicCIWeight;
state.count=zeros(24,5,S);
state.mean=zeros(24,5,S);
state.m2=zeros(24,5,S);
state.globalCount=zeros(1,S);
state.globalMean=zeros(1,S);
state.globalM2=zeros(1,S);
state.lastForecastMean=state.posteriorMean;
state.lastForecastVar=state.posteriorVar;
state.lastActual=nan(1,S);
state.warmupObservationCount=0;

% Optional warm-up must consist exclusively of observations before the
% evaluated window. It changes the estimator state only; physical BESS/H2
% states are never backfilled or injected.
if isfield(strategy,'onlinePriorHistory') && ...
        ~isempty(strategy.onlinePriorHistory)
    state=warm_start(state,strategy.onlinePriorHistory,strategy);
end
end

function [plan,state]=plan_hour(state,base,strategy,eventCode,t)
windowH=double(field_or(strategy,'planningWindowH',1));
windowH=max(1,min(numel(base.timeH)-t+1,round(windowH)));
[planningWindowBySource,forecastWindowMean,forecastWindowVar, ...
    profileWindowMean,riskQuantileWindow,riskLevelWindow]= ...
    forecast_window(state,base,strategy,eventCode,t,windowH);
event=eventCode(t);
profileMean=profileWindowMean(1,:);
forecastMean=forecastWindowMean(1,:);
forecastVar=forecastWindowVar(1,:);
planningBySource=planningWindowBySource(1,:);
q=riskQuantileWindow(1);
riskLevel=riskLevelWindow(1);

state.lastForecastMean=forecastMean;
state.lastForecastVar=forecastVar;
plan=struct( ...
    'sourceNames',{state.sourceNames}, ...
    'priorBySourceMW',profileMean, ...
    'posteriorBySourceMW',forecastMean, ...
    'planningBySourceMW',planningBySource, ...
    'planningWindowBySourceMW',planningWindowBySource, ...
    'planningWindowAvailableMW',sum(planningWindowBySource,2), ...
    'priorAvailableMW',sum(profileMean), ...
    'posteriorAvailableMW',sum(forecastMean), ...
    'planningAvailableMW',sum(planningBySource), ...
    'riskQuantile',q, ...
    'eventRiskLevel',riskLevel, ...
    'forecastSigmaMW',sum(sqrt(forecastVar)), ...
    'warmupObservationCount',state.warmupObservationCount, ...
    'definition',"ONLINE_KALMAN_PLUS_COVARIANCE_INTERSECTION");
end

function [planningBySource,forecastMean,forecastVar,profileMean, ...
    riskQuantile,riskLevel]= ...
    forecast_window(state,base,strategy,eventCode,t,windowH)
S=numel(state.sourceNames);
planningBySource=zeros(windowH,S);
forecastMean=zeros(windowH,S);
forecastVar=zeros(windowH,S);
profileMean=zeros(windowH,S);
riskQuantile=zeros(windowH,1);
riskLevel=zeros(windowH,1);
for j=1:windowH
    tau=t+j-1;
    event=eventCode(tau);
    bucket=time_bucket(base,tau);
    eventBucket=event_bucket(event);
    [thisProfileMean,thisProfileVar,hasProfile]= ...
        lookup_profile(state,bucket,eventBucket);
    dynamicMean=state.posteriorMean;
    dynamicVar=state.posteriorVar+j*state.processNoiseVar;
    if hasProfile
        [thisForecastMean,thisForecastVar]=covariance_intersection( ...
            dynamicMean,dynamicVar,thisProfileMean, ...
            thisProfileVar+j*state.processNoiseVar, ...
            state.dynamicCIWeight);
    else
        thisProfileMean=dynamicMean;
        thisForecastMean=dynamicMean;
        thisForecastVar=dynamicVar;
    end
    thisForecastMean=min(state.sourceCaps,max(0,thisForecastMean));
    thisForecastVar=max(1e-6,thisForecastVar);

    [q,z,level]=event_risk(event,strategy);
    thisPlanning=thisForecastMean+z*sqrt(thisForecastVar);
    thisPlanning=min(state.sourceCaps,max(0,thisPlanning));
    if strcmpi(char(event),'TYPHOON_PASSAGE')
        thisPlanning(:)=0;
    end

    profileMean(j,:)=thisProfileMean;
    forecastMean(j,:)=thisForecastMean;
    forecastVar(j,:)=thisForecastVar;
    planningBySource(j,:)=thisPlanning;
    riskQuantile(j)=q;
    riskLevel(j)=level;
end
end

function state=update_hour(state,base,strategy,eventCode,t)
actual=actual_by_source(base,state,t);
innovation=actual-state.lastForecastMean;
K=state.lastForecastVar./ ...
    (state.lastForecastVar+state.measurementNoiseVar);
state.posteriorMean=state.lastForecastMean+K.*innovation;
state.posteriorMean=min(state.sourceCaps,max(0,state.posteriorMean));
state.posteriorVar=max(1e-6,(1-K).*state.lastForecastVar);
state.lastActual=actual;
state=update_profiles(state,actual,time_bucket(base,t), ...
    event_bucket(eventCode(t)));

multiplier=double(field_or(strategy, ...
    'kalmanEventShockVarianceMultiplier',4));
event=char(eventCode(t));
if any(strcmpi(event,{'TYPHOON_WARNING','TYPHOON_PASSAGE'}))
    state.posteriorVar=max(state.posteriorVar, ...
        multiplier*state.processNoiseVar);
end
end

function state=warm_start(state,history,strategy)
assert(isstruct(history) && isfield(history,'timeH') && ...
    isfield(history,'eventCode'), ...
    'onlinePriorHistory requires timeH and eventCode.');
actual=history_actual_matrix(history,state.sourceNames,state.sourceCaps);
timeH=double(history.timeH(:));
eventCode=string(history.eventCode(:));
assert(size(actual,1)==numel(timeH) && numel(eventCode)==numel(timeH), ...
    'onlinePriorHistory fields must have equal row counts.');
for k=1:numel(timeH)
    predictedVar=state.posteriorVar+state.processNoiseVar;
    K=predictedVar./(predictedVar+state.measurementNoiseVar);
    state.posteriorMean=state.posteriorMean+ ...
        K.*(actual(k,:)-state.posteriorMean);
    state.posteriorMean=min(state.sourceCaps,max(0,state.posteriorMean));
    state.posteriorVar=max(1e-6,(1-K).*predictedVar);
    bucket=mod(round(timeH(k)),24)+1;
    state=update_profiles(state,actual(k,:),bucket, ...
        event_bucket(eventCode(k)));
    event=char(eventCode(k));
    if any(strcmpi(event,{'TYPHOON_WARNING','TYPHOON_PASSAGE'}))
        multiplier=double(field_or(strategy, ...
            'kalmanEventShockVarianceMultiplier',4));
        state.posteriorVar=max(state.posteriorVar, ...
            multiplier*state.processNoiseVar);
    end
end
state.lastForecastMean=state.posteriorMean;
state.lastForecastVar=state.posteriorVar;
state.warmupObservationCount=numel(timeH);
end

function state=update_profiles(state,actual,bucket,eventBucket)
for s=1:numel(actual)
    [state.count(bucket,eventBucket,s), ...
     state.mean(bucket,eventBucket,s), ...
     state.m2(bucket,eventBucket,s)] = update_stats( ...
        state.count(bucket,eventBucket,s), ...
        state.mean(bucket,eventBucket,s), ...
        state.m2(bucket,eventBucket,s),actual(s));
    [state.globalCount(s),state.globalMean(s),state.globalM2(s)] = ...
        update_stats(state.globalCount(s),state.globalMean(s), ...
        state.globalM2(s),actual(s));
end
end

function [meanValue,varValue]=covariance_intersection( ...
    meanA,varA,meanB,varB,weightA)
% Scalar diagonal CI, applied source by source.
precision=weightA./varA+(1-weightA)./varB;
varValue=1./precision;
meanValue=varValue.*(weightA.*meanA./varA+ ...
    (1-weightA).*meanB./varB);
end

function actual=history_actual_matrix(history,names,caps)
if numel(names)==3
    required={'pWindAvailableMW','pPVAvailableMW','pTidalAvailableMW'};
    assert(all(isfield(history,required)), ...
        'Multi-source onlinePriorHistory is incomplete.');
    actual=[double(history.pWindAvailableMW(:)), ...
        double(history.pPVAvailableMW(:)), ...
        double(history.pTidalAvailableMW(:))];
else
    assert(isfield(history,'pSourceAvailableMW'), ...
        'Aggregate onlinePriorHistory is incomplete.');
    actual=double(history.pSourceAvailableMW(:));
end
actual=min(repmat(caps,size(actual,1),1),max(0,actual));
end

function [names,caps]=source_metadata(base,cfg)
if isfield(base,'pWindAvailableMW') && ...
        isfield(base,'pPVAvailableMW') && ...
        isfield(base,'pTidalAvailableMW')
    names=["wind","pv","tidal"];
    caps=[cfg.source.windInstalledMW, ...
        cfg.source.pvInstalledMW,cfg.source.tidalInstalledMW];
else
    names="aggregate";
    caps=cfg.source.installedMW;
end
caps=max(0,double(caps));
end

function actual=actual_by_source(base,state,t)
if numel(state.sourceNames)==3 && ...
        isfield(base,'pWindAvailableMW') && ...
        isfield(base,'pPVAvailableMW') && ...
        isfield(base,'pTidalAvailableMW')
    actual=[double(base.pWindAvailableMW(t)), ...
        double(base.pPVAvailableMW(t)), ...
        double(base.pTidalAvailableMW(t))];
else
    actual=double(base.pSourceAvailableMW(t));
end
actual=min(state.sourceCaps,max(0,actual));
end

function [profileMean,profileVar,hasProfile]= ...
    lookup_profile(state,bucket,eventBucket)
S=numel(state.sourceNames);
profileMean=zeros(1,S);
profileVar=zeros(1,S);
hasProfile=false;
for s=1:S
    c=state.count(bucket,eventBucket,s);
    if c>=2
        profileMean(s)=state.mean(bucket,eventBucket,s);
        profileVar(s)=max(1e-6,state.m2(bucket,eventBucket,s)/(c-1));
        hasProfile=true;
    elseif state.globalCount(s)>=2
        profileMean(s)=state.globalMean(s);
        profileVar(s)=max(1e-6, ...
            state.globalM2(s)/(state.globalCount(s)-1));
        hasProfile=true;
    else
        profileMean(s)=state.posteriorMean(s);
        profileVar(s)=state.posteriorVar(s);
    end
end
end

function [count,meanValue,m2]=update_stats(count,meanValue,m2,value)
count=count+1;
delta=value-meanValue;
meanValue=meanValue+delta/count;
delta2=value-meanValue;
m2=m2+delta*delta2;
end

function bucket=time_bucket(base,t)
bucket=mod(round(double(base.timeH(t))),24)+1;
end

function idx=event_bucket(eventCode)
switch upper(char(eventCode))
    case 'NORMAL'
        idx=1;
    case {'LOW_RESOURCE_WATCH','WATCH'}
        idx=2;
    case 'TYPHOON_WARNING'
        idx=3;
    case 'TYPHOON_PASSAGE'
        idx=4;
    case 'TYPHOON_RECOVERY'
        idx=5;
    otherwise
        idx=1;
end
end

function [q,z,riskLevel]=event_risk(eventCode,strategy)
event=upper(char(eventCode));
switch event
    case {'LOW_RESOURCE_WATCH','WATCH'}
        q=double(field_or(strategy,'kalmanWatchQuantile',0.30));
        riskLevel=1;
    case 'TYPHOON_WARNING'
        q=double(field_or(strategy,'kalmanWarningQuantile',0.10));
        riskLevel=2;
    case 'TYPHOON_PASSAGE'
        q=double(field_or(strategy,'kalmanPassageQuantile',0.05));
        riskLevel=3;
    case 'TYPHOON_RECOVERY'
        q=double(field_or(strategy,'kalmanRecoveryQuantile',0.20));
        riskLevel=1;
    otherwise
        q=double(field_or(strategy,'kalmanNormalQuantile',0.50));
        riskLevel=0;
end
assert(q>0 && q<1,'Risk quantile must be strictly between zero and one.');
z=sqrt(2)*erfinv(2*q-1);
end

function value=field_or(s,name,defaultValue)
if isstruct(s) && isfield(s,name), value=s.(name); else, value=defaultValue; end
end
