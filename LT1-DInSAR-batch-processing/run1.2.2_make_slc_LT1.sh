#!/usr/bin/env bash
# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
# Run 1.2.2: Convert LT-1 TIFF products to GMTSAR SLC/PRM/LED files.
#
# Input:  raw/*.meta.xml and raw/*.tiff created by Run 1.2.1.
# Output: raw/LT1_YYYYMMDD.SLC, .PRM, .LED, and make_slc logs.
# Method: calls make_slc_lt1 with SLC_factor=10 and up to 2 parallel jobs.
# Orbit:  the generated LED still uses the orbit embedded in meta.xml.
#         Run 1.2.3 replaces it with the precise orbit.
# Master: the earliest acquisition is selected automatically.
#
# Examples:
#   ./run1.2.2_make_slc_LT1.sh
#   ./run1.2.2_make_slc_LT1.sh 1
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "${SCRIPT_DIR}/run1.2_preprocess_LT1.py" "$@" --step slc
