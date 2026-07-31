function result = run_v5_model(in,cfgOrMode)
%RUN_V5_MODEL Public entry point for the C4/V5 dispatch optimization model.
%
% result = run_v5_model(in)
% result = run_v5_model(in,'mechanism_test')
% result = run_v5_model(in,cfgOverride)

root=fileparts(mfilename('fullpath'));
addpath(fullfile(root,'config'));
addpath(fullfile(root,'model'));
addpath(fullfile(root,'source'));
foundation=v5_foundation_registry(root);

if nargin<2 || isempty(cfgOrMode)
    cfg=v5_default_config('mechanism_test');
elseif ischar(cfgOrMode) || isstring(cfgOrMode)
    cfg=v5_default_config(char(cfgOrMode));
elseif isstruct(cfgOrMode)
    if isfield(cfgOrMode,'meta') && isfield(cfgOrMode.meta,'caseMode')
        mode=cfgOrMode.meta.caseMode;
    else
        mode='mechanism_test';
    end
    cfg=merge_struct(v5_default_config(mode),cfgOrMode);
else
    error('cfgOrMode must be a case-mode string or configuration struct.');
end

sourceDetail=[];
if ~isfield(in,'pSourceAvailableMW')
    assert(isfield(in,'sourceCase'), ...
        ['Input requires pSourceAvailableMW or sourceCase for the ', ...
         'embedded V4 4.3 supply engine.']);
    [sourceInput,sourceDetail]=v5_source_adapter(cfg,in.sourceCase);
    in=merge_source_input(in,sourceInput);
end
in=v5_validate_and_normalize_input(cfg,in);
result=v5_solve_dispatch(cfg,in);
result.config=cfg;
result.input=in;
result.source=sourceDetail;
result.investmentGate=v5_evaluate_investment_gate(cfg,[]);
result.foundation=foundation;
result.foundationBusCrosscheck= ...
    v5_crosscheck_with_foundation_bus(cfg,in,result);
end

function out=merge_struct(base,override)
out=base;
names=fieldnames(override);
for k=1:numel(names)
    name=names{k};
    if isfield(base,name) && isstruct(base.(name)) && ...
            isstruct(override.(name))
        out.(name)=merge_struct(base.(name),override.(name));
    else
        out.(name)=override.(name);
    end
end
end

function out=merge_source_input(out,sourceInput)
names=fieldnames(sourceInput);
for k=1:numel(names)
    name=names{k};
    if isfield(out,name)
        existing=double(out.(name));
        generated=double(sourceInput.(name));
        assert(isequaln(existing(:),generated(:)), ...
            'Input field %s conflicts with the embedded source result.',name);
    else
        out.(name)=sourceInput.(name);
    end
end
end
