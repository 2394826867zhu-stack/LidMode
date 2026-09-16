#!/bin/bash
set -euo pipefail

APP_PATH="/Applications/LidMode.app"
APP_BINARY="$APP_PATH/Contents/MacOS/LidMode"
HELPER_PATH="/usr/local/libexec/lidmode-helper"
SUDOERS_PATH="/etc/sudoers.d/lidmode"
APP_PROCESS_PATTERN='^/Applications/LidMode\.app/Contents/MacOS/LidMode$'
ROOT_STAGING_DIR=""
UNINSTALL_COMMITTED=0
MOVED_APP=0
MOVED_HELPER=0
MOVED_SUDOERS=0
APP_WAS_RUNNING=0

run_sudo() {
    if [[ -n "${SUDO_ASKPASS:-}" ]]; then
        /usr/bin/sudo -A "$@"
    else
        /usr/bin/sudo "$@"
    fi
}

cleanup() {
    if [[ "$UNINSTALL_COMMITTED" -ne 1 && -n "$ROOT_STAGING_DIR" ]]; then
        echo "Uninstall failed; restoring files that were already moved." >&2
        if [[ "$MOVED_APP" -eq 1 && -d "$ROOT_STAGING_DIR/LidMode.app" ]]; then
            /usr/bin/sudo -n /bin/mv "$ROOT_STAGING_DIR/LidMode.app" "$APP_PATH" 2>/dev/null || true
        fi
        if [[ "$MOVED_HELPER" -eq 1 && -f "$ROOT_STAGING_DIR/lidmode-helper" ]]; then
            /usr/bin/sudo -n /bin/mv "$ROOT_STAGING_DIR/lidmode-helper" "$HELPER_PATH" 2>/dev/null || true
        fi
        if [[ "$MOVED_SUDOERS" -eq 1 && -f "$ROOT_STAGING_DIR/lidmode.sudoers" ]]; then
            /usr/bin/sudo -n /bin/mv "$ROOT_STAGING_DIR/lidmode.sudoers" "$SUDOERS_PATH" 2>/dev/null || true
        fi
        if [[ "$APP_WAS_RUNNING" -eq 1 && -d "$APP_PATH" ]]; then
            /usr/bin/open "$APP_PATH" 2>/dev/null || true
        fi
    fi

    if [[ -n "$ROOT_STAGING_DIR" ]]; then
        /usr/bin/sudo -n /bin/rm -rf "$ROOT_STAGING_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "Administrator approval is needed to restore normal sleep and remove LidMode."
run_sudo -v

if /usr/bin/pgrep -f "$APP_PROCESS_PATTERN" >/dev/null; then
    APP_WAS_RUNNING=1
fi

echo "Restoring and verifying normal sleep before uninstall..."
run_sudo /usr/bin/pmset -a disablesleep 0
PMSET_OUTPUT="$(/usr/bin/pmset -g)"
if ! /usr/bin/grep -Eq '^[[:space:]]*SleepDisabled[[:space:]]+0[[:space:]]*$' <<< "$PMSET_OUTPUT" && {
    ! /usr/bin/grep -q '^System-wide power settings:' <<< "$PMSET_OUTPUT" ||
    ! /usr/bin/grep -q '^Currently in use:' <<< "$PMSET_OUTPUT" ||
    ! /usr/bin/grep -Eq '^[[:space:]]*(sleep|displaysleep|ttyskeepawake)[[:space:]]+[0-9]+' <<< "$PMSET_OUTPUT"
}; then
    echo "Uninstall stopped: normal sleep could not be verified." >&2
    exit 1
fi

if [[ -x "$APP_BINARY" ]]; then
    "$APP_BINARY" --unregister-login-item
fi

if [[ "$APP_WAS_RUNNING" -eq 1 ]]; then
    /usr/bin/pkill -TERM -f "$APP_PROCESS_PATTERN"
    for _ in {1..20}; do
        if ! /usr/bin/pgrep -f "$APP_PROCESS_PATTERN" >/dev/null; then
            break
        fi
        /bin/sleep 0.1
    done
    if /usr/bin/pgrep -f "$APP_PROCESS_PATTERN" >/dev/null; then
        echo "Unable to stop the installed LidMode process safely." >&2
        exit 1
    fi
fi

ROOT_STAGING_DIR="$(run_sudo /usr/bin/mktemp -d /private/tmp/lidmode-uninstall.XXXXXX)"

if [[ -d "$APP_PATH" ]]; then
    run_sudo /bin/mv "$APP_PATH" "$ROOT_STAGING_DIR/LidMode.app"
    MOVED_APP=1
fi
if [[ -e "$HELPER_PATH" ]]; then
    run_sudo /bin/mv "$HELPER_PATH" "$ROOT_STAGING_DIR/lidmode-helper"
    MOVED_HELPER=1
fi
if [[ -e "$SUDOERS_PATH" ]]; then
    run_sudo /bin/mv "$SUDOERS_PATH" "$ROOT_STAGING_DIR/lidmode.sudoers"
    MOVED_SUDOERS=1
fi

if [[ -e "$HELPER_PATH" || -e "$SUDOERS_PATH" || -e "$APP_PATH" ]]; then
    echo "Uninstall failed: one or more LidMode files remain." >&2
    exit 1
fi

UNINSTALL_COMMITTED=1
run_sudo /bin/rm -rf "$ROOT_STAGING_DIR"
ROOT_STAGING_DIR=""
echo "LidMode was completely removed. Normal sleep was restored and verified first."
