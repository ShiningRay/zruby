#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check=0
if [[ "${1:-}" == "--check" ]]; then
  check=1
elif [[ $# -gt 0 ]]; then
  echo "usage: scripts/generate-bindings.sh [--check]" >&2
  exit 2
fi

include="$root/vendor/mruby/build/host/include"
if [[ ! -d "$include" ]]; then
  echo "missing mruby headers: $include (run scripts/build-mruby.sh)" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

zig translate-c \
  -I "$include" \
  -DMRB_NO_DEFAULT_RO_DATA_P=1 \
  -DMRB_USE_SET=1 \
  -DHAVE_MRUBY_IO_GEM=1 \
  -DMRB_USE_RATIONAL=1 \
  -DMRB_USE_COMPLEX=1 \
  -DMRB_USE_BIGINT=1 \
  -DMRB_USE_DEBUG_HOOK=1 \
  "$root/scripts/bindings_headers.h" > "$tmp/mruby.zig"

python3 "$root/scripts/generate_bindings.py" \
  "$tmp/mruby.zig" \
  "$root/src/c.template.zig" \
  "$root/scripts/bindings.txt" \
  "$tmp/c.zig"

if [[ "$check" -eq 1 ]]; then
  if ! diff -u "$root/src/c.zig" "$tmp/c.zig"; then
    echo "src/c.zig is out of date; run scripts/generate-bindings.sh" >&2
    exit 1
  fi
  echo "binding generation: src/c.zig is up to date"
else
  cp "$tmp/c.zig" "$root/src/c.zig"
  echo "wrote $root/src/c.zig"
fi
