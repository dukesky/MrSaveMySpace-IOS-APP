#!/usr/bin/env bash
set -euo pipefail

log() {
    printf "[MrSaveMySpace] %s\n" "$1"
}

log "Stopping xcodebuild processes..."
if pkill -f xcodebuild >/dev/null 2>&1; then
    log "Terminated running xcodebuild processes."
else
    log "No running xcodebuild processes found."
fi

log "Closing Simulator app..."
if command -v osascript >/dev/null 2>&1; then
    if osascript -e 'tell application "Simulator" to quit' >/dev/null 2>&1; then
        log "Simulator app closed."
    else
        log "Simulator app already closed."
    fi
else
    log "osascript not available; skipping Simulator close."
fi

log "Shutting down all booted simulators..."
if xcrun simctl shutdown all >/dev/null 2>&1; then
    log "Shut down all simulators."
else
    log "No booted simulators to shut down."
fi

log "Environment reset complete."
