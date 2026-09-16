#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_TARGET="/Applications/LidMode.app"
HELPER_TARGET="/usr/local/libexec/lidmode-helper"
SUDOERS_TARGET="/etc/sudoers.d/lidmode"
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODEBUILD="$DEVELOPER_DIR_PATH/usr/bin/xcodebuild"
STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lidmode-install.XXXXXX")"
BACKUP_DIR="$STAGING_DIR/backup"
BUILD_DIR="$STAGING_DIR/build"
SUDOERS_FILE="$STAGING_DIR/lidmode.sudoers"
ROOT_STAGING_DIR=""
INSTALL_SUCCEEDED=0
ADMIN_READY=0
HAD_APP=0
HAD_HELPER=0
HAD_SUDOERS=0
CREATED_LIBEXEC=0
CREATED_USR_LOCAL=0
MUTATION_STARTED=0
APP_WAS_RUNNING=0

run_sudo() {
    if [[ -n "${SUDO_ASKPASS:-}" ]]; then
        /usr/bin/sudo -A "$@"
    else
        /usr/bin/sudo "$@"
    fi
}

cleanup() {
    set +e
    if [[ "$INSTALL_SUCCEEDED" -ne 1 && "$ADMIN_READY" -eq 1 && "$MUTATION_STARTED" -eq 1 ]]; then
        echo "Install failed; restoring the previous installation." >&2

        if /usr/bin/pgrep -f '^/Applications/LidMode\.app/Contents/MacOS/LidMode$' >/dev/null; then
            /usr/bin/pkill -TERM -f '^/Applications/LidMode\.app/Contents/MacOS/LidMode$'
        fi

        if [[ "$HAD_APP" -eq 1 ]]; then
            run_sudo /bin/rm -rf "$APP_TARGET"
            run_sudo /usr/bin/ditto "$BACKUP_DIR/LidMode.app" "$APP_TARGET"
        else
            run_sudo /bin/rm -rf "$APP_TARGET"
        fi

        if [[ "$HAD_HELPER" -eq 1 ]]; then
            run_sudo /usr/bin/install -o root -g wheel -m 755 "$BACKUP_DIR/lidmode-helper" "$HELPER_TARGET"
        else
            run_sudo /bin/rm -f "$HELPER_TARGET"
        fi

        if [[ "$HAD_SUDOERS" -eq 1 ]]; then
            run_sudo /usr/bin/install -o root -g wheel -m 440 "$BACKUP_DIR/lidmode.sudoers" "$SUDOERS_TARGET"
        else
            run_sudo /bin/rm -f "$SUDOERS_TARGET"
        fi

        if [[ "$APP_WAS_RUNNING" -eq 1 && -d "$APP_TARGET" ]]; then
            /usr/bin/open "$APP_TARGET" 2>/dev/null || true
        fi

    fi

    if [[ "$INSTALL_SUCCEEDED" -ne 1 && "$ADMIN_READY" -eq 1 && "$CREATED_LIBEXEC" -eq 1 ]]; then
        run_sudo /bin/rmdir /usr/local/libexec 2>/dev/null || true
    fi

    if [[ "$INSTALL_SUCCEEDED" -ne 1 && "$ADMIN_READY" -eq 1 && "$CREATED_USR_LOCAL" -eq 1 ]]; then
        run_sudo /bin/rmdir /usr/local 2>/dev/null || true
    fi

    if [[ "$ADMIN_READY" -eq 1 && -n "$ROOT_STAGING_DIR" ]]; then
        /usr/bin/sudo -n /bin/rm -rf "$ROOT_STAGING_DIR" 2>/dev/null || true
    fi

    if [[ "$ADMIN_READY" -eq 1 ]]; then
        /usr/bin/sudo -n /bin/rm -rf "$STAGING_DIR" 2>/dev/null || true
    else
        /bin/rm -rf "$STAGING_DIR"
    fi
}
trap cleanup EXIT

if [[ "$(/usr/bin/uname -m)" != "arm64" ]]; then
    echo "LidMode V1 requires an Apple Silicon Mac." >&2
    exit 1
fi

if [[ ! -x "$XCODEBUILD" ]]; then
    echo "Xcode is required at $DEVELOPER_DIR_PATH." >&2
    exit 1
fi

CURRENT_USER="$(/usr/bin/id -un)"
if [[ ! "$CURRENT_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Unsupported account name for sudoers: $CURRENT_USER" >&2
    exit 1
fi

/bin/mkdir -p "$BACKUP_DIR" "$BUILD_DIR"

echo "Building LidMode.app..."
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "$XCODEBUILD" \
    -project "$PROJECT_ROOT/LidMode.xcodeproj" \
    -scheme LidMode \
    -destination "platform=macOS,arch=arm64" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    build

BUILT_APP="$BUILD_DIR/DerivedData/Build/Products/Release/LidMode.app"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "Build did not produce LidMode.app." >&2
    exit 1
fi

echo "Building restricted helper..."
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "$PROJECT_ROOT/Helper/build-helper.sh" "$BUILD_DIR/lidmode-helper"

/usr/bin/printf '%s ALL=(root) NOPASSWD: %s on, %s off, %s status\n' \
    "$CURRENT_USER" "$HELPER_TARGET" "$HELPER_TARGET" "$HELPER_TARGET" > "$SUDOERS_FILE"
/bin/chmod 440 "$SUDOERS_FILE"
/usr/sbin/visudo -cf "$SUDOERS_FILE"
HELPER_SHA256="$(/usr/bin/shasum -a 256 "$BUILD_DIR/lidmode-helper" | /usr/bin/awk '{print $1}')"
SUDOERS_SHA256="$(/usr/bin/shasum -a 256 "$SUDOERS_FILE" | /usr/bin/awk '{print $1}')"

echo "Administrator approval is needed once to install the app, helper, and restricted sudoers rule."
run_sudo -v
ADMIN_READY=1

secure_directory() {
    local directory="$1"
    local owner mode
    owner="$(/usr/bin/stat -f '%Su' "$directory")"
    mode="$(/usr/bin/stat -f '%Lp' "$directory")"
    if [[ "$owner" != "root" || $((8#$mode & 8#22)) -ne 0 ]]; then
        echo "Refusing to install into insecure directory: $directory ($owner, mode $mode)" >&2
        exit 1
    fi
}

if [[ ! -d /usr/local ]]; then
    run_sudo /usr/bin/install -d -o root -g wheel -m 755 /usr/local
    CREATED_USR_LOCAL=1
fi
secure_directory /usr/local
if [[ ! -d /usr/local/libexec ]]; then
    run_sudo /usr/bin/install -d -o root -g wheel -m 755 /usr/local/libexec
    CREATED_LIBEXEC=1
fi
secure_directory /usr/local/libexec

if [[ -d "$APP_TARGET" ]]; then
    HAD_APP=1
    run_sudo /usr/bin/ditto "$APP_TARGET" "$BACKUP_DIR/LidMode.app"
fi
if [[ -e "$HELPER_TARGET" ]]; then
    HAD_HELPER=1
    run_sudo /bin/cp -p "$HELPER_TARGET" "$BACKUP_DIR/lidmode-helper"
fi
if [[ -e "$SUDOERS_TARGET" ]]; then
    HAD_SUDOERS=1
    run_sudo /bin/cp -p "$SUDOERS_TARGET" "$BACKUP_DIR/lidmode.sudoers"
fi

ROOT_STAGING_DIR="$(run_sudo /usr/bin/mktemp -d /private/tmp/lidmode-root.XXXXXX)"
run_sudo /usr/bin/install -o root -g wheel -m 755 "$BUILD_DIR/lidmode-helper" "$ROOT_STAGING_DIR/lidmode-helper"
run_sudo /usr/bin/install -o root -g wheel -m 440 "$SUDOERS_FILE" "$ROOT_STAGING_DIR/lidmode.sudoers"

ROOT_HELPER_SHA256="$(run_sudo /usr/bin/shasum -a 256 "$ROOT_STAGING_DIR/lidmode-helper" | /usr/bin/awk '{print $1}')"
ROOT_SUDOERS_SHA256="$(run_sudo /usr/bin/shasum -a 256 "$ROOT_STAGING_DIR/lidmode.sudoers" | /usr/bin/awk '{print $1}')"
if [[ "$ROOT_HELPER_SHA256" != "$HELPER_SHA256" || "$ROOT_SUDOERS_SHA256" != "$SUDOERS_SHA256" ]]; then
    echo "Staged privileged files failed integrity verification." >&2
    exit 1
fi
run_sudo /usr/sbin/visudo -cf "$ROOT_STAGING_DIR/lidmode.sudoers"

MUTATION_STARTED=1

if /usr/bin/pgrep -f '^/Applications/LidMode\.app/Contents/MacOS/LidMode$' >/dev/null; then
    APP_WAS_RUNNING=1
    /usr/bin/pkill -TERM -f '^/Applications/LidMode\.app/Contents/MacOS/LidMode$'
    for _ in {1..20}; do
        if ! /usr/bin/pgrep -f '^/Applications/LidMode\.app/Contents/MacOS/LidMode$' >/dev/null; then
            break
        fi
        /bin/sleep 0.1
    done
    if /usr/bin/pgrep -f '^/Applications/LidMode\.app/Contents/MacOS/LidMode$' >/dev/null; then
        echo "Unable to stop the running LidMode app safely." >&2
        exit 1
    fi
fi

run_sudo /bin/mkdir -p /etc/sudoers.d
run_sudo /usr/bin/install -o root -g wheel -m 755 "$ROOT_STAGING_DIR/lidmode-helper" "$HELPER_TARGET"
run_sudo /usr/bin/install -o root -g wheel -m 440 "$ROOT_STAGING_DIR/lidmode.sudoers" "$SUDOERS_TARGET"
run_sudo /usr/sbin/visudo -cf "$SUDOERS_TARGET"

run_sudo /bin/rm -rf "$APP_TARGET"
run_sudo /usr/bin/ditto "$BUILT_APP" "$APP_TARGET"
run_sudo /usr/sbin/chown -R root:wheel "$APP_TARGET"
run_sudo /usr/bin/codesign --force --deep --sign - "$APP_TARGET"

EXPECTED_HELPER_SHA256="$HELPER_SHA256" "$SCRIPT_DIR/verify-install.sh"

echo "Launching LidMode and confirming that the installed process remains active..."
/usr/bin/open "$APP_TARGET"
for _ in {1..30}; do
    if /usr/bin/pgrep -f '^/Applications/LidMode\.app/Contents/MacOS/LidMode$' >/dev/null; then
        break
    fi
    /bin/sleep 0.1
done
EXPECTED_HELPER_SHA256="$HELPER_SHA256" "$SCRIPT_DIR/verify-install.sh" --require-running

INSTALL_SUCCEEDED=1
echo "LidMode installed successfully and is running in the menu bar."
