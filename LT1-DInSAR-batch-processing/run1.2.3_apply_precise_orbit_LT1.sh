#!/usr/bin/env bash
# =============================================================================
# Author       : Xin Wang
# Affiliation  : University of Science and Technology of China (USTC)
# Location     : Hefei, China
# Email        : xinw11@mail.ustc.edu.cn
# GitHub       : https://github.com/Xin-Wang-520
# Uploaded     : 2026-09-17
# =============================================================================

# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
# Run 1.2.3: Apply LT-1 precise orbits to GMTSAR LED/PRM files.
#
# Input:  raw/*.PRM, raw/*.LED, and precise-orbit TXT files in data/orbit/.
# Formats: 13-column .scie.gps.txt and headered 18-column GpsData_GAS_C.
# Output: raw/*.LED.metadata backup, precise raw/*.LED, and updated raw/*.PRM.
# Method: matches satellite/date, extracts scene time +/-200 s, fills short
#         one-second sampling gaps, writes LED, and runs calc_dop_orb.
# Missing precise orbits automatically repair the metadata/coarse LED and are
# listed in run1.2.3_missing_precise_orbits.tsv. Use --require-precise-orbit
# when a missing orbit should stop execution.
# After a successful formal run, backups, logs, and completion markers are
# archived under raw/archive_run1.2.3/; active PRM/SLC/LED files stay in raw/.
# Master: the earliest acquisition is selected automatically.
#
# Examples:
#   ./run1.2.3_apply_precise_orbit_LT1.sh
#   ./run1.2.3_apply_precise_orbit_LT1.sh 1
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "${SCRIPT_DIR}/run1.2_preprocess_LT1.py" "$@" --step orbit
