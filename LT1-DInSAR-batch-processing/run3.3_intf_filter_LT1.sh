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
# Run 3.3: generate and filter the single LT-1 DInSAR interferogram.
# Preview is the default. Add positional argument 1 to run formally.
# The only pair is derived automatically from the two records in data.list.
set -euo pipefail

usage() {
    cat <<'HELP'
Run 3.3: LT-1 single-pair interferometry and filtering

Usage:
  run3.3_intf_filter_LT1.sh
  run3.3_intf_filter_LT1.sh 1 [--input FILE] [--config FILE]

Examples:
  ./run3.3_intf_filter_LT1.sh
  ./run3.3_intf_filter_LT1.sh 1

Equivalent direct GMTSAR command:
  batch_processing.csh LT1 LT1_YYYYMMDD intf.list 4 config.LT1.txt

Required inputs:
  data.list                    Exactly two chronological acquisitions
  SLC/LT1_YYYYMMDD.PRM         Aligned/cropped PRM from Run 3.1
  SLC/LT1_YYYYMMDD.SLC         Aligned/cropped SLC from Run 3.1
  SLC/LT1_YYYYMMDD.LED         Orbit file used by the aligned SLC
  raw/LT1_YYYYMMDD.PRM         Original PRM used for output directory IDs
  topo/topo_ra.grd             Radar-coordinate DEM from Run 3.2

Main outputs:
  intf_all/REFERENCE_ID_REPEAT_ID/

GMTSAR step 4 runs intf.csh and filter.csh. Each output directory normally
contains phase.grd, phasefilt.grd, corr.grd and related products.

Formal mode writes intf.list and archives an existing output directory under
archive_run3.3/TIMESTAMP/intf_all/ before starting GMTSAR. The configuration's
proc_stage does not need to be changed: batch_processing.csh temporarily sets
proc_stage=4 for this step.
HELP
}

die() { echo "[ERROR] $*" >&2; exit 1; }

formal=0
input_file="data.list"
pairs_file="intf.list"
config_file="config.LT1.txt"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        1) formal=1; shift ;;
        --input)
            [[ $# -ge 2 ]] || die "--input requires a file"
            input_file="$2"
            shift 2
            ;;
        --config)
            [[ $# -ge 2 ]] || die "--config requires a file"
            config_file="$2"
            shift 2
            ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
done

root_dir="$(pwd -P)"
slc_dir="$root_dir/SLC"
raw_dir="$root_dir/raw"
topo_dir="$root_dir/topo"

[[ -s "$input_file" ]] || die "input list not found or empty: $input_file"
[[ -f "$config_file" ]] || die "configuration file not found: $config_file"
[[ -s "$topo_dir/topo_ra.grd" ]] || die "missing $topo_dir/topo_ra.grd; run Run 3.2 first"

batch_cmd="$(command -v batch_processing.csh || true)"
[[ -n "$batch_cmd" ]] || die "batch_processing.csh was not found in PATH"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/run3.3_lt1.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
scene_list="$tmp_dir/scenes.list"
awk 'NF && $1 !~ /^#/ {print $1}' "$input_file" | LC_ALL=C sort > "$scene_list"
[[ "$(wc -l < "$scene_list" | awk '{print $1}')" -eq 2 ]] || die "this DInSAR workflow requires exactly two acquisitions"
reference="$(sed -n '1p' "$scene_list")"
repeat="$(sed -n '2p' "$scene_list")"
[[ "$reference" =~ ^LT1_([0-9]{8})$ ]] || die "invalid reference name: $reference"
master_stem="$reference"
master_date="${BASH_REMATCH[1]}"
[[ "$repeat" =~ ^LT1_[0-9]{8}$ ]] || die "invalid repeat name: $repeat"
generated_pairs="$tmp_dir/intf.list"
printf '%s:%s\n' "$reference" "$repeat" > "$generated_pairs"
pairs_file="$generated_pairs"
pair_manifest="$tmp_dir/pair_manifest.tsv"
: > "$pair_manifest"

pair_count=0
while IFS= read -r pair || [[ -n "$pair" ]]; do
    [[ -n "$pair" ]] || continue
    [[ "$pair" != \#* ]] || continue
    [[ "$pair" =~ ^(LT1_[0-9]{8}):(LT1_[0-9]{8})$ ]] || die "invalid pair in $pairs_file: $pair"
    reference="${BASH_REMATCH[1]}"
    repeat="${BASH_REMATCH[2]}"
    [[ "$reference" != "$repeat" ]] || die "self-interferogram is not allowed: $pair"

    for stem in "$reference" "$repeat"; do
        [[ -s "$slc_dir/${stem}.PRM" ]] || die "missing SLC/${stem}.PRM; Run 3.1 may be incomplete"
        [[ -e "$slc_dir/${stem}.SLC" ]] || die "missing SLC/${stem}.SLC; Run 3.1 may be incomplete"
        [[ -e "$slc_dir/${stem}.LED" ]] || die "missing SLC/${stem}.LED; Run 3.1 may be incomplete"
        [[ -s "$raw_dir/${stem}.PRM" ]] || die "missing raw/${stem}.PRM"
    done

    reference_id="$(awk '$1=="SC_clock_start" && $2=="=" {printf "%d",int($3); exit}' "$raw_dir/${reference}.PRM")"
    repeat_id="$(awk '$1=="SC_clock_start" && $2=="=" {printf "%d",int($3); exit}' "$raw_dir/${repeat}.PRM")"
    [[ -n "$reference_id" && -n "$repeat_id" ]] || die "failed to read SC_clock_start for $pair"
    printf '%s\t%s_%s\n' "$pair" "$reference_id" "$repeat_id" >> "$pair_manifest"
    pair_count=$((pair_count + 1))
done < "$pairs_file"

[[ "$pair_count" -gt 0 ]] || die "no valid pairs found in $pairs_file"

duplicate_pair="$(awk -F'\t' 'seen[$1]++ {print $1; exit}' "$pair_manifest")"
[[ -z "$duplicate_pair" ]] || die "duplicate pair in $pairs_file: $duplicate_pair"

proc_stage="$(awk '$1=="proc_stage" && $2=="=" {print $3; exit}' "$config_file")"
filter_wavelength="$(awk '$1=="filter_wavelength" && $2=="=" {print $3; exit}' "$config_file")"
range_dec="$(awk '$1=="range_dec" && $2=="=" {print $3; exit}' "$config_file")"
azimuth_dec="$(awk '$1=="azimuth_dec" && $2=="=" {print $3; exit}' "$config_file")"

echo "========================================================================"
echo "LT-1 Run 3.3 interferometry and filtering (intf.csh + filter.csh)"
echo "Mode:              $([[ "$formal" -eq 1 ]] && echo FORMAL || echo PREVIEW)"
echo "Working dir:       $root_dir"
echo "Master:            $master_stem"
echo "Pair:              $reference:$repeat"
echo "Selected pairs:    $pair_count"
echo "Radar DEM:         $topo_dir/topo_ra.grd"
echo "Config:            $config_file"
echo "proc_stage:        ${proc_stage:-MISSING} (temporarily overridden to 4)"
echo "filter_wavelength: ${filter_wavelength:-MISSING}"
echo "range_dec:         ${range_dec:-MISSING}"
echo "azimuth_dec:       ${azimuth_dec:-MISSING}"
echo "Output directory:  $root_dir/intf_all"
echo "Command:           batch_processing.csh LT1 $master_stem intf.list 4 $config_file"
echo "========================================================================"

if [[ "$formal" -eq 0 ]]; then
    echo "[PREVIEW] All $pair_count pairs passed the input checks; no processing was started."
    echo "[NEXT]    $0 1 --input $input_file --config $config_file"
    exit 0
fi

cp "$generated_pairs" "$root_dir/intf.list"
pairs_file="$root_dir/intf.list"
echo "[PAIR LIST] $pairs_file"

# Preserve only directories that will be replaced during this run. GMTSAR's
# step-4 loop removes an existing directory with the same reference/repeat ID.
timestamp="$(date +%Y%m%dT%H%M%S)"
archive_dir="$root_dir/archive_run3.3/$timestamp/intf_all"
archive_count=0
while IFS=$'\t' read -r pair output_id; do
    old_dir="$root_dir/intf_all/$output_id"
    if [[ -d "$old_dir" ]]; then
        mkdir -p "$archive_dir"
        mv "$old_dir" "$archive_dir/"
        archive_count=$((archive_count + 1))
    fi
done < "$pair_manifest"

if [[ "$archive_count" -gt 0 ]]; then
    echo "[ARCHIVE] Moved $archive_count existing interferogram directory/directories to $archive_dir"
else
    echo "[ARCHIVE] No selected interferogram directory required backup."
fi

log_file="$root_dir/run3.3_intf_filter_${master_date}.log"
echo "[START]   step 4 interferometry; log: $log_file"
set +e
"$batch_cmd" LT1 "$master_stem" "$pairs_file" 4 "$config_file" 2>&1 | tee "$log_file"
status=${PIPESTATUS[0]}
set -e

[[ "$status" -eq 0 ]] || die "batch_processing.csh exited with status $status; inspect $log_file"

completed_count=0
missing_file="$root_dir/run3.3_missing_interferograms.tsv"
: > "$missing_file"
while IFS=$'\t' read -r pair output_id; do
    output_dir="$root_dir/intf_all/$output_id"
    if [[ -s "$output_dir/corr.grd" && -s "$output_dir/phasefilt.grd" ]]; then
        completed_count=$((completed_count + 1))
    else
        printf '%s\t%s\n' "$pair" "$output_dir" >> "$missing_file"
    fi
done < "$pair_manifest"

if [[ "$completed_count" -ne "$pair_count" ]]; then
    missing_count=$((pair_count - completed_count))
    die "$missing_count/$pair_count interferogram outputs are missing; inspect $missing_file and $log_file"
fi

rm -f "$missing_file"
echo "[SUCCESS] Run 3.3 completed intf.csh and filter.csh; corr.grd and phasefilt.grd are ready."
echo "[NEXT]    ./run3.4_make_landmask_ra_LT1.sh 1"
