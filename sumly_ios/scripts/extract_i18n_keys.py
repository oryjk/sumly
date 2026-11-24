#!/usr/bin/env python3
"""Extract all L10n / AuthL10n keys from Sumly + SumlyWidget Swift sources."""
import glob
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZH_STRINGS = os.path.join(ROOT, "Sumly", "Resources", "zh-Hans.lproj", "Localizable.strings")
OUT_JSON = os.path.join(ROOT, "scripts", "i18n_keys.json")

CALL_RE = re.compile(r'\b(?:L10n|AuthL10n)\.(?:tr|fmt)\s*\(\s*"((?:[^"\\\n]|\\.)*)"')
STRINGS_LINE_RE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')


def unescape_swift_string(raw: str) -> str:
    out = []
    i = 0
    n = len(raw)
    while i < n:
        ch = raw[i]
        if ch == "\\" and i + 1 < n:
            nxt = raw[i + 1]
            if nxt == "n":
                out.append("\n")
                i += 2
            elif nxt == "r":
                out.append("\r")
                i += 2
            elif nxt == "t":
                out.append("\t")
                i += 2
            elif nxt == '"':
                out.append('"')
                i += 2
            elif nxt == "\\":
                out.append("\\")
                i += 2
            elif nxt == "u" and i + 2 < n and raw[i + 2] == "{":
                end = raw.find("}", i + 3)
                if end != -1:
                    out.append(chr(int(raw[i + 3 : end], 16)))
                    i = end + 1
                else:
                    out.append(ch)
                    i += 1
            else:
                out.append(nxt)
                i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def escape_apple_strings(text: str) -> str:
    return (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )


def strip_swift_comments(src: str) -> str:
    # Remove /* ... */ block comments and // line comments outside string literals.
    out = []
    i = 0
    n = len(src)
    in_str = False
    while i < n:
        if in_str:
            ch = src[i]
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(src[i + 1])
                i += 2
                continue
            if ch == '"':
                in_str = False
            i += 1
        else:
            if src[i : i + 2] == "//":
                while i < n and src[i] != "\n":
                    i += 1
            elif src[i : i + 2] == "/*":
                i += 2
                depth = 1
                while i < n and depth > 0:
                    if src[i : i + 2] == "/*":
                        depth += 1
                        i += 2
                    elif src[i : i + 2] == "*/":
                        depth -= 1
                        i += 2
                    else:
                        i += 1
            else:
                ch = src[i]
                if ch == '"':
                    in_str = True
                out.append(ch)
                i += 1
    return "".join(out)


def main() -> int:
    keys = set()
    files = sorted(
        glob.glob(os.path.join(ROOT, "Sumly", "Sources", "**", "*.swift"), recursive=True)
        + glob.glob(os.path.join(ROOT, "SumlyWidget", "**", "*.swift"), recursive=True)
    )
    for path in files:
        with open(path, encoding="utf-8") as f:
            clean = strip_swift_comments(f.read())
        for m in CALL_RE.finditer(clean):
            key = unescape_swift_string(m.group(1))
            if key:
                keys.add(key)

    # Preserve any existing keys already in zh-Hans Localizable.strings
    if os.path.exists(ZH_STRINGS):
        with open(ZH_STRINGS, encoding="utf-8") as f:
            for line in f:
                m = STRINGS_LINE_RE.match(line)
                if m:
                    keys.add(unescape_swift_string(m.group(1)))

    sorted_keys = sorted(keys)

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(sorted_keys, f, ensure_ascii=False, indent=2)
        f.write("\n")

    lines = [
        "/* Sumly / 记金 Localizable.strings (zh-Hans) - auto-extracted master catalog */",
        "",
    ]
    for k in sorted_keys:
        ek = escape_apple_strings(k)
        lines.append(f'"{ek}" = "{ek}";')
    with open(ZH_STRINGS, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    subprocess.run(["plutil", "-lint", ZH_STRINGS], check=True)
    print(f"Extracted {len(sorted_keys)} unique localization keys from {len(files)} Swift files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
