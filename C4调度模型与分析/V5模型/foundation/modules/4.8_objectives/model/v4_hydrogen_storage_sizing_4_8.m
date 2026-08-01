function design=v4_hydrogen_storage_sizing_4_8(cfg,peakInventoryKg)
%V4_HYDROGEN_STORAGE_SIZING_4_8 Process buffer plus cross-time inventory.
% Even a flow-through hydrogen case needs a small process buffer between
% production and export. The buffer-hours setting is an unverified project
% assumption; rated production follows the documented fixed-SEC relation.
if nargin<2 || isempty(peakInventoryKg), peakInventoryKg=0; end
enabled=true;
if isfield(cfg,'assetEnabled') && isfield(cfg.assetEnabled,'hydrogenStorage')
    enabled=logical(cfg.assetEnabled.hydrogenStorage);
end
bufferHours=1; % [假设值，待企业调研校准]
if isfield(cfg.hydrogen,'minimumProcessBufferHours')
    bufferHours=max(0,double(cfg.hydrogen.minimumProcessBufferHours));
end
electrolyzerMW=double(cfg.hydrogen.electrolyzerRatedMW);
if isfield(cfg,'capacity') && isfield(cfg.capacity,'installed') && ...
        isfield(cfg.capacity.installed,'electrolyzerMW')
    electrolyzerMW=double(cfg.capacity.installed.electrolyzerMW);
end
ratedProductionKgPerH=1000*electrolyzerMW/double(cfg.hydrogen.secKWhPerKg);
processBufferKg=ratedProductionKgPerH*bufferHours;
if enabled
    installedKg=max(max(0,double(peakInventoryKg)),processBufferKg);
else
    processBufferKg=0;
    installedKg=0;
end
physicalUpperKg=double(cfg.hydrogen.storageMaxKg);
assert(installedKg<=physicalUpperKg+1e-9, ...
    'Hydrogen storage design %.3f kg exceeds physical interface %.3f kg.', ...
    installedKg,physicalUpperKg);
design=struct( ...
    'enabled',enabled, ...
    'peakCrossTimeInventoryKg',max(0,double(peakInventoryKg)), ...
    'minimumProcessBufferHours',bufferHours, ...
    'ratedProductionKgPerH',ratedProductionKgPerH, ...
    'minimumProcessBufferKg',processBufferKg, ...
    'installedKg',installedKg, ...
    'sizingRule','MAX_PROCESS_BUFFER_AND_COMMITTED_INVENTORY', ...
    'bufferParameterStatus','[假设值，待企业调研校准]');
end
