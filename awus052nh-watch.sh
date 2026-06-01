#!/usr/bin/env bash
# AWUS052NH user-space watcher.
#
# Runs as a systemd --user unit under the logged-in user's session. Watches
# /run/awus052nh/state for changes via inotifywait in monitor mode, and
# launches the Rofi dialog when the state file transitions to "ready".
#
# The state file is written atomically by awus052nh-ready.sh via
# `mktemp + mv -f`, which destroys the old inode — that's why we watch the
# PARENT DIRECTORY and filter on filename, not the file directly. A
# file-level watch would get IN_IGNORED on every update.
#
# Uses session DBUS/DISPLAY inherited from systemctl --user (imported by GDM
# at login).

set -euo pipefail

# --- Configuration ---------------------------------------------------------
# Runs as a systemd --user unit, so /etc/awus052nh/config is the primary
# source; user-scoped override is also supported.
for _cfg in /etc/awus052nh/config "${XDG_CONFIG_HOME:-$HOME/.config}/awus052nh/config"; do
    # shellcheck disable=SC1090
    [[ -r "$_cfg" ]] && source "$_cfg"
done
unset _cfg

: "${STATE_DIR:=/run/awus052nh}"
: "${STATE_FILE:=${STATE_DIR}/state}"
: "${DIALOG:=/usr/local/bin/awus-rofi-dialog}"
: "${DEBOUNCE_SEC:=0.2}"

readonly STATE_DIR STATE_FILE DIALOG DEBOUNCE_SEC
# shellcheck disable=SC2034  # used by the inotify filter below
readonly STATE_FILE_BASENAME="${STATE_FILE##*/}"

log() {
    # systemd --user captures stdout to journald automatically.
    printf '[watch] %s\n' "$*"
}

is_ready() {
    [[ -f "$STATE_FILE" ]] && grep -q '"state":"ready"' "$STATE_FILE"
}

launch_dialog() {
    if [[ -x "$DIALOG" ]]; then
        log "launching dialog: $DIALOG"
        "$DIALOG" &
    else
        log "state=ready but $DIALOG not executable; skipping"
    fi
}

wait_for_state_dir() {
    while [[ ! -d "$STATE_DIR" ]]; do
        log "waiting for $STATE_DIR to appear"
        sleep 2
    done
}

main() {
    log "starting"
    wait_for_state_dir

    # Track mtime so we only react to actual changes, not to our own readbacks.
    # If the file already exists, record its mtime and suppress the next
    # "is it ready?" check so we don't fire a stale dialog on daemon restart.
    local last_mtime=''
    if [[ -f "$STATE_FILE" ]]; then
        last_mtime=$(stat -c %Y "$STATE_FILE")
        log "initial state file mtime=$last_mtime; suppressing stale-state dialog"
    fi

    # Monitor the directory continuously. `-m` = monitor mode (never exits),
    # `-q` = quiet. We care about MOVED_TO (atomic replace lands here),
    # plus CREATE, CLOSE_WRITE, and MODIFY for defense against other write
    # strategies.
    log "entering inotifywait monitor loop on $STATE_DIR"
    inotifywait -mq \
        --format '%e %f' \
        -e create,moved_to,close_write,modify \
        "$STATE_DIR" \
    | while IFS=' ' read -r event filename; do
        log "event: $event on '$filename'"

        # Only react to events on our state file
        if [[ "$filename" != "$STATE_FILE_BASENAME" ]]; then
            continue
        fi

        sleep "$DEBOUNCE_SEC"

        if [[ ! -f "$STATE_FILE" ]]; then
            log "state file missing after event; skipping"
            continue
        fi

        local current_mtime
        current_mtime=$(stat -c %Y "$STATE_FILE")
        if [[ "$current_mtime" == "$last_mtime" ]]; then
            log "duplicate mtime=$current_mtime; skipping"
            continue
        fi
        last_mtime="$current_mtime"

        if is_ready; then
            launch_dialog
        else
            log "state changed but not ready; ignoring (event=$event)"
        fi
    done

    # inotifywait -m should never exit; if it does, systemd will restart us.
    log "inotifywait -m terminated unexpectedly"
    exit 2
}

main "$@"
