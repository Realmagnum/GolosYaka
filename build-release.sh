#!/bin/bash
# Релизная сборка Golosok: universal .app с реальными ресурсами, подпись,
# DMG и (опционально) нотаризация + staple.
#
# Использование:
#   ./build-release.sh                                   # ad-hoc подпись, DMG без нотаризации
#   ./build-release.sh --identity "Developer ID Application: Name (TEAMID)"
#   ./build-release.sh --identity "Developer ID Application: Name (TEAMID)" --notary-profile golosok
#   ./build-release.sh --version 1.14.0 --output ./dist
#
# Переменные окружения:
#   GOLOSOK_RESOURCES_DIR  — каталог с ffmpeg/whisper-cli/transcribe-cli/gigaam.gguf
#   GOLOSOK_BUILD_ROOT     — куда складывать рабочую сборку (по умолчанию ../Golosok-Build)
#
# Нотаризация требует сохранённого профиля notarytool:
#   xcrun notarytool store-credentials golosok --apple-id ... --team-id ... --password ...

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/build_common.sh
source "$ROOT/scripts/build_common.sh"

ARCHS="universal"
IDENTITY=""
NOTARY_PROFILE=""
OUTPUT_DIR="$ROOT/dist"
VERSION="$(read_version)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) ARCHS="${2:?}"; shift 2 ;;
        --identity) IDENTITY="${2:?}"; shift 2 ;;
        --notary-profile) NOTARY_PROFILE="${2:?}"; shift 2 ;;
        --output) OUTPUT_DIR="${2:?}"; shift 2 ;;
        --version) VERSION="${2:?}"; shift 2 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *) echo "❌ Неизвестный аргумент: $1" >&2; exit 1 ;;
    esac
done

BUILD_NUMBER="$(read_build_number)"
BUILD_ROOT="${GOLOSOK_BUILD_ROOT:-$(dirname "$ROOT")/Golosok-Build}"
APP_PATH="$BUILD_ROOT/Golosok.app"
DMG_PATH="$OUTPUT_DIR/Golosok-$VERSION.dmg"

print_banner "release v${VERSION} (build ${BUILD_NUMBER}, ${ARCHS})"

if [[ -z "$IDENTITY" ]]; then
    if IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -n 1)"; then
        IDENTITY="${IDENTITIES//\"/}"
    fi
fi

if [[ -z "$IDENTITY" ]]; then
    echo "⚠️  Developer ID не найден — подпись ad-hoc."
    echo "    Пользователям понадобится: xattr -cr /Applications/Golosok.app"
    IDENTITY="-"
fi

if [[ "$IDENTITY" == "-" ]]; then
    HARDENED="plain"
else
    HARDENED="hardened"
fi

verify_invariants

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
compile_binary "$ARCHS" "$WORK_DIR/Golosok"
stage_bundle "$APP_PATH" "$WORK_DIR/Golosok" "$VERSION" "$BUILD_NUMBER"

# Вложенные исполняемые файлы (ffmpeg, whisper-cli, transcribe-cli) должны быть подписаны
# до подписи бандла, иначе notarization вернёт "The signature of the binary is invalid".
while IFS= read -r -d '' tool; do
    if file -b "$tool" | grep -q "Mach-O"; then
        echo "==> Подпись вложенного бинарника: $(basename "$tool")"
        codesign --force --timestamp --options runtime --sign "$IDENTITY" "$tool"
    fi
done < <(find "$APP_PATH/Contents/Resources" -type f -perm -111 -print0)

sign_bundle "$APP_PATH" "$IDENTITY" "$HARDENED"

# --- DMG -------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR"
STAGE_DIR="$WORK_DIR/dmg"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/Golosok.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Создание DMG: $DMG_PATH"
rm -f "$DMG_PATH"
if ! hdiutil create -volname "Golosok $VERSION" -srcfolder "$STAGE_DIR" -ov -format UDZO -quiet "$DMG_PATH"; then
    # На машинах, где Disk Arbitration недоступен (CI-песочницы), UDIF-образы не создаются.
    # makehybrid не требует устройства и даёт валидный HFS-образ; размер чуть больше.
    echo "⚠️  UDIF недоступен, использую makehybrid (HFS, без сжатия)"
    rm -f "$DMG_PATH"
    hdiutil makehybrid -o "$DMG_PATH" "$STAGE_DIR" -hfs -quiet
fi

if [[ "$IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
fi

# --- Нотаризация -----------------------------------------------------------
if [[ -n "$NOTARY_PROFILE" ]]; then
    if [[ "$IDENTITY" == "-" ]]; then
        echo "❌ Нотаризация невозможна с ad-hoc подписью." >&2
        exit 1
    fi
    echo "==> Нотаризация (профиль: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling..."
    xcrun stapler staple "$DMG_PATH"
fi

# --- Проверки --------------------------------------------------------------
echo "==> Проверка бандла..."
codesign --verify --strict --deep --verbose=2 "$APP_PATH"
enforce_no_symlinks "$APP_PATH"
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"

if [[ "$IDENTITY" == "-" ]]; then
    echo "⚠️  Бандл подписан ad-hoc: Gatekeeper заблокирует его у пользователей."
    echo "    Инструкция для пользователей: xattr -cr /Applications/Golosok.app"
else
    echo "==> Оценка Gatekeeper..."
    spctl --assess --type execute --verbose=4 "$APP_PATH" || true
fi

echo "==> Готово:"
echo "    App: $APP_PATH"
echo "    DMG: $DMG_PATH"
