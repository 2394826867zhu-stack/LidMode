# LidMode Full Audit

Audit date: 2026-09-16  
Audited commit: `302e6f3`  
Target: Apple Silicon macOS, with a MacBook Air M2 as the primary acceptance device

## Executive summary

The audited build was a functional MVP, but it was not ready to be described as a completed
production release. The core `Normal <-> Awake` path worked and the installed compatibility
helper had the intended narrow sudo authorization. The main release risks were unsafe uninstall
semantics, incomplete installation verification, no timeout in the compatibility transport, and
very limited coverage of the production privilege boundary.

Baseline score: **6.5 / 10**

| Area | Baseline |
| --- | ---: |
| Architecture | 8.0 |
| Core toggle behavior | 8.0 |
| Privilege-boundary design | 7.0 |
| Code readability | 8.0 |
| Installation | 6.0 |
| Uninstallation | 4.0 |
| Automated-test confidence | 4.5 |
| Production readiness | 5.5 |

## Evidence collected

- All 15 XCTest cases passed.
- Xcode static analysis and a Release build passed.
- Swift formatting, shell syntax, property lists, and repository integrity checks passed.
- The installed helper completed `NORMAL -> AWAKE -> NORMAL`; the final state was restored to
  `NORMAL`.
- The installed sudoers policy allowed exactly `on`, `off`, and `status` during the manual audit,
  and an injected argument was rejected.
- The app was idle at approximately 0% CPU, made no network connections, and had no third-party
  runtime dependencies.
- The GitHub CI run for the audited commit passed.

Baseline application coverage was 17.54%. `PowerState.swift` reached 89.06%, while
`PowerStateService.swift`, `LoginItemService.swift`, and the XPC helper service had no effective
behavioral coverage. `HelperClient.swift` reached only 3.45%.

## Findings and remediation tracking

| ID | Severity | Finding | Status |
| --- | --- | --- | --- |
| LM-001 | P1 | Uninstall could remove the recovery mechanism while `SleepDisabled=1` remained active. | Resolved: uninstall restores and verifies Normal first. |
| LM-002 | P1 | Installation verification did not prove the exact sudoers policy and could report a false PASS. | Resolved: exact policy, identity, mode, integrity, and negative-argument checks added. |
| LM-003 | P1 | Green tests covered parsers far more than the production privilege and state-machine paths. | Mitigated: application coverage increased from 17.54% to 40.10%; the service reached 76.54%. Signed XPC still needs release acceptance. |
| LM-004 | P2 | The restricted-sudo transport waited forever if its child process stalled. | Resolved: finite timeout and forced termination added to all process paths. |
| LM-005 | P2 | Uninstall mutated login state before authorization, killed every process named `LidMode`, and silently ignored privileged-helper unregistration failures. | Resolved: authorization-first flow, exact process targeting, surfaced errors, and file rollback. |
| LM-006 | P2 | The signed root helper had no explicit idle-exit policy. | Resolved: connection-counted idle exit added. |
| LM-007 | P2 | The installer reported success without confirming that the installed app remained running. | Resolved: launch and process-liveness gate added before commit. |
| LM-008 | P3 | The parser's omitted-key fallback accepted a relatively weak approximation of a complete `pmset -g` response. | Resolved: at least two recognized settings are now required; truncated-output test added. |
| LM-009 | P3 | The release workflow did not exercise a signed SMAppService/XPC round trip. | Partially mitigated: tag releases now rerun tests and verify matching non-empty Team IDs. A real approved XPC round trip remains a manual release gate. |
| LM-010 | P2 | Installation assumed an interactive terminal and could not use a secure macOS askpass prompt. | Resolved after installation testing: install, verify, rollback, and uninstall consistently honor `SUDO_ASKPASS` via `sudo -A`. |

## Required release gates

1. Uninstall must restore and verify `NORMAL` before removing either helper.
2. Verification must compare the installed sudoers file with the exact expected policy, validate it
   with `visudo`, check the application identity and agent-only configuration, and reject invalid
   helper arguments.
3. Every synchronous child process must have a finite timeout.
4. The privileged helper must terminate after an idle grace period.
5. Tests must exercise the service state machine, failure mapping, timeout path, and packaging
   invariants.
6. Installation must confirm that the installed executable remains alive after launch.
7. A public signed release still requires a real Developer ID build, notarization, and a manual
   SMAppService/XPC acceptance run on the target Mac.

## Security strengths retained

- No app or helper shell invocation.
- Fixed absolute executable paths and a closed command set.
- Root-owned compatibility helper and sudoers policy.
- Read-modify-verify-render behavior; command exit alone is never treated as success.
- Team-ID and bundle-identifier checks on both sides of the signed XPC connection.
- No polling, network service, telemetry, analytics, or third-party runtime.

## Remediation verification

- 23 XCTest cases passed after remediation.
- Application line coverage increased from 17.54% to 40.10%.
- `PowerStateService.swift` increased from 0% to 76.54%; its successful toggle path is fully
  exercised.
- `HelperClient.runProcess` reached 88.89%, including a real timeout/termination test.
- Debug and Release builds passed, and Xcode static analysis reported no findings.
- Swift formatting, shell syntax, property lists, helper allowlist behavior, and diff whitespace
  checks passed.
- A real installation attempt confirmed that canceled authorization leaves the existing installation
  untouched; the resulting no-terminal authorization defect was fixed with consistent askpass
  support.
- The remediated source build was then installed on the target MacBook Air. Both pre-launch and
  post-launch installation verification passed, the menu-bar process remained alive at 0.0% CPU
  and approximately 0.3% memory, and no network socket was open.
- The installed helper completed the real `NORMAL -> AWAKE -> NORMAL` integration sequence. The
  final state was independently read back as `NORMAL`.
- Installed ownership and modes were confirmed as `root:wheel 755` for the app and compatibility
  helper and `root:wheel 440` for the sudoers file. The effective passwordless rule remained limited
  to the exact `on`, `off`, and `status` helper invocations.

Post-remediation assessment: **8.2 / 10**. The remaining material release limitation is the lack of
a Developer-ID-signed, administrator-approved SMAppService/XPC acceptance run. That cannot be
truthfully replaced by an ad-hoc CI build.

## Audit limitations

The baseline audit did not include a real Developer ID certificate or notarized build. Therefore it
could inspect the signed-helper design and packaging, but could not prove the production
SMAppService approval and XPC round trip. `shellcheck`, `semgrep`, and `gitleaks` were not installed;
equivalent targeted syntax, source, secret, and command-boundary checks were performed with the
available native tools.

## Feature expansion review — 2026-09-16

The settings expansion preserves the original privilege boundary and system-state source of truth.
Preferences control policy and presentation only; they do not replace the verified `pmset` state.

- The context menu is created on demand and ends with Quit. Left-click retains the one-action toggle.
- Login-item changes use `SMAppService`; no custom LaunchAgent was introduced.
- The display-wake option uses one scoped `ProcessInfo` activity only while both enabled and Awake,
  and releases it on Normal and application termination.
- Battery protection uses the IOKit power-source notification run-loop source, not a timer. It acts
  only on battery, clamps the threshold to 5%–50%, and calls an idempotent read/disable/verify path.
- Repeated low-battery notifications are latched, while a new attempt to enter Awake re-evaluates the
  policy so the protection cannot be bypassed merely by toggling again.
- The original two-state menu-bar text option used a one-shot task and never removed the status
  item, preserving access to settings and Quit. Version 1.2 replaces this with the audited
  three-state behavior described below.

Verification after this change: Debug build passed and all 28 XCTest cases passed with zero failures,
including new safe-default, threshold-clamping, battery-policy, and idempotent Normal-restoration
tests. Physical display sleep, login startup, battery notification, and lid behavior remain hardware
acceptance items rather than claims established by unit tests.

The Release build and Xcode static analysis also passed. The updated source build was installed
transactionally; both pre-launch and post-launch verification passed, the process remained alive,
and the independently read system state remained `NORMAL`. A real right-click UI check confirmed the
visible hierarchy `current state → toggle → Settings → Quit`, with Quit last. No preference was
changed during that acceptance check.

## Full audit — version 1.2.0 / build 3

Audit date: 2026-09-16

### Outcome

No new P0, P1, or P2 defect was found after the menu-bar text-mode change. The implementation keeps
the status icon present in all modes, retains the verified system state as the source of truth, and
adds no repeating timer, polling loop, network dependency, or privilege expansion.

Current assessment: **8.7 / 10**. The remaining material production limitation is unchanged: a
public release still needs Developer ID signing, notarization, and a real administrator-approved
SMAppService/XPC acceptance run. Physical lid, screen-idle, and battery-delivery behavior also remain
hardware acceptance items.

### Code and behavior review

- The modes are `always`, `switching`, and `hidden`, backed by stable integer values. The previous
  stored value `1` migrates naturally from launch-only behavior to the new switching-only behavior.
- Switching-only mode reveals text during a user or battery-protection transition and for three
  seconds after verification. A single cancelable `DispatchWorkItem` performs the delayed hide; it
  is not a repeating timer.
- Hidden mode suppresses text even during switching. If an SF Symbol cannot be created, the fallback
  title remains visible so the status item cannot collapse into an inaccessible zero-content item.
- Settings changes cancel any pending text-hide task before rendering the newly selected policy.
- Hover help now equals the state-specific explanation exactly. The former left-click/right-click
  instruction suffix is absent.
- Battery-triggered restoration requests a transient status reveal only in switching-only mode; it
  does not alter the behavior of always-visible or hidden mode.

### Verification evidence

- 30 XCTest cases passed, with zero failures, skips, warnings, or test errors. New tests cover all
  three persisted modes and every visibility-policy branch, including the missing-image fallback.
- Debug compilation, Release compilation, and Xcode static analysis passed. The first local compile
  exposed a Swift 5 explicit-return error in the new policy function; it was corrected before the
  successful full matrix and is recorded here rather than omitted.
- Swift format lint, shell syntax, property-list validation, embedded-helper packaging, and Git diff
  whitespace checks passed.
- Targeted secret scanning found no disclosed credential or common embedded-secret assignment.
- Targeted source scanning found no timer, network client, or socket API. The Release executable
  links only Apple system frameworks and Swift runtime libraries.
- Transactional installation passed both pre-launch and post-launch verification. Installed version
  is `1.2.0` build `3`; the process remained alive at 0.0% CPU and approximately 0.6% memory, with no
  open network socket observed.
- Accessibility inspection opened the real settings window and confirmed exactly three options:
  `始终显示状态文字`, `仅切换时显示状态文字`, and `隐藏状态文字`.
- A real menu-bar transition confirmed switching-only behavior: `Normal` was visible immediately,
  the label disappeared after four seconds while the tooltip remained state-specific, `Awake` was
  visible during the return transition, and the independently read final system state was restored
  to `NORMAL`.

### Remaining limitations

- The three-second UI transition is covered by policy tests and a real accessibility acceptance run,
  but not by a long-running automated AppKit UI-test target.
- Screen locking, managed-device policy, thermal shutdown, and critical-battery behavior remain under
  macOS control and are intentionally not bypassed.
