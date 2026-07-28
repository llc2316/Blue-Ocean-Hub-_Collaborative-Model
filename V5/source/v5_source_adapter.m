function [dispatchInput,detail] = v5_source_adapter(cfg,sourceCase)
%V5_SOURCE_ADAPTER Convert the embedded V4 4.3 engine to V5 input fields.
%
% Supported modes:
%   device_inputs               Run supplied wind/PV/tidal device inputs.
%   v4_public_baseline_snapshot Run the copied synthetic V4 baseline.
%
% The adapter publishes available generation at MP-03. It does not dispatch
% storage, allocate loads, calculate revenue or close the common bus.

assert(isstruct(sourceCase),'sourceCase must be a struct.');
sourceRoot=fileparts(mfilename('fullpath'));
v5Root=fileparts(sourceRoot);
engineRoot=fullfile(v5Root,'foundation','modules','4.3_source');
assert(isfolder(engineRoot), ...
    'Missing unique V5 4.3 source module: %s',engineRoot);
add_engine_paths(engineRoot);

if isfield(sourceCase,'mode')
    mode=char(string(sourceCase.mode));
elseif any(isfield(sourceCase,{'wind','pv','tidal'}))
    mode='device_inputs';
else
    error('sourceCase requires mode or at least one wind/PV/tidal input.');
end

switch mode
    case 'device_inputs'
        raw=run_device_inputs(cfg,sourceCase);
        profile=profile_from_aggregate(raw.source);
        sourceStatus='DEVICE_INPUTS_USING_EMBEDDED_V4_4_3_ENGINE';
    case 'v4_public_baseline_snapshot'
        [~,raw]=evalc('demo_public_baseline_v2(false)');
        profile=scaled_baseline_profile(cfg,raw.source);
        sourceStatus='SYNTHETIC_V4_PUBLIC_BASELINE_SCALED_TO_V5_CAPACITY';
    otherwise
        error('Unsupported V5 source mode: %s',mode);
end

[hourly,timeH,resamplingAudit]=resample_profile(profile,cfg,sourceCase);
validate_type_capacities(hourly.availableBySourceMW, ...
    profile.sourceType,cfg);
if any(~hourly.qualityBySource,'all')
    allowInvalid=logical(option(sourceCase,'allowInvalidQuality',false));
    assert(allowInvalid, ...
        ['Source input contains invalid-quality intervals. Set ', ...
         'allowInvalidQuality=true only for an explicit data-quality study.']);
end

dispatchInput=struct;
dispatchInput.timeH=timeH;
dispatchInput.pSourceAvailableMW=sum(hourly.availableBySourceMW,2);
dispatchInput.pSourceAuxMW=sum(hourly.auxiliaryBySourceMW,2);

assert(all(dispatchInput.pSourceAvailableMW<= ...
    cfg.source.installedMW+1e-8), ...
    ['Embedded source engine exceeds cfg.source.installedMW. ', ...
     'Check device nameplates or V5 capacity configuration.']);

detail=struct;
detail.mode=mode;
detail.status=sourceStatus;
detail.sourceId=profile.sourceId;
detail.sourceType=profile.sourceType;
detail.timeH=timeH;
detail.availableBySourceMW=hourly.availableBySourceMW;
detail.auxiliaryBySourceMW=hourly.auxiliaryBySourceMW;
detail.collectionLossBySourceMW=hourly.collectionLossBySourceMW;
detail.qualityBySource=hourly.qualityBySource;
detail.aggregateAvailableMW=dispatchInput.pSourceAvailableMW;
detail.aggregateAuxiliaryMW=dispatchInput.pSourceAuxMW;
detail.resampling=resamplingAudit;
detail.boundary=struct( ...
    'meterPoint',cfg.source.meterPoint, ...
    'collectionLossAlreadyDeducted',true, ...
    'sourceAuxiliaryIsSeparateBusDemand',true, ...
    'powerMeaning','interval-average MW', ...
    'dispatchResponsibility','V5 optimizer, not source engine');
detail.evidence=struct( ...
    'engineOrigin','V5 foundation/modules/4.3_source unique copy', ...
    'formulaEvidence','embedded docs directory', ...
    'calibrationStatus','[假设值，待企业/OEM/场址数据校准]');
detail.raw=raw;
end

function raw=run_device_inputs(cfg,sourceCase)
names={'wind','pv','tidal'};
types={'wind','pv','tidal'};
models={@floating_wind_dispatch_v2,@floating_pv_dispatch_v2, ...
    @tidal_current_dispatch_v2};
sources=struct([]);
device=struct;
for k=1:numel(names)
    name=names{k};
    if ~isfield(sourceCase,name) || isempty(sourceCase.(name))
        continue
    end
    item=sourceCase.(name);
    assert(isstruct(item) && isfield(item,'input') && ...
        isfield(item,'parameters'), ...
        'sourceCase.%s requires input and parameters.',name);
    output=models{k}(item.input,item.parameters);
    device.(name)=output;
    if isfield(item,'sourceId')
        sourceId=char(string(item.sourceId));
    else
        sourceId=upper([name '_V5']);
    end
    available=output.pAvailableAtPOI;
    adapterCfg=struct( ...
        'sourceId',sourceId, ...
        'sourceType',types{k}, ...
        'meterPoint',cfg.source.meterPoint, ...
        'pRequested',available, ...
        'pForecastAvailable',field_or(item,'forecastAvailableW',available));
    if isfield(item,'qualityFlag')
        adapterCfg.qualityFlag=item.qualityFlag;
    end
    source=device_output_to_source_4_3_v3(output,adapterCfg);
    if isempty(sources), sources=source; else, sources(end+1)=source; end %#ok<AGROW>
end
assert(~isempty(sources),'No wind/PV/tidal device input was supplied.');
aggregateCfg=struct( ...
    'parameterSetId',char(string(option(sourceCase,'parameterSetId', ...
        cfg.meta.parameterVersion))), ...
    'units','P=W; Q=var; time=s');
source=source_aggregation_4_3_v3(sources,aggregateCfg);
raw=struct('source',source,'device',device, ...
    'assumptionNotice','[假设值，待企业/OEM/场址数据校准]');
end

function profile=profile_from_aggregate(source)
profile=struct;
profile.timeSeconds=double(source.time(:));
profile.sourceId=cellstr(source.sourceId);
profile.sourceType=cellstr(source.sourceType);
profile.availableBySourceW=double(source.perSource.available);
profile.auxiliaryBySourceW=double(source.perSource.auxLoad);
profile.collectionLossBySourceW= ...
    double(source.perSource.collectionLoss);
profile.qualityBySource=logical(source.perSource.qualityFlag);
end

function profile=scaled_baseline_profile(cfg,source)
profile=profile_from_aggregate(source);
baseInstalledMW=[34 4 2];
targetInstalledMW=[cfg.source.windInstalledMW, ...
    cfg.source.pvInstalledMW,cfg.source.tidalInstalledMW];
assert(numel(profile.sourceType)==3 && ...
    isequal(string(profile.sourceType(:)),["wind";"pv";"tidal"]), ...
    'Unexpected source order in embedded V4 baseline.');
scale=targetInstalledMW./baseInstalledMW;
profile.availableBySourceW=profile.availableBySourceW.*scale;
profile.auxiliaryBySourceW=profile.auxiliaryBySourceW.*scale;
profile.collectionLossBySourceW= ...
    profile.collectionLossBySourceW.*scale;
end

function [hourly,timeH,audit]=resample_profile(profile,cfg,sourceCase)
t=profile.timeSeconds;
assert(numel(t)>=2 && all(isfinite(t)) && all(diff(t)>0), ...
    'Source-engine time must be finite and strictly increasing.');
sourceStep=median(diff(t));
assert(max(abs(diff(t)-sourceStep))<=1e-9*max(1,sourceStep), ...
    'V5 source adapter currently requires a uniform source time step.');
dispatchStepSeconds=cfg.time.dispatchStepH*3600;
ratio=dispatchStepSeconds/sourceStep;
assert(abs(ratio-round(ratio))<=1e-10 && ratio>=1, ...
    'Dispatch step must be an integer multiple of the source time step.');
samplesPerInterval=round(ratio);

available=profile.availableBySourceW;
auxiliary=profile.auxiliaryBySourceW;
loss=profile.collectionLossBySourceW;
quality=profile.qualityBySource;
assert(size(available,1)==numel(t) && ...
    isequal(size(auxiliary),size(available)) && ...
    isequal(size(loss),size(available)) && ...
    isequal(size(quality),size(available)), ...
    'Source profile matrices are not aligned.');

% Treat samples as interval-start values and exclude a final endpoint.
usableRows=floor((numel(t)-1)/samplesPerInterval)*samplesPerInterval;
assert(usableRows>=samplesPerInterval, ...
    'Source horizon is shorter than one dispatch interval.');
available=available(1:usableRows,:);
auxiliary=auxiliary(1:usableRows,:);
loss=loss(1:usableRows,:);
quality=quality(1:usableRows,:);
Nbase=usableRows/samplesPerInterval;
available=block_mean(available,samplesPerInterval)/1e6;
auxiliary=block_mean(auxiliary,samplesPerInterval)/1e6;
loss=block_mean(loss,samplesPerInterval)/1e6;
quality=block_all(quality,samplesPerInterval);

if isfield(sourceCase,'hours') && ~isempty(sourceCase.hours)
    requestedN=round(double(sourceCase.hours)/cfg.time.dispatchStepH);
    assert(requestedN>=1 && abs(requestedN*cfg.time.dispatchStepH- ...
        double(sourceCase.hours))<=1e-10, ...
        'sourceCase.hours must align with the dispatch step.');
else
    requestedN=Nbase;
end
idx=mod((0:requestedN-1)',Nbase)+1;
hourly=struct( ...
    'availableBySourceMW',available(idx,:), ...
    'auxiliaryBySourceMW',auxiliary(idx,:), ...
    'collectionLossBySourceMW',loss(idx,:), ...
    'qualityBySource',quality(idx,:));
startH=double(option(sourceCase,'startTimeH',0));
timeH=startH+(0:requestedN-1)'*cfg.time.dispatchStepH;
audit=struct( ...
    'sourceStepSeconds',sourceStep, ...
    'dispatchStepSeconds',dispatchStepSeconds, ...
    'samplesPerDispatchInterval',samplesPerInterval, ...
    'baseDispatchIntervals',Nbase, ...
    'requestedDispatchIntervals',requestedN, ...
    'profileRepeated',requestedN>Nbase, ...
    'rule','uniform interval-start samples; arithmetic mean; final endpoint excluded');
end

function y=block_mean(x,n)
N=size(x,1)/n;
S=size(x,2);
y=squeeze(mean(reshape(x,n,N,S),1));
if S==1, y=reshape(y,N,1); end
end

function y=block_all(x,n)
N=size(x,1)/n;
S=size(x,2);
y=squeeze(all(reshape(x,n,N,S),1));
if S==1, y=reshape(y,N,1); end
end

function add_engine_paths(engineRoot)
addpath(fullfile(engineRoot,'demos'), ...
    fullfile(engineRoot,'model','wind'), ...
    fullfile(engineRoot,'model','pv'), ...
    fullfile(engineRoot,'model','tidal'), ...
    fullfile(engineRoot,'model','aggregation'), ...
    fullfile(engineRoot,'model','demo_support'));
end

function validate_type_capacities(availableBySourceMW,sourceType,cfg)
types=string(sourceType(:))';
checks={ ...
    "wind",cfg.source.windInstalledMW; ...
    "pv",cfg.source.pvInstalledMW; ...
    "tidal",cfg.source.tidalInstalledMW};
for k=1:size(checks,1)
    type=checks{k,1};
    capacity=checks{k,2};
    columns=types==type;
    if any(columns)
        typeAvailable=sum(availableBySourceMW(:,columns),2);
        assert(all(typeAvailable<=capacity+1e-8), ...
            ['Embedded %s source output exceeds its V5 installed ', ...
             'capacity. Check device nameplates or configuration.'],type);
    end
end
end

function value=field_or(s,name,defaultValue)
if isfield(s,name), value=s.(name); else, value=defaultValue; end
end

function value=option(s,name,defaultValue)
if isfield(s,name), value=s.(name); else, value=defaultValue; end
end
