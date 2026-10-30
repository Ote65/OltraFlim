# PRODUCT.md — OltraFlim

## Product

**OltraFlim** is a one-room macOS darkroom for photographs. It takes the open-source
film science of [spektrafilm](https://github.com/andreavolpato/spektrafilm) and turns
it into a display-ready film library: import a photo, choose a stock, tune light,
compare the original, export. No node graphs, no spectral parameters, no Python
runtime, no Electron shell.

The name is kept exactly as supplied by the user: **OltraFlim**.

## Surface mode

**Operate.** The user is inside a task. Familiarity, scanability, precision and
speed outrank expression. The brand lives in restrained details: a brass safelight
accent, a film-frame icon, exact typography and quiet motion.

## Audience

Photographers and colour-curious people who want the character of Portra, Gold,
Ektachrome, Vision3 or Velvia without learning a colour-science application. They
already understand exposure and contrast; they do not want to understand couplers,
printer lights, or ACES channel order.

## Primary flow

1. Land on the library home. Import photographs (⌘O), folders (⇧⌘O), or drag
   either onto the window. Folders are indexed in place and appear as folder
   cards; opening one shows its subfolders and photographs like Finder.
2. Find a photograph with the display menu (grid/list), group menu
   (film/favourites/colour), filter chips and search; star it or give it a
   Lightroom-style colour label.
3. Click a photograph to enter Develop.
4. Choose a film stock in the left library. A stock contains one to four print /
   render variants; the default is chosen for a pleasing starting point.
5. Adjust film strength, light, colour and effects in the right inspector.
6. Compare with the original (Before / Develop, `⌥B`).
7. Export a full-resolution JPEG, PNG, TIFF or HEIC; the top-left back button
   returns to the same library folder.

Secondary: switch photographs with the bottom filmstrip, favourite stocks,
search the film library, filter by brand / type / engine.

## Functional promises

- All **113 LUTs** from the supplied pack are present, grouped into 45 film stocks.
- Each LUT is a **display-ready 33³ ACEScc → gamma-2.2 Rec.709** transform, built
  through the **ACES 2.0 SDR 100-nit Rec.709** output transform.
- The default SpektraFilm grade (+1.5 EV) is baked into the SpektraFilm derivatives
  so a selected stock lands at the intended exposure.
- Real adjustments: exposure, contrast, highlights, shadows, whites, blacks,
  temperature, tint, vibrance, saturation, clarity, sharpen, grain, grain size,
  halation, halation threshold, vignette, film strength.
- Before/after, zoom (fit / 100%), pan, histogram, metadata, export.
- The library remembers photograph paths, folder paths, favourite stars, colour
  labels and edits across launches; files are never copied or deleted.
- Edits are remembered per file path, so re-importing the same photograph
  restores its film, strength and adjustments.
- **Language**: Chinese by default, switchable to English in Settings and applied
  immediately across the app.
- **Imported LUTs**: 3D `.cube` files can be added to the LUT library, applied as
  Rec.709 display LUTs, persisted in Application Support and deleted again.
- **Transparency**: Tonal clarity auto-levels to the final histogram's black/white
  edges; Color clarity measures highlight/shadow colour casts and neutralises
  them with complementary colour.
- **Film texture**: grain size, colour grain, shadow grain, halation amount,
  threshold, radius, warmth, vignette and print fade.
- **Tone curves**: independent luma and R/G/B curves over the live histogram.
- **Compare slider**: split the canvas between the original and the developed
  photograph; drag the divider.
- **Smooth preview**: damped zoom/pan, ctrl/option-scroll, pinch, Space-to-fit.
- **Sample previews**: film and imported-LUT cards use the supplied DNG-derived
  reference still when no photo is open.

## Non-goals

- Editing the spectral model (sensitivities, couplers, printer lights).
- Batch processing, catalogues, cloud sync, presets marketplace.
- Replacing a full RAW developer: RAW files are decoded by macOS/ImageIO into a
  working sRGB image before the film pipeline.
- Importing ACEScc LMTs as user LUTs: user imports are Rec.709 display LUTs
  because the ACES 2.0 DRT is baked into the built-in film pack, not available as
  a runtime node graph.
- Shipping the 28 MB DNG itself: the app ships a 2,200 px reference still derived
  from it to keep the bundle compact.

## Performance budget

- Native SwiftUI + Metal compute; no embedded interpreter.
- Film pack: ~32 MB on disk, ~32 MB of GPU textures, loaded once.
- Preview capped at 2,600 px; full-resolution export is GPU-rendered.
- App bundle target: under 50 MB including resources.

## Truth and attribution

Film modelling is powered by **spektrafilm** by Andrea Volpato. The LUT derivatives
come from the supplied Alcedo export (CC BY-SA 4.0 / commercial-use, no resale).
The display transform uses the ACES 2.0 builtin from OpenColorIO 2.6. See
`Resources/LUT_NOTICE.md` and `Resources/SPEKTRAFILM_LICENSE.txt`.

## Assumptions from the brief

- The user is on macOS 14+ with an Apple-silicon GPU and wants a local `.app`.
- "OltraFlim" is the intended product spelling (kept verbatim).
- The supplied LUT pack is the authoritative film library; the Python reference
  implementation is not embedded at runtime.
