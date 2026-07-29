function params=v4_gfm_parameters_4_5(cfg)
%V4_GFM_PARAMETERS_4_5 Mechanism-test REGFM_B1 parameter set.
%
% WECC/NREL example values are used where explicitly available. H=3 s,
% proportional voltage gain and project equipment limits remain
% [assumption values, pending PCS vendor calibration]. This parameter set
% is not an OEM guarantee or a procurement specification.

params=struct;
params.ratedMVA=cfg.bess.powerMW;
params.ratedMW=cfg.bess.powerMW;
params.energyMWh=cfg.bess.energyMWh;
params.energyInitialMWh=cfg.bess.socInitial*cfg.bess.energyMWh;
params.energyMinMWh=cfg.bess.socMin*cfg.bess.energyMWh;
params.energyMaxMWh=cfg.bess.socMax*cfg.bess.energyMWh;
params.etaCharge=cfg.bess.etaCharge;
params.etaDischarge=cfg.bess.etaDischarge;
params.nominalFrequencyHz=50;
params.mp=0.02;
params.mq=0.05;
params.H=3.0;
params.D1=0;
params.D2=100;
params.omegaD=50;
params.TpS=0.02;
params.TPfS=0.02;
params.TQfS=0.02;
params.TVfS=0.02;
params.kpv=0.5;
params.kiv=5;
params.EminPU=0;
params.EmaxPU=1.2;
params.currentMaxFPU=1.5;
params.filterResistancePU=0.01;
params.filterReactancePU=0.10;
params.omegaMinPU=-0.10;
params.omegaMaxPU=0.10;
params.audit=struct( ...
    'exampleSourceType','official NREL/WECC REGFM_B1 technical report', ...
    'HStatus','[assumption, mechanism-test target; verify effective inertia by test]', ...
    'kpvStatus','[assumption, pending PCS vendor calibration]', ...
    'limitStatus','[assumption, pending PCS short-time current curve]', ...
    'filterStatus','[assumption, reduced-order interface impedance; calibrate against transformer and PCS]', ...
    'frequencyLimitStatus','[assumption, numerical safety boundary; not a protection setting]', ...
    'blackStartSOCThresholdStatus','[assumption, pending auxiliary-load and OEM study]');
end
