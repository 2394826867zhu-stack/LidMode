#!/bin/bash
set -euo pipefail

APP_PATH="/Applications/LidMode.app"
APP_BINARY="$APP_PATH/Contents/MacOS/LidMode"
HELPER_PATH="/usr/local/libexec/lidmode-helper"
SUDOERS_PATH="/etc/sudoers.d/lidmode"
APP_IDENTIFIER="io.github.2394826867zhu-stack.LidMode"
APP_PROCESS_PATTERN='^/Applications/LidMode\.app/Contents/MacOS/LidMode$'
REQUIRE_RUNNING=0

run_sudo() {
    if [[ -n "${SUDO_ASKPASS:-}" ]]; then
        /usr/bin/sudo -A "$@"
    else
        /usr/bin/sudo "$@"
    fi
}

if [[ "${1:-}" == "--require-running" ]]; then
    REQUIRE_RUNNING=1
elif [[ $# -ne 0 ]]; then
    echo "usage: $0 [--require-running]" >&2
    exit 2
fi

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[[ -d "$APP_PATH" ]] || fail "LidMode.app is not installed"
[[ -x "$APP_BINARY" ]] || fail "app executable is missing"
[[ -x "$HELPER_PATH" ]] || fail "helper is missing or not executable"
[[ -f "$SUDOERS_PATH" ]] || fail "sudoers rule is missing"

app_owner="$(/usr/bin/stat -f '%Su:%Sg' "$APP_PATH")"
app_mode="$(/usr/bin/stat -f '%Lp' "$APP_PATH")"
helper_owner="$(/usr/bin/stat -f '%Su:%Sg' "$HELPER_PATH")"
helper_mode="$(/usr/bin/stat -f '%Lp' "$HELPER_PATH")"
sudoers_owner="$(/usr/bin/stat -f '%Su:%Sg' "$SUDOERS_PATH")"
sudoers_mode="$(/usr/bin/stat -f '%Lp' "$SUDOERS_PATH")"
libexec_owner="$(/usr/bin/stat -f '%Su' /usr/local/libexec)"
libexec_mode="$(/usr/bin/stat -f '%Lp' /usr/local/libexec)"

[[ "$app_owner" == "root:wheel" ]] || fail "app owner is $app_owner, expected root:wheel"
[[ "$app_mode" == "755" ]] || fail "app mode is $app_mode, expected 755"
[[ "$helper_owner" == "root:wheel" ]] || fail "helper owner is $helper_owner, expected root:wheel"
[[ "$helper_mode" == "755" ]] || fail "helper mode is $helper_mode, expected 755"
[[ "$sudoers_owner" == "root:wheel" ]] || fail "sudoers owner is $sudoers_owner, expected root:wheel"
[[ "$sudoers_mode" == "440" ]] || fail "sudoers mode is $sudoers_mode, expected 440"
[[ "$libexec_owner" == "root" ]] || fail "/usr/local/libexec is not root-owned"
[[ $((8#$libexec_mode & 8#22)) -eq 0 ]] || fail "/usr/local/libexec is group/other writable"

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
agent_only="$(/usr/bin/plutil -extract LSUIElement raw "$APP_PATH/Contents/Info.plist")"
[[ "$bundle_identifier" == "$APP_IDENTIFIER" ]] || fail "unexpected bundle identifier: $bundle_identifier"
[[ "$agent_only" == "true" ]] || fail "LSUIElement is not enabled"

echo "Administrator approval is needed to validate the installed sudoers file."
run_sudo -v
run_sudo /usr/sbin/visudo -cf "$SUDOERS_PATH" >/dev/null

CURRENT_USER="$(/usr/bin/id -un)"
[[ "$CURRENT_USER" =~ ^[A-Za-z0-9._-]+$ ]] || fail "unsupported account name"
EXPECTED_SUDOERS="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lidmode-sudoers.XXXXXX")"
trap '/bin/rm -f "$EXPECTED_SUDOERS"' EXIT
/usr/bin/printf '%s ALL=(root) NOPASSWD: %s on, %s off, %s status\n' \
    "$CURRENT_USER" "$HELPER_PATH" "$HELPER_PATH" "$HELPER_PATH" > "$EXPECTED_SUDOERS"
run_sudo /usr/bin/cmp -s "$EXPECTED_SUDOERS" "$SUDOERS_PATH" || \
    fail "sudoers policy differs from the exact three-command allowlist"

if [[ -n "${EXPECTED_HELPER_SHA256:-}" ]]; then
    installed_helper_sha256="$(/usr/bin/shasum -a 256 "$HELPER_PATH" | /usr/bin/awk '{print $1}')"
    [[ "$installed_helper_sha256" == "$EXPECTED_HELPER_SHA256" ]] || \
        fail "installed helper differs from the helper built for this installation"
fi

if "$HELPER_PATH" 'on;whoami' >/dev/null 2>&1; then
    fail "helper accepted an invalid argument"
fi

state="$(/usr/bin/sudo -n "$HELPER_PATH" status)"
case "$state" in
    NORMAL|AWAKE) ;;
    *) fail "helper returned unexpected state: $state" ;;
esac

/usr/bin/codesign --verify --deep --strict "$APP_PATH"
if [[ "$REQUIRE_RUNNING" -eq 1 ]]; then
    /usr/bin/pgrep -f "$APP_PROCESS_PATTERN" >/dev/null || fail "installed app is not running"
fi

echo "PASS: app identity, agent mode, helper integrity, exact sudoers policy, signature, and state read are valid ($state)."
