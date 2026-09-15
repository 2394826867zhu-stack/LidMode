#!/bin/bash
set -euo pipefail

HELPER="/usr/local/libexec/lidmode-helper"

if [[ "${LIDMODE_RUN_PRIVILEGED_TESTS:-0}" != "1" ]]; then
    echo "SKIP: set LIDMODE_RUN_PRIVILEGED_TESTS=1 to run the privileged state-changing test."
    exit 0
fi

if [[ ! -x "$HELPER" ]]; then
    echo "FAIL: helper is not installed at $HELPER" >&2
    exit 1
fi

original="$(/usr/bin/sudo -n "$HELPER" status)"
case "$original" in
    NORMAL|AWAKE) ;;
    *)
        echo "FAIL: could not capture the original state" >&2
        exit 1
        ;;
esac

restore() {
    local restore_action
    if [[ "$original" == "AWAKE" ]]; then
        restore_action="on"
    else
        restore_action="off"
    fi

    if ! /usr/bin/sudo -n "$HELPER" "$restore_action" >/dev/null; then
        echo "FAIL: could not restore original state $original" >&2
        return 1
    fi
    if [[ "$(/usr/bin/sudo -n "$HELPER" status)" != "$original" ]]; then
        echo "FAIL: original state $original was not restored" >&2
        return 1
    fi
}
trap 'restore || exit 1' EXIT

/usr/bin/sudo -n "$HELPER" on >/dev/null
[[ "$(/usr/bin/sudo -n "$HELPER" status)" == "AWAKE" ]]
/usr/bin/sudo -n "$HELPER" off >/dev/null
[[ "$(/usr/bin/sudo -n "$HELPER" status)" == "NORMAL" ]]

echo "PASS: status -> on -> status -> off -> status; original state will be restored."
