#!/usr/bin/env python3
"""Render src/c.zig from a template, mruby translate-c output and a manifest."""

from __future__ import annotations

import re
import sys
from pathlib import Path

MARK_BEGIN = "// <generated:mruby>"
MARK_END = "// </generated:mruby>"


def read_externs(translated: str) -> dict[str, str]:
    result: dict[str, str] = {}
    pattern = re.compile(r"pub extern fn\s+([A-Za-z0-9_]+)\(.*?\)[^;]*;", re.S)
    for match in pattern.finditer(translated):
        result[match.group(1)] = match.group(0).strip()
    return result


def normalize(declaration: str) -> str:
    for old, new in (
        ("?*struct_RClass", "?*RClass"),
        ("?*struct_RProc", "?*RProc"),
        ("?*struct_mrb_parser_state", "?*mrb_parser_state"),
        ("?*struct_mrb_state", "?*mrb_state"),
    ):
        declaration = declaration.replace(old, new)
    # len is ABI-compatible with usize on supported 64-bit targets and keeps
    # the public Zig signature stable.
    if declaration.startswith("pub extern fn mrb_str_new("):
        declaration = declaration.replace("len: mrb_int", "len: usize")
    return declaration


def main() -> int:
    if len(sys.argv) not in (4, 5):
        print("usage: generate_bindings.py TRANSLATED TEMPLATE MANIFEST [OUTPUT]", file=sys.stderr)
        return 2
    translated = Path(sys.argv[1]).read_text()
    template = Path(sys.argv[2]).read_text()
    manifest = [line.strip() for line in Path(sys.argv[3]).read_text().splitlines() if line.strip()]

    externs = read_externs(translated)
    missing = [name for name in manifest if name not in externs]
    if missing:
        print("missing translated declarations: " + ", ".join(missing), file=sys.stderr)
        return 1

    block = "\n".join(normalize(externs[name]) for name in manifest)
    begin = template.index(MARK_BEGIN) + len(MARK_BEGIN)
    end = template.index(MARK_END)
    rendered = template[:begin] + "\n" + block + "\n" + template[end:]
    rendered = "// Generated in part from mruby headers by scripts/generate-bindings.sh.\n" + rendered

    if len(sys.argv) == 5:
        Path(sys.argv[4]).write_text(rendered)
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
