function provisional=v4_storage_hydrogen_response(cfg,timeH,req,state0,h2WithdrawnKg,options)
%V4_STORAGE_HYDROGEN_RESPONSE Formal 4.5 response through one state core.
%
% The response no longer maintains a second copy of SOC/H2 equations.
% Cross-module requests remain owned by 4.9; 4.5 clips them only against
% its published physical boundary and commits actual state.

if nargin<6 || isempty(options), options=struct; end
cfg=v4_apply_4_5_parameter_overlay(cfg);
if nargin<5 || isempty(h2WithdrawnKg)
    h2WithdrawnKg=zeros(numel(timeH),1);
end
modelDir=fullfile(fileparts(fileparts(mfilename('fullpath'))),'model');
if exist('v4_storage_hydrogen_core_4_5','file')~=2
    addpath(modelDir);
end

if ~isfield(options,'strictWithdrawal'), options.strictWithdrawal=true; end
if ~isfield(options,'bessStandingLossFractionPerH')
    options.bessStandingLossFractionPerH=cfg.bess.standingLossFractionPerH;
end
if ~isfield(options,'gfmReservePowerMW')
    options.gfmReservePowerMW=cfg.bess.gfmReservePowerMW;
end
if ~isfield(options,'gfmReserveEnergyMWh')
    options.gfmReserveEnergyMWh=cfg.bess.gfmReserveEnergyMWh;
end
if ~isfield(options,'electrolyzerMode')
    if cfg.hydrogen.moduleIndependentCommitment
        options.electrolyzerMode='modular';
    else
        options.electrolyzerMode='aggregate';
    end
end
if ~isfield(options,'electrolyzerModuleCount')
    options.electrolyzerModuleCount=cfg.hydrogen.electrolyzerModuleCount;
end
if ~isfield(options,'electrolyzerModuleRatedMW')
    options.electrolyzerModuleRatedMW=cfg.hydrogen.electrolyzerModuleRatedMW;
end
if ~isfield(options,'electrolyzerModuleMinMW')
    options.electrolyzerModuleMinMW=cfg.hydrogen.electrolyzerModuleMinMW;
end
if ~isfield(options,'bessTerminalRule')
    options.bessTerminalRule=cfg.bess.terminalRule;
end
if ~isfield(options,'bessTerminalTarget')
    if strcmpi(options.bessTerminalRule,'cyclic')
        options.bessTerminalTarget=state0.bessEnergyMWh;
    else
        options.bessTerminalTarget=cfg.bess.terminalTargetSOC*cfg.bess.energyMWh;
    end
end
if ~isfield(options,'h2TerminalRule')
    options.h2TerminalRule=cfg.hydrogen.terminalRule;
end
if ~isfield(options,'h2TerminalTarget')
    if strcmpi(options.h2TerminalRule,'cyclic')
        options.h2TerminalTarget=state0.h2InventoryKg;
    else
        options.h2TerminalTarget=cfg.hydrogen.terminalTargetKg;
    end
end
if ~isfield(options,'enforceTerminal'), options.enforceTerminal=true; end

provisional=v4_storage_hydrogen_core_4_5( ...
    cfg,timeH,req,state0,h2WithdrawnKg,options);
end
