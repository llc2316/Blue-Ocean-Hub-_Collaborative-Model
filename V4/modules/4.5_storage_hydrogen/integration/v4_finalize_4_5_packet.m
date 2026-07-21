function packet=v4_finalize_4_5_packet(cfg,timeH,req,provisional,h2WithdrawnKg)
%V4_FINALIZE_4_5_PACKET Commit 4.5 inventory after 4.7 actual withdrawal.
N=numel(timeH); h2WithdrawnKg=double(h2WithdrawnKg(:));
assert(numel(h2WithdrawnKg)==N && all(h2WithdrawnKg>=0));
assert(isfield(provisional,'h2InventoryKg') && isfield(provisional,'h2AvailableForDeliveryKg'));
packet=common_packet_4_2('4.5',timeH,cfg,'RESPONSE');
packet.ports.bessCharge=v4_fill_port(timeH,cfg.meter.commonBus,req.bessChargeMW, ...
    provisional.pChargeMW,provisional.pChargeMW,0,cfg.bess.chargeMaxMW,"4.5_SOC","AVAILABLE");
packet.ports.bessDischarge=v4_fill_port(timeH,cfg.meter.commonBus,req.bessDischargeMW, ...
    provisional.pDischargeMW,provisional.pDischargeMW,0,cfg.bess.dischargeMaxMW,"4.5_SOC","AVAILABLE");
packet.ports.electrolyzer=v4_fill_port(timeH,cfg.meter.electrolyzer,req.electrolyzerMW, ...
    provisional.pElectrolyzerMW,provisional.pElectrolyzerMW,0,cfg.hydrogen.electrolyzerRatedMW,"4.5_SEC_TANK","AVAILABLE");
packet.state.bessSOC=provisional.bessSOC;
packet.state.bessEnergyMWh=provisional.bessEnergyMWh;
packet.state.h2InventoryKg=provisional.h2InventoryKg;
packet.state.electrolyzerOn=provisional.pElectrolyzerMW>0;
packet.product.h2ProductionKg=provisional.h2ProductionKg;
packet.product.h2AvailableForDeliveryKg=provisional.h2AvailableForDeliveryKg;
packet.audit.h2DeliverySequence='4.5_AVAILABLE_THEN_4.7_ACTUAL_THEN_4.5_COMMIT';
packet.audit.modelOrigin='4.5 existing SOC, SEC and inventory equations; interface-only refactor';
validate_module_packet_4_2(packet,'4.5',cfg,true);
end
