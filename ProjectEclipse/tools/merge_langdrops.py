#!/usr/bin/env python3
"""Merge docs/plans_v3/langdrop/*.json into the real lang files.

Langdrop format per worker: {"en_us": {key: text}, "de_de": {key: text}}.
Langdrop values override existing lang entries (deliberate overrides allowed).
Run from ProjectEclipse root. Idempotent.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANG_DIR = ROOT / "src/main/resources/assets/eclipse/lang"
DROP_DIR = ROOT / "docs/plans_v3/langdrop"


def main() -> int:
    drops = sorted(DROP_DIR.glob("*.json"))
    if not drops:
        print("no langdrops found")
        return 0
    merged = {"en_us": {}, "de_de": {}}
    for drop in drops:
        try:
            data = json.loads(drop.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            print(f"ERROR: {drop.name}: {e}")
            return 1
        for locale in ("en_us", "de_de"):
            for k, v in (data.get(locale) or {}).items():
                if k in merged[locale] and merged[locale][k] != v:
                    print(f"WARN: {locale} key '{k}' set by multiple drops; last wins ({drop.name})")
                merged[locale][k] = v
    for locale in ("en_us", "de_de"):
        path = LANG_DIR / f"{locale}.json"
        lang = json.loads(path.read_text(encoding="utf-8"))
        before = len(lang)
        overridden = sum(1 for k in merged[locale] if k in lang and lang[k] != merged[locale][k])
        lang.update(merged[locale])
        path.write_text(
            json.dumps(dict(sorted(lang.items())), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"{locale}: {before} -> {len(lang)} keys (+{len(lang) - before}, {overridden} overridden)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
