#!/usr/bin/env bash
set -euo pipefail
python -m pip install -r requirements.txt
python scripts/check_data.py --data-root UDC_data
python scripts/run_model.py --data-root UDC_data --output outputs/base_case
