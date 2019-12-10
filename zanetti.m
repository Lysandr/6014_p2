%% padraig lysandrou
clc; close all; clear all;

mu =  3.986004415e+05;      p.mu = mu;

% orbital elements of chief		orbital elements of deputy
oe_c.a 		= 6371 + 400;		oe_d.a 		= oe_c.a;
oe_c.e 		= 0;				oe_d.e 		= oe_c.e;
oe_c.inc 	= deg2rad(51.6);	oe_d.inc 	= oe_c.inc;
oe_c.Omega 	= deg2rad(0);		oe_d.Omega 	= oe_c.Omega;
oe_c.omega 	= deg2rad(0);		oe_d.omega 	= oe_c.omega;
oe_c.Mo 	= deg2rad(0);		oe_d.Mo 	= oe_c.Mo - deg2rad(.001);

% Plan out the timing
orbits = 1/5;         T = 2*pi*sqrt((oe_c.a^3)/mu);
T_tot = orbits*T;

% Guidance law timing
T_f_zanetti = T_tot;  p.T_f_zanetti = T_f_zanetti;

% Sim timing
dt = 0.01;
time = linspace(0,T_tot,T_tot/dt);
control_time = time(1:end-1);
npoints = length(time);

% get other parameters
p_out_c = schaub_elements(oe_c, p,0,2,1);
p_out_d = schaub_elements(oe_d, p,0,2,1);
rc = p_out_c.r;         vc = p_out_c.v;
rd = p_out_d.r;         vd = p_out_d.v;

% get the initial hill frame coordinates
HN = Cart2Hill([rc.' vc.']);
H_omega_ON = [0; 0; p_out_c.n];
rho_N = (rd-rc);
rho_Hill = HN*rho_N;
rhod_Hill = HN*(vd-vc) - skew(H_omega_ON)*rho_Hill;


% the things that matter [or otheta oz]
rho_Hill = [-.2 0.01 0].';
rhod_Hill= [0 0 0].';
theta = deg2rad(-90);

% from this, get the transverse and
p.theta = theta;
RH = [sin(theta) -cos(theta) 0; cos(theta) sin(theta) 0; 0 0 1];
rtz = RH*rho_Hill;
rtzd= RH*rhod_Hill;

% find the costate initial condition
n = p_out_c.n;          p.n = n;
A = [0 1 0 0; ...
    3*(n^2)*(sin(theta)^2) 0 0 -1; ...
    -9*(n^4)*(cos(theta)^2)*(sin(theta)^2) 6*(n^3)*cos(theta)*sin(theta) 0 ...
    -3*(n^2)*(sin(theta)^2); ...
    6*(n^3)*sin(theta)*cos(theta) -4*(n^2) -1 0];
p.A = A;
Phi_tf_0 = expm(A*T_f_zanetti);
Phi_rl = Phi_tf_0(1:2,3:4);
Phi_rr = Phi_tf_0(1:2,1:2);
costate_0 = Phi_rl\([0 0].' - Phi_rr*([rtz(1) rtzd(1)].'));

% setup the initial conditions and other bluushuit
X_0 = [rtz; rtzd; costate_0];
state_out = zeros(length(X_0), npoints);
control_hist = zeros(3, npoints-1);
state_out(:,1) = X_0;
f_dot = @(t_in, state_in, p) zanetti_RHS(t_in, state_in, p);

% gains for things
Kp = 5e-4;
Kd = 1e-2;
Kz = 0.003;

% calculate the dt STM
Phi_dt = expm(A*dt);
eig(Phi_dt)

tic
% integration loop
for i = 1:npoints-1
    rtz = state_out(1:3,i);
    rtzd= state_out(4:6,i);
    costate = state_out(7:8,i);
    
    % compute the control
    x_t = [rtz(1) rtzd(1) costate.'].';
    ur_star = [0 0 0 -1]*Phi_dt*x_t ...
        - 2*n*rtzd(2) - 3*(n^2)*sin(theta)*cos(theta)*rtz(2);
    ut_star = 2*n*rtzd(1) - 3*(n^2)*rtz(1)*sin(theta)*cos(theta) ...
        - 3*(n^2)*(cos(theta)^2)*rtz(2) - Kp*rtz(2) - Kd*rtzd(2);
    uz = -Kz*rtzd(3);
    control_hist(:,i) = [ur_star ut_star uz].';
    p.u = control_hist(:,i);
%     p.u = [0 0 0].';
    
    % integrate the dynamics
    k_1 = f_dot(time(i), state_out(:,i),p);
    k_2 = f_dot(time(i)+0.5*dt, state_out(:,i) + 0.5*dt*k_1,p);
    k_3 = f_dot((time(i)+0.5*dt), (state_out(:,i)+0.5*dt*k_2),p);
    k_4 = f_dot((time(i)+dt), (state_out(:,i)+k_3*dt),p);
    state_out(:,i+1) = state_out(:,i) + (1/6)*(k_1+(2*k_2)+(2*k_3)+k_4)*dt;
end
toc


state_plot = zeros(length(X_0), npoints);
input_hill = zeros(3, npoints -1);
for i = 1:npoints
    state_plot(1:3,i) = RH.'*state_out(1:3,i);
    state_plot(4:6,i) = RH.'*state_out(4:6,i);
    input_hill(:,i) = RH.'*control_hist(:,i);
end


%% plotting
close all
width=4; height=4;

figure('Units','inches','Position',[0 0 width height],'PaperPositionMode','auto');
plot(-state_plot(2,:), state_plot(1,:));  hold on;
plot(-state_plot(2,1), state_plot(1,1),'go');
plot(-state_plot(2,end), state_plot(1,end),'ro');
axis equal; grid on;
xlabel('o_\theta alongtrack km');
ylabel('o_r radial km')
legend('traj','IC','FC','location','best')
title('Hill Frame Trajectory of Deputy over time')
set(gca,...
'Units','normalized',...
'FontUnits','points',...    
'FontWeight','normal',...
'FontSize',9,...
'FontName','Times')
print -depsc2 traj.eps

% plot the same thing with quivers
figure('Units','inches','Position',[0 0 width height],'PaperPositionMode','auto');
plot(-state_plot(2,:), state_plot(1,:));  hold on;
plot(-state_plot(2,1), state_plot(1,1),'go');
plot(-state_plot(2,end), state_plot(1,end),'ro');
axis equal; grid on;
xlabel('o_\theta alongtrack km');
ylabel('o_r radial km')
legend('traj','IC','FC','location','best')
title('Hill Frame Trajectory of Deputy over time')
set(gca,...
'Units','normalized',...
'FontUnits','points',...    
'FontWeight','normal',...
'FontSize',9,...
'FontName','Times')
print -depsc2 traj.eps

figure('Units','inches','Position',[0 0 width height],'PaperPositionMode','auto');
plot(time, state_plot(4:6,:)); grid on;
title('Hill frame velocities over time')
xlabel('Time, s')
ylabel('Velocity km/s')
legend('xdot','ydot','zdot','location','best')
set(gca,...
'Units','normalized',...
'FontUnits','points',...    
'FontWeight','normal',...
'FontSize',9,...
'FontName','Times')
print -depsc2 hillvels.eps

figure('Units','inches','Position',[0 0 width height],'PaperPositionMode','auto');
plot(control_time, control_hist); grid on;
title('Control History vs Time')
xlabel('Time, s')
ylabel('Acceleration km/s2')
legend('ur','ut','uz')
set(gca,...
'Units','normalized',...
'FontUnits','points',...    
'FontWeight','normal',...
'FontSize',9,...
'FontName','Times')
print -depsc2 controls.eps

figure('Units','inches','Position',[0 0 width height],'PaperPositionMode','auto');
plot(time, state_out(4,:)); hold on
plot(time, state_out(5,:));
title('RADIAL TRANSVERSAL frame velocity ')
legend('r','t'); hold off; grid on;
set(gca,...
'Units','normalized',...
'FontUnits','points',...    
'FontWeight','normal',...
'FontSize',9,...
'FontName','Times')
print -depsc2 transvels.eps
























