% DEMO_FLOATING_PV_DISPATCH_V2
% Smoke test only. Every environmental and equipment value below is an
% example and must not be used in project conclusions.

clear; clc;

dt = 60;
in.t = (0:dt:24*3600)';
hour = in.t / 3600;
n = numel(in.t);

daylight = hour >= 6 & hour <= 18;
elevation = -0.10 * ones(n,1);
elevation(daylight) = (pi/2) * sin(pi*(hour(daylight)-6)/12);
azimuth = pi/2 + pi*(hour-6)/12; % clockwise from north [example]
in.sunVector = [cos(elevation).*sin(azimuth), ...
                cos(elevation).*cos(azimuth), sin(elevation)];

in.dni = zeros(n,1);
in.dni(daylight) = 800 .* sin(pi*(hour(daylight)-6)/12);
in.dhi = zeros(n,1);
in.dhi(daylight) = 120;
in.ghi = max(0, in.dni .* max(0,in.sunVector(:,3)) + in.dhi);
in.ambientTemp = 18 + 6*sin(2*pi*(hour-8)/24);
in.windSpeed = 6 + 1.5*sin(2*pi*hour/8);

% Two independently tracked MPPT subarrays with wave-driven motion.
in.roll = [deg2rad(1.2)*sin(2*pi*in.t/9), ...
           deg2rad(1.0)*sin(2*pi*in.t/10 + 0.5)];
in.pitch = [deg2rad(1.5)*sin(2*pi*in.t/11), ...
            deg2rad(1.3)*sin(2*pi*in.t/12 + 0.4)];
in.yaw = zeros(n,2);
in.waveHeight = 1.2*ones(n,2);
in.waveHeight(hour >= 14 & hour < 15,:) = 4.5;
in.availabilityState = true(n,2);
in.soilingFactor = ones(n,2);       % [example]
in.degradationFactor = ones(n,2);   % [example]
in.mismatchFactor = ones(n,2);      % independent MPPT assumption

tilt = deg2rad(10);
normalSouth = [0, -sin(tilt), cos(tilt)];
p.baseNormal = [normalSouth; normalSouth];
p.pdcRated = [0.60e6; 0.60e6];      % [example]
p.pacRated = 1.0e6;                 % [example]
p.apparentPowerRated = 1.1e6;       % [example]
p.gstc = 1000;
p.tstc = 25;
p.gammaP = -0.0035;                 % [example, use module datasheet]
p.U0 = 25; p.U1 = 6.84;             % [example, calibrate for structure]
p.albedo = 0.06;                    % [example, calibrate]
p.bifaciality = 0;                  % monofacial demo
p.iamB0 = 0.05;                     % [example, use IEC 61853-2/OEM data]
p.invLoadFraction = [0 0.05 0.10 0.20 0.50 1.00 1.30]';
p.invEfficiency = [0 0.90 0.95 0.97 0.985 0.985 0.98]'; % [example]
p.auxiliaryPower = 2e3;             % [example]
p.cableLossFraction = 0.015;        % [example]
p.maxOperatingWind = 30;            % [example, platform-specific]
p.maxOperatingWave = 4.0;           % [example, platform-specific]
p.restartWind = 20;                 % [example]
p.restartWave = 2.5;                % [example]
p.restartDelay = 30*60;             % [example]
p.rampUp = 0.10e6;                  % [example]

out = floating_pv_dispatch_v2(in, p);

assert(all(out.pac >= 0));
assert(all(out.pac <= p.pacRated + eps));
assert(all(out.gEffective(:) >= 0));
assert(all(out.qMax >= 0));
assert(all(out.pActualAtPOI>=0) && all(out.pAuxLoad>=0));
assert(max(abs(out.pAvailableAtPOI- ...
    (out.pAvailableGross-out.pAvailableCollectionLoss)))<1e-6);

figure('Color','w');
subplot(3,1,1);
plot(hour, in.ghi, 'k', hour, out.gEffective, '--');
ylabel('Irradiance (W/m^2)'); grid on;
legend('GHI','Subarray 1 POA','Subarray 2 POA','Location','best');

subplot(3,1,2);
plot(hour, out.moduleTemperature, 'LineWidth', 1.0);
ylabel('Module temp. (degC)'); grid on;

subplot(3,1,3);
plot(hour, out.pac/1e6, 'b', 'LineWidth', 1.2);
xlabel('Hour'); ylabel('AC power (MW)'); grid on;

fprintf('Smoke test passed. Demo POI generation energy: %.3f MWh\n', ...
    trapz(out.t, out.pac)/3.6e9);
