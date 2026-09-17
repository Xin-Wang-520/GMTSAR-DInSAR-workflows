#!/usr/bin/env bash
# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
# Make matched full-frame power, amplitude and post/pre dB-change grids.
# Preview is the default. Pass positional argument 1 to execute.
set -euo pipefail

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'HELP'
Full-frame LT-1 intensity-change comparison products

Usage:
  ./run2_make_intensity_change_LT1.sh
  ./run2_make_intensity_change_LT1.sh 1

Both scenes first use conv 1 1 with the same kernel selected from the master
PRM by the standard GMTSAR filter.csh PRF/rng_samp_rate rules. The script keeps
that result, then also creates and applies a 60 m Gaussian filter and keeps the
second result. Comparison PNGs are generated for both processing levels.
HELP
}

formal=0
if [[ $# -eq 0 ]]; then
    formal=0
elif [[ $# -eq 1 && "$1" == "1" ]]; then
    formal=1
elif [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
    usage
    exit 0
else
    usage
    exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
work_dir="$script_dir/SLC_full"
products_dir="$script_dir/products"
env_file="$script_dir/pair.env"
[[ -s "$env_file" ]] || die "missing pair.env; run Run 1 first"
# shellcheck disable=SC1090
source "$env_file"
[[ "$MASTER_STEM" =~ ^LT1_[0-9]{8}$ && "$ALIGNED_STEM" =~ ^LT1_[0-9]{8}_aligned$ ]] || die "invalid values in pair.env"

for cmd in conv gmt gmtsar_sharedir.csh make_gaussian_filter; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd was not found in PATH"
done
for prm in "$work_dir/${MASTER_STEM}.PRM" "$work_dir/${ALIGNED_STEM}.PRM"; do
    [[ -s "$prm" ]] || die "missing $prm"
done

master_prm="$work_dir/${MASTER_STEM}.PRM"
prf="$(awk '$1=="PRF" && $2=="=" {print $3; exit}' "$master_prm")"
rng_samp_rate="$(awk '$1=="rng_samp_rate" && $2=="=" {print $3; exit}' "$master_prm")"
[[ "$prf" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "invalid or missing PRF in $master_prm"
[[ "$rng_samp_rate" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "invalid or missing rng_samp_rate in $master_prm"

# Match the initial-filter selection in GMTSAR filter.csh. Decimation remains
# explicitly 1x1 for this full-frame amplitude-change workflow.
filter_name="$(awk -v prf="$prf" -v fs="$rng_samp_rate" 'BEGIN {
    if (fs > 110000000) print "gauss15x5"
    else if (fs > 20000000) {
        if (prf < 1000) print "gauss5x5"
        else print "gauss15x5"
    }
    else print "gauss15x3"
}')"
filter="$(gmtsar_sharedir.csh)/filters/$filter_name"
[[ -s "$filter" ]] || die "missing filter $filter"

printf '%s\n' '========================================================================'
printf 'LT-1 full-frame intensity change\n'
printf 'Mode:          %s\n' "$([[ "$formal" -eq 1 ]] && echo FORMAL || echo PREVIEW)"
printf 'Pre-event:     %s\n' "$MASTER_STEM"
printf 'Post-event:    %s\n' "$ALIGNED_STEM"
printf 'Master PRF:    %s Hz\n' "$prf"
printf 'Range rate:    %s Hz\n' "$rng_samp_rate"
printf 'Selected kernel: %s (GMTSAR filter.csh rule)\n' "$filter_name"
printf 'Initial pass:  conv 1 1 %s\n' "$filter"
printf 'Second pass:   conv 1 1 gauss_60 (60 m Gaussian)\n'
printf 'Output:        %s\n' "$products_dir"
printf 'Change:        10*log10(power_post/power_pre)\n'
printf 'Coordinates:   master radar coordinates\n'
printf '%s\n' '========================================================================'

if [[ "$formal" -eq 0 ]]; then
    printf '[PREVIEW] No files were modified.\n'
    printf '[NEXT] %s 1\n' "$0"
    exit 0
fi

if [[ -e "$products_dir" ]]; then
    [[ -d "$products_dir" && ! -L "$products_dir" ]] || die "unsafe existing output path: $products_dir"
    stamp="$(date +%Y%m%d_%H%M%S)"
    archive_dir="$script_dir/archive_products_$stamp"
    mkdir -p "$archive_dir"
    mv "$products_dir" "$archive_dir/products"
    printf '[ARCHIVE] Previous products moved to %s\n' "$archive_dir/products"
fi
mkdir -p "$products_dir/plots"
tmp_dir="$(mktemp -d "$products_dir/.tmp.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

(
    cd "$work_dir"
    conv 1 1 "$filter" "${MASTER_STEM}.PRM" "$tmp_dir/power_pre_raw.grd=bf"
    conv 1 1 "$filter" "${ALIGNED_STEM}.PRM" "$tmp_dir/power_post_raw.grd=bf"
)

gmt grdmath "$tmp_dir/power_pre_raw.grd=bf" 1 MUL = "$products_dir/power_pre_initial.grd"
gmt grdmath "$tmp_dir/power_post_raw.grd=bf" 1 MUL = "$products_dir/power_post_initial.grd"
gmt grdmath "$products_dir/power_pre_initial.grd" 0.5 POW = "$products_dir/amplitude_pre_initial.grd"
gmt grdmath "$products_dir/power_post_initial.grd" 0.5 POW = "$products_dir/amplitude_post_initial.grd"
gmt grdmath "$products_dir/power_post_initial.grd" "$products_dir/power_pre_initial.grd" DIV LOG10 10 MUL = "$products_dir/change_initial_db.grd"
gmt grdmath "$products_dir/change_initial_db.grd" ABS = "$products_dir/change_initial_abs_db.grd"

# Reproduce the optional second filtering level used in the interferogram
# workflow while retaining the initial-only products above.
(
    cd "$tmp_dir"
    make_gaussian_filter "$master_prm" 1 1 60 > ijdec_60.txt
)
gauss60="$tmp_dir/gauss_60"
[[ -s "$gauss60" ]] || die "make_gaussian_filter did not create $gauss60"
cp "$gauss60" "$products_dir/gauss_60"
cp "$tmp_dir/ijdec_60.txt" "$products_dir/ijdec_60.txt"
conv 1 1 "$gauss60" "$products_dir/power_pre_initial.grd" "$products_dir/power_pre_60m.grd"
conv 1 1 "$gauss60" "$products_dir/power_post_initial.grd" "$products_dir/power_post_60m.grd"
gmt grdmath "$products_dir/power_pre_60m.grd" 0.5 POW = "$products_dir/amplitude_pre_60m.grd"
gmt grdmath "$products_dir/power_post_60m.grd" 0.5 POW = "$products_dir/amplitude_post_60m.grd"
gmt grdmath "$products_dir/power_post_60m.grd" "$products_dir/power_pre_60m.grd" DIV LOG10 10 MUL = "$products_dir/change_60m_db.grd"
gmt grdmath "$products_dir/change_60m_db.grd" ABS = "$products_dir/change_60m_abs_db.grd"

# Log-power grids are retained because they make the pre/post images directly
# comparable with shared color scales.
gmt grdmath "$products_dir/power_pre_initial.grd" LOG10 10 MUL = "$products_dir/power_pre_initial_db.grd"
gmt grdmath "$products_dir/power_post_initial.grd" LOG10 10 MUL = "$products_dir/power_post_initial_db.grd"
gmt grdmath "$products_dir/power_pre_60m.grd" LOG10 10 MUL = "$products_dir/power_pre_60m_db.grd"
gmt grdmath "$products_dir/power_post_60m.grd" LOG10 10 MUL = "$products_dir/power_post_60m_db.grd"

initial_power_cpt="$tmp_dir/power_initial.cpt"
filtered_power_cpt="$tmp_dir/power_60m.cpt"
change_cpt="$tmp_dir/change.cpt"
gmt grd2cpt "$products_dir/power_pre_initial_db.grd" "$products_dir/power_post_initial_db.grd" -Cgray -Z > "$initial_power_cpt"
gmt grd2cpt "$products_dir/power_pre_60m_db.grd" "$products_dir/power_post_60m_db.grd" -Cgray -Z > "$filtered_power_cpt"
gmt makecpt -Cpolar -T-10/10/0.25 -Z > "$change_cpt"

plot_grid() {
    local grid="$1" cpt="$2" output_base="$3" title="$4" label="$5"
    gmt begin "$output_base" png
        gmt grdimage "$grid" -JX16c -C"$cpt" -Baf -BWSen+t"$title"
        gmt colorbar -DJBC+w11c/0.35c+h+o0c/0.8c -C"$cpt" -Baf+l"$label"
    gmt end
}

plot_grid "$products_dir/power_pre_initial_db.grd" "$initial_power_cpt" "$products_dir/plots/power_pre_initial_db" "Pre-event power: initial filter" "Relative power (dB)"
plot_grid "$products_dir/power_post_initial_db.grd" "$initial_power_cpt" "$products_dir/plots/power_post_initial_db" "Post-event power: initial filter" "Relative power (dB)"
plot_grid "$products_dir/change_initial_db.grd" "$change_cpt" "$products_dir/plots/change_initial_db" "Post/pre change: initial filter" "Power change (dB)"
plot_grid "$products_dir/power_pre_60m_db.grd" "$filtered_power_cpt" "$products_dir/plots/power_pre_60m_db" "Pre-event power: additional 60 m filter" "Relative power (dB)"
plot_grid "$products_dir/power_post_60m_db.grd" "$filtered_power_cpt" "$products_dir/plots/power_post_60m_db" "Post-event power: additional 60 m filter" "Relative power (dB)"
plot_grid "$products_dir/change_60m_db.grd" "$change_cpt" "$products_dir/plots/change_60m_db" "Post/pre change: additional 60 m filter" "Power change (dB)"

for grid in power_pre_initial.grd power_post_initial.grd amplitude_pre_initial.grd amplitude_post_initial.grd change_initial_db.grd change_initial_abs_db.grd power_pre_60m.grd power_post_60m.grd amplitude_pre_60m.grd amplitude_post_60m.grd change_60m_db.grd change_60m_abs_db.grd; do
    [[ -s "$products_dir/$grid" ]] || die "missing output $products_dir/$grid"
done
for figure in power_pre_initial_db.png power_post_initial_db.png change_initial_db.png power_pre_60m_db.png power_post_60m_db.png change_60m_db.png; do
    [[ -s "$products_dir/plots/$figure" ]] || die "missing plot $products_dir/plots/$figure"
done

printf '[SUCCESS] Initial-only and additional-60m full-frame products and plots created.\n'
printf '[OUTPUT]  %s\n' "$products_dir"
printf '[PLOTS]   %s/plots\n' "$products_dir"
printf '[DISPLAY] Change plots are clipped to -10/+10 dB; GRD files retain full values.\n'
printf '[NOTE]    Products are uncalibrated relative power in radar coordinates.\n'
