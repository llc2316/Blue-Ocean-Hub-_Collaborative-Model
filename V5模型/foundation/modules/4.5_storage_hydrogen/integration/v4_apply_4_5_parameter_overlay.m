function cfg=v4_apply_4_5_parameter_overlay(cfg)
%V4_APPLY_4_5_PARAMETER_OVERLAY Schema-compatible 4.5 parameter extension.
%
% The frozen BLUE_HUB_CH4_SCHEMA_V2 port fields are not changed. This
% overlay adds module-internal implementation parameters and updates the
% evidence boundary for the existing SEC field. Unverified values remain
% explicitly marked in 4.5 documentation.

cfg.bess=fill(cfg.bess,'terminalTargetSOC',cfg.bess.socInitial);
cfg.bess=fill(cfg.bess,'standingLossFractionPerH',0);
cfg.bess=fill(cfg.bess,'gfmReservePowerMW',5);
cfg.bess=fill(cfg.bess,'gfmReserveEnergyMWh',1);
cfg.bess=fill(cfg.bess,'blackStartSOCMin',0.30);
cfg.bess=fill(cfg.bess,'dynamicModel', ...
    'WECC_REGFM_B1_REDUCED_ORDER_PROXY');

cfg.hydrogen=fill(cfg.hydrogen,'electrolyzerModuleCount',5);
cfg.hydrogen=fill(cfg.hydrogen,'electrolyzerModuleRatedMW',20);
cfg.hydrogen=fill(cfg.hydrogen,'electrolyzerModuleMinMW',4);
cfg.hydrogen=fill(cfg.hydrogen,'moduleIndependentCommitment',true);
cfg.hydrogen=fill(cfg.hydrogen,'terminalTargetKg', ...
    cfg.hydrogen.storageInitialKg);
cfg.hydrogen.secBoundary= ...
    'AC_FACILITY_INPUT_TO_30_BARG_H2; EXCLUDES_SEAWATER_PRETREATMENT_HIGHER_PRESSURE_COMPRESSION_LIQUEFACTION_SHIP_LOADING';

assert(cfg.bess.terminalTargetSOC>=cfg.bess.socMin && ...
    cfg.bess.terminalTargetSOC<=cfg.bess.socMax);
assert(cfg.bess.standingLossFractionPerH>=0 && ...
    cfg.bess.standingLossFractionPerH<1);
assert(cfg.bess.gfmReservePowerMW>=0 && ...
    cfg.bess.gfmReservePowerMW<=cfg.bess.dischargeMaxMW);
assert(cfg.bess.gfmReserveEnergyMWh>=0 && ...
    cfg.bess.gfmReserveEnergyMWh<= ...
    (cfg.bess.socMax-cfg.bess.socMin)*cfg.bess.energyMWh);
assert(cfg.hydrogen.electrolyzerModuleCount>=1 && ...
    abs(cfg.hydrogen.electrolyzerModuleCount* ...
    cfg.hydrogen.electrolyzerModuleRatedMW- ...
    cfg.hydrogen.electrolyzerRatedMW)<=1e-9);
assert(cfg.hydrogen.electrolyzerModuleMinMW>0 && ...
    cfg.hydrogen.electrolyzerModuleMinMW<= ...
    cfg.hydrogen.electrolyzerModuleRatedMW);
assert(cfg.hydrogen.terminalTargetKg>=0 && ...
    cfg.hydrogen.terminalTargetKg<=cfg.hydrogen.storageMaxKg);
end

function s=fill(s,name,value)
if ~isfield(s,name) || isempty(s.(name)), s.(name)=value; end
end
