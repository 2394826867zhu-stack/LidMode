import AppKit

final class StatusBarController: NSObject {
  private let statusItem: NSStatusItem
  private let powerStateService: PowerStateService
  private var isExecuting = false
  private var currentDisplayState: DisplayState = .unknown

  init(powerStateService: PowerStateService) {
    self.powerStateService = powerStateService
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem.autosaveName = "LidModeStatusItem"
    super.init()

    guard let button = statusItem.button else { return }
    statusItem.isVisible = true
    button.target = self
    button.action = #selector(statusItemClicked)
    button.sendAction(on: [.leftMouseUp])
    render(.unknown)
  }

  func refresh() {
    guard !isExecuting else { return }
    isExecuting = true
    powerStateService.readState { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        self.isExecuting = false
        self.render(result.displayState)
      }
    }
  }

  @objc private func statusItemClicked() {
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
        self.render(result.displayState)
      }
    }
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
    button.title =
      image == nil
      ? "\(presentation.fallbackTitle) \(presentation.statusTitle)"
      : presentation.statusTitle
    button.toolTip = presentation.toolTip
    button.setAccessibilityLabel(presentation.accessibilityLabel)
    statusItem.isVisible = true

    DispatchQueue.main.async { [weak self, weak button] in
      guard let self, let button else { return }
      let frame = button.window.map { NSStringFromRect($0.frame) } ?? "none"
      AppLog.lifecycle.info(
        "Status item rendered; visible=\(self.statusItem.isVisible, privacy: .public), frame=\(frame, privacy: .public)"
      )
    }
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
        symbolName: "moon",
        fallbackTitle: "☾",
        statusTitle: "Normal",
        accessibilityLabel: "LidMode：一般模式",
        toolTip: "一般模式：合盖将正常休眠"
      )
    case .awake:
      DisplayPresentation(
        symbolName: "bolt.fill",
        fallbackTitle: "●",
        statusTitle: "Awake",
        accessibilityLabel: "LidMode：保持唤醒",
        toolTip: "禁止休眠：合盖后 Mac 将继续运行"
      )
    case .executing:
      DisplayPresentation(
        symbolName: "hourglass",
        fallbackTitle: "…",
        statusTitle: "Working",
        accessibilityLabel: "LidMode：正在验证",
        toolTip: "正在验证系统睡眠状态"
      )
    case .unknown:
      DisplayPresentation(
        symbolName: "questionmark",
        fallbackTitle: "?",
        statusTitle: "Unknown",
        accessibilityLabel: "LidMode：状态未知",
        toolTip: "无法读取系统睡眠状态"
      )
    case .setupRequired:
      DisplayPresentation(
        symbolName: "exclamationmark.triangle.fill",
        fallbackTitle: "!",
        statusTitle: "Setup",
        accessibilityLabel: "LidMode：需要设置",
        toolTip: "点击注册签名 Helper，源码构建请运行安装脚本"
      )
    case .error(let message):
      DisplayPresentation(
        symbolName: "exclamationmark.triangle.fill",
        fallbackTitle: "!",
        statusTitle: "Error",
        accessibilityLabel: "LidMode：发生错误",
        toolTip: message
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
