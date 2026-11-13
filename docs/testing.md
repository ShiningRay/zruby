# 测试策略与覆盖

当前 `tests/all.zig` 是测试根，按主题拆成多个文件；每个测试使用独立 VM 和 `std.testing.allocator`，错误消息、字符串拷贝与 VM 资源泄漏由测试分配器兜底。共 **93 个测试声明：88 个 Zig 测试 + 5 个 Ruby 集成套件**。

## 1. 测试分层

| 层 | 文件 | 覆盖内容 |
| --- | --- | --- |
| 基础边界 | `tests/all.zig` | ABI 尺寸、VM 启停、基础 eval、数组/哈希、Zig 回调、异常、NUL、连续 eval |
| 值语义 | `tests/values.zig` | 类型谓词、truthiness、整数边界、NaN/Inf、字符串字节、symbol、inspect、数组/哈希、`Value.call` 返回值 |
| 生命周期 | `tests/lifecycle.zig` | 多 VM 隔离、objectClass、重复定义、错误常量、长源码、GC、arena、线程 |
| 错误路径 | `tests/errors.zig` | 语法错误定位、运行时异常类、rescue、嵌套异常、参数错误、冻结容器、跨 VM、诊断清理 |
| 回调 | `tests/callbacks.zig` | 模块函数、实例/类方法、`i/f/b/n/z/S/o` 参数、可选/rest、返回值、类型/arity 错误、重定义 |
| Ruby 套件 | `tests/ruby_suites.zig` + `tests/ruby/*.rb` | 核心语言、数值、集合、异常控制流、默认 gem 冒烟 |

## 2. 覆盖矩阵

### VM 与构建

- `mrb_value` 指针宽度 ABI 断言；mruby 静态库链接。
- `VM.init` / `deinit`；多个 VM 的定义隔离；两个 VM 在不同线程各自运行。
- `objectClass`；`defineClass` 显式父类；重复 `defineModule`；非 class/module 常量触发 `RubyException` 而非崩溃。
- Clean-room 构建、Debug/ReleaseSafe、示例运行。

### 求值与诊断

- 整数、浮点、字符串、Unicode、CRLF、多行、空源码、纯注释。
- `__FILE__` / `__LINE__` 与 `evalWithOptions` 文件名。
- 大于 4 KiB 的源码走堆路径；非 NUL 结尾 slice；内部 NUL 拒绝。
- 语法错误文件名/行号/列；`SyntaxError` 类。
- `RuntimeError`、`ArgumentError`、`TypeError`、`ZeroDivisionError`、`NoMethodError`、`LocalJumpError`。
- Ruby 内部 rescue/ensure 不向 Zig 冒泡；嵌套调用异常；连续错误覆盖；成功操作清空诊断。
- `lastException` 保留异常对象；`lastBacktrace` 返回不超过 4096 字节的 backtrace；语法错误无异常对象。

### 值

- `is*` 全类型谓词；Ruby truthiness（0、空字符串为真）。
- `i64` 最小/最大、宽整数、fixnum 边界。
- 浮点普通值、正负无穷、NaN。
- 字符串空值、UTF-8、emoji、内部 NUL、无效 UTF-8 字节、7 KB 长串。
- Symbol 构造、inspect、哈希键。
- `inspect`：nil/true/false/int/float/string/symbol/array/hash/exception。
- 数组负索引、越界、赋值扩展、长度；哈希字符串/symbol/宽整数键、缺失键、nil 值、增删。
- `Value.call` 的 nil/true/false/string/float/运算符/超过 8 个参数。
- 异常对象 `isException` + `inspect`。
- Range 构造、inspect、`to_a`；跨 VM 端点拒绝。
- 回调转为 Ruby Proc；Ruby 侧 `Proc#call` 与 Zig 侧 `Value.call("call")`（内部走 yield 路径）。
- Time/custom object 反射与 `className`。
- 数组/哈希迭代器、`hashKeys`、`hashLen`。
- `RootedValue` 跨 GC、`arenaScope` 恢复。

### 回调

- `defineModuleFunction` / `defineMethod` / `defineClassMethod`。
- `mrb_get_args` 格式：`i`（int）、`f`（float）、`b`（bool）、`n`（symbol）、`z`（C string）、`S`（String value）、`o`（任意对象）、`a`（array + length）、`H`（hash）、`*`（rest）。
- `args.none/req/opt/rest` 与 optional `i|i`。
- 返回值：整数、浮点、布尔、字符串、nil、对象、self。
- 错误 arity/type 变成 `RubyException`；回调错误后 VM 仍可继续使用。
- 方法与模块函数重定义；通过 `Value.call` 直接调用模块/类/实例方法。
- 高层回调 API：模块函数/实例方法/类方法自动参数与返回值；超过 16 个参数走堆路径；Zig error → Ruby 异常（`InvalidType`/`RubyException` 类映射）；跨 VM 返回值拒绝；回调失败后 VM 可继续使用。

### GC 与 arena

- 返回的 value 在 `protect` 后跨 20 轮 `GC.start` 仍可读。
- `arenaSave`/`arenaRestore` 后已 protect 的值仍可读。
- 250 次连续 eval；大规模数组（1000）/哈希（200）访问。
- `std.testing.allocator` 检测 Zig 侧错误消息/字符串拷贝泄漏。

### 字节码

- `@embedFile` 加载 `tests/fixtures/bytecode.mrb`，执行顶层返回值与方法调用。
- `loadIrepWithOptions` 文件名、重复加载 20 次、空字节码与非法字节码。
- 非法字节码失败后 VM 仍可继续 eval。

## 3. Ruby 套件

| 文件 | 内容 |
| --- | --- |
| `tests/ruby/core_language.rb` | 字面量、运算、字符串/符号、数组/哈希/range、类/继承/模块、block/proc/lambda、rescue/ensure、Struct/Set/Fiber/eval/Time/Random/GC |
| `tests/ruby/numerics.rb` | 整数边界、宽整数、BigInt、浮点特殊值、Math、位运算、转换、sprintf |
| `tests/ruby/collections.rb` | 数组/哈希/range/string/Set 的常用方法与边界 |
| `tests/ruby/exceptions.rb` | 自定义异常、retry、ensure、显式 re-raise、嵌套 rescue、标准异常类、catch/throw |
| `tests/ruby/stdlib.rb` | Struct、Set、Fiber、Enumerator、eval、Time、Random、pack、JSON 条件测试、GC |

Ruby 套件用 `raise` 断言；失败信息经 `lastErrorClass`/`lastError` 回传到 Zig。mruby 4.0 的 bare `raise` 不会自动 re-raise 当前异常，因此套件用 `raise original` 明确表达。

## 4. 已有测试套件对照

- **nullstyle/mruby-zig**：192 个 Zig 测试 + Ruby 集成套件 + conformance/fuzz/worker 测试。本仓库采纳了“按 VM 隔离、错误类/消息分离、Ruby 断言套件、GC/arena 回归、跨 VM 拒绝、回调 arity/type”这些模式；sandbox/worker/gas 测试不在 zruby 范围。
- **dantecatalfamo/mruby-zig**：只有 `refAllDecls` 级别检查，没有真实 mruby 行为测试；这正是其 issue #2 文档失修的原因之一。
- **hfabre/zigretro-core**：没有测试；PR #1 的实例变量/self 问题只能靠手工试。
- **rguiscard 三仓**：只有 `add(3,7)` 之类模板测试和 fuzz 示例，没有 mruby 行为断言。
- zruby 的测试重点因此放在“绑定边界”和“Ruby 行为”两端，而不是复刻基础设施测试。

## 5. 运行

```console
zig build test
zig build test -Doptimize=ReleaseSafe
zig build run
```

干净环境：

```console
./scripts/build-mruby.sh
zig build test
zig build run
```

当前结果：**93/93** 通过（Debug 与 ReleaseSafe）；干净目录同步后同样通过。

## 6. 尚未覆盖

- 从 Zig 向 Ruby 方法传 block / proc（API 尚未提供 block 参数）。
- Fiber 的 Zig 侧调度、非局部 return。
- `mrbc` 字节码加载与 `mrb_load_irep`。
- 沙箱、资源配额、worker 进程、信号/ORPHAN 行为。
- Windows/Linux 真机运行（CI 配置存在，远程尚未执行）。
- 上游 mruby ISO conformance 全量套件；目前是自建 Ruby 冒烟套件。
- OOM 故障注入、长期 fuzz、性能基准。
