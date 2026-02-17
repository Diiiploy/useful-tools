#!/bin/bash
# One-time setup for GDM3 login wallpaper rotation
# Run this script with: sudo bash ~/.local/bin/setup-login-wallpaper.sh

set -e

USER_HOME="/home/cr4sh"
LOGIN_WP="/usr/share/backgrounds/login-wallpaper.jpg"
THEME_CSS="/usr/share/themes/Kali-Dark/gnome-shell/gnome-shell.css"

echo "[1/3] Creating initial login wallpaper..."
RANDOM_WALL=$(find "$USER_HOME/Pictures/Walls" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) | shuf -n1)
cp "$RANDOM_WALL" "$LOGIN_WP"
chmod 644 "$LOGIN_WP"
echo "  -> Copied: $(basename "$RANDOM_WALL")"

echo "[2/3] Patching GDM3 Kali theme CSS..."
# Backup original
if [ ! -f "${THEME_CSS}.bak" ]; then
    cp "$THEME_CSS" "${THEME_CSS}.bak"
    echo "  -> Backup saved to ${THEME_CSS}.bak"
fi
# Replace the #lockDialogGroup background with our image
sed -i '/#lockDialogGroup {/,/}/ s|background-color: #272a34;|background: url(file:///usr/share/backgrounds/login-wallpaper.jpg) no-repeat center center;\n  background-size: cover;|' "$THEME_CSS"
echo "  -> CSS patched"

echo "[3/3] Adding sudoers rule for passwordless wallpaper rotation..."
cat > /etc/sudoers.d/login-wallpaper << 'EOF'
# Allow cr4sh to update login wallpaper without password
cr4sh ALL=(root) NOPASSWD: /usr/bin/cp * /usr/share/backgrounds/login-wallpaper.jpg
cr4sh ALL=(root) NOPASSWD: /usr/bin/chmod 644 /usr/share/backgrounds/login-wallpaper.jpg
EOF
chmod 440 /etc/sudoers.d/login-wallpaper
echo "  -> Sudoers rule installed"

echo ""
echo "Done! Your GDM3 login screen will now show a random wallpaper."
echo "Test it by running: ~/.local/bin/rotate-wallpaper.sh"
