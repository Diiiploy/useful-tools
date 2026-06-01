# useful-tools

A collection of utility scripts and tools for Linux systems (Kali/Debian-based). Built for personal use but shared publicly.

## Tools

### PDF & Documents

| Tool | Description |
|------|-------------|
| `split-pdf` | Split a large PDF into N evenly-sized chunks. Requires Python 3 + `pypdf`. |
| `md2pdf` | Convert Markdown to PDF via `pandoc` + headless Chromium. Full emoji / Unicode / table / code-block support, with optional styling from `md2pdf-style.html`. |

```bash
split-pdf massive-report.pdf 4
split-pdf massive-report.pdf 10 -o ~/chunks/

md2pdf notes.md                 # -> notes.pdf
md2pdf notes.md ~/out/notes.pdf
```

### Media

| Tool | Description |
|------|-------------|
| `dlmusic` | Download YouTube (or any `yt-dlp`-supported) audio into `~/Music` with slug-cased filenames. Embeds cover art + metadata, dedupes against existing files, and fires a desktop notification on done/skip/fail. |

```bash
dlmusic                         # read the URL from the X11 clipboard
dlmusic <URL>                   # explicit URL
dlmusic -s <URL>                # split a DJ mix into numbered per-chapter files
```

Filenames land lower-cased and hyphenated, e.g. `Café del Mar — Sunset Mix` becomes
`cafe-del-mar-sunset-mix.opus`. With `-s/--split`, each YouTube chapter becomes its own
file (`slug-01-track-name.opus`, `slug-02-...`) and the full-mix file is removed.

> A Claude Code slash command wrapper lives at [`claude-code/dlmusic.md`](claude-code/dlmusic.md) —
> copy or symlink it to `~/.claude/commands/dlmusic.md` to run `/dlmusic <URL>` from inside Claude Code.

### System

| Tool | Description |
|------|-------------|
| `optimize-system.sh` | Performance tuning: CPU governor, sysctl tweaks, noatime, zswap, earlyoom. |
| `setup-swap.sh` | Add a swapfile alongside an existing swap partition. |
| `mem-refresh.sh` | Reclaim memory without rebooting: drop kernel caches, kill idle Zoom, vacuum the journal, clean old `/tmp`, and report before/after savings. |
| `zoom-cleanup.sh` | Kill orphaned Zoom processes after a meeting ends. Inspects every mapped Zoom window by geometry and only kills when no real-sized window remains (120s startup grace period). Designed to run on a systemd timer. |

```bash
sudo bash optimize-system.sh
sudo bash setup-swap.sh
bash mem-refresh.sh
```

### Display & Audio

| Tool | Description |
|------|-------------|
| `safe-refresh-test.sh` | Safely test monitor refresh rates with auto-revert if it fails. |
| `brightnessControl` | Adjust screen brightness (for i3/polybar keybinds). |
| `volumeControl` | Adjust audio volume (for i3/polybar keybinds). |
| `audio-sink-cycle` | Cycle the PipeWire default sink through Analog → HDMI → each connected Bluetooth sink, handling the ACP profile switch and moving active streams. **Edit the hardware constants near the top (`CARD`, sink names) for your machine.** |
| `rotate-wallpaper.sh` | Rotate the desktop (feh) + GDM3 login wallpaper from `~/Pictures/Walls`, with fair-rotation tracking so every wallpaper gets shown before repeats. |
| `wallpaper-scraper.py` | Download trending ultrawide wallpapers from Wallhaven + Reddit (no key needed); optional Unsplash/Pixabay with API keys. Category filters, dedupe, dry-run, and a weekly-cron installer. |
| `setup-login-wallpaper.sh` | One-time GDM3 login screen wallpaper setup. |

```bash
bash safe-refresh-test.sh 144
audio-sink-cycle               # bind to an i3 keybind to toggle outputs
bash rotate-wallpaper.sh
python3 wallpaper-scraper.py --dry-run
```

### Network

| Tool | Description |
|------|-------------|
| `awus052nh-watch.sh` | User-space systemd watcher for an AWUS052NH USB Wi-Fi adapter; watches a state file via `inotifywait` and launches a Rofi dialog when the adapter is ready. Part of a larger AWUS052NH setup — it expects a config at `/etc/awus052nh/config`, a state file under `/run/awus052nh/`, and a dialog helper, so it is included here as a reference rather than a standalone tool. |

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
ln -s "$(pwd)/dlmusic" ~/.local/bin/dlmusic
ln -s "$(pwd)/split-pdf" ~/.local/bin/split-pdf
```

A few tools want extra files in specific locations:

```bash
# md2pdf's optional stylesheet
mkdir -p ~/.local/share/pandoc
cp md2pdf-style.html ~/.local/share/pandoc/

# Claude Code /dlmusic slash command
ln -s "$(pwd)/claude-code/dlmusic.md" ~/.claude/commands/dlmusic.md
```

## Dependencies

- **split-pdf**: Python 3, `pypdf` (`pip install pypdf`)
- **md2pdf**: `pandoc`, `chromium` (headless). The stylesheet `md2pdf-style.html` is optional — copy it to `~/.local/share/pandoc/` for the nicer look; without it `md2pdf` still works.
- **dlmusic**: `yt-dlp` (`pipx install yt-dlp`), plus `pipx inject yt-dlp mutagen` so thumbnail/cover-art embedding works. Uses `xclip`/`xsel`/`wl-paste` for clipboard reads and `notify-send` for notifications (all optional).
- **mem-refresh.sh / optimize-system.sh / setup-swap.sh**: Root access (sudo)
- **audio-sink-cycle**: PipeWire/PulseAudio (`pactl`), `bluetoothctl`, `dunstify`. Hardware constants at the top are specific to one machine — edit them for yours.
- **rotate-wallpaper.sh**: `feh`
- **wallpaper-scraper.py**: Python 3, `requests`, `Pillow` (`pip install requests Pillow`)
- **awus052nh-watch.sh**: `inotify-tools`, `rofi`; part of a larger AWUS052NH setup (config + state file + dialog helper)
- **ncmpcpp-icat**: Kitty terminal, ncmpcpp, mpd
- **brightnessControl / volumeControl**: `brightnessctl` / `pactl`

## License

MIT — see [LICENSE](LICENSE).
