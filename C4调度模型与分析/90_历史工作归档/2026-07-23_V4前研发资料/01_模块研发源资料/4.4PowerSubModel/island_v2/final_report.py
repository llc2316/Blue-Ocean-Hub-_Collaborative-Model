# Comprehensive Report Generator  
import sys, os  
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gen_clean.py')).read())  
  
import matplotlib  
matplotlib.use('Agg')  
import matplotlib.pyplot as plt  
import numpy as np  
  
OUT_DIR = r'C:\Users\86188\Documents\Codex\2026-07-20\ge\outputs\v3'  
os.makedirs(OUT_DIR, exist_ok=True)  
params = CommonCaseV1()  
r1 = run_simulation(params, 'base')  
r2 = run_simulation(params, 'peak') 
# ======== Chart 1: Power Balance ========  
def make_chart1_balance(r1, r2):  
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(12, 5))  
    fig.suptitle('Power Balance: Base vs Peak Scenario', fontsize=13)  
    for ax, r, label in [(a1, r1, 'Base'), (a2, r2, 'Peak')]:  
        b = r['balance']; s = r['source']; e = r['export']  
        categories = ['Source\nNet', 'DC\nLoad', 'Export\nSend', 'Marine\nLoad', 'Post-POI\nLoss', 'Common\nAux']  
        values = [s['net'], -r['dc'], -e['send'], -r['marine'], -b['post_loss'], -b['common_aux']]  
        colors = ['green' if v>=0 else 'red' for v in values]  
        ax.bar(categories, values, color=colors, alpha=0.7, edgecolor='black', linewidth=0.5)  
        ax.axhline(0, color='black', linewidth=0.8)  
        ax.set_ylabel('Power [MW]'); ax.set_title(f'{label}: Net={b['residual']:.2f} MW')  
        for tick in ax.get_xticklabels(): tick.set_fontsize(8)  
        ax.grid(True, alpha=0.3)  
    plt.tight_layout()  
    fp = os.path.join(OUT_DIR, 'chart1_balance.png')  
    plt.savefig(fp, dpi=150); plt.close(); print('Chart 1:', fp) 
# ======== Chart 2: Source Breakdown ========  
def make_chart2_source(r1, r2):  
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(10, 4.5))  
    fig.suptitle('Source Output Breakdown', fontsize=13)  
    params = CommonCaseV1()  
    for ax, r, title in [(a1, r1, 'Base'), (a2, r2, 'Peak')]:  
        sm = SourceModel_4_3(params.s)  
        if title == 'Base': vw,g,vt=8,600,2.0; s_share=sm.wind_power(vw); p_share=sm.pv_power(g); t_share=sm.tidal_power(vt)  
        else: vw,g,vt=4,200,1.0; s_share=sm.wind_power(vw); p_share=sm.pv_power(g); t_share=sm.tidal_power(vt)  
        sizes = [s_share, p_share, t_share]; labels = ['Wind', 'PV', 'Tidal']  
        colors = ['#2ecc71', '#f39c12', '#3498db']  
        wedges, texts, autos = ax.pie(sizes, labels=labels, autopct='%1.1f%%',  
            colors=colors, startangle=90, textprops={'fontsize': 9})  
        ax.set_title(title)  
    plt.tight_layout()  
    fp = os.path.join(OUT_DIR, 'chart2_source.png'); plt.savefig(fp, dpi=150); plt.close(); print('Chart 2:', fp) 
# ======== Chart 3: Loss Distribution ========  
def make_chart3_loss(r1, r2):  
    fig, ax = plt.subplots(figsize=(8, 4.5))  
    cats = ['Collection\nLoss', 'Source\nAux', 'Post-POI\nLoss', 'Common\nAux', 'Cable\nLoss']  
    b1 = [r1['source']['gross']*0.02, r1['source']['poi']*0.015, r1['balance']['post_loss'], r1['balance']['common_aux'], r1['export']['loss']]  
    b2 = [r2['source']['gross']*0.02, r2['source']['poi']*0.015, r2['balance']['post_loss'], r2['balance']['common_aux'], r2['export']['loss']]  
    x = np.arange(len(cats)); w = 0.35  
    ax.bar(x - w/2, b1, w, label='Base', color='#3498db', alpha=0.8)  
    ax.bar(x + w/2, b2, w, label='Peak', color='#e74c3c', alpha=0.8)  
    ax.set_xticks(x); ax.set_xticklabels(cats, fontsize=9)  
    ax.set_ylabel('Power Loss [MW]'); ax.set_title('Loss Distribution Comparison')  
    ax.legend(); ax.grid(True, alpha=0.3)  
    plt.tight_layout()  
    fp = os.path.join(OUT_DIR, 'chart3_loss.png'); plt.savefig(fp, dpi=150); plt.close(); print('Chart 3:', fp) 
# ======== Chart 4: Summary Comparison ========  
def make_chart4_summary(r1, r2):  
    fig, ax = plt.subplots(figsize=(10, 5))  
    b1, b2 = r1['balance'], r2['balance']  
    metrics = ['Source Net\n[MW]', 'DC Load\n[MW]', 'Export\n[MW]', 'Total Inject\n[MW]', 'Total Consume\n[MW]', 'Losses\n[MW]', 'Residual\n[MW]']  
    v1 = [r1['source']['net'], r1['dc'], r1['export']['send'], b1['inject'], b1['consume'], b1['post_loss']+b1['common_aux'], b1['residual']]  
    v2 = [r2['source']['net'], r2['dc'], r2['export']['send'], b2['inject'], b2['consume'], b2['post_loss']+b2['common_aux'], b2['residual']]  
    x = np.arange(len(metrics)); w = 0.35  
    bars1 = ax.bar(x - w/2, v1, w, label='Base', color='#2ecc71', alpha=0.85, edgecolor='black', linewidth=0.5)  
    bars2 = ax.bar(x + w/2, v2, w, label='Peak', color='#e74c3c', alpha=0.85, edgecolor='black', linewidth=0.5)  
    for bars in [bars1, bars2]:  
        for bar, val in zip(bars, v1 if bars is bars1 else v2):  
            ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.1, f'{val:.2f}', ha='center', va='bottom', fontsize=7, rotation=90)  
    ax.set_xticks(x); ax.set_xticklabels(metrics, fontsize=8)  
    ax.set_ylabel('Power [MW]'); ax.set_title('Comprehensive Summary: Base vs Peak')  
    ax.legend(fontsize=9); ax.grid(True, alpha=0.3)  
    plt.tight_layout()  
    fp = os.path.join(OUT_DIR, 'chart4_summary.png'); plt.savefig(fp, dpi=150); plt.close(); print('Chart 4:', fp) 
# Simple main  
make_chart1_balance(r1, r2)  
make_chart2_source(r1, r2)  
make_chart3_loss(r1, r2)  
make_chart4_summary(r1, r2)  
import os  
out = r'C:/Users/86188/Documents/Codex/2026-07-20/ge/outputs/v3'  
for fn in ['chart1_balance.png', 'chart2_source.png', 'chart3_loss.png', 'chart4_summary.png']:  
    fp = os.path.join(out, fn)  
    sz = os.path.getsize(fp) if os.path.exists(fp) else 0  
    print(fn, sz, 'bytes' if sz else 'MISSING')  
print('Charts generated') 
