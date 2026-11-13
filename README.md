# zruby

[![CI](https://github.com/ShiningRay/zruby/actions/workflows/ci.yml/badge.svg)](https://github.com/ShiningRay/zruby/actions/workflows/ci.yml)

在 Zig 0.16 中嵌入 mruby 4.0 的最小绑定。用 Zig 管理 VM、调用 Ruby 代码，也可以把 Zig 函数注册成 Ruby 方法。

> 状态：实验性。当前版本 **0.2.0**，锁定 **Zig 0.16.0** 与 **mruby 4.0.0**；公开 API 在 1.0 前可能变化。

## 特性

- `VM.init` / `VM.deinit`，每个 VM 独立 GC 与异常状态
- `VM.eval` / `VM.evalWithOptions`，支持文件名、语法错误定位
- `Value` 标量转换、字符串拷贝、数组/哈希读写、任意方法调用
- Range/Proc/Time/自定义对象反射、数组/哈希迭代器
- Ruby 异常映射为 `error.RubyException`，通过 `lastError` / `lastErrorClass` / `lastException` / `lastBacktrace` 读取
- 注册 C ABI 或高层 Zig 函数为 Ruby 模块函数、实例方法或类方法
- `RootedValue` / `arenaScope` 显式管理 GC 根
- `VM.loadIrep` 从内存加载 `mrbc` 字节码
- 示例、端到端测试、CI 和 mruby 构建脚本

## 快速开始

当前发布基线：Zig 0.16.0 + mruby 4.0.0。Zig 0.17.1 是下一迁移目标，尚未验证；策略见 [兼容策略](docs/compatibility.md)。

要求：Zig 0.16.0、Ruby 3.3（`.mise.toml` 已固定）、`rake`、C 工具链。

```console
mise install   # 可选：安装固定的 Zig/Ruby
./scripts/build-mruby.sh
./scripts/verify-toolchain.sh
./scripts/check-bindings.sh
./scripts/generate-bindings.sh --check
zig build test
zig build run
```

`scripts/build-mruby.sh` 会把 mruby 4.0.0 下载到 `vendor/mruby`，校验 SHA-256 后构建静态库。也可以使用已有的 mruby 安装：

```console
zig build test -Dmruby-prefix=/path/to/mruby
```

该目录下需要有 `include/` 与 `lib/`，其中包含 mruby 头文件和 `libmruby.a`。

## 在 Zig 中执行 Ruby

```zig
const std = @import("std");
const zruby = @import("zruby");

pub fn main(init: std.process.Init) !void {
    var vm = try zruby.VM.init(init.gpa);
    defer vm.deinit();

    _ = try vm.eval(
        \\def greet(name)
        \\  "Hello, #{name}"
        \\end
    );

    const main_object = try vm.eval("self");
    const greeting = try main_object.call("greet", &.{
        try zruby.Value.fromString(&vm, "Zig"),
    });
    const text = try greeting.toString(init.gpa);
    defer init.gpa.free(text);

    std.debug.print("{s}\n", .{text});
}
```

## 把 Zig 函数暴露给 Ruby

```zig
const zruby = @import("zruby");

fn square(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = mrb orelse unreachable;
    var n: zruby.c.mrb_int = 0;
    _ = zruby.c.mrb_get_args(state, "i", &n);
    return zruby.c.zruby_int_value(state, n * n);
}

// 在 VM 初始化之后：
const zig_module = try vm.defineModule("Zig");
try vm.defineModuleFunction(zig_module, "square", &square, zruby.args.req(1));

const result = try vm.eval("Zig.square(9)"); // 81
```

回调必须是 `callconv(.c)`，第一个参数是 `?*zruby.c.mrb_state`，第二个是 `zruby.c.mrb_value`。不要在回调里让 Zig panic 越过 C 边界；需要报错时用 mruby 的异常 API。

### 高层回调 API

普通 Zig 函数可以免写 `mrb_get_args`，参数与返回值自动转换成 `Value`：

```zig
fn add(vm: *zruby.VM, values: []const zruby.Value) zruby.Error!zruby.Value {
    return zruby.Value.fromInt(vm, try values[0].asInt() + try values[1].asInt());
}

const zig_module = try vm.defineModule("Zig");
try vm.defineModuleCallback(zig_module, "add", &add, zruby.args.req(2));
```

实例方法与类方法分别用 `defineMethodCallback` / `defineClassMethodCallback`。回调返回 Zig error 时会转成 Ruby 异常：`InvalidType` → `TypeError`，`InvalidSource`/`NullPointer` → `ArgumentError`，其余（含 `RubyException`）→ `RuntimeError`/对应类；`RubyException` 的消息取自 `lastError()`。回调注册项在 VM 生命周期内有效，VM 关闭时统一释放。

## 值类型、迭代与诊断

```zig
const range = try zruby.Value.fromRange(&vm, try zruby.Value.fromInt(&vm, 1), try zruby.Value.fromInt(&vm, 5), false);
const proc = try zruby.Value.fromCallback(&vm, &add);

var iter = try hash.hashIterator();
while (try iter.next()) |entry| {
    _ = entry.key;
    _ = entry.value;
}

const exception = vm.lastException(); // ?Value
const backtrace = try vm.lastBacktrace(allocator); // ?[]u8，最多 4096 字节
```

- `isRange` / `isProc` / `isTime` / `isObject` / `className` 提供类型反射。
- `arrayIterator`、`hashIterator`、`hashKeys`、`hashLen` 覆盖常见容器遍历。
- `Value.call` 对 Proc 的 `call`/`[]` 走 `mrb_yield_argv`，避免 mruby tail call 在 C 侧丢失返回值；也可以直接调用 `Value.callProc`。
- `VM.root(value)` 返回 `RootedValue`；`VM.arenaScope()` 返回显式 arena scope，`deinit` 时恢复。
- `eval` 缺省使用 `(eval)` 文件名，让 codegen 生成 debug info，`lastBacktrace` 才能给出位置。

## 错误处理

```zig
const value = vm.eval("raise ArgumentError, \"boom\"") catch |err| {
    std.debug.print("{s}: {s}\n", .{
        vm.lastErrorClass() orelse "unknown",
        vm.lastError() orelse @errorName(err),
    });
    return err;
};
```

`eval` 与 `Value.call` 都用 `mrb_protect_error` 包住可能抛异常的路径。语法错误在解析阶段捕获，消息包含 `文件名:行:列`。

## 字节码

```console
./scripts/build-bytecode.sh   # mrbc -g tests/fixtures/bytecode.rb
```

```zig
const bytecode = @embedFile("bytecode.mrb");
const value = try vm.loadIrep(bytecode);
```

`loadIrepWithOptions` 可带文件名；非法字节码返回 `error.RubyException`，失败后 VM 仍可继续使用。当前没有构建期自动生成 `.mrb` 的步骤，测试夹具已提交在 `tests/fixtures/`。

## 构建选项

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `-Dmruby-prefix` | `vendor/mruby/build/host` | 包含 `include/` 与 `lib/` 的 mruby 前缀 |
| `-Dmruby-boxing` | `word` | `word`、`nan` 或 `none`；必须与 `libmruby.a` 的构建配置一致 |
| `-Doptimize` | `Debug` | Zig 优化模式 |

`zig build` 安装 `zig-out/lib/libzruby.a` 与 `zig-out/bin/zruby-example`。

替代 boxing 构建：

```console
MRUBY_CONFIG="$PWD/build_config/zruby-nan.rb" ./scripts/build-mruby.sh
zig build test -Dmruby-boxing=nan
```

`nan` 配置要求 `MRB_INT64`；`none` 对应 `MRB_NO_BOXING`。`MRB_32BIT` 和未同步宏的配置会编译失败，不会静默错读。

Windows 构建需要 MinGW 工具链；CI 使用 `-Dtarget=x86_64-windows-gnu` 并通过 `build_config/zruby-windows.rb` 构建不含 stdlib-io 的 mruby。MSVC 目标尚未验证。

## API 速览

| 类型/方法 | 作用 |
| --- | --- |
| `VM.init(allocator)` | 打开 mruby VM |
| `VM.eval(source)` | 执行 Ruby 源码 |
| `VM.evalWithOptions(source, .{ .filename = "x.rb" })` | 带文件名执行，便于错误定位 |
| `VM.loadIrep(bytes)` / `loadIrepWithOptions` | 执行 `mrbc` 生成的字节码 |
| `Value.call(name, args)` | 调用 Ruby 方法；Proc 的 `call`/`[]` 自动走 yield 路径 |
| `Value.callProc(args)` | 直接调用 Proc |
| `Value.asInt` / `asFloat` / `toString` / `className` | 取值，字符串会拷贝到 Zig allocator |
| `Value.fromInt` / `fromFloat` / `fromString` / `fromSymbol` / `fromRange` / `fromCallback` | 构造 Ruby 值，返回 `Error!Value` |
| `Value.get` / `set` / `hashGet` / `hashSet` / `hashKeys` / `hashLen` | 数组、哈希读写 |
| `Value.arrayIterator` / `hashIterator` | 容器遍历 |
| `Value.inspect` | 调用 Ruby `inspect` 并拷贝结果 |
| `VM.defineModule` / `defineClass` | 创建 Ruby 模块/类 |
| `VM.defineModuleFunction` / `defineMethod` / `defineClassMethod` | 注册底层 C ABI Zig 回调 |
| `VM.defineModuleCallback` / `defineMethodCallback` / `defineClassMethodCallback` | 注册高层 Zig 回调，自动转换参数与返回值 |
| `VM.lastError` / `lastErrorClass` / `lastException` / `lastBacktrace` | 最近一次 Ruby 异常、异常对象与有界 backtrace |
| `VM.arenaSave` / `arenaRestore` / `arenaScope` / `protect` / `root` | 手动管理 GC 根与 arena scope |

## 限制与安全边界

- 支持 64 位 word boxing、NAN boxing（`MRB_INT64`）和 no-boxing；`MRB_32BIT` 会触发编译期错误。自定义 mruby 配置必须与 `-Dmruby-boxing` 同步修改 `src/c.zig` 与 `src/shim.c` 的 ABI 假设。
- 一个 `VM` 不应跨线程共享。mruby 的异常使用 `setjmp`/`longjmp`，核心的构造、调用、定义与异常检查都放在 `mrb_protect_error` 内。
- `VM.eval` 只接受不含内部 NUL 的源码；内部会复制并补 NUL 哨兵。Ruby 字符串本身仍可包含 NUL，`toString` 会按长度精确拷贝。
- 当前不提供 Fiber、完整类型绑定或自动生成的 C API。数组/哈希操作走 Ruby 方法，适合正确性优先的场景。
- mruby 不是安全沙箱。不要执行不受信任的 Ruby 代码。
- 本地在 macOS arm64 验证；CI 覆盖 Ubuntu 与 Windows（MinGW，`x86_64-windows-gnu`）。Windows MSVC 目标未验证。

## 文档

- [方案设计](docs/design.md)
- [实施计划](docs/plan.md)
- [版本与 API 调研](docs/research.md)
- [已有方案调研](docs/prior-art.md)
- [测试策略与覆盖](docs/testing.md)
- [Zig/mruby 兼容策略](docs/compatibility.md)
- [纯 Zig 构建评估](docs/pure-zig-build.md)
- [变更日志](CHANGELOG.md)

## 许可证

MIT。mruby 自身也使用 MIT 许可证。
