#!/usr/bin/env python3
"""
Golosok Project Invariant Verifier (Architecture & Localization Gate)
Runs before build. Fails the build if:
1. Localizable.xcstrings has keys missing 'en' or 'ru' translations.
2. Swift UI code contains raw, unlocalized Cyrillic strings in UI views.
3. Версия в VERSION, pbxproj и шаблоне Info.plist не расходится.
4. В рантайм-код не утекли приватные адреса, чужие репозитории и эвристики по портам.
"""

import sys
import json
import re
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
XCSTRINGS_PATH = REPO_ROOT / "Golosok" / "Localizable.xcstrings"
SWIFT_DIR = REPO_ROOT / "Golosok"

def check_localization_integrity():
    errors = []
    if not XCSTRINGS_PATH.exists():
        errors.append(f"Missing xcstrings catalog at {XCSTRINGS_PATH}")
        return errors

    with open(XCSTRINGS_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except Exception as e:
            errors.append(f"Invalid JSON in Localizable.xcstrings: {e}")
            return errors

    strings = data.get("strings", {})
    missing_en = []
    missing_ru = []

    for key, item in strings.items():
        if not key.strip():
            continue
        locs = item.get("localizations", {})
        
        # Check EN
        en_val = locs.get("en", {}).get("stringUnit", {}).get("value")
        if en_val is None or en_val == "":
            missing_en.append(key)

        # Check RU
        ru_val = locs.get("ru", {}).get("stringUnit", {}).get("value")
        if ru_val is None or ru_val == "":
            missing_ru.append(key)

    if missing_en:
        errors.append(f"Localizable.xcstrings: {len(missing_en)} keys missing English translation! e.g. {missing_en[:5]}")
    if missing_ru:
        errors.append(f"Localizable.xcstrings: {len(missing_ru)} keys missing Russian translation! e.g. {missing_ru[:5]}")

    return errors

def check_unlocalized_ui_strings():
    errors = []
    # Match UI string declarations that have Cyrillic literals or explicit localization calls
    patterns = [
        (re.compile(r'Text\(\s*"([^"]*[а-яА-ЯёЁ][^"]*)"\s*\)'), "Text(...) raw string"),
        (re.compile(r'Button\(\s*"([^"]*[а-яА-ЯёЁ][^"]*)"\s*\)'), "Button(...) raw string"),
        (re.compile(r'UIOutlineButton\(\s*title:\s*"([^"]*[а-яА-ЯёЁ][^"]*)"'), "UIOutlineButton raw title"),
        (re.compile(r'UIPrimaryButton\(\s*title:\s*"([^"]*[а-яА-ЯёЁ][^"]*)"'), "UIPrimaryButton raw title"),
        (re.compile(r'UIDestructiveButton\(\s*title:\s*"([^"]*[а-яА-ЯёЁ][^"]*)"'), "UIDestructiveButton raw title"),
        (re.compile(r'Label\(\s*"([^"]*[а-яА-ЯёЁ][^"]*)"'), "Label(...) raw title"),
        (re.compile(r'TextField\(\s*"([^"]*[а-яА-ЯёЁ][^"]*)"'), "TextField(...) raw placeholder"),
        (re.compile(r'SecureField\(\s*"([^"]*[а-яА-ЯёЁ][^"]*)"'), "SecureField(...) raw placeholder"),
        (re.compile(r'UIBadge\(\s*text:\s*"([^"]*[а-яА-ЯёЁ][^"]*)"'), "UIBadge(...) raw text"),
        (re.compile(r'\.help\(\s*"([^"]*[а-яА-ЯёЁ][^"]*)"\s*\)'), ".help(...) raw string"),
        (re.compile(r'String\(\s*localized:\s*"([^"\\]*(?:\\.[^"\\]*)*)"'), "String(localized:)"),
        (re.compile(r'LocalizedStringKey\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"'), "LocalizedStringKey(...)"),
        (re.compile(r'L10n\.tr\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"'), "L10n.tr(...)"),
        (re.compile(r'L10n\.format\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"'), "L10n.format(...)"),
        (re.compile(r'\.key\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"'), "LocalizedMessage.key(...)"),
        (re.compile(r'\.formatted\(\s*key:\s*"([^"\\]*(?:\\.[^"\\]*)*)"'), "LocalizedMessage.formatted(...)"),
    ]

    with open(XCSTRINGS_PATH, "r", encoding="utf-8") as f:
        xc_keys = set(json.load(f).get("strings", {}).keys())

    for swift_path in SWIFT_DIR.glob("*.swift"):
        with open(swift_path, "r", encoding="utf-8") as f:
            for line_no, line in enumerate(f, 1):
                clean_line = line.strip()
                if clean_line.startswith("//") or clean_line.startswith("/*"):
                    continue
                for pat, desc in patterns:
                    for m in pat.finditer(line):
                        raw_text = m.group(1).strip()
                        if r'\(' in raw_text:
                            errors.append(f"{swift_path.name}:{line_no} [{desc}] -> interpolated string \"{raw_text}\" must use String(format: String(localized: ...))!")
                            continue
                        unescaped = raw_text.replace("\\n", "\n").replace('\\"', '"')
                        # If the literal is not present as a key in xcstrings, it is a hard violation
                        if unescaped not in xc_keys:
                            errors.append(f"{swift_path.name}:{line_no} [{desc}] -> \"{unescaped}\" is not in Localizable.xcstrings!")

    return errors

def check_version_consistency():
    """Единый источник версии: VERSION ↔ MARKETING_VERSION ↔ шаблон Info.plist."""
    errors = []
    version_path = REPO_ROOT / "VERSION"
    if not version_path.exists():
        return ["Нет файла VERSION (единственного источника версии)"]

    version = version_path.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        errors.append(f"VERSION содержит невалидную версию: {version!r}")

    pbxproj = REPO_ROOT / "Golosok.xcodeproj" / "project.pbxproj"
    if pbxproj.exists():
        marketing = re.findall(r"MARKETING_VERSION = ([^;]+);", pbxproj.read_text(encoding="utf-8"))
        versions = {value.strip().strip('"') for value in marketing}
        # Тестовые таргеты держат собственный MARKETING_VERSION (1.0) — сверяем только
        # наличие версии приложения среди значений, а не равенство множеств.
        if versions and version not in versions:
            errors.append(
                f"MARKETING_VERSION в pbxproj {sorted(versions)} не содержит VERSION {version}"
            )

    template = REPO_ROOT / "Info.plist"
    if template.exists():
        body = template.read_text(encoding="utf-8")
        if "$(MARKETING_VERSION)" not in body:
            errors.append("Info.plist не использует $(MARKETING_VERSION): версия задублирована")
    else:
        errors.append("Нет шаблона Info.plist")

    return errors


# Приватные адреса и чужие идентификаторы не должны попадать в рантайм.
FORBIDDEN_RUNTIME_PATTERNS = [
    (re.compile(r"\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b"), "CGNAT/Tailscale адрес"),
    (re.compile(r"\b192\.168\.\d{1,3}\.\d{1,3}\b"), "приватный адрес 192.168.x.x"),
    (re.compile(r"\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"), "приватный адрес 10.x.x.x"),
    (re.compile(r"\b172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b"), "приватный адрес 172.16-31.x.x"),
    (re.compile(r'contains\(\s*"\d{2,5}"\s*\)'), "эвристика по номеру порта"),
    (re.compile(r"Berliner187"), "чужой репозиторий в рантайм-коде"),
]


def check_runtime_hygiene():
    errors = []
    for swift_path in sorted(SWIFT_DIR.glob("*.swift")):
        with open(swift_path, "r", encoding="utf-8") as f:
            for line_no, line in enumerate(f, 1):
                stripped = line.strip()
                if stripped.startswith("//") or stripped.startswith("/*"):
                    continue
                for pattern, description in FORBIDDEN_RUNTIME_PATTERNS:
                    match = pattern.search(line)
                    if match:
                        errors.append(
                            f"{swift_path.name}:{line_no} [{description}] -> {match.group(0)!r}"
                        )
    return errors


def main():
    print("==> Проверка архитектурных инвариантов и локализации (Pre-Build Gate)...")
    all_errors = []
    
    # 1. Localization completeness
    l10n_errors = check_localization_integrity()
    all_errors.extend(l10n_errors)
    
    # 2. Hardcoded UI strings
    ui_errors = check_unlocalized_ui_strings()
    all_errors.extend(ui_errors)

    # 3. Единый источник версии
    all_errors.extend(check_version_consistency())

    # 4. Гигиена рантайма (приватные адреса, чужие репозитории, эвристики)
    all_errors.extend(check_runtime_hygiene())

    if all_errors:
        print("\n❌ ПРОВЕРКА ИНВАРИАНТОВ ПРОВАЛЕНА! Обнаружены архитектурные нарушения:")
        for err in all_errors:
            print(f"  • {err}")
        print("\nСборка остановлена. Исправьте рассинхрон перед компиляцией.\n")
        sys.exit(1)
    else:
        print("✅ Все архитектурные инварианты и двуязычность соблюдены (0 нарушений).")

if __name__ == "__main__":
    main()
