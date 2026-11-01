# Development and review

One local Codex project automation starts November 1, 2026 at 20:15 Europe/Berlin and repeats every five hours. The Mac must be awake with the Codex app running. A five-hour interval is not a promise of five hours of continuous work. Subscription limits pause work; never fall back to an OpenAI API key.

Setup status: the timezone-anchored automation was prepared as a Codex confirmation card. It is not confirmed active until that card is saved; no alternate scheduler was installed.

The developer follows the roadmap, verifies changes, and creates/updates PRs only. The existing Codex Automatic review integration is configured by the owner to review every push. AGENTS.md authorizes the reviewer to fix all actionable findings, test, push, and let the next review examine that new SHA. Only the reviewer is authorized to merge a clean current head after required CI passes.

There is no additional local reviewer, Codex Security deployment, custom status publisher, or merge workflow. CodeQL and Dependabot are conventional GitHub services, not OpenAI API jobs.

Use the versioned Python/Swift CodeQL workflow (advanced setup). GitHub's Python-only default setup was switched off because it rejects uploads from the versioned workflow. Master requires the standard Python tests, native tests/app build, and both CodeQL jobs; no custom review status is introduced. Python tests run on macOS because the reference security suite checks macOS ACL removal.

## Platform boundary

Repository instructions do not grant tools or permissions to a hosted review integration. Codex Automatic review is documented as posting review feedback; arbitrary editing/pushing/merging during automatic review is not a verified capability here. If the reviewer cannot follow the repair or merge instructions, the PR stays open and the owner receives the limitation. Formal self-approval is not possible when development and review use the same GitHub account.

Required CI blocks broken builds, but does not itself prove a Codex review occurred. The reviewer must follow the latest-head rule in AGENTS.md. Enabling repository auto-merge alone does not implement this review loop.
