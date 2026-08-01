function sample = c5_select_typical_normal_48h(scenario)
%C5_SELECT_TYPICAL_NORMAL_48H Select a normal annual 48 h study sample.
%
% Selection may use the full annual record because it defines the offline
% evaluation sample. Dispatch inside the selected sample remains causal
% and receives no later-hour data.

if nargin<1 || isempty(scenario)
    scenario=c5_build_annual_2025_multisource_scenario();
end
[sourceInput,sourceDetail]= ...
    v5_source_adapter(scenario.config,scenario.input.sourceCase);
base=rmfield(scenario.input,'sourceCase');
base=merge_input(base,sourceInput);
N=numel(base.timeH);
assert(N==8760,'Typical-window selector expects an 8760 h annual case.');

starts=(1:24:(N-47))';
valid=false(numel(starts),1);
features=nan(numel(starts),6);
eventCode=scenario.hourly.eventCode;
bySource=sourceDetail.availableBySourceMW;
for k=1:numel(starts)
    idx=starts(k):(starts(k)+47);
    valid(k)=all(eventCode(idx)=="NORMAL");
    if ~valid(k), continue; end
    features(k,:)=[ ...
        mean(sourceInput.pSourceAvailableMW(idx)), ...
        std(sourceInput.pSourceAvailableMW(idx)), ...
        mean(bySource(idx,1)),mean(bySource(idx,2)), ...
        mean(bySource(idx,3)), ...
        mean(base.pComputeBaseDemandMW(idx)+ ...
            base.pComputeFlexibleMaxMW(idx))];
end
assert(any(valid),'Annual scenario has no normal 48 h candidate.');
validFeatures=features(valid,:);
center=median(validFeatures,1);
scale=median(abs(validFeatures-center),1);
scale(scale<1e-9)=1;
score=inf(numel(starts),1);
score(valid)=sum(abs((validFeatures-center)./scale),2);
[~,winner]=min(score);
idx=starts(winner):(starts(winner)+47);

sample=struct;
sample.meta=struct( ...
    'scenarioId','ANNUAL_2025_TYPICAL_NORMAL_48H_V2', ...
    'parentScenarioId',scenario.meta.scenarioId, ...
    'startIndex',idx(1),'endIndex',idx(end), ...
    'startUTC',char(string(scenario.hourly.timeUTC(idx(1)))), ...
    'endUTC',char(string(scenario.hourly.timeUTC(idx(end)))), ...
    'selectionRule', ...
        'MINIMUM_MAD_DISTANCE_TO_NORMAL_48H_MEDIAN_FEATURE_VECTOR', ...
    'dispatchForesight','NONE; OFFLINE_SAMPLE_SELECTION_ONLY', ...
    'parameterStatus','[假设值，待企业调研校准]');
sample.config=scenario.config;
sample.input=slice_input(base,idx,base.initial);
sample.hourly=scenario.hourly(idx,:);
sample.sourceDetail=sourceDetail;
sample.sourceDetail.timeH=sourceDetail.timeH(idx);
sample.sourceDetail.availableBySourceMW= ...
    sourceDetail.availableBySourceMW(idx,:);
sample.sourceDetail.auxiliaryBySourceMW= ...
    sourceDetail.auxiliaryBySourceMW(idx,:);
sample.sourceDetail.collectionLossBySourceMW= ...
    sourceDetail.collectionLossBySourceMW(idx,:);
sample.sourceDetail.qualityBySource=sourceDetail.qualityBySource(idx,:);
sample.sourceDetail.aggregateAvailableMW= ...
    sourceDetail.aggregateAvailableMW(idx);
sample.sourceDetail.aggregateAuxiliaryMW= ...
    sourceDetail.aggregateAuxiliaryMW(idx);
sample.selectionAudit=table(starts,valid,score);
end

function in=slice_input(base,idx,state)
in=struct;
names=fieldnames(base);
N=numel(base.timeH);
for k=1:numel(names)
    name=names{k};
    if any(strcmp(name,{'availability','initial'})), continue; end
    value=base.(name);
    if (isnumeric(value)||islogical(value)) && isvector(value) && ...
            numel(value)==N
        value=value(idx);
    end
    in.(name)=value;
end
in.timeH=(0:numel(idx)-1)';
in.availability=struct;
names=fieldnames(base.availability);
for k=1:numel(names)
    value=base.availability.(names{k});
    if ~isscalar(value), value=value(idx); end
    in.availability.(names{k})=value;
end
in.initial=state;
end

function out=merge_input(out,addition)
names=fieldnames(addition);
for k=1:numel(names), out.(names{k})=addition.(names{k}); end
end
