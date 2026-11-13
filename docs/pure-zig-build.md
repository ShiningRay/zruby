# 纯 Zig 构建 mruby 评估

日期：2026-11-13。范围：是否把 `scripts/build-mruby.sh`（Ruby + rake）替换为纯 Zig 构建。

## 1. 现状

- `scripts/build-mruby.sh` 下载 mruby 4.0.0 tarball、校验 SHA-256、解压、执行 `rake all`。
- `build.zig` 只消费 `vendor/mruby/build/host` 下的头文件与静态库；`-Dmruby-prefix` 允许外部预构建库。
- CI 在 macOS、Ubuntu、Windows MinGW 上都能安装 Ruby/rake 并完成构建。

## 2. 纯 Zig 构建需要补齐的环节

| 环节 | 说明 | 风险 |
| --- | --- | --- |
| presym | mruby 默认启用 presym，需要生成 `presym/id.h`、`table.h` 与扫描器 | 需要复刻 mruby 的 Ruby 生成器或提交生成物 |
| host `mrbc` | mrblib/gem 的 Ruby 源码必须先由 host `mrbc` 编译为字节码 | 需要两阶段构建（host 与 target），且跨平台 host 选择复杂 |
| gem registry | `default.gembox` 会解析依赖、生成 `gem_init.c` | 需要实现 mruby 的 gem 依赖图与 HAL 选择 |
| 编译/归档 | 每种平台/boxing/per-sym 组合都要生成正确 C 宏与对象文件 | 容易与 mruby 默认构建漂移 |
| 平台 HAL | POSIX/Windows socket/io/dir 等 HAL gem 的选择 | Windows 已验证过 MinGW 组合，但 MSVC 尚未验证 |

## 3. 结论

暂不替换。理由：

1. 当前 Ruby/rake 路径已在三平台 CI 稳定通过，构建可复现性由 tarball SHA-256 + 固定 Ruby/Zig 版本保证。
2. 纯 Zig 构建是独立的大型工程（参考 nullstyle/mruby-zig 的 presym/mrbc/gem registry 复刻），收益主要是去掉 Ruby 依赖，不改善绑定 ABI 或运行时行为。
3. 消费方已经可以通过 `-Dmruby-prefix` 使用自己的预构建 mruby；不需要仓库内纯 Zig 构建即可集成。

重评条件：CI 无法安装 Ruby、需要离线构建、或 Windows MSVC/交叉编译成为发布门槛时，再按上述环节拆分实现。
