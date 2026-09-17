#!/usr/bin/env bash
# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
# Run 3.6: preview the masks and wrapped phase that will be passed to SNAPHU.
# This script never runs phase unwrapping.
set -euo pipefail

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'HELP'
Run 3.6: plot the masked wrapped phase before SNAPHU

Usage:
  ./run3.6_preview_unwrap_LT1.sh
  ./run3.6_preview_unwrap_LT1.sh 1 0.1
  ./run3.6_preview_unwrap_LT1.sh 1 [--threshold VALUE]
  ./run3.6_preview_unwrap_LT1.sh 1 0.1 --use-preview-region
  ./run3.6_preview_unwrap_LT1.sh 1 --region RNG0/RNG1/AZI0/AZI1

Correlation threshold:
  The default is 0.1. A positional value or --threshold VALUE overrides it.

Pre-unwrapping plot processing:
  combined mask = (corr.grd >= threshold) * mask.grd
                  * mask_def.grd                         (when present)
                  * landmask_ra.grd
  plotted phase = phasefilt.grd * combined mask

Run 3.6 stops before nearest_grid and SNAPHU. Temporary GRD/CPT files are
removed automatically. The two PNGs are saved in run3.6_unwrap_preview/.
By default the complete interferogram is previewed. Use --use-preview-region
only after creating a small region with Run 3.5.
HELP
}

config_file="config.LT1.txt"
formal=0
threshold=""
region=""
use_preview_region=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        1) formal=1; shift ;;
        --config) [[ $# -ge 2 ]] || die "--config requires a file"; config_file="$2"; shift 2 ;;
        --threshold) [[ $# -ge 2 ]] || die "--threshold requires a value"; threshold="$2"; shift 2 ;;
        --use-preview-region) use_preview_region=1; shift ;;
        --region) [[ $# -ge 2 ]] || die "--region requires RNG0/RNG1/AZI0/AZI1"; region="$2"; shift 2 ;;
        *)
            if [[ -z "$threshold" && "$1" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]]; then
                threshold="$1"
                shift
            else
                die "unknown argument: $1 (use --help)"
            fi
            ;;
    esac
done

[[ -f "$config_file" ]] || die "configuration file not found: $config_file"
[[ ! ( "$use_preview_region" -eq 1 && -n "$region" ) ]] || die "use either --use-preview-region or --region"
command -v gmt >/dev/null 2>&1 || die "GMT was not found in PATH"

[[ -n "$threshold" ]] || threshold="0.1"
[[ "$threshold" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] || die "invalid threshold_snaphu: ${threshold:-MISSING}"
awk -v v="$threshold" 'BEGIN {exit !(v >= 0 && v <= 1)}' || die "threshold must be between 0 and 1"

root_dir="$(pwd -P)"
[[ -d "$root_dir/intf_all" ]] || die "intf_all directory not found; complete Run 3.3 first"
pair_list="$(mktemp "${TMPDIR:-/tmp}/run3.6_preview_pairs.XXXXXX")"
trap 'rm -f "$pair_list"' EXIT
find "$root_dir/intf_all" -mindepth 1 -maxdepth 1 -type d -print \
    | awk -F/ '$NF ~ /^[0-9]{7,8}_[0-9]{7,8}$/ {print $0}' | LC_ALL=C sort > "$pair_list"
pair_count="$(wc -l < "$pair_list" | awk '{print $1}')"
[[ "$pair_count" -eq 1 ]] || die "expected exactly one interferogram directory; found $pair_count"
pair_dir="$(sed -n '1p' "$pair_list")"
pair_name="$(basename "$pair_dir")"

for grid in corr.grd mask.grd phasefilt.grd; do
    [[ -s "$pair_dir/$grid" ]] || die "missing or empty $pair_dir/$grid; complete Run 3.3 first"
done

grid_signature() {
    gmt grdinfo "$1" -Cn | awk '{print $1,$2,$3,$4,$7,$8,$9,$10}'
}

print_grid_check() {
    local label="$1" grid="$2"
    if [[ ! -s "$grid" ]]; then
        printf '[GRD MISSING] %-16s %s\n' "$label" "$grid"
        return 1
    fi
    gmt grdinfo "$grid" -Cn | awk -v label="$label" -v grid="$grid" '
        NF >= 10 {
            printf "[GRD OK] %-16s size=%sx%s region=%s/%s/%s/%s z=%s/%s file=%s\n", \
                label,$9,$10,$1,$2,$3,$4,$5,$6,grid
            ok=1
        }
        END {exit !ok}
    ' || die "failed to inspect $grid"
}

template_signature="$(grid_signature "$pair_dir/phasefilt.grd")"
[[ "$(grid_signature "$pair_dir/corr.grd")" == "$template_signature" ]] || die "corr.grd geometry differs from phasefilt.grd"
[[ "$(grid_signature "$pair_dir/mask.grd")" == "$template_signature" ]] || die "mask.grd geometry differs from phasefilt.grd"

full_region="$(gmt grdinfo "$pair_dir/phasefilt.grd" -Cn | awk '{print $1"/"$2"/"$3"/"$4}')"
region_source="full phasefilt.grd"
if [[ "$use_preview_region" -eq 1 ]]; then
    preview_region_file="$root_dir/run3.5_unwrap_region/radar_region.txt"
    [[ -s "$preview_region_file" ]] || die "missing $preview_region_file; run Run 3.5 first"
    region="$(awk 'NF {print $1; exit}' "$preview_region_file")"
    region_source="$preview_region_file"
elif [[ -n "$region" ]]; then
    region_source="command line"
fi
[[ -n "$region" ]] || region="$full_region"
[[ "$region" =~ ^[-+0-9.eE]+/[-+0-9.eE]+/[-+0-9.eE]+/[-+0-9.eE]+$ ]] || die "invalid radar region: $region"

printf '%s\n' '[GRD INPUT CHECK]'
print_grid_check "corr.grd" "$pair_dir/corr.grd"
print_grid_check "mask.grd" "$pair_dir/mask.grd"
print_grid_check "phasefilt.grd" "$pair_dir/phasefilt.grd"
landmask_grid="$pair_dir/landmask_ra.grd"
[[ -s "$landmask_grid" ]] || die "missing $pair_dir/landmask_ra.grd; complete Run 3.4 first"
[[ "$(grid_signature "$landmask_grid")" == "$template_signature" ]] || die "landmask_ra.grd geometry differs from phasefilt.grd"
print_grid_check "landmask_ra.grd" "$landmask_grid"
maskdef_grid="$pair_dir/mask_def.grd"
if [[ ! -s "$maskdef_grid" && -s "$root_dir/intf_all/mask_def.grd" ]]; then
    maskdef_grid="$root_dir/intf_all/mask_def.grd"
fi
if [[ -s "$maskdef_grid" ]]; then
    [[ "$(grid_signature "$maskdef_grid")" == "$template_signature" ]] || die "mask_def.grd geometry differs from phasefilt.grd"
    print_grid_check "mask_def.grd" "$maskdef_grid"
else
    printf '[GRD OPTIONAL] %-16s not found; it will not be multiplied.\n' "mask_def.grd"
fi

output_dir="$root_dir/run3.6_unwrap_preview"

printf '%s\n' '========================================================================'
printf 'LT-1 Run 3.6 pre-unwrapping preview\n'
printf 'Mode:                  %s\n' "$([[ "$formal" -eq 1 ]] && echo FORMAL || echo CHECK)"
printf 'Pair:                  %s\n' "$pair_name"
printf 'Correlation threshold: %s\n' "$threshold"
printf 'Region:                %s\n' "$region"
printf 'Region source:         %s\n' "$region_source"
printf 'Combined mask:         (corr >= %s) * mask * optional mask_def * landmask\n' "$threshold"
printf 'Plotted phase:         phasefilt * combined mask\n'
printf 'Interpolation:          not run in Run 3.6\n'
printf 'Mask figure:            %s/mask_presnaphu.png\n' "$output_dir"
printf 'Phase figure:           %s/phase_presnaphu.png\n' "$output_dir"
printf '%s\n' '========================================================================'

if [[ "$formal" -eq 0 ]]; then
    printf '[CHECK] Inputs are ready; preview products were not generated.\n'
    if [[ "$use_preview_region" -eq 1 ]]; then
        printf '[NEXT] ./run3.6_preview_unwrap_LT1.sh 1 %s --use-preview-region\n' "$threshold"
    else
        printf '[NEXT] ./run3.6_preview_unwrap_LT1.sh 1 %s\n' "$threshold"
    fi
    exit 0
fi

mkdir -p "$output_dir"
tmp_local="$(mktemp -d "$output_dir/.phase_presnaphu_tmp.XXXXXX")"
trap 'rm -f "$pair_list"; rm -rf "$tmp_local"' EXIT INT TERM

phase_input="$pair_dir/phasefilt.grd"
corr_input="$pair_dir/corr.grd"
mask_input="$pair_dir/mask.grd"
if [[ "$region" != "$full_region" ]]; then
    printf '[1/5] Cut the requested preview region...\n'
    gmt grdcut "$phase_input" -R"$region" -G"$tmp_local/phasefilt.grd"
    gmt grdcut "$corr_input" -R"$region" -G"$tmp_local/corr.grd"
    gmt grdcut "$mask_input" -R"$region" -G"$tmp_local/mask.grd"
    phase_input="$tmp_local/phasefilt.grd"
    corr_input="$tmp_local/corr.grd"
    mask_input="$tmp_local/mask.grd"
else
    printf '[1/5] Use the complete interferogram...\n'
fi

mask_all="$tmp_local/mask_all.grd"
mask_tmp="$tmp_local/mask_tmp.grd"
mask_resampled="$tmp_local/mask_resampled.grd"
phase_tmp="$tmp_local/phase_presnaphu.grd"
mask_cpt="$tmp_local/mask.cpt"
phase_cpt="$tmp_local/phase.cpt"

printf '[2/5] Apply corr >= %s and mask.grd...\n' "$threshold"
gmt grdmath "$corr_input" "$threshold" GE 0 NAN \
    "$mask_input" 0 GT 0 NAN MUL = "$mask_all"

printf '[3/5] Apply optional mask_def.grd...\n'
maskdef_used=0
maskdef_grid="$pair_dir/mask_def.grd"
if [[ ! -s "$maskdef_grid" && -s "$root_dir/intf_all/mask_def.grd" ]]; then
    maskdef_grid="$root_dir/intf_all/mask_def.grd"
fi
if [[ -s "$maskdef_grid" ]]; then
    phase_inc="$(gmt grdinfo -I "$phase_input")"
    gmt grdsample "$maskdef_grid" -R"$phase_input" "$phase_inc" -G"$mask_resampled"
    gmt grdmath "$mask_all" "$mask_resampled" 0 GT 0 NAN MUL = "$mask_tmp"
    mv "$mask_tmp" "$mask_all"
    maskdef_used=1
else
    printf '[INFO] mask_def.grd not found; skipped.\n'
fi

printf '[4/5] Apply landmask_ra.grd and combine with phasefilt.grd...\n'
phase_inc="$(gmt grdinfo -I "$phase_input")"
gmt grdsample "$landmask_grid" -R"$phase_input" "$phase_inc" -G"$mask_resampled"
gmt grdmath "$mask_all" "$mask_resampled" 0 GT 0 NAN MUL = "$mask_tmp"
mv "$mask_tmp" "$mask_all"
gmt grdmath "$phase_input" "$mask_all" MUL = "$phase_tmp"

printf '[5/5] Plot mask_presnaphu.png and phase_presnaphu.png...\n'
cat > "$mask_cpt" <<'MASK_CPT'
0.0   0   0   0 0.5   0   0   0
0.5 255 255 255 1.0 255 255 255
B     0   0   0
F   255 255 255
N     0   0   0
MASK_CPT
gmt makecpt -Ccyclic -T-3.141592653589793/3.141592653589793/0.02 -Z > "$phase_cpt"
rm -f "$output_dir/phase_presnaphu.pdf" \
    "$output_dir/mask_presnaphu.png" "$output_dir/phase_presnaphu.png"

gmt begin "$output_dir/mask_presnaphu" png
    gmt set MAP_FRAME_TYPE plain FONT_ANNOT_PRIMARY 10p \
        FONT_LABEL 11p FONT_TITLE 13p COLOR_NAN black
    gmt grdimage "$mask_all" -JX7i -C"$mask_cpt" \
        -Bxaf+l"Range" -Byaf+l"Azimuth" \
        -BWSen+t"Pre-SNAPHU combined mask, corr >= $threshold"
    gmt colorbar -DJTC+w5.5i/0.2i+h -C"$mask_cpt" \
        -Bxa1f1+l"Combined mask: 0 masked, 1 valid"
gmt end

gmt begin "$output_dir/phase_presnaphu" png
    gmt set MAP_FRAME_TYPE plain FONT_ANNOT_PRIMARY 10p \
        FONT_LABEL 11p FONT_TITLE 13p COLOR_NAN white
    gmt grdimage "$phase_tmp" -JX7i -C"$phase_cpt" \
        -Bxaf+l"Range" -Byaf+l"Azimuth" \
        -BWSen+t"Pre-SNAPHU wrapped phase, corr >= $threshold"
    gmt colorbar -DJTC+w5.5i/0.2i+h -C"$phase_cpt" \
        -Bxa1.57f0.785+l"Wrapped phase" -By+l"rad"
gmt end

[[ -s "$output_dir/mask_presnaphu.png" ]] || die "mask_presnaphu.png was not generated"
[[ -s "$output_dir/phase_presnaphu.png" ]] || die "phase_presnaphu.png was not generated"
printf 'mask_def used:         %s\n' "$([[ "$maskdef_used" -eq 1 ]] && echo yes || echo no)"
printf 'Mask figure:           %s/mask_presnaphu.png\n' "$output_dir"
printf 'Phase figure:          %s/phase_presnaphu.png\n' "$output_dir"
printf '[SUCCESS] Two pre-SNAPHU PNGs generated; temporary files were removed.\n'
if [[ "$use_preview_region" -eq 1 ]]; then
    printf '[NEXT] ./run3.7_unwrap_LT1.sh --threshold %s --use-preview-region\n' "$threshold"
else
    printf '[NEXT] ./run3.7_unwrap_LT1.sh --threshold %s\n' "$threshold"
fi
