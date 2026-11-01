# StudSync

A native macOS menu-bar app that brings Universität Göttingen Stud.IP course files into ordinary Finder folders. Personal Apple Silicon use comes first; macOS 15 or later is required. The Python CLI is retained as a regression-tested reference during migration.

## Build and run

Install Xcode and select its developer directory, then:

```sh
./script/build_and_run.sh
```

The script resolves the pinned Swift package, builds a release app, installs it at `~/Applications/StudSync.app`, signs and verifies it locally, and launches it. This stable location avoids file-provider metadata interfering with signatures in synced Documents folders and supports Start at Login. Codex's Run action uses the same command. `--build` builds/installs without launching; `--verify` launches it and verifies the process. `--logs`, `--telemetry`, and `--debug` support local diagnostics. Open `Package.swift` in Xcode for native editing/debugging.

This is an ad-hoc-signed personal build, not a notarized public distribution. No Python installation is needed to run the native app. Keep the app at its installed location after enabling Start at Login.

## First launch

Sign in with your university username (without the email suffix), choose a destination, select courses, and start syncing. Credentials are saved in macOS Keychain. The university web login is available for interactive/SSO sign-in; imported web sessions remain valid only as long as the university permits them. Settings and sync history live under `~/Library/Application Support/StudSync/`.

The optional CLI import reads `~/.config/studip-sync/config.json` only after you click Import; it does not change that file. Existing files without a known baseline are preserved unless their content matches the server.

StudSync runs in the menu bar after its window closes. It defaults to hourly sync and offers manual, 15-minute, and four-hour intervals. It does not keep your Mac awake. Closing the panel does not quit the app; Quit does. Current course files are supported; separate MediaCast/Opencast video-library synchronization is not yet part of the native client.

Untouched files are updated atomically without retaining old copies. Locally edited files remain intact, with incoming server versions saved beside them. Remote deletion never deletes your local files. Use the menu-bar panel to see changes and reveal files in Finder.

Remote files and folders include stable Stud.IP ID markers in their names, so Unicode normalization, case differences, duplicate names, and replaced separators cannot combine separate resources. File extensions are retained; excessively long stems are shortened. Upgrading from the initial native prototype creates these new paths and preserves files at the old paths rather than deleting or moving them.

If startup or sync fails offline, configured automatic sync retries when the network returns and at the selected interval. Paused/manual sync does not retry automatically, and rejected credentials require your attention. Each sync refreshes enrolled courses; Settings also offers Refresh courses without changing your selection. If none of your selected courses remain available, choose courses again rather than receiving a false “Up to date” result.

## Verification

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -e ".[google-tasks]"
./script/verify.sh
```

Verification runs legacy Python tests (including optional Google Tasks security tests), native Swift tests, a release app build, and whitespace validation. CI runs native and reference tests plus CodeQL. Fixtures are synthetic and do not require university credentials.

Swift CodeQL runs for native/build changes and all master/weekly scans. PRs containing only known documentation or Python CLI changes keep the required Swift job but skip extraction; Python scanning still runs. Full Swift scans check that every first-party Swift source appears in the extraction archive. Resolving packages before tracing was measured at 15m57s versus an earlier 14m22s run, so that experiment was removed rather than claiming a speedup. Native PRs can still spend about 15–22 minutes in Swift CodeQL on hosted runners.

An optional live check is available with `STUDSYNC_LIVE_TEST=1 swift test --filter liveGoettingenReadOnlyCheck`. It reads the existing CLI credentials locally, signs into Göttingen, and verifies a small course-file download in a temporary location. It never runs in CI and does not change the sync destination or university files.

## Development

See [AGENTS.md](AGENTS.md), [security policy](SECURITY.md), [roadmap](docs/ROADMAP.md), and [automation notes](docs/AUTOMATION.md). Development uses the owner's ChatGPT subscription; no OpenAI API credentials or API-billed Codex Actions are used. Automatic code review is configured in Codex repository settings, not by workflow YAML.

## Existing Python CLI

The original package remains usable with `pipx install git+https://github.com/gnagster/StudSync.git` and `studip-sync --init`. Its scope and runtime are separate from the native app; do not remove it until native parity has been verified. The optional Google Tasks plugin is a legacy CLI feature and is not included in the native app.

## Public releases

Developer ID signing, notarization, signed updates, clean-machine installation testing, and wider hardware support are future milestones. See the roadmap; do not treat a local build or successful unit tests as proof that distribution or live university compatibility is complete.
