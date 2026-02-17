#!/bin/bash
# PAI System Optimization: Performance Tuning Script
# Generated: 2026-02-15
# Purpose: CPU governor, sysctl tuning, noatime, zswap, earlyoom
#
# Run with: sudo bash ~/optimize-system.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
section() { echo ""; echo -e "${CYAN}═══ $1 ═══${NC}"; }

if [ "$EUID" -ne 0 ]; then
    fail "This script must be run with sudo. Usage: sudo bash ~/optimize-system.sh"
fi

echo "============================================="
echo "  System Performance Optimization"
echo "  Geekom Mini Air 11 / Celeron N5095 / 8GB"
echo "============================================="

# Update package index first (prevents apt hangs on missing packages)
info "Updating package index..."
apt-get update -qq
pass "Package index updated"

# ═══════════════════════════════════════════════
section "1/7: CPU GOVERNOR → performance"
# ═══════════════════════════════════════════════

info "Current governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"

# Set all cores to performance immediately
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance > "$cpu"
done

# Verify each core
ALL_PERF=true
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    GOV=$(cat "$cpu")
    if [ "$GOV" != "performance" ]; then
        ALL_PERF=false
        fail "CPU $(basename $(dirname $(dirname $cpu))) still at $GOV"
    fi
done
if $ALL_PERF; then
    pass "All CPU cores set to performance"
fi

# Make persistent with a systemd service (works on Kali without cpufrequtils)
info "Creating systemd service for governor persistence..."

cat > /etc/systemd/system/cpu-performance.service << 'SERVICE_EOF'
[Unit]
Description=Set CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable cpu-performance.service > /dev/null 2>&1

# Verify the service is enabled
if systemctl is-enabled --quiet cpu-performance.service; then
    pass "cpu-performance.service enabled for boot persistence"
else
    fail "Failed to enable cpu-performance.service"
fi

# Show new frequency
info "CPU now running at: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq | awk '{printf "%.0f MHz", $1/1000}') (was throttled in powersave)"

# ═══════════════════════════════════════════════
section "2/7: SYSCTL PERFORMANCE TUNING"
# ═══════════════════════════════════════════════

info "Writing /etc/sysctl.d/99-performance.conf..."

cat > /etc/sysctl.d/99-performance.conf << 'SYSCTL_EOF'
# PAI System Performance Tuning
# Generated: 2026-02-15
# Target: Geekom Mini Air 11 / Celeron N5095 / 8GB RAM / SSD

# ── Swap behavior ──
# Default was 60. Lower = prefer RAM over swap. 10 = only swap under real pressure.
vm.swappiness=10

# ── Filesystem cache ──
# Default was 100. Lower = hold directory/inode caches longer in RAM.
vm.vfs_cache_pressure=50

# ── Dirty page writeback (SSD-optimized) ──
# Flush dirty pages sooner to avoid large write bursts on SSD.
# Defaults were 20/10/500.
vm.dirty_ratio=10
vm.dirty_background_ratio=5
vm.dirty_writeback_centisecs=300
SYSCTL_EOF
# Note: Scheduler tuning (sched_min_granularity_ns) not needed — kernel 6.18
# uses EEVDF scheduler which handles desktop responsiveness natively.

# Apply all sysctl values
sysctl --system > /dev/null 2>&1

# Verify each value
EXPECTED_SWAPPINESS=10
EXPECTED_VFS=50
EXPECTED_DIRTY=10
EXPECTED_DIRTY_BG=5
EXPECTED_WRITEBACK=300
ACTUAL_SWAPPINESS=$(sysctl -n vm.swappiness)
ACTUAL_VFS=$(sysctl -n vm.vfs_cache_pressure)
ACTUAL_DIRTY=$(sysctl -n vm.dirty_ratio)
ACTUAL_DIRTY_BG=$(sysctl -n vm.dirty_background_ratio)
ACTUAL_WRITEBACK=$(sysctl -n vm.dirty_writeback_centisecs)

SYSCTL_OK=true

check_sysctl() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        pass "$name = $actual"
    else
        echo -e "${RED}[FAIL]${NC} $name = $actual (expected $expected)"
        SYSCTL_OK=false
    fi
}

check_sysctl "vm.swappiness" $EXPECTED_SWAPPINESS $ACTUAL_SWAPPINESS
check_sysctl "vm.vfs_cache_pressure" $EXPECTED_VFS $ACTUAL_VFS
check_sysctl "vm.dirty_ratio" $EXPECTED_DIRTY $ACTUAL_DIRTY
check_sysctl "vm.dirty_background_ratio" $EXPECTED_DIRTY_BG $ACTUAL_DIRTY_BG
check_sysctl "vm.dirty_writeback_centisecs" $EXPECTED_WRITEBACK $ACTUAL_WRITEBACK

if ! $SYSCTL_OK; then
    fail "Some sysctl values did not apply correctly"
fi

# ═══════════════════════════════════════════════
section "3/7: FSTAB → noatime"
# ═══════════════════════════════════════════════

# Backup fstab (use different name from swap script backup)
cp /etc/fstab /etc/fstab.bak.noatime.20260215
pass "fstab backed up to /etc/fstab.bak.noatime.20260215"

# Check if noatime already set
if grep -q "noatime" /etc/fstab; then
    info "noatime already present in fstab, skipping edit"
else
    # Precise replacement: only the root mount options field
    # Replace "errors=remount-ro" with "noatime,errors=remount-ro"
    # This targets ONLY that exact string, preserving everything else
    sed -i 's|errors=remount-ro|noatime,errors=remount-ro|' /etc/fstab

    # Verify the edit was correct
    if grep -q "noatime,errors=remount-ro" /etc/fstab; then
        pass "noatime added to root mount options in fstab"
    else
        fail "fstab edit failed. Restoring backup."
        cp /etc/fstab.bak.noatime.20260215 /etc/fstab
        exit 1
    fi
fi

# Verify UUID is still intact
if ! grep -q "03277b46-0528-4328-b54d-feab598f4ea9" /etc/fstab; then
    fail "CRITICAL: Root UUID missing from fstab! Restoring backup."
    cp /etc/fstab.bak.noatime.20260215 /etc/fstab
    exit 1
fi
pass "Root UUID verified intact in fstab"

# Reload systemd to pick up fstab changes (suppresses mount hint)
systemctl daemon-reload

# Remount root with noatime live (no reboot needed)
mount -o remount /

# Verify noatime is active on the live mount
if mount | grep "on / " | grep -q "noatime"; then
    pass "Root filesystem remounted with noatime active"
else
    info "noatime may be reported as 'relatime' by mount — checking /proc/mounts"
    if grep " / " /proc/mounts | grep -q "noatime"; then
        pass "Root filesystem confirmed noatime via /proc/mounts"
    else
        fail "noatime not active after remount"
    fi
fi

# ═══════════════════════════════════════════════
section "4/7: ZSWAP ENABLE"
# ═══════════════════════════════════════════════

# Enable zswap immediately
echo 1 > /sys/module/zswap/parameters/enabled

# Try to load lz4 module
modprobe lz4 2>/dev/null || modprobe lz4_compress 2>/dev/null || true

# Set compressor if parameter exists
if [ -f /sys/module/zswap/parameters/compressor ]; then
    if echo lz4 > /sys/module/zswap/parameters/compressor 2>/dev/null; then
        pass "zswap compressor set to lz4"
    else
        info "lz4 compressor not available, using default"
    fi
else
    info "Compressor parameter not exposed (kernel manages it)"
fi

# Set zpool ONLY if the parameter exists (removed in kernel 6.5+)
if [ -f /sys/module/zswap/parameters/zpool ]; then
    modprobe z3fold 2>/dev/null || true
    if echo z3fold > /sys/module/zswap/parameters/zpool 2>/dev/null; then
        pass "zswap zpool set to z3fold"
    else
        info "z3fold not available, using kernel default pool"
    fi
else
    info "zpool parameter not present (kernel 6.5+ uses zsmalloc exclusively)"
fi

# Verify zswap is enabled
ZSWAP_ENABLED=$(cat /sys/module/zswap/parameters/enabled)
if [ "$ZSWAP_ENABLED" = "Y" ]; then
    pass "zswap is enabled"
    # Report whichever parameters exist
    ZSWAP_COMP=$(cat /sys/module/zswap/parameters/compressor 2>/dev/null || echo "kernel-managed")
    info "zswap compressor: $ZSWAP_COMP"
else
    fail "zswap failed to enable"
fi

# Make persistent via GRUB
info "Updating GRUB for boot persistence..."
cp /etc/default/grub /etc/default/grub.bak.20260215
pass "GRUB config backed up to /etc/default/grub.bak.20260215"

# Build GRUB params based on what parameters actually exist
ZSWAP_GRUB_PARAMS="zswap.enabled=1"
if [ -f /sys/module/zswap/parameters/compressor ]; then
    ZSWAP_COMP_ACTUAL=$(cat /sys/module/zswap/parameters/compressor)
    ZSWAP_GRUB_PARAMS="${ZSWAP_GRUB_PARAMS} zswap.compressor=${ZSWAP_COMP_ACTUAL}"
fi

# Check if zswap params already in GRUB
if grep -q "zswap.enabled=1" /etc/default/grub; then
    info "zswap already in GRUB config, skipping"
else
    # Read current GRUB_CMDLINE and append zswap params
    CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | sed 's/GRUB_CMDLINE_LINUX_DEFAULT="//;s/"$//')
    NEW_CMDLINE="${CURRENT_CMDLINE} ${ZSWAP_GRUB_PARAMS}"
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_CMDLINE}\"|" /etc/default/grub

    # Verify the edit
    if grep -q "zswap.enabled=1" /etc/default/grub; then
        pass "zswap parameters added to GRUB config"
    else
        fail "Failed to add zswap to GRUB. Restoring backup."
        cp /etc/default/grub.bak.20260215 /etc/default/grub
        exit 1
    fi
fi

# Verify "quiet" is still there (didn't clobber existing params)
if grep -q "quiet" /etc/default/grub; then
    pass "Existing GRUB 'quiet' parameter preserved"
else
    fail "GRUB edit damaged existing parameters! Restoring."
    cp /etc/default/grub.bak.20260215 /etc/default/grub
    exit 1
fi

# Update GRUB
update-grub 2> /dev/null
pass "GRUB updated (update-grub completed)"

info "Current GRUB_CMDLINE: $(grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub)"

# ═══════════════════════════════════════════════
section "5/7: EARLYOOM INSTALL"
# ═══════════════════════════════════════════════

if dpkg -l earlyoom 2>/dev/null | grep -q "^ii"; then
    info "earlyoom already installed"
else
    info "Installing earlyoom..."
    apt-get install -y earlyoom
    if dpkg -l earlyoom 2>/dev/null | grep -q "^ii"; then
        pass "earlyoom installed"
    else
        fail "earlyoom installation failed"
    fi
fi

# Enable and start
systemctl enable earlyoom > /dev/null 2>&1
systemctl start earlyoom

# Verify running
if systemctl is-active --quiet earlyoom; then
    pass "earlyoom is running"
else
    fail "earlyoom failed to start"
fi

info "earlyoom status: $(systemctl is-active earlyoom) — will gracefully kill largest process before OOM"

# ═══════════════════════════════════════════════
section "6/7: FINAL VERIFICATION"
# ═══════════════════════════════════════════════

echo ""
TOTAL_PASS=0
TOTAL_FAIL=0

verify() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$label: $actual"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} $label: got '$actual', expected '$expected'"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
}

# CPU Governor (check all cores)
for i in 0 1 2 3; do
    GOV=$(cat /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor)
    verify "CPU${i} governor" "performance" "$GOV"
done

# Sysctl values
verify "vm.swappiness" "10" "$(sysctl -n vm.swappiness)"
verify "vm.vfs_cache_pressure" "50" "$(sysctl -n vm.vfs_cache_pressure)"
verify "vm.dirty_ratio" "10" "$(sysctl -n vm.dirty_ratio)"
verify "vm.dirty_background_ratio" "5" "$(sysctl -n vm.dirty_background_ratio)"
verify "vm.dirty_writeback_centisecs" "300" "$(sysctl -n vm.dirty_writeback_centisecs)"

# noatime
if grep " / " /proc/mounts | grep -q "noatime"; then
    pass "Root mount: noatime active"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Root mount: noatime not active"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# zswap
verify "zswap enabled" "Y" "$(cat /sys/module/zswap/parameters/enabled)"

# earlyoom
EARLYOOM_STATUS=$(systemctl is-active earlyoom)
verify "earlyoom service" "active" "$EARLYOOM_STATUS"

# Persistence files exist
if [ -f /etc/sysctl.d/99-performance.conf ]; then
    pass "Sysctl config file exists"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} Sysctl config file missing"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

if systemctl is-enabled --quiet cpu-performance.service 2>/dev/null; then
    pass "cpu-performance.service persistence enabled"
    TOTAL_PASS=$((TOTAL_PASS + 1))
else
    echo -e "${RED}[FAIL]${NC} cpu-performance.service not enabled"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

# ═══════════════════════════════════════════════
section "7/7: SUMMARY"
# ═══════════════════════════════════════════════

echo ""
echo "─── Before vs After ───"
echo "  CPU Governor:      powersave → performance"
echo "  Swappiness:        60 → 10"
echo "  VFS Cache Press:   100 → 50"
echo "  Dirty Ratio:       20/10 → 10/5"
echo "  Root Mount:        defaults → noatime"
echo "  zswap:             disabled → enabled"
echo "  earlyoom:          not installed → running"
echo "  Scheduler:         EEVDF (kernel 6.18 — already optimal)"
echo ""

if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "============================================="
    echo -e "  ${GREEN}ALL $TOTAL_PASS CHECKS PASSED${NC}"
    echo "  System optimized for desktop performance"
    echo "  All changes persist across reboots"
    echo ""
    echo "  Note: Run 'sudo update-grub' after kernel"
    echo "  updates to preserve zswap parameters."
    echo "============================================="
else
    echo "============================================="
    echo -e "  ${RED}$TOTAL_FAIL CHECKS FAILED${NC} out of $((TOTAL_PASS + TOTAL_FAIL))"
    echo "  Review failures above"
    echo "============================================="
    exit 1
fi
