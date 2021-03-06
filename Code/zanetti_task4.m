%% padraig lysandrou
clc; close all; clear all;
mu =  3.986004415e+05;      p.mu = mu;

%% dp the shit
% orbital elements of chief		orbital elements of deputy
oe_c.a 		= 6371 + 400;		oe_d.a 		= oe_c.a - 0.2;
oe_c.e 		= 0;				oe_d.e 		= oe_c.e;
oe_c.inc 	= deg2rad(51.6);	oe_d.inc 	= oe_c.inc;
oe_c.Omega 	= deg2rad(0);		oe_d.Omega 	= oe_c.Omega;
oe_c.omega 	= deg2rad(0);		oe_d.omega 	= oe_c.omega;
oe_c.Mo 	= deg2rad(0);		oe_d.Mo 	= oe_c.Mo + deg2rad(.0001);



sequence = 1:0.5:80;

pos_inacc = zeros(length(sequence),1);
vel_inacc = zeros(length(sequence),1);
pcounter = 0;

for k = sequence
    % Plan out the timing
    pcounter = pcounter + 1;
    orbits = 1/5;         T = 2*pi*sqrt((oe_c.a^3)/mu);
    T_tot = k*50;

    % Guidance law timing
    T_f_zanetti = T_tot;  p.T_f_zanetti = T_f_zanetti;

    % Sim timing
    dt = T_tot/20000;
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

    % the things that matter [o_r o_theta o_z]
    % rho_Hill = [-.2 0.01 0].';
    % rhod_Hill= [0 0 0].';
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
    zanetti_init = [rtz(1); rtzd(1); costate_0];

    % setup the initial conditions and other bluushuit
    X_0 = [rtz; rtzd; costate_0];
    state_out = zeros(length(X_0), npoints);
    control_hist_H = zeros(3, npoints-1);
    state_out(:,1) = X_0;

    % gains for things
    Kp = 0.0005;
    Kd = 0.05;
    Kz = 0.003;

    % calculate the dt STM
    Phi_dt = expm(A*dt);

    %%
    f_dot = @(t_in, state_in, p) two_body(t_in, state_in, p);

    init_conds = [rc; rd; vc; vd];
    state_cart = zeros(12, npoints);
    state_cart(:,1) = init_conds;
    rdd_hist = zeros(3, npoints-1);
    rho_H_hist= zeros(3, npoints-1);
    u_d_hist = zeros(3,npoints-1);
    rho_H = zeros(3, npoints);
    rhod_H = rho_H;
    control_hist = zeros(3, npoints-1);
    control_hist_N = control_hist;

    % gains for things
    Kp = 0.0005;
    Kd = 0.05;
    Kz = 0.003;
    zstate = zanetti_init;

    tic
    % integration loop
    for i = 1:npoints-1
        rc = state_cart(1:3,i);
        rd = state_cart(4:6,i);
        vc = state_cart(7:9,i);
        vd = state_cart(10:12,i);

        % compute the control
        HN = Cart2Hill([rc.' rd.']);
        rho_H(:,i) = HN*(rd - rc);
        rhod_H(:,i) = HN*(vd-vc) - skew(H_omega_ON)*rho_H(:,i);
        rtz  = RH*rho_H(:,i);
        rtzd = RH*rhod_H(:,i);
        % Phi_t_0 = expm(A*time(i));
        % keep track of the costate
        ur_star = [0 0 0 -1]*zstate ...
            - 2*n*rtzd(2) - 3*(n^2)*sin(theta)*cos(theta)*rtz(2);
        ut_star = 2*n*rtzd(1) - 3*(n^2)*rtz(1)*sin(theta)*cos(theta) ...
            - 3*(n^2)*(cos(theta)^2)*rtz(2) - Kp*rtz(2) - Kd*rtzd(2);
        uz = -Kz*rtzd(3);
        control_hist(:,i) = [ur_star ut_star uz].';
        p.u_d = (HN.')*(RH.')*control_hist(:,i);
        control_hist_N(:,i) = p.u_d;

        zstate = Phi_dt*zstate;
        %zstate = Phi_t_0*zanetti_init;
        % integrate the dynamics
        k_1 = f_dot(time(i), state_cart(:,i),p);
        k_2 = f_dot(time(i)+0.5*dt, state_cart(:,i) + 0.5*dt*k_1,p);
        k_3 = f_dot((time(i)+0.5*dt), (state_cart(:,i)+0.5*dt*k_2),p);
        k_4 = f_dot((time(i)+dt), (state_cart(:,i)+k_3*dt),p);
        state_cart(:,i+1) = state_cart(:,i) + (1/6)*(k_1+(2*k_2)+(2*k_3)+k_4)*dt;
    end
    toc

    % final value for sht
    rc = state_cart(1:3,i+1);
    rd = state_cart(4:6,i+1);
    vc = state_cart(7:9,i+1);
    vd = state_cart(10:12,i+1);
    HN = Cart2Hill([rc.' rd.']);
    rho_H(:,i+1) = HN*(rd - rc);
    rhod_H(:,i+1) = HN*(vd-vc) - skew(H_omega_ON)*rho_H(:,i);


    pos_inacc(pcounter) = norm(rho_H(:,end));
    vel_inacc(pcounter) = norm(rhod_H(:,end));

end


%% plotskies
figure('Units','inches','Position',[0 0 6 3],'PaperPositionMode','auto');
semilogy(sequence*50, pos_inacc.*1000); hold on;
semilogy(sequence*50, vel_inacc.*1000);
legend('position m','velocity m/s', 'location','best')
title('Error in Terminal State vs Final Time')
xlabel('Final time, seconds');
ylabel('Error (m, m/s)');
set(gca,...
'Units','normalized',...
'FontUnits','points',...    
'FontWeight','normal',...
'FontSize',9,...
'FontName','Times')
print -depsc2 finaltime.eps


figure('Units','inches','Position',[0 0 6 6],'PaperPositionMode','auto');
plot(-rho_H(2,:),   rho_H(1,:));  hold on;
plot(-rho_H(2,1),   rho_H(1,1),'go');
plot(-rho_H(2,end), rho_H(1,end),'ro');
plot(0,0,'ko');
axis equal; grid on;
xlabel('o_\theta alongtrack km');
ylabel('o_r radial km')
legend('traj','IC','FC','target','location','best')
title('Hill Frame Trajectory of Deputy over time')


























