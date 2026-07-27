function result=compare_source_portfolios_4_3_v3(time,pPerUnit,quality,capacityShare,windows,lowFraction)
%COMPARE_SOURCE_PORTFOLIOS_4_3_V3 Equal-capacity wind/wind-PV/wind-PV-tidal comparison.
% pPerUnit columns are wind, PV and tidal capacity-factor trajectories.
assert(size(pPerUnit,2)==3,'pPerUnit must contain wind, PV and tidal columns.');
assert(all(pPerUnit>=0 & pPerUnit<=1,'all'),'Per-unit power must lie in [0,1].');
capacityShare=double(capacityShare(:))';
assert(numel(capacityShare)==3 && all(capacityShare>=0) && abs(sum(capacityShare)-1)<1e-10, ...
    'capacityShare must contain three nonnegative shares summing to one.');
portfolios={ [1 0 0], ...
    [capacityShare(1)/(capacityShare(1)+capacityShare(2)),capacityShare(2)/(capacityShare(1)+capacityShare(2)),0], ...
    capacityShare};
names=["仅风电","风电+光伏","风电+光伏+潮流能"];
result=struct('name',cell(1,3),'share',cell(1,3),'power',cell(1,3),'metrics',cell(1,3));
for j=1:3
    share=portfolios{j}; active=share>0;
    power=pPerUnit(:,active).*share(active);
    result(j).name=names(j); result(j).share=share;
    result(j).power=sum(power,2);
    result(j).metrics=source_complementarity_metrics_v3(time,power,quality(:,active), ...
        share(active),windows,lowFraction);
end
end
