# Development guide

## 1. Requirements

- macOS 14 or newer
- Command Line Tools (`xcode-select --install`)
- Python 3 only if you regenerate the LUT pack (`Tools/build_luts.py`)
- Git
- No Xcode required on the reference machine

OltraFlim is built directly with `swiftc`. SwiftPM is intentionally not the
primary build path here because the CLT SDK on the reference machine exposes
two Clang module maps that both define `SwiftBridging`.

## 2. Clone and build

```bash
git clone https://github.com/Ote65/OltraFlim.git
cd OltraFlim

./script/build_and_run.sh --no-launch   # build + stage only, do not launch
```

Other modes:

```bash
./script/build_and_run.sh            # build + launch (only on a machine you own/are allowed to test)
./script/build_and_run.sh --debug    # debug + launch
./script/build_and_run.sh --verify   # build + launch + process check
./script/build_and_run.sh --logs     # build + launch + stream logs
```

**Default for agents and CI-like checks is `--no-launch`.** It never calls
`open`, never kills a running app, and never touches the user's desktop.

## 3. Toolchain workaround

The script creates:

```text
.build/toolchain/include/swift/bridging
.build/toolchain/include/swift/bridging.modulemap
.build/toolchain/lib/swift -> CLT Swift runtime
```

and compiles with:

```text
-resource-dir .build/toolchain/lib/swift
-Xcc -I .build/toolchain/include
```

This is local to the repo. It does not modify `/Library` or the system CLT.

A healthy Xcode toolchain can use `swift build` instead, but the repo's
`Package.swift` is not the reference build path and may need adjustment.

## 4. Resource layout

```text
Resources/
  AppIcon.icns          app icon
  Sample/               sample_preview.jpg (cards when no photo is open)
  LUTs/                 113 built-in .bin + neutral-0/neutral-15
  Shaders.metal         compiled at runtime by Renderer
  catalog.json          45 stocks / 113 looks / defaultStock
  Info.plist            version 1.3 / build 4
  LUT_NOTICE.md
  SPEKTRAFILM_LICENSE.txt
```

`Shaders.metal` is compiled at runtime by `MTLDevice.makeLibrary`. Editing it
does not require a Swift rebuild, but a syntax error will only appear when the
app creates its Renderer. Headless RenderCheck can catch it without launching
the app.

## 5. Runtime data

All user state lives outside the repo:

```text
~/Library/Application Support/OltraFlim/
  edits.json               per-path develop settings
  importedLUTs.json        custom LUT registry
  LUTs/                    custom LUT binaries
  libraryMeta.json         favourites + colour labels
```

Library paths and folder paths are in `UserDefaults`:

```text
studio.oltra.oltraflim
  libraryPhotoPaths
  libraryFolderPaths
  libraryDisplay
  libraryGrouping
  browseStock
  ...
```

**Do not delete these directories while debugging unless the user has
explicitly confirmed they are test data.** They contain the user's library
paths, edits and favourites.

To test a clean first launch, back up the Application Support directory and
the defaults domain first.

## 6. Runtime shader and renderer checks

Headless renderer tool:

```bash
# if a previously built render-check exists
./.build/render-check input.jpg output.png <lookID> <exposure> <contrast> \
  <grain> <halation> <vignette> <strength> <grainSize> <clarity> <sharpen> \
  <halationThreshold> <halationRadius> <halationWarmth> <grainChroma> \
  <grainShadow> <fade>
```

`Tools/RenderCheck.swift` is not shipped in the `.app`. It is useful for
checking that a shader parameter still changes pixels. The repo does not
commit `.build/`; compile it per machine with the same include overlay if
needed.

Renderer invariants:

- `Uniforms` field order must equal `RenderUniforms`.
- Preview and export must use the same `processImage` parameters.
- `renderFull` builds its own curve texture.
- `grainSeed` remains a small float (`abs(hash)%4096/100`).
- Imported LUT cap: 50 entries, max 65³.

## 7. Test launch arguments

These are for local/QA builds. They can import a photo, open a tab, apply LUTs
and export. Do not run them on a user's desktop without permission.

```text
--open <path>          import a photo
--look <lookID>        choose a film look
--library films|luts   library tab
--tab light|color|curves
--before               start compare
--tonal <0…100>        tonal transparency
--color <0…100>        colour transparency
--curve-demo           apply an S curve
--color-demo           apply colour settings
--import-lut <path>    import a .cube
--export-sheet         open export sheet
--export <path>        export PNG/TIFF
--export-sheet
```

## 8. Packaging

```bash
./script/build_and_run.sh --no-launch

rm -rf dist/dmg/OltraFlim.app
ditto dist/OltraFlim.app dist/dmg/OltraFlim.app

hdiutil create -volname "OltraFlim 1.3" -srcfolder dist/dmg \
  -ov -format UDZO dist/OltraFlim-1.3.dmg
ditto -c -k --sequesterRsrc --keepParent dist/OltraFlim.app \
  dist/OltraFlim-1.3.zip

shasum -a 256 dist/OltraFlim-1.3.dmg dist/OltraFlim-1.3.zip
```

- `dist/` is ignored by Git; binaries live in GitHub Releases.
- `dist/dmg/` should contain `OltraFlim.app`, an `Applications` symlink and
  `Read Me.txt`.
- Bump `Resources/Info.plist` and `SettingsView.swift` together.
- Never publish a build that still contains user photos or test LUTs.

## 9. Multi-machine workflow

Each machine:

1. Clone the repo and run `--no-launch` once.
2. Keep its own `.build/` cache; do not copy it between machines.
3. Configure a local git identity and GitHub auth (`gh auth login` or SSH).
4. Use a separate branch/worktree per agent.
5. Run `git fetch` and rebase before opening a PR.
6. Never `git add dist/` or `.build/`.
7. Update `STATUS.md` if verification state changes.

See [`MULTI_AGENT_COORDINATION.md`](MULTI_AGENT_COORDINATION.md) for the
claim/handoff protocol.

## 10. What not to do

- Do not start the app to “see if it works” unless the owner asked.
- Do not use AppleScript/JXA/CGEvent to click the app.
- Do not delete `~/Library/Application Support/OltraFlim` as a “cleanup”.
- Do not add dependencies, cloud sync, telemetry, or a web view.
- Do not remove upstream LUT attribution.
- Do not claim manual UI tests passed without a human doing them.
