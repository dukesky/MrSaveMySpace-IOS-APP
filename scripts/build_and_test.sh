#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="MrSaveMySpace.xcodeproj"
SCHEME="MrSaveMySpace"
SIMULATOR_DEVICE="${SIMULATOR_DEVICE:-iPhone 15}"
SIMULATOR_OS="${SIMULATOR_OS:-17.5}"
SIMULATOR_APP="Simulator"
SIMULATOR_RUNTIME=""
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${REPO_ROOT}/DerivedData}"
CONFIGURATION="${CONFIGURATION:-Debug}"
PRODUCT_NAME="${PRODUCT_NAME:-MrSaveMySpace}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.dukesky.MrSaveMySpace}"

log() {
    printf "[MrSaveMySpace] %s\n" "$1"
}

resolve_simulator() {
    if [[ -n "${SIMULATOR_UDID:-}" ]]; then
        SIMULATOR_RUNTIME="${SIMULATOR_OS:-custom runtime}"
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        if python_output=$(
            SIMULATOR_DEVICE="${SIMULATOR_DEVICE}" \
            SIMULATOR_OS="${SIMULATOR_OS}" \
            python3 <<'PY'
import json
import os
import subprocess
import sys

device = os.environ.get("SIMULATOR_DEVICE", "iPhone 15")
requested_os = os.environ.get("SIMULATOR_OS")

try:
    raw = subprocess.check_output([
        "xcrun",
        "simctl",
        "list",
        "--json",
        "devices",
        "available",
    ])
except Exception as err:
    sys.stderr.write(f"ERROR: {err}\n")
    sys.exit(2)

data = json.loads(raw)

candidates = []
for runtime, sims in data.get("devices", {}).items():
    for sim in sims:
        if not sim.get("isAvailable", True):
            continue
        if sim.get("name") != device:
            continue
        candidates.append((runtime, sim.get("udid")))

if not candidates:
    sys.exit(1)

selected_runtime = None
selected_udid = None
if requested_os:
    for runtime, udid in candidates:
        if requested_os in runtime:
            selected_runtime = runtime
            selected_udid = udid
            break

if selected_udid is None:
    selected_runtime, selected_udid = candidates[0]

print(selected_udid)
print(selected_runtime)
PY
        ); then
            SIMULATOR_UDID=$(printf '%s\n' "$python_output" | sed -n '1p')
            SIMULATOR_RUNTIME=$(printf '%s\n' "$python_output" | sed -n '2p')
        else
            python_status=$?
            if [[ ${python_status} -ne 0 ]]; then
                log "Unable to resolve simulator via JSON list (status ${python_status}). Falling back to grep." >&2
            fi
        fi
    fi

    if [[ -z "${SIMULATOR_UDID:-}" ]]; then
        local device_line=""
        if [[ -n "${SIMULATOR_OS}" ]]; then
            device_line=$(xcrun simctl list devices available | grep -E "${SIMULATOR_DEVICE} \\(${SIMULATOR_OS}\\)" | head -n1 || true)
        fi
        if [[ -z "${device_line}" ]]; then
            device_line=$(xcrun simctl list devices available | grep -E "${SIMULATOR_DEVICE} \\(" | head -n1 || true)
        fi
        if [[ -z "${device_line}" ]]; then
            log "Unable to find ${SIMULATOR_DEVICE}${SIMULATOR_OS:+ (${SIMULATOR_OS})} in available simulators." >&2
            log "List devices with: xcrun simctl list devices available" >&2
            exit 1
        fi
        SIMULATOR_UDID=$(printf '%s' "${device_line}" | awk -F '[\\[\\]]' '{print $2}')
        if [[ -z "${SIMULATOR_RUNTIME}" ]]; then
            SIMULATOR_RUNTIME=$(printf '%s' "${device_line}" | sed -n 's/.*(\([^)]*\)).*/\1/p')
        fi
    fi

    if [[ -z "${SIMULATOR_UDID:-}" ]]; then
        log "Failed to determine simulator UDID." >&2
        exit 1
    fi
}

resolve_simulator

DESTINATION="id=${SIMULATOR_UDID}"

log "Ensuring simulator ${SIMULATOR_DEVICE}${SIMULATOR_OS:+ (${SIMULATOR_OS})} [${SIMULATOR_UDID}]${SIMULATOR_RUNTIME:+ on ${SIMULATOR_RUNTIME}} is booted..."
# Boot the target simulator; ignore if already running.
xcrun simctl boot "${SIMULATOR_UDID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${SIMULATOR_UDID}" -b >/dev/null 2>&1 || true

log "Opening Simulator app (if needed)..."
if command -v pgrep >/dev/null 2>&1 && pgrep -x "${SIMULATOR_APP}" >/dev/null 2>&1; then
    log "Simulator already running."
elif command -v open >/dev/null 2>&1; then
    open -a "${SIMULATOR_APP}" >/dev/null 2>&1 || true
else
    log "Simulator app not opened (open command unavailable)."
fi

log "Cleaning and building ${SCHEME}..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -destination "${DESTINATION}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  clean build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-iphonesimulator/${PRODUCT_NAME}.app"

if [[ ! -d "${APP_PATH}" ]]; then
    log "Built app not found at ${APP_PATH}." >&2
    exit 1
fi

log "Installing build onto simulator..."
if xcrun simctl get_app_container "${SIMULATOR_UDID}" "${BUNDLE_IDENTIFIER}" app >/dev/null 2>&1; then
    xcrun simctl uninstall "${SIMULATOR_UDID}" "${BUNDLE_IDENTIFIER}" >/dev/null 2>&1 || true
fi

if ! xcrun simctl install "${SIMULATOR_UDID}" "${APP_PATH}"; then
    log "Failed to install ${APP_PATH} onto simulator." >&2
    exit 1
fi

log "Launching ${BUNDLE_IDENTIFIER} on simulator..."
if ! xcrun simctl launch "${SIMULATOR_UDID}" "${BUNDLE_IDENTIFIER}"; then
    log "Failed to launch ${BUNDLE_IDENTIFIER}." >&2
    exit 1
fi

log "Build installed and launched successfully."
