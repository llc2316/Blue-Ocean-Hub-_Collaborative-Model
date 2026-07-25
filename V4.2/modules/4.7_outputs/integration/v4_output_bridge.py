from __future__ import annotations
import argparse, sys
from pathlib import Path
import pandas as pd

def main() -> None:
    ap=argparse.ArgumentParser()
    ap.add_argument('--module-root',required=True)
    ap.add_argument('--input',required=True)
    ap.add_argument('--output',required=True)
    ap.add_argument('--cable-cap',type=float,required=True)
    ap.add_argument('--grid-cap',type=float,required=True)
    ap.add_argument('--cable-loss',type=float,required=True)
    ap.add_argument('--pipe-cap',type=float,required=True)
    ap.add_argument('--ship-cap',type=float,required=True)
    ap.add_argument('--pipe-loss',type=float,required=True)
    ap.add_argument('--ship-loss',type=float,required=True)
    ap.add_argument('--marine-base',type=float,required=True)
    ap.add_argument('--marine-desal',type=float,required=True)
    ap.add_argument('--marine-equipment',type=float,required=True)
    ap.add_argument('--marine-flex',type=float,required=True)
    args=ap.parse_args()
    root=Path(args.module_root).resolve(); sys.path.insert(0,str(root/'src'))
    from bluehub_submodules.power_export import PowerExportParams,evaluate_power_export
    from bluehub_submodules.marine_load import MarineLoadParams,evaluate_marine_load
    d=pd.read_csv(args.input); rows=[]
    pp=PowerExportParams(cable_capacity_mw=args.cable_cap,grid_accept_max_mw=args.grid_cap,
                         cable_loss_fraction=args.cable_loss)
    # Component split preserves the existing 4.7 total-demand model while
    # allowing the 4.9 request to remain external.
    mp=MarineLoadParams(aux_load_mw=args.marine_base,desal_load_mw=args.marine_desal,
                        equipment_load_mw=args.marine_equipment,flexible_fraction=args.marine_flex)
    for _,r in d.iterrows():
        e=evaluate_power_export(float(r.export_requested_mw),pp)
        m=evaluate_marine_load(float(r.marine_available_mw),mp,
                               requested_power_mw=float(r.marine_requested_mw))
        avail=max(0.0,float(r.h2_available_kg)); req=max(0.0,float(r.h2_requested_kg))
        pipe=min(req,args.pipe_cap,avail); left=avail-pipe
        ship=min(max(0.0,req-pipe),args.ship_cap,left)
        withdrawn=pipe+ship
        delivered=pipe*(1-args.pipe_loss)+ship*(1-args.ship_loss)
        compute_delivered=min(max(0.0,float(r.compute_served_mwh_cs)),
                              max(0.0,float(r.compute_delivery_cap_mwh_cs)))
        rows.append({'export_actual_mw':e.exported_power_mw,'cable_receive_mw':e.delivered_power_mw,
          'cable_loss_mw':e.lost_power_mw,'marine_actual_mw':m.served_power_mw,
          'marine_unserved_mw':m.unmet_power_mw,'h2_withdrawn_kg':withdrawn,
          'h2_delivered_kg':delivered,'compute_delivered_mwh_cs':compute_delivered,
          'marine_below_rigid':int(m.served_power_mw+1e-12 < mp.rigid_load_mw),
          'marine_violation_count':len(m.violations)})
    out=Path(args.output); out.parent.mkdir(parents=True,exist_ok=True)
    pd.DataFrame(rows).to_csv(out,index=False)

if __name__=='__main__': main()
