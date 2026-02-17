#!/bin/bash
# Safe refresh rate test with auto-revert
# If the new rate doesn't work or you can't confirm, it reverts automatically.
#
# Usage: bash safe-refresh-test.sh [rate]
#   rate: 100, 120, 75, etc. (default: 100)
#
# HDMI 1.4 bandwidth limits at 2560x1080:
#   60Hz  = 185 MHz (works)
#   75Hz  = 243 MHz (works)
#   100Hz = 308 MHz (works at 8bpc — max for HDMI 1.4)
#   120Hz = 369 MHz (EXCEEDS 340 MHz — requires DisplayPort)
#   144Hz = 443 MHz (EXCEEDS 340 MHz — requires DisplayPort)

OUTPUT="HDMI-1"
NEW_RATE="${1:-99.94}"
OLD_RATE="59.94"
RESOLUTION="2560x1080"
TIMEOUT=10

# Save current max bpc so we can restore on revert
OLD_BPC=$(xrandr --prop 2>/dev/null | awk '/max bpc:/{print $NF; exit}')
OLD_BPC=${OLD_BPC:-12}

echo "Current mode: ${RESOLUTION} @ ${OLD_RATE}Hz (${OLD_BPC}bpc)"
echo "Testing:      ${RESOLUTION} @ ${NEW_RATE}Hz (8bpc)"
echo ""
echo "NOTE: Dropping color depth to 8bpc to fit HDMI 1.4 bandwidth."
echo "Switching in 3 seconds... (Ctrl+C to abort)"
sleep 3

# Drop color depth to 8bpc FIRST (required for HDMI 1.4 bandwidth)
xrandr --output "$OUTPUT" --set "max bpc" 8

# Switch to the new refresh rate
xrandr --output "$OUTPUT" --mode "$RESOLUTION" --rate "$NEW_RATE"

echo ""
echo "============================================="
echo " Display set to ${NEW_RATE}Hz @ 8bpc"
echo " Type 'y' within ${TIMEOUT} seconds to KEEP it."
echo " Otherwise it will revert to ${OLD_RATE}Hz @ ${OLD_BPC}bpc."
echo "============================================="

# Read with timeout - if no 'y' received, revert
if read -t "$TIMEOUT" -p "> " response && [ "$response" = "y" ]; then
    echo ""
    echo "Confirmed! Keeping ${NEW_RATE}Hz @ 8bpc."
else
    echo ""
    echo "No confirmation received. Reverting to ${OLD_RATE}Hz..."
    xrandr --output "$OUTPUT" --mode "$RESOLUTION" --rate "$OLD_RATE"
    xrandr --output "$OUTPUT" --set "max bpc" "$OLD_BPC"
    echo "Reverted to ${OLD_RATE}Hz @ ${OLD_BPC}bpc."
fi
