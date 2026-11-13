#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mrbc="${MRBC:-"$root/vendor/mruby/build/host/bin/mrbc"}"

if [[ ! -x "$mrbc" ]]; then
  echo "mrbc not found at $mrbc; run scripts/build-mruby.sh first" >&2
  exit 1
fi

"$mrbc" -g -o "$root/tests/fixtures/bytecode.mrb" "$root/tests/fixtures/bytecode.rb"
echo "wrote $root/tests/fixtures/bytecode.mrb"
