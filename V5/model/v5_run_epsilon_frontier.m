function frontier = v5_run_epsilon_frontier(cfg,in,maxENS,maxNetGHG)
%V5_RUN_EPSILON_FRONTIER Generate epsilon-constraint operating points.
%
% This function does not normalize or weight dimensioned objectives.
% maxENS and maxNetGHG are explicit physical limits chosen by the analyst.

maxENS=double(maxENS(:));
maxNetGHG=double(maxNetGHG(:));
assert(~isempty(maxENS) && ~isempty(maxNetGHG), ...
    'Both epsilon vectors must be nonempty.');

rows=numel(maxENS)*numel(maxNetGHG);
records=cell(rows,1);
ensLimit=zeros(rows,1);
ghgLimit=zeros(rows,1);
economicNetCostCNY=nan(rows,1);
ensMWh=nan(rows,1);
netGHGKgCO2e=nan(rows,1);
curtailmentMWh=nan(rows,1);
status=strings(rows,1);
r=0;
for i=1:numel(maxENS)
    for j=1:numel(maxNetGHG)
        r=r+1;
        localCfg=cfg;
        localCfg.objective.method='EPSILON_CONSTRAINT';
        localCfg.objective.primary='economicNetCostCNY';
        localCfg.objective.maxENSMWh=maxENS(i);
        localCfg.objective.maxNetGHGKgCO2e=maxNetGHG(j);
        ensLimit(r)=maxENS(i);
        ghgLimit(r)=maxNetGHG(j);
        try
            normalized=v5_validate_and_normalize_input(localCfg,in);
            records{r}=v5_solve_dispatch(localCfg,normalized);
            economicNetCostCNY(r)=records{r}.kpi.economicNetCostCNY;
            ensMWh(r)=records{r}.kpi.ensMWh;
            netGHGKgCO2e(r)=records{r}.kpi.netGHGKgCO2e;
            curtailmentMWh(r)=records{r}.kpi.eCurtailmentMWh;
            status(r)="SOLVED";
        catch ME
            records{r}=ME;
            status(r)="INFEASIBLE_OR_ERROR";
        end
    end
end
frontier=struct;
frontier.summary=table(ensLimit,ghgLimit,economicNetCostCNY, ...
    ensMWh,netGHGKgCO2e,curtailmentMWh,status);
frontier.records=records;
frontier.method='AUGMENTED_EPSILON_CONSTRAINT_READY_GRID';
end
