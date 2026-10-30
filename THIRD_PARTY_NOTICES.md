# Third-party notices and license scope

OltraFlim is a mixed-license repository. The application source is
noncommercial; some bundled film assets come from upstream projects whose
licenses allow broader use. This file explains which license applies to what.

## 1. License map

| Path / material | License | Commercial use |
| --- | --- | --- |
| `Sources/OltraFlim/**` (original Swift/Metal code) | PolyForm Noncommercial 1.0.0 (`LICENSE`) | Not permitted |
| Original documentation: `README.md`, `CODE_MAP.md`, `STATUS.md`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/**` | PolyForm Noncommercial 1.0.0 | Not permitted |
| `Resources/LUTs/*.bin`, LUT swatches and the film-look data encoded in `Resources/catalog.json` | CC BY-SA 4.0 (spektrafilm derivatives) | Permitted by upstream; attribution + share-alike required |
| `Tools/build_luts.py` (OltraFlim build tool) | PolyForm Noncommercial 1.0.0 | Not permitted |
| ACES 2.0 transform and OpenColorIO built-ins used during LUT baking | Academy / OpenColorIO licenses | See upstream terms |
| `Resources/AppIcon.icns` and OLTRAFLIM name/logo | Oltra brand material; no trademark license granted | Not permitted without permission |
| `Resources/Sample/sample_preview.jpg` | Project demonstration material derived from the owner's photograph | Not a standalone stock image; do not redistribute separately |
| `Resources/SPEKTRAFILM_LICENSE.txt`, `Resources/LUT_NOTICE.md` | Upstream notices; do not modify | Follow upstream terms |

The noncommercial restriction applies to the **application code and original
documentation**. It does not attempt to relicense upstream LUT/profile data.
If an upstream license grants rights that this repository's code license does
not, those rights remain available for that upstream material alone.

## 2. spektrafilm / film LUTs

- Project: **spektrafilm** by Andrea Volpato
  <https://github.com/andreavolpato/spektrafilm>
- Reference implementation: GPLv3. **No spektrafilm source code is copied into
  this repository.** The OltraFlim renderer is a separate Swift + Metal
  implementation.
- Profiles and direct derivatives, including LUTs: **CC BY-SA 4.0**.
  The full upstream notice is in `Resources/SPEKTRAFILM_LICENSE.txt`.
- The 113 display-ready LUTs under `Resources/LUTs/` are combinations of
  spektrafilm profile data and an ACES 2.0 SDR 100-nit Rec.709 output
  transform. They are shared under CC BY-SA 4.0. Attribution to spektrafilm is
  required on copies and derivatives. The upstream notice states that
  commercial use of the LUT data is permitted, while resale of the LUT pack
  alone is not.
- OltraFlim's own LUT baking/organisation code and catalog structure are
  original work and are covered by the repository's noncommercial code license.

## 3. ACES / OpenColorIO

The LUT pack was baked offline with OpenColorIO 2.6 using the **ACES 2.0 SDR
100-nit Rec.709** output transform. ACES is a project of the Academy of Motion
Picture Arts and Sciences. OpenColorIO is an Academy Software Foundation
project. Their names, transform data and license terms belong to their
respective owners. No ACES or OpenColorIO runtime library is shipped in the app.

## 4. Sample preview

`Resources/Sample/sample_preview.jpg` is a reduced, sRGB preview derived from a
DNG supplied by the project owner for interface previews. It is included only
as demonstration material for this project. It is not a generic stock photo and
is not licensed for separate redistribution or commercial use.

## 5. Trademarks

OLTRAFLIM, the OLTRAFLIM mark and the brass-ring app icon identify the Oltra
project. The repository license does not grant permission to use these marks
for a different product, or to imply endorsement.

## 6. Reporting an attribution problem

If you believe an asset is missing attribution or is covered by a different
license, open an issue in the repository before redistributing it. Do not remove
`Resources/SPEKTRAFILM_LICENSE.txt` or `Resources/LUT_NOTICE.md` from a build
that contains the LUT pack.
