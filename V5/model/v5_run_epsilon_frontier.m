function frontier = v5_run_epsilon_frontier( ...
    cfg,in,maxENS,maxNetGHG,minRenewableUtilization)
%V5_RUN_EPSILON_FRONTIER Generate epsilon-constraint operating points.
%
% This function does not normalize or weight dimensioned objectives.
% maxENS, maxNetGHG and minRenewableUtilization are explicit physical
% limits chosen by the analyst.

if nargin<5 || isempty(minRenewableUtilization)
    minRenewableUtilization=0;
end

maxENS=double(maxENS(:));
maxNetGHG=double(maxNetGHG(:));
minRenewableUtilization=double(minRenewableUtilization(:));
assert(~isempty(maxENS) && ~isempty(maxNetGHG) && ...
    ~isempty(minRenewableUtilization), ...
    'All epsilon vectors must be nonempty.');
assert(all(minRenewableUtilization>=0 & ...
    minRenewableUtilization<=1), ...
    'Minimum renewable-utilization epsilon values must be in [0,1].');

rows=numel(maxENS)*numel(maxNetGHG)* ...
    numel(minRenewableUtilization);
records=cell(rows,1);
ensLimit=zeros(rows,1);
ghgLimit=zeros(rows,1);
renewableUtilizationMinimum=zeros(rows,1);
economicNetCostCNY=nan(rows,1);
ensMWh=nan(rows,1);
netGHGKgCO2e=nan(rows,1);
curtailmentMWh=nan(rows,1);
renewableUtilization=nan(rows,1);
exitflag=nan(rows,1);
auditPass=false(rows,1);
status=strings(rows,1);
r=0;
for i=1:numel(maxENS)
    for j=1:numel(maxNetGHG)
        for k=1:numel(minRenewableUtilization)
            r=r+1;
            localCfg=cfg;
            localCfg.objective.method='EPSILON_CONSTRAINT';
            localCfg.objective.primary='economicNetCostCNY';
            localCfg.objective.maxENSMWh=maxENS(i);
            localCfg.objective.maxNetGHGKgCO2e=maxNetGHG(j);
            localCfg.objective.minRenewableUtilization= ...
                minRenewableUtilization(k);
            ensLimit(r)=maxENS(i);
            ghgLimit(r)=maxNetGHG(j);
            renewableUtilizationMinimum(r)= ...
                minRenewableUtilization(k);
            try
                normalized=v5_validate_and_normalize_input(localCfg,in);
                records{r}=v5_solve_dispatch(localCfg,normalized);
                economicNetCostCNY(r)= ...
                    records{r}.kpi.economicNetCostCNY;
                ensMWh(r)=records{r}.kpi.ensMWh;
                netGHGKgCO2e(r)=records{r}.kpi.netGHGKgCO2e;
                curtailmentMWh(r)=records{r}.kpi.eCurtailmentMWh;
                renewableUtilization(r)= ...
                    records{r}.kpi.renewableUtilization;
                exitflag(r)=double(records{r}.meta.exitflag);
                auditPass(r)=logical(records{r}.audit.pass);
                if exitflag(r)>0 && auditPass(r)
                    status(r)="OPTIMAL_WITHIN_SOLVER_TOLERANCE";
                elseif auditPass(r)
                    status(r)="FEASIBLE_NOT_PROVEN";
                else
                    status(r)="INCUMBENT_FAILED_AUDIT";
                end
            catch ME
                records{r}=ME;
                status(r)="INFEASIBLE_OR_ERROR";
            end
        end
    end
end
frontier=struct;
frontier.summary=table(ensLimit,ghgLimit, ...
    renewableUtilizationMinimum,economicNetCostCNY, ...
    ensMWh,netGHGKgCO2e,curtailmentMWh, ...
    renewableUtilization,exitflag,auditPass,status);
frontier.records=records;
frontier.method='EPSILON_CONSTRAINT_GRID';
end
