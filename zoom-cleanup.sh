#!/bin/bash
# zoom-cleanup.sh — Kill orphaned Zoom processes after meetings end
# Runs via systemd timer every 60s.
# Checks ALL mapped Zoom windows by GEOMETRY (pixel size).
#
# Why geometry, not PID or class alone:
#   v1 (--class zoom): CEF helper windows stayed "visible" → never killed
#   v2 (--pid main):   Meeting window owned by ZoomWebviewHost → killed mid-call
#   v3 (geometry):     Used --onlyvisible — missed windows on non-focused i3 workspaces
#   v4 (this): Search ALL mapped zoom windows (no --onlyvisible), filter by geometry.
#              CEF helpers are tiny (1x1). Real meeting windows are large.

export DISPLAY=:0
export XAUTHORITY=/run/user/1000/gdm/Xauthority

# Find the main Zoom binary PID
ZOOM_PID=$(pgrep -f '/opt/zoom/zoom' | head -1)

# No main Zoom process — nothing to do
[ -z "$ZOOM_PID" ] && exit 0

# Grace period: don't kill within 120s of startup (window may not render yet)
PROC_START=$(stat -c %Y "/proc/$ZOOM_PID" 2>/dev/null)
NOW=$(date +%s)
AGE=$(( NOW - ${PROC_START:-$NOW} ))
[ "$AGE" -lt 120 ] && exit 0

# Safety: verify X server is accessible before trusting xdotool
if ! xdotool getdisplaygeometry >/dev/null 2>&1; then
    exit 0
fi

# Check ALL mapped Zoom windows for any real-sized one (>100x100 pixels)
# Real meeting/UI windows are full-sized; CEF helpers are 1x1 or 0x0
# Note: --onlyvisible misses windows on non-focused i3 workspaces — don't use it
HAS_REAL_WINDOW=0
for WID in $(xdotool search --class zoom 2>/dev/null); do
    WIDTH=0 HEIGHT=0
    eval $(xdotool getwindowgeometry --shell "$WID" 2>/dev/null)
    if [ "$WIDTH" -gt 100 ] && [ "$HEIGHT" -gt 100 ]; then
        HAS_REAL_WINDOW=1
        break
    fi
done

if [ "$HAS_REAL_WINDOW" -eq 0 ]; then
    logger -t zoom-cleanup "No real Zoom windows found (age: ${AGE}s) — killing all"
    pkill zoom
    pkill -f 'xdg-open zoommtg' 2>/dev/null
fi
