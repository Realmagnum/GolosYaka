#!/usr/bin/env python3
"""
Генерирует Info.plist бандла GolosYaka из шаблона Info.plist.

Шаблон содержит переменные сборки ($(MARKETING_VERSION), $(CURRENT_PROJECT_VERSION),
$(PRODUCT_BUNDLE_IDENTIFIER), $(MACOSX_DEPLOYMENT_TARGET)) — те же, что подставляет Xcode,
чтобы версия и минимальная ОС имели единственный источник истины (файл VERSION).

Подстановка текстовая: plistlib не нужен, шаблон сохраняет комментарии, а проверка
на неразвёрнутые переменные ловит опечатки в именах.
"""

import argparse
import re
import sys
from pathlib import Path

VARIABLE = re.compile(r"\$\(([A-Z_]+)\)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True, help="Путь к шаблону Info.plist")
    parser.add_argument("--output", required=True, help="Куда записать готовый Info.plist")
    parser.add_argument("--marketing-version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--min-os", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--executable", default="GolosYaka")
    args = parser.parse_args()

    template = Path(args.template)
    if not template.exists():
        print(f"❌ Шаблон Info.plist не найден: {template}", file=sys.stderr)
        return 1

    variables = {
        "MARKETING_VERSION": args.marketing_version,
        "CURRENT_PROJECT_VERSION": args.build_number,
        "PRODUCT_BUNDLE_IDENTIFIER": args.bundle_id,
        "MACOSX_DEPLOYMENT_TARGET": args.min_os,
        "EXECUTABLE_NAME": args.executable,
        "PRODUCT_NAME": args.executable,
    }

    body = template.read_text(encoding="utf-8")

    def replace(match: re.Match) -> str:
        name = match.group(1)
        return variables.get(name, match.group(0))

    rendered = VARIABLE.sub(replace, body)

    unknown = sorted({m.group(0) for m in VARIABLE.finditer(rendered)})
    if unknown:
        print(f"❌ В Info.plist остались неразвёрнутые переменные: {unknown}", file=sys.stderr)
        return 1

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(rendered, encoding="utf-8")

    print(f"==> Info.plist: v{args.marketing_version} ({args.build_number}), macOS {args.min_os}+")
    return 0


if __name__ == "__main__":
    sys.exit(main())
