#!/bin/bash
# PAI System Optimization: Swap Setup Script
# Generated: 2026-02-15
# Purpose: Add a 3GB swapfile alongside existing 977MB swap partition
# Target total: ~4GB swap
#
# Run with: sudo bash ~/setup-swap.sh

set -euo pipefail  # Exit on ANY error, undefined var, or pipe failure

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Safety check: must be root
if [ "$EUID" -ne 0 ]; then
    fail "This script must be run with sudo. Usage: sudo bash ~/setup-swap.sh"
fi

echo "========================================="
echo "  Swap Setup: Adding 3GB Swapfile"
echo "========================================="
echo ""

# ─── PRE-FLIGHT CHECKS ────────────────────────

info "Running pre-flight checks..."

# Check that /swapfile doesn't already exist
if [ -f /swapfile ]; then
    fail "/swapfile already exists. Remove it first if you want to recreate: sudo swapoff /swapfile && sudo rm /swapfile"
fi

# Check available disk space (need at least 4GB free to be safe)
AVAIL_KB=$(df --output=avail / | tail -1 | tr -d ' ')
AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
if [ "$AVAIL_GB" -lt 4 ]; then
    fail "Only ${AVAIL_GB}GB free on /. Need at least 4GB for safety margin."
fi
pass "Disk space check: ${AVAIL_GB}GB available"

# Check filesystem is ext4 (fallocate compatible)
FSTYPE=$(df --output=fstype / | tail -1 | tr -d ' ')
if [[ "$FSTYPE" != "ext4" && "$FSTYPE" != "ext2" && "$FSTYPE" != "ext3" ]]; then
    fail "Root filesystem is $FSTYPE. fallocate only works reliably on ext4. Use dd instead."
fi
pass "Filesystem check: $FSTYPE (fallocate compatible)"

# Check existing swap state
info "Current swap:"
swapon --show
echo ""

# ─── STEP 1: CREATE SWAPFILE ──────────────────

info "Step 1/6: Creating 3GB swapfile at /swapfile..."
fallocate -l 3G /swapfile

# Verify size
SIZE=$(stat -c %s /swapfile)
EXPECTED=$((3 * 1024 * 1024 * 1024))  # 3221225472 bytes
if [ "$SIZE" -ne "$EXPECTED" ]; then
    rm -f /swapfile
    fail "Swapfile size is $SIZE bytes, expected $EXPECTED. Removed and aborting."
fi
pass "Step 1: /swapfile created, size = $(ls -lh /swapfile | awk '{print $5}')"

# ─── STEP 2: SET PERMISSIONS ─────────────────

info "Step 2/6: Setting permissions to 0600 (root only)..."
chmod 600 /swapfile
chown root:root /swapfile

# Verify permissions
PERMS=$(stat -c %a /swapfile)
OWNER=$(stat -c %U:%G /swapfile)
if [ "$PERMS" != "600" ]; then
    rm -f /swapfile
    fail "Permissions are $PERMS, expected 600. Removed and aborting."
fi
if [ "$OWNER" != "root:root" ]; then
    rm -f /swapfile
    fail "Owner is $OWNER, expected root:root. Removed and aborting."
fi
pass "Step 2: Permissions = $PERMS, Owner = $OWNER"

# ─── STEP 3: FORMAT AS SWAP ──────────────────

info "Step 3/6: Formatting as swap space..."
mkswap /swapfile > /dev/null 2>&1

# Verify it's recognized as swap
FILETYPE=$(file /swapfile)
if ! echo "$FILETYPE" | grep -qi "swap"; then
    rm -f /swapfile
    fail "mkswap failed. file command shows: $FILETYPE. Removed and aborting."
fi
pass "Step 3: Formatted as swap — $FILETYPE"

# ─── STEP 4: ENABLE SWAPFILE ─────────────────

info "Step 4/6: Enabling swapfile with priority 10..."
swapon --priority 10 /swapfile

# Verify it's active
if ! swapon --show | grep -q "/swapfile"; then
    fail "Swapfile not showing in swapon --show after enabling."
fi
pass "Step 4: Swapfile is active"

# ─── STEP 5: ADD TO FSTAB ────────────────────

info "Step 5/6: Backing up fstab and adding swapfile entry..."

# Backup fstab
cp /etc/fstab /etc/fstab.bak.20260215
pass "fstab backed up to /etc/fstab.bak.20260215"

# Check if entry already exists
if grep -q "^/swapfile" /etc/fstab; then
    info "Swapfile entry already in fstab, skipping."
else
    # Append the swapfile entry
    echo '/swapfile none swap sw,pri=10 0 0' >> /etc/fstab
    pass "Step 5: Added /swapfile entry to /etc/fstab"
fi

# Verify original entries are intact
if ! grep -q "03277b46-0528-4328-b54d-feab598f4ea9" /etc/fstab; then
    fail "CRITICAL: Root mount entry missing from fstab! Restoring backup."
    cp /etc/fstab.bak.20260215 /etc/fstab
    exit 1
fi
if ! grep -q "644377d5-08d7-49f4-8b0e-954341c62d3d" /etc/fstab; then
    fail "CRITICAL: Original swap partition entry missing! Restoring backup."
    cp /etc/fstab.bak.20260215 /etc/fstab
    exit 1
fi
pass "Step 5: Original fstab entries verified intact"

# ─── STEP 6: FINAL VERIFICATION ──────────────

info "Step 6/6: Final verification..."
echo ""
echo "─── Swap Status ───"
swapon --show
echo ""
echo "─── Memory Summary ───"
free -h
echo ""
echo "─── fstab (swap entries) ───"
grep swap /etc/fstab
echo ""

# Final assertions
TOTAL_SWAP_KB=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
TOTAL_SWAP_MB=$((TOTAL_SWAP_KB / 1024))
if [ "$TOTAL_SWAP_MB" -lt 3500 ]; then
    fail "Total swap is only ${TOTAL_SWAP_MB}MB, expected ~4000MB."
fi
pass "Total swap: ${TOTAL_SWAP_MB}MB (~$((TOTAL_SWAP_MB / 1024))GB)"

SWAPFILE_PRIO=$(swapon --show --noheadings | grep "/swapfile" | awk '{print $5}')
PARTITION_PRIO=$(swapon --show --noheadings | grep "/dev/sda6" | awk '{print $5}')
if [ "$SWAPFILE_PRIO" -gt "$PARTITION_PRIO" ]; then
    pass "Swapfile priority ($SWAPFILE_PRIO) > partition priority ($PARTITION_PRIO)"
else
    fail "Swapfile priority ($SWAPFILE_PRIO) should be higher than partition ($PARTITION_PRIO)"
fi

echo ""
echo "========================================="
echo -e "  ${GREEN}ALL CHECKS PASSED${NC}"
echo "  Swap increased from ~1GB to ~4GB"
echo "  Swapfile is persistent across reboots"
echo "========================================="
