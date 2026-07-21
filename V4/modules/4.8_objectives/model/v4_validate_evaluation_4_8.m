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
if ~strcmp(packet.meta.schemaId,cfg.meta.schemaId) || ...
        ~strcmp(packet.meta.schemaVersion,cfg.meta.schemaVersion)
    errors{end+1}='4.8 schema identity mismatch.'; %#ok<AGROW>
end
report=struct('moduleId','4.8','ok',isempty(errors),'errors',{errors(:)});
if strictMode && ~report.ok, error('BLUEHUB:Evaluation48Invalid','%s',strjoin(errors,newline)); end
end
