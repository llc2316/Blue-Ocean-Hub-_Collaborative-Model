@echo off
setlocal
python -m pip install -r requirements.txt
python scripts\check_data.py --data-root UDC_data
python scripts\run_raw_model.py --config config\raw_power_following.json --data-root UDC_data --output outputs\raw_power_following
python scripts\plot_results.py --input outputs\raw_power_following --output outputs\raw_power_following\figures
pause