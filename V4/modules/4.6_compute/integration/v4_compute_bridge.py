from __future__ import annotations
import argparse, json, sys, types
from pathlib import Path
import pandas as pd

def main() -> None:
    ap=argparse.ArgumentParser()
    ap.add_argument('--module-root',required=True)
    ap.add_argument('--output',required=True)
    ap.add_argument('--hours',type=int,default=24)
    ap.add_argument('--cap-mw',type=float,default=10.0)
    ap.add_argument('--request')
    args=ap.parse_args()
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
    from udc_dc_only.model import solve_dc_only
    cfg=load_config(root/'config'/'default.json')
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
        bundle.power=bundle.power.copy()
        bundle.power['dc_power_cap_mw']=cap.to_numpy(float)
        cfg['power_interface_mode']='file'
    result=solve_dc_only(bundle,cfg)
    h=result.hourly.copy()
    # Frozen interface normalization. MWh-CS uses the existing GPU-equivalent
    # conversion; calibration factor is currently 1.0 [assumption].
    factor=float(result.summary['equivalent_gpu_it_power_kw'])/1000.0
    h['compute_served_mwh_cs']=h['total_gpu_hours']*factor
    h['compute_queue_mwh_cs']=h['flex_queue_mwh_it']
    h['dc_aux_power_mw']=h['dc_power_mw']-h['it_power_mw']
    cols=['dc_power_mw','it_power_mw','dc_aux_power_mw',
          'compute_served_mwh_cs','compute_queue_mwh_cs','pue']
    out=Path(args.output); out.parent.mkdir(parents=True,exist_ok=True)
    h[cols].to_csv(out,index=False)
    (out.parent/'v4_compute_audit.json').write_text(json.dumps({
        'existing_model_audit':result.audit,'existing_solver':result.solver,
        'normalization':'MWh-CS = GPUh * equivalent_gpu_it_power_kw / 1000',
        'normalization_status':'[假设值，待企业调研校准]',
        'dispatch_request_source':'4.9 hourly request' if args.request else 'constant bridge cap',
        'h5py_available':h5py_available,
        'sea_temperature_fallback_allowed':True,
        'sea_temperature_note':'缺少h5py时使用4.6既有配置的23.5°C回退值 [假设值，待企业调研校准]'},ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__': main()
