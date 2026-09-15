# Security

## Privileged boundary

LidMode supports two mutually exclusive privileged transports:

1. Developer ID releases use an `SMAppService` LaunchDaemon. Both sides require
   the expected bundle identifier and the same Apple Developer Team ID before
   exchanging XPC messages. Missing signing identity is a hard failure.
2. Ad-hoc source builds use the installer-managed compatibility helper. Its
   sudoers entry permits only the fixed `on`, `off`, and `status` invocations.

Both helpers execute `/usr/bin/pmset` directly with fixed arguments. Neither
accepts an executable path, shell fragment, environment-derived command, or
arbitrary argument. A state change is successful only after `pmset -g` reports
the requested state.

## Reporting a vulnerability

Do not include secrets, credentials, personal files, or exploit payloads in a
public issue. Contact the repository owner privately with the affected commit,
reproduction conditions, and impact. Until a dedicated security contact is
published, use GitHub's private vulnerability reporting feature when available.

## Operational safety

Awake mode can consume battery and generate heat while the lid is closed. Lock
the screen before leaving the Mac unattended, do not run sustained heavy work
inside a closed bag, and return to `☾ Normal` when the task finishes.
