# 版本与 API 调研

调研日期：2026-11-13。目标是确定一个可落地的“Zig 调用 Ruby”绑定基线，而不是罗列全部 API。

## 1. 版本基线

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| Zig | 0.16.0（本项目基线）；最新稳定 0.17.1 | 0.16.0 于 2026-04 发布，本机验证通过；0.17.1 于 2026-11-02 发布，尚未在本仓库验证，见 [兼容策略](compatibility.md) |
| mruby | 4.0.0 | 2026-04-20 发布；本机构建成功；4.1 仍是 rc |

> 本文件其余部分记录 2026-11-13 以 0.16.0/4.0.0 为基线的调研结果；当前 release 仍以该组合为准。Zig 0.17.1 的迁移属于下一版本，不应把本文的 API 结论直接当成 0.17 已验证事实。

mruby 4.0.0 的关键变化来自官方 `NEWS.md`：

- C API：`mrb_alloca()` 改名为 `mrb_temp_alloc()`；`mruby/ext/io.h` 改名为 `mruby/io.h`。
- `mrb_open()` 在初始化失败时返回带 `exc` 的 `mrb_state`，可用 `MRB_OPEN_FAILURE()` 检查。
- 新增 `MRB_ENSURE()`、`mrb_gc_add_region()`、`mrb_class_outer()` 等。
- 默认启用 presym；`MRB_NO_PRESYM` 被移除。
- 语言层新增 `case/in` 模式匹配；内置类使用只读方法表，降低堆占用。
- 构建层新增 amalgamation（`rake amalgam`）与 `mruby-task`。

Zig 0.16.0 中与本项目直接相关的点：

- 程序入口从 `pub fn main() !void` 变为 `pub fn main(init: std.process.Init) !void`。`Init` 提供 `io`、`gpa`、`arena`、`minimal.args`。
- `std.Io` 成为显式 I/O 接口；读文件使用 `std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(n))`。
- Build API 使用模块图：`b.addModule` / `b.createModule`，可执行文件与库通过 `root_module` 接收 target/optimize/imports。
- 库产物用 `b.addLibrary(.{ .name, .root_module, .linkage = .static })`；C 源文件用 `addCSourceFile`，头文件/库路径与宏用 `addIncludePath`、`addLibraryPath`、`linkSystemLibrary`、`addCMacro`。
- 绝对路径的 `LazyPath` 使用 `.cwd_relative`，相对路径使用 `b.path`。

## 2. mruby C API 形状

以下签名来自 mruby 4.0.0 头文件，并在本机通过链接验证：

```c
mrb_state *mrb_open(void);
void mrb_close(mrb_state *mrb);

mrb_value mrb_load_nstring_cxt(mrb_state *mrb, const char *s, size_t len,
                               mrb_ccontext *cxt);
struct mrb_parser_state *mrb_parse_nstring(mrb_state *mrb, const char *s,
                                           size_t len, mrb_ccontext *cxt);
mrb_value mrb_load_exec(mrb_state *mrb, struct mrb_parser_state *p,
                        mrb_ccontext *cxt);

mrb_value mrb_protect_error(mrb_state *mrb,
                            mrb_protect_error_func *body,
                            void *userdata, mrb_bool *error);

mrb_value mrb_funcall_argv(mrb_state *mrb, mrb_value val, mrb_sym name,
                           mrb_int argc, const mrb_value *argv);
mrb_sym mrb_intern_cstr(mrb_state *mrb, const char *s);

void mrb_define_module_function(mrb_state *mrb, struct RClass *cla,
                                const char *name, mrb_func_t fun,
                                mrb_aspec aspec);
mrb_int mrb_get_args(mrb_state *mrb, const char *format, ...);
```

`mrb_func_t` 是：

```c
typedef mrb_value (*mrb_func_t)(mrb_state *mrb, mrb_value self);
```

### 2.1 `mrb_value` 与 ABI

mruby 默认使用 word boxing：

```c
typedef struct mrb_value { uintptr_t w; } mrb_value;
```

本机（macOS arm64、mruby 4.0.0 默认构建）测得：

```text
sizeof(mrb_value)=8  align=8
sizeof(mrb_int)=8    sizeof(mrb_float)=8
sizeof(mrb_state)=18856
```

因此绑定把 `mrb_value` 声明为 `extern struct { w: usize }`，并在 C 侧用 `_Static_assert` 锁定：

- `sizeof(mrb_value) == sizeof(uintptr_t)`
- `sizeof(mrb_int) == 8`
- `sizeof(mrb_float) == 8`

这不覆盖 mruby 的 NAN boxing 或 `MRB_NO_BOXING` 构建；这些配置需要不同的绑定。当前选择是“明确锁定默认配置”，而不是假装兼容全部 ABI。

### 2.2 异常与语法错误

`mrb_load_nstring_cxt` 和 `mrb_load_exec` 在语法错误时返回 `mrb_undef_value()`，并可能把异常放到 `mrb->exc`。实际测试发现：

- `raise` 与 `1 / 0` 的异常不一定会让 `mrb_protect_error` 的 `error` 置位；必须在调用后同时检查 `mrb->exc`。
- 直接 `mrb_load_nstring_cxt` 的语法错误默认打印到 stderr，异常消息只包含 `line N`，不含文件名。
- 先用 `mrb_parse_nstring` 解析，再检查 `parser->nerr` 与 `error_buffer`，可以拿到行、列和消息；随后调用 `mrb_load_exec` 执行。这样可以在 Zig 侧格式化为 `filename:line:column: message`。
- `mrb_ccontext` 的 `capture_errors = TRUE` 会阻止解析器直接打印错误，并把错误留在 parser 的 `error_buffer`。

这三点决定了 `VM.eval` 的实现路径：解析 -> 检查 `nerr` -> `mrb_protect_error` 包住 `mrb_load_exec` -> 同时检查 error 标志与 `mrb->exc`。

### 2.3 回调与参数

`mrb_get_args` 是可变参数函数，常见格式：

- `"i"`：`mrb_int *`
- `"z"`：`const char **`（NUL 结尾）
- `"S"`：`mrb_value *`
- `"o"`：任意对象

从 Zig 调用可变参数 C 函数可行；回调必须使用 `callconv(.c)`。回调内不要跨越 C 边界传播 Zig panic，错误应通过 `mrb_raise` / `mrb_exc_raise` 转为 Ruby 异常（当前示例只演示成功路径）。

## 3. Zig 侧绑定策略的实测结论

### 3.1 `@cImport` 路线

最初的方案是 `@cImport({ @cInclude("mruby.h"); ... })`。在 Zig 0.16 + macOS 上失败：

- `mruby/value.h` 在 `__APPLE__` 下包含 `<mach-o/getsect.h>`，translate-c 对 `mach_msg_*` 的透明联合/静态断言生成 14 个编译错误。
- mruby 的 `RBasic`/`mrb_state` 含位域，translate-c 会把部分结构降级为 `opaque`；`mrb_type`、`mrb_integer` 等 static inline 函数被降级为 `extern`，但库中不一定有对应符号。
- 即使能用 `MRB_NO_DEFAULT_RO_DATA_P` 绕开 mach 头，位域和 inline 函数仍是长期维护风险。

### 3.2 手写声明 + 小型 C shim（采用）

最终结构：

- `src/c.zig`：手写 `mrb_value`、`mrb_state` 等类型与约 30 个 `extern` 函数声明。
- `src/shim.c`：只包装无法从 Zig 直接使用的 inline 函数/宏，并用 `_Static_assert` 校验 ABI 假设。
- 直接调用 mruby 导出的 `mrb_*` 符号；回调继续使用 C ABI 的 `mrb_func_t`。

优点：

- 不依赖 translate-c 对 mruby 头文件的处理，macOS 上可构建。
- 类型面更小，错误信息更直接。
- 仍由 mruby 官方静态库承载 VM、GC、编译器。

代价：

- 需要手工维护声明；升级 mruby 时要对照头文件检查。
- 只支持 word boxing 默认配置；自定义 ABI 需要重做绑定。

### 3.3 备选方案

1. **全部 API 走 C shim**：最稳，但要为每个函数写包装，且 Zig 侧回调仍需 `mrb_value` 表示。
2. **生成绑定**：用 `zig translate-c` 生成后人工修补，或写脚本从头文件提取；适合 API 覆盖面扩大后。
3. **直接用现有 Zig Ruby 绑定**：可作为后续对比，但版本、构建系统和 mruby 配置不一定匹配本项目目标。

## 4. 构建与兼容性

- mruby 4.0.0 release tarball 自带生成的 parser 源文件，`rake all` 不需要 bison/gperf；只需要 Ruby 2.5+、C 工具链、make/ar。
- 默认 `build_config/default.rb` 包含 `mruby-compiler` 等 gem，`mrb_parse_nstring` / `mrb_load_exec` 可用。
- 静态库产物：`vendor/mruby/build/host/lib/libmruby.a`；头文件：`vendor/mruby/build/host/include`。
- 默认构建的 C 宏（`MRB_USE_SET`、`MRB_USE_BIGINT`、`MRB_USE_RATIONAL`、`MRB_USE_COMPLEX`、`MRB_USE_DEBUG_HOOK` 等）在 `build.zig` 中同步传给 shim；ABI 相关的选项必须与库一致。
- 本机验证：`zig build test` 通过 89/89（Debug 与 ReleaseSafe）；`zig build run` 输出嵌入 mruby 4.0、`Zig.square(7) = 49`、Ruby 方法调用结果。

## 5. 结论

以“手写最小 C API 绑定 + 必要 shim”作为 v0.1 基线，锁定 Zig 0.16.0 与 mruby 4.0.0 默认配置。这个组合在本机完成了端到端验证，且把最危险的 ABI 假设收敛到三个静态断言和少量构造函数/谓词包装中。后续若要支持 NAN boxing、32 位 `mrb_int`、Windows 或更大 API 覆盖面，应优先改为代码生成绑定，而不是继续手工扩展。

## 6. 来源

- Zig 0.16.0 release notes: <https://ziglang.org/download/0.16.0/release-notes.html>
- mruby downloads / 4.0.0: <https://mruby.org/downloads/>
- mruby 4.0.0 NEWS: <https://github.com/mruby/mruby/blob/4.0.0/NEWS.md>
- mruby compile guide: <https://github.com/mruby/mruby/blob/4.0.0/doc/guides/compile.md>
- 本机头文件与构建产物：`vendor/mruby/include`、`vendor/mruby/build/host`（mruby 4.0.0）
- 已有 Zig + mruby 方案对照：见 [prior-art.md](prior-art.md)
