# Changelog

## Unreleased

- High-level callback API: `defineModuleCallback` / `defineMethodCallback` /
  `defineClassMethodCallback` with `fn (*VM, []const Value) Error!Value`.
- Automatic argument/return marshalling, Zig error to Ruby exception mapping,
  callback registry cleanup on VM deinit, and >16 argument support.
- Range construction, callback-backed Procs, Time/object reflection, array and
  hash iterators, RootedValue/arenaScope, lastException and bounded backtraces.
- Default `(eval)` filename so compiled code carries debug info for backtraces.
- Bytecode loading: `VM.loadIrep` / `loadIrepWithOptions`, `mrbc` fixture and regeneration script.
- Configurable 64-bit ABI layouts: word, NAN boxing (`MRB_INT64`), and `MRB_NO_BOXING` via `-Dmruby-boxing`.
- Binding symbol check in CI; Windows MinGW CI with a core-only mruby build profile.
- Compile-time rejection for `MRB_32BIT` / unsynchronized boxing macros.
- Test suite: 93 tests (88 Zig + 5 Ruby integration suites).

## 0.1.0 (2026-11-13)

- Zig 0.16.0 + mruby 4.0.0 release baseline.
- VM/Value API: eval, call, arrays/hashes, callbacks, error diagnostics, GC arena.
- Protected eval/call/construction/definition paths; NUL-safe source handling.
- 75 tests: 70 Zig tests + 5 Ruby integration suites.
- Build script with mruby SHA-256 verification, toolchain pin, clean-room CI.
- Compatibility policy and canary workflow for future Zig/mruby upgrades.

## 0.2.0 (planned)

- Zig 0.17.1 migration on a dedicated branch.
- mruby 4.1 evaluation after its stable release.
- Bytecode (`mrbc`/`mrb_load_irep`), block callbacks, explicit roots, structured backtraces.
