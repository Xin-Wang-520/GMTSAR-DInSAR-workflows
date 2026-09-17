#!/usr/bin/env bash
# Author: Xin Wang
# Affiliation: University of Science and Technology of China (USTC), Hefei, China
# Last updated: 2026-09-14
#
# Read-only compatibility check for one LT-1 DInSAR pair.
set -euo pipefail

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ -s data.list ]] || die "missing or empty data.list; complete Run 1.2.1 first"

mapfile_path="$(mktemp "${TMPDIR:-/tmp}/lt1_pair.XXXXXX")"
trap 'rm -f "${mapfile_path}"' EXIT
awk 'NF && $1 !~ /^#/ {print $1}' data.list > "${mapfile_path}"
scene_count="$(wc -l < "${mapfile_path}" | awk '{print $1}')"
[[ "${scene_count}" -eq 2 ]] || die "data.list must contain exactly two acquisitions; found ${scene_count}"
first="$(sed -n '1p' "${mapfile_path}")"
second="$(sed -n '2p' "${mapfile_path}")"
[[ "${first}" =~ ^LT1_([0-9]{8})$ ]] || die "invalid acquisition name in data.list: ${first}"
MASTER_DATE="${BASH_REMATCH[1]}"
MASTER_STEM="${first}"
[[ "${second}" =~ ^LT1_([0-9]{8})$ ]] || die "invalid acquisition name in data.list: ${second}"
REPEAT_DATE="${BASH_REMATCH[1]}"
REPEAT_STEM="${second}"
[[ "${MASTER_DATE}" < "${REPEAT_DATE}" ]] ||
    die "data.list is not chronological; the earlier acquisition must be first"

master_prm="raw/${MASTER_STEM}.PRM"
repeat_prm="raw/${REPEAT_STEM}.PRM"
for path in "${master_prm}" "${repeat_prm}" "raw/${MASTER_STEM}.SLC" "raw/${REPEAT_STEM}.SLC" \
            "raw/${MASTER_STEM}.LED" "raw/${REPEAT_STEM}.LED"; do
    [[ -s "${path}" ]] || die "missing or empty ${path}"
done

prm_value() {
    awk -v key="$2" '$1==key && $2=="=" {print $3; exit}' "$1"
}

same_number() {
    awk -v a="$1" -v b="$2" -v rel="$3" 'BEGIN {
        d=a-b; if (d<0) d=-d
        s=(a<0?-a:a); t=(b<0?-b:b); if (t>s) s=t; if (s<1) s=1
        exit !(d <= rel*s)
    }'
}

hard_fail=0
printf '%s\n' '========================================================================'
printf 'LT-1 pair compatibility check (read only)\n'
printf 'Reference/master: %s\n' "${MASTER_STEM}"
printf 'Repeat/secondary: %s\n' "${REPEAT_STEM}"
printf '%s\n' '------------------------------------------------------------------------'
printf '%-20s %-20s %-20s %s\n' PARAMETER MASTER REPEAT RESULT

for key in radar_wavelength orbdir lookdir; do
    a="$(prm_value "${master_prm}" "${key}")"
    b="$(prm_value "${repeat_prm}" "${key}")"
    if [[ -z "${a}" || -z "${b}" ]]; then
        result="NOT_REPORTED"
    elif [[ "${key}" == "radar_wavelength" ]]; then
        if same_number "${a}" "${b}" 0.000001; then result="OK"; else result="INCOMPATIBLE"; hard_fail=1; fi
    elif [[ "${a}" == "${b}" ]]; then
        result="OK"
    else
        result="INCOMPATIBLE"; hard_fail=1
    fi
    printf '%-20s %-20s %-20s %s\n' "${key}" "${a:-MISSING}" "${b:-MISSING}" "${result}"
done

sampling_diff=0
for key in PRF rng_samp_rate; do
    a="$(prm_value "${master_prm}" "${key}")"
    b="$(prm_value "${repeat_prm}" "${key}")"
    [[ -n "${a}" && -n "${b}" ]] || die "${key} is missing from one or both PRMs"
    if same_number "${a}" "${b}" 0.000000001; then result="OK"; else result="RESAMPLE_NEEDED"; sampling_diff=1; fi
    printf '%-20s %-20s %-20s %s\n' "${key}" "${a}" "${b}" "${result}"
done

for key in num_rng_bins num_lines num_valid_az num_patches near_range; do
    a="$(prm_value "${master_prm}" "${key}")"
    b="$(prm_value "${repeat_prm}" "${key}")"
    printf '%-20s %-20s %-20s %s\n' "${key}" "${a:-MISSING}" "${b:-MISSING}" INFO
done

printf '%s\n' '------------------------------------------------------------------------'
printf 'Extracted products:\n'
find data -maxdepth 1 -type d \( -name "LT1*_${MASTER_DATE}_SLC_*" -o -name "LT1*_${REPEAT_DATE}_SLC_*" \) -print | LC_ALL=C sort

if command -v SAT_baseline >/dev/null 2>&1; then
    printf '%s\n' '------------------------------------------------------------------------'
    printf 'SAT_baseline result:\n'
    baseline_log="SAT_baseline_${MASTER_STEM}_${REPEAT_STEM}.log"
    set +e
    (cd raw && SAT_baseline "${MASTER_STEM}.PRM" "${REPEAT_STEM}.PRM") >"${baseline_log}" 2>&1
    baseline_status=$?
    set -e
    [[ "${baseline_status}" -eq 0 ]] || die "SAT_baseline failed with status ${baseline_status}"
    hermite_count="$(grep -cF '[ERROR]:hermite interpolation not in center interval' "${baseline_log}" || true)"
    if [[ "${hermite_count}" -gt 0 ]]; then
        printf '[ERROR]:hermite interpolation not in center interval\n'
        printf '[INFO] This message occurred %s time(s); full output saved in %s.\n' "${hermite_count}" "${baseline_log}"
    fi
    # Keep the useful SAT_baseline values visible while suppressing repeated warnings.
    grep -vF '[ERROR]:hermite interpolation not in center interval' "${baseline_log}" || true

    # Save a compact temporal/perpendicular-baseline table and draw a two-scene plot.
    bperp="$(awk -F'= *' '$1 ~ /^B_perpendicular[[:space:]]*$/ {print $2; exit}' "${baseline_log}" | awk '{print $1}')"
    if [[ -n "${bperp}" ]]; then
        if command -v python3 >/dev/null 2>&1; then
            delta_days="$(python3 - "${MASTER_DATE}" "${REPEAT_DATE}" <<'PY'
import datetime, sys
a = datetime.datetime.strptime(sys.argv[1], '%Y%m%d').date()
b = datetime.datetime.strptime(sys.argv[2], '%Y%m%d').date()
print((b - a).days)
PY
)"
        else
            delta_days=""
        fi
        [[ "${delta_days}" =~ ^[0-9]+$ ]] || delta_days=0
        {
            printf 'date\ttemporal_days\tperpendicular_baseline_m\trole\n'
            printf '%s\t0\t0\tmaster\n' "${MASTER_DATE}"
            printf '%s\t%s\t%s\trepeat\n' "${REPEAT_DATE}" "${delta_days}" "${bperp}"
        } > "baseline_summary.tsv"
        printf '[BASELINE TABLE] baseline_summary.tsv\n'
        if command -v gmt >/dev/null 2>&1; then
            x_min="$(awk -v d="${delta_days}" 'BEGIN {print (d > 0 ? -d*0.15 : -1)}')"
            x_max="$(awk -v d="${delta_days}" 'BEGIN {print (d > 0 ? d*1.25 : 1)}')"
            y_min="$(awk -v b="${bperp}" 'BEGIN {print (b < 0 ? b*1.15 : -((b > 0 ? b : 1)*0.15))}')"
            y_max="$(awk -v b="${bperp}" 'BEGIN {print (b > 0 ? b*1.30 : ((b < 0 ? -b : 1)*0.20))}')"
            if gmt begin baseline_plot png && gmt basemap -R${x_min}/${x_max}/${y_min}/${y_max} -JX12c/8c \
                -Bxa+l"Temporal baseline (days)" -Bya+l"Perpendicular baseline (m)" -BWSen
                awk 'NR>1 {print $2, $3}' baseline_summary.tsv | gmt plot -Sc0.28c -Groyalblue -W0.5p &&
                awk 'NR==2 {print $2, $3}' baseline_summary.tsv | gmt plot -Sc0.32c -Gred -W0.5p &&
                awk 'NR==3 {print $2, $3}' baseline_summary.tsv | gmt plot -Sc0.32c -Groyalblue -W0.5p &&
                awk 'NR>1 {print $2, $3, $1}' baseline_summary.tsv | gmt text -F+f8p,Helvetica,black+jTL -D0.12c/0.12c &&
                gmt end; then
                printf '[BASELINE PLOT] baseline_plot.png\n'
            else
                printf '[WARNING] GMT could not draw baseline_plot.png; baseline_summary.tsv was kept.\n'
            fi
        else
            printf '[WARNING] GMT is not in PATH; baseline_summary.tsv was written but no PNG was drawn.\n'
        fi
    else
        printf '[WARNING] Could not parse B_perpendicular; baseline plot was not generated.\n'
    fi
else
    printf '[WARNING] SAT_baseline is not in PATH; perpendicular baseline was not calculated.\n'
fi

printf '%s\n' '========================================================================'
if [[ "${hard_fail}" -ne 0 ]]; then
    die "the two scenes have incompatible hard geometry parameters"
fi
if [[ "${sampling_diff}" -ne 0 ]]; then
    printf '[ACTION] PRF/range sampling differs; preview and then run Run 1.2.4 before alignment.\n'
else
    printf '[OK] PRF and range sampling already match; Run 1.2.4 formal mode is unnecessary.\n'
fi
printf '[PASS] The available PRM hard-geometry checks passed. Continue with ROI and alignment after reviewing SAT_baseline.\n'
printf '[NEXT] ./run2.1_prepare_topo_DEM_LT1.sh 1\n'
