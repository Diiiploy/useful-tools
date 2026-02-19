#!/bin/bash
# zoom-cleanup.sh — Kill orphaned Zoom processes
# Runs via systemd timer. If main zoom process is gone but
# ZoomWebviewHost processes linger, kill them.

ZOOM_MAIN=$(pgrep -x zoom)
ZOOM_WEBVIEW=$(pgrep -f ZoomWebviewHost)

if [ -z "$ZOOM_MAIN" ] && [ -n "$ZOOM_WEBVIEW" ]; then
    logger -t zoom-cleanup "Killing orphaned ZoomWebviewHost processes"
    pkill -f ZoomWebviewHost
fi
