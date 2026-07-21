function [packet,raw]=v4_source_adapter(cfg,phase)
%V4_SOURCE_ADAPTER Run existing 4.3 baseline and map 5-min W signals to 1-h MW.
if nargin<2 || isempty(phase), phase='RESPONSE'; end
moduleRoot=fileparts(fileparts(mfilename('fullpath')));
base=moduleRoot;
addpath(fullfile(base,'demos'));
raw=demo_public_baseline_v2(false); % Only raw.source is consumed by V4.

src=raw.source;
tSec=double(src.time(:));
assert(numel(tSec)>=288 && abs(tSec(1))<1e-12,'Unexpected 4.3 time axis.');
idx=1:288; % 24 half-open hourly intervals; endpoint at 24 h is excluded.
timeH=(0:23)';
agg=@(x) reshape(mean(reshape(double(x(idx)),12,24),1),24,1)/1e6;

pAvailable=agg(src.aggregate.available);
pRequested=agg(src.aggregate.requested);
pAccepted=agg(src.aggregate.accepted);
pActual=agg(src.aggregate.actual);
pAux=agg(src.aggregate.sourceAuxLoad);
pLoss=agg(src.aggregate.actualCollectionLoss);

packet=common_packet_4_2('4.3',timeH,cfg,phase);
packet.ports.source=v4_fill_port(timeH,cfg.meter.sourcePOI, ...
    pRequested,pAccepted,pActual,zeros(24,1),pAvailable,"4.3_DEVICE_MODEL","AVAILABLE");
packet.loss.pCollectionLossMW=pLoss;
packet.loss.pSourceAuxLoadMW=pAux;
packet.loss.collectionLossAlreadyDeducted=true;
packet.state.sourceOperatingState=repmat("AGGREGATED",24,1);
packet.state.sourceConstraintCode=repmat("4.3_DEVICE_MODEL",24,1);
packet.state.stateOut=struct('source','existing_public_baseline_v2');
packet.quality.dataSourceType="SYNTHETIC_4.3_BASELINE";
packet.quality.calibrationVersion="UNCALIBRATED";
packet.audit.sourceModelPath=fullfile(base,'model');
packet.audit.resamplingRule='5-min mean to 1-h interval-average power; endpoint excluded';
packet.audit.downstreamOutputsIgnored=true;
validate_module_packet_4_2(packet,'4.3',cfg,true);
end
