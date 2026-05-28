#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Sources/NomiPetApp/Resources/NomiAssets/assets"
OUT_ROOT = Path(os.environ.get("NOMI_ASSET_OUT", str(ROOT / "dist/nomi-animation-assets"))).expanduser()
FRAME_SIZE = (384, 512)
GENERATED_ROOT = Path(os.environ.get("NOMI_GENERATED_ROOT", str(ROOT / "Sources/NomiPetApp/Resources/NomiAssets/assets/source/generated-rows"))).expanduser()


@dataclass(frozen=True)
class Animation:
    anim_id: str
    name: str
    category: str
    fps: int
    loop: bool
    status: str
    notes: str
    source: str
    row_path: Path | None = None


ANIMATIONS = [
    Animation(
        "concerned",
        "Concerned",
        "emotion",
        8,
        True,
        "new",
        "Failed or stalled task: restrained worried hand-to-mouth loop.",
        "imagegen-row",
        GENERATED_ROOT / "ig_04bdd72f1f2503cb016a16c0663e7081918de0be6725a25926.png",
    ),
    Animation(
        "nod",
        "Nod",
        "social",
        8,
        False,
        "new",
        "Completed/caring response: small restrained nod one-shot.",
        "imagegen-row",
        GENERATED_ROOT / "ig_04bdd72f1f2503cb016a16bfa5300c8191a9cd24602701cff9.png",
    ),
    Animation(
        "eat",
        "Eat / Drink",
        "ambient",
        8,
        False,
        "new",
        "Water or snack reminder: tiny drink prop and satisfied return.",
        "imagegen-row",
        GENERATED_ROOT / "ig_04bdd72f1f2503cb016a16c0d7165481919420a427c71b9573.png",
    ),
    Animation(
        "dance",
        "Dance",
        "ambient",
        8,
        True,
        "new",
        "Music detected: subtle side-to-side rhythm loop.",
        "imagegen-row",
        GENERATED_ROOT / "ig_04bdd72f1f2503cb016a16c13f5e008191b2119a08ae053d33.png",
    ),
    Animation(
        "headpat",
        "Headpat",
        "interaction",
        8,
        False,
        "new",
        "Right-click headpat: shy and comfortable one-shot.",
        "imagegen-row",
        GENERATED_ROOT / "ig_04bdd72f1f2503cb016a16c176e3c88191ba384c7dea6bd97e.png",
    ),
    Animation(
        "shrug",
        "Shrug",
        "emotion",
        8,
        False,
        "new",
        "Uncertain or casual response: restrained shrug one-shot.",
        "imagegen-row",
        GENERATED_ROOT / "ig_04bdd72f1f2503cb016a16c1ab98ac819199171acbc1ccb416.png",
    ),
    Animation(
        "peek",
        "Peek",
        "ambient",
        8,
        False,
        "new",
        "Quiet patrol: side peek and return one-shot.",
        "imagegen-row",
        GENERATED_ROOT / "ig_04bdd72f1f2503cb016a16c1e623288191a8b14b9aea52aab6.png",
    ),
    Animation(
        "worried",
        "Worried",
        "emotion",
        8,
        True,
        "new",
        "Late-night or tiredness: arms-crossed caring worry loop.",
        "imagegen-row",
        GENERATED_ROOT / "ig_04bdd72f1f2503cb016a16c220dfa48191bc5987f820cf6bb7.png",
    ),
    Animation(
        "pout",
        "Pout",
        "emotion",
        8,
        True,
        "existing",
        "Already drawn: bored pout loop.",
        "existing-frames",
    ),
    Animation(
        "wake_up",
        "Wake Up",
        "ambient",
        8,
        False,
        "existing",
        "Already drawn: sleepy wake-up one-shot.",
        "existing-frames",
    ),
    Animation(
        "walk_left",
        "Walk Left",
        "movement",
        10,
        True,
        "existing",
        "Already drawn: free walking left loop.",
        "existing-frames",
    ),
    Animation(
        "walk_right",
        "Walk Right",
        "movement",
        10,
        True,
        "existing",
        "Already drawn: free walking right loop.",
        "existing-frames",
    ),
]


def ensure_clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def transparentize_magenta(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = pixels[x, y]
            is_key = r > 210 and b > 210 and g < 90
            is_key_edge = r > 185 and b > 185 and g < 130 and abs(r - b) < 55
            if is_key or is_key_edge:
                pixels[x, y] = (0, 0, 0, 0)
    return rgba


def content_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A")
    return alpha.point(lambda p: 255 if p > 12 else 0).getbbox()


def split_generated_row(row_path: Path, anim_id: str) -> list[Image.Image]:
    if not row_path.exists():
        raise FileNotFoundError(row_path)

    row = Image.open(row_path).convert("RGBA")
    cell_w = row.width // 8
    cells = []
    boxes = []

    for i in range(8):
        crop = row.crop((i * cell_w, 0, (i + 1) * cell_w, row.height))
        clean = transparentize_magenta(crop)
        bbox = content_bbox(clean)
        if bbox is None:
            raise RuntimeError(f"{anim_id}/{i:03d}.png is blank after chroma removal")
        cells.append((clean, bbox))
        boxes.append(bbox)

    max_w = max(box[2] - box[0] for box in boxes)
    max_h = max(box[3] - box[1] for box in boxes)
    scale = min(330 / max_w, 458 / max_h)
    baseline = 500
    preserve_side_motion = anim_id in {"peek", "dance"}
    frames = []

    for clean, bbox in cells:
        sprite = clean.crop(bbox)
        resized = sprite.resize(
            (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))),
            Image.Resampling.LANCZOS,
        )
        canvas = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
        source_center = (bbox[0] + bbox[2]) / 2
        source_offset = (source_center - cell_w / 2) * scale
        if preserve_side_motion:
            x = round(FRAME_SIZE[0] / 2 - resized.width / 2 + source_offset)
        else:
            x = round(FRAME_SIZE[0] / 2 - resized.width / 2)
        x = max(-80, min(FRAME_SIZE[0] - resized.width + 80, x))
        y = baseline - resized.height
        canvas.alpha_composite(resized, (x, y))
        frames.append(canvas)

    return frames


def copy_existing_frames(anim: Animation) -> list[Image.Image]:
    src_dir = SOURCE_ROOT / "frames" / anim.anim_id
    if not src_dir.exists():
        raise FileNotFoundError(src_dir)
    frames = []
    for index in range(8):
        frame = Image.open(src_dir / f"{index:03d}.png").convert("RGBA")
        if frame.size != FRAME_SIZE:
            frame = frame.resize(FRAME_SIZE, Image.Resampling.LANCZOS)
        frames.append(frame)
    return frames


def save_frames(anim: Animation, frames: list[Image.Image]) -> None:
    frame_dir = OUT_ROOT / "assets/frames" / anim.anim_id
    frame_dir.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(frames):
        frame.save(frame_dir / f"{index:03d}.png")


def save_raw_strip(anim: Animation, frames: list[Image.Image]) -> None:
    raw_dir = OUT_ROOT / "assets/raw-strips"
    raw_dir.mkdir(parents=True, exist_ok=True)
    strip = Image.new("RGBA", (FRAME_SIZE[0] * 8, FRAME_SIZE[1]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME_SIZE[0], 0))
    strip.save(raw_dir / f"{anim.anim_id}.png")


def save_preview(anim: Animation, frames: list[Image.Image]) -> None:
    preview_dir = OUT_ROOT / "assets/previews"
    preview_dir.mkdir(parents=True, exist_ok=True)
    duration = round(1000 / anim.fps)
    frames[0].save(
        preview_dir / f"{anim.anim_id}.gif",
        save_all=True,
        append_images=frames[1:],
        duration=duration,
        loop=0 if anim.loop else 1,
        disposal=2,
        transparency=0,
    )


def copy_sources() -> None:
    source_dir = OUT_ROOT / "assets/source"
    source_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE_ROOT / "source/nomi-base.png", source_dir / "nomi-base.png")

    gen_dir = OUT_ROOT / "assets/source/generated-rows"
    gen_dir.mkdir(parents=True, exist_ok=True)
    for anim in ANIMATIONS:
        if anim.row_path is not None:
            shutil.copy2(anim.row_path, gen_dir / f"{anim.anim_id}-imagegen-row.png")


def write_manifest() -> None:
    animations = []
    for anim in ANIMATIONS:
        animations.append(
            {
                "id": anim.anim_id,
                "name": anim.name,
                "category": anim.category,
                "fps": anim.fps,
                "loop": anim.loop,
                "status": anim.status,
                "source": anim.source,
                "frameSize": list(FRAME_SIZE),
                "frames": [
                    f"assets/frames/{anim.anim_id}/{index:03d}.png"
                    for index in range(8)
                ],
                "preview": f"assets/previews/{anim.anim_id}.gif",
                "rawStrip": f"assets/raw-strips/{anim.anim_id}.png",
                "notes": anim.notes,
            }
        )

    payload = {
        "name": "Nomi additional animation asset pack",
        "version": "0.2.0",
        "character": {
            "id": "nomi",
            "displayName": "Nomi",
            "source": "assets/source/nomi-base.png",
        },
        "format": {
            "type": "transparent-png-frame-sequence",
            "frameSize": list(FRAME_SIZE),
            "framesPerAnimation": 8,
        },
        "animations": animations,
    }
    (OUT_ROOT / "manifest.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def write_readme() -> None:
    lines = [
        "# Nomi Animation Asset Pack",
        "",
        "This folder contains finished Nomi animation materials for app integration.",
        "",
        "## Structure",
        "",
        "- `assets/frames/<animation_id>/000.png..007.png`: transparent 384x512 PNG frames.",
        "- `assets/raw-strips/<animation_id>.png`: 8-frame transparent horizontal strip.",
        "- `assets/previews/<animation_id>.gif`: quick motion preview.",
        "- `assets/source/generated-rows/`: original generated chroma-key row references.",
        "- `manifest.json`: integration metadata.",
        "- `contact-sheet.png`: visual QA overview.",
        "",
        "## Included Animations",
        "",
    ]
    for anim in ANIMATIONS:
        loop = "loop" if anim.loop else "one-shot"
        lines.append(f"- `{anim.anim_id}`: {anim.name}, {loop}, {anim.status}.")
    (OUT_ROOT / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def checkerboard(size: tuple[int, int], tile: int = 16) -> Image.Image:
    image = Image.new("RGBA", size, (245, 245, 245, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], tile):
        for x in range(0, size[0], tile):
            if (x // tile + y // tile) % 2:
                draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill=(226, 226, 226, 255))
    return image


def make_contact_sheet(all_frames: dict[str, list[Image.Image]]) -> None:
    thumb = (96, 128)
    label_h = 26
    margin = 12
    row_h = thumb[1] + label_h + margin
    width = margin + 8 * (thumb[0] + margin)
    height = margin + len(ANIMATIONS) * row_h
    sheet = checkerboard((width, height), tile=12)
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 14)
    except OSError:
        font = ImageFont.load_default()

    for row_index, anim in enumerate(ANIMATIONS):
        y = margin + row_index * row_h
        draw.text((margin, y), f"{anim.anim_id} ({'loop' if anim.loop else 'one-shot'})", fill=(20, 20, 20), font=font)
        for frame_index, frame in enumerate(all_frames[anim.anim_id]):
            thumb_frame = frame.resize(thumb, Image.Resampling.LANCZOS)
            x = margin + frame_index * (thumb[0] + margin)
            sheet.alpha_composite(thumb_frame, (x, y + label_h))
            draw.text((x + 3, y + label_h + 2), f"F{frame_index}", fill=(80, 80, 80), font=font)

    sheet.convert("RGB").save(OUT_ROOT / "contact-sheet.png", quality=95)


def validate(all_frames: dict[str, list[Image.Image]]) -> None:
    errors = []
    for anim in ANIMATIONS:
        frames = all_frames.get(anim.anim_id, [])
        if len(frames) != 8:
            errors.append(f"{anim.anim_id}: expected 8 frames, got {len(frames)}")
            continue
        for index, frame in enumerate(frames):
            if frame.size != FRAME_SIZE:
                errors.append(f"{anim.anim_id}/{index:03d}: bad size {frame.size}")
            if frame.getchannel("A").getbbox() is None:
                errors.append(f"{anim.anim_id}/{index:03d}: blank frame")
            for point in [(0, 0), (FRAME_SIZE[0] - 1, 0), (0, FRAME_SIZE[1] - 1), (FRAME_SIZE[0] - 1, FRAME_SIZE[1] - 1)]:
                if frame.getpixel(point)[3] != 0:
                    errors.append(f"{anim.anim_id}/{index:03d}: nontransparent corner")
                    break

    report = {
        "ok": not errors,
        "errors": errors,
        "animationCount": len(ANIMATIONS),
        "frameCount": len(ANIMATIONS) * 8,
        "frameSize": list(FRAME_SIZE),
    }
    qa_dir = OUT_ROOT / "qa"
    qa_dir.mkdir(parents=True, exist_ok=True)
    (qa_dir / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if errors:
        raise RuntimeError("\n".join(errors))


def main() -> None:
    ensure_clean_dir(OUT_ROOT)
    copy_sources()

    all_frames: dict[str, list[Image.Image]] = {}
    for anim in ANIMATIONS:
        if anim.row_path is not None:
            frames = split_generated_row(anim.row_path, anim.anim_id)
        else:
            frames = copy_existing_frames(anim)
        all_frames[anim.anim_id] = frames
        save_frames(anim, frames)
        save_raw_strip(anim, frames)
        save_preview(anim, frames)

    write_manifest()
    write_readme()
    make_contact_sheet(all_frames)
    validate(all_frames)

    print(f"Exported {len(ANIMATIONS)} animations to {OUT_ROOT}")


if __name__ == "__main__":
    main()
