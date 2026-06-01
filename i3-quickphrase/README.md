# i3-quickphrase

> Bind an i3 keyboard shortcut to type a fixed phrase into the focused window.

Press a key, your phrase types itself. Stop typing the same prompt fifty times a day.

## Install

```sh
git clone git@github.com:cr4shOverr1de/i3-quickphrase ~/projects/i3-quickphrase
cd ~/projects/i3-quickphrase && ./install.sh
```

The installer is idempotent, refuses to run as root, validates your i3 config with `i3 -C` before swapping it, and adds a clearly-marked `BEGIN i3-quickphrase` / `END i3-quickphrase` block to `~/.config/i3/config` so uninstall is surgical.

## Use

The default install ships one phrase, bound to **Alt+M**:

> Use comprehensive effort, your time is unlimited, I prefer maximum quality over speed.

Focus a window, press Alt+M, watch it type.

## Add a phrase

Three steps. No CLI to learn — convention over command.

```sh
# 1. Create the phrase file
#    Use printf (not echo) so you can include a trailing space without a newline.
printf 'Please review this carefully. ' > phrases/review.txt

# 2. Add a binding to dist/i3-quickphrase.conf
echo 'bindsym --release $mod+r exec --no-startup-id ~/.local/bin/i3-quickphrase review' \
     >> dist/i3-quickphrase.conf

# 3. Reload i3
i3-msg reload
```

That's it. Press Alt+R, your new phrase types itself.

## Diagnostics

```sh
i3-quickphrase doctor
```

Reports: dependencies, phrase files (with size and validation status), `DISPLAY`, active window class, and current allowlist.

## Window-class allowlist (optional)

By default the tool types into any focused window. To restrict (e.g., only type into kitty), set:

```sh
export I3_QUICKPHRASE_ALLOWED_CLASSES=kitty
```

Or comma-separated: `kitty,Firefox,Chromium`. The check uses `xprop` on the active window's `WM_CLASS`. If `xprop` is not installed and the env var is set, the script aborts.

## Requirements

- Linux + i3wm + X11 (Wayland not supported in v0.1.0 — see `DESIGN.md` for v0.3.0 plans)
- Required: `xdotool`, `i3`, `i3-msg`
- Recommended: `xprop` (class allowlist), `notify-send` (visible errors), `flock` (reentry guard)
- Install on Debian/Ubuntu/Kali: `sudo apt install xdotool x11-utils libnotify-bin util-linux i3`

## Uninstall

```sh
~/projects/i3-quickphrase/uninstall.sh
```

Removes the binary symlink, the i3 dropin, and the `BEGIN i3-quickphrase` / `END i3-quickphrase` block in `~/.config/i3/config`. The repo directory is left untouched — delete it manually if you want it gone.

## Why

Some prompts you type fifty times a day. "Please continue.", "Run the tests.", "Use maximum effort." Stop typing them. Bind them to a key. Get back to thinking.

## Security

Phrase files are typed as keystrokes into your focused window — **treat them as code**. The script enforces:

- Phrase files must be regular files (no symlinks)
- Phrase files must be owned by you
- Phrase content must be printable ASCII + TAB + LF only (rejects ANSI escape injection, OSC 52 clipboard exfil, Trojan Source bidi controls, zero-width characters)
- Install/uninstall scripts refuse to run as root
- Single-shot `flock` prevents key-repeat double-fire
- Window ID is captured at script start and passed to `xdotool --window <id>`, defeating focus-drift races
- `bindsym --release` + `--clearmodifiers` defeats the i3 mod-key release race so xdotool isn't typing while Alt is still held
- Optional `I3_QUICKPHRASE_ALLOWED_CLASSES` env var restricts which window classes can receive a phrase

See [`SECURITY.md`](SECURITY.md) for the full threat model.

## Roadmap

See [`DESIGN.md`](DESIGN.md). v0.2.0 ships a full stateful CLI (`qp add | list | edit | remove | test`); v0.3.0 adds a Wayland backend.

## License

MIT — see [`LICENSE`](LICENSE).
