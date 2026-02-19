#!/bin/bash
# mem-refresh.sh — Reclaim memory without rebooting
# Clears caches, kills known memory hogs, reports savings

set -e

echo "=== Memory Refresh ==="
echo ""

# Snapshot before
MEM_BEFORE=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
echo "Before: $(( MEM_BEFORE / 1024 )) MiB available"
echo ""

# 1. Drop page cache, dentries, inodes (needs sudo)
echo "[1/4] Dropping kernel caches..."
sync
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || echo "  (skipped — needs sudo)"

# 2. Kill known memory hogs if not actively in use
echo "[2/4] Checking for idle Zoom processes..."
ZOOM_MAIN=$(pgrep -x zoom 2>/dev/null || true)
ZOOM_WEB=$(pgrep -f ZoomWebviewHost 2>/dev/null || true)
if [ -z "$ZOOM_MAIN" ] && [ -n "$ZOOM_WEB" ]; then
    pkill -f ZoomWebviewHost && echo "  Killed orphaned ZoomWebviewHost"
elif [ -n "$ZOOM_MAIN" ]; then
    echo "  Zoom is running (active meeting?) — skipping"
else
    echo "  No Zoom processes found"
fi

# 3. Clear systemd journal (keep last 100M)
echo "[3/4] Vacuuming journal logs..."
sudo journalctl --vacuum-size=100M 2>/dev/null || echo "  (skipped — needs sudo)"

# 4. Clear /tmp files older than 7 days
echo "[4/4] Cleaning old /tmp files..."
find /tmp -type f -atime +7 -delete 2>/dev/null || true

# Snapshot after
MEM_AFTER=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
SAVED=$(( (MEM_AFTER - MEM_BEFORE) / 1024 ))
echo ""
echo "After:  $(( MEM_AFTER / 1024 )) MiB available"
echo "Freed:  ${SAVED} MiB"
echo ""
echo "Current memory status:"
free -h
