# LidMode

LidMode is a tiny native macOS menu bar app that exposes one system toggle:

```text
☾ Normal  → click →  ● Awake  → click →  ☾ Normal
```

It reads and changes the real macOS `SleepDisabled` power-management state. It does not keep a separate preference that can drift away from the system. Current macOS versions omit the `SleepDisabled` line when its value is the default `0`; LidMode recognizes that only when the rest of a complete `pmset -g` response is present. Partial output remains Unknown.

## Requirements

- Apple Silicon MacBook; primary target: MacBook Air M2
- macOS 13 or later
- Xcode 15 or later with the license accepted
- An administrator account for the one-time installation

LidMode has no third-party dependencies, network service, analytics, updater, database, or scripting runtime.

## Architecture

```text
LidMode.app
    └── /usr/bin/sudo -n /usr/local/libexec/lidmode-helper on|off|status
                                  └── /usr/bin/pmset
```

The GUI runs without root privileges. The installed helper is owned by `root:wheel`, accepts only `on`, `off`, or `status`, and invokes `/usr/bin/pmset` directly without a shell. The sudoers rule grants passwordless access to those three exact command lines only.

The menu bar controller follows `read → modify → verify → render`. An unsuccessful command or mismatched verification never renders a false success state.

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

Building the app alone does not install privileged files and therefore does not enable toggling yet.

## Install

From the repository root:

```bash
./Scripts/install.sh
```

The script builds the app and helper before requesting administrator approval. That one approval installs:

- `/Applications/LidMode.app`
- `/usr/local/libexec/lidmode-helper`, mode `755`, owner `root:wheel`
- `/etc/sudoers.d/lidmode`, mode `440`, owner `root:wheel`

It validates the sudoers syntax with `visudo`, verifies the installed permissions and signature, and confirms that `sudo -n ... status` works. If a privileged installation step fails, the script restores the previous LidMode installation or removes the partial new installation.

After installation, the app starts and registers itself as a login item with `SMAppService`. Depending on macOS policy, Login Items may show a system notification or require approval in **System Settings → General → Login Items**. Failure to register does not affect the toggle while the app is running.

## Use

LidMode has no window or menu. Click its text in the menu bar:

| Display | Meaning |
| --- | --- |
| `☾ Normal` | `SleepDisabled = 0`; normal system sleep policy |
| `● Awake` | `SleepDisabled = 1`; system sleep is disabled |
| `…` | A read, change, or verification is running |
| `? Unknown` | The system state could not be parsed |
| `⚠ Setup` | The restricted helper is not installed |
| `⚠ Error` | The operation or verification failed; hover for a short explanation |

The app reads state on launch, after a click, after modification, and when macOS wakes. It does not poll.

## Verify an installation

```bash
./Scripts/verify-install.sh
```

The command checks the exact install locations, ownership, modes, local app signature, passwordless helper access, and normalized state output.

## Tests

Unit tests cover `SleepDisabled` parsing, whitespace and malformed output, helper output parsing, the command allowlist, and the fixed helper path:

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

1. Run `./Scripts/install.sh` and confirm `☾ Normal` or `● Awake` appears without a Dock icon or application window.
2. Set `☾ Normal`, close the lid, and confirm the Mac sleeps.
3. Set `● Awake`, start a harmless long-running local task, close the lid, and verify from another device or after reopening that the task continued.
4. Return to `☾ Normal`, close the lid, and confirm normal sleep resumes.
5. Restart macOS and confirm LidMode launches and its displayed state matches `sudo -n /usr/local/libexec/lidmode-helper status`.
6. Temporarily move the helper aside using an administrator shell, click the status item, and confirm an error is shown without a password prompt or false state. Restore the helper afterward.
7. Observe idle CPU and memory in Activity Monitor. CPU should settle near zero with no continuing growth.

Physical lid behavior must be tested on the target hardware; it cannot be established by unit tests alone.

## Troubleshooting

### `⚠ Setup`

Run `./Scripts/install.sh`. Do not broaden the sudoers rule or grant `NOPASSWD: ALL`.

### `⚠ Error`

Run `./Scripts/verify-install.sh`. Common causes are a removed helper, changed ownership or modes, or a missing sudoers rule. Detailed operational events are available in Console under subsystem `app.lidmode.LidMode`; LidMode does not create log files.

### Login item is not enabled

Launch `/Applications/LidMode.app` once. If macOS requires approval, enable LidMode under **System Settings → General → Login Items**.

### Xcode reports that its license is not accepted

Open Xcode once and accept its license, or run Apple's documented `xcodebuild -license` flow as an administrator.

## Uninstall completely

From the repository root:

```bash
./Scripts/uninstall.sh
```

The script asks for administrator approval, unregisters the login item when possible, stops the app, and removes only these LidMode paths:

- `/Applications/LidMode.app`
- `/usr/local/libexec/lidmode-helper`
- `/etc/sudoers.d/lidmode`

LidMode installs no daemon and stores no user database. Uninstalling the app does not silently change the current `SleepDisabled` value; switch to `☾ Normal` before uninstalling if normal sleep is desired.

## Known limitations

- V1 targets Apple Silicon only.
- The local build is ad-hoc signed, not notarized for public binary distribution. Build from source on the target Mac.
- macOS can still enforce thermal, low-battery, shutdown, and other hardware safety behavior.
- Login item approval can depend on the macOS version and device-management policy.
- The app intentionally does not reset the system state when it quits or restarts.

## Security notes

- No shell is invoked by the app or helper.
- All executables and privileged paths are absolute and fixed.
- The app passes one value from a closed Swift enum; the helper repeats the allowlist check.
- The helper is not resident and no LaunchDaemon is installed.
- The app performs no network request and includes no telemetry.
- The sudoers rule names `on`, `off`, and `status` separately and never grants a shell or `pmset *` access.

See [PRD.md](PRD.md) for the product requirements and [AGENTS.md](AGENTS.md) for repository implementation guidance.
