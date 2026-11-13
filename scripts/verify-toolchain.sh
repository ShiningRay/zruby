#!/usr/bin/env bash
set -euo pipefail

# Verify the exact toolchain pair recorded by this release.
# Usage:
#   ./scripts/verify-toolchain.sh              # Zig + built mruby if present
#   ZRUBY_ZIG_VERSION=0.16.0 ./scripts/verify-toolchain.sh
#   MRUBY_BIN=/path/to/mruby ./scripts/verify-toolchain.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_ZIG="${ZRUBY_ZIG_VERSION:-0.16.0}"
EXPECTED_MRUBY="${ZRUBY_MRUBY_VERSION:-4.0.0}"
MRUBY_BIN="${MRUBY_BIN:-$ROOT/vendor/mruby/build/host/bin/mruby}"

actual_zig="$(zig version)"
if [ "$actual_zig" != "$EXPECTED_ZIG" ]; then
  echo "toolchain mismatch: expected Zig $EXPECTED_ZIG, found $actual_zig" >&2
  exit 1
fi

if [ -x "$MRUBY_BIN" ]; then
  actual_mruby="$("$MRUBY_BIN" -v | awk '{print $2}')"
  if [ "$actual_mruby" != "$EXPECTED_MRUBY" ]; then
    echo "toolchain mismatch: expected mruby $EXPECTED_MRUBY, found $actual_mruby" >&2
    exit 1
  fi
  echo "toolchain: Zig $actual_zig, mruby $actual_mruby"
else
  echo "toolchain: Zig $actual_zig; mruby not built yet ($MRUBY_BIN missing)"
fi
