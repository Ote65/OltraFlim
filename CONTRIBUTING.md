# Contributing to OltraFlim

OltraFlim is a native macOS film-simulation darkroom. Contributions are welcome
for noncommercial use and development under the repository license.

## License of contributions

By opening a pull request you agree that your original code and documentation
contributions are licensed under the same **PolyForm Noncommercial 1.0.0**
terms as the application. You retain copyright in your contribution.

Do not relicense or remove upstream attribution for:

- `Resources/LUTs/**` and film-profile derivatives (CC BY-SA 4.0)
- `Resources/SPEKTRAFILM_LICENSE.txt`
- `Resources/LUT_NOTICE.md`
- ACES / OpenColorIO notices

See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and [`LICENSE`](LICENSE).

## Before you start

Read:

1. [`CODE_MAP.md`](CODE_MAP.md)
2. [`STATUS.md`](STATUS.md)
3. [`AGENTS.md`](AGENTS.md) if you are an agent
4. [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)

For a non-trivial change, open an issue first and describe the behavior you
want to change. For UI, include a before/after description or screenshot from
your own testing; do not assume the maintainer will run the app for you.

## Environment

- macOS 14 or newer.
- This project builds with Command Line Tools and `swiftc`; Xcode is not
  required on the reference machine.
- SwiftPM is currently not usable there because the CLT SDK ships duplicate
  `SwiftBridging` module maps. Use the shell build.

```bash
git clone https://github.com/Ote65/OltraFlim.git
cd OltraFlim
./script/build_and_run.sh --no-launch
```

`--no-launch` builds `dist/OltraFlim.app` without starting the app. This is the
default verification command for contributors and agents.

To launch on your own machine:

```bash
./script/build_and_run.sh
```

## What to work on

Good first issues:

- UI polish that follows the existing `DS` design tokens
- localization gaps (`T("中文", "English")`)
- performance of folder scanning / thumbnail loading
- accessibility labels and keyboard navigation
- documentation and manual-test checklists

Avoid without prior discussion:

- new dependencies
- account/cloud sync or telemetry
- changing the noncommercial license
- rewriting the renderer or photo-library architecture
- deleting upstream license/notice files
- changing the 113 LUT pack or catalog IDs

## Code style

- Swift 5 mode, macOS 14 APIs unless a fallback is provided.
- Keep the existing architecture:
  - state and use-cases in `AppModel`
  - Metal in `Renderer` + `Resources/Shaders.metal`
  - views under `Views/`, tokens in `DesignSystem`
  - all user-visible strings in `T(...)`
- Do not add a new color/radius/animation value if a `DS` token exists.
- Prefer small, complete changes over speculative abstractions.
- Comments explain *why* a non-obvious choice exists, not *what* the code does.
- Do not commit generated artifacts: `dist/`, `.build/`, `*.xcuserstate`,
  `AppIcon.iconset/`, `AppIcon_1024.png`, `__pycache__`.

## Renderer changes

When touching `Renderer.swift` or `Shaders.metal`:

1. Keep the `Uniforms` field order exactly aligned with `RenderUniforms`.
2. Update preview (`update`) and export (`renderFull`) together.
3. Add a `RenderCheck` argument if you need headless validation.
4. Remember runtime shader compilation: a compile error will only show at
   launch, not during `swiftc`.
5. In the PR, list the exact manual visual checks the owner should perform.

## Photo-library changes

- `folder == nil` means a directly imported photograph; only those go into
  `libraryPhotoPaths`.
- Folder contents are indexed, never copied or deleted.
- Favourites and colour labels live in `LibraryMetaStore`, not `PhotoEdit`.
- Keep `saveLibrary()` / `saveFolders()` / `restoreLibrary()` / `restoreFolders()`
  consistent.
- Avoid nested SwiftUI `Button`s inside clickable cards/rows; use overlays.

## Commits and pull requests

Branch from `main`:

```bash
git switch -c agent/<agent-id>/<issue>-<short-slug>
```

Use clear commit subjects:

```text
library: add folder breadcrumb navigation
renderer: keep export curves independent from preview
ui: centre traffic lights in the 46pt title strip
fix: correct grain seed precision
```

A PR should contain:

- what changed and why
- affected files/subsystems
- verification commands and actual output summary
- explicit **not verified** list (especially UI)
- screenshots only if you produced them yourself
- linked issue

Use the PR template. Keep PRs focused; avoid mixing unrelated cleanup.

## Review rules

- Two things must be true: the spec is implemented, and the repo's patterns
  are followed.
- A review should call out:
  - renderer/export consistency
  - photo-library persistence invariants
  - license/attribution changes
  - hidden global window/gesture behavior
  - unverified UI claims
- UI changes require the owner's manual test before a release, not necessarily
  before merge.

## Reporting bugs

Use the GitHub bug template and include:

- macOS version and OltraFlim version/build
- exact steps
- whether the photo came from the root library or a folder
- whether the app was launched from `dist/` or built locally
- relevant Console logs only (never paste tokens or personal paths if public)
- no private photos in a public issue; use a synthetic or cropped sample

Do not attach the user's DNG or personal library data to public issues.

## Release checklist

See [`STATUS.md`](STATUS.md) and [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).
The release owner must build with `--no-launch`, create DMG/ZIP, record SHA-256,
and publish a GitHub Release with notes. Do not claim UI verification that did
not happen.
