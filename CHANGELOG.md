# Changelog

All notable changes to OltraFlim. Dates are project-local.

## 1.4 — 2026-10-30

### Fixed

- **Highlights** was effectively inert after the film LUT: ±100 changed the
  picture by ~4/255. It now operates on printed luminance (measured 44/255).
- Bloom reused the halation blur, but the blur forced alpha to 1, so threshold
  and radius did nothing and bloom brightened the whole frame. Alpha now carries
  the untinted highlight energy through both blur passes.
- Green saturation travel widened after the audit showed ~1/255 response.

### Added

- **Grain 2.0**: band-limited three-octave grain with slowly varying density
  patches, a midtone-weighted tone response, `Grain roughness`, and coarser
  dye-cloud colour grain. Grain size is normalised to the short side so preview
  and export match.
- **Midtones** and **Highlight rolloff** in the Light tab.
- **Bloom** under Film Texture, sharing the highlight threshold/radius with
  halation.
- **Vignette** detail: midpoint, roundness, feather, centre X/Y.
- **In-app settings panel** — a floating gear on the library opens text size,
  reduce motion, default export folder/format, thumbnail cache stats and clear.
- **Disk thumbnail cache** — previews persist under `~/Library/Caches/` with
  size pruning, a memory cap and memory-pressure eviction.
- **Imported LUTs persist** — user LUTs are copied to Application Support and
  missing registry entries self-heal.
- New app logo assets.

### Changed

- Vignette defaults reproduce the previous look (midpoint 50, feather 50).
- Version 1.4 / build 5. No new DMG/ZIP has been built or published yet;
  v1.3 remains the latest release.

## 1.3 — 2026-10-30

### Added

- Finder-like **photo library home**: grid/list display, film/favourites/colour
  grouping, filter chips, live search, folder cards, breadcrumb navigation.
- **Folder import** by button, ⇧⌘O, or drag-and-drop; folders are indexed in
  place, subfolders are navigable, and files are never copied or deleted.
- **Favourites and five Lightroom-style colour labels**, persisted per path
  separately from develop settings.
- Fixed **Reset / Export / Settings** bar at the bottom of the inspector.
- Self-drawn traffic lights centred in the 46 pt title strip.

### Changed

- Only the title strip moves the window; canvas drag pans the photograph.
- Ctrl / Cmd / Option + scroll zooms; wheel direction corrected; damped pan
  remains.
- App opens on the library instead of a blank canvas.
- Version 1.3 / build 4; DMG and ZIP packages.

### Documentation / licensing

- Added code map, status, agent rules, contribution guide, development guide,
  multi-agent protocol, issue/PR templates.
- Application code is now published under **PolyForm Noncommercial 1.0.0**.
  Bundled LUT/profile derivatives remain **CC BY-SA 4.0**; see
  `THIRD_PARTY_NOTICES.md`.

## 1.2 — 2026-10-30

- RAW-derived sample previews for film/LUT cards when no photo is open.
- Grain seed precision fix (grain no longer collapses into a flat tint).
- Halation threshold mapping fix.
- Whites moved to display-referred white point; tint/highlight masks rebalanced.
- Full-resolution exports now build their own curve texture.
- Compare split slider in the canvas corner.
- Damped 120 Hz zoom/pan, curved Ctrl/Option-scroll zoom, Space reset.
- Light / Color / Curves inspector tabs; professional colour controls.
- LUT import cap: 50 custom LUTs, max 65³.

## 1.1 — 2026-10-30

- Chinese default UI with English switch in Settings.
- Imported `.cube` LUT library.
- Tonal and colour transparency sliders with histogram analysis.
- Halation radius/warmth, colour grain, shadow grain, fade.
- Language-aware menus, export sheet, settings and empty states.

## 1.0 — 2026-10-29

- Initial native macOS SwiftUI + Metal film darkroom.
- 113 ACES 2.0 / Rec.709 display LUTs across 45 film stocks.
- Exposure, tone, colour, clarity, grain, halation, vignette.
- Before/after, zoom, pan, export, per-path edit memory.
