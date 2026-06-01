# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.6] — 2026-04-20

### Changed
- **`SPACE_SETTLE` default lowered from `0.15` (150 ms) to `0.1`
  (100 ms).** v0.1.5's 150 ms reliably cleared Claude Code's
  voice-mode detector but added ~1.4 s of wall time to the
  `comprehensive` phrase vs v0.1.3. Live testing confirmed 100 ms is
  sufficient — worst-case inter-space gap is still ~125 ms, ~4×
  X11's default 30 ms repeat rate. Trims ~650 ms off total runtime
  (now ~1.6 s total, vs ~2.0 s at v0.1.5).
- If your setup needs more margin, bump via the env var (e.g.
  `I3_QUICKPHRASE_SPACE_SETTLE=0.15`). 150 ms remains the proven-
  reliable value; 100 ms is the proven-minimum.

### Preserved (no regression)
- All v0.1.5 / v0.1.4 / v0.1.3 / v0.1.1 / v0.1.0 invariants unchanged.

### Found by
Trevor in live A/B testing of v0.1.5 → dial-down to 0.1, 2026-04-20.

## [0.1.5] — 2026-04-20

### Changed
- **`SPACE_SETTLE` default raised from `0.05` (50 ms) to `0.15`
  (150 ms).** Live testing of v0.1.4 showed that 50 ms still tripped
  Claude Code's voice-mode detector on some setups — the worst-case
  inter-space gap (~75 ms, after a single-character word like "I")
  appears to be inside the detector's sensitivity window, which
  looks closer to 100 ms than to X11's 30 ms key-repeat rate.
  150 ms lifts the worst case to ~175 ms — comfortably outside.
  Total phrase runtime rises to ~2.0 s (was ~1.6 s at v0.1.4,
  ~1.0 s at v0.1.3).

### Tuning guide (if 150 ms still isn't enough)
- Bump via the env var without editing code:
    `I3_QUICKPHRASE_SPACE_SETTLE=0.2 ~/.local/bin/i3-quickphrase comprehensive`
- To persist in the i3 binding, edit
  `~/projects/i3-quickphrase/dist/i3-quickphrase.conf` and change:
    `bindsym --release $mod+m exec --no-startup-id ~/.local/bin/i3-quickphrase comprehensive`
  to:
    `bindsym --release $mod+m exec --no-startup-id env I3_QUICKPHRASE_SPACE_SETTLE=0.2 ~/.local/bin/i3-quickphrase comprehensive`
  Then run `i3-msg reload`.
- Step up in 50 ms increments: `0.2`, `0.25`, `0.3`. Each 50 ms
  adds ~0.65 s to the 13-space `comprehensive` phrase runtime.

### Preserved (no regression)
- All v0.1.4 / v0.1.3 / v0.1.1 / v0.1.0 invariants unchanged.

### Found by
Trevor in live Alt+M / Alt+. re-testing of v0.1.4, 2026-04-20.

## [0.1.4] — 2026-04-20

### Fixed
- **Residual voice-mode triggering after v0.1.3.** v0.1.3's hybrid
  emission (`xdotool type` for words, `xdotool key --delay 0 space`
  for spaces) reduced the dropped-space rate from "more often than
  not" to ~30 %. The remaining failures were reproducibly localized
  to phrase positions where a single-character word ("I" in
  `comprehensive`, "I" and "me" in `clarify`) sits between two spaces:
  the gap between consecutive space events there collapses to
  `type("I")` + xdotool process startup ≈ 25 ms, which is inside
  X11's default 30 ms key-repeat rate and reads to Claude Code's
  voice-mode detector as a held-space event. The dwell itself was no
  longer the problem — `xdotool key --delay 0 space` emits a
  press+release pair separated only by one `XFlush` (sub-millisecond),
  which is the tightest dwell possible without switching tools.

### Changed
- `bin/i3-quickphrase`: added a `$SPACE_SETTLE`-seconds sleep after
  each `xdotool key space` emission so that consecutive space events
  are always separated by more than X11's repeat rate, regardless of
  the word between them. Default `SPACE_SETTLE=0.05` (50 ms) lifts the
  worst-case inter-space gap to ~75 ms, safely outside the detection
  window. Total extra runtime for the 13-space `comprehensive` phrase
  is ~650 ms.
- New env var `I3_QUICKPHRASE_SPACE_SETTLE` overrides the default at
  runtime. Set to `0.1` if 50 ms still triggers voice mode on your
  setup, or `0` to disable the settle entirely (useful for target
  apps that don't have Claude Code's voice-mode debouncing).
- `VERSION` bumped to `0.1.4`.

### Preserved (no regression)
- All v0.1.3 fixes: hybrid emission, `xdotool key --delay 0` for
  spaces, per-run `--file -` (stdin), pure-bash character loop.
- All v0.1.1 / v0.1.0 invariants: explicit modifier keyup, 30 ms
  propagation sleep, `flock -n` single-shot, `--window` on every
  xdotool call, validation allowlist.
- Phrase file byte-for-byte integrity (87 bytes `comprehensive`, 78
  bytes `clarify`, trailing space preserved in both).

### Found by
Trevor in live Alt+M / Alt+. re-testing of v0.1.3, 2026-04-20.
Observed "~7/10 success" pattern with the voice UI (rainbow cursor)
flashing on the failing trials. Root cause re-diagnosed as
inter-space event rate rather than per-event dwell.

## [0.1.3] — 2026-04-20

### Fixed
- **Dropped spaces when typing into Claude Code's CLI prompt.** v0.1.2's
  `xdotool type --file --delay 12` held each synthetic `KeyPress` open
  for several milliseconds before the matching `KeyRelease` — xdotool
  v3.20160805.1's `CHARDELAY` floor in `xdo_enter_text_window`
  ([xdo.c:958](https://github.com/jordansissel/xdotool/blob/v3.20160805.1/xdo.c#L958))
  plus X11 `XSync` + `XkbLockGroup` + `XFlush` roundtrip per event.
  Claude Code's push-to-talk voice mode (added ~v2.1.69) interprets
  held-space as a "start recording" intent and retroactively removes
  the 1-2 most recent spaces from its prompt buffer. On phrases like
  `comprehensive` (87 bytes, 13 interior + trailing spaces) this shows
  up as random words running together — `"usecomprehensive effort,"` or
  `"your time is unlimitedI prefer"` — and a brief voice-mode UI flash.
  Other apps (kitty itself, browsers, editors) don't implement this
  retroactive-delete so they were unaffected.

  Matches upstream reports
  [anthropics/claude-code#37932](https://github.com/anthropics/claude-code/issues/37932)
  (Linux synthetic-keystroke space loss) and
  [#38620](https://github.com/anthropics/claude-code/issues/38620)
  (synthesized-paste regression).

### Changed
- `bin/i3-quickphrase`: replaced the single whole-phrase `xdotool type`
  call with a hybrid emission loop:
  - Non-space runs type through `xdotool type --delay 12 --file -`
    (stdin-fed so the byte-literal / no-argv-leak guarantee holds
    per-run, not just once).
  - Each ASCII `0x20` goes through `xdotool key --delay 0 --window
    "$active_id" space`, which emits `KeyPress`+`KeyRelease`
    back-to-back via a single XTEST call pair — sub-millisecond hold,
    below Claude Code's voice-mode detection window.
  - A pure-bash character loop drives the split so leading, trailing,
    and back-to-back spaces are preserved exactly (`awk RS=" "` drops
    the trailing empty record on many awks — would have silently eaten
    the load-bearing trailing space on both default phrases).
- `VERSION` bumped from `0.1.0` to `0.1.3` (was never updated when
  `0.1.1` and `0.1.2` landed — caught during this fix).

### Preserved (no regression)
- Explicit `xdotool keyup Alt_L Alt_R Control_L Control_R Shift_L
  Shift_R Super_L Super_R` before typing (v0.1.1 stuck-modifier fix).
- `sleep 0.03` propagation delay after keyup.
- `--window "$active_id"` on every `xdotool` call (focus-drift
  safety) — now applies to both `type` and `key` calls, strengthening
  the invariant.
- `flock -n` single-shot guard against key-repeat reentry.
- `lib/validate.sh` phrase-content allowlist (printable ASCII + TAB +
  LF) and phrase-name regex.
- Trailing-space preservation in `phrases/*.txt` (verified via
  byte-count test against both `comprehensive.txt` and `clarify.txt`).

### Found by
Trevor in live Alt+M / Alt+. testing into Claude Code running in
kitty on X11 Kali, 2026-04-20. Root cause localized to xdotool's
press-release dwell via source-level archaeology of xdotool v2016
(`xdo.c:958-1006`, `_xdo_send_key:1512`) and Claude Code's
[voice-dictation docs](https://code.claude.com/docs/en/voice-dictation)
("Claude Code detects a held key by watching for rapid key-repeat
events from your terminal, so there is a brief warmup before recording
begins"). `xdotool key` bypasses the chardelay path entirely.

## [0.1.2] — 2026-04-08

### Added
- New default phrase: `clarify` bound to `Alt+period`. Content:
  "Ask me clarifying questions until you're 98% sure you understand what
  I want. " (78 bytes exact, trailing space preserved, no trailing LF).
- Chosen after verifying Trevor's preferred Alt+N was taken by Arszilla's
  `border normal` binding at `keybinds.conf:47`. Alt+period was selected
  as the closest physically-adjacent free key to Alt+M on QWERTY.

### Framework validation
- **First real test of the "convention over CLI" extensibility claim.**
  Adding phrase #2 took exactly three commands:
  1. `printf '%s' "..." > phrases/clarify.txt`
  2. Append one `bindsym` line to `dist/i3-quickphrase.conf`
  3. `i3-msg reload`
  The Architect seat's argument against the Designer's full stateful CLI
  was vindicated — no `qp add` wizard needed at the 2-phrase scale.

## [0.1.1] — 2026-04-07

### Fixed
- **Stuck Alt modifier after typing.** v0.1.0 used
  `xdotool type --clearmodifiers`, which has a known restore-step bug
  ([xdotool#43](https://github.com/jordansissel/xdotool/issues/43)):
  it re-presses modifiers at the end of typing, leaving them "stuck" if
  the user has already released them physically. v0.1.1 replaces the
  `--clearmodifiers` flag with an explicit
  `xdotool keyup Alt_L Alt_R Control_L Control_R Shift_L Shift_R Super_L Super_R`
  before typing, plus a 30 ms propagation sleep. The keyup approach has
  no restore step so nothing can get stuck. Found by Trevor in live
  testing of v0.1.0.

### Changed
- `bin/i3-quickphrase` injection block: dropped `--clearmodifiers`,
  added explicit `keyup` of all common modifier keys with a `2>/dev/null
  || true` so the keyup never fails the script.
- `SECURITY.md` and `DESIGN.md` updated to document the new approach.

## [0.1.0] — 2026-04-07

### Added
- Initial release.
- `bin/i3-quickphrase` typing tool. Subcommands: `<phrase-name>` (type),
  `doctor` (diagnostics), `--version`, `--help`.
- `lib/validate.sh` sourced phrase file/name validators (printable ASCII
  allowlist, symlink rejection, owner check).
- `phrases/comprehensive.txt` example phrase (87 bytes exact, no trailing
  LF, mapped to `Alt+M`).
- `dist/i3-quickphrase.conf` i3 binding snippet with extension instructions.
- `install.sh`: idempotent, refuses root, validates i3 config with `i3 -C`
  before atomic swap, BEGIN/END sentinels, symlink-based file management,
  `chmod 700/600` on phrases directory and files.
- `uninstall.sh`: symmetric to install, surgical `sed` block-delete using
  the BEGIN/END sentinels, repo directory left intact.
- `xdotool type --clearmodifiers --delay 12 --window <captured-id> --file`
  injection mechanism (per Researcher and Pentester recommendations).
- `flock` single-shot guard against key-repeat and double-press reentry.
- Optional `I3_QUICKPHRASE_ALLOWED_CLASSES` env var allowlist (default
  `*` = allow any window).
- `.editorconfig`: `trim_trailing_whitespace = false` and
  `insert_final_newline = false` for `phrases/*.txt` to protect the
  trailing-space convention.
- `.gitattributes`: `phrases/*.txt -text` to prevent git LF normalization.
- `.github/workflows/ci.yml`: shellcheck on all shell scripts plus
  phrase-content allowlist and bidi-control detection.
- `README.md`, `SECURITY.md`, `DESIGN.md`, `LICENSE` (MIT).

### Security
- Strict ASCII allowlist on phrase content rejects ANSI escapes, OSC 52
  clipboard exfil, Trojan Source bidi controls, and zero-width characters.
- Phrase names validated against `^[a-z][a-z0-9_-]*$` to prevent path
  traversal.
- `xdotool --file` mode (never argv) prevents content leaking via
  `ps auxf` and prevents shell metacharacter injection.
- Captured-window-ID + `--window` defeats focus-drift races.
- Refuse-root install/uninstall.

[0.1.0]: https://github.com/cr4shOverr1de/i3-quickphrase/releases/tag/v0.1.0
[0.1.1]: https://github.com/cr4shOverr1de/i3-quickphrase/releases/tag/v0.1.1
[0.1.2]: https://github.com/cr4shOverr1de/i3-quickphrase/releases/tag/v0.1.2
[0.1.3]: https://github.com/cr4shOverr1de/i3-quickphrase/releases/tag/v0.1.3
[0.1.4]: https://github.com/cr4shOverr1de/i3-quickphrase/releases/tag/v0.1.4
[0.1.5]: https://github.com/cr4shOverr1de/i3-quickphrase/releases/tag/v0.1.5
[0.1.6]: https://github.com/cr4shOverr1de/i3-quickphrase/releases/tag/v0.1.6
