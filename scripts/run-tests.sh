#!/bin/bash
# Локальный прогон тестов без Xcode.
#
# 1. Если доступен полный Xcode — запускает настоящий test-таргет (Swift Testing).
# 2. Иначе собирает приложение как модуль с -enable-testing и гоняет smoke-набор
#    из Tests/SmokeTests.swift (чистые функции: форматтер, тайминги, субтитры, поиск).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/build_common.sh
source "$ROOT/scripts/build_common.sh"

MODE="${GOLOSOK_TEST_MODE:-auto}"

if [[ "$MODE" == "auto" ]] && xcodebuild -version >/dev/null 2>&1; then
    MODE="xcode"
fi
if [[ "$MODE" == "xcode" ]]; then
    echo "==> Полный Xcode найден: запускаю test-таргет"
    xcodebuild test \
        -project "$ROOT/Golosok.xcodeproj" \
        -scheme Golosok \
        -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO
    exit $?
fi

echo "==> Полного Xcode нет: smoke-набор через swiftc"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

SDK="$(xcrun --show-sdk-path)"
TARGET="$(uname -m)-apple-macos${GOLOSOK_MIN_OS}"
MODULE_DIR="$WORK_DIR/module"
mkdir -p "$MODULE_DIR"

echo "==> Сборка модуля Golosok ($TARGET)..."
swiftc -parse-as-library \
    -emit-module -emit-library \
    -module-name Golosok \
    -enable-testing \
    -target "$TARGET" -sdk "$SDK" \
    "$ROOT"/Golosok/*.swift \
    -emit-module-path "$MODULE_DIR/Golosok.swiftmodule" \
    -o "$MODULE_DIR/libGolosok.dylib"

echo "==> Сборка и запуск smoke-тестов..."
swiftc \
    -target "$TARGET" -sdk "$SDK" \
    -I "$MODULE_DIR" -L "$MODULE_DIR" -lGolosok \
    -Xlinker -rpath -Xlinker "$MODULE_DIR" \
    "$ROOT/Tests/SmokeTests.swift" \
    -o "$WORK_DIR/smoke"

DYLD_LIBRARY_PATH="$MODULE_DIR" "$WORK_DIR/smoke"
