#!/usr/bin/env bash
# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
# Run 3.7: unwrap the single LT-1 DInSAR interferogram with a selected wrapper.
# Preview is the default. Add positional argument 1 to run formally.
set -euo pipefail

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'HELP'
Run 3.7: LT-1 single-pair phase unwrapping

Usage:
  ./run3.7_unwrap_LT1.sh
  ./run3.7_unwrap_LT1.sh 1
  ./run3.7_unwrap_LT1.sh [1] CORR_THRESHOLD
  ./run3.7_unwrap_LT1.sh [1] [--threshold VALUE] [--defomax VALUE]
  ./run3.7_unwrap_LT1.sh [1] --use-preview-region
  ./run3.7_unwrap_LT1.sh [1] --region RNG0/RNG1/AZI0/AZI1
  ./run3.7_unwrap_LT1.sh [1] (--snaphu_interp | --snaphu)

Unwrapping method:
  --snaphu_interp  Use snaphu_interp.csh (mask low-coherence pixels, then run
                   nearest_grid before SNAPHU).
  --snaphu         Use standard snaphu.csh without nearest_grid interpolation.
  If neither option is supplied, select method 1 or 2 interactively.

Correlation threshold:
  CORR_THRESHOLD or --threshold VALUE
               Set the correlation threshold from 0 to 1.
  If omitted, it must be entered interactively after selecting the method.

Region selection:
  Default                Unwrap the complete phasefilt.grd.
  --use-preview-region   Read run3.5_unwrap_region/radar_region.txt.
  --region REGION        Use an explicit radar-coordinate region.

Examples:
  ./run3.7_unwrap_LT1.sh
  ./run3.7_unwrap_LT1.sh 1
  ./run3.7_unwrap_LT1.sh --snaphu_interp 0.1
  ./run3.7_unwrap_LT1.sh 1 --snaphu_interp 0.1
  ./run3.7_unwrap_LT1.sh --use-preview-region
  ./run3.7_unwrap_LT1.sh 1 --use-preview-region
  ./run3.7_unwrap_LT1.sh --snaphu 0.1
  ./run3.7_unwrap_LT1.sh 1 --snaphu 0.1

The defomax value is read from config.LT1.txt unless overridden on the command
line. Existing unwrap products are archived before a formal rerun. In
interpolation mode, the phase input is masked and filled by nearest_grid before
SNAPHU. The --snaphu mode skips that fill.
HELP
}

formal=0
config_file="config.LT1.txt"
threshold=""
defomax=""
region=""
use_preview_region=0
unwrap_wrapper=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        1) formal=1; shift ;;
        --config) [[ $# -ge 2 ]] || die "--config requires a file"; config_file="$2"; shift 2 ;;
        --threshold) [[ $# -ge 2 ]] || die "--threshold requires a value"; threshold="$2"; shift 2 ;;
        --defomax) [[ $# -ge 2 ]] || die "--defomax requires a value"; defomax="$2"; shift 2 ;;
        --use-preview-region) use_preview_region=1; shift ;;
        --region) [[ $# -ge 2 ]] || die "--region requires RNG0/RNG1/AZI0/AZI1"; region="$2"; shift 2 ;;
        --snaphu_interp)
            [[ -z "$unwrap_wrapper" ]] || die "choose only one unwrapping method"
            unwrap_wrapper="snaphu_interp.csh"
            shift
            ;;
        --snaphu)
            [[ -z "$unwrap_wrapper" ]] || die "choose only one unwrapping method"
            unwrap_wrapper="snaphu.csh"
            shift
            ;;
        [0-9]*|[.][0-9]*)
            [[ -z "$threshold" ]] || die "correlation threshold was specified more than once"
            threshold="$1"
            shift
            ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
done

if [[ -z "$unwrap_wrapper" ]]; then
    [[ -t 0 ]] || die "select an unwrapping method with --snaphu_interp or --snaphu"
    printf '%s\n' 'Select an unwrapping method:'
    printf '%s\n' '  1) snaphu_interp.csh (mask + nearest_grid interpolation)'
    printf '%s\n' '  2) snaphu.csh        (no nearest_grid interpolation)'
    read -r -p 'Enter 1 or 2: ' method_choice
    case "$method_choice" in
        1) unwrap_wrapper="snaphu_interp.csh" ;;
        2) unwrap_wrapper="snaphu.csh" ;;
        *) die "invalid selection: ${method_choice:-EMPTY}; enter 1 or 2" ;;
    esac
fi

[[ -f "$config_file" ]] || die "configuration file not found: $config_file"
[[ ! ( "$use_preview_region" -eq 1 && -n "$region" ) ]] || die "use either --use-preview-region or --region"
command -v "$unwrap_wrapper" >/dev/null 2>&1 || die "$unwrap_wrapper was not found in PATH"
if [[ "$unwrap_wrapper" == "snaphu_interp.csh" ]]; then
    command -v nearest_grid >/dev/null 2>&1 || die "nearest_grid was not found in PATH"
fi
command -v gmt >/dev/null 2>&1 || die "GMT was not found in PATH"

config_value() {
    awk -v key="$1" '$1==key && $2=="=" {print $3; exit}' "$config_file"
}

if [[ -z "$threshold" ]]; then
    [[ -t 0 ]] || die "provide a correlation threshold, for example: --threshold 0.1"
    configured_threshold="$(config_value threshold_snaphu)"
    printf 'Configured threshold_snaphu: %s\n' "${configured_threshold:-MISSING}"
    read -r -p 'Enter correlation threshold (0 to 1): ' threshold
fi
[[ -n "$defomax" ]] || defomax="$(config_value defomax)"
[[ "$threshold" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] || die "invalid threshold_snaphu: ${threshold:-MISSING}"
[[ "$defomax" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "invalid defomax: ${defomax:-MISSING}"
awk -v v="$threshold" 'BEGIN {exit !(v >= 0 && v <= 1)}' || die "threshold must be between 0 and 1"

root_dir="$(pwd -P)"
[[ -d "$root_dir/intf_all" ]] || die "intf_all directory not found; complete Run 3.3 first"
pair_list="$(mktemp "${TMPDIR:-/tmp}/run3.7_pairs.XXXXXX")"
trap 'rm -f "$pair_list"' EXIT
find "$root_dir/intf_all" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null \
    | awk -F/ '$NF ~ /^[0-9]{7,8}_[0-9]{7,8}$/ {print $0}' | LC_ALL=C sort > "$pair_list"
pair_count="$(wc -l < "$pair_list" | awk '{print $1}')"
[[ "$pair_count" -eq 1 ]] || die "expected exactly one interferogram directory under intf_all; found $pair_count"
pair_dir="$(sed -n '1p' "$pair_list")"
pair_name="$(basename "$pair_dir")"

for grid in corr.grd mask.grd phasefilt.grd; do
    [[ -s "$pair_dir/$grid" ]] || die "missing or empty $pair_dir/$grid; complete Run 3.3 first"
done
[[ -s "$pair_dir/landmask_ra.grd" ]] || die "missing $pair_dir/landmask_ra.grd; complete Run 3.4 first"

full_region="$(gmt grdinfo "$pair_dir/phasefilt.grd" -Cn | awk '{print $1"/"$2"/"$3"/"$4}')"
[[ "$full_region" =~ ^[^/]+/[^/]+/[^/]+/[^/]+$ ]] || die "failed to read the phasefilt.grd region"
region_source="full phasefilt.grd"
if [[ "$use_preview_region" -eq 1 ]]; then
    preview_region_file="$root_dir/run3.5_unwrap_region/radar_region.txt"
    [[ -s "$preview_region_file" ]] || die "missing $preview_region_file; run Run 3.5 first"
    region="$(awk 'NF {print $1; exit}' "$preview_region_file")"
    region_source="$preview_region_file"
elif [[ -n "$region" ]]; then
    region_source="command line"
fi
if [[ -n "$region" ]]; then
    [[ "$region" =~ ^[-+0-9.eE]+/[-+0-9.eE]+/[-+0-9.eE]+/[-+0-9.eE]+$ ]] || die "invalid radar region: $region"
fi

printf '%s\n' '========================================================================'
printf 'LT-1 Run 3.7 single-pair phase unwrapping\n'
printf 'Mode:                  %s\n' "$([[ "$formal" -eq 1 ]] && echo FORMAL || echo PREVIEW)"
printf 'Pair:                  %s\n' "$pair_name"
printf 'Input phase:           %s\n' "$pair_dir/phasefilt.grd"
printf 'SNAPHU wrapper:         %s\n' "$unwrap_wrapper"
printf 'Full radar region:     %s\n' "$full_region"
printf 'Unwrap region:         %s\n' "${region:-FULL}"
printf 'Region source:         %s\n' "$region_source"
printf 'Correlation threshold: %s\n' "$threshold"
printf 'Maximum discontinuity: %s\n' "$defomax"
if [[ -n "$region" ]]; then
    printf 'Command:               %s %s %s %s\n' "$unwrap_wrapper" "$threshold" "$defomax" "$region"
else
    printf 'Command:               %s %s %s\n' "$unwrap_wrapper" "$threshold" "$defomax"
fi
printf '%s\n' '========================================================================'

if [[ "$formal" -eq 0 ]]; then
    printf '[PREVIEW] No unwrapping was started.\n'
    if [[ "$unwrap_wrapper" == "snaphu_interp.csh" ]]; then
        method_option=" --snaphu_interp"
    else
        method_option=" --snaphu"
    fi
    threshold_option=" $threshold"
    if [[ "$use_preview_region" -eq 1 ]]; then
        printf '[NEXT] ./run3.7_unwrap_LT1.sh 1 --use-preview-region%s%s\n' "$method_option" "$threshold_option"
    elif [[ -n "$region" ]]; then
        printf '[NEXT] ./run3.7_unwrap_LT1.sh 1 --region %s%s%s\n' "$region" "$method_option" "$threshold_option"
    else
        printf '[NEXT] ./run3.7_unwrap_LT1.sh 1%s%s\n' "$method_option" "$threshold_option"
    fi
    exit 0
fi

archive_dir="$root_dir/archive_run3.7/$(date +%Y%m%dT%H%M%S)/$pair_name"
archive_count=0
for name in unwrap.grd unwrap.pdf conncomp.grd phasefilt_interp.grd snaphu.conf snaphu.log; do
    if [[ -e "$pair_dir/$name" ]]; then
        mkdir -p "$archive_dir"
        mv "$pair_dir/$name" "$archive_dir/"
        archive_count=$((archive_count + 1))
    fi
done
[[ "$archive_count" -eq 0 ]] || printf '[ARCHIVE] Moved %s previous unwrap product(s) to %s\n' "$archive_count" "$archive_dir"

log_file="$root_dir/run3.7_unwrap_${pair_name}.log"
printf '[START] Unwrapping %s; log: %s\n' "$pair_name" "$log_file"

# Keep backward compatibility when an optional mask_def.grd is still stored
# in intf_all/. landmask_ra.grd is generated directly in the pair directory.
if [[ -s "$root_dir/intf_all/mask_def.grd" && ! -e "$pair_dir/mask_def.grd" ]]; then
    ln -s ../mask_def.grd "$pair_dir/mask_def.grd"
fi
set +e
if [[ -n "$region" ]]; then
    (cd "$pair_dir" && "$unwrap_wrapper" "$threshold" "$defomax" "$region") 2>&1 | tee "$log_file"
else
    (cd "$pair_dir" && "$unwrap_wrapper" "$threshold" "$defomax") 2>&1 | tee "$log_file"
fi
status=${PIPESTATUS[0]}
set -e
[[ "$status" -eq 0 ]] || die "$unwrap_wrapper exited with status $status; inspect $log_file"
[[ -s "$pair_dir/unwrap.grd" ]] || die "unwrap.grd was not generated; inspect $log_file"

printf '[SUCCESS] Unwrapped phase: %s\n' "$pair_dir/unwrap.grd"
printf '[NEXT] ./run3.8_geocode_unwrap_LOS_LT1.sh\n'
