import AppKit

final class SettingsWindowController: NSWindowController {
  private let settings: SettingsStore
  private let loginItemService: LoginItemService

  private lazy var launchAtLoginButton = checkbox(
    title: "登录时自动启动",
    action: #selector(launchAtLoginChanged)
  )
  private lazy var keepDisplayAwakeButton = checkbox(
    title: "Awake 时保持屏幕点亮",
    action: #selector(keepDisplayAwakeChanged)
  )
  private lazy var batteryProtectionButton = checkbox(
    title: "低电量时自动恢复 Normal",
    action: #selector(batteryProtectionChanged)
  )
  private let thresholdStepper = NSStepper()
  private let thresholdLabel = NSTextField(labelWithString: "")
  private let menuBarModePopup = NSPopUpButton()
  private let statusLabel = NSTextField(wrappingLabelWithString: "")

  init(settings: SettingsStore, loginItemService: LoginItemService) {
    self.settings = settings
    self.loginItemService = loginItemService

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 310),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "LidMode 设置"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    buildContent()
    reload()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    reload()
    window?.center()
    showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func buildContent() {
    guard let contentView = window?.contentView else { return }

    thresholdStepper.minValue = 5
    thresholdStepper.maxValue = 50
    thresholdStepper.increment = 5
    thresholdStepper.target = self
    thresholdStepper.action = #selector(thresholdChanged)

    for mode in MenuBarTextMode.allCases {
      menuBarModePopup.addItem(withTitle: mode.title)
    }
    menuBarModePopup.target = self
    menuBarModePopup.action = #selector(menuBarModeChanged)

    statusLabel.textColor = .secondaryLabelColor
    statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

    let thresholdRow = NSStackView(views: [thresholdLabel, thresholdStepper])
    thresholdRow.orientation = .horizontal
    thresholdRow.alignment = .centerY
    thresholdRow.spacing = 8

    let menuBarLabel = NSTextField(labelWithString: "菜单栏状态文字")
    menuBarLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

    let stack = NSStackView(views: [
      sectionTitle("启动"),
      launchAtLoginButton,
      separator(),
      sectionTitle("Awake 行为"),
      keepDisplayAwakeButton,
      batteryProtectionButton,
      thresholdRow,
      separator(),
      sectionTitle("外观"),
      menuBarLabel,
      menuBarModePopup,
      statusLabel,
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 9
    stack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
      menuBarModePopup.widthAnchor.constraint(equalToConstant: 220),
      statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }

  private func reload() {
    launchAtLoginButton.state = settings.launchAtLogin ? .on : .off
    keepDisplayAwakeButton.state = settings.keepDisplayAwake ? .on : .off
    batteryProtectionButton.state = settings.batteryProtectionEnabled ? .on : .off
    thresholdStepper.integerValue = settings.batteryThreshold
    menuBarModePopup.selectItem(at: settings.menuBarTextMode.rawValue)
    updateThresholdUI()
    statusLabel.stringValue = "屏幕保持仅在 Awake 生效；电量保护仅在使用电池时触发。"
  }

  @objc private func launchAtLoginChanged() {
    let requested = launchAtLoginButton.state == .on
    guard loginItemService.setEnabled(requested) else {
      launchAtLoginButton.state = settings.launchAtLogin ? .on : .off
      statusLabel.stringValue = "无法修改登录启动项，请检查系统设置中的登录项权限。"
      return
    }
    settings.launchAtLogin = requested
    statusLabel.stringValue = requested ? "已启用登录时自动启动。" : "已关闭登录时自动启动。"
  }

  @objc private func keepDisplayAwakeChanged() {
    settings.keepDisplayAwake = keepDisplayAwakeButton.state == .on
  }

  @objc private func batteryProtectionChanged() {
    settings.batteryProtectionEnabled = batteryProtectionButton.state == .on
    updateThresholdUI()
  }

  @objc private func thresholdChanged() {
    settings.batteryThreshold = thresholdStepper.integerValue
    updateThresholdUI()
  }

  @objc private func menuBarModeChanged() {
    settings.menuBarTextMode =
      MenuBarTextMode(rawValue: menuBarModePopup.indexOfSelectedItem) ?? .always
  }

  private func updateThresholdUI() {
    thresholdLabel.stringValue = "保护阈值：\(settings.batteryThreshold)%"
    thresholdStepper.isEnabled = settings.batteryProtectionEnabled
    thresholdLabel.textColor =
      settings.batteryProtectionEnabled ? .labelColor : .disabledControlTextColor
  }

  private func checkbox(title: String, action: Selector) -> NSButton {
    NSButton(checkboxWithTitle: title, target: self, action: action)
  }

  private func sectionTitle(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    return label
  }

  private func separator() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    return box
  }
}
