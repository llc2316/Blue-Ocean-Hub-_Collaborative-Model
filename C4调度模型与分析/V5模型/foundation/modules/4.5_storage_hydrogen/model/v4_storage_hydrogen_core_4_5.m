function result=v4_storage_hydrogen_core_4_5(cfg,timeH,request,state0,h2WithdrawalRequestKg,options)
%V4_STORAGE_HYDROGEN_CORE_4_5 Physical 4.5 energy/mass state transition.
%
% This function owns only BESS, electrolyzer and hydrogen-inventory
% responses. Cross-module allocation remains a 4.9 responsibility.
%
% State equations follow the public PyPSA storage convention:
%   E_t = eta_stand^dt E_{t-1} + eta_ch P_ch dt - P_dis dt/eta_dis
%   H_t = eta_H^dt H_{t-1} + q_prod - q_withdrawn
% Reference: https://docs.pypsa.org/latest/user-guide/optimization/storage/
%
% The fixed-SEC relation is q_prod = 1000*P_el*dt/SEC. The configured
% 56.77 kWh/kg case is the Nel MC-Series full-load system figure to a
% 30-barg product boundary. Applying it at part load is an
% [assumption, pending OEM curve calibration].

if nargin<6 || isempty(options), options=struct; end
timeH=double(timeH(:)); N=numel(timeH);
assert(N>=1 && all(isfinite(timeH)) && ...
    (N==1 || all(diff(timeH)>0)),'timeH must be finite and increasing.');
dtH=step_series(cfg,timeH,options);
tol=option_value(options,'tolerance',1e-9);

required={'bessChargeMW','bessDischargeMW','electrolyzerMW'};
for k=1:numel(required)
    assert(isfield(request,required{k}), ...
        'Missing 4.5 request field %s.',required{k});
    request.(required{k})=numeric_series(request.(required{k}),N,required{k});
end
if isfield(request,'electrolyzerAvailable')
    electrolyzerAvailable=logical(request.electrolyzerAvailable(:));
    assert(numel(electrolyzerAvailable)==N, ...
        'electrolyzerAvailable must have N rows.');
else
    electrolyzerAvailable=true(N,1);
end
if isfield(request,'secKWhPerKg')
    secKWhPerKg=numeric_series(request.secKWhPerKg,N,'secKWhPerKg');
    assert(all(secKWhPerKg>0),'secKWhPerKg must be positive.');
else
    secKWhPerKg=repmat(double(cfg.hydrogen.secKWhPerKg),N,1);
end

if nargin<5 || isempty(h2WithdrawalRequestKg)
    h2WithdrawalRequestKg=zeros(N,1);
else
    h2WithdrawalRequestKg=numeric_series( ...
        h2WithdrawalRequestKg,N,'h2WithdrawalRequestKg');
end
assert(all(h2WithdrawalRequestKg>=0), ...
    'Hydrogen withdrawal request must be nonnegative.');

assert(isfield(state0,'bessEnergyMWh') && isfield(state0,'h2InventoryKg'), ...
    'state0 must contain bessEnergyMWh and h2InventoryKg.');
ePrev=double(state0.bessEnergyMWh);
hPrev=double(state0.h2InventoryKg);
assert(isscalar(ePrev) && isfinite(ePrev) && ...
    ePrev>=cfg.bess.socMin*cfg.bess.energyMWh-tol && ...
    ePrev<=cfg.bess.socMax*cfg.bess.energyMWh+tol, ...
    'Initial BESS energy is outside the configured SOC range.');
assert(isscalar(hPrev) && isfinite(hPrev) && hPrev>=-tol && ...
    hPrev<=cfg.hydrogen.storageMaxKg+tol, ...
    'Initial hydrogen inventory is outside the storage range.');
eInitial=ePrev; hInitial=hPrev;

if isfield(state0,'electrolyzerOn')
    elWasOn=logical(state0.electrolyzerOn);
else
    elWasOn=false;
end
if isfield(state0,'electrolyzerPowerMW')
    elPrev=double(state0.electrolyzerPowerMW);
else
    elPrev=0;
end
if isfield(state0,'electrolyzerFLEH')
    flehPrev=double(state0.electrolyzerFLEH);
else
    flehPrev=0;
end

strictWithdrawal=logical(option_value(options,'strictWithdrawal',true));
enforceRamp=logical(option_value(options,'enforceElectrolyzerRamp',false));
bessStandingLoss=option_value(options,'bessStandingLossFractionPerH', ...
    cfg_value(cfg.bess,'standingLossFractionPerH',0));
h2Loss=option_value(options,'h2StorageLossFractionPerH', ...
    cfg.hydrogen.storageLossFractionPerH);
reservePowerMW=option_value(options,'gfmReservePowerMW', ...
    cfg_value(cfg.bess,'gfmReservePowerMW',0));
reserveEnergyMWh=option_value(options,'gfmReserveEnergyMWh', ...
    cfg_value(cfg.bess,'gfmReserveEnergyMWh',0));
assert(isfinite(bessStandingLoss) && bessStandingLoss>=0 && bessStandingLoss<1);
assert(isfinite(h2Loss) && h2Loss>=0 && h2Loss<1);
assert(isfinite(reservePowerMW) && reservePowerMW>=0 && ...
    reservePowerMW<=cfg.bess.dischargeMaxMW);
assert(isfinite(reserveEnergyMWh) && reserveEnergyMWh>=0);
ePhysicalMin=cfg.bess.socMin*cfg.bess.energyMWh+reserveEnergyMWh;
assert(ePrev>=ePhysicalMin-tol, ...
    'Initial BESS energy is below the SOC plus GFM energy-reserve boundary.');

electrolyzerMode=string(option_value(options,'electrolyzerMode','aggregate'));
isModular=strcmpi(electrolyzerMode,'modular');
if isModular
    moduleRatedMW=option_value(options,'electrolyzerModuleRatedMW',20);
    moduleMinMW=option_value(options,'electrolyzerModuleMinMW',4);
    moduleCount=option_value(options,'electrolyzerModuleCount', ...
        round(cfg.hydrogen.electrolyzerRatedMW/moduleRatedMW));
    assert(moduleRatedMW>0 && moduleMinMW>0 && ...
        moduleMinMW<=moduleRatedMW && moduleCount>=1);
else
    moduleRatedMW=cfg.hydrogen.electrolyzerRatedMW;
    moduleMinMW=cfg.hydrogen.electrolyzerMinMW;
    moduleCount=1;
end

E=zeros(N,1); soc=zeros(N,1); pch=zeros(N,1); pdis=zeros(N,1);
pel=zeros(N,1); prod=zeros(N,1); waterM3=zeros(N,1);
h2Retained=zeros(N,1); h2Available=zeros(N,1); h2End=zeros(N,1);
h2Withdrawn=zeros(N,1); h2Shortfall=zeros(N,1);
h2StorageLoss=zeros(N,1); h2DirectFlowThrough=zeros(N,1);
startEvent=false(N,1); fleh=zeros(N,1); onlineModules=zeros(N,1);
bessResidual=zeros(N,1); h2Residual=zeros(N,1);
bessConstraint=repmat("NONE",N,1); elConstraint=repmat("NONE",N,1);

for t=1:N
    dt=dtH(t);
    chRequest=request.bessChargeMW(t);
    disRequest=request.bessDischargeMW(t);
    assert(~(chRequest>tol && disRequest>tol), ...
        'Simultaneous BESS charge/discharge request is forbidden at t=%d.',t);

    eBefore=ePrev;
    eRetained=ePrev*(1-bessStandingLoss)^dt;
    eMin=cfg.bess.socMin*cfg.bess.energyMWh+reserveEnergyMWh;
    eMax=cfg.bess.socMax*cfg.bess.energyMWh;
    assert(eMin<=eMax+tol,'GFM reserve energy exceeds the usable SOC range.');
    room=max(0,eMax-eRetained);
    available=max(0,eRetained-eMin);
    chargeLimit=min(cfg.bess.chargeMaxMW,room/(cfg.bess.etaCharge*dt));
    dischargeLimit=min(max(0,cfg.bess.dischargeMaxMW-reservePowerMW), ...
        available*cfg.bess.etaDischarge/dt);
    ch=min(chRequest,chargeLimit);
    dis=min(disRequest,dischargeLimit);
    if ch<chRequest-tol, bessConstraint(t)="CHARGE_LIMIT"; end
    if dis<disRequest-tol, bessConstraint(t)="DISCHARGE_OR_GFM_RESERVE_LIMIT"; end
    ePrev=eRetained+cfg.bess.etaCharge*ch*dt ...
        -dis*dt/cfg.bess.etaDischarge;
    if ePrev<eMin-tol || ePrev>eMax+tol
        error('BLUEHUB:BESSReserveBoundary45', ...
            'BESS end state violates the SOC/GFM reserve boundary at t=%d.',t);
    end
    bessResidual(t)=ePrev-(eRetained+cfg.bess.etaCharge*ch*dt ...
        -dis*dt/cfg.bess.etaDischarge);

    hBefore=hPrev;
    hRet=hPrev*(1-h2Loss)^dt;
    hLossThis=hPrev-hRet;
    el=max(0,min(request.electrolyzerMW(t), ...
        cfg.hydrogen.electrolyzerRatedMW));
    if ~electrolyzerAvailable(t)
        el=0; elConstraint(t)="UNAVAILABLE";
    elseif enforceRamp
        rampMW=cfg.hydrogen.electrolyzerRampFractionRatedPerS* ...
            cfg.hydrogen.electrolyzerRatedMW*dt*3600;
        el=max(elPrev-rampMW,min(el,elPrev+rampMW));
    end

    % Withdrawal in the same interval creates valid flow-through room.
    % Therefore the tank limit is applied to end-of-interval inventory,
    % avoiding the former zero-withdrawal first-pass truncation.
    productionRoomKg=max(0,cfg.hydrogen.storageMaxKg-hRet ...
        +h2WithdrawalRequestKg(t));
    tankPowerCap=productionRoomKg*secKWhPerKg(t)/(1000*dt);
    if el>tankPowerCap+tol, elConstraint(t)="TANK_END_STATE_LIMIT"; end
    el=min(el,tankPowerCap);

    if isModular
        if el>tol && el<moduleMinMW-tol
            el=0; elConstraint(t)="BELOW_SINGLE_MODULE_MINIMUM";
        end
        if el>tol
            nOnline=min(moduleCount,max(1,ceil((el-tol)/moduleRatedMW)));
            if el<nOnline*moduleMinMW-tol
                el=0; nOnline=0;
                elConstraint(t)="MODULE_MINIMUM_INFEASIBLE";
            end
        else
            nOnline=0;
        end
    else
        if el>tol && el<cfg.hydrogen.electrolyzerMinMW-tol
            el=0; elConstraint(t)="BELOW_AGGREGATE_MINIMUM";
        end
        nOnline=double(el>tol);
    end

    produced=1000*el*dt/secKWhPerKg(t);
    availableH2=hRet+produced;
    if strictWithdrawal
        assert(h2WithdrawalRequestKg(t)<=availableH2+tol, ...
            'Requested hydrogen withdrawal exceeds available mass at t=%d.',t);
        withdrawn=h2WithdrawalRequestKg(t);
    else
        withdrawn=min(h2WithdrawalRequestKg(t),availableH2);
    end
    hPrev=availableH2-withdrawn;
    assert(hPrev<=cfg.hydrogen.storageMaxKg+1e-6, ...
        'Hydrogen end inventory exceeds storage capacity at t=%d.',t);
    h2Residual(t)=hPrev-(hRet+produced-withdrawn);

    isOn=el>tol;
    startEvent(t)=isOn && ~elWasOn;
    flehPrev=flehPrev+el/cfg.hydrogen.electrolyzerRatedMW*dt;
    elWasOn=isOn; elPrev=el;

    pch(t)=ch; pdis(t)=dis; E(t)=ePrev;
    soc(t)=ePrev/cfg.bess.energyMWh;
    pel(t)=el; prod(t)=produced;
    waterM3(t)=produced*cfg.hydrogen.waterLPerKg/1000;
    h2Retained(t)=hRet; h2Available(t)=availableH2;
    h2End(t)=hPrev; h2Withdrawn(t)=withdrawn;
    h2Shortfall(t)=h2WithdrawalRequestKg(t)-withdrawn;
    h2StorageLoss(t)=hLossThis;
    h2DirectFlowThrough(t)=max(0,availableH2-cfg.hydrogen.storageMaxKg);
    fleh(t)=flehPrev; onlineModules(t)=nOnline;

    assert(abs(eBefore)>=0 && abs(hBefore)>=0); %#ok<ASGLU>
end

[bessTerminalOK,bessTerminalResidual,bessTerminalTarget]= ...
    terminal_check(E(end),eInitial,options,'bess',tol);
[h2TerminalOK,h2TerminalResidual,h2TerminalTarget]= ...
    terminal_check(h2End(end),hInitial,options,'h2',tol);
terminalOK=bessTerminalOK && h2TerminalOK;
if logical(option_value(options,'enforceTerminal',false)) && ~terminalOK
    error('BLUEHUB:TerminalConstraint45', ...
        ['4.5 terminal constraint failed: BESS residual %.6g MWh, ' ...
        'H2 residual %.6g kg.'],bessTerminalResidual,h2TerminalResidual);
end

result=struct;
result.timeH=timeH;
result.dtH=dtH;
result.pChargeMW=pch;
result.pDischargeMW=pdis;
result.pElectrolyzerMW=pel;
result.bessEnergyMWh=E;
result.bessSOC=soc;
result.h2ProductionKg=prod;
result.waterConsumptionM3=waterM3;
result.h2StorageLossKg=h2StorageLoss;
result.h2RetainedBeforeProductionKg=h2Retained;
result.h2AvailableForDeliveryKg=h2Available;
result.h2WithdrawnKg=h2Withdrawn;
result.h2WithdrawalShortfallKg=h2Shortfall;
result.h2InventoryKg=h2End;
result.h2DirectFlowThroughKg=h2DirectFlowThrough;
result.electrolyzerStartEvent=startEvent;
result.electrolyzerFLEH=fleh;
result.electrolyzerOnlineModules=onlineModules;
result.bessMassBalanceResidualMWh=bessResidual;
result.h2MassBalanceResidualKg=h2Residual;
result.bessConstraintCode=bessConstraint;
result.electrolyzerConstraintCode=elConstraint;
result.finalState=struct( ...
    'bessEnergyMWh',E(end), ...
    'h2InventoryKg',h2End(end), ...
    'electrolyzerOn',elWasOn, ...
    'electrolyzerPowerMW',elPrev, ...
    'electrolyzerFLEH',flehPrev);
result.terminal=struct( ...
    'ok',terminalOK, ...
    'bessOK',bessTerminalOK, ...
    'bessTargetMWh',bessTerminalTarget, ...
    'bessResidualMWh',bessTerminalResidual, ...
    'h2OK',h2TerminalOK, ...
    'h2TargetKg',h2TerminalTarget, ...
    'h2ResidualKg',h2TerminalResidual);
result.feasible=terminalOK && all(h2Shortfall<=tol) && ...
    all(E>=ePhysicalMin-tol) && ...
    all(E<=cfg.bess.socMax*cfg.bess.energyMWh+tol);
result.audit=struct( ...
    'modelClass','4.5_PHYSICAL_STATE_TRANSITION', ...
    'storageEquationSourceType','official open-source model documentation (PyPSA)', ...
    'electrolyzerSECSourceType','manufacturer specification (Nel MC Series)', ...
    'partLoadSECStatus','[assumption, pending OEM curve calibration]', ...
    'modularDispatchStatus', ...
    '[assumption, independent module commitment pending OEM/BOP confirmation]', ...
    'secBoundary','AC facility input to 30-barg hydrogen product; seawater pretreatment, higher-pressure compression, liquefaction and ship loading excluded');
end

function x=numeric_series(x,N,name)
x=double(x(:));
assert(numel(x)==N && all(isfinite(x)), ...
    '%s must be a finite N-by-1 series.',name);
assert(all(x>=0),'%s must be nonnegative.',name);
end

function dtH=step_series(cfg,timeH,options)
N=numel(timeH);
if isfield(options,'dtH')
    dtH=options.dtH;
else
    dtH=cfg.time.dispatchStepH;
end
if isscalar(dtH), dtH=repmat(double(dtH),N,1); else, dtH=double(dtH(:)); end
assert(numel(dtH)==N && all(isfinite(dtH)) && all(dtH>0), ...
    'dtH must be positive scalar or N-by-1.');
if N>1
    assert(max(abs(diff(timeH)-dtH(1:end-1)))<=1e-10, ...
        'timeH increments must equal the corresponding dtH values.');
end
end

function value=option_value(options,name,defaultValue)
if isfield(options,name), value=options.(name); else, value=defaultValue; end
end

function value=cfg_value(s,name,defaultValue)
if isfield(s,name), value=s.(name); else, value=defaultValue; end
end

function [ok,residual,target]=terminal_check(finalValue,initialValue,options,prefix,tol)
ruleName=[prefix 'TerminalRule'];
targetName=[prefix 'TerminalTarget'];
rule=string(option_value(options,ruleName,'free'));
target=option_value(options,targetName,initialValue);
assert(isscalar(target) && isfinite(target) && target>=0, ...
    '%s must be a finite nonnegative scalar.',targetName);
switch lower(rule)
    case {"free","free_with_terminal_value"}
        residual=0; ok=true;
    case "cyclic"
        residual=finalValue-target;
        ok=abs(residual)<=tol;
    case {"minimum","cyclic_or_minimum"}
        residual=finalValue-target;
        ok=residual>=-tol;
    otherwise
        error('Unsupported 4.5 terminal rule %s.',rule);
end
end
