# Zig 与 mruby 兼容策略

## 1. 当前事实（2026-11-13）

| 组件 | 当前稳定版 | 说明 |
| --- | --- | --- |
| Zig | **0.17.1**（2026-11-02） | 0.17.0 于 2026-10-02 发布；0.16.0 是上一稳定版。Zig 仍是 pre-1.0，不承诺语言/标准库/Build API 稳定。0.17 重做了 Build System，并改动了 `@bitCast`、`@intFromEnum`、`std.builtin` 等。 |
| mruby | **4.0.0**（2026-04-20） | 4.1.0-rc 于 2026-09-04 出现，但截至本日没有 4.1 稳定版。4.1 计划切换到 Prism parser，C API/头文件会变。 |

zruby 当前实测基线：**Zig 0.16.0 + mruby 4.0.0**，75/75 测试通过。0.17.1 是下一迁移目标，尚未在本仓库验证；不要在发布说明里声称支持。

## 2. 支持分层

不要追求“支持所有 Zig 0.x / mruby 4.x”。维护三档：

| 档位 | 内容 | 是否阻塞发布 |
| --- | --- | --- |
| **Release gate** | 一个精确的 Zig 稳定版 + 一个精确的 mruby 稳定版 + 默认 build config | 是；全矩阵必须绿 |
| **Previous release** | 上一个 zruby release 的锁定组合；只修安全/严重 bug | 否；保留一个发布周期（到下一个稳定版 + 30 天） |
| **Canary** | Zig master 或 mruby master/rc | 否；每周跑，失败开 issue |

明确不支持：任意 Zig/mruby 版本组合、未同步 C 宏的自定义 mruby、CRuby、未验证的 Windows 组合。`-Dallow-untested-zig` / `-Dallow-untested-mruby` 只用于迁移试验，不是支持声明。

## 3. 版本与发布规则

- zruby 使用 SemVer：
  - **patch**：同一工具链组合内的 bugfix。
  - **minor**：新增 API，或升级工具链基线。
  - **major**：公开 Zig API 破坏；0.x 期间也按此约定。
- `build.zig.zon` 的 `minimum_zig_version` 只是下限，不等于支持上限；精确版本放在 `.mise.toml`、CI 和 release manifest。
- mruby 版本、tarball SHA-256、build config、gem set、C ABI 宏全部固定在 release 元数据中。
- `src/zruby.zig` 的公开 API 稳定；`pub const c` 是原始逃生口，明确不承诺稳定。
- 发布说明必须写：`zruby 版本 / Zig 版本 / mruby 版本 / 平台 / build config`。

## 4. 代码层如何隔离

1. **C shim 是主兼容层**：mruby 的结构体、宏、inline 函数变化只应影响 `src/c.zig` 与 `src/shim.c`。不要恢复 `@cImport` 直接吃 mruby 头文件。
2. **版本开关**：`src/shim.c` 用 `MRUBY_RELEASE_MAJOR/MINOR` 做硬检查；4.0.x 之外默认编译失败，迁移时用 `-Dallow-untested-mruby` 显式打开，验证后再改默认。
3. **Zig 侧版本门**：`build.zig` 对 0.16.x 做硬检查；其他版本会直接报错并指向本文。迁移到 0.17 时改常量、单独分支验证，不要在一个 `build.zig` 里堆版本判断。
4. **构建系统不跨版本复用**：Zig Build API 的 breaking change 往往先于语言语法出现；0.16 与 0.17 用不同分支/tag，而不是试图让一个 `build.zig` 同时解析两套 API。
5. **示例隔离**：`std.Io`、`std.process.Init` 等只在 `examples/` 使用；库本体不依赖这些易变 API。
6. **ABI 断言**：`mrb_value` 指针宽度、`mrb_int`/`mrb_float` 大小在 C 侧 `_Static_assert`；这比“编译过了”更早暴露配置错误。

## 5. CI 设计

### Release gate（阻塞）

- 精确 Zig + 精确 mruby。
- macOS + Linux。
- Debug 与 ReleaseSafe。
- `zig fmt --check`。
- `zig build test`、`zig build`、`zig build run`。
- clean-room：`./scripts/build-mruby.sh && zig build test`。
- `./scripts/verify-toolchain.sh` 校验 Zig/mruby 版本。

### Canary（非阻塞）

- 每周/手动触发 Zig master。
- 用 `-Dallow-untested-zig` 尝试构建。
- 失败只开 issue，不阻塞 tag；失败日志保留。
- mruby 4.1 stable 发布后再加 mruby rc 矩阵。

## 6. 升级流程

1. Canary 或上游 release note 触发升级 issue，记录工具链对和失败日志。
2. 从 `main` 建 `next/zig-0.17`（或 `next/mruby-4.1`）分支；`main` 保持可发布。
3. 改 `.mise.toml`、CI、`build.zig` 版本门；必要时新增 shim 分支或按 mruby minor 拆绑定文件。
4. 先修编译，再修行为；每修一类问题补一个回归测试。
5. 全矩阵 + clean-room 通过后更新 `docs/compatibility.md`、`CHANGELOG.md`、README，合并到 `main`。
6. 打 tag；旧组合保留在 `release/x.y` 分支，只回移植关键修复。

不要在升级 PR 中混入新功能；工具链升级和 API 变更分开评审。

## 7. Release 检查清单

- [ ] `zig version` 与 `.mise.toml` 一致。
- [ ] `vendor/mruby/build/host/bin/mruby -v` 与 pin 一致。
- [ ] mruby tarball SHA-256 与 `scripts/build-mruby.sh` 一致。
- [ ] `zig fmt --check build.zig src tests examples`。
- [ ] Debug/ReleaseSafe 测试全绿。
- [ ] clean-room 构建通过。
- [ ] 示例运行通过。
- [ ] 更新 compatibility 表、CHANGELOG、README。
- [ ] 打不可变 tag，并附上工具链/平台说明。

## 8. 当前兼容矩阵

| zruby | Zig | mruby | 状态 |
| --- | --- | --- | --- |
| 0.1.x（当前） | 0.16.0 | 4.0.0 | release gate；75/75 通过 |
| 0.2（计划） | 0.17.1 | 4.0.0 | 迁移目标；未验证 |
| canary | Zig master | mruby 4.0.0 / 4.1 rc | 非阻塞探测 |

## 9. 消费方建议

- 固定 zruby 的 tag，不要跟随 `main`。
- 固定 Zig 版本；不要把 `minimum_zig_version` 当成“任意更高版本可用”。
- 固定 mruby tarball/commit；不要用系统里随意安装的 mruby。
- 升级顺序：先升级 zruby → 再升级 mruby → 最后升级 Zig；每一步跑同一套 75 个测试。
- 如果你的应用必须停留在旧 Zig，使用对应的 `release/x.y` 分支，而不是要求库同时兼容多个 Zig minor。
