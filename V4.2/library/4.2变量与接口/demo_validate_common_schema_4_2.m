function out = demo_validate_common_schema_4_2()
%DEMO_VALIDATE_COMMON_SCHEMA_4_2 Smoke test for the Chapter 4 schema.

cfgSmoke = common_config_4_2('interface_smoke');
smokeReport = validate_common_schema_4_2(cfgSmoke,true);
assert(smokeReport.ok,'interface_smoke must pass strict schema validation.');

cfgEngineering = common_config_4_2('engineering_base');
engineeringReport = validate_common_schema_4_2(cfgEngineering,false);
assert(~engineeringReport.ok, ...
    'Unsigned engineering_base must fail until P0 values are frozen.');

out = struct('smokeConfig',cfgSmoke,'smokeReport',smokeReport, ...
    'engineeringConfig',cfgEngineering, ...
    'engineeringReport',engineeringReport);

fprintf('COMMON SCHEMA 4.2: INTERFACE_SMOKE PASSED\n');
fprintf('ENGINEERING_BASE: BLOCKED AS EXPECTED (%d unresolved errors)\n', ...
    engineeringReport.errorCount);
end
