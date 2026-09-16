LidMode — Production Blueprint / PRD

0. 文档定位

这是一个极小型 macOS 原生菜单栏应用。

## 0.1 当前增量需求（优先于下文冲突条款）

2026-09-16 的产品决策在保持核心 one-bit toggle 不变的前提下，加入一组轻量设置。下文中“不创建设置窗口”“不出现菜单”等早期 V1 限制由本节覆盖；真实系统状态、最小权限、低资源占用和无轮询原则继续有效。

新增要求：

* 左键菜单栏图标仍直接切换 Normal / Awake。
* 右键显示简洁菜单：当前状态、切换动作、设置、退出；退出必须是最后一项。
* 设置支持登录时自动启动。
* 设置支持 Awake 时保持屏幕点亮并抑制空闲休眠；回到 Normal 或退出应用时必须立即释放断言。
* 设置支持低电量保护，默认开启且阈值为 20%，允许在 5%–50% 调节或关闭。仅使用电池且电量小于等于阈值时，自动恢复并验证 Normal。
* 设置支持菜单栏状态文字三态：“始终显示”“仅切换时显示”“隐藏”。“仅切换时”在切换开始至验证结束后 3 秒显示；任何模式都必须保留可操作图标，避免应用失去入口。
* 菜单栏悬停说明仅描述当前状态，不追加左右键操作提示。
* 电量变化必须使用系统事件通知；禁止增加轮询定时器。
* 设置使用原生 AppKit / ServiceManagement / IOKit，不引入第三方依赖或常驻运行时。

产品只解决一个问题：

在 MacBook 上，通过菜单栏单一按钮，在「一般模式」与「禁止休眠模式」之间切换，并始终准确显示当前真实系统状态。

禁止引入任何与该目标无直接关系的功能。

⸻

1. 产品目标

目标设备：

* Apple Silicon MacBook
* 首要适配：MacBook Air M2
* macOS 13+
* 优先兼容当前稳定版 macOS

核心使用场景：

用户需要让 MacBook 在合盖情况下继续运行 Codex、本地终端任务、网络服务或其他后台工作。

用户不希望：

* 打开 Terminal
* 输入 sudo
* 每次 Touch ID
* 打开设置窗口
* 使用复杂 Session
* 选择时间
* 使用大型第三方软件
* 启动 Electron / Node / Python Runtime
* 引入高内存常驻程序

最终体验必须接近系统原生开关。

⸻

2. 产品原则

优先级：

1. 简单
2. 稳定
3. 真实状态
4. 极低资源占用
5. 最小权限
6. 可恢复
7. 无干扰

禁止为了“架构优雅”增加不必要组件。

这是一个：

one-bit system toggle

而不是完整电源管理软件。

⸻

3. 用户界面

3.1 UI 形态

应用：

* 仅存在于 macOS Menu Bar
* 不显示 Dock 图标
* 不出现在 Cmd + Tab
* 不创建主窗口
* 不创建设置窗口
* 不创建欢迎页

Info.plist：

LSUIElement = YES

⸻

4. 菜单栏状态

按钮必须同时承担：

* 状态展示
* 点击操作

推荐状态：

一般模式

☾ Normal

含义：

SleepDisabled = 0

Mac 保持系统默认睡眠逻辑。

合盖：

Sleep

⸻

禁止休眠模式

● Awake

含义：

SleepDisabled = 1

系统睡眠被禁止。

合盖时保持系统运行。

⸻

状态未知

? Unknown

仅用于：

* pmset 读取失败
* helper 不可用
* 返回格式无法识别

Unknown 状态下：

禁止直接执行盲目 toggle。

⸻

执行失败

⚠ Error

通过 tooltip 提供最小错误说明。

不要自动弹窗。

⸻

5. 核心交互

只有一个核心动作：

点击菜单栏按钮

业务流程：

Read current state
        ↓
SleepDisabled == 0 ?
        ↓
YES             NO
 ↓               ↓
Enable          Disable
 ↓               ↓
Verify          Verify
        ↓
Refresh UI

要求：

* 单击执行
* 不出现菜单
* 不要求额外确认
* 不打开 Terminal
* 不弹窗口
* 不要求 Touch ID
* 不要求密码

目标交互时间：

< 500 ms

实际完成时间应主要取决于系统命令。

⸻

6. 系统状态

6.1 Single Source of Truth

应用内部状态不是权威状态。

禁止：

UserDefaults.standard.bool(forKey: "awake")

作为系统状态判断依据。

必须：

macOS actual power-management state

作为 Single Source of Truth。

UI 状态永远来源于实际系统读取结果。

⸻

7. 系统控制方式

V1 使用：

/usr/bin/pmset

核心命令：

开启禁止休眠：

/usr/bin/pmset -a disablesleep 1

恢复正常：

/usr/bin/pmset -a disablesleep 0

状态：

通过：

/usr/bin/pmset -g

解析：

SleepDisabled

或对应系统实际输出。

不要依赖应用自己的缓存。

⸻

8. 权限架构

8.1 V1 推荐架构

LidMode.app
     │
     ▼
Restricted Helper
     │
     ▼
pmset

使用：

sudoers NOPASSWD

但只允许执行一个固定 root-owned helper。

禁止：

NOPASSWD: ALL

禁止：

/bin/sh

禁止：

/bin/bash

禁止给 App 任意 root command execution capability。

⸻

9. Helper 设计

路径建议：

/usr/local/libexec/lidmode-helper

Owner：

root:wheel

权限：

755

helper 只接受三个参数：

on
off
status

行为：

lidmode-helper on
→ pmset -a disablesleep 1
lidmode-helper off
→ pmset -a disablesleep 0
lidmode-helper status
→ 返回规范化状态

推荐输出：

NORMAL
AWAKE
UNKNOWN

退出码：

0 = success
1 = invalid argument
2 = pmset execution failed
3 = state verification failed

禁止 helper 接收：

* 任意 shell command
* 任意 path
* 任意 environment executable
* arbitrary arguments

所有 binary path 使用绝对路径。

⸻

10. sudoers

建议独立文件：

/etc/sudoers.d/lidmode

权限：

440

允许当前用户执行：

/usr/local/libexec/lidmode-helper

无需密码。

必须使用：

visudo -cf

验证语法。

App 调用：

/usr/bin/sudo -n /usr/local/libexec/lidmode-helper on

-n 非常重要。

如果权限失效：

立即失败。

禁止弹出密码请求。

⸻

11. 首次安装

允许首次安装执行一次管理员认证。

这是唯一允许出现权限授权的阶段。

安装流程：

Install App
    ↓
Run setup once
    ↓
Admin authentication
    ↓
Install helper
    ↓
Set root ownership
    ↓
Install sudoers rule
    ↓
Validate
    ↓
Done

安装完成以后：

正常使用期间不得再次要求：

* sudo password
* Touch ID
* admin dialog

除非系统配置已经被破坏。

⸻

12. 常驻架构

常驻：

LidMode.app

不常驻：

helper

helper 只在调用时启动。

禁止增加：

* LaunchDaemon
* 后台 HTTP Server
* localhost service
* Node
* Python
* Electron
* WebView
* SQLite
* database
* telemetry
* analytics
* network connection

除非未来版本有明确 PRD。

⸻

13. 技术栈

必须：

Language:
Swift
UI:
AppKit
Menu Bar:
NSStatusItem
Process execution:
Foundation.Process
State:
pmset
Login Item:
SMAppService
Build:
Xcode native macOS app

优先：

AppKit

而不是 SwiftUI。

原因：

这个应用只有一个 NSStatusItem。

不需要引入额外 UI abstraction。

⸻

14. App 生命周期

启动：

applicationDidFinishLaunching
        ↓
create NSStatusItem
        ↓
readState()
        ↓
renderState()

⸻

15. 点击逻辑

伪代码：

func statusItemClicked() {
    guard !isExecuting else { return }
    isExecuting = true
    let current = readSystemState()
    switch current {
    case .normal:
        execute(.enableAwake)
    case .awake:
        execute(.disableAwake)
    case .unknown:
        render(.error)
        isExecuting = false
        return
    }
    let verifiedState = readSystemState()
    render(verifiedState)
    isExecuting = false
}

必须：

read → modify → verify → render

禁止：

modify → assume success

⸻

16. 并发控制

防止快速连续点击造成 race condition。

状态：

isExecuting

执行期间忽略额外点击。

不要创建复杂 queue framework。

一个串行执行路径即可。

⸻

17. UI 状态机

NORMAL
AWAKE
UNKNOWN
ERROR
EXECUTING

EXECUTING 可以短暂显示：

…

但如果执行足够快，也可以保持原状态直到验证完成。

⸻

18. Tooltip

Normal：

一般模式：合盖将正常休眠

Awake：

禁止休眠：合盖后 Mac 将继续运行

Unknown：

无法读取系统睡眠状态

Error：

显示精简错误。

不要输出技术堆栈给普通 UI。

详细日志写入系统日志。

⸻

19. 日志

使用：

os.Logger

禁止创建长期增长的自定义 logfile。

记录：

* App start
* State read
* Toggle request
* helper exit code
* verification result
* failure

不得记录：

* 用户文件
* Codex 内容
* shell history
* personal data

⸻

20. CPU 设计

必须事件驱动。

禁止：

while true

禁止每秒轮询。

禁止定时高频读取 pmset。

允许：

App 启动

读取一次。

用户点击

读取一次。

修改后

验证一次。

System Wake

读取一次。

⸻

21. Sleep / Wake 同步

监听 macOS workspace wake notification。

例如：

NSWorkspace.didWakeNotification

唤醒后：

readState()
renderState()

避免长时间运行后 UI 与系统状态不同步。

⸻

22. Login Item

提供：

Launch at Login

但不需要提供设置页面。

V1 可默认注册 Login Item。

使用：

SMAppService

如果注册失败：

应用仍应正常工作。

⸻

23. 内存目标

这是一个微型 App。

目标：

Idle RSS:
尽量控制在几十 MB 以内

不设置死性数字验收，因为 macOS runtime / OS 版本会影响实际 RSS。

重点验收：

* 不持续增长
* 不 leak
* 不运行大型 runtime
* 无后台计算
* 无定时高频任务

⸻

24. CPU 目标

Idle：

≈ 0%

可接受偶发系统调度。

禁止：

持续 >0.5%

除非用户刚刚执行 toggle。

⸻

25. Network

产品完全不需要网络。

验收：

No outbound network requests

禁止：

* analytics
* update framework
* crash upload
* remote config
* telemetry

V1 全部禁止。

⸻

26. Failure Handling

helper missing

显示：

⚠ Setup

不弹管理员窗口。

⸻

sudoers invalid

显示：

⚠ Error

日志记录：

permission denied

⸻

pmset command fails

不修改 UI 为目标状态。

重新读取真实状态。

⸻

state verification mismatch

例如请求：

AWAKE

但验证仍：

NORMAL

处理：

ERROR

绝不能显示虚假成功。

⸻

27. Restart Behaviour

应用启动时：

读取真实系统状态

不恢复 App 自己记录的旧状态。

禁止：

LastMode == Awake
→ force Awake

系统状态永远优先。

⸻

28. 安全要求

helper：

* root-owned
* 不可被普通用户修改
* command allowlist
* absolute executable path
* no shell expansion
* no dynamic path
* no eval
* no arbitrary Process arguments

sudoers：

只授权：

lidmode-helper

而不是：

pmset *

进一步避免参数注入。

⸻

29. Uninstall

必须提供 README 中的卸载命令。

卸载必须可以完全清理：

LidMode.app
/usr/local/libexec/lidmode-helper
/etc/sudoers.d/lidmode

同时取消 Login Item。

不得留下后台 daemon。

⸻

30. 项目目录

建议：

LidMode/
│
├── LidMode.xcodeproj
│
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

保持简单。

不要建立：

Clean Architecture
DDD
Repository Pattern
Dependency Container
Redux
MVVM framework

这些对于本项目全部属于不必要抽象。

⸻

31. PowerState

建议：

enum PowerState {
    case normal
    case awake
    case unknown
}

UI 状态：

enum DisplayState {
    case normal
    case awake
    case executing
    case unknown
    case error(String)
}

⸻

32. 测试要求

至少完成：

Unit Tests

pmset parser：

输入不同 pmset 输出。

测试：

SleepDisabled 1
SleepDisabled 0
missing key
unexpected whitespace
unexpected output

⸻

Integration Tests

helper：

status
on
status
off
status

结果：

NORMAL
AWAKE
NORMAL

⸻

33. 手工验收测试

必须在 Apple Silicon MacBook 上测试。

首要机器：

MacBook Air M2

测试矩阵：

Case 1

一般模式：

Normal
→ 合盖
→ Mac sleep

Case 2

禁止休眠：

Awake
→ 合盖
→ Mac remains operational

Case 3

Codex：

Start Codex task
→ Awake
→ close lid
→ wait
→ remotely inspect
→ task still running

Case 4

返回：

open lid
→ click Awake
→ Normal
→ close lid
→ system sleeps

Case 5

重启：

reboot
→ LidMode launches
→ displayed state equals actual pmset state

Case 6

helper failure：

temporarily remove helper
→ click
→ Error
→ no fake state

⸻

34. Definition of Done

只有满足以下全部条件才视为完成：

* [ ]	App 为原生 Swift
* [ ]	菜单栏只有一个控制按钮
* [ ]	无 Dock icon
* [ ]	无主窗口
* [ ]	单击 Normal → Awake
* [ ]	单击 Awake → Normal
* [ ]	状态来自真实系统状态
* [ ]	修改后再次验证
* [ ]	正常使用不要求密码
* [ ]	正常使用不要求 Touch ID
* [ ]	正常使用不弹 Terminal
* [ ]	正常使用不弹系统窗口
* [ ]	idle CPU 接近 0
* [ ]	无持续 polling
* [ ]	无 network
* [ ]	无 telemetry
* [ ]	无 Electron
* [ ]	无 Node
* [ ]	无 Python runtime
* [ ]	无常驻 helper daemon
* [ ]	helper 权限最小化
* [ ]	helper 不支持 arbitrary shell
* [ ]	M2 MacBook Air 实测通过
* [ ]	合盖 Codex 任务继续运行
* [ ]	恢复 Normal 后合盖正常睡眠
* [ ]	README 有安装方式
* [ ]	README 有完全卸载方式

⸻

35. 明确不做

V1 禁止加入：

* Timer
* Session duration
* App trigger
* CPU trigger
* Network trigger
* Battery trigger
* Auto Awake
* schedule
* profiles
* multiple modes
* settings window
* menu
* preferences UI
* remote control
* cloud sync
* iCloud
* telemetry
* auto update
* Sparkle
* notifications
* statistics
* history
* themes
* localization framework

如果不是实现：

Normal ↔ Awake

必需的，就不要做。

⸻

36. 产品最终形态

用户看到的全部产品应当接近：

Menu Bar
☾ Normal

点击：

● Awake

再次点击：

☾ Normal

至此结束。

产品成功标准不是功能多。

而是：

用户完全感觉不到它的存在，但每次点击都可靠工作。
