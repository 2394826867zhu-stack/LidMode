你现在作为该项目的 Principal macOS Engineer，负责从零实现一个可以实际安装、运行、测试和卸载的生产级 macOS 工具。

项目名称：

LidMode

目标设备：

Apple Silicon MacBook，首要测试目标为 MacBook Air M2。

核心产品定义：

这是一个只有一个 Boolean 状态的 macOS System Toggle：

Normal ↔ Awake

其唯一用途是：

通过 macOS 菜单栏一个按钮，在：

1. 一般模式：MacBook 正常允许睡眠；
2. 禁止休眠模式：禁止系统睡眠，使 MacBook 合盖后仍可继续执行 Codex、本地程序和后台任务；

之间切换。

⸻

第一原则

不要过度工程化。

如果一个功能不是完成：

Normal ↔ Awake

所必需的，不要实现。

禁止把项目做成完整的电源管理软件。

⸻

技术栈约束

必须使用：

* Swift
* AppKit
* NSStatusItem
* Foundation
* Process
* os.Logger
* SMAppService
* macOS 原生 API

禁止使用：

* Electron
* Node.js
* Python Runtime
* WebView
* React
* SwiftUI 重型界面架构
* SQLite
* 第三方依赖
* 网络服务
* HTTP server
* telemetry
* analytics

项目必须可以在 Xcode 中直接打开和构建。

⸻

UI

应用：

* 只存在于 macOS Menu Bar
* 不显示 Dock icon
* 不出现在 Cmd + Tab
* 没有主窗口
* 没有设置窗口
* 没有 onboarding

设置：

LSUIElement = YES

正常状态：

☾ Normal

禁止休眠状态：

● Awake

未知：

? Unknown

错误：

⚠ Error

按钮本身即操作入口。

不要创建 dropdown menu。

用户单击按钮直接 toggle。

⸻

操作逻辑

点击时必须：

1. 读取真实系统状态
2. 判断当前 Normal / Awake
3. 执行目标状态切换
4. 再次读取真实系统状态
5. 验证修改是否成功
6. 更新菜单栏 UI

必须遵循：

read → modify → verify → render

禁止：

modify → assume success

⸻

系统状态

系统真实状态是唯一 Single Source of Truth。

禁止使用：

UserDefaults

作为 Awake 状态的权威数据。

必须读取实际 macOS power-management state。

核心使用：

/usr/bin/pmset

开启：

/usr/bin/pmset -a disablesleep 1

关闭：

/usr/bin/pmset -a disablesleep 0

读取：

/usr/bin/pmset -g

根据真实输出解析 SleepDisabled 状态。

解析器必须健壮处理：

* whitespace
* key missing
* unexpected output
* 0
* 1

⸻

权限架构

不要让 GUI App 获得无限 root 权限。

实现：

LidMode.app
↓
restricted root-owned helper
↓
pmset

helper：

/usr/local/libexec/lidmode-helper

必须：

owner = root
group = wheel

helper 仅允许：

on
off
status

禁止任何 arbitrary command。

禁止：

eval
sh -c
bash -c
dynamic executable path
arbitrary argument passthrough

所有 executable 使用 absolute path。

建议：

on
→ /usr/bin/pmset -a disablesleep 1

off
→ /usr/bin/pmset -a disablesleep 0

status
→ 输出 NORMAL / AWAKE / UNKNOWN

定义清晰 exit code。

⸻

sudoers

创建：

/etc/sudoers.d/lidmode

只允许当前用户无密码执行：

/usr/local/libexec/lidmode-helper

禁止：

NOPASSWD: ALL

禁止直接授权 shell。

GUI App 调用：

/usr/bin/sudo -n /usr/local/libexec/lidmode-helper

必须使用：

-n

确保权限异常时直接失败。

绝不能在日常操作时弹出密码窗口。

⸻

安装

实现：

Scripts/install.sh

安装脚本允许首次要求管理员权限。

完成：

1. 构建/安装 helper
2. copy helper
3. chown root:wheel
4. chmod
5. 创建 sudoers rule
6. 设置 440
7. 使用 visudo 校验 sudoers
8. 验证 helper status
9. 输出明确结果

如果中途失败：

安全回滚。

不要留下部分安装状态。

⸻

卸载

实现：

Scripts/uninstall.sh

必须彻底删除：

* helper
* sudoers configuration
* Login Item registration where applicable

README 必须给出完整卸载步骤。

⸻

Menu Bar Architecture

建议文件：

AppDelegate.swift

StatusBarController.swift

PowerState.swift

PowerStateService.swift

HelperClient.swift

LoginItemService.swift

Logger.swift

不要使用庞大的 architecture pattern。

不要：

DDD
Clean Architecture
Redux
Repository abstraction
Dependency injection framework

如果简单 Swift object 足够，就保持简单。

⸻

State Model

实现：

enum PowerState {
case normal
case awake
case unknown
}

必要时单独：

enum DisplayState {
case normal
case awake
case executing
case unknown
case error(String)
}

⸻

并发

防止用户快速重复点击。

实现一个最小：

isExecuting

或 serial execution mechanism。

执行期间忽略新的 toggle。

不要为了这个引入复杂 concurrency framework。

可以使用现代 Swift concurrency，但只在能够明显降低复杂度时使用。

⸻

Resource Requirements

这是一个微型工具。

Idle CPU：

应接近 0%。

禁止持续 polling。

禁止：

Timer 每秒执行
while true
后台高频 pmset
定时网络请求

状态刷新只在以下情况执行：

1. App launch
2. 用户点击
3. 修改后 verify
4. macOS wake event

监听：

NSWorkspace.didWakeNotification

Wake 后重新读取真实状态。

⸻

内存

要求：

没有大型 runtime。

没有持续增长。

没有 memory leak。

不要为了少量状态创建复杂缓存。

一个 NSStatusItem + 少量 Swift object 即可。

⸻

Network

整个 App 不需要网络。

不要添加任何 outbound network request。

不要：

analytics
telemetry
crash upload
update server
remote configuration

⸻

Logging

使用：

os.Logger

记录：

app start
state read
toggle request
helper result
verification
failure

不要记录：

用户文件
Codex 内容
个人数据
shell history

⸻

Login Item

使用：

SMAppService

让应用可以登录自动启动。

不要因此引入额外 daemon。

如果 Login Item 注册失败：

主功能仍然可使用。

⸻

Error Handling

如果 helper 不存在：

UI：

⚠ Setup

或者：

⚠ Error

不要偷偷要求管理员权限。

如果 sudo 失败：

保持系统原状态。

如果 pmset 修改失败：

重新读取真实状态。

如果 verify 与目标状态不一致：

显示 Error。

绝不能显示虚假成功状态。

⸻

Restart

应用每次启动：

重新读取 macOS 实际状态。

不要根据上一次 App 保存状态自动修改系统。

不要：

lastState == awake
→ force awake

系统当前状态永远优先。

⸻

Testing

创建 Unit Tests：

PowerStateParserTests

至少覆盖：

SleepDisabled 0

SleepDisabled 1

extra whitespace

missing field

malformed output

unexpected output

创建 helper integration test。

测试：

status
on
status
off
status

⸻

Manual Acceptance Test

必须在真实 Apple Silicon MacBook 上提供测试步骤。

重点：

MacBook Air M2。

测试：

Normal
→ close lid
→ expected sleep

Awake
→ close lid
→ Mac remains operational

启动 Codex 任务
→ Awake
→ close lid
→ 远程检查
→ Codex task continues

重新开盖
→ click Awake
→ Normal
→ close lid
→ sleep

⸻

Security Review

完成实现后主动审计：

1. helper 是否能执行 arbitrary command
2. sudoers 是否权限过宽
3. helper 是否普通用户可修改
4. executable 是否使用绝对路径
5. 是否存在 argument injection
6. 是否存在 shell injection
7. 是否存在 race condition
8. 是否存在错误状态假成功
9. 是否存在不必要 root process
10. 是否存在长期 privileged daemon

发现问题直接修复。

⸻

项目结构

优先生成：

LidMode/
│
├── LidMode.xcodeproj
├── LidMode/
│   ├── AppDelegate.swift
│   ├── StatusBarController.swift
│   ├── PowerState.swift
│   ├── PowerStateService.swift
│   ├── HelperClient.swift
│   ├── LoginItemService.swift
│   ├── Logger.swift
│   ├── Assets.xcassets
│   └── Info.plist
│
├── Helper/
│   ├── lidmode-helper.swift
│   └── build-helper.sh
│
├── Scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   └── verify-install.sh
│
├── Tests/
│   ├── PowerStateParserTests.swift
│   └── HelperTests.swift
│
├── README.md
└── LICENSE

如果你认为存在更简单并保持同等安全性的目录，可以调整。

但是不要增加无意义层级。

⸻

README

README 必须包含：

1. 项目用途
2. 系统要求
3. 构建方法
4. 安装方法
5. 首次权限说明
6. 使用方法
7. 状态含义
8. 安全模型
9. 完整卸载方法
10. Troubleshooting
11. 手工验收流程

⸻

Definition of Done

不要在“代码能编译”时停止。

只有以下全部完成才算完成：

* Xcode project 可以构建
* App 可以启动
* Menu Bar icon 出现
* 无 Dock icon
* 无主窗口
* Normal / Awake 正确显示
* 单击可以 toggle
* 不打开 Terminal
* 日常 toggle 不要求密码
* 日常 toggle 不要求 Touch ID
* 修改后实际 verify
* helper 最小权限
* sudoers 最小权限
* 无 arbitrary shell execution
* idle CPU 接近 0
* 无 polling
* 无 network
* 无 telemetry
* 无第三方 runtime
* Unit Tests 通过
* install.sh 工作
* uninstall.sh 工作
* README 完整
* Security Review 完成

⸻

工作方式

不要一次性生成一堆未经验证的代码。

按以下顺序执行：

Phase 1

审查需求与 macOS 权限设计。

输出：

* 最终 architecture
* 风险点
* 文件结构

如果没有阻塞问题，直接继续，不需要等待人工批准。

Phase 2

创建最小可编译 App。

先实现：

* NSStatusItem
* state model
* pmset state parser

编译验证。

Phase 3

实现 helper。

完成 helper 自测。

Phase 4

实现 sudoers installer。

进行语法验证和安全审查。

Phase 5

连接 GUI ↔ helper。

完成：

read
toggle
verify
render

Phase 6

实现 Login Item 和 wake synchronization。

Phase 7

完成 tests。

Phase 8

运行完整 build/test。

修复所有 warning 和 error。

Phase 9

Security Review。

Phase 10

生成 README 和最终验收报告。

⸻

Codex 自主执行原则

你可以：

* 创建文件
* 修改文件
* 执行 build
* 执行 test
* 重构
* 修复 warning
* 修复 bug
* 更新 README

不要因为普通实现细节询问用户。

遇到没有必要询问的技术选择：

优先选择：

最简单
最原生
最安全
依赖最少
维护最少

的方案。

不要增加用户没有提出的产品功能。

⸻

最终输出

完成后返回：

Build

PASS / FAIL

Tests

PASS / FAIL

Security

PASS / FAIL

Files Created

简表。

Manual Steps Required

只列真正需要用户人工执行的操作。

Known Limitations

必须真实列出。

Final Usage

用户最终应该只需要：

☾ Normal
    ↓ click
● Awake
    ↓ click
☾ Normal

这就是整个产品。
