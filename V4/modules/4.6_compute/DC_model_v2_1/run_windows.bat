@echo off
setlocal
python -m pip install -r requirements.txt
python scripts\check_data.py --data-root UDC_data
python scripts/run_model.py --config config/power_shortage_test.json --data-root UDC_data --output outputs/power_shortage_test
python scripts\plot_results.py --input outputs\power_shortage_test --output outputs\power_shortage_test\figures
pause