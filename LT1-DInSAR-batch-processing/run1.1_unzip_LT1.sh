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
# LT-1 SLC tar.gz batch extractor for GMTSAR data preparation.

set -euo pipefail

export LC_ALL=C
export LANG=C
export LANGUAGE=C

MARKER_NAME=".run1.1_unzip_LT1_complete"

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  ./run1.1_unzip_LT1.sh [1] [--jobs N]

Modes:
  no positional arg  Read-only preview; do not extract or modify data
  1                  Extract data/zip/*.tar.gz into data/

Options:
  --jobs N           Number of parallel extraction jobs (default: 2)
  -h, --help         Show this help

Required directory layout:
  Track/
  ├── run1.1_unzip_LT1.sh       # Run the script from this directory
  └── data/
      ├── zip/                   # Put all LT1*.tar.gz archives here
      │   ├── LT1A_...tar.gz
      │   └── LT1B_...tar.gz
      ├── orbit/                 # Put precise-orbit TXT files here
      │   ├── LT1A_GpsData_...txt
      │   └── LT1B_SAR_....scie.gps.txt
      └── LT1A_MONO_.../         # Generated: one directory per archive

The script only reads data/zip/ and creates product directories under data/.
It never moves, modifies, or deletes files in data/zip/ or data/orbit/.

Recommended server usage:
  cd /data2/xinw/Huangshan_landsides/LT1/Ascending
  ./run1.1_unzip_LT1.sh
  ./run1.1_unzip_LT1.sh 1

Use the same procedure for any independently processed track directory.
EOF
}

file_size() {
    local size
    if size="$(stat -c '%s' "$1" 2>/dev/null)"; then
        :
    else
        size="$(stat -f '%z' "$1" 2>/dev/null)" || return 1
    fi
    [[ "${size}" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${size}"
}

product_name_from_archive() {
    local name
    name="$(basename -- "$1")"
    [[ "${name}" == *.tar.gz ]] || return 1
    printf '%s\n' "${name%.tar.gz}"
}

product_is_valid() {
    local product_dir="$1" product_name="$2"
    [[ -d "${product_dir}" ]] || return 1
    [[ -s "${product_dir}/${product_name}.meta.xml" ]] || return 1
    [[ -s "${product_dir}/${product_name}.tiff" ]] || return 1
}

archive_paths_are_safe() {
    local archive="$1"
    # Reject absolute paths and .. components to prevent path traversal.
    tar -tzf "${archive}" | awk '
        BEGIN { bad = 0; count = 0 }
        {
            count++
            path = $0
            sub(/^\.\//, "", path)
            if (path ~ /^\// || path == ".." || path ~ /(^|\/)\.\.($|\/)/) {
                print "unsafe archive member: " $0 > "/dev/stderr"
                bad = 1
            }
        }
        END { exit (bad || count == 0) ? 1 : 0 }
    '
}

archive_layout() {
    local archive="$1" product_name="$2"
    tar -tzf "${archive}" | awk -v product="${product_name}" '
        BEGIN { wrapped = 0; flat = 0 }
        {
            path = $0
            sub(/^\.\//, "", path)
            if (path == product || index(path, product "/") == 1) {
                wrapped++
            } else {
                flat++
            }
        }
        END {
            if (wrapped > 0 && flat == 0) {
                print "wrapped"
                exit 0
            }
            if (flat > 0 && wrapped == 0) {
                print "flat"
                exit 0
            }
            exit 1
        }
    '
}

write_marker() {
    local product_dir="$1" archive="$2" marker_tmp
    marker_tmp="${product_dir}/${MARKER_NAME}.tmp.$$"
    {
        printf 'source_archive=%s\n' "$(basename -- "${archive}")"
        printf 'source_size=%s\n' "$(file_size "${archive}")"
        printf 'completed_at=%s\n' "$(date '+%F %T %z')"
    } > "${marker_tmp}"
    mv -f -- "${marker_tmp}" "${product_dir}/${MARKER_NAME}"
}

run_worker() {
    local output_dir="$1" temp_root="$2" archive="$3"
    local product_name final_dir job_tmp extracted_dir extract_target layout

    product_name="$(product_name_from_archive "${archive}")" || {
        printf '[FAILED] Not a .tar.gz file: %s\n' "${archive}" >&2
        return 1
    }
    final_dir="${output_dir}/${product_name}"

    if product_is_valid "${final_dir}" "${product_name}"; then
        printf '[SKIP] Product already extracted: %s\n' "${product_name}"
        return 0
    fi

    if [[ -e "${final_dir}" ]]; then
        printf '[FAILED] Existing destination is incomplete; inspect it manually: %s\n' "${final_dir}" >&2
        return 1
    fi

    printf '[CHECK] %s\n' "${archive}"
    if ! gzip -t -- "${archive}"; then
        printf '[FAILED] gzip integrity check failed: %s\n' "${archive}" >&2
        return 1
    fi
    if ! archive_paths_are_safe "${archive}"; then
        printf '[FAILED] Archive is empty, unsafe, or unreadable: %s\n' "${archive}" >&2
        return 1
    fi
    if ! layout="$(archive_layout "${archive}" "${product_name}")"; then
        printf '[FAILED] Archive mixes wrapped and flat content; layout is ambiguous: %s\n' \
            "${archive}" >&2
        return 1
    fi

    job_tmp="${temp_root}/${product_name}.$$"
    rm -rf -- "${job_tmp}"
    mkdir -p -- "${job_tmp}"

    extracted_dir="${job_tmp}/${product_name}"
    if [[ "${layout}" == "flat" ]]; then
        # LT-1 archives are commonly flat. Create a product directory first.
        mkdir -p -- "${extracted_dir}"
        extract_target="${extracted_dir}"
    else
        extract_target="${job_tmp}"
    fi

    printf '[START] %s  layout=%s\n' "${archive}" "${layout}"
    if ! tar -xzf "${archive}" -C "${extract_target}"; then
        printf '[FAILED] Extraction failed: %s\n' "${archive}" >&2
        rm -rf -- "${job_tmp}"
        return 1
    fi

    if ! product_is_valid "${extracted_dir}" "${product_name}"; then
        printf '[FAILED] Extracted product lacks .meta.xml or .tiff: %s\n' "${archive}" >&2
        rm -rf -- "${job_tmp}"
        return 1
    fi

    write_marker "${extracted_dir}" "${archive}"
    # The temporary and final directories share a filesystem for atomic mv.
    mv -- "${extracted_dir}" "${final_dir}"
    rmdir -- "${job_tmp}" 2>/dev/null || true
    printf '[DONE] %s\n' "${product_name}"
}

if [[ "${1:-}" == "--worker" ]]; then
    [[ "$#" -eq 4 ]] || die "invalid internal worker arguments"
    run_worker "$2" "$3" "$4"
    exit $?
fi

MODE="PREVIEW"
if [[ "${1:-}" == "1" ]]; then
    MODE="FORMAL"
    shift
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    die "mode must be 1, or omitted for preview"
fi

JOBS=2
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --jobs)
            [[ "$#" -ge 2 ]] || die "--jobs requires an integer"
            JOBS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ "${JOBS}" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"

for command_name in find sort tar gzip awk stat tee wc; do
    command -v "${command_name}" >/dev/null 2>&1 || die "command not found: ${command_name}"
done

WORK_DIR="$(pwd -P)"
DATA_DIR="${WORK_DIR}/data"
ZIP_DIR="${DATA_DIR}/zip"
ORBIT_DIR="${DATA_DIR}/orbit"
OUTPUT_DIR="${DATA_DIR}"
TEMP_ROOT="${DATA_DIR}/.run1.1_unzip_LT1_tmp"
LOG_FILE="${WORK_DIR}/run1.1_unzip_LT1.log"
JOB_LOG="${WORK_DIR}/run1.1_unzip_LT1_parallel_joblog.txt"
FAILED_FILE="${WORK_DIR}/failed_tar_gz.txt"
SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")"

printf '%s\n' '============================================================'
printf 'LT-1 Run 1.1 data layout\n'
printf 'Track directory: %s\n' "${WORK_DIR}"
printf 'Data directory:  %s\n' "${DATA_DIR}"
printf '1. SLC archives: %s/\n' "${ZIP_DIR}"
printf '   File pattern: LT1*.tar.gz\n'
printf '2. Precise orbits: %s/\n' "${ORBIT_DIR}"
printf '   File patterns: LT1*_GpsData_*.txt or LT1*_SAR_*.scie.gps.txt\n'
printf '3. Extracted products: %s/LT1A_MONO_.../\n' "${OUTPUT_DIR}"
printf '4. Source files in zip/ and orbit/ are preserved\n'
printf '%s\n' '============================================================'

if [[ ! -d "${ZIP_DIR}" ]]; then
    printf '[ERROR] Archive directory not found: %s/\n' "${ZIP_DIR}" >&2
    printf '[HINT]  Run mkdir -p data/zip data/orbit and place the files there.\n' >&2
    exit 1
fi

if [[ -d "${ORBIT_DIR}" ]]; then
    ORBIT_COUNT="$(find "${ORBIT_DIR}" -maxdepth 1 -type f -name 'LT1*.txt' | wc -l | awk '{print $1}')"
    printf '[INFO] Found %s LT-1 precise-orbit file(s) in orbit/.\n' "${ORBIT_COUNT}"
else
    printf '[WARNING] orbit/ is missing. Extraction can continue, but precise orbits are recommended.\n' >&2
fi

ARCHIVES=()
while IFS= read -r archive; do
    ARCHIVES+=("${archive}")
done < <(find "${ZIP_DIR}" -maxdepth 1 -type f -name 'LT1*.tar.gz' -print | LC_ALL=C sort)
TOTAL=${#ARCHIVES[@]}
(( TOTAL > 0 )) || die "no LT1*.tar.gz archives found in zip/"

VALID=0
PENDING=0
INCOMPLETE=0

printf '\n%s\n' '============================================================'
printf 'LT-1 tar.gz batch extraction  Mode: %s\n' "${MODE}"
printf 'Working directory: %s\n' "${WORK_DIR}"
printf 'Archive directory: %s\n' "${ZIP_DIR}"
printf 'Archive count:     %s\n' "${TOTAL}"
printf '%s\n' '============================================================'

for archive in "${ARCHIVES[@]}"; do
    product_name="$(product_name_from_archive "${archive}")"
    product_dir="${OUTPUT_DIR}/${product_name}"
    if product_is_valid "${product_dir}" "${product_name}"; then
        printf '[READY]   %s/\n' "${product_dir}"
        VALID=$((VALID + 1))
    elif [[ -e "${product_dir}" ]]; then
        printf '[BROKEN]  %s/  destination exists but lacks meta.xml/tiff\n' "${product_dir}"
        INCOMPLETE=$((INCOMPLETE + 1))
    else
        printf '[PENDING] %s\n' "$(basename -- "${archive}")"
        printf '          → %s/\n' "${product_dir}"
        PENDING=$((PENDING + 1))
    fi
done

printf '%s\n' '------------------------------------------------------------'
printf 'Ready: %s  Pending: %s  Broken: %s  Total: %s\n' \
    "${VALID}" "${PENDING}" "${INCOMPLETE}" "${TOTAL}"

if [[ "${MODE}" == "PREVIEW" ]]; then
    (( INCOMPLETE == 0 )) || printf '[WARNING] Inspect all [BROKEN] directories first.\n' >&2
    printf '\nPreview complete; no data were modified.\n'
    if (( PENDING > 0 )); then
        printf 'To execute: %s 1\n' "${SCRIPT_PATH}"
    fi
    exit 0
fi

(( INCOMPLETE == 0 )) || die "found ${INCOMPLETE} incomplete destination directory/directories; extraction not started"

if (( PENDING == 0 )); then
    printf 'All products are already extracted.\n'
    : > "${FAILED_FILE}"
    exit 0
fi

command -v parallel >/dev/null 2>&1 || die "formal parallel mode requires GNU Parallel"
mkdir -p -- "${TEMP_ROOT}"
: > "${FAILED_FILE}"

PENDING_LIST="${TEMP_ROOT}/pending_archives.$$.txt"
: > "${PENDING_LIST}"
for archive in "${ARCHIVES[@]}"; do
    product_name="$(product_name_from_archive "${archive}")"
    if [[ ! -e "${OUTPUT_DIR}/${product_name}" ]]; then
        printf '%s\n' "${archive}" >> "${PENDING_LIST}"
    fi
done

printf '\n[INFO] Starting parallel extraction with %s job(s).\n' "${JOBS}"
set +e
parallel \
    --jobs "${JOBS}" \
    --line-buffer \
    --joblog "${JOB_LOG}" \
    --results "${TEMP_ROOT}/parallel_results" \
    "${SCRIPT_PATH}" --worker "${OUTPUT_DIR}" "${TEMP_ROOT}" {} \
    :::: "${PENDING_LIST}" 2>&1 | tee "${LOG_FILE}"
parallel_status=${PIPESTATUS[0]}
set -e

rm -f -- "${PENDING_LIST}"

# Validate final products and write an explicit failure list.
FINAL_VALID=0
for archive in "${ARCHIVES[@]}"; do
    product_name="$(product_name_from_archive "${archive}")"
    if product_is_valid "${OUTPUT_DIR}/${product_name}" "${product_name}"; then
        FINAL_VALID=$((FINAL_VALID + 1))
    else
        printf '%s\n' "$(basename -- "${archive}")" >> "${FAILED_FILE}"
    fi
done

FAILED_COUNT=$((TOTAL - FINAL_VALID))
printf '\n%s\n' '============================================================'
printf 'Valid extracted products: %s/%s\n' "${FINAL_VALID}" "${TOTAL}"
printf 'Failure count:            %s\n' "${FAILED_COUNT}"
printf 'Run log:                  %s\n' "${LOG_FILE}"
printf 'Job log:                  %s\n' "${JOB_LOG}"
printf 'Failure list:             %s\n' "${FAILED_FILE}"
printf '%s\n' '============================================================'

if (( FAILED_COUNT > 0 )) || (( parallel_status != 0 )); then
    die "one or more products failed; inspect failed_tar_gz.txt and the logs"
fi

printf '[SUCCESS] All LT-1 products extracted; zip/ and orbit/ were preserved.\n'
