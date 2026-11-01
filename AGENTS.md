# StudSync agent instructions

StudSync is a native Swift/SwiftUI menu-bar app for Universität Göttingen Stud.IP files in ordinary Finder folders. Personal Apple Silicon use comes first. Python remains a tested reference during migration.

## Development

- Use Ponytail: make the smallest complete change, reuse existing code and platform APIs, and avoid speculative abstractions.
- Use the Build macOS Apps skills for native work and GitHub tools or `gh` for repository operations.
- Read `SECURITY.md` for authentication, networking, files, persistence, and workflow changes.
- Build/run: `./script/build_and_run.sh`. Verify: `./script/verify.sh`.
- Keep networking/sync in StudSyncCore and presentation in StudSyncApp. Native code must not depend on Python.
- Add focused regression tests for nontrivial changes; keep existing checks passing.
- Never use OpenAI API credentials or API-billed Codex Actions. Use the owner's ChatGPT subscription; GitHub CI runs conventional tools only.
- Follow `docs/ROADMAP.md`. Continue the highest-priority unfinished task, test it, and create/update a focused PR against `master`. Keep one development PR active. Development agents must not approve or merge PRs.
- Do not create a separate local reviewer, security schedule, or merge bot.

## Automatic code-review agent: repair, push, re-review, merge

The owner authorizes the code-review agent to implement fixes for all actionable correctness, security, test, and documentation findings in the PR. Inspect connected code, not only the diff. Keep fixes within the PR's scope.

1. Review the latest PR head and applicable `SECURITY.md` guidance.
2. If issues are found, fix them on the PR branch and run the relevant checks. Push the fixes, then stop that review session. The configured review-on-every-push integration should start a fresh review of the new commit.
3. Repeat through new review sessions until no actionable findings remain. Never weaken tests or security controls to hide a finding or failure.
4. When no issues remain, verify the reviewed head SHA is still current, required build/test/CodeQL checks for that SHA have passed, and no blocking findings remain. The owner authorizes **the code-review agent only** to squash-merge into `master` with `gh pr merge --squash --match-head-commit <reviewed-sha>` or the connected equivalent. Never use `--admin`, force-push, or bypass protections.
5. Never merge immediately after pushing fixes: wait for review of the new SHA. If the head changes, review again.
6. Do not queue GitHub auto-merge while review is incomplete. Resolve a review conversation only after fixing and verifying its finding; required conversation resolution alone does not prove the latest SHA has a clean review.

These instructions authorize actions but do not grant platform capabilities. If the integration cannot edit, push, inspect checks, or merge, report that limitation and leave the PR open. Do not claim success without evidence. If a fix needs owner input or unavailable authentication/tools, report the blocker rather than creating no-op pushes. Keep credentials and private vulnerability details out of public comments. GitHub review decisions and merging are distinct; authors cannot formally approve their own PRs.
