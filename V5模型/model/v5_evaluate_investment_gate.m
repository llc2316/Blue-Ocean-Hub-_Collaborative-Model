function gate = v5_evaluate_investment_gate(cfg,finance)
%V5_EVALUATE_INVESTMENT_GATE Separate project-investment decision gate.
%
% Hourly dispatch cannot establish project IRR, DSCR or payback. Pass a
% signed life-cycle cash-flow structure after investment estimates are
% available:
%   finance.capexCNY
%   finance.annualNetCashflowCNY   (year 0 must include negative CAPEX)
%   finance.annualDebtServiceCNY   (optional, years 1..end)

thresholdNames={ ...
    'investmentBudgetCNY', ...
    'minimumProjectIRR', ...
    'minimumDSCR', ...
    'maximumPaybackYear'};
unsigned=thresholdNames(cellfun(@(name) ...
    ~isfinite(cfg.economic.(name)),thresholdNames));

gate=struct( ...
    'status','NOT_EVALUATED', ...
    'pass',false, ...
    'reason','No signed life-cycle finance input was supplied.', ...
    'unsignedThresholds',{unsigned}, ...
    'projectIRR',NaN, ...
    'minimumDSCR',NaN, ...
    'simplePaybackYear',NaN, ...
    'budgetPass',false, ...
    'irrPass',false, ...
    'dscrPass',false, ...
    'paybackPass',false);
if nargin<2 || isempty(finance)
    return
end
if ~isempty(unsigned)
    gate.status='NOT_EVALUATED_UNSIGNED_THRESHOLDS';
    gate.reason=['Enterprise investment thresholds are unsigned: ' ...
        strjoin(unsigned,', ')];
    return
end

assert(isfield(finance,'capexCNY') && isfinite(finance.capexCNY) && ...
    finance.capexCNY>=0,'finance.capexCNY must be finite and nonnegative.');
assert(isfield(finance,'annualNetCashflowCNY'), ...
    'finance.annualNetCashflowCNY is required.');
cash=double(finance.annualNetCashflowCNY(:));
assert(numel(cash)>=2 && all(isfinite(cash)), ...
    'annualNetCashflowCNY must contain finite year-0 and operating values.');

gate.projectIRR=calculate_irr(cash);
gate.simplePaybackYear=calculate_simple_payback(cash);
if isfield(finance,'annualDebtServiceCNY') && ...
        ~isempty(finance.annualDebtServiceCNY)
    debt=double(finance.annualDebtServiceCNY(:));
    operatingCash=cash(2:end);
    if numel(debt)==numel(cash)
        debt=debt(2:end);
    end
    assert(numel(debt)==numel(operatingCash) && ...
        all(isfinite(debt)) && all(debt>=0), ...
        'annualDebtServiceCNY must align with operating years.');
    positiveDebt=debt>0;
    if any(positiveDebt)
        gate.minimumDSCR=min(operatingCash(positiveDebt)./ ...
            debt(positiveDebt));
    else
        gate.minimumDSCR=Inf;
    end
end

gate.budgetPass=finance.capexCNY<=cfg.economic.investmentBudgetCNY;
gate.irrPass=isfinite(gate.projectIRR) && ...
    gate.projectIRR>=cfg.economic.minimumProjectIRR;
gate.dscrPass=isfinite(gate.minimumDSCR) && ...
    gate.minimumDSCR>=cfg.economic.minimumDSCR;
gate.paybackPass=isfinite(gate.simplePaybackYear) && ...
    gate.simplePaybackYear<=cfg.economic.maximumPaybackYear;
gate.pass=gate.budgetPass && gate.irrPass && ...
    gate.dscrPass && gate.paybackPass;
gate.status=ternary(gate.pass,'PASS','FAIL');
gate.reason=['Independent investment-stage gate; thresholds must be signed ' ...
    'by the enterprise investment owner.'];
end

function r=calculate_irr(cash)
% Bisection on NPV; returns NaN when a unique bracket is not established.
npv=@(rate) sum(cash./((1+rate).^(0:numel(cash)-1)'));
grid=[-0.999,linspace(-0.9,1,191),linspace(1.1,100,100)];
values=arrayfun(npv,grid);
idx=find(values(1:end-1).*values(2:end)<=0,1,'first');
if isempty(idx)
    r=NaN;
    return
end
lo=grid(idx);
hi=grid(idx+1);
for k=1:200
    mid=(lo+hi)/2;
    if npv(lo)*npv(mid)<=0
        hi=mid;
    else
        lo=mid;
    end
end
r=(lo+hi)/2;
end

function year=calculate_simple_payback(cash)
cumulative=cumsum(cash);
idx=find(cumulative>=0,1,'first');
if isempty(idx) || idx==1
    if isempty(idx), year=NaN; else, year=0; end
    return
end
previous=cumulative(idx-1);
increment=cash(idx);
if increment<=0
    year=NaN;
else
    year=(idx-2)+(-previous/increment);
end
end

function out=ternary(condition,a,b)
if condition, out=a; else, out=b; end
end
