% DEMO_FLOATING_WIND_DISPATCH_V2
% Smoke test only. All environmental signals and the synthetic power curve
% below are example values and must not be used in project conclusions.

clear; clc;

dt = 1;
in.t = (0:dt:900)';
n = numel(in.t);

% Two turbines with slightly decorrelated inflow [example only].
in.windSpeed = [12 + 1.2*sin(2*pi*in.t/120), ...
                11.7 + 1.0*sin(2*pi*in.t/135 + 0.6)];
in.windSpeed(in.t >= 250 & in.t < 285, 1) = 26;
in.surgeVelocity = [0.18*sin(2*pi*in.t/22), ...
                    0.15*sin(2*pi*in.t/24 + 0.4)];
in.pitchRate = deg2rad([0.12*sin(2*pi*in.t/28), ...
                       0.10*sin(2*pi*in.t/30 + 0.2)]);
in.platformPitch=deg2rad([1.5*sin(2*pi*in.t/28), ...
                         1.2*sin(2*pi*in.t/30+0.2)]);
in.waveHeight=1.5*ones(n,2);
in.waveHeight(in.t>=400 & in.t<430,:)=6.5;
in.availabilityState = true(n, 2);
in.availabilityState(in.t >= 600 & in.t < 650, 2) = false;
in.derate = ones(n, 2);
in.derate(in.t >= 720, :) = 0.90;

% Public reference scale: 15 MW and 240 m rotor. The curve below is a
% synthetic monotone smoke-test curve, not the IEA/OEM certified curve.
p.ratedPower = 15e6;
p.ratedApparentPower = 16.5e6; % [example value, calibrate]
p.hubHeight = 150;
p.powerCurveWind = [0 3 5 7 9 10.59 24.99 25 60]';
p.powerCurveP = [0 0 0.7 3.2 8.5 15 15 0 0]' * 1e6;
p.cutOutWind = 25;
p.restartWind = 20;            % [example value, calibrate]
p.maxOperatingWave=6.0;        % [example value, calibrate]
p.restartWave=4.0;             % [example value, calibrate]
p.maxOperatingPitch=deg2rad(8); % [example value, calibrate]
p.restartPitch=deg2rad(4);      % [example value, calibrate]
p.restartDelay = 60;           % [example value, calibrate]
p.rampUp = 0.30e6;             % [example value, calibrate]
p.auxiliaryPower = 0.05e6;     % [example value, calibrate]
p.arrayLossFraction = 0.02;    % [example value, calibrate]

out = floating_wind_dispatch_v2(in, p);

assert(all(out.turbinePower(:) >= 0));
assert(all(out.turbinePower(:) <= p.ratedPower + eps));
assert(all(out.farmNetPower <= 2*p.ratedPower + eps));
assert(all(out.qMax(:) >= 0));
assert(all(out.pActualAtPOI>=0) && all(out.pAuxLoad>=0));
assert(max(abs(out.pAvailableAtPOI- ...
    (out.pAvailableGross-out.pAvailableCollectionLoss)))<1e-6);

figure('Color','w');
subplot(3,1,1);
plot(out.t, in.windSpeed, 'LineWidth', 1.0);
ylabel('Wind speed (m/s)'); grid on;
legend('Turbine 1','Turbine 2','Location','best');

subplot(3,1,2);
plot(out.t, out.turbinePower/1e6, 'LineWidth', 1.0);
ylabel('Turbine P (MW)'); grid on;

subplot(3,1,3);
plot(out.t, out.farmNetPower/1e6, 'k', 'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('Farm net P (MW)'); grid on;

fprintf('Smoke test passed. POI generation energy over demo: %.3f MWh\n', ...
    trapz(out.t, out.farmNetPower)/3.6e9);
