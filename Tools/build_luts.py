#!/usr/bin/env python3
"""
Build OltraFlim's compact film-LUT pack and catalog.

Input: the Alcedo/SpektraFilm .cube export (65^3 ACEScc -> ACEScc LMTs).
Output: 33^3 RGBA16F LUT textures (ACEScc -> gamma-2.2 Rec.709) + catalog.json.

The display render is the ACES 2.0 SDR 100-nit Rec.709 output transform
(from OpenColorIO's ACES 2.0 builtin), so the exported film looks match the
reference pipeline used to generate these LMTs.

Requires: PyOpenColorIO, numpy (see Tools/requirements.txt).
Usage:
  /path/to/python Tools/build_luts.py --source "/path/to/Alcedo_LUT_导出" \
      --out Resources
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import struct
import sys
from dataclasses import dataclass, field

import numpy as np
import PyOpenColorIO as ocio
from PIL import Image


# ---------------------------------------------------------------------------
# Color math
# ---------------------------------------------------------------------------

CONFIG = ocio.Config.CreateFromBuiltinConfig("ocio://default")


def _matrix(src: str, dst: str) -> np.ndarray:
    processor = CONFIG.getProcessor(src, dst)
    cpu = processor.getDefaultCPUProcessor()
    m = np.zeros((3, 3), dtype=np.float32)
    for i in range(3):
        v = np.zeros((1, 3), dtype=np.float32)
        v[0, i] = 1.0
        cpu.applyRGB(v)
        m[:, i] = v[0]
    return m


M_R709_TO_AP1 = _matrix("Linear Rec.709 (sRGB)", "ACEScg")
M_AP1_TO_AP0 = _matrix("ACEScg", "ACES2065-1")

DISPLAY_PROCESSOR = CONFIG.getProcessor(
    ocio.DisplayViewTransform(
        src="ACES2065-1",
        display="Gamma 2.2 Rec.709 - Display",
        view="ACES 2.0 - SDR 100 nits (Rec.709)",
    )
).getDefaultCPUProcessor()


def acescc_encode(x: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=np.float64)
    return np.where(
        x <= 0,
        (math.log2(1.0 / 65536.0) + 9.72) / 17.52,
        np.where(
            x < 0.000061,
            (np.log2(0.000061 + x) + 9.72) / 17.52,
            (np.log2(np.maximum(x, 1e-10)) + 9.72) / 17.52,
        ),
    )


def acescc_decode(y: np.ndarray) -> np.ndarray:
    y = np.asarray(y, dtype=np.float64)
    return np.where(
        y <= 0,
        0.0,
        np.where(
            y < (math.log2(0.000061) + 9.72) / 17.52,
            2.0 ** (y * 17.52 - 9.72) - 0.000061,
            2.0 ** (y * 17.52 - 9.72),
        ),
    )


def read_cube(path: str) -> tuple[np.ndarray, int]:
    size = None
    values: list[list[float]] = []
    with open(path, "r", errors="ignore") as handle:
        for line in handle:
            s = line.strip()
            if not s or s.startswith("#") or s.startswith("TITLE") or s.startswith("DOMAIN"):
                continue
            if s.startswith("LUT_3D_SIZE"):
                size = int(s.split()[-1])
                continue
            if s.startswith("LUT_1D_SIZE"):
                raise ValueError("1D LUT is not supported")
            parts = s.split()
            if len(parts) == 3:
                try:
                    values.append([float(parts[0]), float(parts[1]), float(parts[2])])
                except ValueError:
                    continue
    if size is None:
        raise ValueError(f"missing LUT_3D_SIZE in {path}")
    data = np.asarray(values, dtype=np.float32)
    if data.shape[0] != size ** 3:
        raise ValueError(f"expected {size}^3 entries in {path}, got {data.shape[0]}")
    # .cube order: red varies fastest, then green, then blue.
    return data.reshape(size, size, size, 3), size


def sample_cube(cube: np.ndarray, xyz: np.ndarray) -> np.ndarray:
    """Trilinear sample of a cube laid out [b][g][r][rgb] with xyz in 0..1."""
    n = cube.shape[0]
    xyz = np.clip(xyz, 0.0, 1.0)
    q = xyz * (n - 1)
    i0 = np.floor(q).astype(np.int64)
    i1 = np.minimum(i0 + 1, n - 1)
    t = q - i0
    r0, g0, b0 = i0[:, 0], i0[:, 1], i0[:, 2]
    r1, g1, b1 = i1[:, 0], i1[:, 1], i1[:, 2]
    tr, tg, tb = t[:, 0:1], t[:, 1:2], t[:, 2:3]
    c00 = cube[b0, g0, r0] * (1 - tr) + cube[b0, g0, r1] * tr
    c01 = cube[b0, g1, r0] * (1 - tr) + cube[b0, g1, r1] * tr
    c10 = cube[b1, g0, r0] * (1 - tr) + cube[b1, g0, r1] * tr
    c11 = cube[b1, g1, r0] * (1 - tr) + cube[b1, g1, r1] * tr
    c0 = c00 * (1 - tg) + c01 * tg
    c1 = c10 * (1 - tg) + c11 * tg
    return c0 * (1 - tb) + c1 * tb


def acscc_to_display(cc: np.ndarray) -> np.ndarray:
    """ACEScc (AP1) values -> gamma-2.2 encoded Rec.709 via ACES 2.0 SDR."""
    ap1 = acescc_decode(cc)
    ap0 = (ap1 @ M_AP1_TO_AP0.T).astype(np.float32)
    display = ap0.copy()
    DISPLAY_PROCESSOR.applyRGB(display)
    return np.clip(display, 0.0, 1.0)


def build_lut(cube: np.ndarray, cube_size: int, out_size: int, exposure_ev: float) -> np.ndarray:
    axis = np.linspace(0.0, 1.0, out_size, dtype=np.float32)
    # [z][y][x] slices with x/r fastest: exactly Metal's 3D texture layout.
    # meshgrid("ij") makes B vary on axis 0, G on axis 1, R on axis 2.
    b, g, r = np.meshgrid(axis, axis, axis, indexing="ij")
    xyz = np.stack([r, g, b], axis=-1).reshape(-1, 3)
    if exposure_ev:
        # ACEScc is logarithmic: one stop is 1/17.52 in ACEScc.
        xyz = np.clip(xyz + exposure_ev / 17.52, 0.0, 1.0)
    film_cc = sample_cube(cube, xyz)
    display = acscc_to_display(film_cc)
    rgba = np.empty((out_size, out_size, out_size, 4), dtype=np.float16)
    rgba[..., :3] = display.reshape(out_size, out_size, out_size, 3)
    rgba[..., 3] = 1.0
    return rgba


def build_neutral(out_size: int, exposure_ev: float) -> np.ndarray:
    axis = np.linspace(0.0, 1.0, out_size, dtype=np.float32)
    b, g, r = np.meshgrid(axis, axis, axis, indexing="ij")
    xyz = np.stack([r, g, b], axis=-1).reshape(-1, 3)
    if exposure_ev:
        xyz = np.clip(xyz + exposure_ev / 17.52, 0.0, 1.0)
    display = acscc_to_display(xyz)
    rgba = np.empty((out_size, out_size, out_size, 4), dtype=np.float16)
    rgba[..., :3] = display.reshape(out_size, out_size, out_size, 3)
    rgba[..., 3] = 1.0
    return rgba


# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------

BRAND_ORDER = ["Kodak", "Fujifilm", "Agfa"]

@dataclass
class Look:
    lut_id: str
    file_name: str
    source: str
    brand: str
    film_name: str
    stock_id: str
    print_name: str | None
    variant_key: str | None
    title: str
    display_requirement: str | None
    note: str | None
    exposure_ev: float
    variant_label: str
    engine_label: str
    swatch: list[str] = field(default_factory=list)
    luminance: float = 0.5


def slug(text: str) -> str:
    text = text.lower()
    text = text.replace("+", " plus ")
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text


FILM_ALIASES = {
    "vision3 200t 5213": "Vision3 200T",
    "vision3 250d 5207": "Vision3 250D",
    "vision3 500t 5219": "Vision3 500T",
    "vision3 50d 5203": "Vision3 50D",
    "vision 320t 5277": "Vision 320T",
    "verita 200d 5206": "Verita 200D",
    "exr 100t 5248": "EXR 100T",
    "exr 200t 5293": "EXR 200T",
    "superia x-tra 400": "Superia X-Tra 400",
    "x-tra 400": "Superia X-Tra 400",
    "portra 800 @1600": "Portra 800 · Push 1",
    "portra 800 (push 1)": "Portra 800 · Push 1",
    "portra 800 @3200": "Portra 800 · Push 2",
    "portra 800 (push 2)": "Portra 800 · Push 2",
}


def norm_film_name(name: str) -> str:
    return FILM_ALIASES.get(name.strip().lower(), name.strip())


def classify(name: str) -> tuple[str, int | None, bool]:
    low = name.lower()
    if "aerochrome" in low:
        return "special", None, 0
    if "instax" in low or "fp-100c" in low:
        return "instant", None, 0
    if any(k in low for k in ["vision", "exr", "verita", "eterna", "5247", "5248", "5250"]):
        iso = None
        m = re.search(r"(\d{2,3})[dt]", low)
        if m:
            iso = int(m.group(1))
        if "cinema" not in low:
            return "cinema", iso, 0
    if any(k in low for k in ["ektachrome", "provia", "velvia", "kodachrome"]):
        m = re.search(r"(\d{2,4})", low)
        return "slide", int(m.group(1)) if m else None, 0
    if any(k in low for k in ["portra", "gold", "ultramax", "ektar", "c200", "pro 160", "pro 400h",
                              "natura", "superia", "vista", "aerocolor", "vericolor", "xtra", "x-tra"]):
        m = re.search(r"(\d{3,4})", low)
        iso = int(m.group(1)) if m else None
        push = 1 if "push 1" in low else 2 if "push 2" in low else 0
        return "negative", iso, push
    return "negative", None, 0


def variant_labels(meta: dict) -> tuple[str, str, float]:
    source = meta["source"]["id"]
    variant = meta.get("variant")
    print_name = (meta.get("print") or {}).get("name")
    if source == "spektrafilm_lut":
        engine = "SpektraFilm"
        exposure = 1.5
        if print_name:
            short = (print_name
                     .replace("Professional ", "")
                     .replace("Portra Endura", "Endura")
                     .replace("Crystal Archive Type II", "Crystal Archive")
                     .replace("Vision Premier 2393", "2393")
                     .replace("Vision 2383", "2383"))
            label = short
        else:
            label = "Slide"
        return label, engine, exposure
    engine = "Spectral Film"
    exposure = 0.0
    if variant == "adx-printdensity-gammacal":
        return "ADX density", engine, exposure
    if variant == "adx":
        return "ADX", engine, exposure
    if print_name:
        short = (print_name
                 .replace("Paper", "")
                 .replace("Portra Endura", "Endura")
                 .strip())
        return f"{short} · SDR", engine, exposure
    film_low = (meta.get("film") or {}).get("name", "").lower()
    if "aerochrome" in film_low:
        return "Infrared", engine, exposure
    if "instax" in film_low or "fp-100c" in film_low:
        return "Print", engine, exposure
    if any(k in film_low for k in ("velvia", "provia", "ektachrome", "kodachrome")):
        return "Slide", engine, exposure
    return "SDR", engine, exposure


SWATCH_COLORS = [
    (0.22, 0.42, 0.75),   # sky
    (0.55, 0.36, 0.28),   # skin
    (0.18, 0.42, 0.16),   # foliage
]


def swatch_for(lut: np.ndarray) -> tuple[list[str], float]:
    """Sample three real-world hues through the LUT so empty-state cards are
    differentiated by the film's actual colour response."""
    n = lut.shape[0]
    cc = []
    for rgb in SWATCH_COLORS:
        linear = np.asarray(rgb, dtype=np.float64)
        ap1 = M_R709_TO_AP1 @ linear
        cc.append(np.clip(acescc_encode(ap1), 0.0, 1.0))
    coords = np.asarray(cc, dtype=np.float32)
    samples = sample_cube(lut[..., :3].astype(np.float32), coords)
    hexes = ["#%02X%02X%02X" % tuple(int(round(min(1, max(0, v)) * 255)) for v in rgb) for rgb in samples]
    lum = float(np.mean([0.2126 * s[0] + 0.7152 * s[1] + 0.0722 * s[2] for s in samples]))
    return hexes, lum


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, help="Alcedo_LUT_导出 directory")
    parser.add_argument("--out", default="Resources", help="OltraFlim Resources directory")
    parser.add_argument("--size", type=int, default=33, choices=[17, 25, 33, 45, 65])
    args = parser.parse_args()

    source = os.path.abspath(args.source)
    out_dir = os.path.abspath(args.out)
    lut_dir = os.path.join(out_dir, "LUTs")
    os.makedirs(lut_dir, exist_ok=True)

    looks: list[Look] = []
    cubes: dict[str, tuple[np.ndarray, int]] = {}
    files = sorted(
        os.path.join(root, name)
        for root, _, names in os.walk(source)
        for name in names
        if name.lower().endswith(".cube")
    )
    print(f"found {len(files)} cubes", flush=True)

    for index, path in enumerate(files, 1):
        with open(path, "r", errors="ignore") as handle:
            header = handle.readline().strip()
        if not header.startswith("# ALCEDO_LUT "):
            print("skip (no metadata)", path)
            continue
        meta = json.loads(header[len("# ALCEDO_LUT "):])
        brand = (meta.get("film") or {}).get("brand", "Unknown")
        film_raw = (meta.get("film") or {}).get("name", "Unknown")
        film_name = norm_film_name(film_raw)
        stock_id = f"{slug(brand)}-{slug(film_name)}"
        label, engine, exposure = variant_labels(meta)
        display_req = meta.get("display_requirement")
        note = None
        with open(path, "r", errors="ignore") as handle:
            for line in handle:
                s = line.strip()
                if s.startswith("# neutralize="):
                    note = s[2:]
                if s.startswith("TITLE"):
                    break
        lut_id = slug(f"{meta['id']}")
        lut_id = lut_id.replace("spectral-film-lut-", "spc-").replace("spektrafilm-lut-", "spk-")
        out_lut = os.path.join(lut_dir, lut_id + ".bin")
        cube, cube_size = read_cube(path)
        cubes[lut_id] = (cube, cube_size)
        rgba = build_lut(cube, cube_size, args.size, exposure)
        rgba.tofile(out_lut)
        swatch, lum = swatch_for(rgba.astype(np.float32))
        looks.append(
            Look(
                lut_id=lut_id,
                file_name=os.path.basename(path),
                source=meta["source"]["id"],
                brand=brand,
                film_name=film_name,
                stock_id=stock_id,
                print_name=(meta.get("print") or {}).get("name"),
                variant_key=meta.get("variant"),
                title=meta.get("id", lut_id),
                display_requirement=display_req,
                note=note,
                exposure_ev=exposure,
                variant_label=label,
                engine_label=engine,
                swatch=swatch,
                luminance=lum,
            )
        )
        if index % 10 == 0:
            print(f"  {index}/{len(files)} {film_name} · {label}", flush=True)

    # Neutral ACES renders for look-strength blending.
    for ev, name in ((0.0, "neutral-0"), (1.5, "neutral-15")):
        build_neutral(args.size, ev).tofile(os.path.join(lut_dir, name + ".bin"))

    # Stock grouping and default selection.
    groups: dict[str, list[Look]] = {}
    for look in looks:
        groups.setdefault(look.stock_id, []).append(look)

    def look_rank(look: Look) -> tuple:
        # Prefer SpektraFilm, display-ready SDR variants, Endura paper, then 2383.
        src = 0 if look.source == "spektrafilm_lut" else 1
        var = 0 if look.variant_key in (None, "aces2-sdr") else 1
        # Pair Kodak emulsions with Endura and Fujifilm emulsions with Crystal
        # Archive; this is both more authentic and gives the two brands distinct
        # starting points.
        if look.brand == "Fujifilm":
            paper = 0 if look.print_name and "Crystal Archive" in look.print_name else 1
        else:
            paper = 0 if look.print_name and "Endura" in look.print_name else 1
        film = 0 if look.variant_key == "aces2-sdr" else 1
        return (src, var, paper, film, look.variant_label)

    stocks = []
    for stock_id, items in groups.items():
        items_sorted = sorted(items, key=look_rank)
        default = items_sorted[0]
        brand = default.brand
        name = default.film_name
        kind, iso, push = classify(name)
        # Variant chips are ordered default first, then the rest by label.
        variants = []
        seen_labels = set()
        for look in items_sorted:
            label = look.variant_label
            if label in seen_labels:
                label = f"{label} · {look.engine_label}"
            seen_labels.add(label)
            variants.append(
                {
                    "id": look.lut_id,
                    "label": label,
                    "engine": look.engine_label,
                    "source": look.source,
                    "print": look.print_name,
                    "variant": look.variant_key,
                    "exposureEV": look.exposure_ev,
                    "note": look.note,
                    "displayRequirement": look.display_requirement,
                    "lut": f"{look.lut_id}.bin",
                }
            )
        stocks.append(
            {
                "id": stock_id,
                "brand": brand,
                "name": name,
                "type": kind,
                "iso": iso,
                "push": push,
                "defaultLook": default.lut_id,
                "swatch": default.swatch,
                "luminance": default.luminance,
                "variants": variants,
            }
        )

    popularity = {
        "kodak-portra-400": 0, "kodak-portra-160": 1, "kodak-gold-200": 2,
        "kodak-portra-800": 3, "kodak-ultramax-400": 4, "kodak-ektar-100": 5,
        "fujifilm-c200": 6, "fujifilm-pro-400h": 7, "fujifilm-superia-x-tra-400": 8,
        "fujifilm-pro-160c": 9, "fujifilm-pro-160s": 10, "fujifilm-superia-reala": 11,
        "fujifilm-natura-1600": 12, "agfa-vista-100": 13,
        "kodak-portra-800-push-1": 14, "kodak-portra-800-push-2": 15,
        "kodak-ultramax-500": 16, "kodak-vericolor-iii": 17,
        "fujifilm-velvia-50": 18, "fujifilm-velvia-100": 19,
        "fujifilm-provia-100f": 20, "kodak-ektachrome-100": 21,
        "kodak-ektachrome-100d": 22, "kodak-kodachrome-64": 23,
        "fujifilm-instax-color": 24, "fujifilm-fp-100c": 25,
        "kodak-aerochrome-iii-infrared-film-1443": 26,
    }
    stocks.sort(key=lambda s: (
        popularity.get(s["id"], 100),
        BRAND_ORDER.index(s["brand"]) if s["brand"] in BRAND_ORDER else 99,
        s["name"].lower(),
    ))
    default_stock = next((s["id"] for s in stocks if s["id"] == "kodak-portra-400"), stocks[0]["id"])
    catalog = {
        "version": 1,
        "generated": "2026-10-29",
        "lutSize": args.size,
        "defaultStock": default_stock,
        "attribution": "Film modeling powered by spektrafilm by Andrea Volpato. "
                       "LUT pack derived from the Alcedo LUT export (CC BY-SA 4.0 / "
                       "commercial-use-no-resale). ACES 2.0 display transform via OpenColorIO.",
        "stocks": stocks,
        "looks": [
            {
                "id": l.lut_id,
                "stock": l.stock_id,
                "lut": f"{l.lut_id}.bin",
                "label": l.variant_label,
                "engine": l.engine_label,
                "source": l.source,
                "exposureEV": l.exposure_ev,
                "swatch": l.swatch,
            }
            for l in looks
        ],
    }
    with open(os.path.join(out_dir, "catalog.json"), "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2)

    # A compact license/attribution note shipped with the assets.
    with open(os.path.join(out_dir, "LUT_NOTICE.md"), "w", encoding="utf-8") as handle:
        handle.write(
            "# Film LUT pack\n\n"
            "This pack contains display-ready derivatives of LUTs exported from the "
            "open-source **spektrafilm** project by Andrea Volpato "
            "(https://github.com/andreavolpato/spektrafilm), via the Alcedo LUT export.\n\n"
            "- Film simulation: spektrafilm (GPLv3 reference implementation; "
            "LUTs/profile data CC BY-SA 4.0).\n"
            "- ACES 2.0 SDR Rec.709 output transform: Academy Color Encoding System / "
            "OpenColorIO 2.6 builtins.\n"
            "- Combined LUTs are shared under CC BY-SA 4.0. Commercial use of the "
            "spektrafilm LUT data is permitted; resale of the LUT pack alone is not.\n\n"
            "Regenerate with `Tools/build_luts.py`.\n"
        )

    print(f"wrote {len(looks)} LUTs ({args.size}^3) and {len(stocks)} stocks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
