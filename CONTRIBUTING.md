# Contributing to LidMode

Thank you for helping improve LidMode. The project deliberately stays small: it is a verified two-state macOS system toggle, not a general power-management suite.

## Before opening an issue

- Search existing issues and discussions.
- Use the bug template for reproducible defects and the feature template for narrowly scoped proposals.
- Never post passwords, signing certificates, private keys, personal files, or unredacted sensitive logs.
- For security-sensitive findings, follow [SECURITY.md](SECURITY.md) instead of filing a public issue.

## Development setup

Requirements:

- Apple Silicon Mac
- macOS 13 or later
- Xcode 15 or later

Open `LidMode.xcodeproj` in Xcode, or build from the command line:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build \
  -project LidMode.xcodeproj \
  -scheme LidMode \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/LidModeDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

## Required checks

Run these before submitting a pull request:

```bash
/bin/bash -n Scripts/*.sh Tests/helper-integration.sh
xcrun swift-format lint --recursive LidMode Helper PrivilegedHelper Shared Tests
plutil -lint LidMode/Info.plist PrivilegedHelper/app.lidmode.PrivilegedHelper.plist
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project LidMode.xcodeproj \
  -scheme LidMode \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/LidModeTests \
  CODE_SIGNING_ALLOWED=NO
```

The privileged integration test is intentionally opt-in because it changes the real system state. Run it only on a suitable test Mac and read its warning in [README.md](README.md) first.

## Pull-request expectations

- Keep changes focused and explain the user-visible outcome.
- Preserve `read → modify → verify → render`; never render an assumed success state.
- Do not broaden helper arguments, executable paths, sudoers permissions, or the privilege boundary.
- Avoid polling, third-party runtimes, networking, analytics, and unrelated power-management features.
- Add or update tests for behavior changes.
- Document hardware behavior honestly; automated tests cannot prove real closed-lid behavior.

By contributing, you agree that your contribution is licensed under the repository's [MIT License](LICENSE).
