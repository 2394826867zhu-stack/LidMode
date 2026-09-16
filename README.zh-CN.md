# LidMode

<p align="center">
  <img src="LidMode/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" alt="LidMode 应用图标">
</p>

<p align="center">
  一个轻量、原生的 macOS 菜单栏工具，用于在正常睡眠与合盖保持运行之间切换。
</p>

[English](README.md) · **简体中文**

## 它解决什么问题

LidMode 直接读取和修改 macOS 的真实 `SleepDisabled` 电源状态：

```text
☾ Normal  → 点击 →  ● Awake  → 点击 →  ☾ Normal
```

- `Normal`：恢复系统正常睡眠策略。
- `Awake`：禁止系统睡眠，使 MacBook 合盖后仍可继续本地任务。
- 每次操作都遵循“读取 → 修改 → 再次读取 → 验证 → 显示”，不会假定命令一定成功。

## 特点

- Swift + AppKit 原生实现，不使用 Electron、Node、Python 运行时或第三方依赖。
- 左键直接切换；右键打开精简的设置与退出菜单。
- 支持开机启动、Awake 时保持屏幕点亮、可调低电量保护和三种菜单栏文字显示模式。
- GUI 始终以普通用户身份运行；提权 helper 只接受 `on`、`off`、`status` 三个固定操作。
- 无网络请求、无遥测、无分析、无后台轮询。
- 在参考的 16 GB M2 设备上，30 秒空闲实测 CPU 为 0.0%，物理内存约 25 MB。

## 系统要求

- Apple Silicon MacBook（主要在 M2 设备上验证）
- macOS 13 或更高版本
- Xcode 15 或更高版本，并已接受 Xcode 许可协议
- 具有密码的管理员账户

## 安装

项目目前只提供源码安装，不提供公开预编译二进制。打开终端执行：

```bash
git clone https://github.com/2394826867zhu-stack/LidMode.git
cd LidMode
./Scripts/install.sh
```

安装器会在本机编译应用，申请一次管理员授权，安装受限 helper，验证权限、签名、sudoers 规则和真实电源状态，然后启动菜单栏应用。

安装后如果 macOS 提示后台项目或登录项，请前往“系统设置 → 通用 → 登录项”确认 LidMode。该确认只影响自动启动，不影响应用已运行时的切换功能。

## 使用

- 左键菜单栏图标：在 Normal 与 Awake 之间切换。
- 右键菜单栏图标：查看当前状态、切换、打开设置或退出。
- 设置中可以控制登录时启动、屏幕保持点亮、低电量保护和状态文字显示方式。

Awake 模式会让 MacBook 在合盖后继续消耗电量并可能发热。不要把正在执行重负载的合盖设备放入封闭包内；任务完成后应恢复 `Normal`。

## 完整卸载

在仓库目录执行：

```bash
./Scripts/uninstall.sh
```

卸载器会先恢复并验证正常睡眠，再移除应用、helper、sudoers 规则和登录项。

## 验证安装

```bash
./Scripts/verify-install.sh
```

该命令检查安装路径、所有者与权限、应用身份、签名、helper 完整性、精确 sudoers 规则以及真实状态读取。

## 从源码构建

可直接使用 Xcode 打开 `LidMode.xcodeproj`，选择 `LidMode` scheme 并为“我的 Mac”构建。完整的命令行构建、测试、架构与故障排查说明见 [英文 README](README.md)。

## 安全与隐私

- 应用和 helper 都不会执行 shell。
- 所有提权路径和命令参数固定，不接受任意命令。
- 应用不联网，不包含更新器、遥测或用户数据库。
- 完整威胁模型和漏洞报告方式见 [SECURITY.md](SECURITY.md)。
- 代码审计与验证证据见 [AUDIT.md](AUDIT.md)。

## 参与贡献

欢迎提交可复现的 Bug、文档改进和保持产品轻量的修复。提交前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。

LidMode 使用 [MIT License](LICENSE) 开源。
