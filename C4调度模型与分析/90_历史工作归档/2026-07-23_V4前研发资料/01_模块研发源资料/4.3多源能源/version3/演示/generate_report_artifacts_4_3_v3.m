function out=generate_report_artifacts_4_3_v3()
%GENERATE_REPORT_ARTIFACTS_4_3_V3 Produce report figures/tables from synthetic data.
% Every numeric input and result is [ASSUMPTION - CALIBRATE WITH OEM/SITE DATA].
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'互补体系模型'));
outputDir=fullfile(root,'输出'); figureDir=fullfile(outputDir,'figures');
if ~exist(figureDir,'dir'), mkdir(figureDir); end
rng(4303);

%% 30-day synthetic same-site resource trajectories
dt=300; t=(0:dt:30*24*3600)'; h=t/3600; day=h/24; N=numel(t);
capacityMW=[85 10 5]; capacityW=capacityMW*1e6;
synoptic=0.09*sin(2*pi*h/(24*5))+0.04*sin(2*pi*h/(24*2.3));
windPu=min(1,max(0,0.58+0.20*sin(2*pi*h/17)+synoptic+0.025*randn(N,1)));
solarBase=max(0,sin(pi*mod(h-6,24)/12));
cloud=min(0.75,max(0,0.28-1.5*synoptic+0.05*randn(N,1)));
pvPu=solarBase.*(1-cloud);
tidalPu=abs(sin(2*pi*h/12.42)).^3;

% Common severe-sea-state event: all sources unavailable for six hours.
storm=day>=19.25 & day<19.50;
windPu(storm)=0; pvPu(storm)=0; tidalPu(storm)=0;
actualBySource=[windPu pvPu tidalPu].*capacityW;
availableBySource=min(capacityW,max(actualBySource,actualBySource./0.985));
forecastError=[0.035*sin(2*pi*h/7),0.06*sin(2*pi*h/5),0.025*sin(2*pi*h/8)];
forecastBySource=min(capacityW,max(0,availableBySource.*(1+forecastError)));

%% Equal-installed-capacity portfolio comparison and metrics
quality=true(N,3); shares=[0.85 0.10 0.05]; windows=[dt 3600 6*3600 24*3600];
portfolio=compare_source_portfolios_4_3_v3(t,[windPu pvPu tidalPu],quality,shares,windows,0.2);
portfolioNames=string({portfolio.name})';
summary=table(portfolioNames,zeros(3,1),zeros(3,1),zeros(3,1),zeros(3,1), ...
    'VariableNames',{'Portfolio','CV_1h','P05_1h_pu','LowFraction_1h','MaxLowDuration_1h_h'});
for j=1:3
    m=portfolio(j).metrics; summary.CV_1h(j)=m.coefficientVariation(2);
    summary.P05_1h_pu(j)=m.empiricalLowQuantileP05(2);
    summary.LowFraction_1h(j)=m.lowOutputFraction(2);
    summary.MaxLowDuration_1h_h(j)=m.maxLowDurationSeconds(2)/3600;
end
writetable(summary,fullfile(outputDir,'report_portfolio_comparison.csv'),'Encoding','UTF-8');

%% Correlated aggregate scenarios and coverage diagnostics
K=80; sourceScenario=zeros(N,3,K); common=0.055*randn(N,K);
for j=1:3
    idio=(0.035+0.012*j)*randn(N,K);
    sourceScenario(:,j,:)=reshape(min(capacityW(j),max(0,forecastBySource(:,j).*(1+common+idio))),N,1,K);
end
aggregateScenario=squeeze(sum(sourceScenario,2));
aggregateActual=sum(actualBySource,2); aggregateAvailable=sum(availableBySource,2);
aggregateForecast=sum(forecastBySource,2);
coverage=evaluate_scenario_coverage_4_3_v3(aggregateActual,aggregateScenario,[0.50 0.80 0.90]);
coverageTable=table(coverage.nominalCoverage',coverage.empiricalCoverage', ...
    coverage.coverageError',coverage.meanIntervalWidth'/1e6, ...
    'VariableNames',{'NominalCoverage','EmpiricalCoverage','CoverageError','MeanWidthMW'});
writetable(coverageTable,fullfile(outputDir,'report_scenario_coverage.csv'),'Encoding','UTF-8');

%% State/constraint dictionary export
dict=source_state_dictionary_4_3_v3();
writetable(dict.operatingState,fullfile(outputDir,'report_operating_state_dictionary.csv'),'Encoding','UTF-8');
writetable(dict.constraintReason,fullfile(outputDir,'report_constraint_reason_dictionary.csv'),'Encoding','UTF-8');

%% Plot defaults
fontName='Microsoft YaHei'; colors=[0.10 0.36 0.66;0.91 0.55 0.14;0.16 0.62 0.45];
set(groot,'defaultAxesFontName',fontName,'defaultTextFontName',fontName, ...
    'defaultAxesFontSize',10,'defaultLineLineWidth',1.4, ...
    'defaultAxesColor','w','defaultAxesXColor',[0.18 0.18 0.18], ...
    'defaultAxesYColor',[0.18 0.18 0.18],'defaultTextColor',[0.12 0.12 0.12], ...
    'defaultLegendColor','w','defaultLegendTextColor',[0.12 0.12 0.12], ...
    'defaultColorbarColor',[0.18 0.18 0.18]);

%% Figure 0a: chapter boundary and cross-module interfaces
f=figure('Color','w','Position',[100 100 1300 500]); ax=axes(f); axis(ax,[0 12 0 6]); axis(ax,'off'); hold(ax,'on');
boxnode(ax,[1.2 3.0],1.75,0.9,{'4.2 公共定义','时间轴/单位/测点'},colors(1,:));
boxnode(ax,[3.6 3.0],1.75,0.9,{'设备级模型','风电/光伏/潮流能'},colors(2,:));
boxnode(ax,[6.0 3.0],1.85,1.15,{'4.3 源侧边界','适配/聚合/场景/指标'},colors(3,:));
boxnode(ax,[8.7 4.35],1.55,0.85,{'4.4','母线功率守恒'},colors(1,:));
boxnode(ax,[8.7 1.65],1.55,0.85,{'4.5','储能/构网响应'},colors(2,:));
boxnode(ax,[11.0 3.0],1.65,0.95,{'4.8—4.9','EMS优化调度'},colors(3,:));
arrow(ax,[2.08 3.0],[2.72 3.0],''); arrow(ax,[4.48 3.0],[5.05 3.0],'');
arrow(ax,[6.93 3.25],[7.93 4.08],'实际注入'); arrow(ax,[6.93 2.75],[7.93 1.92],'波动边界');
arrow(ax,[9.48 4.1],[10.18 3.35],'功率缺口'); arrow(ax,[9.48 1.9],[10.18 2.65],'可行域');
arrow(ax,[10.18 3.05],[6.95 3.05],'逐源请求/备用');
title(ax,'4.3模型边界及跨模块接口','FontSize',15,'FontWeight','bold');
exportgraphics(f,fullfile(figureDir,'figure_4_3_boundary_interface.png'),'Resolution',180); close(f);

%% Figure 0b: device models to the common collection point
f=figure('Color','w','Position',[100 100 1300 620]); ax=axes(f); axis(ax,[0 12 0 8]); axis(ax,'off'); hold(ax,'on');
rowY=[6.4 4.0 1.6]; leftText={{'风速/平台运动','可用状态'},{'辐照/温度/姿态','海况'},{'有符号流速','平台速度/海况'}};
modelText={{'漂浮式风电','设备模型'},{'漂浮式光伏','设备模型'},{'潮流能','设备模型'}};
adaptText={{'风电公共测点适配','available/forecast/actual'},{'光伏公共测点适配','available/forecast/actual'},{'潮流能公共测点适配','available/forecast/actual'}};
for j=1:3
    boxnode(ax,[1.35 rowY(j)],2.0,0.9,leftText{j},colors(j,:));
    boxnode(ax,[4.25 rowY(j)],1.8,0.9,modelText{j},colors(j,:));
    boxnode(ax,[7.15 rowY(j)],2.25,0.9,adaptText{j},colors(j,:));
    arrow(ax,[2.35 rowY(j)],[3.35 rowY(j)],'环境/状态');
    arrow(ax,[5.15 rowY(j)],[6.03 rowY(j)],'设备输出');
    arrow(ax,[8.28 rowY(j)],[9.45 4.0],'');
end
boxnode(ax,[10.55 4.0],1.9,1.2,{'多源聚合','联合场景/互补指标'},[0.35 0.35 0.35]);
text(ax,6,7.65,'风—光—潮设备模型到公共汇集点的数据流','HorizontalAlignment','center','FontSize',15,'FontWeight','bold');
exportgraphics(f,fullfile(figureDir,'figure_4_3_device_to_poi.png'),'Resolution',180); close(f);

%% Figure 1: typical/extreme day source and aggregate trajectories
typicalMask=day>=4 & day<5; extremeMask=day>=19 & day<20;
f=figure('Color','w','Position',[100 100 1250 760]); tl=tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
plot_source_panel(nexttile(tl),h(typicalMask)-24*4,actualBySource(typicalMask,:)/1e6,colors,'典型日：逐源实际出力');
plot_aggregate_panel(nexttile(tl),h(typicalMask)-24*4,aggregateAvailable(typicalMask)/1e6,aggregateForecast(typicalMask)/1e6,aggregateActual(typicalMask)/1e6,'典型日：聚合边界与实际出力');
plot_source_panel(nexttile(tl),h(extremeMask)-24*19,actualBySource(extremeMask,:)/1e6,colors,'极端日：共同海况停机');
plot_aggregate_panel(nexttile(tl),h(extremeMask)-24*19,aggregateAvailable(extremeMask)/1e6,aggregateForecast(extremeMask)/1e6,aggregateActual(extremeMask)/1e6,'极端日：聚合边界与实际出力');
title(tl,'风—光—潮典型日/极端日源侧出力（合成数据）','FontWeight','bold');
exportgraphics(f,fullfile(figureDir,'figure_4_3_typical_extreme_output.png'),'Resolution',180); close(f);

%% Figure 2: multi-timescale complementarity diagnostics
scaleLabels={'5 min','1 h','6 h','24 h'}; f=figure('Color','w','Position',[100 100 1250 760]);
tl=tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(tl); imagesc(ax,portfolio(3).metrics.powerCorrelation(:,:,2),[-1 1]); axis(ax,'square');
xticks(ax,1:3); yticks(ax,1:3); xticklabels(ax,{'风','光','潮'}); yticklabels(ax,{'风','光','潮'}); colorbar(ax); title(ax,'1 h功率相关系数');
ax=nexttile(tl); cv=zeros(3,4); low=zeros(3,4);
for j=1:3, cv(j,:)=portfolio(j).metrics.coefficientVariation; low(j,:)=portfolio(j).metrics.lowOutputFraction; end
bar(ax,categorical(scaleLabels),cv'); ylabel(ax,'CV'); legend(ax,portfolioNames,'Location','northoutside','Orientation','horizontal'); grid(ax,'on'); title(ax,'多时间尺度聚合波动');
% The comparison input is per-unit power, so the ramp metric is reported as
% percentage of installed capacity per minute (not MW/min).
ax=nexttile(tl); p01=portfolio(3).metrics.rampP01WPerS*60*100; p99=portfolio(3).metrics.rampP99WPerS*60*100;
x=1:4; errorbar(ax,x,(p01+p99)/2,(p99-p01)/2,'o-','Color',colors(1,:),'MarkerFaceColor',colors(1,:)); xlim(ax,[0.5 4.5]); xticks(ax,x); xticklabels(ax,scaleLabels); ylabel(ax,'装机容量/min / %'); grid(ax,'on'); title(ax,'风光潮组合爬坡P01—P99');
ax=nexttile(tl); bar(ax,categorical(scaleLabels),100*low'); ylabel(ax,'低出力时间比例 / %'); legend(ax,portfolioNames,'Location','northoutside','Orientation','horizontal'); grid(ax,'on'); title(ax,'低于20%装机的时间比例');
title(tl,'多时间尺度互补性诊断（合成数据）','FontWeight','bold');
exportgraphics(f,fullfile(figureDir,'figure_4_3_multiscale_metrics.png'),'Resolution',180); close(f);

%% Figure 3: scenario fan and empirical coverage
fanMask=day>=18.75 & day<20.25; xh=h(fanMask)-24*18.75;
lo90=coverage.lower(fanMask,3)/1e6; hi90=coverage.upper(fanMask,3)/1e6;
lo50=coverage.lower(fanMask,1)/1e6; hi50=coverage.upper(fanMask,1)/1e6;
med=coverage.median(fanMask)/1e6; act=aggregateActual(fanMask)/1e6;
f=figure('Color','w','Position',[100 100 1200 690]); tl=tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
ax=nexttile(tl); hold(ax,'on');
fill(ax,[xh;flipud(xh)],[lo90;flipud(hi90)],[0.75 0.84 0.95],'EdgeColor','none','DisplayName','90%区间');
fill(ax,[xh;flipud(xh)],[lo50;flipud(hi50)],[0.45 0.68 0.90],'EdgeColor','none','DisplayName','50%区间');
plot(ax,xh,med,'Color',colors(1,:),'DisplayName','场景中位数'); plot(ax,xh,act,'k','LineWidth',1.3,'DisplayName','实际');
ylabel(ax,'聚合功率 / MW'); xlabel(ax,'距窗口起点 / h'); grid(ax,'on'); legend(ax,'Location','northoutside','Orientation','horizontal'); title(ax,'联合场景扇形图（含共同停机事件）');
ax=nexttile(tl); b=bar(ax,100*[coverage.nominalCoverage;coverage.empiricalCoverage]'); b(1).FaceColor=[0.65 0.65 0.65]; b(2).FaceColor=colors(1,:); xticklabels(ax,{'50%','80%','90%'}); ylabel(ax,'覆盖率 / %'); ylim(ax,[0 100]); grid(ax,'on'); legend(ax,{'名义覆盖率','经验覆盖率'},'Location','northoutside','Orientation','horizontal'); title(ax,'预测区间覆盖率校验');
title(tl,'联合场景与覆盖率诊断（合成数据）','FontWeight','bold');
exportgraphics(f,fullfile(figureDir,'figure_4_3_scenario_fan_coverage.png'),'Resolution',180); close(f);

%% Figure 4: state-machine/constraint dictionary overview
f=figure('Color','w','Position',[100 100 1200 650]); ax=axes(f); axis(ax,[0 10 0 7]); axis(ax,'off'); hold(ax,'on');
nodes=[1.4 5.2;3.8 5.2;6.2 5.2;8.6 5.2;3.8 2.0;6.2 2.0];
labels={'正常运行','环境停机','复归等待','恢复运行','资源不足/静水','故障/检修不可用'};
for i=1:size(nodes,1), rectangle(ax,'Position',[nodes(i,1)-0.8 nodes(i,2)-0.38 1.6 0.76],'Curvature',0.15,'FaceColor',[0.92 0.95 0.98],'EdgeColor',colors(1,:)); text(ax,nodes(i,1),nodes(i,2),labels{i},'HorizontalAlignment','center','FontWeight','bold'); end
arrow(ax,nodes(1,:),nodes(2,:),'环境越限'); arrow(ax,nodes(2,:),nodes(3,:),'安全条件恢复'); arrow(ax,nodes(3,:),nodes(4,:),'达到复归延时'); arrow(ax,nodes(1,:),nodes(5,:),'资源/静水'); arrow(ax,nodes(1,:),nodes(6,:),'故障或检修'); arrow(ax,nodes(5,:),nodes(1,:),'资源恢复'); arrow(ax,nodes(6,:),nodes(1,:),'修复且可用');
text(ax,5,6.45,'统一设备状态与约束原因关系','HorizontalAlignment','center','FontSize',14,'FontWeight','bold');
text(ax,5,0.65,'物理状态 operatingState 与受限原因 constraintReason 分离记录','HorizontalAlignment','center','Color',[0.25 0.25 0.25]);
exportgraphics(f,fullfile(figureDir,'figure_4_3_state_constraint.png'),'Resolution',180); close(f);

out=struct('time',t,'actualBySource',actualBySource,'availableBySource',availableBySource, ...
    'forecastBySource',forecastBySource,'portfolio',{portfolio},'summary',summary, ...
    'coverage',coverage,'coverageTable',coverageTable,'dictionary',dict, ...
    'figureDir',string(figureDir),'assumptionNotice',"[假设值，待企业调研校准]");
save(fullfile(outputDir,'report_artifacts_4_3_v3.mat'),'out','-v7.3');
fprintf('CHAPTER 4.3 REPORT ARTIFACTS GENERATED\n');
fprintf('All numerical results are [假设值，待企业调研校准].\n');
end

function plot_source_panel(ax,x,p,colors,titleText)
hold(ax,'on'); for j=1:3, plot(ax,x,p(:,j),'Color',colors(j,:)); end
xlabel(ax,'时刻 / h'); ylabel(ax,'功率 / MW'); grid(ax,'on'); title(ax,titleText); legend(ax,{'风电','光伏','潮流能'},'Location','northoutside','Orientation','horizontal');
end
function plot_aggregate_panel(ax,x,av,fc,act,titleText)
hold(ax,'on'); plot(ax,x,av,'--','Color',[0.35 0.35 0.35]); plot(ax,x,fc,':','Color',[0.85 0.45 0.10]); plot(ax,x,act,'Color',[0.10 0.36 0.66]);
xlabel(ax,'时刻 / h'); ylabel(ax,'功率 / MW'); grid(ax,'on'); title(ax,titleText); legend(ax,{'可用','预测','实际'},'Location','northoutside','Orientation','horizontal');
end
function arrow(ax,a,b,label)
v=b-a; quiver(ax,a(1),a(2),v(1),v(2),0,'Color',[0.25 0.25 0.25],'MaxHeadSize',0.15,'LineWidth',1.1); mid=(a+b)/2; text(ax,mid(1),mid(2)+0.18,label,'HorizontalAlignment','center','FontSize',9,'BackgroundColor','w');
end
function boxnode(ax,center,width,height,labels,edgeColor)
rectangle(ax,'Position',[center(1)-width/2 center(2)-height/2 width height], ...
    'Curvature',0.12,'FaceColor',[0.95 0.97 0.99],'EdgeColor',edgeColor,'LineWidth',1.2);
text(ax,center(1),center(2),labels,'HorizontalAlignment','center','VerticalAlignment','middle','FontWeight','bold','FontSize',10);
end
