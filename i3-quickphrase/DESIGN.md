# Design Notes & Roadmap

## v0.1.0 (current) — Hardened minimal framework

A small, opinionated, security-conscious foundation. The `i3-quickphrase`
binary takes a phrase name and types the matching phrase into the
captured-active-window. Adding a new phrase is filesystem-only:

1. `printf 'Your phrase ' > phrases/yourname.txt`
2. Append a `bindsym` line to `dist/i3-quickphrase.conf`
3. `i3-msg reload`

**Convention over CLI.** The framework's extensibility comes from
filesystem conventions, not from a stateful command surface. Three steps,
no flags to remember, no command grammar to learn.

This was the v0.1.0 design winner from a 5-agent council debate (Engineer,
Architect, Researcher, Designer, Pentester) across five rounds. The
Designer's full stateful CLI vision was deferred to v0.2.0 to keep v0.1.0
shippable and auditable.

## v0.2.0 (planned) — Full stateful CLI (the Designer's vision)

A friendly command surface on top of the v0.1.0 foundation. Backward
compatible: the v0.1.0 manual workflow continues to work.

```
qp add <name> --key Mod1+r        # interactive: $EDITOR opens, conflict-checks i3 binds, auto-reloads
qp list                            # show all phrases with their bindings
qp edit <name>                     # re-open a phrase in $EDITOR
qp remove <name>                   # delete phrase + remove its bindsym + reload
qp test <name>                     # type the phrase into focused window with 2-second notify-send countdown
qp doctor                          # already in v0.1.0; expanded with binding-coverage report
```

Key features:
- **Conflict detection at `add` time.** Parses `~/.config/i3/config` and
  every file it includes; refuses to clobber an existing bind. Suggests
  free combos.
- **`$EDITOR` integration.** No file format to remember; the user types
  the phrase into their editor.
- **Auto-reload.** Every `add`/`edit`/`remove` triggers `i3-msg reload`
  automatically.
- **`qp test` countdown.** A 2-second `notify-send` "typing 'review' in
  2... 1..." countdown lets the user verify focus before keystrokes
  actually fire.
- **Allowlist UX:** `qp doctor` reports the active allowlist; `qp
  --allowlist=kitty <name>` allows per-invocation override.

The conflict detector parses i3 config as untrusted text (no `eval`,
no `source`); the Pentester seat's hard requirements still apply.

## v0.3.0 (planned) — Wayland backend

The v0.1.0 injection backend is currently inlined into `bin/i3-quickphrase`.
v0.3.0 will factor it into `lib/inject.sh` (X11/xdotool) and add
`lib/inject-wayland.sh` using `ydotool` or `dotool`. Backend selection
at runtime via `$XDG_SESSION_TYPE` or `$WAYLAND_DISPLAY`.

This is the reason `lib/` exists in v0.1.0 even though it currently only
holds `validate.sh`: the directory layout pre-pays the migration cost
without spending it today.

## Design FAQs

### Why no auto-Enter / auto-submit?

Claude Code uses Ink's `ink-text-input`, which distinguishes physical
Enter from synthetic `\r`/`\n`
([anthropics/claude-code#15553](https://github.com/anthropics/claude-code/issues/15553)).
Synthetic Enter is treated as a literal newline character in the prompt
buffer; only physical Enter submits. Auto-submitting via xdotool is
therefore unreliable across Claude Code versions. The framework deliberately
types only the phrase content (with optional trailing space) and leaves
submission to the user.

### Why xdotool and not espanso?

Espanso uses typed-string triggers, not key combinations. The user types
e.g. `:rev` and espanso replaces it with the expanded text. This is a
different mental model from "press a key, type a phrase" and didn't match
the requested feature shape. Espanso also has the same kitty XTEST modifier
bug ([kovidgoyal/kitty#4487](https://github.com/kovidgoyal/kitty/issues/4487))
and requires a daemon, so its theoretical advantages don't materialize for
this use case.

### Why `bindsym --release` + explicit `keyup` + `flock`?

These solve **four different races**, not one:
1. **Mod-key release race** (i3 fires `exec` while user still holds Alt)
   → fixed by `--release`, which makes i3 wait for the trigger key's key-up
2. **Modifier-leak race** (xdotool sees Mod1 active while typing)
   → fixed by an explicit `xdotool keyup Alt_L Alt_R ... Super_L Super_R`
   before typing
3. **Key-repeat reentry** (held key fires the bind multiple times)
   → fixed by `flock -n`, which serializes invocations
4. **Focus-drift race** (user Alt+Tabs between bind-fire and type)
   → fixed by capturing the window ID at start and passing
   `--window <id>` to xdotool

### Why NOT `xdotool --clearmodifiers`?

The first version of v0.1.0 used `xdotool type --clearmodifiers`, which
seemed like the right answer (it's what the i3 FAQ recommends). But
real-world testing surfaced [xdotool#43](https://github.com/jordansissel/xdotool/issues/43)'s
"stuck modifiers after --clearmodifiers" bug:

1. User presses Alt+M
2. `bindsym --release` fires when M is released
3. xdotool starts. `--clearmodifiers` queries the modifier state, sees
   Alt held (because at fire time, Alt may still be held), sends a
   synthetic Alt-Release, types the phrase, and then **sends a synthetic
   Alt-Press at the end to "restore" the original state**
4. By that time the user has physically released Alt
5. X11 now has an unmatched synthetic Alt-Press → Alt appears stuck
   until the next physical Alt press/release
6. User tries to type the next character → it gets interpreted as
   Alt+character, often producing nothing or triggering a binding

The explicit `xdotool keyup` approach fires synthetic key-release events
without any matching "restore" step, so nothing can get left dangling.
v0.1.1 was the patch that fixed this.

### Why `xdotool --file` instead of an argv?

Three reasons:
1. **Trailing space preservation.** Shell command substitution
   `$(cat phrase.txt)` strips trailing newlines but not trailing spaces.
   Reading via `--file` reads the file's exact bytes.
2. **No `ps auxf` leak.** A phrase passed via argv shows up in process
   listings. `--file` keeps it out.
3. **No shell metacharacter risk.** A future contributor adding command
   substitution to the wrapper script can't accidentally introduce
   injection because the content path never touches a shell variable.

### Why default the window-class allowlist to `*`?

Trevor's locked spec said "Claude Code in kitty terminal", which would
suggest a `kitty`-only default. But locking too tight makes the tool feel
broken when you want to use it in a browser later. The compromise: ship
the detection code, default it disabled, document the override clearly.
If your threat model requires strict targeting, one `export` line in your
shell rc enables it.
