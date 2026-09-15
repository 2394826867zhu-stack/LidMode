#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_PATH="${1:-$PROJECT_ROOT/.build/lidmode-helper}"
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
MODULE_CACHE_PATH="$(/usr/bin/dirname "$OUTPUT_PATH")/ModuleCache"

/bin/mkdir -p "$(/usr/bin/dirname "$OUTPUT_PATH")" "$MODULE_CACHE_PATH"
/usr/bin/xcrun --sdk macosx swiftc \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE_PATH" \
    -target arm64-apple-macos13.0 \
    -O \
    -whole-module-optimization \
    -parse-as-library \
    "$PROJECT_ROOT/LidMode/PowerState.swift" \
    "$SCRIPT_DIR/lidmode-helper.swift" \
    -o "$OUTPUT_PATH"

/bin/chmod 755 "$OUTPUT_PATH"
/usr/bin/file "$OUTPUT_PATH"
