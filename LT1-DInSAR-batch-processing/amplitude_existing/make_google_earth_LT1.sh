#!/usr/bin/env bash
# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
set -euo pipefail

# Create Google Earth KML/PNG products from the existing geocoded amplitude grids.
# Usage: ./make_google_earth_LT1.sh [amplitude_results/PAIR_DIR]

project_dir="$(pwd -P)"
if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [amplitude_results/PAIR_DIR]" >&2
    exit 2
fi

if [[ $# -eq 1 ]]; then
    result_dir="$1"
    [[ "$result_dir" = /* ]] || result_dir="$project_dir/$result_dir"
else
    result_count=0
    while IFS= read -r d; do
        result_dir="$d"
        result_count=$((result_count + 1))
    done < <(find "$project_dir/amplitude_results" -mindepth 1 -maxdepth 1 -type d -name '*_*' 2>/dev/null | sort)
    [[ $result_count -eq 1 ]] || { echo "Specify the amplitude result directory" >&2; exit 1; }
fi

grd_dir="$result_dir/grd"
out_dir="$result_dir/google_earth"
mkdir -p "$out_dir"
command -v grd2kml.csh >/dev/null || { echo "grd2kml.csh not found in GMTSAR PATH" >&2; exit 1; }

pre_grid=("$grd_dir"/power_pre_*_ll_db.grd)
post_grid=("$grd_dir"/power_post_*_ll_db.grd)
change_grid=("$grd_dir/change_post_over_pre_ll_db.grd")
[[ -f "${pre_grid[0]}" && -f "${post_grid[0]}" && -f "${change_grid[0]}" ]] || {
    echo "Required dB grids are missing in $grd_dir" >&2; exit 1;
}
power_cpt="$result_dir/power_common.cpt"
change_cpt="$result_dir/change_common.cpt"
[[ -f "$power_cpt" && -f "$change_cpt" ]] || { echo "CPT files are missing in $result_dir" >&2; exit 1; }

make_one() {
    local grid="$1" cpt="$2" stem="$3"
    local tmp="$out_dir/.tmp_$stem"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    gmt grdmath "$grid" 1 MUL = "$tmp/$stem.grd"
    (cd "$tmp" && grd2kml.csh "$stem" "$cpt")
    mv "$tmp/$stem.kml" "$out_dir/$stem.kml"
    mv "$tmp/$stem.png" "$out_dir/$stem.png"
    rm -rf "$tmp"
}

make_one "${pre_grid[0]}" "$power_cpt" "pre_event_db"
make_one "${post_grid[0]}" "$power_cpt" "post_event_db"
make_one "${change_grid[0]}" "$change_cpt" "change_post_over_pre_db"

for stem in pre_event_db post_event_db change_post_over_pre_db; do
    kmz="$out_dir/${stem}.kmz"
    rm -f "$kmz"
    (cd "$out_dir" && zip -q "$kmz" "$stem.kml" "$stem.png")
done
echo "Created Google Earth products in: $out_dir"
ls -lh "$out_dir"/*.kml "$out_dir"/*.png "$out_dir"/*.kmz
