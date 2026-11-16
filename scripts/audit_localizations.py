#!/usr/bin/env python3
"""
Аудит String Catalog: находит ключи, которые не встречаются ни в одном Swift-литерале.

Ключ считается используемым, если в исходниках есть литерал `"<ключ>"` (с учётом
escape-последовательностей) — это устойчиво к вложенным кавычкам внутри интерполяций
и к строкам с переводами строк. Ключи, собираемые в рантайме (имена уровней,
заголовки промптов из enum), перечислены в DYNAMIC_ALLOWLIST.

Использование:
    python3 scripts/audit_localizations.py            # только отчёт
    python3 scripts/audit_localizations.py --apply    # удалить неиспользуемые ключи
"""

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SWIFT_DIR = REPO_ROOT / "GolosYaka"
XCSTRINGS_PATH = SWIFT_DIR / "Localizable.xcstrings"

# Ключи, которые формируются в рантайме (L10n.tr(variable)) или приходят из enum/моделей.
DYNAMIC_ALLOWLIST = {
    "Новичок",
    "Ученик",
    "Практик",
    "Мастер",
    "Гуру",
    "Легенда",
}


def swift_literal_forms(key: str) -> tuple:
    """Возвращает варианты записи ключа в Swift-литерале."""
    plain = '"' + key + '"'
    escaped = (
        '"'
        + key.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
        + '"'
    )
    return plain, escaped


def load_sources() -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in SWIFT_DIR.glob("*.swift"))


def find_unused(strings: dict, sources: str) -> list:
    unused = []
    for key in strings:
        if not key.strip() or key in DYNAMIC_ALLOWLIST:
            continue
        plain, escaped = swift_literal_forms(key)
        if plain in sources or escaped in sources:
            continue
        unused.append(key)
    return sorted(unused)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Удалить неиспользуемые ключи")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    catalog = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = catalog.get("strings", {})
    unused = find_unused(strings, load_sources())

    if not args.quiet:
        print(f"==> Ключей в каталоге: {len(strings)}")
        print(f"==> Неиспользуемых: {len(unused)}")
        for key in unused:
            print(f"  • {key!r}")

    if args.apply and unused:
        for key in unused:
            del strings[key]
        XCSTRINGS_PATH.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"==> Удалено ключей: {len(unused)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
