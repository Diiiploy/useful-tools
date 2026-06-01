# Security Policy

## Threat Model

`i3-quickphrase` types phrase file contents as keystrokes into the focused
window. **Phrase files must be treated as code, not data.** Anyone who can
write to your `phrases/` directory can effectively type arbitrary text into
whatever window you have focused when you trigger a phrase.

The realistic attackers are:

1. **Drive-by GitHub contributors** opening "helpful" PRs that smuggle
   payloads into phrase files (ANSI escapes, bidi controls, zero-width
   characters, OSC 52 clipboard exfil sequences).
2. **Trevor's own muscle memory**, pressing the trigger into the wrong
   window (a sudo prompt, a GPG pinentry, an IRC channel, a password
   manager).
3. **A future malicious commit** to `install.sh` that adds a hidden
   `curl … | bash` line.

The asset is the input stream of your focused window. On a typical Linux
dev box that's a superset of: terminal sessions, sudo prompts, password
manager search fields, SSH connections, and chat clients.

## Mitigations Built In (v0.1.0)

### Refuse-root install
`install.sh` and `uninstall.sh` exit immediately if invoked as root, to
prevent leaving root-owned files in `$HOME` and creating permission tangles.

### Phrase content allowlist
`lib/validate.sh` rejects any phrase file containing bytes outside:
- Printable ASCII (`0x20`–`0x7E`)
- TAB (`0x09`)
- LF (`0x0A`)

This catches:
- ANSI escape sequences (`\x1b[...`)
- OSC 52 clipboard-write sequences (`\x1b]52;c;…`)
- Trojan Source bidi controls (`\u202a`–`\u202e`, `\u2066`–`\u2069`,
  CVE-2021-42574)
- Zero-width characters (`\u200b`–`\u200f`)
- Any high-bit byte that could form part of a multi-byte exploit

### Symlink rejection
Phrase files must be regular files. A symlinked `phrases/x.txt` →
`/etc/shadow` would be rejected before any read.

### Owner check
`stat -c %u <file>` must equal `id -u`. A phrase file owned by another user
is rejected.

### Phrase name validation
Phrase names must match `^[a-z][a-z0-9_-]*$`. Prevents path traversal
(`i3-quickphrase ../../etc/passwd` is rejected at the regex layer).

### `xdotool --file` (never argv)
Phrase content is read by `xdotool` directly from the file descriptor,
never expanded into a shell variable or passed as a command-line argument.
This prevents:
- Leaking phrase content via `ps auxf`
- Shell metacharacter injection if a future contributor adds command
  substitution

### Captured window ID + `--window <id>`
The active window ID is captured at script start and passed explicitly to
`xdotool --window`. If the user Alt+Tabs to a different window between
trigger and type, the phrase still lands in the *originally* focused
window — defeating the focus-drift race.

### `flock` single-shot guard
A non-blocking `flock` on `$XDG_RUNTIME_DIR/i3-quickphrase/<name>.lock`
prevents key-repeat or rapid double-press from firing the phrase multiple
times.

### `bindsym --release` + explicit `keyup` of all modifiers
Defeats the i3 mod-key release race documented in
[i3 FAQ #478](https://faq.i3wm.org/question/478/how-do-i-simulate-keypresses/index.html).
By using `--release`, the binding only fires after the user releases the
trigger key. Then, before typing, the script explicitly issues
`xdotool keyup Alt_L Alt_R Control_L Control_R Shift_L Shift_R Super_L Super_R`
to clear any modifier that may still be held.

**Important note:** `xdotool --clearmodifiers` is intentionally NOT used.
That flag has a known restore-step bug ([xdotool#43](https://github.com/jordansissel/xdotool/issues/43))
where it re-presses modifiers at the end of typing — if the user has
released them physically by then, X11 ends up with an unmatched synthetic
press and the modifier appears "stuck" until the next physical release.
The explicit `keyup` approach has no restore step, so nothing can get stuck.

### Atomic i3 config edits
`install.sh` writes the modified `~/.config/i3/config` to a temp file,
validates it with `i3 -C`, and only `mv`s it into place on success. A
failed validation leaves your existing config completely untouched.

### BEGIN/END sentinels
The block added to your i3 config is bracketed with `# BEGIN i3-quickphrase`
and `# END i3-quickphrase` comments, so `uninstall.sh` can do a precise
`sed` block-delete with zero risk of nuking unrelated lines.

### Optional window-class allowlist
Set `I3_QUICKPHRASE_ALLOWED_CLASSES=kitty` (or a comma-separated list)
to restrict which window classes can receive a typed phrase. Detection
uses `xprop` on the active window's `WM_CLASS`. Default is `*` (allow
any window) for v0.1.0 to maximize compatibility — set the env var if
you want strict targeting.

## Known Limitations

- **Window-class allowlist disabled by default.** v0.1.0 ships with
  `I3_QUICKPHRASE_ALLOWED_CLASSES=*`, meaning phrases will type into
  whatever window has focus. Set the env var explicitly if your threat
  model requires strict targeting.
- **No defense against malicious commits to your own repo.** If you
  `git pull` malicious changes, the content allowlist will catch most
  payloads but is not a substitute for code review.
- **No defense against an attacker with arbitrary code execution on your
  machine.** This is out of scope.
- **No Wayland support.** xdotool requires X11. Wayland users will need
  to wait for v0.3.0 (planned `lib/inject-wayland.sh` using `ydotool`).

## Reporting Vulnerabilities

Open a private security advisory on GitHub, or email tw22@protonmail.com.

## Out of Scope

- Defeating attackers with arbitrary code execution on your machine
- Defending against malicious i3 config edits performed by other tools
- Wayland (planned for v0.3.0)
- Multi-user systems (the tool is designed for single-user dev workstations)
