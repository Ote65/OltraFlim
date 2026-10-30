# Changelog

All notable changes to OltraFlim. Dates are project-local.

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
