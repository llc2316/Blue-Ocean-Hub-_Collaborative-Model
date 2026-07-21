function report=validate_module_packet_4_2(packet,moduleId,cfg,strictMode)
%VALIDATE_MODULE_PACKET_4_2 Validate a 4.3--4.7 exchange packet.

if nargin<4, strictMode=true; end
validate_common_schema_4_2(cfg,true);
moduleId=validatestring(char(moduleId),{'4.3','4.4','4.5','4.6','4.7'});
errors={}; warnings={};

top={'meta','axis','ports','state','product','service','loss','quality','audit'};
for i=1:numel(top)
    if ~isfield(packet,top{i}), errors{end+1}=['Missing packet.' top{i}]; end %#ok<AGROW>
end
if ~isempty(errors), report=finish(errors,warnings,moduleId); throw_if_needed(report,strictMode); return; end

metaFields=cfg.interface.commonMeta;
for i=1:numel(metaFields)
    if ~isfield(packet.meta,metaFields{i})
        errors{end+1}=['Missing packet.meta.' metaFields{i}]; %#ok<AGROW>
    end
end
if isempty(errors)
    errors=check(errors,strcmp(packet.meta.schemaId,cfg.meta.schemaId),'schemaId mismatch.');
    errors=check(errors,strcmp(packet.meta.schemaVersion,cfg.meta.schemaVersion),'schemaVersion mismatch.');
    errors=check(errors,strcmp(packet.meta.caseId,cfg.meta.caseId),'caseId mismatch.');
    errors=check(errors,strcmp(packet.meta.caseMode,cfg.meta.caseMode),'caseMode mismatch.');
    errors=check(errors,strcmp(packet.meta.parameterVersion,cfg.meta.parameterVersion),'parameterVersion mismatch.');
    errors=check(errors,strcmp(packet.meta.moduleId,moduleId),'moduleId mismatch.');
    errors=check(errors,any(strcmp(packet.meta.phase,cfg.enums.packetPhase)),'Unsupported packet phase.');
end

axisFields=cfg.interface.commonAxis;
for i=1:numel(axisFields)
    if ~isfield(packet.axis,axisFields{i})
        errors{end+1}=['Missing packet.axis.' axisFields{i}]; %#ok<AGROW>
    end
end
if isfield(packet.axis,'timeH')
    t=packet.axis.timeH(:); N=numel(t);
    errors=check(errors,N>=1 && all(isfinite(t)) && (N==1 || all(diff(t)>0)), ...
        'timeH must be finite and strictly increasing.');
else
    N=0;
end
if isfield(packet.axis,'dtH')
    errors=check(errors,isscalar(packet.axis.dtH) && ...
        abs(packet.axis.dtH-cfg.time.dispatchStepH)<=1e-12,'dtH mismatch.');
end

requiredPorts=ports_for_module(moduleId);
for i=1:numel(requiredPorts)
    name=requiredPorts{i};
    if ~isfield(packet.ports,name)
        errors{end+1}=['Missing packet.ports.' name]; %#ok<AGROW>
    else
        errors=validate_port(errors,packet.ports.(name),name,N,cfg,packet.meta.phase);
    end
end

errors=validate_module_data(errors,packet,moduleId,N);
if strcmp(moduleId,'4.7') && isfield(packet.ports,'gridImport') && ~cfg.commonBus.allowGridImport
    p=packet.ports.gridImport;
    for field={'requestedMW','acceptedMW','actualMW','maxMW'}
        if isfield(p,field{1})
            x=p.(field{1}); finite=x(isfinite(x));
            errors=check(errors,all(abs(finite)<=1e-12), ...
                ['Grid import is disabled but gridImport.' field{1} ' is nonzero.']);
        end
    end
end
if isfield(packet.audit,'implicitDefaultsUsed')
    errors=check(errors,isequal(packet.audit.implicitDefaultsUsed,false), ...
        'Integrated packet reports implicit defaults.');
end
report=finish(errors,warnings,moduleId);
throw_if_needed(report,strictMode);
end

function names=ports_for_module(moduleId)
switch moduleId
    case '4.3', names={'source'};
    case '4.4', names={};
    case '4.5', names={'bessCharge','bessDischarge','electrolyzer'};
    case '4.6', names={'dcFacility'};
    case '4.7', names={'exportSend','gridImport','marine'};
end
end

function errors=validate_port(errors,p,name,N,cfg,phase)
fields=cfg.interface.commonDispatchPort;
for j=1:numel(fields)
    if ~isfield(p,fields{j}), errors{end+1}=['Missing port field ' name '.' fields{j}]; end %#ok<AGROW>
end
if isfield(p,'meterPoint')
    expected=expected_meter(name,cfg);
    errors=check(errors,isstring(p.meterPoint) || ischar(p.meterPoint), ...
        ['Port ' name ' meterPoint must be text.']);
    if strlength(expected)>0
        errors=check(errors,strcmp(string(p.meterPoint),expected), ...
            ['Port ' name ' meterPoint mismatch; expected ' char(expected) '.']);
    end
end
if isfield(p,'qualityFlag')
    errors=check(errors,islogical(p.qualityFlag) && size(p.qualityFlag,1)==N, ...
        ['Port ' name ' qualityFlag must be logical with N rows.']);
end
numeric={'requestedMW','acceptedMW','actualMW','minMW','maxMW', ...
    'upCapabilityMW','downCapabilityMW'};
for j=1:numel(numeric)
    if isfield(p,numeric{j})
        x=p.(numeric{j});
        errors=check(errors,isnumeric(x) && size(x,1)==N, ...
            ['Port field ' name '.' numeric{j} ' must have N rows.']);
        finiteValues=x(isfinite(x));
        errors=check(errors,all(finiteValues>=0), ...
            ['Port field ' name '.' numeric{j} ' must be nonnegative.']);
    end
end

function meter=expected_meter(name,cfg)
switch name
    case 'source', meter=string(cfg.meter.sourcePOI);
    case {'bessCharge','bessDischarge','marine'}, meter=string(cfg.meter.commonBus);
    case 'electrolyzer', meter=string(cfg.meter.electrolyzer);
    case 'dcFacility', meter=string(cfg.meter.dcFacility);
    case {'exportSend','gridImport'}, meter=string(cfg.meter.cableSend);
    otherwise, meter="";
end
end
switch phase
    case 'BOUNDARY', mustBeFinite={'minMW','maxMW','upCapabilityMW','downCapabilityMW'};
    case 'REQUEST', mustBeFinite={'requestedMW','minMW','maxMW'};
    case 'RESPONSE', mustBeFinite=numeric;
    otherwise, mustBeFinite={};
end
for j=1:numel(mustBeFinite)
    if isfield(p,mustBeFinite{j})
        errors=check(errors,all(isfinite(p.(mustBeFinite{j})),'all'), ...
            ['Port field ' name '.' mustBeFinite{j} ' must be finite in phase ' phase '.']);
    end
end
if all(isfield(p,{'minMW','maxMW','acceptedMW','actualMW'}))
    valid=isfinite(p.minMW)&isfinite(p.maxMW)&isfinite(p.acceptedMW)&isfinite(p.actualMW);
    errors=check(errors,all(p.minMW(valid)<=p.maxMW(valid)),['Port ' name ' has min>max.']);
    errors=check(errors,all(p.acceptedMW(valid)>=p.minMW(valid)-1e-9 & ...
        p.acceptedMW(valid)<=p.maxMW(valid)+1e-9),['Port ' name ' accepted is outside bounds.']);
    errors=check(errors,all(p.actualMW(valid)>=p.minMW(valid)-1e-9 & ...
        p.actualMW(valid)<=p.maxMW(valid)+1e-9),['Port ' name ' actual is outside bounds.']);
end
end

function errors=validate_module_data(errors,p,moduleId,N)
switch moduleId
    case '4.3'
        errors=require_fields(errors,p.loss,{'pCollectionLossMW','pSourceAuxLoadMW','collectionLossAlreadyDeducted'},'loss');
    case '4.4'
        errors=require_fields(errors,p.state,{'pBusResidualMW','pSpillActualMW','pUnservedMW','balanceStatus'},'state');
    case '4.5'
        errors=require_fields(errors,p.state,{'bessSOC','bessEnergyMWh','h2InventoryKg'},'state');
        errors=require_fields(errors,p.product,{'h2ProductionKg','h2AvailableForDeliveryKg'},'product');
    case '4.6'
        errors=require_fields(errors,p.state,{'computeQueueMWhCS'},'state');
        errors=require_fields(errors,p.service,{'computeServedMWhCS','pITActualMW','pDCAuxActualMW'},'service');
    case '4.7'
        errors=require_fields(errors,p.product,{'h2DeliveredKg'},'product');
        errors=require_fields(errors,p.service,{'pCableReceiveMW','cableLossMW','computeDeliveredMWhCS','marineUnservedMW'},'service');
end
if N<1, errors{end+1}='Packet has no time rows.'; end
end

function errors=require_fields(errors,s,fields,label)
for i=1:numel(fields)
    if ~isfield(s,fields{i}), errors{end+1}=['Missing packet.' label '.' fields{i}]; end %#ok<AGROW>
end
end

function errors=check(errors,condition,message)
if ~condition, errors{end+1}=message; end
end
function report=finish(errors,warnings,moduleId)
report=struct('moduleId',moduleId,'ok',isempty(errors),'errorCount',numel(errors), ...
    'warningCount',numel(warnings),'errors',{errors(:)},'warnings',{warnings(:)});
end
function throw_if_needed(report,strictMode)
if strictMode && ~report.ok
    error('BLUEHUB:ModulePacketInvalid','%s',strjoin(report.errors,newline));
end
end
