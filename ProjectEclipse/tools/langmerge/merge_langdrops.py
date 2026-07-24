#!/usr/bin/env python3
"""Merge docs/plans_v3/langdrop/*.json into the shipped lang files.

Langdrop schema: {"en_us": {key: value, ...}, "de_de": {key: value, ...}}
Langdrop keys win over existing keys (drops are authored intentionally).
Usage: python3 tools/langmerge/merge_langdrops.py [DROP ...]
Without args, merges every langdrop file.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LANG_DIR = ROOT / "src/main/resources/assets/eclipse/lang"
DROP_DIR = ROOT / "docs/plans_v3/langdrop"

REMOVALS = {"gui.eclipse.journey.settings_entry"}


def main() -> None:
    drops = sys.argv[1:]
    files = [DROP_DIR / d for d in drops] if drops else sorted(DROP_DIR.glob("*.json"))
    lang = {}
    for locale in ("en_us", "de_de"):
        path = LANG_DIR / f"{locale}.json"
        lang[locale] = json.loads(path.read_text(encoding="utf-8"))

    added = {"en_us": 0, "de_de": 0}
    for f in files:
        data = json.loads(f.read_text(encoding="utf-8"))
        if "en_us" in data or "de_de" in data:
            payload = {"en_us": data.get("en_us", {}), "de_de": data.get("de_de", {})}
        elif "en" in data or "de" in data:
            payload = {"en_us": data.get("en", {}), "de_de": data.get("de", {})}
        elif all(isinstance(v, str) for v in data.values()):
            # Flat English-only drop; German must be supplied via a sibling
            # "<name>.de.json" file, else keys land English-only in both.
            de_path = f.with_suffix(".de.json")
            de = json.loads(de_path.read_text(encoding="utf-8")) if de_path.exists() else data
            payload = {"en_us": data, "de_de": de}
        else:
            print(f"SKIP (not a locale drop): {f.name}")
            continue
        for locale in ("en_us", "de_de"):
            for k, v in payload.get(locale, {}).items():
                if lang[locale].get(k) != v:
                    added[locale] += 1
                lang[locale][k] = v
    for locale in ("en_us", "de_de"):
        for k in REMOVALS:
            lang[locale].pop(k, None)

    # Parity check
    en_keys, de_keys = set(lang["en_us"]), set(lang["de_de"])
    missing_de = sorted(en_keys - de_keys)
    missing_en = sorted(de_keys - en_keys)
    for locale in ("en_us", "de_de"):
        path = LANG_DIR / f"{locale}.json"
        path.write_text(
            json.dumps(lang[locale], ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    print(f"merged: en_us +{added['en_us']}, de_de +{added['de_de']}; totals "
          f"en={len(en_keys)} de={len(de_keys)}")
    if missing_de:
        print(f"MISSING de_de ({len(missing_de)}): {missing_de[:20]}")
    if missing_en:
        print(f"MISSING en_us ({len(missing_en)}): {missing_en[:20]}")
    if not missing_de and not missing_en:
        print("parity OK")


if __name__ == "__main__":
    main()
