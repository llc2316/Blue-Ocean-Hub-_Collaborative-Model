function report=v4_validate_evaluation_4_8(packet,cfg,strictMode)
%V4_VALIDATE_EVALUATION_4_8 Validate 4.8 objective/KPI output.
if nargin<3, strictMode=true; end
errors={};
if ~strcmp(packet.meta.moduleId,'4.8'), errors{end+1}='moduleId must be 4.8.'; end %#ok<AGROW>
if ~strcmp(packet.meta.phase,'EVALUATION'), errors{end+1}='4.8 packet phase must be EVALUATION.'; end %#ok<AGROW>
for f={'economicNetCostCNY','lifecycleEmissionKgCO2e','EENSMWh'}
    if ~isfield(packet.product,f{1}) || ~isscalar(packet.product.(f{1})) || ...
            ~isfinite(packet.product.(f{1}))
        errors{end+1}=['Missing or invalid packet.product.' f{1}]; %#ok<AGROW>
    end
end
nonnegative={'lifecycleEmissionKgCO2e','EENSMWh'};
for k=1:numel(nonnegative)
    if isfield(packet.product,nonnegative{k}) && packet.product.(nonnegative{k})<0
        errors{end+1}=[nonnegative{k} ' must be nonnegative.']; %#ok<AGROW>
    end
end
if ~isfield(packet.state,'objectiveVectorRaw') || numel(packet.state.objectiveVectorRaw)~=3
    errors{end+1}='Raw objective vector must contain three objectives.'; %#ok<AGROW>
end
componentPairs={ ...
    'costComponentsCNY','totalCostCNY'; ...
    'revenueComponentsCNY','totalRevenueCNY'; ...
    'emissionComponentsKgCO2e','lifecycleEmissionKgCO2e'};
for k=1:size(componentPairs,1)
    componentField=componentPairs{k,1};
    totalField=componentPairs{k,2};
    if ~isfield(packet.service,componentField) || ...
            any(~isfinite(packet.service.(componentField))) || ...
            any(packet.service.(componentField)<-1e-9)
        errors{end+1}=['Missing or invalid packet.service.' componentField]; %#ok<AGROW>
        continue
    end
    if strcmp(totalField,'lifecycleEmissionKgCO2e')
        expected=packet.product.lifecycleEmissionKgCO2e;
    elseif ~isfield(packet.service,totalField)
        errors{end+1}=['Missing packet.service.' totalField]; %#ok<AGROW>
        continue
    else
        expected=packet.service.(totalField);
    end
    scale=max(1,abs(expected));
    if abs(sum(packet.service.(componentField))-expected)>1e-9*scale
        errors{end+1}=[componentField ' does not sum to ' totalField '.']; %#ok<AGROW>
    end
end
if isfield(packet.service,'totalCostCNY') && ...
        isfield(packet.service,'totalRevenueCNY') && ...
        isfield(packet.product,'economicNetCostCNY')
    expected=packet.service.totalCostCNY-packet.service.totalRevenueCNY;
    if abs(expected-packet.product.economicNetCostCNY)>1e-9*max(1,abs(expected))
        errors{end+1}='Economic net cost does not equal total cost minus total revenue.'; %#ok<AGROW>
    end
end
if ~isfield(packet.service,'lifecycle') || ~isstruct(packet.service.lifecycle)
    errors{end+1}='Missing packet.service.lifecycle.'; %#ok<AGROW>
else
    lifecycleFields={'grossCapexCNY','constructionFinancingCNY', ...
        'financedCapexCNY','annualDepreciationCNY', ...
        'annualFinancingCostCNY','annualFixedOMCNY', ...
        'replacementPresentValueCNY','annualReplacementReserveCNY', ...
        'lifecycleCostPresentValueCNY','lifecycleNPVAfterPenaltyCNY', ...
        'lifecycleNPVBeforePenaltyCNY'};
    for k=1:numel(lifecycleFields)
        f=lifecycleFields{k};
        if ~isfield(packet.service.lifecycle,f) || ...
                ~isscalar(packet.service.lifecycle.(f)) || ...
                ~isfinite(packet.service.lifecycle.(f))
            errors{end+1}=['Missing or invalid lifecycle field ' f '.']; %#ok<AGROW>
        end
    end
end
if ~isfield(packet.service,'lifecycleAssetTable') || ...
        ~istable(packet.service.lifecycleAssetTable) || ...
        isempty(packet.service.lifecycleAssetTable)
    errors{end+1}='Missing lifecycle asset ledger table.'; %#ok<AGROW>
end
if ~strcmp(packet.meta.schemaId,cfg.meta.schemaId) || ...
        ~strcmp(packet.meta.schemaVersion,cfg.meta.schemaVersion)
    errors{end+1}='4.8 schema identity mismatch.'; %#ok<AGROW>
end
report=struct('moduleId','4.8','ok',isempty(errors),'errors',{errors(:)});
if strictMode && ~report.ok, error('BLUEHUB:Evaluation48Invalid','%s',strjoin(errors,newline)); end
end
