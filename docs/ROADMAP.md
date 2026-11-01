# StudSync roadmap

## Operating plan

Build native Swift, retaining Python as a reference until native parity is proven. One Codex project schedule runs every five hours, anchored at November 1, 2026, 20:15 Europe/Berlin. Development creates/updates PRs only. Existing automatic review on every push follows `AGENTS.md`: repair, test, push, re-review, then merge a clean current revision when the integration supports those actions. No separate reviewer, security scheduler, merge bot, or OpenAI API usage.

## Milestones

- [ ] Foundation: complete instructions, CI, dependency updates, build/run action, and five-hour schedule. Establish whether automatic review has the requested write/merge capabilities; report platform blockers honestly.
- [x] Core: authenticated JSON-API, selected courses, safe paths, atomic downloads, local-edit detection, and regression tests.
- [x] Personal app implementation: Keychain setup, menu-bar stats/recent changes, settings, cancellation, background sync, Finder actions, optional Start at Login. Complete the acceptance checks below before calling this a finished release.
- [ ] Acceptance: builds/tests, reference CLI tests, fresh setup, interrupted/offline recovery, session expiry, local edits, and unchanged downloads. Profile idle CPU, memory, and wakeups. Unit tests do not prove live or visual acceptance.
- [ ] Polish: German/English text, VoiceOver, light/dark appearance, icon, user onboarding feedback, and live university checks.

## Verified in the initial native implementation

November 1, 2026: 16 reference Python tests, twelve synthetic native tests, and an opt-in live Göttingen login/course/file/download check passed. A release app was installed in `~/Applications`, its signature verified, and the German first-run window inspected. Native tests cover path traversal/symlinks, pagination, rejected login, HTML attachment/session distinction, unavailable course areas, duplicate course titles, edited-file preservation, atomic updates, cancellation, and incorrect download sizes. Full interactive setup, automatic session renewal, Start at Login, offline recovery, accessibility, and battery profiling remain acceptance work. The exact five-hour start was prepared as an automation card and still requires confirmation in Codex. The first hosted review posted findings without implementing or pushing fixes; the local development session addressed them. Automatic repair and merge remain unverified platform capabilities.

## Recovery after PR #3

The initial native PR was merged before its last two findings were addressed. Revert PR #6 remains open and has not changed master. The follow-up fixes add scheduled offline-startup recovery and stable file/folder identity markers to avoid normalized-path collisions, with regressions that do not access personal credentials. Master now requires resolved review conversations; queued auto-merge is still prohibited until the current commit has a clean review. Files at the prototype's older paths are preserved when the new naming scheme is used.

## Defaults

Göttingen only, macOS 15+, Apple Silicon personal release. Ordinary folders; hourly sync; no mirrored deletion. Replace untouched files without old backups. Preserve user edits alongside a collision-safe incoming version. Keychain credentials, session reuse, one re-login on expiry.

## Public-release roadmap

Developer ID signing/notarization, clean-machine installation, signed updates, support policy, private reporting, Intel/minimum-OS evaluation. No App Store submission, Python bundle, Finder extension, or multi-university framework for the personal version.
