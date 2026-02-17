# useful-tools

A collection of utility scripts and tools for Linux systems (Kali/Debian-based). Built for personal use but shared publicly.

## Tools

### PDF

| Tool | Description |
|------|-------------|
| `split-pdf` | Split a large PDF into N evenly-sized chunks. Requires Python 3 + `pypdf`. |

```bash
split-pdf massive-report.pdf 4
split-pdf massive-report.pdf 10 -o ~/chunks/
```

### System

| Tool | Description |
|------|-------------|
| `optimize-system.sh` | Performance tuning: CPU governor, sysctl tweaks, noatime, zswap, earlyoom. |
| `setup-swap.sh` | Add a swapfile alongside an existing swap partition. |

```bash
sudo bash optimize-system.sh
sudo bash setup-swap.sh
```

### Display

| Tool | Description |
|------|-------------|
| `safe-refresh-test.sh` | Safely test monitor refresh rates with auto-revert if it fails. |
| `brightnessControl` | Adjust screen brightness (for i3/polybar keybinds). |
| `volumeControl` | Adjust audio volume (for i3/polybar keybinds). |
| `rotate-wallpaper.sh` | Rotate desktop wallpaper to a random image from `~/Pictures/Walls`. |
| `setup-login-wallpaper.sh` | One-time GDM3 login screen wallpaper setup. |

```bash
bash safe-refresh-test.sh 144
bash rotate-wallpaper.sh
```

### Desktop Apps

| Tool | Description |
|------|-------------|
| `kitty-theme` | Interactive theme switcher for the Kitty terminal emulator. |
| `ncmpcpp-icat` | Wrapper for ncmpcpp music player with Kitty album art display. |
| `whatsie-fix-theme.sh` | Fix Whatsie (WhatsApp) dark mode config persistence across reboots. |

```bash
kitty-theme
ncmpcpp-icat
```

## Installation

Clone the repo and symlink or copy the tools you want into your PATH:

```bash
git clone git@github.com:Diiiploy/useful-tools.git
cd useful-tools

# Symlink a tool into your PATH
ln -s "$(pwd)/split-pdf" ~/.local/bin/split-pdf

# Or copy all
cp * ~/.local/bin/
```

## Dependencies

- **split-pdf**: Python 3, `pypdf` (`pip install pypdf`)
- **ncmpcpp-icat**: Kitty terminal, ncmpcpp, mpd
- **brightnessControl / volumeControl**: `brightnessctl` / `pactl`
- **rotate-wallpaper.sh**: `feh`
- **optimize-system.sh / setup-swap.sh**: Root access

## License

MIT
