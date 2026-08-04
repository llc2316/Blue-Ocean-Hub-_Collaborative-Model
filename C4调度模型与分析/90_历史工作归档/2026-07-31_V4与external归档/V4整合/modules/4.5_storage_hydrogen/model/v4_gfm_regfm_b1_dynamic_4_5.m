function result=v4_gfm_regfm_b1_dynamic_4_5(params,scenario)
%V4_GFM_REGFM_B1_DYNAMIC_4_5 Reduced-order positive-sequence GFM proxy.
%
% Frequency states implement the public WECC REGFM_B1 VSM structure:
%   Tp*dpd/dt + pd = (wref-wm)/mp
%   Tpf*dpf/dt + pf = p
%   2H*d(dw)/dt = pref+pd-pf-D1*dw-D2*(dw-zd)
%   dzd/dt = omegaD*(dw-zd), ddelta/dt = omega0*dw
% Source: NREL/WECC REGFM_B1, https://www.osti.gov/biblio/2376832
%
% Q-V control uses the REGFM_B1 VdrpFlag=0 arrangement. The internal
% voltage source is connected to a constant-impedance load through a
% reduced-order R+jX interface. Positive-sequence current is clipped at
% the published PCS boundary and the terminal P/Q/V are recomputed.
%
% Claim boundary: this is not an EMT model. It cannot certify transformer
% inrush, harmonics, unbalance, protection coordination, fault ride
% through or black-start equipment qualification.

requiredParams={'ratedMVA','ratedMW','energyMWh','energyInitialMWh', ...
    'energyMinMWh','energyMaxMWh','etaCharge','etaDischarge', ...
    'nominalFrequencyHz','mp','mq','H','D1','D2','omegaD', ...
    'TpS','TPfS','TQfS','TVfS','kpv','kiv','EminPU','EmaxPU', ...
    'currentMaxFPU','filterResistancePU','filterReactancePU', ...
    'omegaMinPU','omegaMaxPU'};
for k=1:numel(requiredParams)
    assert(isfield(params,requiredParams{k}), ...
        'Missing REGFM_B1 parameter %s.',requiredParams{k});
end
requiredScenario={'timeS','pDemandMW','qDemandMvar'};
for k=1:numel(requiredScenario)
    assert(isfield(scenario,requiredScenario{k}), ...
        'Missing GFM scenario field %s.',requiredScenario{k});
end

timeS=double(scenario.timeS(:)); N=numel(timeS);
assert(N>=2 && all(isfinite(timeS)) && all(diff(timeS)>0), ...
    'GFM timeS must be finite and increasing.');
dtS=[diff(timeS); timeS(end)-timeS(end-1)];
pDemand=series(scenario.pDemandMW,N,'pDemandMW');
qDemand=series(scenario.qDemandMvar,N,'qDemandMvar');
baseDispatchMW=series(option_value(scenario,'baseDispatchMW', ...
    pDemand(1)),N,'baseDispatchMW');
if isfield(scenario,'frequencyReferencePU')
    wRef=series(scenario.frequencyReferencePU,N,'frequencyReferencePU');
else
    wRef=ones(N,1);
end
if isfield(scenario,'voltageReferencePU')
    vRef=series(scenario.voltageReferencePU,N,'voltageReferencePU');
else
    vRef=ones(N,1);
end
if isfield(scenario,'pReferencePU')
    pRef=series(scenario.pReferencePU,N,'pReferencePU');
else
    pRef=baseDispatchMW/params.ratedMVA;
end
if isfield(scenario,'qReferencePU')
    qRef=series(scenario.qReferencePU,N,'qReferencePU');
else
    qRef=zeros(N,1);
end
assert(all(wRef>=0 & wRef<=1.1),'frequencyReferencePU is outside proxy range.');
assert(all(vRef>=0 & vRef<=1.2),'voltageReferencePU is outside proxy range.');
assert(all(baseDispatchMW>=0),'baseDispatchMW must be nonnegative.');

assert(params.ratedMVA>0 && params.ratedMW>0 && params.energyMWh>0);
assert(params.energyMinMWh<=params.energyInitialMWh && ...
    params.energyInitialMWh<=params.energyMaxMWh);
assert(params.mp>0 && params.mq>0 && params.H>0);
assert(all([params.TpS params.TPfS params.TQfS params.TVfS]>0));
assert(params.filterResistancePU>=0 && params.filterReactancePU>0);
assert(params.omegaMinPU<0 && params.omegaMaxPU>0);
assert(max(dtS)<= ...
    min([params.TpS params.TPfS params.TQfS params.TVfS])/5+1e-12, ...
    'Dynamic time step is too large for explicit REGFM_B1 integration.');

dw=zeros(N,1); pd=zeros(N,1); pf=zeros(N,1); zd=zeros(N,1);
delta=zeros(N,1); qf=zeros(N,1); vf=zeros(N,1);
Einternal=zeros(N,1); xiV=zeros(N,1);
pActualMW=zeros(N,1); qActualMvar=zeros(N,1);
pInverterMW=zeros(N,1); filterLossMW=zeros(N,1);
terminalVoltagePU=zeros(N,1); currentPU=zeros(N,1);
energyMWh=zeros(N,1); pShortfall=zeros(N,1); qShortfall=zeros(N,1);
currentLimited=false(N,1); powerLimited=false(N,1);
energyLimited=false(N,1);
voltageSaturated=false(N,1); frequencySaturated=false(N,1);

if isfield(scenario,'initialFrequencyDeviationPU')
    dw(1)=double(scenario.initialFrequencyDeviationPU);
end
if isfield(scenario,'initialAngleRad')
    delta(1)=double(scenario.initialAngleRad);
end
if isfield(scenario,'initialInternalVoltagePU')
    Einternal(1)=double(scenario.initialInternalVoltagePU);
else
    Einternal(1)=vRef(1);
end
if isfield(scenario,'initialVoltageIntegratorPU')
    xiV(1)=double(scenario.initialVoltageIntegratorPU);
else
    xiV(1)=Einternal(1);
end
vf(1)=option_value(scenario,'initialFilteredVoltagePU',Einternal(1));
pf(1)=pRef(1);
energyMWh(1)=params.energyInitialMWh;
omega0=2*pi*params.nominalFrequencyHz;
filterZ=complex(params.filterResistancePU,params.filterReactancePU);

for k=1:N
    dt=dtS(k);
    eNow=energyMWh(k);
    maxDischargeMW=max(0,(eNow-params.energyMinMWh)* ...
        params.etaDischarge*3600/dt);
    maxChargeMW=max(0,(params.energyMaxMWh-eNow)* ...
        3600/(params.etaCharge*dt));
    [terminalVoltagePU(k),currentPU(k),pActualMW(k), ...
        qActualMvar(k),pInverterMW(k),filterLossMW(k), ...
        currentLimited(k),powerLimited(k),energyLimited(k)]= ...
        network_service_point( ...
        Einternal(k),delta(k),pDemand(k),qDemand(k),filterZ,params, ...
        maxDischargeMW,maxChargeMW);
    pShortfall(k)=pDemand(k)-pActualMW(k);
    qShortfall(k)=qDemand(k)-qActualMvar(k);

    if k==N, break; end
    pPU=pActualMW(k)/params.ratedMVA;
    qPU=qActualMvar(k)/params.ratedMVA;
    dPd=((-dw(k))/params.mp-pd(k))/params.TpS;
    dPf=(pPU-pf(k))/params.TPfS;
    dZd=params.omegaD*(dw(k)-zd(k));
    yD=params.D2*(dw(k)-zd(k));
    dDw=(pRef(k)+pd(k)-pf(k)-params.D1*dw(k)-yD)/(2*params.H);
    dDelta=omega0*dw(k);
    dQf=(qPU-qf(k))/params.TQfS;
    dVf=(terminalVoltagePU(k)-vf(k))/params.TVfS;
    vCommand=vRef(k)+params.mq*(qRef(k)-qf(k));
    voltageError=vCommand-vf(k);
    xiCandidate=xiV(k)+params.kiv*voltageError*dt;
    eUnsaturated=params.kpv*voltageError+xiCandidate;
    eNext=min(params.EmaxPU,max(params.EminPU,eUnsaturated));
    voltageSaturated(k+1)=abs(eNext-eUnsaturated)>1e-12;
    if voltageSaturated(k+1) && ...
            sign(voltageError)==sign(eUnsaturated-eNext)
        xiCandidate=xiV(k);
        eUnsaturated=params.kpv*voltageError+xiCandidate;
        eNext=min(params.EmaxPU,max(params.EminPU,eUnsaturated));
    end

    pd(k+1)=pd(k)+dPd*dt;
    pf(k+1)=pf(k)+dPf*dt;
    zd(k+1)=zd(k)+dZd*dt;
    dwCandidate=dw(k)+dDw*dt;
    dw(k+1)=min(params.omegaMaxPU,max(params.omegaMinPU,dwCandidate));
    frequencySaturated(k+1)=abs(dw(k+1)-dwCandidate)>1e-12;
    delta(k+1)=delta(k)+dDelta*dt;
    qf(k+1)=qf(k)+dQf*dt;
    vf(k+1)=vf(k)+dVf*dt;
    xiV(k+1)=xiCandidate;
    Einternal(k+1)=eNext;
    if pInverterMW(k)>=0
        energyMWh(k+1)=eNow-pInverterMW(k)*dt/ ...
            (3600*params.etaDischarge);
    else
        energyMWh(k+1)=eNow-params.etaCharge*pInverterMW(k)*dt/3600;
    end
end

frequencyHz=params.nominalFrequencyHz*(wRef+dw);
rocofHzPerS=[0; diff(frequencyHz)./diff(timeS)];
soc=energyMWh/params.energyMWh;
eventIndex=find(abs(diff(pDemand))>1e-9,1,'first')+1;
if isempty(eventIndex), eventIndex=1; end
eventTime=timeS(eventIndex);
halfSecondIndex=find(timeS>=eventTime+0.5,1,'first');
if isempty(halfSecondIndex)
    rocof05=NaN;
else
    rocof05=(frequencyHz(halfSecondIndex)-frequencyHz(eventIndex))/ ...
        (timeS(halfSecondIndex)-timeS(eventIndex));
end
nadirMask=timeS>=eventTime & timeS<=eventTime+12;

blackStart=logical(option_value(scenario,'blackStart',false));
blackStartSOCMin=option_value(scenario,'blackStartSOCMin',0);
blackStartReady=params.energyInitialMWh/params.energyMWh>=blackStartSOCMin;
energizedMask=frequencyHz>=0.98*params.nominalFrequencyHz & ...
    terminalVoltagePU>=0.90;
energizedIndex=find(energizedMask,1,'first');
if isempty(energizedIndex)
    energizedTimeS=NaN;
else
    energizedTimeS=timeS(energizedIndex);
end
firstLoadIndex=find(pDemand>1e-9 | qDemand>1e-9,1,'first');
if isempty(firstLoadIndex)
    firstLoadPickupTimeS=NaN;
    loadPickupAfterEnergization=true;
else
    firstLoadPickupTimeS=timeS(firstLoadIndex);
    loadPickupAfterEnergization=~isnan(energizedTimeS) && ...
        firstLoadPickupTimeS>=energizedTimeS-1e-12;
end

incrementDemandMW=max(0,pDemand-baseDispatchMW);
incrementActualMW=max(0,pInverterMW-baseDispatchMW);
requiredReservePowerMW=max(incrementDemandMW);
requiredReserveEnergyMWh=trapz(timeS,incrementDemandMW)/3600;
actualDynamicSupportEnergyMWh=trapz(timeS,incrementActualMW)/3600;
if isfield(scenario,'reservedPowerMW')
    reservePowerMW=double(scenario.reservedPowerMW);
    assert(isscalar(reservePowerMW) && isfinite(reservePowerMW) && ...
        reservePowerMW>=0);
    reservePowerAdequate=reservePowerMW+1e-9>=requiredReservePowerMW && ...
        all(baseDispatchMW+reservePowerMW<=params.ratedMW+1e-9);
else
    reservePowerMW=NaN;
    reservePowerAdequate=true;
end
if isfield(scenario,'reservedEnergyMWh')
    reserveEnergyMWh=double(scenario.reservedEnergyMWh);
    assert(isscalar(reserveEnergyMWh) && isfinite(reserveEnergyMWh) && ...
        reserveEnergyMWh>=0);
    reserveEnergyAdequate= ...
        reserveEnergyMWh+1e-9>=requiredReserveEnergyMWh;
else
    reserveEnergyMWh=NaN;
    reserveEnergyAdequate=true;
end

result=struct;
result.timeS=timeS;
result.frequencyHz=frequencyHz;
result.frequencyDeviationPU=dw;
result.rocofHzPerS=rocofHzPerS;
result.rocof05HzPerS=rocof05;
result.frequencyNadirHz=min(frequencyHz(nadirMask));
result.pDemandMW=pDemand;
result.qDemandMvar=qDemand;
result.pActualMW=pActualMW;
result.qActualMvar=qActualMvar;
result.pInverterMW=pInverterMW;
result.filterLossMW=filterLossMW;
result.pServiceShortfallMW=pShortfall;
result.qServiceShortfallMvar=qShortfall;
result.currentPU=currentPU;
result.currentLimited=currentLimited;
result.powerLimited=powerLimited;
result.terminalVoltagePU=terminalVoltagePU;
result.internalVoltageCommandPU=Einternal;
result.internalVoltagePU=Einternal;
result.voltageIntegratorPU=xiV;
result.voltageSaturated=voltageSaturated;
result.frequencySaturated=frequencySaturated;
result.angleRad=delta;
result.droopPowerStatePU=pd;
result.filteredPowerPU=pf;
result.washoutStatePU=zd;
result.filteredReactivePowerPU=qf;
result.filteredVoltagePU=vf;
result.energyMWh=energyMWh;
result.soc=soc;
result.energyLimited=energyLimited;
result.baseDispatchMW=baseDispatchMW;
result.dynamicIncrementDemandMW=incrementDemandMW;
result.dynamicIncrementActualMW=incrementActualMW;
result.requiredReservePowerMW=requiredReservePowerMW;
result.requiredReserveEnergyMWh=requiredReserveEnergyMWh;
result.actualDynamicSupportEnergyMWh=actualDynamicSupportEnergyMWh;
result.reservedPowerMW=reservePowerMW;
result.reservedEnergyMWh=reserveEnergyMWh;
result.reservePowerAdequate=reservePowerAdequate;
result.reserveEnergyAdequate=reserveEnergyAdequate;
result.blackStart=struct( ...
    'requested',blackStart, ...
    'socReady',blackStartReady, ...
    'energized',~isnan(energizedTimeS), ...
    'energizedTimeS',energizedTimeS, ...
    'firstLoadPickupTimeS',firstLoadPickupTimeS, ...
    'loadPickupAfterEnergization',loadPickupAfterEnergization);
result.feasible=all(~energyLimited) && all(~currentLimited) && ...
    all(~powerLimited) && ...
    all(currentPU<=params.currentMaxFPU+1e-9) && ...
    reservePowerAdequate && reserveEnergyAdequate && ...
    (~blackStart || (blackStartReady && ~isnan(energizedTimeS) && ...
    loadPickupAfterEnergization));
result.audit=struct( ...
    'modelClass','WECC_REGFM_B1_REDUCED_ORDER_POSITIVE_SEQUENCE_CONSTANT_IMPEDANCE_LOAD_PROXY', ...
    'formulaSourceType','official national-laboratory/WECC technical report', ...
    'currentLimitSourceType','official PNNL/WECC technical report', ...
    'socSourceType','national-laboratory paper and official open-source documentation', ...
    'networkBoundary',['internal voltage source behind reduced-order R+jX; ' ...
        'terminal load is constant impedance and clipped by current/energy limits'], ...
    'parameterStatus','[assumption, pending PCS/transformer vendor calibration]', ...
    'blackStartStatus',['Tier-4 application-specific behavioral proxy only; ' ...
        'EMT/HIL and protection studies required'], ...
    'notValidated',['transformer inrush; harmonics; phase unbalance; faults; ' ...
        'relay coordination; multi-inverter synchronization']);
end

function [vMag,iMag,pTerminal,qTerminal,pInternal,lossMW, ...
        currentLimited,powerLimited,energyLimited]=network_service_point( ...
        eInternal,delta,pDemand,qDemand,z,params,maxDischarge,maxCharge)
% Algebraic network closure. P/Q demand defines nominal-voltage
% constant-impedance service. Current clipping represents curtailed load.
ePhasor=eInternal*exp(1i*delta);
yLoad=complex(pDemand,-qDemand)/params.ratedMVA;
vFree=ePhasor/(1+z*yLoad);
iFree=yLoad*vFree;
if abs(iFree)>params.currentMaxFPU
    iPhasor=iFree/abs(iFree)*params.currentMaxFPU;
    currentLimited=true;
else
    iPhasor=iFree;
    currentLimited=false;
end
[vPhasor,sTerminal,sInternal]=phasor_power( ...
    ePhasor,z,iPhasor,params.ratedMVA);
powerLimited=real(sTerminal)>params.ratedMW+1e-9 || ...
    real(sTerminal)<-params.ratedMW-1e-9;
if powerLimited && abs(iPhasor)>eps
    if real(sTerminal)>params.ratedMW
        activeLimit=params.ratedMW;
        direction=1;
    else
        activeLimit=-params.ratedMW;
        direction=-1;
    end
    lo=0; hi=1;
    for iteration=1:60 %#ok<NASGU>
        alpha=(lo+hi)/2;
        [~,sTry,~]=phasor_power( ...
            ePhasor,z,alpha*iPhasor,params.ratedMVA);
        if direction*real(sTry)<=direction*activeLimit
            lo=alpha;
        else
            hi=alpha;
        end
    end
    iPhasor=lo*iPhasor;
    [vPhasor,sTerminal,sInternal]=phasor_power( ...
        ePhasor,z,iPhasor,params.ratedMVA);
end
pInternalCandidate=real(sInternal);
energyLimited=pInternalCandidate>maxDischarge+1e-9 || ...
    pInternalCandidate<-maxCharge-1e-9;
if energyLimited && abs(iPhasor)>eps
    if pInternalCandidate>maxDischarge
        activeLimit=maxDischarge;
        direction=1;
    else
        activeLimit=-maxCharge;
        direction=-1;
    end
    lo=0; hi=1;
    for iteration=1:60 %#ok<NASGU>
        alpha=(lo+hi)/2;
        [~,~,sTry]=phasor_power( ...
            ePhasor,z,alpha*iPhasor,params.ratedMVA);
        if direction*real(sTry)<=direction*activeLimit
            lo=alpha;
        else
            hi=alpha;
        end
    end
    iPhasor=lo*iPhasor;
    [vPhasor,sTerminal,sInternal]=phasor_power( ...
        ePhasor,z,iPhasor,params.ratedMVA);
end
vMag=abs(vPhasor);
iMag=abs(iPhasor);
pTerminal=real(sTerminal);
qTerminal=imag(sTerminal);
pInternal=real(sInternal);
lossMW=max(0,pInternal-pTerminal);
end

function [vPhasor,sTerminal,sInternal]= ...
        phasor_power(ePhasor,z,iPhasor,ratedMVA)
vPhasor=ePhasor-z*iPhasor;
sTerminal=vPhasor*conj(iPhasor)*ratedMVA;
sInternal=ePhasor*conj(iPhasor)*ratedMVA;
end

function x=series(x,N,name)
if isscalar(x), x=repmat(double(x),N,1); else, x=double(x(:)); end
assert(numel(x)==N && all(isfinite(x)), ...
    '%s must be finite scalar or N-by-1.',name);
end

function value=option_value(s,name,defaultValue)
if isfield(s,name), value=s.(name); else, value=defaultValue; end
end
