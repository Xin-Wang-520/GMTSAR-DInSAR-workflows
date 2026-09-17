#!/usr/bin/env bash
# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
# Run 1.2.1: Prepare LT-1 inputs in raw/.
#
# Input:  data/LT1*/<product>.meta.xml and <product>.tiff.
# Output: raw/*.meta.xml and raw/*.tiff symlinks, data.list, config.LT1.txt.
# Naming: data.list uses LT1_YYYYMMDD; the earliest date is its first line.
# Orbit:  meta.xml contains the product metadata orbit. This step does not
#         read or validate data/orbit/.
# Next:   Run 1.2.2 creates SLC/PRM/LED with the metadata orbit; Run 1.2.3
#         replaces the LED with the precise orbit.
# Master: the earliest acquisition is selected automatically.
# Mode:   omit positional 1 for preview; add 1 to perform the changes.
#
# Examples:
#   ./run1.2.1_prepare_raw_LT1.sh
#   ./run1.2.1_prepare_raw_LT1.sh 1
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "${SCRIPT_DIR}/run1.2_preprocess_LT1.py" "$@" --step prepare
