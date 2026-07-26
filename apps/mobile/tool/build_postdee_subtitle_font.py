"""Build PostDee subtitle-only derivatives for every selectable Thai font.

Requires the development-only ``fonttools`` package. The generated font keeps
normal Thai glyphs unchanged and adds four private-use glyphs for tone marks
stacked above another upper mark. Mobile substitutes those glyphs only in the
temporary SRT sent to libass, so saved and editable captions remain Unicode
Thai.
"""

from copy import deepcopy
from pathlib import Path
import shutil

from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets" / "fonts"
OUTPUT_DIR = ROOT / "assets" / "fonts" / "postdee_subtitle"
TONE_MARKS = ("uni0E48", "uni0E49", "uni0E4A", "uni0E4B")
FIRST_PRIVATE_CODE_POINT = 0xE000
DERIVATIVES = (
    (
        "baijamjuree/BaiJamjuree-Bold.ttf",
        "PostDeeSubtitleThai-Bold.ttf",
        "PostDee Subtitle Thai",
        "Bold",
    ),
    *(
        (
            f"anuphan/Anuphan-{weight}.ttf",
            f"PostDeeSubtitleAnuphan-{weight}.ttf",
            "PostDee Subtitle Anuphan",
            weight,
        )
        for weight in ("Regular", "Medium", "SemiBold", "Bold")
    ),
    *(
        (
            f"prompt/Prompt-{weight}.ttf",
            f"PostDeeSubtitlePrompt-{weight}.ttf",
            "PostDee Subtitle Prompt",
            weight,
        )
        for weight in (
            "Regular",
            "Medium",
            "SemiBold",
            "Bold",
            "ExtraBold",
            "Black",
        )
    ),
)


def _replace_names(font: TTFont, family: str, subfamily: str) -> None:
    postscript_family = family.replace(" ", "")
    values = {
        1: family,
        2: subfamily,
        3: f"PostDee:{postscript_family}:{subfamily}:2026.07.27.2",
        4: f"{family} {subfamily}",
        5: "Version 1.000",
        6: f"{postscript_family}-{subfamily}",
        16: family,
        17: subfamily,
    }
    names = font["name"]
    for name_id, value in values.items():
        names.removeNames(nameID=name_id)
        names.setName(value, name_id, 3, 1, 0x409)
        names.setName(value, name_id, 1, 0, 0)


def _validate_font(output_font: Path, family: str) -> None:
    font = TTFont(output_font, recalcBBoxes=False, recalcTimestamp=False)
    glyph_order = font.getGlyphOrder()
    cmap = font.getBestCmap()
    mark_classes = font["GDEF"].table.GlyphClassDef.classDefs

    protected_glyphs = [
        glyph_name
        for glyph_name in glyph_order
        if glyph_name.startswith("postdeeTone")
    ]
    if len(protected_glyphs) != len(TONE_MARKS):
        raise RuntimeError(
            f"{output_font.name} contains {len(protected_glyphs)} protected "
            f"glyphs instead of {len(TONE_MARKS)}"
        )

    for index in range(len(TONE_MARKS)):
        target_name = f"postdeeTone{index + 1}"
        if glyph_order.count(target_name) != 1:
            raise RuntimeError(f"{output_font.name} has a duplicate {target_name}")
        if cmap.get(FIRST_PRIVATE_CODE_POINT + index) != target_name:
            raise RuntimeError(f"{output_font.name} has an invalid PUA cmap")
        if mark_classes.get(target_name) != 3:
            raise RuntimeError(f"{output_font.name} does not classify {target_name} as a mark")

    family_names = {
        record.toUnicode()
        for record in font["name"].names
        if record.nameID == 1
    }
    if family not in family_names:
        raise RuntimeError(f"{output_font.name} has an invalid family name")


def _build_derivative(
    source_font: Path,
    output_font: Path,
    family: str,
    subfamily: str,
) -> None:
    font = TTFont(source_font, recalcBBoxes=False)
    # Keep the source font timestamp so rebuilding an unchanged derivative
    # produces the same bytes instead of dirtying the Git worktree.
    font.recalcTimestamp = False
    glyphs = font["glyf"]
    mark_classes = font["GDEF"].table.GlyphClassDef.classDefs

    for index, base_name in enumerate(TONE_MARKS):
        source_name = f"{base_name}.small"
        target_name = f"postdeeTone{index + 1}"
        glyphs[target_name] = deepcopy(glyphs[source_name])
        font["hmtx"].metrics[target_name] = font["hmtx"].metrics[source_name]
        mark_classes[target_name] = mark_classes[source_name]
        for table in font["cmap"].tables:
            if table.isUnicode():
                table.cmap[FIRST_PRIVATE_CODE_POINT + index] = target_name

    _replace_names(font, family, subfamily)
    if "DSIG" in font:
        del font["DSIG"]

    font["head"].yMax = max(
        font["head"].yMax,
        max(
            glyph.yMax
            for glyph in glyphs.glyphs.values()
            if hasattr(glyph, "yMax")
        ),
    )
    font.recalcBBoxes = False
    font.save(output_font)
    _validate_font(output_font, family)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for source_name, output_name, family, subfamily in DERIVATIVES:
        _build_derivative(
            SOURCE_DIR / source_name,
            OUTPUT_DIR / output_name,
            family,
            subfamily,
        )
    shutil.copyfile(
        SOURCE_DIR / "baijamjuree" / "OFL.txt",
        OUTPUT_DIR / "OFL.txt",
    )


if __name__ == "__main__":
    main()
