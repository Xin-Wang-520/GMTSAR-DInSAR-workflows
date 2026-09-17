#!/usr/bin/env bash
# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
# Align the complete LT-1 repeat SLC to the complete master SLC.
# Preview is the default. Pass positional argument 1 to execute.
set -euo pipefail

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'HELP'
Full-frame LT-1 alignment for amplitude-change analysis

Usage:
  ./run1_align_full_frame_LT1.sh
  ./run1_align_full_frame_LT1.sh 1
  ./run1_align_full_frame_LT1.sh --project /path/to/processing-directory
  ./run1_align_full_frame_LT1.sh 1 --project /path/to/processing-directory

The default input project is the parent directory. Use --project when data.list
and raw/ are stored elsewhere. The script does not call cut_slc and does not
modify the input raw/. Formal mode creates/rebuilds SLC_full/ after archiving
any previous SLC_full directory inside this workflow folder.
HELP
}

formal=0
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_arg=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        1) formal=1; shift ;;
        --project)
            [[ $# -ge 2 ]] || die "--project requires a directory"
            project_arg="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
done
if [[ -n "$project_arg" ]]; then
    [[ -d "$project_arg" ]] || die "project directory not found: $project_arg"
    project_dir="$(cd -- "$project_arg" && pwd -P)"
else
    project_dir="$(cd -- "$script_dir/.." && pwd -P)"
fi
raw_dir="$project_dir/raw"
data_list="$project_dir/data.list"
work_dir="$script_dir/SLC_full"

[[ -s "$data_list" ]] || die "missing or empty $data_list"
[[ -d "$raw_dir" ]] || die "missing $raw_dir"
for cmd in SAT_baseline xcorr fitoffset.csh resamp; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd was not found in PATH"
done

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/lt1_amp_align.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
scene_list="$tmp_dir/scenes.list"
awk 'NF && $1 !~ /^#/ {print $1}' "$data_list" > "$scene_list"
[[ "$(wc -l < "$scene_list" | awk '{print $1}')" -eq 2 ]] || die "data.list must contain exactly two acquisitions"
master="$(sed -n '1p' "$scene_list")"
repeat="$(sed -n '2p' "$scene_list")"
[[ "$master" =~ ^LT1_[0-9]{8}$ && "$repeat" =~ ^LT1_[0-9]{8}$ ]] || die "unexpected scene names in data.list"

for stem in "$master" "$repeat"; do
    for suffix in PRM SLC LED; do
        [[ -s "$raw_dir/${stem}.${suffix}" ]] || die "missing raw/${stem}.${suffix}"
    done
done

master_x="$(awk '$1=="num_rng_bins" && $2=="=" {printf "%d",$3; exit}' "$raw_dir/${master}.PRM")"
master_y="$(awk '$1=="num_lines" && $2=="=" {printf "%d",$3; exit}' "$raw_dir/${master}.PRM")"

printf '%s\n' '========================================================================'
printf 'LT-1 full-frame alignment\n'
printf 'Mode:            %s\n' "$([[ "$formal" -eq 1 ]] && echo FORMAL || echo PREVIEW)"
printf 'Input project:   %s\n' "$project_dir"
printf 'Master/pre:      %s\n' "$master"
printf 'Repeat/post:     %s\n' "$repeat"
printf 'Master geometry: %s x %s\n' "$master_x" "$master_y"
printf 'Input:           %s (complete SLCs)\n' "$raw_dir"
printf 'Output:          %s\n' "$work_dir"
printf 'Cropping:        disabled\n'
printf 'Commands:        SAT_baseline -> xcorr -> fitoffset.csh -> resamp\n'
printf '%s\n' '========================================================================'

if [[ "$formal" -eq 0 ]]; then
    printf '[PREVIEW] No files were modified.\n'
    printf '[NEXT] %s 1\n' "$0"
    exit 0
fi

if [[ -e "$work_dir" ]]; then
    [[ -d "$work_dir" && ! -L "$work_dir" ]] || die "unsafe existing output path: $work_dir"
    stamp="$(date +%Y%m%d_%H%M%S)"
    archive_dir="$script_dir/archive_$stamp"
    mkdir -p "$archive_dir"
    mv "$work_dir" "$archive_dir/SLC_full"
    printf '[ARCHIVE] Previous SLC_full moved to %s\n' "$archive_dir/SLC_full"
fi
mkdir -p "$work_dir"
log_file="$script_dir/run1_align_full_frame.log"
: > "$log_file"

# Copy PRMs because baseline and offset parameters are appended during alignment.
cp "$raw_dir/${master}.PRM" "$work_dir/${master}.PRM"
cp "$raw_dir/${repeat}.PRM" "$work_dir/${repeat}.PRM"
ln -s "$raw_dir/${master}.SLC" "$work_dir/${master}.SLC"
ln -s "$raw_dir/${repeat}.SLC" "$work_dir/${repeat}.SLC"
ln -s "$raw_dir/${master}.LED" "$work_dir/${master}.LED"
ln -s "$raw_dir/${repeat}.LED" "$work_dir/${repeat}.LED"

(
    cd "$work_dir"
    cp "${repeat}.PRM" "${repeat}.PRM0"
    SAT_baseline "${master}.PRM" "${repeat}.PRM0" > baseline.tmp 2>> "$log_file"
    cat baseline.tmp >> "$log_file"
    cat baseline.tmp >> "${repeat}.PRM"
    rm -f baseline.tmp

    xcorr "${master}.PRM" "${repeat}.PRM" -xsearch 128 -ysearch 128 -nx 20 -ny 50 2>&1 | tee -a "$log_file"
    [[ -s freq_xcorr.dat ]] || exit 20

    fitoffset.csh 3 3 freq_xcorr.dat 18 > fitoffset.tmp 2>> "$log_file"
    [[ -s fitoffset.tmp ]] || exit 21
    cat fitoffset.tmp >> "$log_file"
    cat fitoffset.tmp >> "${repeat}.PRM"
    rm -f fitoffset.tmp

    resamp "${master}.PRM" "${repeat}.PRM" "${repeat}_aligned.PRM" "${repeat}_aligned.SLC" 4 2>&1 | tee -a "$log_file"
) || die "full-frame alignment failed; inspect $log_file"

aligned_prm="$work_dir/${repeat}_aligned.PRM"
aligned_slc="$work_dir/${repeat}_aligned.SLC"
[[ -s "$aligned_prm" && -s "$aligned_slc" ]] || die "resamp did not create aligned PRM/SLC"
aligned_x="$(awk '$1=="num_rng_bins" && $2=="=" {printf "%d",$3; exit}' "$aligned_prm")"
aligned_y="$(awk '$1=="num_lines" && $2=="=" {printf "%d",$3; exit}' "$aligned_prm")"
[[ "$aligned_x" -eq "$master_x" && "$aligned_y" -eq "$master_y" ]] || die "aligned geometry ${aligned_x}x${aligned_y} differs from master ${master_x}x${master_y}"

cat > "$script_dir/pair.env" <<EOF
MASTER_STEM=$master
REPEAT_STEM=$repeat
ALIGNED_STEM=${repeat}_aligned
EOF

printf '[SUCCESS] Full-frame repeat aligned to the %sx%s master grid.\n' "$master_x" "$master_y"
printf '[RAW]     No file under %s was modified.\n' "$raw_dir"
printf '[NEXT]    %s/run2_make_intensity_change_LT1.sh 1\n' "$script_dir"
