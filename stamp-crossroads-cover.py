#!/usr/bin/env python3
"""
================================================================================
ARCHITECTURAL BLOCK COMMENT: stamp-crossroads-cover.py
================================================================================
PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
    Interactive branching novels in our library are published under the
    **RaggieSoft Story Crossroads** imprint. To help readers immediately spot an
    interactive branching novel on the bookshelf, this Python script uses the
    **Pillow (`PIL`)** image-processing library to stamp a crisp circular Story
    Crossroads medallion (complete with a soft drop-shadow halo) onto both the
    vertical `2:3` book cover and the horizontal `16:9` social-sharing cover!

WHEN IT RUNS:
    Manually (`./raggiesoft-deployment-tools/stamp-crossroads-cover.py --book <slug>`)
    right after generating raw cover artwork for any Story Crossroads interactive novel.

INPUTS & OUTPUTS:
    - Reads:
        * Seal PNGs: `raggiesoft-assets/raggiesoft-books/images/logos/story-crossroads-seal-{2,3}way.png`
        * Branching Manifest: `raggiesoft-narratives/books/<slug>/crossroads.json` (or `ovab.json`)
        * Base Cover Artwork: `raggiesoft-books/images/covers/{2x3,og}/<slug>.jpg` (or `--input`)
    - Writes:
        * Stamped JPEG/PNG cover files with pixel-accurate safe-zone margins and
          Gaussian-blurred alpha drop shadows.

Design Decisions & Layout Geometry:
    - 2-Directional vs. 3-Directional Variant Selection:
      * `--directions 2` stamps `story-crossroads-seal-2way.png` (for binary
        Option A / Option B Crossroads novels).
      * `--directions 3` stamps `story-crossroads-seal-3way.png` (for multi-path
        Crossroads novels offering 3+ choices).
      * When `--book <slug>` is used without `--directions`, the script inspects
        `crossroads.json` (`ovab.json` fallback) and automatically selects `3`
        if any Crossroads has 3+ options, else `2`.
    - Aspect-Aware Safe-Zone Placement (`--position auto`):
      * Portrait (`2:3`, `h > w`): Places the medallion (`16.5%` of cover width)
        in the lower-right safe zone (`4.2%` from right edge, `8.8%` from bottom
        edge) so it sits cleanly above the centered bottom author line
        (`"A NOVEL BY MICHAEL RAGSDALE"`).
      * Landscape (`16:9` OG, `w >= h`): Places the medallion (`18.5%` of cover
        height) in the bottom-right corner (`2.8%` from right edge, `4.2%` from
        bottom edge) clear of the centered widescreen title and author credit.
    - Elevation Contrast Halo:
      * Applies a soft Gaussian-blurred drop shadow behind the circular `#0F4C5C`
        and `#E3B27C` medallion so the seal maintains crisp visual separation
        over both sunlit and dark cover illustrations.

Usage Examples:
    # Stamp both 2:3 and OG covers for a Crossroads book slug (auto-detecting 2 vs 3):
    ./raggiesoft-deployment-tools/stamp-crossroads-cover.py --book my-crossroads-novel

    # Stamp explicit input/output files with a 3-directional seal:
    ./raggiesoft-deployment-tools/stamp-crossroads-cover.py \
        --input raw-cover-2x3.jpg --output stamped-cover-2x3.jpg --directions 3
================================================================================
"""

# Standard-library imports + Pillow (`PIL`: Python Imaging Library fork)
import argparse
import json
import os
import sys
from PIL import Image, ImageFilter


# Resolve canonical workspace directories relative to `raggiesoft-deployment-tools/`:
# `__file__` is this script's path; `dirname` steps up one folder at a time.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WORKSPACE_ROOT = os.path.dirname(SCRIPT_DIR)
ASSETS_BOOKS_DIR = os.path.join(
    WORKSPACE_ROOT, "raggiesoft-servers", "raggiesoft-assets", "raggiesoft-books"
)
LOGOS_DIR = os.path.join(ASSETS_BOOKS_DIR, "images", "logos")
COVERS_2X3_DIR = os.path.join(ASSETS_BOOKS_DIR, "images", "covers", "2x3")
COVERS_OG_DIR = os.path.join(ASSETS_BOOKS_DIR, "images", "covers", "og")
NARRATIVES_BOOKS_DIR = os.path.join(
    WORKSPACE_ROOT, "raggiesoft-servers", "raggiesoft-narratives", "books"
)


def detect_book_directions(book_slug: str) -> int:
    """
    Inspects `books/<slug>/crossroads.json` (and `ovab.json` fallback) to
    determine whether any Story Crossroads in the novel offers 3 or more
    options. Defaults to 2 directions when binary or unspecified.
    """
    for filename in ("crossroads.json", "ovab.json"):
        manifest_path = os.path.join(NARRATIVES_BOOKS_DIR, book_slug, filename)
        if not os.path.isfile(manifest_path):
            continue
        try:
            with open(manifest_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            crossroads_list = data.get("crossroads", [])
            if isinstance(crossroads_list, list):
                for cx in crossroads_list:
                    options = cx.get("options", []) if isinstance(cx, dict) else []
                    # As soon as we see any Crossroads offering 3+ routes, return the 3-way signpost crest
                    if isinstance(options, list) and len(options) >= 3:
                        return 3
        except Exception:
            # Fall back cleanly if JSON parsing fails
            pass

    return 2


def load_cropped_seal(directions: int) -> Image.Image:
    """
    Loads the high-DPI 1024x1024 RGBA PNG Concept 3 seal for the requested
    direction count (2 or 3) and tight-crops transparent outer padding so
    percentage diameter calculations apply strictly to the visible medallion.
    """
    variant = 3 if directions >= 3 else 2
    seal_path = os.path.join(LOGOS_DIR, f"story-crossroads-seal-{variant}way.png")
    if not os.path.isfile(seal_path):
        raise FileNotFoundError(f"Missing Story Crossroads seal asset: {seal_path}")

    # HOW PILLOW `RGBA` & `.getbbox()` WORK:
    #   - `.convert("RGBA")` ensures every pixel has 4 channels: Red, Green, Blue,
    #     and **Alpha** (`0` = completely invisible/transparent, `255` = solid opaque).
    #   - `.getbbox()` finds the tight `(left, top, right, bottom)` rectangle enclosing
    #     all non-transparent pixels (`Alpha > 0`), stripping invisible outer margin!
    seal_rgba = Image.open(seal_path).convert("RGBA")
    bbox = seal_rgba.getbbox()
    return seal_rgba.crop(bbox) if bbox else seal_rgba


def stamp_cover_image(
    input_path: str,
    output_path: str,
    seal_img: Image.Image,
    position: str = "auto",
    scale_override: float = 0.0,
    jpeg_quality: int = 94,
) -> tuple[int, int, int]:
    """
    Composites the Story Crossroads circular seal onto `input_path` and writes
    the stamped result to `output_path`. Returns `(width, height, stamp_diameter)`.
    """
    # Convert JPEG cover to `RGBA` in memory so we can alpha-blend transparent layers onto it.
    # Pillow image coordinates start at `(0, 0)` in the **TOP-LEFT** corner (`+x` goes right, `+y` goes down).
    base = Image.open(input_path).convert("RGBA")
    width, height = base.size
    is_portrait = height > width

    # Compute target medallion diameter proportional to cover dimensions (enforcing >= 48px floor)
    if scale_override > 0.0:
        diam = int(round(min(width, height) * scale_override))
    elif is_portrait:
        diam = int(round(width * 0.165))
    else:
        diam = int(round(height * 0.185))

    diam = max(48, diam)

    # Resolve target `(x, y)` top-left coordinates for the stamp:
    # Because `(0, 0)` is top-left, placing an object of size `diam` near the right/bottom edge
    # is calculated as `width - diam - margin_x` and `height - diam - margin_y`.
    margin_x = int(round(width * (0.042 if is_portrait else 0.028)))
    margin_y_std = int(round(height * (0.036 if is_portrait else 0.042)))
    margin_y_above_author = int(round(height * 0.088))

    if position == "auto":
        x = width - diam - margin_x
        y = height - diam - (margin_y_above_author if is_portrait else margin_y_std)
    elif position == "bottom-right-above-author":
        x = width - diam - margin_x
        y = height - diam - margin_y_above_author
    elif position == "bottom-right":
        x = width - diam - margin_x
        y = height - diam - margin_y_std
    elif position == "bottom-left":
        x = margin_x
        y = height - diam - (margin_y_above_author if is_portrait else margin_y_std)
    elif position == "top-right":
        x = width - diam - margin_x
        y = margin_y_std
    elif position == "top-left":
        x = margin_x
        y = margin_y_std
    else:
        raise ValueError(f"Unsupported --position value: {position}")

    # Resize medallion using `LANCZOS`—the highest-quality mathematical resampling filter
    # for shrinking crisp line art and typography without jagged pixel stair-stepping ("aliasing").
    stamp = seal_img.resize((diam, diam), Image.Resampling.LANCZOS)

    # HOW THE GAUSSIAN DROP SHADOW IS BUILT IN 5 STEPS:
    #   1. Create an empty transparent `RGBA` canvas slightly larger (`+ pad * 2`) than the seal
    #      so the blurred shadow glow has room to spread outward without clipping at the edges.
    #   2. `stamp.split()[3]` extracts channel index `3` (the **Alpha** mask of the circular seal).
    #   3. Create a semi-transparent black square (`(0, 0, 0, 165)`) and paste it through `alpha_mask`
    #      so only the exact silhouette of the seal becomes dark shadow.
    #   4. Apply `ImageFilter.GaussianBlur` to soften that sharp dark silhouette into a smooth halo.
    #   5. `.alpha_composite(...)` layers first the shadow (nudged down slightly by `shadow_offset_y`
    #      to simulate overhead gallery lighting) and then the crisp `stamp` right on top!
    pad = max(8, int(round(diam * 0.12)))
    shadow = Image.new("RGBA", (diam + pad * 2, diam + pad * 2), (0, 0, 0, 0))
    alpha_mask = stamp.split()[3]
    dark_disc = Image.new("RGBA", (diam, diam), (0, 0, 0, 165))
    shadow.paste(dark_disc, (pad, pad), alpha_mask)
    blur_radius = max(3, int(round(diam * 0.04)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=blur_radius))

    shadow_offset_y = max(2, int(round(diam * 0.02)))
    base.alpha_composite(shadow, (x - pad, y - pad + shadow_offset_y))
    base.alpha_composite(stamp, (x, y))

    # Ensure parent output directory exists (`exist_ok=True` is Python's `mkdir -p`).
    # Note: JPEG files do NOT support an Alpha channel (`RGBA`), so we flatten back to
    # 3-channel `RGB` (`base.convert("RGB")`) before saving `.jpg`!
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    ext = os.path.splitext(output_path)[1].lower()
    if ext == ".png":
        base.save(output_path, format="PNG", optimize=True)
    else:
        base.convert("RGB").save(output_path, format="JPEG", quality=jpeg_quality, optimize=True)

    return width, height, diam


def main() -> int:
    # `argparse.ArgumentParser` builds a self-documenting CLI (`--help`, type checks, allowed `choices`)
    parser = argparse.ArgumentParser(
        description="Stamp the RaggieSoft Story Crossroads Imprint Seal onto 2:3 and 16:9 OG book covers."
    )
    parser.add_argument(
        "--book",
        help="Book slug under raggiesoft-books/images/covers/{2x3,og}/<slug>.jpg",
    )
    parser.add_argument(
        "--input",
        help="Explicit input cover image path (used when not stamping by --book slug)",
    )
    parser.add_argument(
        "--output",
        help="Explicit output cover image path (defaults to overwriting --input when omitted)",
    )
    parser.add_argument(
        "--directions",
        type=int,
        choices=[2, 3],
        default=None,
        help="Signpost variant: 2 (Option A/B) or 3 (3+ options). Auto-detected from ovab.json when --book is used.",
    )
    parser.add_argument(
        "--position",
        choices=[
            "auto",
            "bottom-right",
            "bottom-right-above-author",
            "bottom-left",
            "top-right",
            "top-left",
        ],
        default="auto",
        help="Corner placement for the seal (default: auto safe-zone per aspect ratio).",
    )
    parser.add_argument(
        "--scale",
        type=float,
        default=0.0,
        help="Optional custom diameter ratio relative to min(width, height).",
    )

    args = parser.parse_args()

    if not args.book and not args.input:
        parser.error("Provide either --book <slug> or --input <image_path>.")

    # Mode A: `--book <slug>` automatically stamps BOTH `2x3/<slug>.jpg` and `og/<slug>.jpg` in-place
    if args.book:
        directions = args.directions or detect_book_directions(args.book)
        seal_img = load_cropped_seal(directions)
        targets = [
            ("2:3 Cover", os.path.join(COVERS_2X3_DIR, f"{args.book}.jpg")),
            ("16:9 OG Cover", os.path.join(COVERS_OG_DIR, f"{args.book}.jpg")),
        ]
        stamped_any = False
        for label, path in targets:
            if os.path.isfile(path):
                w, h, d = stamp_cover_image(
                    path, path, seal_img, position=args.position, scale_override=args.scale
                )
                print(
                    f"[OK] Stamped {directions}-way Story Crossroads seal ({d}px) onto {label}: {path} ({w}x{h})"
                )
                stamped_any = True
            else:
                print(f"[SKIP] {label} not found at {path}", file=sys.stderr)
        return 0 if stamped_any else 1

    # Mode B: `--input <path>` (and optional `--output <path>`) stamps a single arbitrary image file
    directions = args.directions or 2
    seal_img = load_cropped_seal(directions)
    out_path = args.output or args.input
    w, h, d = stamp_cover_image(
        args.input, out_path, seal_img, position=args.position, scale_override=args.scale
    )
    print(
        f"[OK] Stamped {directions}-way Story Crossroads seal ({d}px) -> {out_path} ({w}x{h})"
    )
    return 0


if __name__ == "__main__":
    # Pass `main()`'s integer return value (`0` = OK, `1` = error) to the OS shell via `sys.exit(...)`
    sys.exit(main())
