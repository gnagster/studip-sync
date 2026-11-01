# StudSync roadmap

## Operating plan

Build native Swift, retaining Python as a reference until native parity is proven. Development runs are manual; the owner explicitly instructed that no development schedule be created. Development creates/updates PRs only. Existing automatic review on every push follows `AGENTS.md`: repair, test, push, re-review, then merge a clean current revision when the integration supports those actions. No separate reviewer, security scheduler, merge bot, or OpenAI API usage.

## Milestones

- [ ] Foundation: complete instructions, CI, dependency updates, build/run action, and manual development workflow. Establish whether automatic review has the requested write/merge capabilities; report platform blockers honestly.
- [x] Core: authenticated JSON-API, selected courses, safe paths, atomic downloads, local-edit detection, and regression tests.
- [x] Personal app implementation: Keychain setup, menu-bar stats/recent changes, settings, cancellation, background sync, Finder actions, optional Start at Login. Complete the acceptance checks below before calling this a finished release.
- [ ] Acceptance: builds/tests, reference CLI tests, fresh setup, interrupted/offline recovery, session expiry, local edits, and unchanged downloads. Profile idle CPU, memory, and wakeups. Unit tests do not prove live or visual acceptance.
- [ ] Polish: German/English text, VoiceOver, light/dark appearance, icon, user onboarding feedback, and live university checks.

## Verified in the initial native implementation

November 1, 2026: the initial native implementation passed synthetic tests and an opt-in live Göttingen login/course/file/download check. A release app was installed in `~/Applications`, its signature verified, and the German first-run window inspected. Native tests cover path traversal/symlinks, pagination, rejected login, HTML attachment/session distinction, unavailable course areas, duplicate course titles, edited-file preservation, atomic updates, cancellation, and incorrect download sizes. No development schedule was saved; the owner subsequently instructed that none be created. Hosted reviews posted findings without implementing or pushing fixes; local development addressed them. Automatic repair and merge remain unverified platform capabilities.

## Recovery after PR #3

The initial native PR was merged before its last two findings were addressed. Follow-up PR #11 repaired the findings; obsolete revert PR #6 was closed without merging. PR #12 consolidated dependency updates. The fixes add scheduled offline-startup recovery and stable file/folder identity markers to avoid normalized-path collisions, with regressions that do not access personal credentials. Master requires resolved review conversations; queued auto-merge is still prohibited until the current commit has a clean review. Files at the prototype's older paths are preserved when the new naming scheme is used.

## Current acceptance increment (PR #13)

- [x] Synthetic first-run sign-in, course/folder selection, settings reload, private file permissions, and failure to save settings. Tests inject credential storage and never access personal Keychain items.
- [x] Refresh enrollment without losing selections; refresh before syncing and report when selected courses are no longer available.
- [x] Synthetic expired sessions (401 and login HTML): reauthenticate once; stop after rejected credentials.
- [x] Resume configured automatic sync on offline-to-online transitions, including a transition during a failing request. Preserve manual/pause choices and stop retries after rejected credentials.
- [x] Keep both required CodeQL jobs; skip Swift extraction only for known unrelated PR changes, and verify source-archive coverage on full scans. A package pre-resolution experiment did not improve measured runtime and was removed.
- [ ] Complete interactive setup and reconnect with the university, including interrupted downloads and Start at Login. Verify network recovery after sleep on a real Mac.
- [ ] Inspect German/English layout, keyboard navigation, VoiceOver, and light/dark appearance. No computer-use validation is authorized in this development session.
- [ ] Profile idle CPU, memory, wakeups, and battery impact before calling acceptance complete.

## Defaults

Göttingen only, macOS 15+, Apple Silicon personal release. Ordinary folders; hourly sync; no mirrored deletion. Replace untouched files without old backups. Preserve user edits alongside a collision-safe incoming version. Keychain credentials, session reuse, one re-login on expiry.

## Public-release roadmap

Developer ID signing/notarization, clean-machine installation, signed updates, support policy, private reporting, Intel/minimum-OS evaluation. No App Store submission, Python bundle, Finder extension, or multi-university framework for the personal version.
