# zruby

在 Zig 0.16 中嵌入 mruby 4.0 的最小绑定。用 Zig 管理 VM、调用 Ruby 代码，也可以把 Zig 函数注册成 Ruby 方法。

> 状态：实验性。当前锁定 **Zig 0.16.0** 与 **mruby 4.0.0**，公开 API 在 1.0 前可能变化。

## 特性

- `VM.init` / `VM.deinit`，每个 VM 独立 GC 与异常状态
- `VM.eval` / `VM.evalWithOptions`，支持文件名、语法错误定位
- `Value` 标量转换、字符串拷贝、数组/哈希读写、任意方法调用
- Ruby 异常映射为 `error.RubyException`，通过 `lastError` / `lastErrorClass` 读取消息
- 注册 C ABI 的 Zig 函数为 Ruby 模块函数、实例方法或类方法
- GC arena 标记与 `protect`
- 示例、端到端测试、CI 和 mruby 构建脚本

## 快速开始

当前发布基线：Zig 0.16.0 + mruby 4.0.0。Zig 0.17.1 是下一迁移目标，尚未验证；策略见 [兼容策略](docs/compatibility.md)。

要求：Zig 0.16.0、Ruby 3.3（`.mise.toml` 已固定）、`rake`、C 工具链。

```console
mise install   # 可选：安装固定的 Zig/Ruby
./scripts/build-mruby.sh
./scripts/verify-toolchain.sh
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

## 构建选项

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `-Dmruby-prefix` | `vendor/mruby/build/host` | 包含 `include/` 与 `lib/` 的 mruby 前缀 |
| `-Doptimize` | `Debug` | Zig 优化模式 |

`zig build` 安装 `zig-out/lib/libzruby.a` 与 `zig-out/bin/zruby-example`。

## API 速览

| 类型/方法 | 作用 |
| --- | --- |
| `VM.init(allocator)` | 打开 mruby VM |
| `VM.eval(source)` | 执行 Ruby 源码 |
| `VM.evalWithOptions(source, .{ .filename = "x.rb" })` | 带文件名执行，便于错误定位 |
| `Value.call(name, args)` | 调用 Ruby 方法 |
| `Value.asInt` / `asFloat` / `toString` | 取值，字符串会拷贝到 Zig allocator |
| `Value.fromInt` / `fromFloat` / `fromString` / `fromSymbol` | 构造 Ruby 值，返回 `Error!Value` |
| `Value.get` / `set` / `hashGet` / `hashSet` | 数组、哈希读写 |
| `Value.inspect` | 调用 Ruby `inspect` 并拷贝结果 |
| `VM.defineModule` / `defineClass` | 创建 Ruby 模块/类 |
| `VM.defineModuleFunction` / `defineMethod` / `defineClassMethod` | 注册 Zig 回调 |
| `VM.lastError` / `lastErrorClass` | 最近一次 Ruby 异常 |
| `VM.arenaSave` / `arenaRestore` / `protect` | 手动管理 GC 根 |

## 限制与安全边界

- 只支持 mruby 默认构建配置（word boxing、64 位 `mrb_int`、bigint/rational/complex/set 等）。自定义 mruby 配置必须同步修改 `src/c.zig` 与 `src/shim.c` 的 ABI 假设。
- 一个 `VM` 不应跨线程共享。mruby 的异常使用 `setjmp`/`longjmp`，核心的构造、调用、定义与异常检查都放在 `mrb_protect_error` 内。
- `VM.eval` 只接受不含内部 NUL 的源码；内部会复制并补 NUL 哨兵。Ruby 字符串本身仍可包含 NUL，`toString` 会按长度精确拷贝。
- 当前不提供字节码加载、Fiber、完整类型绑定或自动生成的 C API。数组/哈希操作走 Ruby 方法，适合正确性优先的场景。
- mruby 不是安全沙箱。不要执行不受信任的 Ruby 代码。
- 已在 macOS arm64 验证；Linux/Windows 尚未在本地验证。

## 文档

- [方案设计](docs/design.md)
- [实施计划](docs/plan.md)
- [版本与 API 调研](docs/research.md)
- [已有方案调研](docs/prior-art.md)
- [测试策略与覆盖](docs/testing.md)
- [Zig/mruby 兼容策略](docs/compatibility.md)
- [变更日志](CHANGELOG.md)

## 许可证

MIT。mruby 自身也使用 MIT 许可证。
