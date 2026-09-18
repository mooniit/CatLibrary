# Android 模拟器

2026-09-18 实际检查：本机 WHPX 可用，已创建并启动 `catlibrary_m0`。Android 15 / API 35 / x86_64，内存 1536 MB、2 个 CPU 核心、软件图形渲染；虚拟机文件保存在忽略目录 `.tooling/avd`，不提交仓库。没有生成或采纳新的美术素材。

## 已执行验证

- `emulator -accel-check`：退出码 0，WHPX installed and usable。
- ADB：`emulator-5554` 状态为 `device`。
- `sys.boot_completed`：`1`。
- 系统版本：`15`；CPU ABI：`x86_64`。
- Package Manager 可查询系统设置应用，系统服务可用。

Android x86_64 调试 APK 已成功构建、安装和冷启动。模拟器四页导航、同进程后台恢复、短时锁屏返回、强制停止后的 SQLite 冷恢复均通过；详见 evidence/m0-android-lifecycle.json。这些是模拟器证据，不代表一加真机或 iPhone 验收。此前依赖下载 TLS 问题已在沿用本机代理后重试解决，未关闭证书校验。内存有限，构建与模拟器尽量错开；本机 Gradle 缓存中配置 1.5 GB 堆、最多 2 个工作线程。

## 再次启动与使用

```powershell
./scripts/start-emulator.ps1
# 无窗口自动化测试时：
./scripts/start-emulator.ps1 -Headless
./scripts/flutter.ps1 devices
# 运行结构原型：
./scripts/flutter.ps1 run -d emulator-5554
./scripts/flutter.ps1 test integration_test/timer_probe_test.dart -d emulator-5554
# 对已安装的普通原型执行系统级测试（会开始一条探针记录并强制停止应用）：
node scripts/test-android-probe.cjs emulator-5554
```

脚本在该虚拟机已在线时直接报告现有设备，不重复启动。设备编号由 ADB 分配，以 `devices` 实际结果为准。关闭模拟器窗口即可结束虚拟机，也可使用 `adb -s <设备编号> emu kill`。

## 首次安装记录

系统镜像来自 Android SDK 官方源：`system-images;android-35;default;x86_64`。使用项目内 `sdkmanager` 安装，并通过 `avdmanager create avd --name catlibrary_m0 --package 'system-images;android-35;default;x86_64' --path <项目>/.tooling/avd/catlibrary_m0.avd` 创建；运行前设置 `ANDROID_HOME=<项目>/.tooling/android-sdk` 与 `ANDROID_AVD_HOME=<项目>/.tooling/avd`。此次下载沿用本机既有 HTTP 代理，未关闭 TLS 校验。

模拟器适合验证导航、SQLite、启动恢复和 Android 生命周期；一加 Ace 3 的厂商后台限制仍需真机验证。iPhone/Mac/Xcode 和远端 Supabase 项目仍缺，不能由 Android 模拟器替代。

## 已保存 APK

模拟器包：output/android/cat-library-m0-x64-debug.apk。一加真机包：output/android/cat-library-m0-arm64-debug.apk。二者已构建成功；arm64 尚未安装验证。普通原型包与集成测试包不同，运行集成测试后需重新安装普通原型再执行 scripts/test-android-probe.cjs。
