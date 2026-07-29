function result=v4_levelized_source_cost_4_8(costCase)
%V4_LEVELIZED_SOURCE_COST_4_8 Same-boundary source LCOE comparison.
% Formula source: NREL Annual Technology Baseline, Equations & Variables:
% LCOE=(FCR*CAPEX+FOM)/(CF*8760)+VOM+FUEL-PTC.
% Here CF*8760 is replaced by audited annual energy per installed kW.
required={'sourceType','installedCapacityMW','annualEnergyMWh', ...
    'capexCNYPerKW','fixedOMCNYPerKWYear','variableOMCNYPerMWh', ...
    'fixedChargeRate','allocatedSharedAnnualCostCNY','evidenceStatus'};
assert(istable(costCase),'costCase must be a table.');
assert(all(ismember(required,costCase.Properties.VariableNames)), ...
    'costCase is missing required columns.');
n=height(costCase);
numericNames=required(2:8);
for k=1:numel(numericNames)
    x=double(costCase.(numericNames{k}));
    assert(numel(x)==n && all(isfinite(x)) && all(x>=0), ...
        '%s must be finite and nonnegative.',numericNames{k});
end
assert(all(costCase.installedCapacityMW>0) && all(costCase.annualEnergyMWh>0), ...
    'Capacity and annual energy must be positive.');
assert(all(costCase.fixedChargeRate<1), ...
    'fixedChargeRate must be a fraction below 1/year.');
assert(all(strlength(string(costCase.evidenceStatus))>0), ...
    'Every row must carry evidenceStatus.');

capacityKW=double(costCase.installedCapacityMW)*1000;
annualCapitalCNY=double(costCase.fixedChargeRate).* ...
    double(costCase.capexCNYPerKW).*capacityKW;
annualFixedOMCNY=double(costCase.fixedOMCNYPerKWYear).*capacityKW;
annualVariableOMCNY=double(costCase.variableOMCNYPerMWh).* ...
    double(costCase.annualEnergyMWh);
annualCostCNY=annualCapitalCNY+annualFixedOMCNY+annualVariableOMCNY+ ...
    double(costCase.allocatedSharedAnnualCostCNY);
lcoeCNYPerMWh=annualCostCNY./double(costCase.annualEnergyMWh);

result=costCase(:,{'sourceType','installedCapacityMW','annualEnergyMWh', ...
    'evidenceStatus'});
result.annualCapitalCNY=annualCapitalCNY;
result.annualFixedOMCNY=annualFixedOMCNY;
result.annualVariableOMCNY=annualVariableOMCNY;
result.annualCostCNY=annualCostCNY;
result.lcoeCNYPerMWh=lcoeCNYPerMWh;
result.Properties.UserData=struct( ...
    'formulaSourceType','美国国家实验室官方技术基准', ...
    'formulaURL','https://atb.nrel.gov/electricity/2024/2023/equations_%26_variables', ...
    'comparisonRule','Only compare rows with the same price year, currency, system boundary, shared-cost allocation and annual resource period.');
end
