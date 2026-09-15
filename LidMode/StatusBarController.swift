import AppKit

final class StatusBarController: NSObject {
  private let statusItem: NSStatusItem
  private let powerStateService: PowerStateService
  private var isExecuting = false

  init(powerStateService: PowerStateService) {
    self.powerStateService = powerStateService
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    guard let button = statusItem.button else { return }
    button.target = self
    button.action = #selector(statusItemClicked)
    button.sendAction(on: [.leftMouseUp])
    button.setAccessibilityLabel("LidMode sleep toggle")
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

    switch state {
    case .normal:
      button.title = "☾ Normal"
      button.toolTip = "一般模式：合盖将正常休眠"
    case .awake:
      button.title = "● Awake"
      button.toolTip = "禁止休眠：合盖后 Mac 将继续运行"
    case .executing:
      button.title = "…"
      button.toolTip = "正在验证系统睡眠状态"
    case .unknown:
      button.title = "? Unknown"
      button.toolTip = "无法读取系统睡眠状态"
    case .setupRequired:
      button.title = "⚠ Setup"
      button.toolTip = "需要运行 LidMode 安装脚本"
    case .error(let message):
      button.title = "⚠ Error"
      button.toolTip = message
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
