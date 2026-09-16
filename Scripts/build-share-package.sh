#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODEBUILD="$DEVELOPER_DIR_PATH/usr/bin/xcodebuild"
OUTPUT_DIR="${1:-/tmp}"
WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lidmode-share.XXXXXX")"

cleanup() {
    /bin/rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ "$(/usr/bin/uname -m)" != "arm64" ]]; then
    echo "The M2 share package must be built on Apple Silicon." >&2
    exit 1
fi
if [[ ! -x "$XCODEBUILD" ]]; then
    echo "Xcode is required at $DEVELOPER_DIR_PATH." >&2
    exit 1
fi

/bin/mkdir -p "$OUTPUT_DIR"

echo "Building the arm64 Release app..."
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "$XCODEBUILD" \
    -project "$PROJECT_ROOT/LidMode.xcodeproj" \
    -scheme LidMode \
    -destination "platform=macOS,arch=arm64" \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    build

BUILT_APP="$WORK_DIR/DerivedData/Build/Products/Release/LidMode.app"
[[ -d "$BUILT_APP" ]] || { echo "Release build did not produce LidMode.app." >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist")"
PACKAGE_NAME="LidMode-${VERSION}-M2"
PACKAGE_DIR="$WORK_DIR/$PACKAGE_NAME"
PAYLOAD_DIR="$PACKAGE_DIR/Payload"
SUPPORT_DIR="$PACKAGE_DIR/Support"
ARCHIVE="$OUTPUT_DIR/$PACKAGE_NAME.zip"

/bin/mkdir -p "$PAYLOAD_DIR" "$SUPPORT_DIR"
/usr/bin/ditto "$BUILT_APP" "$PAYLOAD_DIR/LidMode.app"
/usr/bin/codesign --force --deep --sign - "$PAYLOAD_DIR/LidMode.app"
/usr/bin/codesign --verify --deep --strict "$PAYLOAD_DIR/LidMode.app"

echo "Building the restricted arm64 helper..."
HELPER_BUILD_DIR="$WORK_DIR/HelperBuild"
/bin/mkdir -p "$HELPER_BUILD_DIR"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
    "$PROJECT_ROOT/Helper/build-helper.sh" "$HELPER_BUILD_DIR/lidmode-helper"
/bin/cp "$HELPER_BUILD_DIR/lidmode-helper" "$PAYLOAD_DIR/lidmode-helper"
/bin/chmod 755 "$PAYLOAD_DIR/lidmode-helper"

/bin/cp "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/uninstall.sh" "$SCRIPT_DIR/verify-install.sh" "$SUPPORT_DIR/"
/bin/chmod 755 "$SUPPORT_DIR/install.sh" "$SUPPORT_DIR/uninstall.sh" "$SUPPORT_DIR/verify-install.sh"

/usr/bin/printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' \
    'export LIDMODE_PREBUILT_APP="$PACKAGE_DIR/Payload/LidMode.app"' \
    'export LIDMODE_PREBUILT_HELPER="$PACKAGE_DIR/Payload/lidmode-helper"' \
    '"$PACKAGE_DIR/Support/install.sh"' \
    'echo' \
    'echo "安装完成，可以关闭此窗口。"' \
    'read -r -p "按回车键关闭…" _ || true' \
    > "$PACKAGE_DIR/安装 LidMode.command"

/usr/bin/printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' \
    '"$PACKAGE_DIR/Support/uninstall.sh"' \
    'echo' \
    'echo "卸载完成，可以关闭此窗口。"' \
    'read -r -p "按回车键关闭…" _ || true' \
    > "$PACKAGE_DIR/卸载 LidMode.command"

/bin/chmod 755 "$PACKAGE_DIR/安装 LidMode.command" "$PACKAGE_DIR/卸载 LidMode.command"

/usr/bin/printf '%s\n' \
    "LidMode $VERSION — MacBook Pro M2 分享版" \
    "" \
    "安装：" \
    "1. 右键点击『安装 LidMode.command』，选择『打开』。" \
    "2. 如有系统确认，请允许打开；在终端提示 Password 时输入 Mac 登录密码。" \
    "3. 等待出现『LidMode installed successfully』。菜单栏会显示 LidMode。" \
    "" \
    "使用：左键切换 Normal/Awake；右键打开设置和退出菜单。" \
    "卸载：右键打开『卸载 LidMode.command』，输入一次登录密码。" \
    "" \
    "此分享版没有 Apple Developer ID，因此第一次必须通过右键『打开』确认信任。" \
    > "$PACKAGE_DIR/使用说明.txt"

/bin/rm -f "$ARCHIVE" "$ARCHIVE.sha256"
/usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PACKAGE_DIR" "$ARCHIVE"
(
    cd "$OUTPUT_DIR"
    /usr/bin/shasum -a 256 "$PACKAGE_NAME.zip" > "$PACKAGE_NAME.zip.sha256"
)

echo "Share package created: $ARCHIVE"
echo "Checksum created: $ARCHIVE.sha256"
