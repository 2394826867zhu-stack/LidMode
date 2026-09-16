# Security

## Supported versions

Security fixes are maintained on the `main` branch. The latest source version is the only supported
version until the project establishes a broader release policy. LidMode does not currently publish
prebuilt public binaries.

## Privileged boundary

LidMode supports two privileged transports. The signed XPC transport is preferred
whenever its service is enabled; the source-install transport is the compatibility fallback:

1. Developer ID releases use an `SMAppService` LaunchDaemon. Both sides require
   the expected bundle identifier and the same Apple Developer Team ID before
   exchanging XPC messages. Missing signing identity is a hard failure.
2. Ad-hoc source builds use the installer-managed compatibility helper. Its
   sudoers entry permits only the fixed `on`, `off`, and `status` invocations.

Both helpers execute `/usr/bin/pmset` directly with fixed arguments. Neither
accepts an executable path, shell fragment, environment-derived command, or
arbitrary argument. A state change is successful only after `pmset -g` reports
the requested state.

Every child-process invocation has a finite timeout. The signed helper exits after its last XPC
connection has remained closed for an idle grace period, so no privileged process is intentionally
kept resident while the app is idle.

## Reporting a vulnerability

Do not include secrets, credentials, personal files, or exploit payloads in a public issue. Use
[GitHub private vulnerability reporting](https://github.com/2394826867zhu-stack/LidMode/security/advisories/new)
with the affected commit, reproduction conditions, and impact. Allow the maintainer reasonable
time to investigate and coordinate a fix before public disclosure.

## Operational safety

Awake mode can consume battery and generate heat while the lid is closed. Lock
the screen before leaving the Mac unattended, do not run sustained heavy work
inside a closed bag, and return to `☾ Normal` when the task finishes.

The uninstaller always restores and verifies normal sleep before removing the helper. It obtains
administrator authorization before changing app or login-item state and restores moved files if a
later removal step fails.
