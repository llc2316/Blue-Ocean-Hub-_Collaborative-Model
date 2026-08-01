function out = c5_slice_input_horizon(base,idx)
%C5_SLICE_INPUT_HORIZON Public utility for C5 smoke and study subsets.
idx=idx(:);
N=numel(base.timeH);
assert(all(idx>=1 & idx<=N & idx==round(idx)),'Invalid horizon indices.');
out=struct;
names=fieldnames(base);
for k=1:numel(names)
    name=names{k};
    if strcmp(name,'availability')
        continue
    end
    value=base.(name);
    if (isnumeric(value)||islogical(value)) && isvector(value) && ...
            numel(value)==N
        value=value(idx);
    end
    out.(name)=value;
end
out.timeH=(0:numel(idx)-1)';
out.availability=struct;
names=fieldnames(base.availability);
for k=1:numel(names)
    value=base.availability.(names{k});
    if ~isscalar(value), value=value(idx); end
    out.availability.(names{k})=value;
end
end
