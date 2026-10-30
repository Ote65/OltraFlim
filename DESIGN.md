# DESIGN.md — OltraFlim

## World

An industrial darkroom after the safelight has warmed up: nearly black surfaces,
one brass accent, precise hairline separation, photographs as the only saturated
object in the room. The reference is the supplied 欧创 brief (minimal, industrial,
restrained) plus the high-end dark UI rules (surface luminance, optical irradiation,
authored motion).

Not a Lightroom clone visually; Lightroom's **information architecture** is the
reference, not its chrome.

## Layout

```
top bar 46 (only draggable strip; custom traffic lights centred)
LIBRARY
┌─────────────────────────────────────────────────────────────────────┐
│ title / breadcrumb                         import photo / folder   │
│ filter chips · search · View menu · Group menu                      │
│ folder cards (grid / list)                                          │
│ photograph cards / rows + group headers                             │
└─────────────────────────────────────────────────────────────────────┘

DEVELOP
┌──────────── 286 ───────────┬──────── flexible ────────┬──── 342 ────┐
│ FILMS                      │ canvas                    │ DEVELOP      │
│ search / brand chips       │ photo + identity chip     │ histogram    │
│ film card grid             │ zoom / metadata           │ film card    │
│ footer status              ├──────── 88 ───────────────┤ LIGHT        │
│                            │ PHOTOS filmstrip          │ COLOR / CURVES│
│                            │                           │ fixed bar:   │
│                            │                           │ reset/export/│
│                            │                           │ settings     │
└────────────────────────────┴───────────────────────────┴──────────────┘
```

- Window: 1520 × 940 default, min 1180 × 740. Chrome-less title bar; the 46 pt
  title strip is the only window-drag surface. Traffic lights are drawn inside it
  so they are vertically centred; an 84 pt leading inset keeps content clear.
- Library root shows folders and directly imported photographs. Folder pages
  replace those with subfolders and the folder's photographs, with breadcrumbs.
- Hairline separators are 1 px `rgba(255,255,255,.045)`; no black borders.
- Panels are surface-1; canvas is surface-0; selected cards are surface-2.

## Tokens

| Token | Value |
| --- | --- |
| surface-0 | `#0B0B0B` |
| surface-1 | `#151515` |
| surface-2 | `#1A1A19` |
| surface-3 | `#20201F` |
| surface-4 | `#262624` |
| text primary | `#FFFFFF` |
| text secondary | white 62% |
| text tertiary | white 42% |
| text quaternary | white 26% |
| hairline | white 4.5% |
| accent (brass) | `#C8A97E` |
| accent strong | `#D9BD95` |
| danger | `#C7705D` |

Adjacent surfaces move 1–3% in luminance. The only accent is brass; no second hue
competes with the photograph. Selection is brass stroke + surface-2, not a filled
colour block. Focus is a soft double ring + shadow, never a bright outline.

## Type

SF Pro, one family. Dark-mode compensation: weights step down (regular where 500
would be, medium where 600 would be). Section labels are 8.5–10 pt uppercase with
1.2–1.7 tracking. Values use monospaced digits (`tabular-nums` equivalent) so
exposure, strength and percentages never shift. Film names are 11–14 pt; the empty
state title is 26 pt. No display face, no gradient text, no all-caps body copy.

## Components

- **Film card**: 2-column grid, 72 pt thumbnail, name / brand / type / ISO. Dynamic
  previews of the current photo replace static swatches once a photo is open.
  Selected = brass 72% stroke + surface-2, plus a 3.5 pt brass dot. Star sits
  outside the card button so favouriting never applies the film.
- **Chips**: 22–26 pt height, 6 pt radius, surface-1; selected = brass 10% tint +
  brass 25% stroke + brass text. No filled accent chips except primary actions.
- **Sliders**: native macOS mini slider tinted brass, label left, monospaced value
  right, double-click label resets. No custom thumb that fights the platform.
- **Inspector sections**: chevron + uppercase label, 0 → content layout animation
  at 280 ms `cubic-bezier(.16,1,.3,1)`. Light starts open; Effects and Information
  start closed.
- **Histogram**: luma fill at 10% white, RGB curves at 45% additive, global log
  normalization, 1 px grid, 5-tap display smoothing.
- **Transparency panel**: two 0–100 sliders (明暗通透 / 颜色通透), a measured
  `black–white%` readout, cast description (`高光偏黄 · 阴影偏青`) and an Analyze
  action. The panel stays open by default because it is a signature feature.
- **LUT cards**: identity swatch, name, `size³ · 自定义 LUT`, brass selection
  border. Import tile uses a quiet plus, not a loud CTA.
- **Language**: Chinese default, English switch in Settings; all in-app copy,
  tooltips and custom menus re-render immediately. macOS system menu names stay
  OS-controlled.
- **Top bar**: 46 pt; photo identity on the left in one line, Reset / Export /
  Settings on the right, wordmark at the far right. Import moved out of the bar.
- **Canvas Original**: a glass button at the canvas top-left opens a draggable
  vertical split (original left, developed right) with two tiny labels and a
  brass chevron handle.
- **Inspector tabs**: Light / Color / Curves with a matched-geometry selection
  pill and a directional horizontal slide. Transparency, Detail, Film Texture and
  Information remain below the tabs.
- **Curves**: 158 pt histogram-backed editor with luma/R/G/B channel chips and
  five PCHIP control points; line colours follow the channel.
- **Motion**: iOS-like spring (`response 0.34, damping 0.82`) for tabs, cards,
  panels and compare; canvas zoom/pan uses a 120 Hz damped follow with a curved
  wheel response. Space animates back to fit.
- **Canvas chips**: material glass only for floating overlays (film identity,
  before, zoom); it is an effect, not page decoration.
- **Toast**: surface-3, 94% opacity, offset blur shadow, auto-dismiss at 2.5 s.
- **Empty state**: a drawn film frame with sprocket holes and a brass aperture;
  "Begin with a photograph." with one Chinese supporting line; import button;
  format breadcrumb. No numbered steps.

## Motion

- Panel open/close: 280 ms expo-out.
- Hover: 180 ms expo-out.
- Toast: spring 0.32 s, 2.5 s lifetime.
- Photo switch: 280 ms cross-fade; no orchestrated page load.
- Zoom/pan: direct, zero-lag, over-damped; no bounce.

## Copy

Short, direct, photographic: "Before", "Develop", "Film strength", "Print / render",
"Exposure", "Halation", "Grain". Errors name the file and the recovery. The empty
state teaches the first action in one sentence.

## Verification

Screenshot at 1500 × 925: empty library, populated library, one photo with Portra
400, before/after, export sheet. Check:
- no hard black borders;
- selected card legible;
- every slider value uses monospaced digits;
- no clipped labels at 1180 pt minimum;
- contrast of secondary text on surface-0;
- all 113 looks reachable through search and variants.

## Constraints

- No nested cards as page structure. The inspector film card is a single card.
- No coloured left borders, no gradients as text, no emoji icons.
- Platform affordances win: native sliders, menus, file panels, focus rings.
