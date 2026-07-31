from __future__ import annotations
import argparse, copy, json, sys, types
from pathlib import Path
import numpy as np
import pandas as pd

def main() -> None:
    ap=argparse.ArgumentParser()
    ap.add_argument('--module-root',required=True)
    ap.add_argument('--output',required=True)
    ap.add_argument('--hours',type=int,default=24)
    ap.add_argument('--cap-mw',type=float,default=10.0)
    ap.add_argument('--unit-count',type=int,default=1)
    ap.add_argument('--unit-cap-mw',type=float,default=7.618080005)
    ap.add_argument('--request')
    ap.add_argument(
        '--mode', choices=('sla', 'power_following'), default='sla',
        help='sla is the integrated operating model; power_following is an infinite-backlog absorption benchmark')
    args=ap.parse_args()
    if args.unit_count < 1 or args.unit_cap_mw <= 0:
        raise ValueError('unit-count and unit-cap-mw must be positive')
    root=Path(args.module_root).resolve()
    sys.path.insert(0,str(root/'src'))
    # h5py is optional for the documented constant-temperature fallback.
    # Do not install or alter the 4.6 module when the runtime lacks it.
    try:
        import h5py  # noqa: F401
        h5py_available=True
    except ModuleNotFoundError:
        dummy=types.ModuleType('h5py')
        class MissingH5File:
            def __init__(self,*_a,**_k):
                raise RuntimeError('h5py unavailable in V4 runtime')
        dummy.File=MissingH5File
        dummy.Dataset=object
        sys.modules['h5py']=dummy
        h5py_available=False
    from udc_dc_only.config import load_config
    from udc_dc_only.data_loader import load_inputs
    if args.mode == 'sla':
        from udc_dc_only.model import solve_dc_only
        override_path=root/'config'/'power_shortage_test.json'
    else:
        from udc_dc_only.raw_model import solve_dc_only
        override_path=root/'config'/'raw_power_following.json'
    # Both mode files are scenario overrides.  Start from the complete
    # validated default so either entry point receives all required keys.
    cfg=load_config(root/'config'/'default.json')
    cfg.update(json.loads(override_path.read_text(encoding='utf-8')))
    cfg.update({'simulation_hours':args.hours,'power_interface_mode':'constant',
        'constant_dc_power_cap_mw':args.cap_mw,'enforce_terminal_flex_queue':False,
        'allow_invalid_sea_temperature_fallback':True,
        'output_dir':str(Path(args.output).parent)})
    bundle=load_inputs(root/'UDC_data',cfg)
    if args.request:
        request=pd.read_csv(args.request)
        if 'compute_requested_mw' not in request.columns or len(request) != args.hours:
            raise ValueError('4.9 compute request must contain compute_requested_mw with one row per hour')
        cap=pd.to_numeric(request['compute_requested_mw'],errors='raise')
        if cap.isna().any() or (cap < 0).any():
            raise ValueError('4.9 compute request contains invalid power caps')
        total_cap=cap.to_numpy(float)
        cfg['power_interface_mode']='file'
    else:
        total_cap=np.full(args.hours,args.cap_mw,dtype=float)

    unit_frames=[]
    unit_audits=[]
    factor=None
    for unit_index in range(args.unit_count):
        # Sequential loading keeps unused units shut down and lets the
        # aggregate cluster operate between one-unit minimum and full scale.
        unit_cap=np.clip(
            total_cap-unit_index*args.unit_cap_mw,0.0,args.unit_cap_mw)
        unit_bundle=copy.deepcopy(bundle)
        unit_bundle.power=unit_bundle.power.copy()
        unit_bundle.power['dc_power_cap_mw']=unit_cap
        unit_cfg=dict(cfg)
        unit_cfg['power_interface_mode']='file'
        result=solve_dc_only(unit_bundle,unit_cfg)
        h_unit=result.hourly.copy()
        if factor is None:
            factor=float(result.summary['equivalent_gpu_it_power_kw'])/1000.0
        h_unit['compute_served_mwh_cs']=h_unit['total_gpu_hours']*factor
        h_unit['compute_queue_mwh_cs']=h_unit['flex_queue_mwh_it']
        h_unit['dc_aux_power_mw']=h_unit['dc_power_mw']-h_unit['it_power_mw']
        h_unit['rigid_unserved_mwh_cs']=h_unit['rigid_unserved_mwh_it']
        h_unit['flex_overdue_mwh_cs']=h_unit['flex_sla_overdue_mwh_it']
        h_unit['spot_dropped_mwh_cs']=h_unit['spot_dropped_mwh_it']
        h_unit['dc_online_min_mw']=h_unit['dc_base_power_mw']
        h_unit['compute_gross_revenue_yuan']=(
            h_unit['rigid_revenue_yuan']+
            h_unit['flex_revenue_yuan']+
            h_unit['spot_revenue_yuan'])
        h_unit['compute_sla_penalty_yuan']=h_unit['total_sla_penalty_yuan']
        h_unit['compute_variable_om_yuan']=h_unit['variable_om_yuan']
        h_unit['compute_electricity_transfer_yuan']=h_unit['electricity_cost_yuan']
        unit_frames.append(h_unit)
        unit_audits.append(result.audit)

    sum_cols=[
        'dc_power_mw','it_power_mw','dc_aux_power_mw',
        'compute_served_mwh_cs','compute_queue_mwh_cs',
        'rigid_unserved_mwh_cs','flex_overdue_mwh_cs',
        'spot_dropped_mwh_cs','dc_online_min_mw',
        'compute_gross_revenue_yuan','compute_sla_penalty_yuan',
        'compute_variable_om_yuan','compute_electricity_transfer_yuan']
    h=pd.DataFrame(index=unit_frames[0].index)
    for column in sum_cols:
        h[column]=sum(frame[column].to_numpy(float) for frame in unit_frames)
    online_count=sum(
        frame['dc_operational'].to_numpy(float) for frame in unit_frames)
    h['dc_online']=online_count>0
    h['compute_model_mode']=args.mode
    h['pue']=np.divide(
        h['dc_power_mw'],h['it_power_mw'],
        out=np.ones(len(h),dtype=float),
        where=h['it_power_mw'].to_numpy(float)>1e-12)
    cols=['dc_power_mw','it_power_mw','dc_aux_power_mw',
          'compute_served_mwh_cs','compute_queue_mwh_cs',
          'rigid_unserved_mwh_cs','flex_overdue_mwh_cs',
          'spot_dropped_mwh_cs','dc_online_min_mw','dc_online',
          'compute_model_mode','pue',
          'compute_gross_revenue_yuan','compute_sla_penalty_yuan',
          'compute_variable_om_yuan','compute_electricity_transfer_yuan']
    out=Path(args.output); out.parent.mkdir(parents=True,exist_ok=True)
    h[cols].to_csv(out,index=False)
    (out.parent/'v4_compute_audit.json').write_text(json.dumps({
        'existing_model_audit':unit_audits[0],
        'existing_solver':result.solver,
        'normalization':'MWh-CS = GPUh * equivalent_gpu_it_power_kw / 1000',
        'normalization_status':'[假设值，待企业调研校准]',
        'dispatch_request_source':'4.9 hourly request' if args.request else 'constant bridge cap',
        'compute_model_mode':args.mode,
        'compute_unit_count':args.unit_count,
        'compute_unit_facility_cap_mw':args.unit_cap_mw,
        'aggregate_physical_facility_cap_mw':args.unit_count*args.unit_cap_mw,
        'aggregation_method':'sequential identical units; extensive outputs summed',
        'aggregation_status':'[假设值，待企业调研校准]',
        'mode_meaning':(
            'task arrivals, queue and SLA accounting'
            if args.mode == 'sla'
            else 'infinite-backlog power-following absorption benchmark; not a rigid-task SLA model'
        ),
        'h5py_available':h5py_available,
        'sea_temperature_fallback_allowed':True,
        'sea_temperature_note':'缺少h5py时使用4.6既有配置的23.5°C回退值 [假设值，待企业调研校准]'},ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__': main()
