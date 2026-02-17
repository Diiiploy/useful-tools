#!/bin/bash
# Ensures Whatsie dark mode config persists across reboots.
# Snap-confined Qt apps can lose their QSettings if killed during shutdown.
# This restores the config from a backup in the persistent common directory.

SNAP_DATA="$HOME/snap/whatsie/current/.config/org.keshavnrj.ubuntu"
BACKUP="$HOME/snap/whatsie/common/WhatSie.conf.bak"
CONF="$SNAP_DATA/WhatSie.conf"

case "${1:-restore}" in
    restore)
        if [ -f "$BACKUP" ]; then
            if [ ! -f "$CONF" ] || ! grep -q 'windowTheme=dark' "$CONF"; then
                mkdir -p "$SNAP_DATA"
                cp "$BACKUP" "$CONF"
            fi
        fi
        ;;
    backup)
        if [ -f "$CONF" ]; then
            cp "$CONF" "$BACKUP"
            echo "Backed up config to $BACKUP"
        else
            echo "No config file found at $CONF"
            exit 1
        fi
        ;;
esac
