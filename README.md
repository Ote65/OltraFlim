# OltraFlim

**OltraFlim 是一个原生 macOS 胶片模拟暗房。** 以照片库为首页，导入照片或
整个文件夹，点击照片进入显影；选胶片、调光线与色彩、加颗粒与光晕、用原图
分割杆对比，最后导出全分辨率照片。编辑、收藏、颜色标签和文件夹索引按路径
记忆，文件始终留在原位置。

A native macOS film-simulation darkroom. Import photographs or whole folders,
open one into Develop, choose a film stock, tune light and grain, compare with
the original, and export full resolution. The library remembers paths,
favourites, colour labels and per-file edits without copying or deleting your
files.

- Version: **1.3 / build 4** · macOS 14+
- Download: [GitHub Releases](https://github.com/Ote65/OltraFlim/releases)
- License: **source-available, noncommercial** — see [License](#license)

## Project docs

| Doc | What it covers |
| --- | --- |
| [`CODE_MAP.md`](CODE_MAP.md) | source map, data flow, renderer order, hot files |
| [`STATUS.md`](STATUS.md) | current status, verified/unverified, known limits, roadmap |
| [`AGENTS.md`](AGENTS.md) | hard rules for coding agents, build policy, handoff |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | contribution flow, style, PR/review rules |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | toolchain, build, packaging, debug |
| [`docs/MULTI_AGENT_COORDINATION.md`](docs/MULTI_AGENT_COORDINATION.md) | multi-agent / multi-machine protocol |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | license scope and upstream attribution |
| [`CHANGELOG.md`](CHANGELOG.md) | release history |

OltraFlim is a SwiftUI + Metal application. It carries a display-ready pack of
**113 film LUTs** derived from the open-source
[spektrafilm](https://github.com/andreavolpato/spektrafilm) project by Andrea
Volpato, using the **ACES 2.0 SDR 100-nit Rec.709** output transform from
OpenColorIO. It does not embed Python, Electron or a web view.

## Run

```bash
./script/build_and_run.sh            # build release + launch
./script/build_and_run.sh --debug    # debug build + launch
./script/build_and_run.sh --verify   # build, launch, verify the process
./script/build_and_run.sh --logs     # launch + stream app logs
./script/build_and_run.sh --no-launch # build and stage only
```

The app is staged at `dist/OltraFlim.app` and ad-hoc signed. macOS 14+ is required.

Packaged copies live at `dist/OltraFlim-1.3.dmg` (drag-to-Applications) and
`dist/OltraFlim-1.3.zip`.

> This machine only has Command Line Tools (no Xcode) and its install ships two
> Clang module maps that both define `SwiftBridging`. The build script works around
> that with a local include overlay under `.build/toolchain`; it does not modify
> `/Library`. The app is compiled directly with `swiftc` because SwiftPM's manifest
> compilation hits the same broken SDK. On a Mac with a healthy Xcode toolchain,
> `swift build` can be used instead.

## Controls

| Action | Shortcut |
| --- | --- |
| Import photos | ⌘O |
| Import folder | ⇧⌘O |
| Export | ⌘E |
| Before / Develop | ⌥B |
| Auto tone | ⇧⌘A |
| Reset adjustments | ⌥⌘R |
| Next / previous photo | ⌘] / ⌘[ |
| Back to library / one folder up | top-left button |
| Fit / 100% | double-click canvas |
| Reset zoom | Space |
| Zoom | pinch, ⌃-scroll, ⌘-scroll or ⌥-scroll |
| Pan | drag, or two–finger scroll |
| Compare | click the Original button in the canvas corner, then drag the divider |
| Move the window | drag the 46 pt title strip only |

Library: display menu (grid/list), group menu (film/favourites/colour labels),
filter chips, search, favourite stars and colour-label menus on every card or row.
Folders can be imported, opened, navigated by breadcrumb and refreshed without
copying files.

Film library: search by film, brand or ISO; filter by brand; the funnel menu
filters type (negative / slide / cinema / instant / special), engine (SpektraFilm
/ Spectral Film) and favourites. Every stock exposes its print/render variants in
the inspector.

## New in 1.3

- **Photo library home** — the app opens on a Finder-like library wall. Click a
  photograph to enter Develop; the top bar returns to the same folder.
  Imported paths, favourites, colour labels and edits survive restarts.
- **Folder support** — import folders from the button, menu (⇧⌘O) or by dragging
  them onto the window. Folders are indexed in place, open into their own page,
  show subfolders, and keep breadcrumb / up navigation.
- **Finder-style view controls** — a display menu switches grid/list; a group
  menu groups by film stock, favourites or colour label; filter chips cover all,
  favourites, edited and the five Lightroom colour labels; live search matches
  file names, film stocks and labels.
- **Lightroom metadata** — per-photo favourite stars and colour labels, stored
  separately from develop settings.
- **Window chrome** — only the 46 pt title strip drags the window; the canvas
  keeps its damped pan. Traffic lights are redrawn inside that strip so they
  sit exactly on its vertical centre. Reset / Export / Settings moved to a fixed
  footer at the bottom of the inspector.

## New in 1.2

- **RAW sample previews** — the supplied DNG is rendered once to a 2,200 px
  reference still; film and imported-LUT cards show it when no photograph is open.
- **Grain and halation fixes** — grain used an over-large seed that collapsed the
  noise into a flat tint; halation's threshold mapping capped almost all highlights.
  Both are corrected, with stronger grain sizing and visible texture at 100.
- **Parameter audit fixes** — Whites now maps to the display white point (the old
  pre-LUT mask only reached 0.85+ linear and felt inert), tint travel was widened,
  highlight/shadow masks were rebalanced, and full-resolution exports now build
  their own curve texture instead of falling back to identity.
- **Compare slider** — the Original control lives in the canvas corner and reveals
  a draggable split between the untouched photo and the developed photo.
- **Smooth preview navigation** — damped 120 Hz zoom/pan follow, ctrl/option-scroll
  zoom with a curved response, pinch, Space-to-fit, and a compact top bar.
- **Inspector tabs** — Light / Color slide horizontally; Transparency, Detail,
  Film Texture and Information stay below the tabs. The third Curves tab offers
  independent luma and R/G/B curves over the live histogram.
- **Professional colour** — hue shift, colour density, skin/foliage/sky saturation,
  highlight warmth and shadow coolness join temperature/tint/vibrance/saturation.

## New in 1.1

- **Bilingual UI** — Chinese is the default; Settings has a 中文 / English switch that applies immediately.
- **Imported LUT library** — import 3D `.cube` LUTs from the sidebar. They are applied as Rec.709 display LUTs over the adjusted photo and remembered across launches.
- **Transparency panel** — two smart sliders:
  - **Tonal clarity** reads the final histogram's black/white edges and remaps levels, removing the grey veil.
  - **Color clarity** samples the average highlight and shadow colours and neutralises casts with the complementary-colour principle (for example, a yellow highlight gains blue, a green shadow loses green).
  - **Analyze** re-measures the current luminance range and casts.
- **Film texture** — halation radius, halation warmth, colour grain, shadow grain and print fade join the existing grain/halation/vignette controls.
- **Language-aware menus**, tooltips, export sheet, settings and empty states.

## Architecture

```
Sources/OltraFlim/
  App/          SwiftUI entry point, app delegate
  Views/        top bar, film library, canvas, inspector, filmstrip, export sheet
  Stores/       AppModel (selection, edits, favourites, export, imported LUTs),
                EditStore (per-file memory), ImportedLUTStore (LUT registry)

  Models/       catalog, photo, adjustments, curves
  Engine/       Metal renderer, LUT pack loader, .cube importer, curve texture,
                ImageIO decode
  Support/      design tokens, localization, window configuration
Resources/
  LUTs/         113 × 33³ RGBA16F combined LUTs + two neutral LUTs
  catalog.json  stocks, variants, swatches, metadata
  Shaders.metal compute kernels (runtime-compiled)
Tools/
  build_luts.py  reproducible LUT conversion
  RenderCheck.swift  headless engine check
```

### Film pipeline

```
sRGB photo → linear Rec.709 → white balance / exposure / tone / colour
→ AP1 → ACEScc → 33³ film LUT → gamma-2.2 encoded Rec.709
→ halation / grain / vignette / dither → display
```

The LUTs already contain the ACES 2.0 SDR output transform, so the RGB values
coming out of the 3D texture are ready to display. A neutral LUT with the same
exposure is blended in for the film-strength control.

Imported LUTs use a second branch: the adjusted scene-linear image is encoded to
sRGB and sampled through the user's 33³/65³ display LUT. That branch bypasses the
ACES render, because almost all downloadable creative LUTs are Rec.709 display
transforms rather than ACEScc LMTs.

After the look is formed, the RGB/luma curve texture is applied, then the colour
mixer, **Tonal clarity** (histogram-edge levels), **Color clarity** (automatic
complementary cast correction), print fade, vignette, grain and dither.

The Metal pass also implements clarity and sharpening (source taps), halation
(a thresholded half-resolution bloom), grain (multi-octave value noise) and vignette.

### Rebuilding the film pack

Requires Python 3 with `numpy`, `Pillow`, `PyOpenColorIO` (2.6+). The source is the
Alcedo `.cube` export (65³ ACEScc → ACEScc LMT files).

```bash
python3 -m venv /tmp/aciovenv
/tmp/aciovenv/bin/pip install numpy pillow opencolorio
/tmp/aciovenv/bin/python Tools/build_luts.py \
  --source "/path/to/Alcedo_LUT_导出" \
  --out Resources --size 33
```

The output is ~32 MB of `RGBA16F` 3D textures and a new `catalog.json`. The script
applies the ACES 2.0 SDR Rec.709 transform with OCIO's builtin config, bakes the
SpektraFilm +1.5 EV default, and groups the 113 files into 45 stocks.

## Credits and provenance

- Film modelling: **spektrafilm** by Andrea Volpato (GPLv3 reference
  implementation; profiles/LUTs CC BY-SA 4.0, commercial use of LUT data
  permitted, no resale of the LUT pack).
- LUT derivatives: CC BY-SA 4.0. See `Resources/LUT_NOTICE.md` and
  `Resources/SPEKTRAFILM_LICENSE.txt`.
- ACES 2.0 output transform: Academy Color Encoding System / OpenColorIO 2.6.
- The OltraFlim Swift/Metal engine is original to this project; no spektrafilm
  source code is copied into the app.
- The reference preview is derived from a DNG supplied by the project owner;
  the DNG itself is not shipped.
- Full license map and asset carve-outs: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Imported LUTs

Choose **LUT** in the library tabs, then **Import .cube**. The importer accepts
3D `.cube` files from 2³ to 128³ (1D LUTs are rejected with a clear message). Files
are converted to a compact RGBA16F binary in
`~/Library/Application Support/OltraFlim/LUTs/`; the original `.cube` is not copied.
The registry lives in `importedLUTs.json`. Imported LUTs appear as their own cards
with an identity swatch and can be deleted from the card's context menu.

Imported LUTs are **not** ACEScc LMTs. If a LUT was authored for an ACEScc LMT slot,
it will not match; re-bake it as a Rec.709 display LUT or use the built-in pack.

## Transparency

The two sliders are intentionally separate:

- **明暗通透 / Tonal clarity** finds the first and last 0.4% of the final luminance
  histogram, then stretches black/white toward those edges. This is the classic
  “pull both ends inward to the waveform” move, automated. The panel shows the
  measured range (for example `6–92%`).
- **颜色通透 / Color clarity** accumulates the average RGB of the top and bottom
  luminance bands, computes the complementary delta, and applies it only in the
  white and black masks. Yellow highlights get blue; green shadows lose green.
  This follows the complementary-colour theory in your note without requiring a
  picker.
- Both use a 0–100 strength. At 0 the measurement is re-taken; when active the
  measurements are held so the correction does not chase its own histogram. Press
  **Analyze** to re-measure after large exposure/film changes.

## Language

Chinese is the default. Settings → LANGUAGE switches to English immediately for the
app UI, tooltips, menus and empty states. The macOS system menu names themselves
remain controlled by the operating system.

## Known limits

- RAW files are decoded through macOS ImageIO/Core Image into sRGB before the film
  pipeline; camera-specific RAW controls are not exposed.
- Preview is capped at 2,600 px for responsiveness; export is full resolution.
- Export above 16,000 px on the long edge is scaled down to fit Metal limits.
- Library paths, folder paths, favourites, colour labels, language and export
  defaults persist. Edits are remembered per file path in
  `~/Library/Application Support/OltraFlim/edits.json`. Folder contents are
  rescanned when the folder is opened; moved or renamed folders need re-import.
- Folder photographs are indexed in place and cannot be removed individually
  from the library (reopening the folder would discover them again). A top-level
  folder can be removed from the library index without touching disk files.
- Imported LUTs are display LUTs (Rec.709), not ACEScc LMTs. 1D LUTs are not yet
  supported. LUTs larger than 65³ are rejected and the library keeps at most 50
  custom LUTs to bound GPU memory.
- The build is ad-hoc signed, not notarized. Gatekeeper may require right-click →
  Open on first launch.

## License

The original OltraFlim application code and documentation are licensed under
**PolyForm Noncommercial 1.0.0** (`LICENSE`): you may use, modify and share the
code for noncommercial purposes only. This is a source-available, noncommercial
license, not an OSI-approved open-source license.

Bundled film LUTs and film-profile derivatives are **not** relicensed by that
file; they remain **CC BY-SA 4.0** under the upstream spektrafilm notice. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and
[`Resources/SPEKTRAFILM_LICENSE.txt`](Resources/SPEKTRAFILM_LICENSE.txt) before
using or redistributing those assets. The OLTRAFLIM name/icon are brand material
and are not licensed for a different product.

Film modelling powered by spektrafilm by Andrea Volpato. LUT derivatives
CC BY-SA 4.0. ACES 2.0 display transform © Academy / OpenColorIO.

