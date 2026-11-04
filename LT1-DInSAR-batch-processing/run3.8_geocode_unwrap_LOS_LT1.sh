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
# Run 3.8: geocode the single-pair unwrapped phase and make LOS displacement.
# Existing wrapped-phase/correlation/amplitude geocoding is preserved.
set -euo pipefail

export LC_ALL=C
export LANG=C
export LANGUAGE=C

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'HELP'
Run 3.8: geocode unwrapped phase and generate LOS displacement

Usage:
  ./run3.8_geocode_unwrap_LOS_LT1.sh
  ./run3.8_geocode_unwrap_LOS_LT1.sh 1
  ./run3.8_geocode_unwrap_LOS_LT1.sh 1 0.1
  ./run3.8_geocode_unwrap_LOS_LT1.sh [1] [--threshold VALUE]
  ./run3.8_geocode_unwrap_LOS_LT1.sh [1] [--filter-wavelength METERS]

No arguments run a read-only preview. Add positional 1 for formal execution.
The default correlation threshold is 0.1. The default geocoding filter
wavelength is read from config.LT1.txt (normally 60 m), giving geographic
sampling of approximately one quarter of that value.

Processing follows the unwrap/LOS portion of GMTSAR geocode.csh:
  mask2.grd       = (corr.grd >= threshold) * mask.grd
  unwrap_mask.grd = unwrap.grd * mask2 resampled to the unwrap geometry
  los.grd         = unwrap_mask.grd * radar_wavelength * -79.58
  unwrap_mask_ll.grd is made with proj_ra2ll.csh
  los_ll.grd      = unwrap_mask_ll.grd * radar_wavelength * -79.58

The negative factor follows GMTSAR's convention: positive LOS displacement
means range decrease (motion toward the satellite). LOS grids are in mm.

Managed outputs in intf_all/DATE1_DATE2/:
  unwrap_mask.grd       unwrap_mask_ll.grd
  los.grd               los_ll.grd
  unwrap_mask_ll.png    los.png               los_ll.png

Existing corr_ll.grd, phasefilt_ll.grd, display_amp_ll.grd and their related
products are detected and left untouched; they need not be geocoded again.
Each managed output that already exists is also reused; only missing files are
generated.
HELP
}

formal=0
threshold=""
config_file="config.LT1.txt"
filter_wavelength=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        1) formal=1; shift ;;
        --threshold)
            [[ $# -ge 2 ]] || die "--threshold requires a value"
            [[ -z "$threshold" ]] || die "correlation threshold was specified more than once"
            threshold="$2"
            shift 2
            ;;
        --filter-wavelength)
            [[ $# -ge 2 ]] || die "--filter-wavelength requires a value"
            filter_wavelength="$2"
            shift 2
            ;;
        --config)
            [[ $# -ge 2 ]] || die "--config requires a file"
            config_file="$2"
            shift 2
            ;;
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

[[ -n "$threshold" ]] || threshold="0.1"
[[ "$threshold" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] || die "invalid threshold: $threshold"
awk -v value="$threshold" 'BEGIN {exit !(value >= 0 && value <= 1)}' || die "threshold must be between 0 and 1"

root_dir="$(pwd -P)"
[[ -f "$config_file" ]] || die "configuration file not found: $config_file"
if [[ -z "$filter_wavelength" ]]; then
    filter_wavelength="$(awk '$1=="filter_wavelength" && $2=="=" {print $3; exit}' "$config_file")"
fi
[[ "$filter_wavelength" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "invalid filter wavelength: ${filter_wavelength:-MISSING}"
awk -v value="$filter_wavelength" 'BEGIN {exit !(value > 0)}' || die "filter wavelength must be positive"

[[ -d "$root_dir/intf_all" ]] || die "intf_all directory not found; complete Run 3.3 first"
pair_list="$(mktemp "${TMPDIR:-/tmp}/run3.8_pairs.XXXXXX")"
work_dir=""
cleanup() {
    rm -f "$pair_list"
    if [[ -n "$work_dir" && -d "$work_dir" ]]; then
        rm -rf "$work_dir"
    fi
}
trap cleanup EXIT INT TERM

find "$root_dir/intf_all" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null \
    | awk -F/ '$NF ~ /^[0-9]{7,8}_[0-9]{7,8}$/ {print $0}' | LC_ALL=C sort > "$pair_list"
pair_count="$(wc -l < "$pair_list" | awk '{print $1}')"
[[ "$pair_count" -eq 1 ]] || die "expected exactly one interferogram directory; found $pair_count"
pair_dir="$(sed -n '1p' "$pair_list")"
pair_name="$(basename "$pair_dir")"

for input in "$pair_dir/unwrap.grd" "$pair_dir/corr.grd" "$pair_dir/mask.grd" "$root_dir/topo/trans.dat"; do
    [[ -s "$input" ]] || die "missing or empty input: $input"
done

prm_file="$(find "$pair_dir" -maxdepth 1 -type f -name '*.PRM' -print 2>/dev/null | LC_ALL=C sort | sed -n '1p')"
if [[ -z "$prm_file" ]]; then
    prm_file="$(find "$root_dir/SLC" -maxdepth 1 -type f -name '*.PRM' -print 2>/dev/null | LC_ALL=C sort | sed -n '1p')"
fi
[[ -n "$prm_file" && -s "$prm_file" ]] || die "no usable PRM file was found in the pair or SLC directory"
wavelength="$(awk '$1=="radar_wavelength" && $2=="=" {print $3; exit}' "$prm_file")"
[[ "$wavelength" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "invalid radar_wavelength in $prm_file"
los_factor="$(awk -v wavelength="$wavelength" 'BEGIN {printf "%.12g", wavelength * -79.58}')"

existing_geocode=()
for name in corr_ll.grd phasefilt_ll.grd phase_mask_ll.grd display_amp_ll.grd; do
    [[ -s "$pair_dir/$name" ]] && existing_geocode+=("$name")
done
managed_outputs=(unwrap_mask.grd unwrap_mask_ll.grd los.grd los_ll.grd unwrap_mask_ll.png los.png los_ll.png)
missing_outputs=()
for name in "${managed_outputs[@]}"; do
    [[ -s "$pair_dir/$name" ]] || missing_outputs+=("$name")
done

printf '%s\n' '========================================================================'
printf 'LT-1 Run 3.8 geocode unwrapped phase and generate LOS displacement\n'
printf 'Mode:                     %s\n' "$([[ "$formal" -eq 1 ]] && echo FORMAL || echo PREVIEW)"
printf 'Pair:                     %s\n' "$pair_name"
printf 'Unwrapped phase:          %s/unwrap.grd\n' "$pair_dir"
printf 'Projection table:         %s/topo/trans.dat\n' "$root_dir"
printf 'PRM/wavelength source:    %s\n' "$prm_file"
printf 'Radar wavelength:         %s m\n' "$wavelength"
printf 'Correlation threshold:    %s\n' "$threshold"
printf 'Geocode filter wavelength:%s m (~%s m geographic sampling)\n' \
    "$filter_wavelength" "$(awk -v value="$filter_wavelength" 'BEGIN {printf "%.6g", value/4}')"
printf 'LOS conversion:           LOS(mm) = unwrap(rad) * %s * -79.58\n' "$wavelength"
printf 'LOS scale factor:         %s mm/rad\n' "$los_factor"
if [[ "${#existing_geocode[@]}" -gt 0 ]]; then
    printf 'Existing geocoding:       %s (preserved)\n' "${existing_geocode[*]}"
else
    printf 'Existing geocoding:       none detected\n'
fi
if [[ "${#missing_outputs[@]}" -gt 0 ]]; then
    printf 'Missing outputs:          %s\n' "${missing_outputs[*]}"
else
    printf 'Missing outputs:          none\n'
fi
printf 'Output directory:         %s\n' "$pair_dir"
printf '%s\n' '========================================================================'

if [[ "$formal" -eq 0 ]]; then
    printf '[PREVIEW] No files were modified. Existing wrapped-product geocoding will not be repeated.\n'
    printf '[NEXT] ./run3.8_geocode_unwrap_LOS_LT1.sh 1 %s --filter-wavelength %s\n' \
        "$threshold" "$filter_wavelength"
    exit 0
fi

for command_name in gmt proj_ra2ll.csh; do
    command -v "$command_name" >/dev/null 2>&1 || die "$command_name was not found in PATH"
done

if [[ "${#missing_outputs[@]}" -eq 0 ]]; then
    printf '[SUCCESS] All Run 3.8 outputs already exist; nothing was regenerated.\n'
    printf '[LOS] %s/los_ll.grd\n' "$pair_dir"
    exit 0
fi

work_dir="$(mktemp -d "$pair_dir/run3.8_work.XXXXXX")"
log_file="$pair_dir/run3.8_geocode_LOS.log"
exec > >(tee -a "$log_file") 2>&1
printf '\n===== Run 3.8 %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')"

ln -s "$root_dir/topo/trans.dat" "$work_dir/trans.dat"
ln -s "$pair_dir/unwrap.grd" "$work_dir/unwrap.grd"
ln -s "$pair_dir/corr.grd" "$work_dir/corr.grd"
ln -s "$pair_dir/mask.grd" "$work_dir/mask.grd"
for name in "${managed_outputs[@]}"; do
    if [[ -s "$pair_dir/$name" ]]; then
        ln -s "$pair_dir/$name" "$work_dir/$name"
    fi
done
cd "$work_dir"

printf '[1/5] Prepare masked unwrapped phase...\n'
if [[ -s unwrap_mask.grd ]]; then
    printf '[REUSE] %s/unwrap_mask.grd\n' "$pair_dir"
else
    gmt grdmath corr.grd "$threshold" GE 0 NAN mask.grd MUL = mask2.grd
    unwrap_region="$(gmt grdinfo unwrap.grd -I-)"
    unwrap_inc="$(gmt grdinfo unwrap.grd -I)"
    gmt grdsample mask2.grd "$unwrap_region" "$unwrap_inc" -Gmask3.grd
    gmt grdmath unwrap.grd mask3.grd MUL = unwrap_mask.grd
fi

printf '[2/5] Convert unwrapped phase to radar-coordinate LOS displacement...\n'
if [[ -s los.grd ]]; then
    printf '[REUSE] %s/los.grd\n' "$pair_dir"
else
    gmt grdmath unwrap_mask.grd "$wavelength" MUL -79.58 MUL = los.grd
    gmt grdedit -D//"mm"/1///"$pair_name LOS displacement"/"positive equals range decrease" los.grd
fi

printf '[3/5] Geocode the masked unwrapped phase and generate geographic LOS...\n'
if [[ -s unwrap_mask_ll.grd ]]; then
    printf '[REUSE] %s/unwrap_mask_ll.grd\n' "$pair_dir"
else
    rm -f raln.grd ralt.grd
    proj_ra2ll.csh trans.dat unwrap_mask.grd unwrap_mask_ll.grd "$filter_wavelength"
    gmt grdedit -D//"radians"/1///"$pair_name geocoded masked unwrapped phase"/"Run 3.8" unwrap_mask_ll.grd
fi
if [[ -s los_ll.grd ]]; then
    printf '[REUSE] %s/los_ll.grd\n' "$pair_dir"
else
    gmt grdmath unwrap_mask_ll.grd "$wavelength" MUL -79.58 MUL = los_ll.grd
    gmt grdedit -D//"mm"/1///"$pair_name geocoded LOS displacement"/"positive equals range decrease" los_ll.grd
fi

make_los_plot() {
    local grid="$1" output="$2" title="$3" projection="$4"
    local lower upper cpt_step
    read -r lower upper < <(
        gmt grdinfo "$grid" -C -L2 | awk '{
            lower=$12-$13*2; upper=$12+$13*2
            if (lower == upper) {lower-=1; upper+=1}
            printf "%.12g %.12g\n", lower, upper
            exit
        }'
    )
    [[ -n "$lower" && -n "$upper" ]] || die "failed to determine plotting limits for $grid"
    cpt_step="$(awk -v lower="$lower" -v upper="$upper" 'BEGIN {printf "%.12g", (upper-lower)/100}')"
    gmt makecpt -Cpolar -Z -T"$lower"/"$upper"/"$cpt_step" -D > los.cpt
    gmt begin "$output" png
        gmt set MAP_FRAME_TYPE plain COLOR_NAN white
        gmt grdimage "$grid" "$projection" -Clos.cpt -Baf -BWSen+t"$title"
        gmt colorbar -DJTC+w5.5i/0.2i+h -Clos.cpt \
            -Bxaf+l"LOS displacement" -By+l"mm"
    gmt end
}

make_unwrap_plot() {
    local grid="$1" output="$2" title="$3"
    local lower upper cpt_step
    read -r lower upper < <(
        gmt grdinfo "$grid" -C -L2 | awk '{
            lower=$12-$13*2; upper=$12+$13*2
            if (lower == upper) {lower-=1; upper+=1}
            printf "%.12g %.12g\n", lower, upper
            exit
        }'
    )
    [[ -n "$lower" && -n "$upper" ]] || die "failed to determine plotting limits for $grid"
    cpt_step="$(awk -v lower="$lower" -v upper="$upper" 'BEGIN {printf "%.12g", (upper-lower)/100}')"
    gmt makecpt -Cseis -I -Z -T"$lower"/"$upper"/"$cpt_step" -D > unwrap_ll.cpt
    gmt begin "$output" png
        gmt set MAP_FRAME_TYPE plain COLOR_NAN white
        gmt grdimage "$grid" -JX7i -Cunwrap_ll.cpt -Baf -BWSen+t"$title"
        gmt colorbar -DJTC+w5.5i/0.2i+h -Cunwrap_ll.cpt \
            -Bxaf+l"Unwrapped phase" -By+l"rad"
    gmt end
}

printf '[4/5] Plot geocoded unwrapped phase and LOS PNGs...\n'
if [[ -s unwrap_mask_ll.png ]]; then
    printf '[REUSE] %s/unwrap_mask_ll.png\n' "$pair_dir"
else
    make_unwrap_plot unwrap_mask_ll.grd unwrap_mask_ll "$pair_name geocoded masked unwrapped phase"
fi
if [[ -s los.png ]]; then
    printf '[REUSE] %s/los.png\n' "$pair_dir"
else
    make_los_plot los.grd los "$pair_name LOS displacement in radar coordinates" -JX7i
fi
if [[ -s los_ll.png ]]; then
    printf '[REUSE] %s/los_ll.png\n' "$pair_dir"
else
    make_los_plot los_ll.grd los_ll "$pair_name geocoded LOS displacement" -JX7i
fi

printf '[5/5] Validate and install outputs...\n'
for name in "${managed_outputs[@]}"; do
    [[ -s "$name" ]] || die "missing generated output: $name"
    if [[ "$name" == *.grd ]]; then
        gmt grdinfo "$name" >/dev/null || die "invalid generated grid: $name"
    fi
    if [[ ! -L "$name" ]]; then
        mv "$name" "$pair_dir/$name"
        printf '[CREATED] %s/%s\n' "$pair_dir" "$name"
    fi
done

printf '[PRESERVED] Existing wrapped-phase/correlation/amplitude geocoding was not regenerated.\n'
printf '[SUCCESS] Radar LOS:      %s/los.grd\n' "$pair_dir"
printf '[SUCCESS] Geographic LOS: %s/los_ll.grd\n' "$pair_dir"
printf '[FIGURES] %s/unwrap_mask_ll.png\n' "$pair_dir"
printf '[FIGURES] %s/los.png  %s/los_ll.png\n' "$pair_dir" "$pair_dir"
printf '[LOG] %s\n' "$log_file"
printf '[NEXT] ./run3.9_detrend_LOS_LT1.sh\n'
