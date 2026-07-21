function provisional=v4_storage_hydrogen_response(cfg,timeH,req,state0,h2WithdrawnKg)
%V4_STORAGE_HYDROGEN_RESPONSE 4.5 response using existing SOC/SEC relations.
% No cross-module allocation is performed here; req is owned by the rule stub/4.9.
N=numel(timeH); dt=cfg.time.dispatchStepH;
if nargin<5 || isempty(h2WithdrawnKg), h2WithdrawnKg=zeros(N,1); end
h2WithdrawnKg=double(h2WithdrawnKg(:));
assert(numel(h2WithdrawnKg)==N && all(h2WithdrawnKg>=0), ...
    '4.7 actual hydrogen withdrawal must be nonnegative N-by-1.');
fields={'bessChargeMW','bessDischargeMW','electrolyzerMW'};
for k=1:numel(fields)
    assert(isfield(req,fields{k}) && numel(req.(fields{k}))==N, ...
        'Missing or invalid 4.5 request %s.',fields{k});
end
E=zeros(N,1); soc=zeros(N,1); h2BeforeDelivery=zeros(N,1); h2End=zeros(N,1); prod=zeros(N,1);
pch=zeros(N,1); pdis=zeros(N,1); pel=zeros(N,1);
ePrev=state0.bessEnergyMWh; hPrev=state0.h2InventoryKg;
for t=1:N
    ch=max(0,min(req.bessChargeMW(t),cfg.bess.chargeMaxMW));
    dis=max(0,min(req.bessDischargeMW(t),cfg.bess.dischargeMaxMW));
    assert(ch==0 || dis==0,'Simultaneous charge/discharge request is forbidden.');
    room=max(0,cfg.bess.socMax*cfg.bess.energyMWh-ePrev);
    available=max(0,(ePrev-cfg.bess.socMin*cfg.bess.energyMWh));
    ch=min(ch,room/(cfg.bess.etaCharge*dt));
    dis=min(dis,available*cfg.bess.etaDischarge/dt);
    ePrev=ePrev+cfg.bess.etaCharge*ch*dt-dis*dt/cfg.bess.etaDischarge;

    el=max(0,min(req.electrolyzerMW(t),cfg.hydrogen.electrolyzerRatedMW));
    if el>0 && el<cfg.hydrogen.electrolyzerMinMW, el=0; end
    maxByTank=max(0,(cfg.hydrogen.storageMaxKg-hPrev)*cfg.hydrogen.secKWhPerKg/(1000*dt));
    el=min(el,maxByTank);
    if el>0 && el<cfg.hydrogen.electrolyzerMinMW, el=0; end
    produced=1000*el*dt/cfg.hydrogen.secKWhPerKg;
    availableH2=min(cfg.hydrogen.storageMaxKg,hPrev+produced);
    assert(h2WithdrawnKg(t)<=availableH2+1e-9, ...
        '4.7 actual withdrawal exceeds 4.5 available hydrogen at t=%d.',t);
    hPrev=availableH2-h2WithdrawnKg(t);

    pch(t)=ch; pdis(t)=dis; pel(t)=el; E(t)=ePrev;
    soc(t)=ePrev/cfg.bess.energyMWh; prod(t)=produced;
    h2BeforeDelivery(t)=availableH2; h2End(t)=hPrev;
end
provisional=struct('pChargeMW',pch,'pDischargeMW',pdis,'pElectrolyzerMW',pel, ...
    'bessEnergyMWh',E,'bessSOC',soc,'h2ProductionKg',prod, ...
    'h2AvailableForDeliveryKg',h2BeforeDelivery,'h2InventoryKg',h2End);
end
