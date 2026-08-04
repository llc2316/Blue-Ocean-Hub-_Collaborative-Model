import sys, os  
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gen_clean.py')).read())  
import matplotlib; matplotlib.use('Agg')  
import matplotlib.pyplot as plt; import numpy as np  
out = r'C:/Users/86188/Documents/Codex/2026-07-20/ge/outputs/v3'  
os.makedirs(out, exist_ok=True)  
p = CommonCaseV1(); r1 = run_simulation(p, 'base'); r2 = run_simulation(p, 'peak')  
b1 = r1[chr(98)+chr(97)+chr(108)+chr(97)+chr(110)+chr(99)+chr(101)]; b2 = r2[chr(98)+chr(97)+chr(108)+chr(97)+chr(110)+chr(99)+chr(101)]  
s1 = r1['source']; s2 = r2['source']; e1 = r1['export']; e2 = r2['export']; d1 = r1['dc']; d2 = r2['dc']  
m1 = r1['marine']; m2 = r2['marine']; el1 = r1['electrolyzer']; el2 = r2['electrolyzer'] 
s1_net, s2_net = s1['net'], s2['net']  
e1_send, e2_send = e1['send'], e2['send']  
e1_loss, e2_loss = e1['loss'], e2['loss']  
b1_inj, b2_inj = b1['inject'], b2['inject']  
b1_con, b2_con = b1['consume'], b2['consume']  
b1_res, b2_res = b1['residual'], b2['residual']  
b1_pl, b2_pl = b1['post_loss'], b2['post_loss']  
b1_ca, b2_ca = b1['common_aux'], b2['common_aux']  
b1_stat, b2_stat = b1['status'], b2['status']  
g1, g2 = r1['source']['gross'], r2['source']['gross']  
po1, po2 = r1['source']['poi'], r2['source']['poi'] 
# Chart 1: Power Balance  
fig, (a1,a2) = plt.subplots(1,2,figsize=(12,5))  
fig.suptitle('Power Balance Comparison')  
cats = ['Source','DC','Export','Marine','Loss']  
for ax, s_net, dc, e_s, m, pl, ca, res, lbl in [  
    (a1,s1_net,d1,e1_send,m1,b1_pl,b1_ca,b1_res,'Base'),  
    (a2,s2_net,d2,e2_send,m2,b2_pl,b2_ca,b2_res,'Peak')]:  
    vals = [s_net, -dc, -e_s, -m, -(pl+ca)]  
    colors = ['#2ecc71' if v else '#e74c3c' for v in vals]  
    ax.bar(cats, vals, color=colors, alpha=0.7, edgecolor='black')  
    ax.axhline(0, color='black', lw=0.8)  
    ax.set_title(lbl + ': Net=' + '{:.2f}'.format(res) + ' MW')  
    ax.set_ylabel('Power [MW]'); ax.grid(True, alpha=0.3)  
plt.tight_layout()  
plt.savefig(os.path.join(out, 'chart1_balance.png'), dpi=150); plt.close(); print('Chart 1 done') 
# Chart 2: Source Breakdown  
fig, (a1,a2) = plt.subplots(1,2,figsize=(10,4.5))  
fig.suptitle('Source Output Breakdown')  
sm = SourceModel_4_3(p.s)  
for ax, vw, g, vt, lbl in [(a1,8,600,2.0,'Base'),(a2,4,200,1.0,'Peak')]:  
    sw = sm.wind_power(vw); sp = sm.pv_power(g); st = sm.tidal_power(vt)  
    ax.pie([sw,sp,st], labels=['Wind','PV','Tidal'], autopct='%1.1f%%',  
        colors=['#2ecc71','#f39c12','#3498db'], startangle=90)  
    ax.set_title(lbl)  
plt.tight_layout()  
plt.savefig(os.path.join(out, 'chart2_source.png'), dpi=150); plt.close(); print('Chart 2 done')  
  
# Chart 3: Loss Distribution  
fig, ax = plt.subplots(figsize=(8,4.5))  
cats3 = ['Coll Loss','Source Aux','Post-POI','Common Aux','Cable Loss']  
v3b = [g1*0.02, po1*0.015, b1_pl, b1_ca, e1_loss]  
v3p = [g2*0.02, po2*0.015, b2_pl, b2_ca, e2_loss]  
x = np.arange(5); w = 0.35  
ax.bar(x-w/2, v3b, w, label='Base', color='#3498db', alpha=0.8)  
ax.bar(x+w/2, v3p, w, label='Peak', color='#e74c3c', alpha=0.8)  
ax.set_xticks(x); ax.set_xticklabels(cats3, fontsize=9)  
ax.set_ylabel('Power [MW]'); ax.set_title('Loss Distribution')  
ax.legend(); ax.grid(True, alpha=0.3); plt.tight_layout()  
plt.savefig(os.path.join(out, 'chart3_loss.png'), dpi=150); plt.close(); print('Chart 3 done') 
# Chart 4: Summary  
fig, ax = plt.subplots(figsize=(10,5))  
cats4 = ['Src Net','DC Load','Export','Inject','Consume','Losses','Residual']  
v4b = [s1_net, -d1, -e1_send, b1_inj, b1_con, -(b1_pl+b1_ca), b1_res]  
v4p = [s2_net, -d2, -e2_send, b2_inj, b2_con, -(b2_pl+b2_ca), b2_res]  
x = np.arange(7); w = 0.35  
ax.bar(x-w/2, v4b, w, label='Base', color='#2ecc71', alpha=0.85, edgecolor='black')  
ax.bar(x+w/2, v4p, w, label='Peak', color='#e74c3c', alpha=0.85, edgecolor='black')  
ax.set_xticks(x); ax.set_xticklabels(cats4, fontsize=9)  
ax.set_ylabel('Power [MW]'); ax.set_title('Comprehensive Summary')  
ax.legend(); ax.grid(True, alpha=0.3); plt.tight_layout()  
plt.savefig(os.path.join(out, 'chart4_summary.png'), dpi=150); plt.close(); print('Chart 4 done')  
  
L = []  
L.append('Energy Island Power Balance Model Report')  
L.append('')  
L.append('=== Base Scenario ===')  
L.append('Source net: {:.3f} MW  DC load: {:.3f} MW  Export: {:.3f} MW'.format(s1_net, d1, e1_send))  
L.append('Inject: {:.3f} MW  Consume: {:.3f} MW  Losses: {:.3f} MW  Residual: {:.4f} MW'.format(b1_inj, b1_con, b1_pl+b1_ca, b1_res))  
L.append('Status: ' + b1_stat)  
L.append('')  
L.append('=== Peak Scenario ===')  
L.append('Source net: {:.3f} MW  Residual: {:.4f} MW  Status: {}'.format(s2_net, b2_res, b2_stat))  
L.append('')  
L.append('Charts saved: chart1_balance, chart2_source, chart3_loss, chart4_summary')  
open(os.path.join(out, 'report.txt'), 'w', encoding='utf-8').write(chr(10).join(L))  
print('Report saved')  
print('ALL COMPLETE') 
