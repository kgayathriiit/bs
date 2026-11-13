% export_profiles.m
% Exports the SPEL microgrid load and PV profiles (and the BESS / DG ratings)
% for the "Blackout!" web page.
%
% How to use:
%   1. Open your Simulink model and run "Variable Initialization" as usual,
%      so the profiles are in the MATLAB workspace.
%   2. Run this script in the same MATLAB session.
%   3. It writes profiles.js in the current folder. Put profiles.js next to
%      index.html (same folder on your computer and on GitHub). The page then
%      uses your profiles instead of the sample ones.
%   4. Read the summary it prints. Any line marked DEFAULT means that value
%      was not found in your workspace; type the right variable name below.

%% ---- 1. Names of your workspace variables (change here if needed) ----
TIME_VAR  = 'time';                                                     % time vector used in [time cri_load1]
LOAD_VARS = {'cri_load1','cri_load2','varload3','varload4','varload5'}; % Load 1..5
LOAD_NAME = {'Hospital','Homes','School','Water works','Factory'};      % names shown on the page
PV_VAR    = '';   % '' = search common names; or type your PV power profile variable, e.g. 'Ppv_profile'

% Ratings: the first name found in the workspace is used, otherwise the default.
RATINGS = {
  % field        candidate variable names                                   default   unit hint
  'bessKW',      {'Pbmax','Pb_max','P_bess_max','Pbess_max'},                400e3,    'W or kW'
  'bessKWh',     {'E_bess','Ebess','BESS_capacity','E_batt','Ebat'},         1000e3,   'Wh or kWh'
  'soc0',        {'SOC0','SOC_init','SOC_initial','SOCini','soc0'},          60,       '%'
  'socMin',      {'SOC_min','SOCmin'},                                       20,       '%'
  'dgKW',        {'Pdg_max','P_dg_max','Pdgmax','PDGmax','DG_rating'},       500e3,    'W or kW'
  'dgLperKWh',   {'fuel_eff_DGR'},                                           0.25,     'litre per kWh'
};

%% ---- 2. Read the time vector and work out its unit ----
t = evalin('base', TIME_VAR); t = double(t(:));
if max(t) <= 24.5, tq = (0:0.25:24)'; unitT = 'hours';          % time in hours
else,              tq = (0:900:86400)'; unitT = 'seconds'; end   % time in seconds
fprintf('\nTime vector "%s": %d points, in %s (%.0f to %.0f)\n', TIME_VAR, numel(t), unitT, min(t), max(t));

%% ---- 3. Loads, sampled every 15 minutes, in kW ----
D = struct();
D.source  = 'matlab';
D.exported = datestr(now, 'yyyy-mm-dd HH:MM');
D.stepMin = 15;
fprintf('\n%-12s %-12s %10s %10s\n', 'Page name', 'Variable', 'min kW', 'max kW');
for k = 1:5
    v = getProfile(LOAD_VARS{k}, t);
    v = toKW(interp1(v(:,1), v(:,2), tq, 'linear', 'extrap'));
    D.loads.(sprintf('L%d', k)) = round(max(v, 0)', 1);
    fprintf('%-12s %-12s %10.1f %10.1f\n', LOAD_NAME{k}, LOAD_VARS{k}, min(v), max(v));
end

%% ---- 4. PV profile, in kW ----
if isempty(PV_VAR)
    cands = {'Ppv','P_pv','Ppv_profile','pv_profile','PV_profile','PVpower','P_PV','pvPower','Pv'};
    for c = cands
        if evalin('base', sprintf('exist(''%s'',''var'')', c{1})) && isnumeric(evalin('base', c{1})) ...
                && numel(evalin('base', c{1})) > 10
            PV_VAR = c{1}; break
        end
    end
end
if isempty(PV_VAR)
    error(['No PV power profile found. Set PV_VAR at the top of this script to the name of ', ...
           'your PV power profile variable (the one feeding the "Irradiance Profiles" block).']);
end
v = getProfile(PV_VAR, t);
v = toKW(interp1(v(:,1), v(:,2), tq, 'linear', 'extrap'));
D.pv = round(max(v, 0)', 1);
fprintf('%-12s %-12s %10.1f %10.1f\n', 'Solar', PV_VAR, min(v), max(v));

%% ---- 5. Ratings ----
fprintf('\nRatings used:\n');
for r = 1:size(RATINGS, 1)
    field = RATINGS{r,1}; names = RATINGS{r,2}; val = RATINGS{r,3}; from = 'DEFAULT';
    for n = names
        if evalin('base', sprintf('exist(''%s'',''var'')', n{1}))
            x = evalin('base', n{1});
            if isnumeric(x) && isscalar(x), val = double(x); from = n{1}; break, end
        end
    end
    if any(strcmp(field, {'bessKW','dgKW','bessKWh'})), val = toKW(val); end
    D.ratings.(field) = val;
    fprintf('  %-10s = %10.2f   (%s, %s)\n', field, val, from, RATINGS{r,4});
end
D.ratings.chargeKW  = D.ratings.bessKW;   % charging limit = discharging limit, as in run_restoration_opt.m
D.ratings.dgIdleLph = 5;                  % diesel at idle, litre per hour (change if you have a value)

%% ---- 6. Write profiles.js ----
fid = fopen('profiles.js', 'w');
fprintf(fid, '// Exported from MATLAB by export_profiles.m on %s\n', D.exported);
fprintf(fid, 'window.MICROGRID_DATA = %s;\n', jsonencode(D));
fclose(fid);
fprintf('\nWrote %s\nPut it next to index.html.\n\n', fullfile(pwd, 'profiles.js'));

%% ---- helpers ----
function v = getProfile(name, t)
    % Returns [time value] for a workspace variable that is either a vector
    % the same length as t, or a two-column [time value] matrix.
    x = double(evalin('base', name));
    if size(x, 2) == 2 && size(x, 1) > 2
        v = x;
    elseif numel(x) == numel(t)
        v = [t, x(:)];
    else
        error('Variable "%s" has %d values but the time vector has %d. Check the names at the top.', ...
              name, numel(x), numel(t));
    end
end

function y = toKW(x)
    % Values above 5000 are taken as watts (or Wh) and converted to kW (kWh).
    if max(abs(x(:))) > 5000, y = x / 1000; else, y = x; end
end
