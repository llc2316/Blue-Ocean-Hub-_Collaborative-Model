import sys  
sys.path.insert(0, r'C:\Users\86188\Documents\Codex\2026-07-20\ge\work\island_power_balance')  
exec(open(r'C:\Users\86188\Documents\Codex\2026-07-20\ge\work\island_power_balance\model.py').read())  
cc = CommonCaseV1()  
cb, p = create_common_case(cc)  
r = run_balance(cb, p, 'base')  
print('Inject:', r.p_source_actual - r.p_source_aux + r.p_grid_import + r.p_bess_discharge)  
print('Consume:', r.p_bess_charge + r.p_electrolyzer + r.p_dc_facility + r.p_export_send + r.p_marine + r.p_spill + r.p_post_poi_loss + r.p_common_aux)  
print('Residual:', r.p_residual) 
