# LidMode

LidMode is a tiny native macOS menu bar app centered on one system toggle:

```text
☾ Normal  → click →  ● Awake  → click →  ☾ Normal
```

It reads and changes the real macOS `SleepDisabled` power-management state. It does not keep a separate preference that can drift away from the system. Current macOS versions omit the `SleepDisabled` line when its value is the default `0`; LidMode recognizes that only when the rest of a complete `pmset -g` response is present. Partial output remains Unknown.

## Requirements

- Apple Silicon MacBook; primary target: MacBook Air M2
- macOS 13 or later
- Xcode 15 or later with the license accepted when building from source
- An administrator account with a password for the source-install fallback

LidMode has no third-party dependencies, network service, analytics, updater, database, or scripting runtime.

## Architecture

```text
LidMode.app
    ├── signed release → Team-ID-pinned XPC → embedded root helper → /usr/bin/pmset
    └── source fallback → sudo -n → /usr/local/libexec/lidmode-helper → /usr/bin/pmset
```

The GUI always runs without root privileges. A Developer ID release uses an embedded `SMAppService` LaunchDaemon and an XPC connection constrained in both directions to LidMode's bundle identifiers and signing Team ID. Authentication fails closed if either process has no Team ID. The helper exposes only status and Boolean state-setting operations, invokes `/usr/bin/pmset` using a fixed absolute path, verifies the resulting system state, and exits after its last connection has remained closed for an idle grace period.

Ad-hoc source builds cannot activate Apple's signed privileged-helper path. For those builds, the installer provides the original compatibility backend: a `root:wheel` helper accepting only `on`, `off`, or `status`, plus a sudoers rule granting those three exact command lines. The app prefers XPC whenever the signed helper is enabled and never silently falls back after an XPC failure.

The menu bar controller follows `read → modify → verify → render`. An unsuccessful command or mismatched verification never renders a false success state. Battery protection listens to IOKit power-source change events, and display wake uses a scoped native activity assertion; neither feature introduces a polling loop.

## Build in Xcode

Open `LidMode.xcodeproj`, select the `LidMode` scheme, and build for `My Mac`.

Command-line build:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project LidMode.xcodeproj \
  -scheme LidMode \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Debug \
  -derivedDataPath /tmp/LidModeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Building the app produces an app bundle containing the privileged helper and LaunchDaemon property list. An ad-hoc build cannot register that helper and therefore needs the source-install fallback below.

## Install a signed release

After a Developer ID release has been published:

1. Download `LidMode-<version>.zip` from GitHub Releases.
2. Move `LidMode.app` to `/Applications` and launch it.
3. When `⚠ Setup` appears, click it once.
4. Approve LidMode under **System Settings → General → Login Items & Extensions**.
5. Click the status item again. It will read the real state before allowing a toggle.

This path does not install a sudoers rule. It requires a properly signed and notarized release; an ad-hoc local build intentionally cannot impersonate the production helper.

## Install from source

From the repository root:

```bash
./Scripts/install.sh
```

The script builds the app and helper before requesting administrator approval. That one approval installs:

- `/Applications/LidMode.app`
- `/usr/local/libexec/lidmode-helper`, mode `755`, owner `root:wheel`
- `/etc/sudoers.d/lidmode`, mode `440`, owner `root:wheel`

It validates the sudoers syntax and exact three-command policy, verifies application identity, agent-only mode, permissions, signature, and helper integrity, confirms that `sudo -n ... status` works, then launches the app and confirms that the installed process remains active. If a privileged installation step fails, the script restores the previous LidMode installation or removes the partial new installation.

After installation, the app starts and enables its login item with `SMAppService` by default. This can be changed in LidMode settings. Depending on macOS policy, Login Items may show a system notification or require approval in **System Settings → General → Login Items**. Failure to register does not affect the toggle while the app is running.

## Build a simple M2 share package

For a trusted recipient with a similar Apple Silicon Mac who does not have Xcode, build a precompiled offline package:

```bash
./Scripts/build-share-package.sh /path/to/output
```

The output contains `LidMode-<version>-M2.zip` and its SHA-256 file. The recipient extracts the ZIP, right-clicks `安装 LidMode.command`, chooses Open, and enters their Mac login password once. The package installs the same app, restricted helper, exact sudoers policy, settings, login item, verification, and rollback behavior as the source installer. It also includes a clickable uninstaller.

This package is ad-hoc signed rather than Developer-ID signed. The first right-click/Open is therefore unavoidable. The installer removes quarantine only from the installed LidMode bundle after the user has explicitly launched the installer; it does not disable Gatekeeper or change global security settings.

## Use

Left-click the menu bar item to switch directly between Normal and Awake. Right-click it for a compact menu containing the current state, the toggle action, Settings, and Quit. Quit is always the final menu item.

| Display | Meaning |
| --- | --- |
| `☾ Normal` | `SleepDisabled = 0`; normal system sleep policy |
| `● Awake` | `SleepDisabled = 1`; system sleep is disabled |
| `…` | A read, change, or verification is running |
| `? Unknown` | The system state could not be parsed |
| `⚠ Setup` | No usable helper is available; click to register a signed embedded helper, or use the source installer |
| `⚠ Error` | The operation or verification failed; hover for a short explanation |

The settings window provides:

- Launch at login, enabled by default.
- Keep the display awake while LidMode is in Awake mode, disabled by default. The assertion is released immediately when returning to Normal or when LidMode exits.
- Battery protection, enabled by default at 20% and adjustable from 5% to 50%. While running on battery at or below the threshold, LidMode restores and verifies Normal. Protection can be disabled.
- Menu bar status text has three modes: always visible, visible only while switching and for three seconds after verification, or hidden. The icon itself remains available in every mode so the app cannot become inaccessible.

Hover text contains only the current state explanation. Interaction instructions are intentionally kept out of the tooltip.

The app reads state on launch, after an action, after modification, and when macOS wakes. Battery changes come from system notifications. It does not poll.

## Verify an installation

```bash
./Scripts/verify-install.sh
```

For a source installation, the command checks the exact install locations, ownership, modes, bundle identity, `LSUIElement`, local app signature, helper argument rejection, exact sudoers policy, passwordless helper access, and normalized state output. Reading the root-owned sudoers file requires administrator approval.

## Tests

Unit tests cover `SleepDisabled` parsing, whitespace, truncated and malformed output, helper output parsing, the command allowlist, process timeout handling, the read-modify-verify state machine, failure recovery, fixed identifiers and paths, and presence of the embedded privileged helper:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project LidMode.xcodeproj \
  -scheme LidMode \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/LidModeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The privileged integration test deliberately changes the real system state. It is opt-in, requires an installed helper, captures the initial state, and restores it on exit:

```bash
LIDMODE_RUN_PRIVILEGED_TESTS=1 ./Tests/helper-integration.sh
```

Do not run the integration test while another process depends on a particular sleep policy.

## Manual acceptance on a MacBook Air M2

1. Run `./Scripts/install.sh` and confirm `☾ Normal` or `● Awake` appears without a Dock icon.
2. Right-click the item, confirm the compact menu opens and `退出 LidMode` is last, then open Settings and verify each control persists.
3. Set `☾ Normal`, close the lid, and confirm the Mac sleeps.
4. Set `● Awake`, start a harmless long-running local task, close the lid, and verify from another device or after reopening that the task continued.
   Lock the screen first with Control–Command–Q if the Mac will be left unattended.
5. Enable display wake, enter Awake, and verify idle display sleep is inhibited; return to Normal and verify the assertion is gone.
6. Test battery protection at a safe temporary threshold above the current battery percentage while disconnected from power; verify Awake automatically returns to Normal, then restore the desired threshold.
7. Return to `☾ Normal`, close the lid, and confirm normal sleep resumes.
8. Restart macOS and confirm LidMode launches and its displayed state matches `sudo -n /usr/local/libexec/lidmode-helper status`.
9. Temporarily move the helper aside using an administrator shell, click the status item, and confirm an error is shown without a password prompt or false state. Restore the helper afterward.
10. Observe idle CPU and memory in Activity Monitor. CPU should settle near zero with no continuing growth.

Physical lid behavior must be tested on the target hardware; it cannot be established by unit tests alone.

## Troubleshooting

### `⚠ Setup`

For a signed release, click `⚠ Setup` and approve LidMode under **System Settings → General → Login Items & Extensions**. For an ad-hoc source build, run `./Scripts/install.sh`. Do not broaden the sudoers rule or grant `NOPASSWD: ALL`.

### `⚠ Error`

Run `./Scripts/verify-install.sh`. Common causes are a removed helper, changed ownership or modes, or a missing sudoers rule. Detailed operational events are available in Console under subsystem `io.github.2394826867zhu-stack.LidMode`; LidMode does not create log files.

### The app runs but no menu bar icon appears

On macOS 26 or later, check **System Settings → Menu Bar → Allow in the Menu Bar** and make sure LidMode is enabled. macOS controls this visibility independently of the app; `NSStatusItem.isVisible` can still report `true` when the item is hidden by the system. LidMode uses a stable, project-specific bundle identifier so its permission is not shared with another app.

### Login item is not enabled

Launch `/Applications/LidMode.app` once. If macOS requires approval, enable LidMode under **System Settings → General → Login Items**.

### Xcode reports that its license is not accepted

Open Xcode once and accept its license, or run Apple's documented `xcodebuild -license` flow as an administrator.

## Uninstall completely

From the repository root:

```bash
./Scripts/uninstall.sh
```

The script asks for administrator approval first, restores and verifies normal sleep, unregisters the login item and embedded privileged helper, stops only the executable at the installed LidMode path, and transactionally moves the following files out of place before deleting them:

- `/Applications/LidMode.app`
- `/usr/local/libexec/lidmode-helper`
- `/etc/sudoers.d/lidmode`

The signed helper is managed visibly by macOS under Login Items & Extensions and is unregistered before the app is removed. If a file operation fails, moved files are restored. LidMode stores no user database. Uninstall intentionally returns `SleepDisabled` to `0` so removing the recovery mechanism can never leave the Mac stuck in Awake mode.

## Signed releases

`.github/workflows/release.yml` builds the app and embedded helper with the same Developer ID Team, verifies both signatures, submits the app to Apple's notarization service, staples the ticket, and attaches a ZIP to a tag-based GitHub Release. It requires these repository secrets:

- `MACOS_CERTIFICATE`: base64-encoded Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `DEVELOPMENT_TEAM`
- `NOTARY_KEY_P8`: base64-encoded App Store Connect API key
- `NOTARY_KEY_ID`
- `NOTARY_ISSUER_ID`

After configuring them, pushing a version tag such as `v1.0.0` produces the release. CI independently runs unit tests, a Release build, and embedded-helper packaging checks on every push and pull request.

## Known limitations

- V1 targets Apple Silicon only.
- A public binary is not available until the repository owner configures Apple Developer signing secrets and pushes the first version tag.
- The source installer requires a non-empty administrator password because macOS `sudo` rejects passwordless administrator accounts.
- macOS can still enforce thermal, low-battery, shutdown, and other hardware safety behavior.
- Battery protection depends on LidMode remaining running and on macOS delivering power-source events; it is a recovery aid, not a substitute for hardware safeguards. Do not leave sustained heavy workloads running in a closed bag.
- “Keep display awake” prevents idle display/system sleep while Awake, but does not override lock-screen, managed-device, shutdown, thermal, or critical-battery policies.
- Login item approval can depend on the macOS version and device-management policy.
- The app intentionally does not reset the system state when it quits or restarts. Complete uninstall is different: it always restores normal sleep before removing the helpers.

## Security notes

- No shell is invoked by the app or helper.
- All executables and privileged paths are absolute and fixed.
- The app passes one value from a closed Swift enum; the helper repeats the allowlist check.
- The production LaunchDaemon is loaded on demand by macOS and accepts only correctly signed LidMode clients. The source fallback is not resident.
- XPC authentication is fail-closed when a Team ID cannot be established.
- The app performs no network request and includes no telemetry.
- The sudoers rule names `on`, `off`, and `status` separately and never grants a shell or `pmset *` access.

See [PRD.md](PRD.md) for the product requirements, [AUDIT.md](AUDIT.md) for the evidence-backed audit and remediation record, [AGENTS.md](AGENTS.md) for repository implementation guidance, [SECURITY.md](SECURITY.md) for the threat model, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution.
