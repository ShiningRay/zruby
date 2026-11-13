# zruby 实施计划

## 1. 目标

交付一个可构建、可测试、可阅读的 Zig 0.16 + mruby 4.0 绑定仓库。首版目标是“在 Zig 中可靠调用 Ruby”，同时提供最小的 Ruby -> Zig 回调能力。

## 2. 范围

### 做

- `VM` 生命周期、`eval`、`Value.call`、标量/字符串/数组/哈希访问。
- Ruby 异常与语法错误 -> Zig error + 可读消息。
- Zig 函数注册为 Ruby 模块函数/方法。
- mruby 4.0.0 构建脚本、静态库产物、示例、CI。
- 方案、调研、计划文档。

### 不做

- CRuby 绑定、完整 mruby C API、Fiber、字节码加载。
- 自动生成的绑定、跨平台 ABI 全覆盖。
- Ruby 沙箱、安全隔离、生产级性能优化。

## 3. 里程碑

| 阶段 | 状态 | 交付物 | 验收 |
| --- | --- | --- | --- |
| M0 调研 | 已完成 | 版本/API/构建结论 | Zig 0.16.0 与 mruby 4.0.0 本机验证 |
| M1 核心绑定 | 已完成 | `src/c.zig`、`src/shim.c`、`src/zruby.zig` | `zig build test` 通过 |
| M2 可用性 | 已完成 | 示例、README、构建脚本、CI | `zig build run` 输出正确 |
| M3 发布准备 | 已完成 | 版本号、变更日志、Git tag、远程仓库 | 干净 clone 后按 README 可复现 |
| M4 扩展 | 进行中 | 高层回调、更多类型、字节码 | 新增测试与文档 |

## 4. 已完成的实施步骤

1. **环境与版本锁定**
   - 本机 `zig version` = 0.16.0；mruby 4.0.0 release tarball。
   - 记录 `sizeof(mrb_value)=8`、`sizeof(mrb_int)=8`、`sizeof(mrb_float)=8`。

2. **构建 mruby**
   - `scripts/build-mruby.sh` 下载并 `rake all`。
   - 产物：`vendor/mruby/build/host/lib/libmruby.a`、`build/host/include`。

3. **绑定层**
   - `src/c.zig`：手写 `mrb_value`/`mrb_state`/`mrb_ccontext`/`mrb_parser_state` 与 extern 声明。
   - `src/shim.c`：arena、构造器、谓词、异常访问、parser 错误访问、ABI 断言。
   - 放弃 `@cImport`：macOS mach 头文件与位域导致 translate-c 失败。

4. **VM 与 Value**
   - `VM.init/deinit`、`evalWithOptions`（解析 + protect + 执行）。
   - `Value.call/get/set/hashGet/hashSet/arrayLen`。
   - 异常捕获：protect 标志 + `mrb->exc` 双检查；语法错误格式化文件名/行/列。
   - GC：eval/call 返回前 protect；暴露 arenaSave/arenaRestore/protect。

5. **示例与测试**
   - `examples/embed.zig` + `examples/hello.rb`。
   - `tests/` 按 values/lifecycle/errors/callbacks/ruby_suites 拆分，共 93 个测试（含 5 个 Ruby 套件）。
   - `zig build test` = 93/93；`zig build test -Doptimize=ReleaseSafe` 同样通过；`zig build run` 输出符合预期。

6. **仓库工程化**
   - `build.zig` 静态库/示例/测试三个产物。
   - `.gitignore` 排除 `.zig-cache`、`zig-out`、`vendor`。
   - GitHub Actions：Ubuntu + macOS，构建 mruby 后跑 test/run。

7. **已有方案调研与加固**
   - 检查 hfabre/zigretro-core、rguiscard 三个仓库、dantecatalfamo/mruby-zig、nullstyle/mruby-zig 的 README、代码、issue/PR。
   - 修正源串 NUL、完整保护帧、构造器/类定义保护、异常 inspect 保护；新增 5 个回归测试。
   - 结论与逐条教训写入 `docs/prior-art.md`。

## 5. 发布前待办（M3）

- [x] 在干净目录执行 `./scripts/build-mruby.sh && zig build test && zig build run`，记录结果（2026-11-13 通过）。
- [ ] 在 Ubuntu 上验证（本地或 CI），确认 `linkSystemLibrary("m")` 分支。
- [ ] 增加 `CHANGELOG.md`，写 0.1.0 初始功能与已知限制。
- [ ] 决定远程仓库归属与可见性；创建远程仓库并推送（需要用户确认）。
- [ ] 打 `v0.1.0` tag（release manifest 写明 Zig 0.16.0 + mruby 4.0.0）。
- [ ] 为 README 增加 CI 状态徽章（只有实际跑绿后）。
- [ ] 规划 0.2：迁移到 Zig 0.17.1；按 [兼容策略](compatibility.md) 用 `next/zig-0.17` 分支验证，不把 0.16/0.17 混在同一个 `build.zig`。

验收命令：

```console
./scripts/build-mruby.sh
zig build test
zig build run
zig build
```

验收标准：

- `zig build test` 全部通过；
- `zig build run` 输出嵌入版本、`Zig.square(7) = 49`、`ruby_sum(20, 22) = 42`；
- `zig build` 生成 `zig-out/lib/libzruby.a` 与 `zig-out/bin/zruby-example`；
- 干净环境不需要未记录的依赖。

## 6. 下一阶段（M4）

### 6.1 高层回调 API（已完成）

目标：用户写普通 Zig 函数，不必手写 `mrb_get_args`。

任务：

- [x] 支持 `fn(*VM, []const Value) Error!Value` 的自适应包装；
- [x] 参数/返回值自动转换（含超过 16 个参数的堆路径）；
- [x] 异常安全：Zig error -> Ruby 异常；`RubyException` 保留常见异常类；
- [x] 回调注册表与生命周期管理（注册项随 VM 释放）。

验收：回调抛错时 Ruby 侧收到异常，Zig 侧不 panic、不泄漏。已由 `tests/callbacks.zig` 覆盖，含 arity、类型错误、Ruby 异常、跨 VM 返回值与 VM 复用。

### 6.2 值类型覆盖与生命周期（已完成）

- [x] Symbol、Range、Proc、Time、自定义对象（`fromRange`、`fromCallback`、`isTime`、`isObject`、`className`）；
- [x] 数组/哈希迭代器（`arrayIterator` / `hashIterator` / `hashKeys` / `hashLen`）；
- [x] 显式 `RootedValue` / `arenaScope`；`RootedValue` 校验 VM，`ArenaScope` 校验 active 状态；
- [x] 结构化错误详情与有界 backtrace（`lastException` / `lastBacktrace`，上限 4096 字节）；
- [x] `mrb_value` 直接 API 与反射（公开 `Value.raw` / `VM.raw`，`className` 与类型谓词；跨 scope 自动失效检查暂未实现，依赖 arena 语义）。

### 6.3 字节码（已完成）

- [x] `scripts/build-bytecode.sh` 用 `mrbc -g` 生成 `tests/fixtures/bytecode.mrb`；
- [x] `VM.loadIrep` / `loadIrepWithOptions` 基于 `mrb_load_irep_buf_cxt`；
- [x] 资源嵌入示例：测试用 `@embedFile` 加载 `.mrb`，并覆盖重复加载与非法字节码。

### 6.4 跨平台与构建

- [x] Linux CI 实跑（Ubuntu + macOS 矩阵）；
- [x] 绑定符号一致性检查：`scripts/check-bindings.sh` 对照 `libmruby.a` 校验 `src/c.zig` 的 `mrb_*` 声明；
- [ ] Windows CI；
- [ ] 从 mruby 头文件生成 `c.zig`；
- [ ] 支持 `MRB_NAN_BOXING` / `MRB_NO_BOXING` 的配置化绑定；
- [ ] 评估纯 Zig 的 mruby 构建（presym、host `mrbc`、gem registry），去掉 Ruby/rake 依赖；
- [ ] 非 BigInt 配置的 Hash 行为负向测试。

Windows、绑定生成器、boxing 配置和纯 Zig 构建属于独立的大型工程，当前版本保持“手写最小绑定 + 默认 word-boxing”的边界，不在未验证的情况下宣称支持。

## 7. 风险与依赖

| 项 | 说明 | 应对 |
| --- | --- | --- |
| ABI 锁定 | 只支持 word boxing / 64 位 int | 文档明确；静态断言；符号检查 |
| longjmp | mruby 异常跨 C 边界 | 核心分配/调用/定义路径经 protect；回调禁止 panic |
| GC | 未保护值可能被回收 | 返回值 protect；文档要求长期值 protect |
| 平台 | 本地 macOS + CI Ubuntu/macOS | Windows 待补 |
| 远程仓库 | 已发布 `ShiningRay/zruby` | 保持 main 可发布，tag 不可变 |

## 8. 时间估算

- M3 发布准备：0.5–1 天（含干净环境复现与 Linux 验证）。
- M4 高层回调：2–3 天。
- M4 绑定生成器：3–5 天。
- v1.0 稳定化：2–4 周，取决于平台覆盖与 API 评审。

## 9. 完成定义

首版完成 = 仓库可克隆、可按 README 构建、测试与示例通过、限制和风险写清楚。当前代码与文档已满足本地版本；M3 的远程仓库与跨平台实跑仍需执行。
