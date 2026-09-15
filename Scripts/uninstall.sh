#!/bin/bash
set -euo pipefail

APP_PATH="/Applications/LidMode.app"
APP_BINARY="$APP_PATH/Contents/MacOS/LidMode"
HELPER_PATH="/usr/local/libexec/lidmode-helper"
SUDOERS_PATH="/etc/sudoers.d/lidmode"

if [[ -x "$APP_BINARY" ]]; then
    "$APP_BINARY" --unregister-login-item >/dev/null 2>&1 || \
        echo "Warning: Login Item could not be unregistered automatically." >&2
fi

/usr/bin/pkill -x LidMode 2>/dev/null || true

echo "Administrator approval is needed to remove LidMode."
/usr/bin/sudo -v
/usr/bin/sudo /bin/rm -f "$HELPER_PATH" "$SUDOERS_PATH"
/usr/bin/sudo /bin/rm -rf "$APP_PATH"

if [[ -e "$HELPER_PATH" || -e "$SUDOERS_PATH" || -e "$APP_PATH" ]]; then
    echo "Uninstall failed: one or more LidMode files remain." >&2
    exit 1
fi

echo "LidMode was completely removed, including its registered privileged helper."
