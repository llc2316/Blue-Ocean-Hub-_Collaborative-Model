function gate = v5_select_gfm_dynamic_gate_points(result)
%V5_SELECT_GFM_DYNAMIC_GATE_POINTS Select hourly states for dynamic tests.
%
% This function does not calculate voltage, frequency, RoCoF or nadir. It
% identifies operating points that must be replayed in the validated REGFM
% or EMT layer. Dynamic acceptance formulas and thresholds remain
% [需查证文献支撑] until the selected evidence and PCS data are signed.

d=result.dispatch;
sourceRamp=[0;diff(d.pSourceAvailableMW)];
events={ ...
    'MAX_BESS_DISCHARGE',argmax(d.pBessDischargeMW); ...
    'MAX_BESS_CHARGE',argmax(d.pBessChargeMW); ...
    'MIN_BESS_SOC',argmin(d.bessSOC); ...
    'MAX_SOURCE_RAMP_UP',argmax(sourceRamp); ...
    'MAX_SOURCE_RAMP_DOWN',argmin(sourceRamp); ...
    'MAX_CABLE_SEND',argmax(d.pCableSendMW); ...
    'MAX_ELECTROLYZER_LOAD',argmax(d.pElectrolyzerMW); ...
    'MAX_COMPUTE_LOAD',argmax(d.pComputeFacilityMW); ...
    'MAX_CURTAILMENT',argmax(d.pCurtailmentMW)};

n=size(events,1);
eventName=string(events(:,1));
rowIndex=cell2mat(events(:,2));
timeH=d.timeH(rowIndex);
pSourceAvailableMW=d.pSourceAvailableMW(rowIndex);
sourceRampMWPerH=sourceRamp(rowIndex);
pBessChargeMW=d.pBessChargeMW(rowIndex);
pBessDischargeMW=d.pBessDischargeMW(rowIndex);
bessSOC=d.bessSOC(rowIndex);
pCableSendMW=d.pCableSendMW(rowIndex);
pElectrolyzerMW=d.pElectrolyzerMW(rowIndex);
pComputeFacilityMW=d.pComputeFacilityMW(rowIndex);
pCurtailmentMW=d.pCurtailmentMW(rowIndex);
dynamicValidationStatus=repmat( ...
    "NOT_RUN_REQUIRES_REGFM_OR_EMT_GATE",n,1);
requiredOutputs=repmat( ...
    "frequency_nadir;RoCoF;voltage_deviation;current_limit;recovery_time", ...
    n,1);
formulaStatus=repmat("[需查证文献支撑]",n,1);

gate=table(eventName,rowIndex,timeH,pSourceAvailableMW, ...
    sourceRampMWPerH,pBessChargeMW,pBessDischargeMW,bessSOC, ...
    pCableSendMW,pElectrolyzerMW,pComputeFacilityMW,pCurtailmentMW, ...
    dynamicValidationStatus,requiredOutputs,formulaStatus);
end

function idx=argmax(x)
[~,idx]=max(x);
end

function idx=argmin(x)
[~,idx]=min(x);
end
