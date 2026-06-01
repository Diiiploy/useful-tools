#!/bin/bash
# Rotate wallpaper to a random image from ~/Pictures/Walls
# Sets both i3 desktop (feh) and GDM3 login screen wallpaper
# Tracks usage count and last-set date for fair rotation

WALLS_DIR="$HOME/Pictures/Walls"
LOG_FILE="$HOME/.local/share/wallpaper.log"
LOGIN_WP="/usr/share/backgrounds/login-wallpaper.jpg"
TRACKER_FILE="$HOME/.local/share/wallpaper-tracker.csv"

# Create tracker file with header if it doesn't exist
if [ ! -f "$TRACKER_FILE" ]; then
    echo "filename|count|last_date" > "$TRACKER_FILE"
fi

# Collect all current image basenames
mapfile -t image_paths < <(find "$WALLS_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \))

if [ ${#image_paths[@]} -eq 0 ]; then
    echo "$(date): No images found in $WALLS_DIR" >> "$LOG_FILE"
    exit 1
fi

# Build array of basenames for comparison
declare -A current_images
for img in "${image_paths[@]}"; do
    base="$(basename "$img")"
    current_images["$base"]=1
done

# --- SYNC TRACKER ---

# Add new wallpapers not yet in tracker (count=0, no date)
for base in "${!current_images[@]}"; do
    if ! grep -qF "$base" "$TRACKER_FILE"; then
        echo "${base}|0|" >> "$TRACKER_FILE"
    fi
done

# Prune stale entries (wallpapers deleted from disk)
tmp_tracker=$(mktemp)
head -1 "$TRACKER_FILE" > "$tmp_tracker"
tail -n +2 "$TRACKER_FILE" | while IFS='|' read -r fname count last_date; do
    if [ -n "${current_images[$fname]+x}" ]; then
        echo "${fname}|${count}|${last_date}" >> "$tmp_tracker"
    fi
done
mv "$tmp_tracker" "$TRACKER_FILE"

# --- PICK WALLPAPER FUNCTION ---
# Picks a wallpaper using tracker-aware selection:
#   1. If zero-count wallpapers exist, pick randomly among them
#   2. Otherwise pick the one with lowest count + oldest date
# After picking, increments count and records today's date.
# Arg $1: "desktop" or "login" (for logging only)
# Prints the full path of the chosen wallpaper.
pick_wallpaper() {
    local role="$1"
    local today
    today="$(date '+%Y-%m-%d')"

    # Collect zero-count entries
    mapfile -t zeros < <(tail -n +2 "$TRACKER_FILE" | awk -F'|' '$2 == 0 {print $1}')

    local chosen=""

    if [ ${#zeros[@]} -gt 0 ]; then
        # Random pick from zero-count wallpapers
        chosen="${zeros[$RANDOM % ${#zeros[@]}]}"
    else
        # Sort by count (asc), then by date (asc, empty first)
        # awk replaces empty date with epoch-zero for proper sorting
        chosen=$(tail -n +2 "$TRACKER_FILE" \
            | awk -F'|' '{d = ($3 == "" ? "0000-00-00" : $3); print $1 "|" $2 "|" d}' \
            | sort -t'|' -k2,2n -k3,3 \
            | head -1 \
            | cut -d'|' -f1)
    fi

    if [ -z "$chosen" ]; then
        echo "$(date): pick_wallpaper($role) failed — no candidates" >> "$LOG_FILE"
        return 1
    fi

    # Update tracker: increment count, set today's date
    tmp_update=$(mktemp)
    head -1 "$TRACKER_FILE" > "$tmp_update"
    tail -n +2 "$TRACKER_FILE" | while IFS='|' read -r fname count last_date; do
        if [ "$fname" = "$chosen" ]; then
            echo "${fname}|$(( count + 1 ))|${today}" >> "$tmp_update"
        else
            echo "${fname}|${count}|${last_date}" >> "$tmp_update"
        fi
    done
    mv "$tmp_update" "$TRACKER_FILE"

    echo "${WALLS_DIR}/${chosen}"
}

# --- MAIN ---

# Need DISPLAY set for cron context
export DISPLAY=":0"
export XAUTHORITY="$HOME/.Xauthority"

# Pick wallpapers using tracker-aware selection
desktop_pick="$(pick_wallpaper desktop)"
login_pick="$(pick_wallpaper login)"

if [ -z "$desktop_pick" ] || [ -z "$login_pick" ]; then
    echo "$(date): Failed to pick wallpapers" >> "$LOG_FILE"
    exit 1
fi

# Set desktop wallpaper with feh
feh --bg-fill "$desktop_pick"

# Set GDM3 login wallpaper (sudoers NOPASSWD allows this)
sudo /usr/bin/cp "$login_pick" "$LOGIN_WP"
sudo /usr/bin/chmod 644 "$LOGIN_WP"

# Log the changes
echo "$(date '+%Y-%m-%d %H:%M') | desktop: $(basename "$desktop_pick") | login: $(basename "$login_pick")" >> "$LOG_FILE"
