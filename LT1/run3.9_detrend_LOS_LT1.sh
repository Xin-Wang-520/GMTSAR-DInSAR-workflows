#!/usr/bin/env bash
# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
# Run 3.9: remove a robust six-parameter long-wavelength trend from LOS.
set -euo pipefail

export LC_ALL=C
export LANG=C
export LANGUAGE=C

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'HELP'
Run 3.9: detrend the geocoded LT-1 LOS displacement

Usage:
  ./run3.9_detrend_LOS_LT1.sh
  ./run3.9_detrend_LOS_LT1.sh 1

No arguments run a read-only preview. Add positional 1 for formal execution.

Method copied from the earlier LT-1 batch workflow:
  gmt grdtrend los_ll.grd -N6r \
      -Tlos_ll_trend.grd \
      -Dlos_ll_detrend.grd

-N6 fits a six-parameter two-dimensional quadratic surface. The r modifier
uses robust iterative fitting. This removes a possible ionospheric/orbital
long-wavelength ramp, but it is not a split-spectrum or TEC-based ionospheric
correction. A broad real deformation signal can also enter the fitted trend.

Outputs:
  intf_all/DATE1_DATE2/los_ll_detrend.grd
  intf_all/DATE1_DATE2/los_ll_detrend_comparison.png
  intf_all/DATE1_DATE2/los_ll_detrend.png

los_ll_trend.grd is temporary and is deleted after plotting.

The comparison has three panels:
  original LOS | fitted N6r trend | detrended LOS
HELP
}

formal=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        1) formal=1; shift ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
done

for command_name in awk basename find gmt sort wc; do
    command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
done

root_dir="$(pwd -P)"
[[ -d "$root_dir/intf_all" ]] || die "intf_all directory not found; complete Run 3.3 first"
pair_list="$(mktemp "${TMPDIR:-/tmp}/run3.9_pairs.XXXXXX")"
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
input_grid="$pair_dir/los_ll.grd"
trend_grid="$pair_dir/los_ll_trend.grd"
detrend_grid="$pair_dir/los_ll_detrend.grd"
comparison_png="$pair_dir/los_ll_detrend_comparison.png"
detrend_png="$pair_dir/los_ll_detrend.png"

[[ -s "$input_grid" ]] || die "missing or empty $input_grid; complete Run 3.8 first"
input_info="$(gmt grdinfo "$input_grid" -Cn | awk '{print $1,$2,$3,$4,$5,$6,$9,$10; exit}')"
[[ -n "$input_info" ]] || die "failed to inspect $input_grid"

printf '%s\n' '========================================================================'
printf 'LT-1 Run 3.9 geocoded LOS long-wavelength detrending\n'
printf 'Mode:             %s\n' "$([[ "$formal" -eq 1 ]] && echo FORMAL || echo PREVIEW)"
printf 'Pair:             %s\n' "$pair_name"
printf 'Input:            %s\n' "$input_grid"
printf 'Input grid:       %s\n' "$input_info"
printf 'Trend model:      N6r (robust six-parameter quadratic surface)\n'
printf 'Command:          gmt grdtrend los_ll.grd -N6r -Tlos_ll_trend.grd -Dlos_ll_detrend.grd\n'
printf 'Trend grid:       temporary (deleted after plotting)\n'
printf 'Detrended output: %s\n' "$detrend_grid"
printf 'Comparison PNG:   %s\n' "$comparison_png"
printf 'Detrended PNG:    %s\n' "$detrend_png"
printf 'Interpretation:   possible ionospheric/orbital long-wave trend removal\n'
printf '%s\n' '========================================================================'

if [[ "$formal" -eq 0 ]]; then
    printf '[PREVIEW] No files were modified.\n'
    printf '[CAUTION] Inspect all three panels; broad real deformation may be removed by N6r.\n'
    printf '[NEXT] ./run3.9_detrend_LOS_LT1.sh 1\n'
    exit 0
fi

archive_dir="$root_dir/archive_run3.9/$(date +%Y%m%dT%H%M%S)/$pair_name"
archive_count=0
for existing in "$detrend_grid" "$comparison_png" "$detrend_png"; do
    if [[ -e "$existing" ]]; then
        mkdir -p "$archive_dir"
        mv "$existing" "$archive_dir/"
        archive_count=$((archive_count + 1))
    fi
done
[[ "$archive_count" -eq 0 ]] || printf '[ARCHIVE] Moved %s previous Run 3.9 output(s) to %s\n' "$archive_count" "$archive_dir"
if [[ -e "$trend_grid" ]]; then
    rm -f "$trend_grid"
    printf '[CLEANUP] Removed old intermediate trend grid: %s\n' "$trend_grid"
fi

work_dir="$(mktemp -d "$pair_dir/run3.9_work.XXXXXX")"
trend_tmp="$work_dir/los_ll_trend.grd"
detrend_tmp="$work_dir/los_ll_detrend.grd"

printf '[1/4] Fit and remove the robust N6r trend...\n'
gmt grdtrend "$input_grid" -N6r -T"$trend_tmp" -D"$detrend_tmp"
[[ -s "$trend_tmp" && -s "$detrend_tmp" ]] || die "grdtrend did not generate both output grids"

grid_signature() {
    gmt grdinfo "$1" -Cn | awk '{print $1,$2,$3,$4,$7,$8,$9,$10; exit}'
}
input_signature="$(grid_signature "$input_grid")"
[[ "$(grid_signature "$trend_tmp")" == "$input_signature" ]] || die "trend-grid geometry differs from los_ll.grd"
[[ "$(grid_signature "$detrend_tmp")" == "$input_signature" ]] || die "detrended-grid geometry differs from los_ll.grd"
gmt grdedit -D//"mm"/1///"$pair_name fitted N6r LOS trend"/"Run 3.9" "$trend_tmp"
gmt grdedit -D//"mm"/1///"$pair_name detrended LOS displacement"/"positive equals range decrease" "$detrend_tmp"

symmetric_limit() {
    awk '{
        for (i=1; i<=NF; i++) {
            value=$i
            if (value<0) value=-value
            if (value>maximum) maximum=value
        }
    }
    END {
        if (!(maximum>0)) maximum=1
        printf "%.12g", maximum
    }'
}
z_limits() {
    gmt grdinfo "$1" -Cn | awk '{print $5,$6; exit}'
}

printf '[2/4] Determine common plotting scales...\n'
los_limit="$(printf '%s\n%s\n' "$(z_limits "$input_grid")" "$(z_limits "$detrend_tmp")" | symmetric_limit)"
trend_limit="$(z_limits "$trend_tmp" | symmetric_limit)"
detrend_limit="$(z_limits "$detrend_tmp" | symmetric_limit)"
los_step="$(awk -v value="$los_limit" 'BEGIN {printf "%.12g", 2*value/100}')"
trend_step="$(awk -v value="$trend_limit" 'BEGIN {printf "%.12g", 2*value/100}')"
detrend_step="$(awk -v value="$detrend_limit" 'BEGIN {printf "%.12g", 2*value/100}')"
gmt makecpt -Cpolar -T-"$los_limit"/"$los_limit"/"$los_step" -Z > "$work_dir/los.cpt"
gmt makecpt -Cpolar -T-"$trend_limit"/"$trend_limit"/"$trend_step" -Z > "$work_dir/trend.cpt"
gmt makecpt -Cpolar -T-"$detrend_limit"/"$detrend_limit"/"$detrend_step" -Z > "$work_dir/detrend.cpt"

read -r west east south north < <(gmt grdinfo "$input_grid" -Cn | awk '{print $1,$2,$3,$4; exit}')
panel_width="3.5"
panel_height="$(awk -v width="$panel_width" -v west="$west" -v east="$east" -v south="$south" -v north="$north" '
    BEGIN {
        x=east-west; y=north-south
        if (!(x>0 && y>0)) exit 1
        height=width*y/x
        if (height<1.8) height=1.8
        if (height>6.0) height=6.0
        printf "%.4f", height
    }')" || die "failed to calculate the plot aspect ratio"

printf '[3/4] Plot original, trend and detrended LOS...\n'
plot_base="$work_dir/los_ll_detrend_comparison"
gmt begin "$plot_base" png
    gmt set MAP_TITLE_OFFSET 8p FONT_TITLE 12p FONT_HEADING 15p \
        FONT_LABEL 10p FONT_ANNOT_PRIMARY 8p COLOR_NAN white
    gmt subplot begin 1x3 -Fs"${panel_width}i/${panel_height}i" -M0.12i

    gmt subplot set 0,0
    gmt grdimage "$input_grid" -C"$work_dir/los.cpt" \
        -Bxa+l"Longitude" -Bya+l"Latitude" -BWSen+t"Original LOS"
    gmt colorbar -C"$work_dir/los.cpt" -DJBC+w2.5i/0.12i+h+o0i/0.38i \
        -Baf+l"LOS (mm)"

    gmt subplot set 0,1
    gmt grdimage "$trend_tmp" -C"$work_dir/trend.cpt" \
        -Bxa+l"Longitude" -Bya -BWSen+t"Fitted N6r trend"
    gmt colorbar -C"$work_dir/trend.cpt" -DJBC+w2.5i/0.12i+h+o0i/0.38i \
        -Baf+l"Trend (mm)"

    gmt subplot set 0,2
    gmt grdimage "$detrend_tmp" -C"$work_dir/los.cpt" \
        -Bxa+l"Longitude" -Bya -BWSen+t"Detrended LOS"
    gmt colorbar -C"$work_dir/los.cpt" -DJBC+w2.5i/0.12i+h+o0i/0.38i \
        -Baf+l"LOS (mm)"

    gmt subplot end
gmt end
[[ -s "$plot_base.png" ]] || die "comparison PNG was not generated"

detrend_plot_base="$work_dir/los_ll_detrend"
gmt begin "$detrend_plot_base" png
    gmt set MAP_FRAME_TYPE plain FONT_TITLE 13p FONT_LABEL 11p \
        FONT_ANNOT_PRIMARY 9p COLOR_NAN white
    gmt grdimage "$detrend_tmp" -JX7i -C"$work_dir/detrend.cpt" \
        -Bxa+l"Longitude" -Bya+l"Latitude" \
        -BWSen+t"LT-1 $pair_name detrended LOS (-N6r)"
    gmt colorbar -C"$work_dir/detrend.cpt" -DJTC+w5.5i/0.2i+h \
        -Baf+l"Detrended LOS displacement" -By+l"mm"
gmt end
[[ -s "$detrend_plot_base.png" ]] || die "detrended LOS PNG was not generated"

printf '[4/4] Install and report outputs...\n'
mv "$detrend_tmp" "$detrend_grid"
mv "$plot_base.png" "$comparison_png"
mv "$detrend_plot_base.png" "$detrend_png"
rm -f "$trend_tmp"

printf '[SUCCESS] Detrended LOS:  %s\n' "$detrend_grid"
printf '[FIGURE]  %s\n' "$comparison_png"
printf '[FIGURE]  %s\n' "$detrend_png"
printf '[CLEANUP] Temporary los_ll_trend.grd was removed after plotting.\n'
printf '[CAUTION] Treat this as long-wave detrending, not a unique ionospheric correction.\n'
printf '[NEXT] Inspect the comparison before using los_ll_detrend.grd.\n'
