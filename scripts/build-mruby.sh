#!/usr/bin/env bash
set -euo pipefail

# Build the mruby static library used by zruby. Requirements:
#   - Ruby 2.5+ with rake
#   - a C toolchain (clang/gcc, make, ar)
# The release tarball ships generated parser sources, so bison/gperf are not
# required for the default configuration.
#
# Override the mruby version or configuration with:
#   MRUBY_VERSION=4.0.0 MRUBY_CONFIG=build_config/default.rb ./scripts/build-mruby.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MRUBY_VERSION="${MRUBY_VERSION:-4.0.0}"
MRUBY_DIR="$ROOT/vendor/mruby"
ARCHIVE="$ROOT/vendor/mruby-$MRUBY_VERSION.tar.gz"
URL="https://github.com/mruby/mruby/archive/refs/tags/$MRUBY_VERSION.tar.gz"
# SHA-256 of the mruby 4.0.0 release tarball. Set MRUBY_SHA256 yourself when
# intentionally testing another version; an empty value skips the check.
if [ "$MRUBY_VERSION" = "4.0.0" ]; then
  MRUBY_SHA256="${MRUBY_SHA256:-e2ea271dbed14e9f2b33df773ae447b747dbc242ce2675022c0a57efea85a7b4}"
else
  MRUBY_SHA256="${MRUBY_SHA256:-}"
fi

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mkdir -p "$ROOT/vendor"

if [ ! -d "$MRUBY_DIR/src" ]; then
  if [ ! -f "$ARCHIVE" ]; then
    echo "downloading mruby $MRUBY_VERSION"
    curl -fsSL "$URL" -o "$ARCHIVE"
  fi
  if [ -n "$MRUBY_SHA256" ]; then
    actual_hash="$(hash_file "$ARCHIVE")"
    if [ "$actual_hash" != "$MRUBY_SHA256" ]; then
      echo "mruby tarball checksum mismatch" >&2
      echo "expected: $MRUBY_SHA256" >&2
      echo "actual:   $actual_hash" >&2
      exit 1
    fi
  fi
  echo "extracting $ARCHIVE"
  rm -rf "$MRUBY_DIR"
  mkdir -p "$MRUBY_DIR"
  tar xzf "$ARCHIVE" -C "$MRUBY_DIR" --strip-components=1
fi

echo "building mruby in $MRUBY_DIR"
(
  cd "$MRUBY_DIR"
  if [ -n "${MRUBY_CONFIG:-}" ]; then
    MRUBY_CONFIG="$MRUBY_CONFIG" rake all
  else
    rake all
  fi
)

LIB="$MRUBY_DIR/build/host/lib/libmruby.a"
if [ ! -f "$LIB" ]; then
  echo "mruby build did not produce $LIB" >&2
  exit 1
fi

MRUBY_BIN="$MRUBY_DIR/build/host/bin/mruby"
actual_version="$("$MRUBY_BIN" -v | awk '{print $2}')"
if [ "$actual_version" != "$MRUBY_VERSION" ]; then
  echo "mruby version mismatch: expected $MRUBY_VERSION, found $actual_version" >&2
  exit 1
fi

echo "mruby built: $LIB"
echo "headers:     $MRUBY_DIR/build/host/include"
echo "now run:     zig build test"
