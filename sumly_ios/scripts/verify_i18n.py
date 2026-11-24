#!/usr/bin/env python3
"""Verify 6-language Localizable.strings syntax, 100% key coverage, and printf format specifier parity."""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Sumly", "Resources")
KEYS_JSON = os.path.join(ROOT, "scripts", "i18n_keys.json")
LANGS = ["zh-Hans", "en", "es", "fr", "pt", "ja"]

# Match printf format specifiers (skipping escaped %%)
FMT_RE = re.compile(r'%(?:%|(?:(\d+)\$)?[-+#0 ]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?([@dDuUxXoOfeEgGcCsSpFaA]))')
CJK_RE = re.compile(r'[\u4e00-\u9fff]')


def parse_strings(path: str) -> dict[str, str]:
    raw = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", path])
    return json.loads(raw.decode("utf-8"))


def extract_specifiers(text: str) -> list[str]:
    specs = []
    for m in FMT_RE.finditer(text):
        if m.group(0) == "%%":
            continue
        pos = m.group(1)
        conv = m.group(2)
        specs.append((int(pos) if pos else None, conv))
    # Sort positional specs by index so reordered translations like "%2$@ %1$@" pass cleanly!
    if specs and all(p is not None for p, _ in specs):
        return [c for _, c in sorted(specs, key=lambda x: x[0])]
    return [c for _, c in specs]


def main() -> int:
    target_langs = sys.argv[1:] if len(sys.argv) > 1 else LANGS
    with open(KEYS_JSON, encoding="utf-8") as f:
        master_keys: list[str] = json.load(f)

    failed = False
    for lang in target_langs:
        path = os.path.join(RES, f"{lang}.lproj", "Localizable.strings")
        info_path = os.path.join(RES, f"{lang}.lproj", "InfoPlist.strings")
        for p in (path, info_path):
            res = subprocess.run(["plutil", "-lint", p], capture_output=True, text=True)
            if res.returncode != 0:
                print(f"[FAIL] plutil -lint {p}: {res.stderr.strip()}")
                failed = True

        data = parse_strings(path)
        missing = [k for k in master_keys if k not in data or not data[k].strip()]
        fmt_errors = []
        cjk_leaks = []
        for k in master_keys:
            if k not in data:
                continue
            v = data[k]
            ks = extract_specifiers(k)
            vs = extract_specifiers(v)
            if ks != vs:
                fmt_errors.append((k, v, ks, vs))
            if lang in ("en", "es", "fr", "pt") and CJK_RE.search(v):
                # Allow native display name "简体中文" if ever present
                if k != "简体中文":
                    cjk_leaks.append((k, v))

        status = "PASS" if (not missing and not fmt_errors and not cjk_leaks) else "FAIL"
        print(
            f"[{status}] {lang:7s} | total={len(data)}/{len(master_keys)} | missing={len(missing)} | fmt_err={len(fmt_errors)} | cjk_leak={len(cjk_leaks)}"
        )
        if missing:
            print("  Missing sample:", missing[:10])
            failed = True
        if fmt_errors:
            for item in fmt_errors[:10]:
                print("  Format mismatch:", item)
            failed = True
        if cjk_leaks:
            for item in cjk_leaks[:10]:
                print("  CJK leak:", item)
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
