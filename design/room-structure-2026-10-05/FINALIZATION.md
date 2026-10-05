# 月轨家具样稿定稿与编译验证

2026-10-05，用户确认 [v5 设计](LUNAR-V5.md) 定稿。入口为 [lunar.html](lunar.html)，固定房屋标准仍是 `room-standard-v1`，基准提交为 `cc33751`，工作分支为 `codex/room-structure-sample`。

## 本次提交范围

提交内容限定在 `design/room-structure-2026-10-05/`：已确认的家具、窗框与画框、材质、独立昼夜窗景、预览与制作代码、尺寸/占格/锚点清单、测试和设计说明。v1–v4 的本地设计过程保留为历史记录，当前入口使用 v5。结构入口增加样稿链接，四个画位的最大预留范围沿用此前确认的放大尺寸。

本轮没有将样稿接入正式 Flutter 房间，也没有修改生产主页、商店、购买、计时、任务、猫咪、存档或主题设置逻辑。样稿目录之外的 353 个已跟踪文件在编译前后 SHA-256 一致。原有无关未跟踪素材及证据文件保留在工作区，不混入本次提交。

本次不再改变手板视觉。正式开发时，两堵墙分别设计；窗外景色根据各墙的真实朝向与可见范围分别投影或制作，不通过简单水平镜像造成月相、文字或景物方向等常识冲突。当前手板和家具的已确认镜像方案继续保留，正式接入时再处理这项差异。

## 验证结果

| 检查 | 结果 |
|---|---|
| Flutter analyze --no-pub | 无问题 |
| Flutter 全量单元与 Widget 测试 | 68 项全部通过 |
| Flutter Web release 编译 | 成功，产物在 `build/web/` |
| Android ARM64 debug APK 编译 | 成功，产物在 `build/app/outputs/flutter-apk/app-debug.apk` |
| JavaScript 语法检查 | 20 个模块通过 |
| 房屋、占格、实体构造与锚点检查 | 18 项全部通过 |
| 当前样稿浏览器验证 | 32 种家具朝向组合、36 组模板/画芯组合、昼夜 API 与显隐联动、360/390px 显示通过 |
| 透明素材检查 | 35 张 PNG 通过；镜像像素差为零；家具没有游离残留像素 |
| 固定标准与视觉锚点 | 五个标准文件相对 `cc33751` 无差异 |
| 业务源码完整性 | 样稿目录之外 353 个已跟踪文件逐字节一致 |

Flutter 测试覆盖主页导航、家具选款/显隐/重启恢复、主题保存、计时与恢复、任务、猫咪、存储与同步等现有行为。此次编译及测试没有升级项目依赖，编译产物保留在 Git 已忽略的 `build/` 目录。

本机 Flutter 批处理启动脚本曾出现运行时路径解析问题；验证通过直接调用已有 Dart 运行时和缓存的 `flutter_tools.snapshot` 完成，没有更改项目源码或 SDK 脚本。命令使用既有 `.tooling/pub-cache`、`.tooling/android-sdk` 与 `.tooling/gradle-cache`，并加 `--no-version-check` 避免无关的升级检查。

对应 Flutter 命令参数为 `analyze --no-pub`、`test --no-pub --reporter expanded`、`build web --release --no-pub --no-wasm-dry-run`、`build apk --debug --target-platform android-arm64 --no-pub`。完整本地编译/测试日志保存在 Git 忽略的 `.tooling/lunar-final-*.log`。

样稿验证的可移植记录：[浏览器报告](lunar-assets-v5/verification.json)、[透明素材报告](lunar-assets-v5/alpha-verification.json)、[素材清单](lunar-assets-v5/manifest.json)。复建与测试命令见 [LUNAR-V5.md](LUNAR-V5.md)。
