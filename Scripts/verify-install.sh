#!/bin/bash
set -euo pipefail

APP_PATH="/Applications/LidMode.app"
HELPER_PATH="/usr/local/libexec/lidmode-helper"
SUDOERS_PATH="/etc/sudoers.d/lidmode"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[[ -d "$APP_PATH" ]] || fail "LidMode.app is not installed"
[[ -x "$HELPER_PATH" ]] || fail "helper is missing or not executable"
[[ -f "$SUDOERS_PATH" ]] || fail "sudoers rule is missing"

helper_owner="$(/usr/bin/stat -f '%Su:%Sg' "$HELPER_PATH")"
helper_mode="$(/usr/bin/stat -f '%Lp' "$HELPER_PATH")"
sudoers_owner="$(/usr/bin/stat -f '%Su:%Sg' "$SUDOERS_PATH")"
sudoers_mode="$(/usr/bin/stat -f '%Lp' "$SUDOERS_PATH")"
libexec_owner="$(/usr/bin/stat -f '%Su' /usr/local/libexec)"
libexec_mode="$(/usr/bin/stat -f '%Lp' /usr/local/libexec)"

[[ "$helper_owner" == "root:wheel" ]] || fail "helper owner is $helper_owner, expected root:wheel"
[[ "$helper_mode" == "755" ]] || fail "helper mode is $helper_mode, expected 755"
[[ "$sudoers_owner" == "root:wheel" ]] || fail "sudoers owner is $sudoers_owner, expected root:wheel"
[[ "$sudoers_mode" == "440" ]] || fail "sudoers mode is $sudoers_mode, expected 440"
[[ "$libexec_owner" == "root" ]] || fail "/usr/local/libexec is not root-owned"
[[ $((8#$libexec_mode & 8#22)) -eq 0 ]] || fail "/usr/local/libexec is group/other writable"

state="$(/usr/bin/sudo -n "$HELPER_PATH" status)"
case "$state" in
    NORMAL|AWAKE) ;;
    *) fail "helper returned unexpected state: $state" ;;
esac

/usr/bin/codesign --verify --deep --strict "$APP_PATH"
echo "PASS: app, helper, sudoers permissions, signature, and passwordless state read are valid ($state)."
