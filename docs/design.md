# zruby 方案设计

## 1. 目标

让 Zig 程序以最小摩擦嵌入 mruby：

- Zig 创建/销毁 VM，执行 Ruby 源码。
- Zig 调用 Ruby 方法，读取标量、字符串、数组、哈希。
- Ruby 调用 Zig 注册的函数。
- Ruby 异常与语法错误能变成可读的 Zig 错误，不把 longjmp 漏到 Zig 调用栈。
- 构建过程可复现，不要求手写 C 代码。

## 2. 非目标

- 不做 Ruby 安全沙箱。
- 不覆盖 mruby 全部 C API。
- 不绑定 CRuby（只有 mruby）。
- 不在 v0.1 支持 Fiber、`mrbc` 字节码、GC 压缩、跨线程 VM。
- 不承诺兼容所有 mruby 构建配置；只承诺默认 word-boxing 配置。

## 3. 版本基线

| 组件 | 版本 |
| --- | --- |
| Zig | 0.16.0 |
| mruby | 4.0.0 |

版本写死在 `.mise.toml`、`build.zig.zon` 的 `minimum_zig_version`、CI 与构建脚本中。升级策略、支持分层和 release 检查清单见 [兼容策略](compatibility.md)。升级时要重新跑 ABI 断言和测试。

## 4. 总体架构

```text
┌──────────────────────────────────────────────┐
│ Zig 应用 / 测试 / 示例                        │
│   VM, Value, args, Error                     │
└──────────────────────┬───────────────────────┘
                       │ 直接调用
┌──────────────────────▼───────────────────────┐
│ src/zruby.zig                                │
│   VM 生命周期、eval、call、错误捕获、GC 根    │
└───────────────┬──────────────────────┬───────┘
                │                      │
┌───────────────▼────────────┐  ┌──────▼──────────────┐
│ src/c.zig                  │  │ src/shim.c          │
│ 手写 extern 声明            │  │ inline/宏/ABI 断言   │
│ mrb_value = struct { w }   │  │ arena/save、构造器   │
└───────────────┬────────────┘  └──────┬──────────────┘
                │                      │
                └──────────┬───────────┘
                           │ 链接
                 ┌─────────▼──────────┐
                 │ libmruby.a (4.0.0) │
                 │ mruby VM / GC /    │
                 │ parser / compiler  │
                 └────────────────────┘
```

模块职责：

- `src/zruby.zig`：唯一的公开入口。所有 Ruby 对象以 `Value` 表示，所有可能抛异常的操作返回 `Error!T`。
- `src/c.zig`：C ABI 的最小声明面。只声明实际用到的函数与类型，避免把 mruby 头文件的平台依赖带进 Zig 编译。
- `src/shim.c`：mruby 的 inline 函数和宏不能从 Zig 直接调用，因此在 C 侧包一层；同时用 `_Static_assert` 锁定 `mrb_value`、`mrb_int`、`mrb_float` 的大小。
- `build.zig`：把 mruby 的 include/lib 路径、默认 C 宏、shim.c 注入模块；产出静态库、测试和示例。

## 5. 关键设计决策

### 5.1 为什么手写绑定，而不是 `@cImport`

实测 Zig 0.16 的 `@cImport` 在 macOS 上无法直接吃下 mruby 4.0 头文件：

- `mruby/value.h` 在 Apple 平台包含 `mach-o/getsect.h`，translate-c 对 mach 结构体的静态断言报错。
- `RBasic`、`mrb_state` 等含位域，translate-c 会降级成 `opaque`。
- `mrb_type`、`mrb_integer` 等是 static inline；translate-c 可能声明成 `extern`，但静态库里没有对应符号。

手写声明把依赖收敛到“实际用到的符号 + 一个 8 字节值结构”，可控性更高。shim 只负责 Zig 无法表达的部分，而不是把所有 API 再包一遍。

### 5.2 ABI 契约

当前契约：

```c
typedef struct mrb_value { uintptr_t w; } mrb_value;
typedef int64_t mrb_int;
typedef double mrb_float;
```

对应 Zig：

```zig
pub const mrb_value = extern struct { w: usize };
pub const mrb_int = i64;
pub const mrb_float = f64;
```

`src/shim.c` 的静态断言在编译期检查；`tests/all.zig` 再通过 `zruby_value_size()` 做运行期防线。

该契约只对 mruby 默认构建成立。若使用 `MRB_NAN_BOXING`、`MRB_NO_BOXING`、`MRB_INT32` 或 32 位目标，必须调整绑定。文档和构建选项不假装自动适配这些配置。

### 5.3 值的所有权与 GC

mruby 的 GC 根集合包含 VM 栈和 GC arena。`zruby` 的规则：

- `eval` 返回的 `Value` 在返回前调用 `mrb_gc_protect`，因此跨调用有效。
- `call` 的接收者与参数在调用前 protect；返回值同样 protect。
- `Value.fromString` / `fromInt` / `fromFloat` / `fromSymbol` 返回 `Error!Value`，内部走保护帧；构造出的值只在当前 arena 中有效，长期保存需调用 `VM.protect`。
- `VM.arenaSave()` / `arenaRestore()` 暴露给高级用户，用于在批量创建临时对象后回收 arena 槽位。
- `fromString` 使用 `mrb_str_new`，支持含 NUL 的字节串；`toString` 按 `RSTRING_PTR` + `RSTRING_LEN` 精确拷贝，不经过 C 字符串截断。

不做自动引用计数：mruby 本身用 tracing GC，引入第二套所有权会制造悬挂引用。代价是用户必须理解 arena/protect；这一点在 README 中明确写出。

### 5.4 异常与错误模型

Zig 的 error union 不携带负载，所以采用：

```zig
pub const Error = error{ OutOfMemory, VmInitFailed, RubyException, InvalidType, NullPointer };
```

- `VM.eval` / `Value.call` 返回 `Error!T`。
- 具体 Ruby 异常消息放在 `VM.lastError()`，类名放在 `VM.lastErrorClass()`。
- 每次新的 eval/call 会清空上一次错误；错误消息由 VM 的 allocator 复制，生命周期到下一次操作或 `deinit`。

异常路径：

1. `eval` 先 `mrb_parse_nstring`，检查 `parser->nerr`。语法错误直接格式化为 `filename:line:column: message`，不进入 VM。
2. 源串先复制成 NUL 结尾的 buffer，并拒绝内部 NUL；`mrb_ccontext_new`、文件名设置、`mrb_parse_nstring` 放在同一个保护帧里。
3. 解析成功后，另一次 `mrb_protect_error` 包住 `mrb_load_exec`；返回后同时检查 protect 的 error 标志和 `mrb->exc`。
4. `Value.call` 把 receiver/参数 rooting、`mrb_intern`、`mrb_funcall_argv`、结果 rooting 全部放进同一个 C 保护帧。
5. `Value.from*` 与 `defineModule`/`defineClass`/`defineMethod` 等分配型操作也走保护帧；`captureException` 的 `mrb_inspect` 同样受保护。
5. 捕获异常时调用 `mrb_inspect` 获取可读文本，再清理 `exc`。

不在 Zig 回调里让 panic 穿过 C 边界。回调需要报错时应使用 mruby 的 `mrb_raise` / `mrb_exc_raise`；当前 v0.1 的示例只覆盖成功路径，异常回调是下一阶段任务。

### 5.5 方法注册

`VM.defineModule` / `defineClass` 返回 `*c.RClass`。`defineModuleFunction` / `defineMethod` / `defineClassMethod` 接受：

```zig
fn (mrb: ?*c.mrb_state, self: c.mrb_value) callconv(.c) c.mrb_value
```

这正是 mruby 的 `mrb_func_t`。参数通过 `mrb_get_args` 读取，返回值通过 `zruby_int_value` / `zruby_bool_value` 等构造。`args.req/opt/rest/none` 镜像 `MRB_ARGS_*`。

不提供“自动把任意 Zig 函数签名映射为 Ruby 方法”的高层宏，因为：

- 需要处理可变参数、关键字参数、块、异常；
- 任何隐藏的分配/保护都可能破坏 GC 语义；
- v0.1 优先把底层契约做对，高层封装留到 v0.2。

### 5.6 构建集成

`build.zig`：

- `-Dmruby-prefix` 指定包含 `include/` 与 `lib/` 的前缀，默认 `vendor/mruby/build/host`。
- 为模块添加 mruby include/lib、链接 `mruby`；Linux 额外链接 `m`。
- 注入 mruby 默认构建宏，编译 `src/shim.c`。
- 生成 `libzruby.a`、`zruby-example`、测试可执行文件。
- 相对路径用 `b.path`，绝对路径用 `LazyPath{ .cwd_relative }`。

`scripts/build-mruby.sh`：

- 下载 mruby 4.0.0 release tarball；
- 解压到 `vendor/mruby`；
- `rake all` 生成 `libmruby.a` 与头文件；
- 允许 `MRUBY_VERSION`、`MRUBY_CONFIG` 覆盖。

不把 mruby 源码提交进仓库；`vendor/` 在 `.gitignore` 中。这样仓库只包含绑定与构建逻辑，升级 mruby 只需改版本号。

## 6. 公开 API

```zig
pub const VM = struct {
    pub fn init(allocator: std.mem.Allocator) Error!VM;
    pub fn deinit(self: *VM) void;
    pub fn eval(self: *VM, source: []const u8) Error!Value;
    pub fn evalWithOptions(self: *VM, source: []const u8, options: EvalOptions) Error!Value;
    pub fn lastError(self: *const VM) ?[]const u8;
    pub fn lastErrorClass(self: *const VM) ?[]const u8;
    pub fn arenaSave(self: *VM) ArenaMark;
    pub fn arenaRestore(self: *VM, mark: ArenaMark) void;
    pub fn protect(self: *VM, value: Value) void;
    pub fn defineModule(self: *VM, name: []const u8) Error!*c.RClass;
    pub fn defineClass(self: *VM, name: []const u8, super: ?*c.RClass) Error!*c.RClass;
    pub fn defineModuleFunction(...) Error!void;
    pub fn defineMethod(...) Error!void;
    pub fn defineClassMethod(...) Error!void;
};

pub const Value = struct {
    pub fn fromInt/fromFloat/fromString/fromSymbol(...) Error!Value;
    pub fn call(self: Value, method: []const u8, args: []const Value) Error!Value;
    pub fn get/set/hashGet/hashSet/arrayLen(...) Error!...
    pub fn asInt/asFloat/toString/inspect(...) Error!...
    pub fn isNil/isTrue/isFalse/isInteger/isFloat/isString/isArray/isHash/isSymbol/isException/truthy(...) bool;
};
```

公开 `c` 命名空间是为了让高级用户直接使用 `mrb_get_args`、`mrb_func_t` 等。这是有意的“逃生口”，不承诺稳定。

### 6.1 与已有方案的关系

详见 [已有方案调研](prior-art.md)。三点直接影响本设计：

- 手写 extern + C shim 的路线与 nullstyle/mruby-zig 一致；它的自带评审也指出“只包住最后一次 dispatch 不够”，因此 zruby 把 interning、构造、类定义、inspect 也纳入保护帧。
- rguiscard 的 translate-c 方案需要把 `mrb_gc` 改成 `u128`、导出 `etext/edata/end`。zruby 手写声明绕开 `mrb_gc`/mach-o 问题；`etext/edata/end` 仍必须导出，因为 Linux 默认的预构建 `libmruby.a` 引用了它们。
- dantecatalfamo 的 issue/PR 表明构建集成和文档示例会随编译器/mruby 版本腐烂；zruby 固定版本、把 mruby 构建放在显式脚本里，并用测试覆盖 README 中的核心用法。

## 7. 测试与验证

已落地：

- 75 个测试（含 5 个 Ruby 集成套件）覆盖 ABI、VM 生命周期、求值/诊断、值语义、回调、GC/arena、多线程 VM、类/模块定义、数组/哈希、NUL/UTF-8、跨 VM 拒绝等边界。测试矩阵见 [测试策略](testing.md)。
- `zig build test` 通过 75/75；`zig build test -Doptimize=ReleaseSafe` 同样通过。
- `zig build run` 端到端运行 `examples/hello.rb`，验证 `Zig.square(7)` 与 Ruby 方法调用。

后续补充：

- 回调抛 Ruby 异常、GC 压力、arena 回收、错误消息非泄漏。
- Linux/Windows CI 的真实运行结果。
- 与自定义 mruby 配置的负向测试（应明确失败，而不是静默错读）。

## 8. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| mruby ABI 配置不匹配 | 值布局错误、崩溃 | 默认配置锁定 + 静态断言 + 文档明确 |
| longjmp 跨 Zig 栈 | 未定义行为 | 核心分配/调用/定义路径都在 `mrb_protect_error` 内；回调禁止 panic |
| GC 回收未保护值 | 悬空 `mrb_value` | eval/call 返回前 protect；文档要求长期值手动 protect |
| `@cImport` 不可用 | 无法编译 | 手写声明 + C shim；已在 macOS 验证 |
| mruby 4.0 仍是新版本 | API 变动 | 版本固定；升级时重跑测试与 ABI 断言 |
| 仅 macOS 验证 | 其他平台未知 | CI 矩阵；README 标注未验证平台 |

## 9. 安全边界

- `VM.eval` 执行的是完整 Ruby 代码，不是受限表达式。mruby 默认 gem 可能包含文件、socket 等能力（取决于构建配置）。
- 不要对不受信任输入调用 `eval`；需要沙箱时，应在 mruby 构建配置中移除危险 gem，并在进程/权限层隔离。
- `Value.toString` / `inspect` 会按 Ruby 语义分配内存；异常消息也由 VM allocator 持有，注意生命周期。
- 回调参数指针只在回调执行期间有效，不能保存 `mrb_value` 的裸指针到 Ruby 栈。

## 10. 后续演进

1. **v0.2**：高层回调注册（自动参数转换、异常安全）、更多值类型（Symbol/Range/Proc）、哈希/数组直接 API。
2. **v0.3**：`mrbc` 字节码加载、`mrb_load_irep`、资源打包。
3. **v0.4**：绑定生成器，从 mruby 头文件生成 `c.zig`，支持多种 boxing 配置。
4. **v0.5**：评估纯 Zig 的 mruby 构建（presym、host `mrbc`、gem registry），去掉 Ruby/rake 构建依赖。
5. **v1.0**：稳定 API、Linux/Windows CI、性能基准、文档站。
