#!/usr/bin/env bash
# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
# Geocode existing GMTSAR amp1/amp2 grids and calculate post/pre power change.
# Assumption requested for this LT-1 workflow: earlier PRM = amp1 = pre-event;
# later PRM = amp2 = post-event.
# Preview is the default. Pass positional argument 1 to execute.
set -euo pipefail

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'HELP'
Geocode existing LT-1 amp1/amp2 and plot pre/post change

Run from the processing-project root (the directory containing intf_all):

  ./run_amp_geocode_change_LT1.sh
  ./run_amp_geocode_change_LT1.sh 1

Optional:

  ./run_amp_geocode_change_LT1.sh [1] --pair-dir /path/to/intf_all/PAIR
  ./run_amp_geocode_change_LT1.sh [1] --filter-wavelength 60
  ./run_amp_geocode_change_LT1.sh [1] --output-dir /path/to/output

Default behavior:
  - Automatically selects the only directory under intf_all/.
  - Sorts the two LT1_YYYYMMDD.PRM files by date.
  - Treats amp1 as the earlier/pre-event image.
  - Treats amp2 as the later/post-event image.
  - FLIPUD is applied before proj_ra2ll.csh.
  - A filter wavelength of 60 m gives about 15 m geographic grid sampling.
  - Existing outputs are archived instead of deleted.
HELP
}

formal=0
pair_dir_arg=""
output_dir_arg=""
filter_wavelength="60"

while [[ $# -gt 0 ]]; do
    case "$1" in
        1) formal=1; shift ;;
        --pair-dir)
            [[ $# -ge 2 ]] || die "--pair-dir requires a directory"
            pair_dir_arg="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || die "--output-dir requires a directory"
            output_dir_arg="$2"
            shift 2
            ;;
        --filter-wavelength)
            [[ $# -ge 2 ]] || die "--filter-wavelength requires a value"
            filter_wavelength="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
done

[[ "$filter_wavelength" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "invalid filter wavelength: $filter_wavelength"

project_dir="$(pwd -P)"
if [[ -n "$pair_dir_arg" ]]; then
    [[ -d "$pair_dir_arg" ]] || die "pair directory not found: $pair_dir_arg"
    pair_dir="$(cd -- "$pair_dir_arg" && pwd -P)"
else
    [[ -d "$project_dir/intf_all" ]] || die "missing $project_dir/intf_all; run from the project root or use --pair-dir"
    pair_list="$(mktemp "${TMPDIR:-/tmp}/lt1_amp_pairs.XXXXXX")"
    trap 'rm -f "$pair_list"' EXIT
    find "$project_dir/intf_all" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort > "$pair_list"
    pair_count="$(wc -l < "$pair_list" | awk '{print $1}')"
    [[ "$pair_count" -eq 1 ]] || die "expected one intf_all pair, found $pair_count; use --pair-dir"
    pair_dir="$(sed -n '1p' "$pair_list")"
    rm -f "$pair_list"
    trap - EXIT
fi

pair_name="$(basename "$pair_dir")"
for input in amp1.grd amp2.grd trans.dat; do
    [[ -s "$pair_dir/$input" ]] || die "missing or empty $pair_dir/$input"
done

for cmd in gmt proj_ra2ll.csh; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd was not found in PATH"
done

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/lt1_amp_geocode.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT INT TERM
prm_list="$tmp_root/prms.list"
find "$pair_dir" -maxdepth 1 \( -type f -o -type l \) -name 'LT1_????????.PRM' -print |
    awk -F/ '{name=$NF; if (name ~ /^LT1_[0-9]{8}\.PRM$/) print}' |
    LC_ALL=C sort > "$prm_list"
prm_count="$(wc -l < "$prm_list" | awk '{print $1}')"
[[ "$prm_count" -eq 2 ]] || die "expected exactly two LT1_YYYYMMDD.PRM files in $pair_dir; found $prm_count"

pre_prm="$(sed -n '1p' "$prm_list")"
post_prm="$(sed -n '2p' "$prm_list")"
pre_name="$(basename "$pre_prm" .PRM)"
post_name="$(basename "$post_prm" .PRM)"
pre_date="${pre_name#LT1_}"
post_date="${post_name#LT1_}"
[[ "$pre_date" < "$post_date" ]] || die "PRM dates are not strictly chronological"

if [[ -n "$output_dir_arg" ]]; then
    output_dir="$output_dir_arg"
else
    output_dir="$project_dir/amplitude_results/$pair_name"
fi
output_parent="$(dirname "$output_dir")"

pix_m="$(awk -v w="$filter_wavelength" 'BEGIN {printf "%.6g",w/4}')"

# -Cn emits numeric columns in the order x_min x_max y_min y_max z_min z_max
# dx dy nx ny. Compare x/y geometry only; z ranges legitimately differ.
amp1_sig="$(gmt grdinfo "$pair_dir/amp1.grd" -Cn | awk '{print $1,$2,$3,$4,$7,$8,$9,$10}')"
amp2_sig="$(gmt grdinfo "$pair_dir/amp2.grd" -Cn | awk '{print $1,$2,$3,$4,$7,$8,$9,$10}')"
[[ "$amp1_sig" == "$amp2_sig" ]] || die "amp1.grd and amp2.grd do not have matching radar grids"

printf '%s\n' '========================================================================'
printf 'LT-1 existing-amplitude geocode and change workflow\n'
printf 'Mode:                 %s\n' "$([[ "$formal" -eq 1 ]] && echo FORMAL || echo PREVIEW)"
printf 'Pair directory:       %s\n' "$pair_dir"
printf 'Earlier PRM:          %s\n' "$(basename "$pre_prm")"
printf 'Later PRM:            %s\n' "$(basename "$post_prm")"
printf 'amp1 assignment:      PRE  (%s)\n' "$pre_date"
printf 'amp2 assignment:      POST (%s)\n' "$post_date"
printf 'Filter wavelength:    %s m\n' "$filter_wavelength"
printf 'Geographic sampling:  about %s m (= wavelength/4)\n' "$pix_m"
printf 'Output directory:     %s\n' "$output_dir"
printf 'Change definition:    10*log10(power_post/power_pre)\n'
printf '%s\n' '========================================================================'

if [[ "$formal" -eq 0 ]]; then
    printf '[PREVIEW] No files were modified.\n'
    if [[ -n "$pair_dir_arg" ]]; then
        printf '[NEXT]    %s 1 --pair-dir %q\n' "$0" "$pair_dir"
    else
        printf '[NEXT]    %s 1\n' "$0"
    fi
    exit 0
fi

if [[ -e "$output_dir" ]]; then
    [[ -d "$output_dir" && ! -L "$output_dir" ]] || die "unsafe existing output path: $output_dir"
    mkdir -p "$output_parent"
    stamp="$(date +%Y%m%d_%H%M%S)"
    archive_dir="${output_dir}_archive_${stamp}"
    mv "$output_dir" "$archive_dir"
    printf '[ARCHIVE] Previous result moved to %s\n' "$archive_dir"
fi
mkdir -p "$output_dir/grd" "$output_dir/png"

work_dir="$tmp_root/work"
mkdir -p "$work_dir"

printf '[1/5] Flip amp1/amp2 to GMTSAR geocoding orientation...\n'
gmt grdmath "$pair_dir/amp1.grd" FLIPUD = "$work_dir/power_pre_ra.grd"
gmt grdmath "$pair_dir/amp2.grd" FLIPUD = "$work_dir/power_post_ra.grd"

printf '[2/5] Geocode both power grids using filter wavelength %s m...\n' "$filter_wavelength"
(
    cd "$work_dir"
    proj_ra2ll.csh "$pair_dir/trans.dat" power_pre_ra.grd power_pre_ll_raw.grd "$filter_wavelength"
    proj_ra2ll.csh "$pair_dir/trans.dat" power_post_ra.grd power_post_ll_raw.grd "$filter_wavelength"
)

# Force the post-event output onto the exact pre-event grid if tiny rounding
# differences occur between the two independent projections.
pre_ll="$work_dir/power_pre_ll_raw.grd"
post_ll_raw="$work_dir/power_post_ll_raw.grd"
inc_opt="$(gmt grdinfo -I "$pre_ll")"
gmt grdsample "$post_ll_raw" -R"$pre_ll" "$inc_opt" -G"$work_dir/power_post_ll.grd"
gmt grdmath "$pre_ll" 1 MUL = "$output_dir/grd/power_pre_${pre_date}_ll.grd"
gmt grdmath "$work_dir/power_post_ll.grd" 1 MUL = "$output_dir/grd/power_post_${post_date}_ll.grd"

pre_out="$output_dir/grd/power_pre_${pre_date}_ll.grd"
post_out="$output_dir/grd/power_post_${post_date}_ll.grd"

printf '[3/5] Calculate valid mask, log-power and post/pre change...\n'
gmt grdmath "$pre_out" 0 GT "$post_out" 0 GT MUL 0 NAN = "$output_dir/grd/valid_both_ll.grd"
valid="$output_dir/grd/valid_both_ll.grd"
gmt grdmath "$pre_out" LOG10 10 MUL "$valid" MUL = "$output_dir/grd/power_pre_${pre_date}_ll_db.grd"
gmt grdmath "$post_out" LOG10 10 MUL "$valid" MUL = "$output_dir/grd/power_post_${post_date}_ll_db.grd"
gmt grdmath "$post_out" "$pre_out" DIV LOG10 10 MUL "$valid" MUL = "$output_dir/grd/change_post_over_pre_ll_db.grd"
gmt grdmath "$output_dir/grd/change_post_over_pre_ll_db.grd" ABS = "$output_dir/grd/change_absolute_ll_db.grd"
gmt grdmath "$post_out" "$pre_out" DIV "$valid" MUL = "$output_dir/grd/ratio_post_over_pre_ll.grd"
gmt grdmath "$post_out" "$pre_out" SUB "$valid" MUL = "$output_dir/grd/difference_post_minus_pre_ll.grd"

pre_db="$output_dir/grd/power_pre_${pre_date}_ll_db.grd"
post_db="$output_dir/grd/power_post_${post_date}_ll_db.grd"
change_db="$output_dir/grd/change_post_over_pre_ll_db.grd"

printf '[4/5] Build common color scales...\n'
power_cpt="$work_dir/power_common.cpt"
change_cpt="$work_dir/change_common.cpt"
gmt grd2cpt "$pre_db" "$post_db" -Cgray -Z > "$power_cpt"
gmt makecpt -Cpolar -T-10/10/0.25 -Z > "$change_cpt"
cp "$power_cpt" "$output_dir/power_common.cpt"
cp "$change_cpt" "$output_dir/change_common.cpt"

plot_grid() {
    local grid="$1" cpt="$2" output_base="$3" title="$4" label="$5"
    gmt begin "$output_base" png
        gmt grdimage "$grid" -JM15c -C"$cpt" -Baf -BWSen+t"$title"
        gmt colorbar -DJBC+w10c/0.35c+h+o0c/0.8c -C"$cpt" -Baf+l"$label"
    gmt end
}

printf '[5/5] Plot pre-event, post-event and change maps...\n'
plot_grid "$pre_db" "$power_cpt" "$output_dir/png/power_pre_${pre_date}_ll_db" "Pre-event power ${pre_date}" "Relative power (dB)"
plot_grid "$post_db" "$power_cpt" "$output_dir/png/power_post_${post_date}_ll_db" "Post-event power ${post_date}" "Relative power (dB)"
plot_grid "$change_db" "$change_cpt" "$output_dir/png/change_post_over_pre_ll_db" "Post/pre power change ${post_date}/${pre_date}" "Power change (dB)"

# One-row, three-column comparison. The first two panels share power_common.cpt;
# the change panel uses the fixed -10/+10 dB diverging scale.
comparison_base="$output_dir/png/comparison_pre_post_change_1x3"
gmt begin "$comparison_base" png
    gmt subplot begin 1x3 -Fs8c/8c -M0.45c -A+jTL+o0.1c/0.1c
        gmt subplot set 0
        gmt grdimage "$pre_db" '-JM?' -C"$power_cpt" -Baf -BWSen+t"Pre ${pre_date}"
        gmt colorbar -DJBC+w5.8c/0.25c+h+o0c/0.55c -C"$power_cpt" -Baf+l"Relative power (dB)"

        gmt subplot set 1
        gmt grdimage "$post_db" '-JM?' -C"$power_cpt" -Baf -BWSen+t"Post ${post_date}"
        gmt colorbar -DJBC+w5.8c/0.25c+h+o0c/0.55c -C"$power_cpt" -Baf+l"Relative power (dB)"

        gmt subplot set 2
        gmt grdimage "$change_db" '-JM?' -C"$change_cpt" -Baf -BWSen+t"Post / pre change"
        gmt colorbar -DJBC+w5.8c/0.25c+h+o0c/0.55c -C"$change_cpt" -Bxa2f1+l"Power change (dB)"
    gmt subplot end
gmt end

# One-row raw linear-power comparison. This intentionally does not use dB:
# panels 1/2 are raw relative power and panel 3 is the linear post/pre ratio.
raw_power_cpt="$work_dir/power_raw_common.cpt"
raw_ratio_cpt="$work_dir/ratio_raw.cpt"
gmt grd2cpt "$pre_out" "$post_out" -Cgray -Z > "$raw_power_cpt"
gmt makecpt -Cpolar -T0.5/1.5/0.025 -Z > "$raw_ratio_cpt"
raw_comparison_base="$output_dir/png/comparison_pre_post_ratio_raw_1x3"
gmt begin "$raw_comparison_base" png
    gmt subplot begin 1x3 -Fs8c/8c -M0.45c -A+jTL+o0.1c/0.1c
        gmt subplot set 0
        gmt grdimage "$pre_out" '-JM?' -C"$raw_power_cpt" -Baf -BWSen+t"Pre raw power ${pre_date}"
        gmt colorbar -DJBC+w5.8c/0.25c+h+o0c/0.55c -C"$raw_power_cpt" -Baf+l"Raw relative power"

        gmt subplot set 1
        gmt grdimage "$post_out" '-JM?' -C"$raw_power_cpt" -Baf -BWSen+t"Post raw power ${post_date}"
        gmt colorbar -DJBC+w5.8c/0.25c+h+o0c/0.55c -C"$raw_power_cpt" -Baf+l"Raw relative power"

        gmt subplot set 2
        gmt grdimage "$output_dir/grd/ratio_post_over_pre_ll.grd" '-JM?' -C"$raw_ratio_cpt" -Baf -BWSen+t"Raw post / pre ratio"
        gmt colorbar -DJBC+w5.8c/0.25c+h+o0c/0.55c -C"$raw_ratio_cpt" -Bxa0.25f0.25+l"Linear ratio"
    gmt subplot end
gmt end

cat > "$output_dir/processing_summary.txt" <<EOF
Pair directory: $pair_dir
Pre-event PRM / amp1: $(basename "$pre_prm")
Post-event PRM / amp2: $(basename "$post_prm")
Geocoding command parameter: $filter_wavelength m
Approximate output sampling: $pix_m m
Change definition: 10*log10(power_post/power_pre)
Raw ratio: power_post/power_pre
Raw difference: power_post-power_pre
Change PNG display range: -10 to +10 dB
Power type: relative, uncalibrated GMTSAR power
EOF

for required in "$pre_out" "$post_out" "$pre_db" "$post_db" "$change_db" \
    "$output_dir/grd/ratio_post_over_pre_ll.grd" \
    "$output_dir/grd/difference_post_minus_pre_ll.grd" \
    "$output_dir/png/power_pre_${pre_date}_ll_db.png" \
    "$output_dir/png/power_post_${post_date}_ll_db.png" \
    "$output_dir/png/change_post_over_pre_ll_db.png" \
    "$output_dir/png/comparison_pre_post_change_1x3.png" \
    "$output_dir/png/comparison_pre_post_ratio_raw_1x3.png"; do
    [[ -s "$required" ]] || die "missing expected output: $required"
done

printf '[SUCCESS] Existing amp1/amp2 were geocoded and compared.\n'
printf '[GRIDS]   %s/grd\n' "$output_dir"
printf '[IMAGES]  %s/png\n' "$output_dir"
printf '[NOTE]    The change PNG is clipped to -10/+10 dB; its GRD retains full values.\n'
