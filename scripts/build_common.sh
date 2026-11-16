#!/bin/bash
# Общие шаги сборки GolosYaka. Подключается через `source` из build-dev.sh и build-release.sh.
# Требования: macOS, Command Line Tools (swiftc), rsync, python3.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GOLOSYAKA_MIN_OS="${GOLOSYAKA_MIN_OS:-13.0}"
GOLOSYAKA_BUNDLE_ID="${GOLOSYAKA_BUNDLE_ID:-com.realmagnum.GolosYaka}"
GOLOSYAKA_EXECUTABLE="GolosYaka"
# Откуда берутся реальные ресурсы (ffmpeg, whisper-cli, transcribe-cli, модель GigaAM).
# Можно переопределить: GOLOSYAKA_RESOURCES_DIR=/path/to/Resources ./build-release.sh
# Иначе ищем установленное приложение: сначала новое имя, затем старое (Golosok) — ресурсы
# у форка те же, а старая установка ещё может быть на месте.
if [[ -n "${GOLOSYAKA_RESOURCES_DIR:-}" ]]; then
    GOLOSYAKA_RESOURCES_SRC="$GOLOSYAKA_RESOURCES_DIR"
elif [[ -d "/Applications/GolosYaka.app/Contents/Resources" ]]; then
    GOLOSYAKA_RESOURCES_SRC="/Applications/GolosYaka.app/Contents/Resources"
else
    GOLOSYAKA_RESOURCES_SRC="/Applications/Golosok.app/Contents/Resources"
fi

read_version() {
    local version
    version="$(head -n 1 "$ROOT/VERSION" | tr -d '[:space:]')"
    if [[ -z "$version" ]]; then
        echo "❌ Файл VERSION пуст" >&2
        return 1
    fi
    printf '%s\n' "$version"
}

read_build_number() {
    local number
    number="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
    printf '%s\n' "$number"
}

verify_invariants() {
    echo "==> Проверка архитектурных инвариантов и локализации..."
    python3 "$ROOT/scripts/verify_project_invariants.py"
}

# compile_binary <arm64|x86_64|universal> <output-path>
compile_binary() {
    local archs="$1"
    local output="$2"
    local sdk
    sdk="$(xcrun --show-sdk-path)"
    local -a inputs=("$ROOT"/GolosYaka/*.swift)
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN

    local -a targets=()
    case "$archs" in
        universal) targets=("arm64-apple-macos${GOLOSYAKA_MIN_OS}" "x86_64-apple-macos${GOLOSYAKA_MIN_OS}") ;;
        arm64) targets=("arm64-apple-macos${GOLOSYAKA_MIN_OS}") ;;
        x86_64) targets=("x86_64-apple-macos${GOLOSYAKA_MIN_OS}") ;;
        *) echo "❌ Неизвестная архитектура: $archs" >&2; return 1 ;;
    esac

    local -a slices=()
    local target
    for target in "${targets[@]}"; do
        local slice="$tmp_dir/${target%%-*}"
        echo "==> Компиляция ($target)..."
        swiftc -parse-as-library -target "$target" -O -sdk "$sdk" "${inputs[@]}" -o "$slice"
        slices+=("$slice")
    done

    mkdir -p "$(dirname "$output")"
    if [[ ${#slices[@]} -eq 1 ]]; then
        cp "${slices[0]}" "$output"
    else
        lipo -create "${slices[@]}" -output "$output"
    fi
    chmod +x "$output"
    echo "==> Бинарник: $(file -b "$output")"
}

# enforce_no_symlinks <bundle-path>
enforce_no_symlinks() {
    local bundle="$1"
    local offenders
    offenders="$(find "$bundle" -type l -print)"
    if [[ -n "$offenders" ]]; then
        echo "❌ В бандле остались симлинки (бандл невалиден для распространения):" >&2
        echo "$offenders" >&2
        return 1
    fi
}

# stage_bundle <bundle-path> <binary> <version> <build-number>
stage_bundle() {
    local bundle="$1"
    local binary="$2"
    local version="$3"
    local build_number="$4"
    local contents="$bundle/Contents"
    local resources="$contents/Resources"

    echo "==> Сборка бандла: $bundle"
    rm -rf "$bundle"
    mkdir -p "$contents/MacOS" "$resources"
    printf 'APPL????' > "$contents/PkgInfo"

    cp "$binary" "$contents/MacOS/$GOLOSYAKA_EXECUTABLE"

    if [[ ! -d "$GOLOSYAKA_RESOURCES_SRC" ]]; then
        echo "❌ Не найдены исходные ресурсы: $GOLOSYAKA_RESOURCES_SRC" >&2
        echo "   Укажите каталог: GOLOSYAKA_RESOURCES_DIR=/path/to/Resources" >&2
        return 1
    fi

    echo "==> Копирование ресурсов реальными файлами (без симлинков): $GOLOSYAKA_RESOURCES_SRC"
    # --copy-links разворачивает симлинки старого dev-бандла, --exclude .lproj —
    # локализации генерируются из String Catalog ниже.
    rsync -a --copy-links --exclude '*.lproj' --exclude '.DS_Store' --exclude 'README.md' \
        "$GOLOSYAKA_RESOURCES_SRC"/ "$resources"/

    python3 "$ROOT/scripts/generate_localizations.py" \
        --xcstrings "$ROOT/GolosYaka/Localizable.xcstrings" \
        --resources-dir "$resources"

    # Юридические тексты обязаны ехать внутри бандла, а не только в репозитории.
    cp "$ROOT/LICENSE" "$resources/LICENSE.md"
    cp "$ROOT/THIRD-PARTY-NOTICES.md" "$resources/THIRD-PARTY-NOTICES.md"

    python3 "$ROOT/scripts/generate_info_plist.py" \
        --template "$ROOT/Info.plist" \
        --output "$contents/Info.plist" \
        --marketing-version "$version" \
        --build-number "$build_number" \
        --min-os "$GOLOSYAKA_MIN_OS" \
        --bundle-id "$GOLOSYAKA_BUNDLE_ID" \
        --executable "$GOLOSYAKA_EXECUTABLE"

    enforce_no_symlinks "$bundle"
}

# sign_bundle <bundle-path> <identity|-> [hardened]
sign_bundle() {
    local bundle="$1"
    local identity="$2"
    local hardened="${3:-}"

    xattr -cr "$bundle"
    local -a args=(--force --deep --timestamp --options runtime --entitlements "$ROOT/GolosYaka.entitlements")
    if [[ "$hardened" != "hardened" ]]; then
        args=(--force --deep)
    fi

    echo "==> Подпись ($identity${hardened:+, hardened runtime})..."
    codesign "${args[@]}" --sign "$identity" "$bundle"

    echo "==> Проверка подписи..."
    codesign --verify --strict --deep --verbose=2 "$bundle"
}

print_banner() {
    echo "╭──────────────────────────────────────────────╮"
    printf "│ GolosYaka %-36s│\n" "$1"
    echo "╰──────────────────────────────────────────────╯"
}
