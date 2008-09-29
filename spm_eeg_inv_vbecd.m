function P = spm_eeg_inv_vbecd(P)
% Model inversion routine for ECDs using "variational Bayes"
%
% FORMAT P = spm_eeg_inv_vbecd(P)
%
% Input:
% structure P with fields:
%  forward      - structure containing the forward model, i.e. the "vol"
%                 and "sens" structure in a FT compatible format
%  bad          - list of bad channels, not to use.
%  y            - data vector
%  Nc           -
%  Niter        - maximum number of iterations
%  threshold_dF - threshold on free energy improvement to stop iterating
%  priors       - priors on parameters, hard and soft, as filled in (and 
%                 described) in spm_eeg_inv_vbecd_gui.m.
%
% Output:
% same structure with extra fields
%  init         - initial valuse used for mu_w/s
%  ok           - flags indicating if everything was ok
%  dF           - successive (relative) improvement of F
%  post         - posterior value of estimated parameters and ther variance
%  Fi           - successive values of F
%  F            - Free energy final value.
% 
% Reference:
% Kiebel et al., Variational Bayesian inversion of the equivalent current
% dipole model in EEG/MEG., NeuroImage, 39:728-741, 2008
%__________________________________________________________________________
% Copyright (C) 2008 Wellcome Trust Centre for Neuroimaging

% Christophe Phillips & Stefan Kiebel
% $Id: spm_eeg_inv_vbecd.m 2232 2008-09-29 15:22:00Z christophe $

% unpack model, priors, data
vol = P.forward.vol;
sens = P.forward.sens;

a10 = P.priors.a10; b10 = P.priors.b10;
a20 = P.priors.a20; b20 = P.priors.b20;
a30 = P.priors.a30; b30 = P.priors.b30;

mu_w0 = P.priors.mu_w0;
mu_s0 = P.priors.mu_s0;
iS_w0 = P.priors.iS_w0;
iS_s0 = P.priors.iS_s0;

try
    Tw = P.priors.Tw;
catch
    Tw = eye(length(mu_w0));
end

try
    Ts = P.priors.Ts;
catch
    Ts = eye(length(mu_s0));
end

Vw = full(spm_svd(Tw));
Vs = full(spm_svd(Ts));

y = P.y;
y(P.Bad) = [];

dv = 10^-2; % used to compute step-size for gradients
%---------------
% initialization
%---------------

% use some random initialization for parameters, 
% but ensure the starting points are inside the volume !!!
Nd = length(mu_s0)/3;
inside = zeros(Nd,1);
mu_sn = zeros(3,Nd);
while ~all(inside)
    mu_sn(:,~inside) = 30*randn(3,length(find(~inside)));
    [inside] = forwinv_inside_vol(mu_sn',vol);
end
mu_s = mu_sn(:);

[gmn, gm, dgm] = spm_eeg_inv_vbecd_getLF(mu_s, sens, vol, ...
                                    dv.*ones(1, length(mu_w0)), P.Bad);
% Initialize mu_w with best estimate given random locations rather than at
% random
% mu_w = randn(size(mu_w0,1), 1);
mu_w = pinv(gmn)*y; 

P.init.mu_s = mu_s;
P.init.mu_w = mu_w;

[Nc, Np] = size(gmn);

res = y - gmn*mu_w;
a1 = Nc/2;
b1 = var(res).*a1;

a2 = Np/2;
b2 = (mu_w-mu_w0)'*(mu_w-mu_w0)./2;

a3 = Np/2;
b3 = (mu_s-mu_s0)'*(mu_s-mu_s0)./2;

S_w = b2/a2*pinv(iS_w0);
S_s = b3/a3*pinv(iS_s0);

%---------------
% iterate update rules
%---------------

% mu_w_old = mu_w;
% mu_s_old = mu_s;

% these don't change
a1 = Nc/2 + a10;
a2 = size(Vw,2)/2 + a20;
a3 = size(Vs,2)/2 + a30;

% fprintf('Iterations:\n')
P.ok = 1;

for i = 1:P.Niter

    % orientation parameters w
    SD = zeros(Np, Np);
    Dm = dgm*S_s*dgm';
    for j = 1:Nc
        ind = j + [0:Np-1]*Nc;
        d = Dm(ind, ind);
        SD = SD + d;
    end

    S_w = Tw*inv(a2/b2*iS_w0 + a1/b1*(gmn'*gmn + SD))*Tw';
    mu_w = Tw*S_w*(a1/b1*gmn'*y + a2/b2*iS_w0*mu_w0);

    % precision on y
    DE = kron(S_w+mu_w*mu_w', eye(Nc));
    b1 = 0.5*(y'*y...
        - 2*mu_w'*gmn'*y...
        + gm'*DE*gm...
        + trace(S_s*dgm'*DE*dgm))...
        + b10;

    % precision on w
    b2 = 0.5*((Vw'*(mu_w-mu_w0))'*Vw'*iS_w0*Vw*(Vw'*(mu_w-mu_w0)) + ...
                trace(Vw'*iS_w0*S_w*Vw)) + b20;

    % precision on s
    b3 = 0.5*((Vs'*(mu_s-mu_s0))'*Vs'*iS_s0*Vs*(Vs'*(mu_s-mu_s0)) + ...
                trace(Vs'*iS_s0*Vs*Vs'*S_s*Vs)) + b30;

    % location parameters s
    old_mu_s = mu_s;
    S_s = Ts*inv(a3/b3*iS_s0 + a1/b1*(dgm'*DE*dgm))*Ts';
    mu_s = Ts*S_s*(a1/b1*(dgm'*(kron(mu_w, y)+ DE*(dgm*mu_s - gm))) + ...
                a3/b3*iS_s0*mu_s0);

    % update leadfield and its partials
    [gmn, gm, dgm] = spm_eeg_inv_vbecd_getLF(mu_s, sens, vol, ...
                dv.*sqrt(diag(S_s)), P.Bad);
    
    mu_sn = reshape(mu_s, 3, Np/3);
    old_mu_sn = reshape(old_mu_s, 3, Np/3);
    % list of sources outside the brain volume
    outside = ~forwinv_inside_vol(mu_sn',vol);
   
    if i == 1
        F(i) = -Nc/2*log(2*pi) + Nc/2*(psi(a1) - log(b1))...
            -a1/(2*b1)*(y'*y - 2*mu_w'*gmn'*y + gm'*DE*gm + trace(S_s*dgm'*DE*dgm))...
            -spm_kl_normal(Vw'*mu_w, Vw'*S_w*Vw, Vw'*mu_w0, Vw'*b2/a2*inv(iS_w0)*Vw)...
            -spm_kl_normal(Vs'*mu_s, Vs'*S_s*Vs, Vs'*mu_s0, Vs'*b3/a3*inv(iS_s0)*Vs)...
            -spm_kl_gamma(1/b1,a1,1/b10,a10)...
            -spm_kl_gamma(1/b2,a2,1/b20,a20)...
            -spm_kl_gamma(1/b3,a3,1/b30,a30);

        % make sure that first update of mu_s doesn't jump outside sphere
        q_out = ~all(~outside);
        while q_out
            mu_sn(:, outside) = mu_sn(:, outside)/2;
            outside = ~forwinv_inside_vol(mu_sn',vol);

            q_out = ~all(~outside);
        end
        mu_s = mu_sn(:);
        % update leadfield and its partials
        [gmn, gm, dgm] = spm_eeg_inv_vbecd_getLF(mu_s, sens, vol, ...
                                            dv.*sqrt(diag(S_s)), P.Bad);
    else
        for j = 1:16
            % compute neg free energy
            mu_s = mu_sn(:);
            F(i) = -Nc/2*log(2*pi) + Nc/2*(psi(a1) - log(b1))...
                -a1/(2*b1)*(y'*y - 2*mu_w'*gmn'*y + gm'*DE*gm + trace(S_s*dgm'*DE*dgm))...
                -spm_kl_normal(Vw'*mu_w, Vw'*S_w*Vw, Vw'*mu_w0, Vw'*b2/a2*inv(iS_w0)*Vw)...
                -spm_kl_normal(Vs'*mu_s, Vs'*S_s*Vs, Vs'*mu_s0, Vs'*b3/a3*inv(iS_s0)*Vs)...
                -spm_kl_gamma(1/b1,a1,1/b10,a10)...
                -spm_kl_gamma(1/b2,a2,1/b20,a20)...
                -spm_kl_gamma(1/b3,a3,1/b30,a30);
            % check dF
            if ~all(~outside)
                % decrease change in violating dipoles only
                mu_sn(:, outside) = (old_mu_sn(:, outside) + mu_sn(:, outside))/2;
                mu_s = mu_sn(:);
                % update leadfield and its partials
                [gmn, gm, dgm] = spm_eeg_inv_vbecd_getLF(mu_s, sens, vol, ...
                                            dv.*sqrt(diag(S_s)), P.Bad);
            else
                if F(i) < F(i-1)
                    mu_sn = (old_mu_sn + mu_sn)/2;
                    mu_s = mu_sn(:);
                    % update leadfield and its partials
                    [gmn, gm, dgm] = spm_eeg_inv_vbecd_getLF(mu_s, sens, vol, ...
                                                dv.*sqrt(diag(S_s)), P.Bad);
                    mu_sn = reshape(mu_s, 3, Np/3);

                else
                    break;
                end
            end
            outside = ~forwinv_inside_vol(mu_sn',vol);
            if j == 16
                % this seeems to be a bad case, let's start over
                fprintf('bang\n')
                post.mu_w = mu_w;
                post.mu_s = mu_s;
                post.S_w = S_w;
                post.S_s = S_s;
                post.a1 = a1; post.b1 = b1;
                post.a2 = a2; post.b2 = b2;
                post.a3 = a3; post.b3 = b3;

                P.post = post;

                P.Fi = F;
                P.F = F(end);
                P.ok = 0;
                return;
            end
        end
    end

    if i == 1
        dF = 0;
    else
        dF = (F(i)-F(i-1))/abs(F(i));
        if (F(i-1)-F(i))/abs(F(i)) > P.threshold_dF
            a=Ftest';
            a = a(:);
            ad=diff(a);
            f=reshape([0;ad]', size(Ftest'))';
            disp('Evidence Violation');
            
            P.ok = 0;
            break;
        elseif abs((F(i)-F(i-1))/F(i)) < P.threshold_dF
            P.dF(i) = dF;
            str = sprintf('%3d/%d, F: %f\t dFr: %f', i, P.Niter, F(i), dF);
            fprintf('%s\n', str)
            break;
        end
    end
    P.dF(i) = dF;
%     mu_w_old = mu_w;
%     mu_s_old = mu_s;
    str = sprintf('%3d/%d, F: %f\t dFr: %f', i, P.Niter, F(i), dF);
    fprintf('%s\n', str)
end

% save results 
post.mu_w = mu_w;
post.mu_s = mu_s;
post.S_w = S_w;
post.S_s = S_s;
post.a1 = a1; post.b1 = b1;
post.a2 = a2; post.b2 = b2;
post.a3 = a3; post.b3 = b3;
post.gmn = gmn; % lead field

P.post = post;
P.Fi = F;
P.F = F(end);
