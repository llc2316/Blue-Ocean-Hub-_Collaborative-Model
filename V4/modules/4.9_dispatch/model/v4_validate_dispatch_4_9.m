function report=v4_validate_dispatch_4_9(packet,d,cfg,p43,p46Boundary,strictMode)
%V4_VALIDATE_DISPATCH_4_9 Validate requests and physical planned closure.
if nargin<6, strictMode=true; end
errors={}; N=numel(packet.axis.timeH);
if ~strcmp(packet.meta.moduleId,'4.9'), errors{end+1}='moduleId must be 4.9.'; end %#ok<AGROW>
if ~strcmp(packet.meta.phase,'REQUEST'), errors{end+1}='4.9 packet phase must be REQUEST.'; end %#ok<AGROW>
required={'exportRequestedMW','marineRequestedMW','marineAllocatedMW', ...
    'computeRequestedMW','computeNominalMW','h2DeliveryCapKg','spillPlannedMW', ...
    'commonAuxUnservedPlannedMW','computeDeferredPlannedMW', ...
    'unservedPlannedMW','bessEnergyPlanMWh'};
for k=1:numel(required)
    if ~isfield(d,required{k}) || numel(d.(required{k}))~=N
        errors{end+1}=['Missing or invalid dispatch.' required{k}]; %#ok<AGROW>
    elseif any(~isfinite(d.(required{k})(:))) || any(d.(required{k})(:)<0)
        errors{end+1}=['Nonfinite or negative dispatch.' required{k}]; %#ok<AGROW>
    end
end
for f={'bessChargeMW','bessDischargeMW','electrolyzerMW'}
    if ~isfield(d.req45,f{1}) || numel(d.req45.(f{1}))~=N
        errors{end+1}=['Missing or invalid dispatch.req45.' f{1}]; %#ok<AGROW>
    end
end
if isempty(errors)
    ch=d.req45.bessChargeMW(:); dis=d.req45.bessDischargeMW(:); el=d.req45.electrolyzerMW(:);
    if any(ch>cfg.bess.chargeMaxMW+1e-9), errors{end+1}='Charge request exceeds capacity.'; end %#ok<AGROW>
    if any(dis>cfg.bess.dischargeMaxMW+1e-9), errors{end+1}='Discharge request exceeds capacity.'; end %#ok<AGROW>
    if any(ch>0 & dis>0), errors{end+1}='Simultaneous charge/discharge requested.'; end %#ok<AGROW>
    if any(el>cfg.hydrogen.electrolyzerRatedMW+1e-9), errors{end+1}='Electrolyzer request exceeds capacity.'; end %#ok<AGROW>
    if any(d.computeRequestedMW>p46Boundary.ports.dcFacility.maxMW+1e-9)
        errors{end+1}='Compute request exceeds the 4.6 boundary.'; %#ok<AGROW>
    end
    if any(d.computeRequestedMW>1e-9 & d.computeRequestedMW<cfg.compute.facilityMinMW-1e-9)
        errors{end+1}='Compute request must be zero or at least the online minimum.'; %#ok<AGROW>
    end
    if any(d.marineAllocatedMW>d.marineRequestedMW+1e-9)
        errors{end+1}='Marine allocation exceeds requested demand.'; %#ok<AGROW>
    end
    if any(d.exportRequestedMW>min(cfg.output.cableSendCapacityMW,cfg.output.gridAcceptMaxMW)+1e-9)
        errors{end+1}='Export request exceeds the active limit.'; %#ok<AGROW>
    end
    if any(d.bessEnergyPlanMWh<cfg.bess.socMin*cfg.bess.energyMWh-1e-9 | ...
            d.bessEnergyPlanMWh>cfg.bess.socMax*cfg.bess.energyMWh+1e-9)
        errors{end+1}='Planned battery energy violates SOC bounds.'; %#ok<AGROW>
    end
    closure=p43.ports.source.actualMW-p43.loss.pSourceAuxLoadMW ...
        -cfg.commonBus.commonAuxMW-cfg.commonBus.postPOILossMW ...
        -d.computeRequestedMW-d.marineAllocatedMW-el-ch+dis ...
        -d.exportRequestedMW-d.spillPlannedMW;
    if max(abs(closure))>cfg.commonBus.balanceToleranceMW
        errors{end+1}='4.9 physical planned closure exceeds tolerance.'; %#ok<AGROW>
    end
    expectedUnserved=(d.marineRequestedMW-d.marineAllocatedMW) ...
        +d.computeUnservedPlannedMW+d.commonAuxUnservedPlannedMW;
    if max(abs(expectedUnserved-d.unservedPlannedMW))>1e-9
        errors{end+1}='Unserved demand accounting is inconsistent.'; %#ok<AGROW>
    end
end
report=struct('moduleId','4.9','ok',isempty(errors),'errors',{errors(:)});
if strictMode && ~report.ok, error('BLUEHUB:Dispatch49Invalid','%s',strjoin(errors,newline)); end
end
