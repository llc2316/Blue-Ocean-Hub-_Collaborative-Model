@echo off
setlocal
python -m pip install -r requirements.txt
python scripts\check_data.py --data-root UDC_data
python scripts\run_model.py --data-root UDC_data --output outputs\base_case
python scripts\plot_results.py --input outputs\base_case --output outputs\base_case\figures
pause
