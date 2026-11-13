#!/usr/bin/env bash
set -euo pipefail

# Verify that every mrb_* symbol declared in src/c.zig exists in libmruby.a.
# This catches drift after a mruby upgrade without requiring translate-c.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="${MRUBY_LIB:-"$root/vendor/mruby/build/host/lib/libmruby.a"}"

if [[ ! -f "$lib" ]]; then
  echo "missing mruby library: $lib" >&2
  exit 1
fi

symbols="$(nm -g "$lib" 2>/dev/null | awk '{print $NF}' | sed 's/^_//' | sort -u)"
missing=0

while IFS= read -r symbol; do
  case "$symbol" in
    zruby_*) continue ;;
  esac
  if ! grep -qx "$symbol" <<<"$symbols"; then
    echo "missing mruby symbol: $symbol" >&2
    missing=1
  fi
done < <(sed -n 's/^pub extern fn \([A-Za-z0-9_]*\).*/\1/p' "$root/src/c.zig")

if [[ "$missing" -ne 0 ]]; then
  echo "binding check failed" >&2
  exit 1
fi

echo "binding check: all declared mruby symbols are present"
