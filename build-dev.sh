#!/bin/bash
# Dev-сборка Golosok: валидный бандл с реальными ресурсами, ad-hoc подпись.
#
# Использование:
#   ./build-dev.sh                     # universal (arm64 + x86_64)
#   ./build-dev.sh --arch arm64        # только arm64 (быстрее)
#   GOLOSOK_BUILD_ROOT=/tmp/build ./build-dev.sh
#
# Каталог сборки по умолчанию — ../Golosok-Build рядом с репозиторием, без привязки к /Users/...

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/build_common.sh
source "$ROOT/scripts/build_common.sh"

ARCHS="universal"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCHS="${2:?--arch требует значение: arm64 | x86_64 | universal}"
            shift 2
            ;;
        --arch=*)
            ARCHS="${1#*=}"
            shift
            ;;
        *)
            echo "❌ Неизвестный аргумент: $1" >&2
            exit 1
            ;;
    esac
done

VERSION="$(read_version)"
BUILD_NUMBER="$(read_build_number)"
BUILD_ROOT="${GOLOSOK_BUILD_ROOT:-$(dirname "$ROOT")/Golosok-Build}"
APP_TARGET="$BUILD_ROOT/Golosok-Dev.app"

print_banner "dev v${VERSION}-dev ($ARCHS)"

verify_invariants

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
compile_binary "$ARCHS" "$WORK_DIR/Golosok"

stage_bundle "$APP_TARGET" "$WORK_DIR/Golosok" "${VERSION}-dev" "$BUILD_NUMBER"
sign_bundle "$APP_TARGET" "-"

echo "==> Готово: $APP_TARGET (v${VERSION}-dev, build ${BUILD_NUMBER}, ${ARCHS})"
echo "    Запуск: open \"$APP_TARGET\""
