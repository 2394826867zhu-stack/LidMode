import AppKit

final class StatusBarController: NSObject {
  private let statusItem: NSStatusItem
  private let powerStateService: PowerStateService
  private let settings: SettingsStore
  private let onOpenSettings: () -> Void
  private let onPowerStateChanged: (PowerState) -> Void
  private var isExecuting = false
  private var currentDisplayState: DisplayState = .unknown
  private var launchTextVisible = true
  private var launchTextWorkItem: DispatchWorkItem?

  init(
    powerStateService: PowerStateService,
    settings: SettingsStore,
    onOpenSettings: @escaping () -> Void,
    onPowerStateChanged: @escaping (PowerState) -> Void
  ) {
    self.powerStateService = powerStateService
    self.settings = settings
    self.onOpenSettings = onOpenSettings
    self.onPowerStateChanged = onPowerStateChanged
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem.autosaveName = "LidModeStatusItem"
    super.init()

    guard let button = statusItem.button else { return }
    statusItem.isVisible = true
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    render(.unknown)
    applySettings()
  }

  func refresh() {
    guard !isExecuting else { return }
    isExecuting = true
    powerStateService.readState { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        self.isExecuting = false
        self.handle(result)
      }
    }
  }

  func applySettings() {
    launchTextWorkItem?.cancel()
    launchTextWorkItem = nil

    if settings.menuBarTextMode == .launchOnly {
      launchTextVisible = true
      let item = DispatchWorkItem { [weak self] in
        guard let self else { return }
        self.launchTextVisible = false
        self.render(self.currentDisplayState)
      }
      launchTextWorkItem = item
      DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: item)
    } else {
      launchTextVisible = true
    }
    render(currentDisplayState)
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }
    if event.type == .rightMouseUp {
      NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: sender)
    } else {
      togglePowerState()
    }
  }

  @objc private func toggleFromMenu() {
    togglePowerState()
  }

  @objc private func openSettings() {
    onOpenSettings()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func togglePowerState() {
    guard !isExecuting else { return }

    if currentDisplayState == .setupRequired {
      preparePrivilegedHelper()
      return
    }

    isExecuting = true
    render(.executing)
    powerStateService.toggle { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        self.isExecuting = false
        self.handle(result)
      }
    }
  }

  private func handle(_ result: Result<PowerState, PowerStateServiceError>) {
    if case .success(let state) = result {
      onPowerStateChanged(state)
    }
    render(result.displayState)
  }

  private func makeContextMenu() -> NSMenu {
    let menu = NSMenu()
    let status = NSMenuItem(
      title: "当前：\(currentDisplayState.presentation.statusTitle)", action: nil, keyEquivalent: ""
    )
    status.isEnabled = false
    menu.addItem(status)

    let toggleTitle = currentDisplayState == .awake ? "恢复 Normal" : "切换到 Awake"
    let toggleItem = NSMenuItem(
      title: toggleTitle, action: #selector(toggleFromMenu), keyEquivalent: "")
    toggleItem.target = self
    toggleItem.isEnabled = !isExecuting
    menu.addItem(toggleItem)
    menu.addItem(.separator())

    let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    menu.addItem(settingsItem)
    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "退出 LidMode", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)
    return menu
  }

  private func render(_ state: DisplayState) {
    guard let button = statusItem.button else { return }
    currentDisplayState = state
    let presentation = state.presentation
    let image = NSImage(
      systemSymbolName: presentation.symbolName,
      accessibilityDescription: presentation.accessibilityLabel
    )
    image?.isTemplate = true
    button.image = image
    button.imagePosition = image == nil ? .noImage : .imageLeading

    let showText = settings.menuBarTextMode == .always || launchTextVisible || image == nil
    button.title =
      showText
      ? (image == nil
        ? "\(presentation.fallbackTitle) \(presentation.statusTitle)" : presentation.statusTitle)
      : ""
    button.toolTip = "\(presentation.toolTip)；左键切换，右键打开菜单"
    button.setAccessibilityLabel(presentation.accessibilityLabel)
    statusItem.isVisible = true
  }

  private func preparePrivilegedHelper() {
    isExecuting = true
    render(.executing)

    powerStateService.preparePrivilegedHelper { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        self.isExecuting = false

        switch result {
        case .enabled:
          self.refresh()
        case .requiresApproval:
          self.powerStateService.openPrivilegedHelperSettings()
          self.render(.setupRequired)
        case .unavailable:
          self.render(.setupRequired)
        case .failed:
          self.render(.error("无法注册特权 Helper"))
        }
      }
    }
  }
}

struct DisplayPresentation: Equatable {
  let symbolName: String
  let fallbackTitle: String
  let statusTitle: String
  let accessibilityLabel: String
  let toolTip: String
}

extension DisplayState {
  var presentation: DisplayPresentation {
    switch self {
    case .normal:
      DisplayPresentation(
        symbolName: "moon", fallbackTitle: "☾", statusTitle: "Normal",
        accessibilityLabel: "LidMode：一般模式", toolTip: "一般模式：合盖将正常休眠"
      )
    case .awake:
      DisplayPresentation(
        symbolName: "bolt.fill", fallbackTitle: "●", statusTitle: "Awake",
        accessibilityLabel: "LidMode：保持唤醒", toolTip: "禁止休眠：合盖后 Mac 将继续运行"
      )
    case .executing:
      DisplayPresentation(
        symbolName: "hourglass", fallbackTitle: "…", statusTitle: "Working",
        accessibilityLabel: "LidMode：正在验证", toolTip: "正在验证系统睡眠状态"
      )
    case .unknown:
      DisplayPresentation(
        symbolName: "questionmark", fallbackTitle: "?", statusTitle: "Unknown",
        accessibilityLabel: "LidMode：状态未知", toolTip: "无法读取系统睡眠状态"
      )
    case .setupRequired:
      DisplayPresentation(
        symbolName: "exclamationmark.triangle.fill", fallbackTitle: "!", statusTitle: "Setup",
        accessibilityLabel: "LidMode：需要设置", toolTip: "点击注册签名 Helper，源码构建请运行安装脚本"
      )
    case .error(let message):
      DisplayPresentation(
        symbolName: "exclamationmark.triangle.fill", fallbackTitle: "!", statusTitle: "Error",
        accessibilityLabel: "LidMode：发生错误", toolTip: message
      )
    }
  }
}

extension Result where Success == PowerState, Failure == PowerStateServiceError {
  fileprivate var displayState: DisplayState {
    switch self {
    case .success(let state):
      switch state {
      case .normal: .normal
      case .awake: .awake
      case .unknown: .unknown
      }
    case .failure(let error):
      switch error {
      case .setupRequired: .setupRequired
      case .unreadableState: .unknown
      default: .error(error.displayMessage)
      }
    }
  }
}
