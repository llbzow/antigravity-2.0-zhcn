#!/usr/bin/env python3
"""Antigravity 2.0 AI UI Chinese translator."""
import argparse
import json
import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRANSLATIONS_FILE = os.path.join(PROJECT_ROOT, "translations", "ui-translations.json")


def load_translations():
    with open(TRANSLATIONS_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)
    return [(t["key"], t["value"]) for t in data["translations"]]


def to_single_quoted(value):
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def apply_literal_replacement(content, original, translated):
    sv, tv = original[1:-1], translated[1:-1]
    before = content
    content = content.replace(repr(sv).replace('"', "'"), to_single_quoted(tv))
    content = content.replace(f'"{sv}"', f'"{tv}"')
    content = content.replace(to_single_quoted(sv), to_single_quoted(tv))
    content = content.replace(
        '"' + sv.replace("\\", "\\\\").replace('"', '\\"') + '"',
        '"' + tv.replace("\\", "\\\\").replace('"', '\\"') + '"',
    )
    return content, content != before


def main():
    parser = argparse.ArgumentParser(description="Translate Antigravity 2.0 AI UI bundle")
    parser.add_argument("--input", required=True, help="Path to the UI main.js bundle")
    parser.add_argument("--output", required=True, help="Path for the translated output")
    args = parser.parse_args()

    with open(args.input, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    translations = load_translations()
    print(f"Loaded {len(translations)} translations from {TRANSLATIONS_FILE}")
    print(f"Bundle: {len(content):,} bytes")

    LITERAL = re.compile(r"""^(["']).*\1$""")
    replaced = 0
    for original, translated in translations:
        changed = False
        if LITERAL.match(original) and LITERAL.match(translated):
            content, changed = apply_literal_replacement(content, original, translated)
        elif original in content:
            content = content.replace(original, translated)
            changed = True

        if changed:
            replaced += 1

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"Applied: {replaced}/{len(translations)}")
    print(f"Output: {args.output}")


if __name__ == "__main__":
    main()
