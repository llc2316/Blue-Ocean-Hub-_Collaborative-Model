from core.power_balance import BalanceStatus
from core.components import EnergyIslandSystem
def plot_power_balance(system, result, title=None, save_path=None):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    fig, ((a1,a2),(a3,a4)) = plt.subplots(2,2,figsize=(14,10))
    fig.suptitle(title or f"{system.name} - Power Balance", fontsize=14, fontweight="bold")
    x = np.arange(7)
    cats = ["Gen","StgDis","Load","Comp","StgChg","Loss","Resv"]
    sup = [result.total_generation_mw, result.storage_discharge_mw, 0,0,0,0,0]
    dem = [0,0,result.total_load_mw,result.total_computing_mw,result.storage_charge_mw,result.total_loss_mw,result.reserve_gap_mw]
    a1.bar(x-0.15, sup, 0.3, label="Supply", color="green", alpha=0.7)
    a1.bar(x+0.15, dem, 0.3, label="Demand", color="red", alpha=0.7)
    a1.set_xticks(x); a1.set_xticklabels(cats, fontsize=9)
    a1.set_ylabel("MW"); a1.legend(); a1.grid(True, alpha=0.3)
    a1.set_title("Supply vs Demand")
    lbls = ["Gen","Load","Comp","Loss","ResvGap","NetImb"]
    vals = [result.total_generation_mw,result.total_load_mw,result.total_computing_mw,result.total_loss_mw,result.reserve_gap_mw,result.net_imbalance_mw]
    colors = ["green","red","orange","gray","purple","blue" if result.net_imbalance_mw>=0 else "darkred"]
    bars = a2.bar(lbls, vals, color=colors, alpha=0.7)
    for b,v in zip(bars,vals): a2.text(b.get_x()+b.get_width()/2, b.get_height()+max(vals)*0.02, f"{v:.1f}", ha="center", fontsize=9)
    a2.set_ylabel("MW"); a2.set_title("Summary"); a2.grid(True, alpha=0.3)
    rl = ["Req","Avail","Gap"]
    req_r = result.reserve_gap_mw + max(result.total_supply_mw-result.total_demand_mw, 0) * 0.15
    if req_r == 0: req_r = result.total_supply_mw * 0.15
    avail = max(result.total_supply_mw-result.total_demand_mw, 0)
    rv = [req_r, avail, result.reserve_gap_mw]
    a3.bar(rl, rv, color=["orange","green","red"], alpha=0.7)
    a3.set_ylabel("MW"); a3.set_title(f"Reserve: {result.status.value}"); a3.grid(True, alpha=0.3)
    if result.port_details:
        pn = list(result.port_details.keys())
        pv = list(result.port_details.values())
        pc = ["green" if v>=0 else "red" for v in pv]
        a4.barh(pn, pv, color=pc, alpha=0.7)
        a4.set_xlabel("MW")
        a4.set_title("Port Details")
    a4.grid(True, alpha=0.3)
    plt.tight_layout()
    if save_path: plt.savefig(save_path, dpi=150, bbox_inches="tight"); print("Saved:", save_path)
    plt.close()
    return fig
def plot_system_overview(system, save_path=None):
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, (a1,a2) = plt.subplots(1,2,figsize=(12,5))
    fig.suptitle(f"Overview: {system.name}", fontsize=14)
    labels=[]; sizes=[]
    tsrc=sum(s.rated_capacity_mw for s in system.sources.values())
    tstg=sum(s.rated_power_mw for s in system.storages.values())
    tcmp=sum(c.rated_power_mw for c in system.computings.values())
    tld=sum(l.rated_power_mw for l in system.loads.values())
    for lbl,val,clr in [("Src",tsrc,"green"),("Stg",tstg,"blue"),("Cmp",tcmp,"orange"),("Load",tld,"red")]:
        if val>0: labels.append(f"{lbl}\n{val:.0f}MW"); sizes.append(val)
    a1.pie(sizes, labels=labels, autopct="%1.1f%%", startangle=90, colors=["green","blue","orange","red"][:len(sizes)])
    a1.set_title("Installed Capacity")
    ol=[]; ov=[]
    for src in system.sources.values(): ol.append(f"{src.name}\n({src.current_output_mw:.0f}MW)"); ov.append(src.current_output_mw)
    for stg in system.storages.values(): ol.append(f"{stg.name}\nSOC={stg.current_soc:.0%}"); ov.append(stg.current_soc*stg.rated_power_mw)
    for cmp in system.computings.values(): ol.append(f"{cmp.name}\n({cmp.current_load_mw:.0f}MW)"); ov.append(-cmp.current_load_mw)
    for ld in system.loads.values(): ol.append(f"{ld.name}\n({ld.current_load_mw:.0f}MW)"); ov.append(-ld.current_load_mw)
    bc = ["green" if v>=0 else "red" for v in ov]
    a2.barh(ol, ov, color=bc, alpha=0.7)
    a2.axvline(0, color="black", linewidth=0.5)
    a2.set_xlabel("MW (+inject, -absorb)")
    a2.set_title("Current Operation")
    plt.tight_layout()
    if save_path: plt.savefig(save_path, dpi=150, bbox_inches="tight")
    plt.close()
    return fig
def plot_parameter_sweep(results, save_path=None):
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt; import numpy as np
    fig, ((a1,a2),(a3,a4)) = plt.subplots(2,2,figsize=(14,10))
    fig.suptitle("Parameter Sweep", fontsize=14)
    sl = sorted(set(r[0] for r in results))
    ll = sorted(set(r[1] for r in results))
    for a,metric,m,u in [(a1,"net_imbalance_mw","Net Imbalance","MW"),(a2,"total_loss_mw","Losses","MW"),(a3,"reserve_gap_mw","Reserve Gap","MW"),(a4,"surplus_ratio","Surplus Ratio","")]:
        for lv in ll:
            vals = []
            for s in sl:
                for si,li,res in results:
                    if abs(si-s)<0.01 and abs(li-lv)<0.01:
                        v = getattr(res, metric, 0)
                        if callable(v): v = v()
                        vals.append(v)
            if vals:
                a.plot(sl[:len(vals)], vals, marker="o", label=f"Load={lv:.1f}pu")
        a.set_xlabel("Source [pu]"); a.set_ylabel(f"{m} [{u}]" if u else m)
        a.set_title(metric); a.legend(fontsize=8); a.grid(True, alpha=0.3)
    plt.tight_layout()
    if save_path: plt.savefig(save_path, dpi=150, bbox_inches="tight")
    plt.close()
    return fig
