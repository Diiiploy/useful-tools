#!/bin/bash
# Rotate wallpaper to a random image from ~/Pictures/Walls
# Sets both i3 desktop (feh) and GDM3 login screen wallpaper

WALLS_DIR="$HOME/Pictures/Walls"
LOG_FILE="$HOME/.local/share/wallpaper.log"
LOGIN_WP="/usr/share/backgrounds/login-wallpaper.jpg"

# Only pick regular image files (not subdirectories)
mapfile -t images < <(find "$WALLS_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \))

if [ ${#images[@]} -eq 0 ]; then
    echo "$(date): No images found in $WALLS_DIR" >> "$LOG_FILE"
    exit 1
fi

# Pick two different random wallpapers (desktop + login)
desktop_pick="${images[$RANDOM % ${#images[@]}]}"
login_pick="${images[$RANDOM % ${#images[@]}]}"

# Need DISPLAY set for cron context
export DISPLAY=":0"
export XAUTHORITY="$HOME/.Xauthority"

# Set desktop wallpaper with feh
feh --bg-fill "$desktop_pick"

# Set GDM3 login wallpaper (sudoers NOPASSWD allows this)
sudo /usr/bin/cp "$login_pick" "$LOGIN_WP"
sudo /usr/bin/chmod 644 "$LOGIN_WP"

# Log the changes
echo "$(date '+%Y-%m-%d %H:%M') | desktop: $(basename "$desktop_pick") | login: $(basename "$login_pick")" >> "$LOG_FILE"
