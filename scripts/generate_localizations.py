#!/usr/bin/env python3
"""
Генерирует en.lproj/ru.lproj/Localizable.strings из GolosYaka/Localizable.xcstrings.

Единственный источник локализаций — String Catalog. Скрипт падает, если у ключа нет
одного из двух переводов, чтобы в бандл не попал полупустой .strings.
"""

import argparse
import json
import sys
from pathlib import Path

LANGS = ("en", "ru")


def escape(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )


def load_translations(xcstrings: Path):
    with open(xcstrings, encoding="utf-8") as handle:
        catalog = json.load(handle)

    translations = {lang: {} for lang in LANGS}
    missing = []

    for key, item in catalog.get("strings", {}).items():
        if not key.strip():
            continue
        localizations = item.get("localizations", {})
        for lang in LANGS:
            unit = localizations.get(lang, {}).get("stringUnit", {})
            value = unit.get("value")
            if not value:
                missing.append((key, lang))
                continue
            translations[lang][key] = value

    return translations, missing


def write_strings(translations: dict, resources_dir: Path) -> None:
    for lang, entries in translations.items():
        target = resources_dir / f"{lang}.lproj" / "Localizable.strings"
        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, "w", encoding="utf-8") as handle:
            for key in sorted(entries):
                handle.write(f'"{escape(key)}" = "{escape(entries[key])}";\n')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xcstrings", required=True)
    parser.add_argument("--resources-dir", required=True)
    args = parser.parse_args()

    translations, missing = load_translations(Path(args.xcstrings))
    if missing:
        preview = ", ".join(f"{key!r} [{lang}]" for key, lang in missing[:10])
        print(f"❌ В Localizable.xcstrings нет переводов: {preview}", file=sys.stderr)
        return 1

    write_strings(translations, Path(args.resources_dir))
    print(
        "==> Localizable.strings: "
        + ", ".join(f"{lang}={len(entries)}" for lang, entries in translations.items())
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
