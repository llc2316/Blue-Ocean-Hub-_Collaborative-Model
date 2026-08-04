function out=demo_public_resource_audit_4_3(dataRoot,doPlot)
%DEMO_PUBLIC_RESOURCE_AUDIT_4_3 Inspect optional public proxy resources.
if nargin<1, dataRoot=[]; end
if nargin<2, doPlot=true; end
moduleRoot=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot,'integration'));
out=load_public_reference_resource_4_3(dataRoot);
T=out.resource;
fprintf('\n4.3 PUBLIC RESOURCE AUDIT\n');
fprintf('Rows: %d; UTC: %s to %s\n',height(T),char(T.timestampUTC(1)), ...
    char(T.timestampUTC(end)));
fprintf('WS50M mean/min/max: %.3f / %.3f / %.3f m/s\n', ...
    mean(T.windSpeed50mMS),min(T.windSpeed50mMS),max(T.windSpeed50mMS));
fprintf('Shortwave mean/max: %.3f / %.3f Wh/m2 per hourly interval\n', ...
    mean(T.shortwaveDownwardWhM2),max(T.shortwaveDownwardWhM2));
fprintf('Wave height mean/min/max: %.3f / %.3f / %.3f m\n', ...
    mean(T.waveHeightM),min(T.waveHeightM),max(T.waveHeightM));
fprintf('Tidal current: MISSING; no synthetic replacement was generated.\n');
fprintf('Status: PUBLIC PROXY, NOT PROJECT MEASUREMENT OR POWER OUTPUT.\n\n');
if doPlot
    figure('Color','w','Name','4.3公开代理资源审计');
    tiledlayout(3,1,'TileSpacing','compact');
    nexttile; plot(T.timestampUTC,T.windSpeed50mMS,'LineWidth',1.0);
    ylabel('WS50M (m/s)'); grid on;
    nexttile; plot(T.timestampUTC,T.shortwaveDownwardWhM2,'LineWidth',1.0);
    ylabel('Wh/m^2'); grid on;
    nexttile; plot(T.timestampUTC,T.waveHeightM,'LineWidth',1.0);
    ylabel('H_s (m)'); xlabel('UTC'); grid on;
end
end
