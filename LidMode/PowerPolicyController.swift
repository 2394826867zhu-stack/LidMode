import Foundation
import IOKit.ps

struct BatterySnapshot: Equatable {
  let percentage: Int
  let isOnBattery: Bool
}

enum BatteryProtectionPolicy {
  static func shouldRestoreNormal(
    snapshot: BatterySnapshot,
    enabled: Bool,
    threshold: Int
  ) -> Bool {
    enabled && snapshot.isOnBattery && snapshot.percentage <= threshold
  }
}

final class DisplayWakeController {
  private var activity: NSObjectProtocol?

  func update(powerState: PowerState, enabled: Bool) {
    let shouldBeActive = enabled && powerState == .awake
    if shouldBeActive, activity == nil {
      activity = ProcessInfo.processInfo.beginActivity(
        options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
        reason: "LidMode Awake display policy"
      )
      AppLog.power.info("Display wake assertion enabled")
    } else if !shouldBeActive {
      release()
    }
  }

  func release() {
    guard let activity else { return }
    ProcessInfo.processInfo.endActivity(activity)
    self.activity = nil
    AppLog.power.info("Display wake assertion released")
  }

  deinit {
    release()
  }
}

final class BatteryProtectionController {
  private let settings: SettingsStore
  private let powerStateService: PowerStateService
  private var runLoopSource: CFRunLoopSource?
  private var protectionLatched = false
  private var isEnforcing = false

  var onNormalRestored: (() -> Void)?

  init(settings: SettingsStore, powerStateService: PowerStateService) {
    self.settings = settings
    self.powerStateService = powerStateService
  }

  func start() {
    guard runLoopSource == nil else { return }
    let context = Unmanaged.passUnretained(self).toOpaque()
    guard
      let unmanagedSource = IOPSNotificationCreateRunLoopSource(
        { context in
          guard let context else { return }
          Unmanaged<BatteryProtectionController>.fromOpaque(context)
            .takeUnretainedValue()
            .evaluate()
        },
        context
      )
    else { return }

    let source = unmanagedSource.takeRetainedValue()
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    evaluate()
  }

  func stop() {
    guard let runLoopSource else { return }
    CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
    CFRunLoopSourceInvalidate(runLoopSource)
    self.runLoopSource = nil
  }

  func settingsDidChange() {
    protectionLatched = false
    evaluate()
  }

  func evaluate() {
    guard let snapshot = Self.currentBatterySnapshot() else { return }
    let shouldProtect = BatteryProtectionPolicy.shouldRestoreNormal(
      snapshot: snapshot,
      enabled: settings.batteryProtectionEnabled,
      threshold: settings.batteryThreshold
    )

    guard shouldProtect else {
      protectionLatched = false
      return
    }
    guard !protectionLatched, !isEnforcing else { return }

    protectionLatched = true
    isEnforcing = true
    AppLog.power.info("Battery protection restoring Normal")
    powerStateService.ensureNormal { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        self.isEnforcing = false
        if case .success(.normal) = result {
          self.onNormalRestored?()
        } else {
          self.protectionLatched = false
        }
      }
    }
  }

  static func currentBatterySnapshot() -> BatterySnapshot? {
    guard
      let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sourceList = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }

    for source in sourceList {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any],
        let current = description[kIOPSCurrentCapacityKey] as? Int,
        let maximum = description[kIOPSMaxCapacityKey] as? Int,
        maximum > 0,
        let powerSource = description[kIOPSPowerSourceStateKey] as? String
      else { continue }

      return BatterySnapshot(
        percentage: Int((Double(current) / Double(maximum) * 100).rounded()),
        isOnBattery: powerSource == kIOPSBatteryPowerValue
      )
    }
    return nil
  }

  deinit {
    stop()
  }
}
