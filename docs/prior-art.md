# 已有 Zig + mruby 方案调研

调研日期：2026-11-13。检查了六个公开仓库的 README、源码、构建脚本、issue 与 PR。结论先行：**手写 C ABI 声明 + 窄 C shim 是可行路线，但“安全封装”必须覆盖完整操作，不能只包住最后一次函数调用**。本次调研直接改掉了 zruby 的几处隐患。

## 1. 对照表

| 仓库 | 时间 | 方法 | 状态/社区 | 关键教训 |
| --- | --- | --- | --- | --- |
| [hfabre/zigretro-core](https://github.com/hfabre/zigretro-core) | 2022 | libretro core；mruby 子模块；复用 dantecatalfamo 绑定 | 2 个 PR，已合并；无 issue | 错误路径、`self`/实例变量、崩溃 backtrace |
| [rguiscard/mrubyOnZig](https://github.com/rguiscard/mrubyOnZig) | 2025-12 起 | `zig translate-c` + `mrbc` 字节码；mruby 3.4 | 无 issue/PR | translate-c 的 opaque/etext hack；构建期字节码 |
| [rguiscard/mrubyOnZap](https://github.com/rguiscard/mrubyOnZap) | 2026-01 起 | mruby 3.4 嵌入 zap web server | 无 issue/PR | 单 VM 与多 worker；每请求对象/GC |
| [rguiscard/mrubyOnHttp.zig](https://github.com/rguiscard/mrubyOnHttp.zig) | 2026-03 起 | mruby 4.0 嵌入 http.zig | 无 issue/PR | Zig 0.16 translate-c 改善但仍手写生成文件 |
| [dantecatalfamo/mruby-zig](https://github.com/dantecatalfamo/mruby-zig) | 2022-2023 | 大规模手写绑定 + `mruby_compat.c`；`addMruby` 调 rake | 5 个 issue/PR；2 个 PR 仍开着 | 构建集成、版本漂移、文档示例失修 |
| [nullstyle/mruby-zig](https://github.com/nullstyle/mruby-zig) | 2026-08 起 | Zig 0.17；手写 `c.zig` + `shim.c`；纯 Zig 构建 mruby 4.0；安全 API/沙箱/worker | 无 issue/PR；README 标注 “VIBE CODE WARNING” | 完整保护、显式 root、跨 VM 检查；自带评审也指出缺口 |

## 2. issue 与 PR 细读

### 2.1 dantecatalfamo/mruby-zig

- [#2 Example in README fails](https://github.com/dantecatalfamo/mruby-zig/issues/2)：README 示例在 Zig 0.9.1 上报 `std.ChildProcess.init` 返回类型错误。维护者回复是 master 分支已随新 Zig 改动，建议用 0.10.0 并拉最新代码。教训：**文档示例必须跟 CI 同版本跑**；仅靠 README 会迅速腐烂。
- [#1 How to create the initialize method for a Ruby class defined in zig?](https://github.com/dantecatalfamo/mruby-zig/issues/1)：用户不知道如何在 Zig 里给 Ruby 类写 `initialize`、设置实例变量并返回实例。维护者后来补了示例。教训：**示例要覆盖类生命周期、实例变量、回调中的 `self`**，不能只演示 `zig_add`。
- [#3 Update zig to v0.11.0, add github actions CI](https://github.com/dantecatalfamo/mruby-zig/pull/3)：更新 Zig、移除 macOS SDK 路径、去掉 `-ffast-math`、加 CI。说明绑定代码对编译器版本极其敏感，需要矩阵化验证。
- [#4 Update mruby to v3.2.0](https://github.com/dantecatalfamo/mruby-zig/pull/4)：2023-05 提交，仍开着。说明**升级 mruby 是持续维护工作**，不是一次性适配。
- [#5 Allow depending on mruby build, support passing args to rake](https://github.com/dantecatalfamo/mruby-zig/pull/5)：给 `addMruby` 增加构建依赖、允许传 rake 参数、支持 `mrbc` 字节码。仍开着。说明**构建集成是独立需求**：消费方需要控制 mruby 配置，而不是只能吃仓库内固定版本。

其 `build.zig` 用 `addSystemCommand` 在 Zig 构建中直接调 `rake`，并把 `CC=zig cc` 传进去。这个方案在 2023 年可用，但把 Ruby、rake、mruby 子模块和 Zig 版本全部耦合进构建；任一漂移都会失败。

### 2.2 hfabre/zigretro-core

- [PR #1](https://github.com/hfabre/zigretro-core/pull/1) “Fix color class, draw rect, get backtrace on crash”：diff 显示作者原先尝试用 `mrb_data_object_alloc` 包装 Zig 颜色对象，最后退回到 Ruby 实例变量；`mrb_iv_get(self, ...)` 一度读不到值，后来从传入的 `mrb_color` 参数读取。还出现 `.integer() catch unreachable`。
- [PR #2](https://github.com/hfabre/zigretro-core/pull/2) “Feature/include mruby”：8 个提交，把 mruby 作为子模块加入，使用 `minirake` 构建，并在 `Engine.init` 里加载 `@embedFile("./mruby_ext.rb")`。

教训：

- 回调里的 `self`、实例变量和参数对象必须用真实测试覆盖；仅看类型签名很容易读错对象。
- `load_file` / `funcall` 的返回值被 `_ =` 丢弃，异常不会传播；崩溃时还需要 backtrace。错误路径是集成的一等公民。
- mruby 子模块 + 本地 `minirake` 构建适合单机 demo，不适合可复现发布。

### 2.3 rguiscard 的三个仓库

三个仓库的 README 是操作手册而非库文档，没有 issue/PR，但代码里的 workaround 很有信息量：

- 都用 `zig translate-c` 生成 `mruby_h.zig`。
- 都需要把翻译出的 `gc: mrb_gc` 改成 `gc: u128` 以绕过 opaque/位域问题；`mrb_gc_arena_restore` 等宏仍会翻译失败。
- 都需要 `export var edata: u8 = 0; export var end: u8 = 0; export var etext: u8 = 0;` 解决 mruby 默认 `mrb_ro_data_p` 在 ELF 上引用 `etext/edata` 的链接问题。
- 都用 `mrbc` 在构建期把 `.rb` 编译成 C 字节码数组，再 `mrb_load_irep` 执行；不在运行时解析源码。
- 都建议 `CC='zig cc' rake test all`，而不是默认 C 编译器。
- `mrubyOnHttp.zig` 的 README 明确提到 Zig 0.16 可能不再需要手工修 `mruby_h.zig`，但仍保留手写生成文件；这说明 translate-c 的修复不等于绑定稳定。

`mrubyOnZap` 把 `mrb_state` 放在全局 `MContext`，zap 配置 `workers = 1`；`mrubyOnHttp.zig` 也在请求处理里直接共享一个 `mrb`。这暴露了**一个 VM 不能被多个线程同时使用**的约束。两者都用 `mrb_load_irep` 的返回值继续 `mrb_funcall`，没有检查异常。

### 2.4 nullstyle/mruby-zig

这是目前最完整的参考实现：

- `src/c.zig` 手写 extern，`src/shim.c` 把宏/内联/结构布局留在 C 侧；与 zruby 的路线一致。
- `build.zig` 完全用 Zig 复刻 mruby 的 presym、host `mrbc`、mrblib/gem 字节码和静态库构建，不依赖 Ruby/rake。
- `docs/safe-api.md` 提出：所有可分配/可抛异常操作返回 error union；`Value`/`Class` 属于创建它的 `Vm`，跨 VM 返回 `ForeignValue`；回调签名从 Zig 参数类型推导；`loadString` 内部分配 root，支持 `arenaScope`/`RootedValue`。
- `docs/maintenance.md` 记录了 mruby 4.0 的 Hash 补丁：在 **非 BigInt** 回退路径中，宽整数按 identity hash，Symbol 分支把 word-boxed symbol 当 fixnum，导致哈希退化。zruby 的默认构建带 `MRB_USE_BIGINT`，实测 `2**40` 键往返正常；如果改成 minimal/非 BigInt，需要重新评估。
- `docs/security-review-2026-09.md` 和 `docs/full-spectrum-codebase-assessment.md` 是仓库自带评审。后者明确指出：**“protected” 操作没有覆盖 interning、参数转换、分配等前置步骤**；`Value` 生命周期/root 仍可能逃逸；gem 选择、Windows 时钟、构建契约也有缺口。README 自己标注 “VIBE CODE WARNING”。

这份“先进实现”的价值不在代码可直接复制，而在于它把问题暴露得很清楚：**安全边界不能只包住 dispatch；源串 NUL、完整保护、root 生命周期、跨 VM 检查、构建可复现性都要单独设计**。它也有过度承诺的风险：沙箱/worker 是独立的大型系统，不能因为 README 写了就默认安全。

## 3. 对 zruby 的直接修正

根据上述教训，本轮改了这些点：

1. **源串 NUL 终止**：`VM.eval` 先用 `dupeZ` 复制并补 `\0`；拒绝含内部 NUL 的源码（`error.InvalidSource`）。mruby 4.0 的词法分析不能假定普通 `[]const u8` 后面有哨兵。
2. **完整保护 `Value.call`**：把 receiver/参数 rooting、`mrb_intern`、`mrb_funcall_argv`、结果 rooting 全部放进 `mrb_protect_error` 的 C 回调体，避免 interning 或 arena 扩容的 longjmp 穿过 Zig 帧。
3. **构造器保护**：`Value.fromInt` / `fromFloat` / `fromString` / `fromSymbol` 改为 `Error!Value`，内部走 `mrb_protect_error`；宽整数/堆浮点/字符串/符号 interning 不再裸调。
4. **类/模块/方法定义保护**：`defineModule` / `defineClass` / `defineModuleFunction` / `defineMethod` / `defineClassMethod` 统一走 `DefineData` + `protectDefine`。
5. **异常检查保护**：`captureException` 的 `mrb_inspect` 也放进 protect；失败时回退到通用消息。
6. **`objectClass()`**：避免 `defineClass(..., null)` 触发 mruby 的 “Object assumed” 警告。
7. **测试补齐**：非 NUL 结尾源码、内部 NUL、Ruby 字符串内 NUL、宽整数 hash key、`defineClass` + 实例方法、错误参数个数、方法内异常，并扩展为 75 个测试（含 5 个 Ruby 套件）；高层回调 API 落地后为 93 个测试，当前 93/93 通过。

## 3.1 已有测试套件对照

- **nullstyle/mruby-zig**：`src/tests.zig` 192 个 Zig 测试，另有 Ruby 集成套件、conformance、fuzz、worker 测试。可迁移的模式：每测试独立 VM、错误类/消息分离、Ruby `assert` 套件、GC/arena 回归、跨 VM 拒绝、回调 arity/type 覆盖。sandbox/worker/gas 测试不在 zruby 范围。
- **dantecatalfamo/mruby-zig**：只有 `refAllDecls` 级检查，没有 mruby 行为断言；这也是其 README 示例和 mruby 升级容易失修的原因之一。
- **hfabre/zigretro-core**：没有测试；PR #1 里的实例变量/`self` 问题只能靠手工试。
- **rguiscard 三仓**：只有 `add(3, 7)` 模板测试和 Zig fuzz 示例，没有 mruby 行为测试。
- zruby 因此把测试重点放在绑定边界和 Ruby 行为两端，详见 [测试策略](testing.md)。

## 4. 明确不采用/暂缓的部分

| 方案 | 决定 | 原因 |
| --- | --- | --- |
| `zig translate-c` 生成绑定 | 不采用 | macOS mach 头文件、位域 opaque、宏/inline 翻译失败；维护者需手工 patch |
| 导出 `etext/edata/end` | **采用（仅 Linux 链接兼容）** | 预构建 `libmruby.a` 默认启用 `MRB_USE_ETEXT_RO_DATA_P`；Zig 链接器不提供这些符号。zruby 仍用 `MRB_NO_DEFAULT_RO_DATA_P` 编译 shim，避免把 mach-o 头文件带进来，但需要在 Zig 侧导出这三个符号。 |
| 在 `zig build` 内调 `rake` | 不采用 | 把 Ruby/rake/mruby 子模块耦合进构建；zruby 用显式 `scripts/build-mruby.sh` |
| 纯 Zig 构建 mruby | 暂缓 | nullstyle 证明可行，但 presym/mrbc/gem 注册/补丁量很大；v0.1 优先绑定正确性 |
| `mrb_load_irep` 字节码 | 暂缓 | 需要 `mrbc` 构建步骤与资源打包；已列入 M4 |
| 沙箱/worker/资源配额 | 不做 | 属于独立安全产品，超出“嵌入调用 Ruby”范围；文档明确不宣称沙箱 |
| 高层回调签名推导 | 暂缓 | nullstyle 的设计很好，但涉及可选参数/关键字/block/异常；先保留原始 `mrb_get_args` 逃生口 |
| mruby Hash 补丁 | 暂不做 | 默认 `MRB_USE_BIGINT` 构建实测宽整数键正常；非 BigInt 配置需单独验证 |

## 5. 结论

1. 走“手写最小 extern + C shim”是对的，但**每个可能分配/抛异常的操作都必须完整落在保护帧内**，包括 interning、构造、定义类、inspect。
2. **源串必须显式 NUL 终止**；不要把 Zig slice 直接交给 mruby 词法器。
3. **版本固定 + CI + 可执行示例**是防止 dantecatalfamo 式腐烂的最低成本；文档示例要进测试或至少进 CI 运行。
4. **构建集成要可配置**：允许用户提供 mruby prefix、mruby 版本、gem 配置；不要把所有东西塞进 `addMruby`。
5. **不要把“嵌入”误称为“沙箱”**。sandbox/worker 是独立工程；zruby 目前只做受信任脚本嵌入。

## 6. 来源

- <https://github.com/hfabre/zigretro-core>，PR #1/#2
- <https://github.com/rguiscard/mrubyOnZig>
- <https://github.com/rguiscard/mrubyOnZap>
- <https://github.com/rguiscard/mrubyOnHttp.zig>
- <https://github.com/dantecatalfamo/mruby-zig>，issue #1/#2，PR #3/#4/#5
- <https://github.com/nullstyle/mruby-zig>，`docs/safe-api.md`、`docs/maintenance.md`、`docs/security-review-2026-09.md`、`docs/full-spectrum-codebase-assessment.md`
