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
# Run 1.2.4: Optionally resample LT-1 SLCs to common sampling parameters.
#
# Input:  raw/*.PRM and raw/*.SLC after Run 1.2.3.
# Preview: lists every scene's PRF/rng_samp_rate and reports the target maxima.
# Execute: backs up current PRM/SLC, then runs samp_slc.csh in isolated
#          per-scene workspaces and rewrites raw/*.PRM and raw/*.SLC.
# Backup: raw/archive_run1.2.4/ (old PRM/SLC and sampling logs).
# This step is optional and modifies large SLC files. Preview it first.
# Master: the earliest acquisition is selected automatically.
#
# Examples:
#   ./run1.2.4_common_sampling_LT1.sh
#   ./run1.2.4_common_sampling_LT1.sh 1
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "${SCRIPT_DIR}/run1.2_preprocess_LT1.py" "$@" --step sample
