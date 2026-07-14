#!/usr/bin/env python3
"""Normalize transparent pixel-art strips into Pocket Vector runtime sprites.

The three input images must each contain one horizontal row of equal-width
slots. Receiver frames face right and are mirrored for leftward travel. Defenders
stay square to the quarterback, so both runtime directions reuse the same
front-facing art instead of reversing the visible jersey number.

Pillow with WebP support is required for processing, but ``--help`` and output
collision checks work without importing Pillow.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = ROOT / "public" / "assets" / "characters"

CANVAS_WIDTH = 384
CANVAS_HEIGHT = 512
ANCHOR_X = 192
ANCHOR_Y = 496
SAFE_PADDING = 16
TRANSPARENT = (0, 0, 0, 0)

QB_POSES = (
    ("idle", "idle"),
    ("aim", "aim"),
    ("throw", "throw"),
    ("recovery", "recovery"),
)
RECEIVER_POSES = (
    ("run-1", "run1"),
    ("run-2", "run2"),
    ("run-3", "run3"),
    ("run-4", "run4"),
    ("catch", "catch"),
    ("touchdown", "touchdown"),
)
DEFENDER_POSES = (
    ("run-1", "run1"),
    ("run-2", "run2"),
    ("run-3", "run3"),
    ("run-4", "run4"),
    ("interception", "interception"),
)

OFFENSE = {
    "jersey": "#E23A31",
    "pads": "#A7191E",
    "pants": "#E4E2DA",
    "helmet": "#D32728",
    "accent": "#F4F0E8",
    "socks": "#2B3137",
    "number": "#F8FBFF",
    "gloves": "#302729",
}

DEFENSE = {
    "jersey": "#1680CE",
    "pads": "#07579F",
    "pants": "#E6E8E4",
    "helmet": "#0A6FC2",
    "accent": "#FFF0C8",
    "socks": "#2A70B4",
    "number": "#FFFFFF",
    "gloves": "#E9EEF1",
}


class PipelineError(RuntimeError):
    """An actionable input, processing, or output error."""


@dataclass(frozen=True)
class RoleInput:
    role: str
    path: Path
    poses: tuple[tuple[str, str], ...]


@dataclass(frozen=True)
class LoadedRole:
    role: str
    path: Path
    strip_size: tuple[int, int]
    slot_width: int
    poses: tuple[tuple[str, str], ...]
    frames: tuple[Any, ...]
    scale: float
    trimmed_right: int


@dataclass(frozen=True)
class OutputFrame:
    filename: str
    role: str
    pose: str
    direction: str
    image: Any


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Convert three transparent horizontal pixel-art strips into the "
            "26 Pocket Vector character WebPs and sprites.json."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Input slot order:
  QB (4):       idle, aim, throw, recovery; rear view
  Receiver (6): run-1, run-2, run-3, run-4, catch, touchdown; facing right
  Defender (5): run-1, run-2, run-3, run-4, interception; square/front-facing

Each strip uses equal-width slots, and every slot must contain at least one
non-transparent pixel. If needed, fewer than one slot-count of fully transparent
trailing columns are safely trimmed to reach an even division; non-transparent
remainders fail validation. The pipeline uses one shared scale per role,
nearest-neighbor resampling, a 16 px safe area, and bottom-center anchor
[192, 496]. Receiver left frames are exact full-canvas mirrors of right frames;
square defender frames are reused unchanged for both directions.

Example:
  python3 scripts/process-pixel-character-strips.py \\
    --qb-strip art/qb-strip.png \\
    --receiver-strip art/receiver-strip.png \\
    --defender-strip art/defender-strip.png \\
    --dry-run

Remove --dry-run to write. Existing runtime files are replaced only with
--force.
""",
    )
    parser.add_argument(
        "--qb-strip",
        required=True,
        type=Path,
        help="transparent 4-slot rear-view quarterback strip",
    )
    parser.add_argument(
        "--receiver-strip",
        required=True,
        type=Path,
        help="transparent 6-slot right-facing receiver strip",
    )
    parser.add_argument(
        "--defender-strip",
        required=True,
        type=Path,
        help="transparent 5-slot square/front-facing defender strip",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"runtime asset directory (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate and encode all outputs in memory without writing files",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="replace the 26 runtime WebPs and sprites.json if they exist",
    )
    return parser


def runtime_filenames() -> tuple[str, ...]:
    filenames = [f"qb-{file_pose}.webp" for file_pose, _ in QB_POSES]
    for role, poses in (
        ("receiver", RECEIVER_POSES),
        ("defender", DEFENDER_POSES),
    ):
        for file_pose, _ in poses:
            filenames.extend(
                (
                    f"{role}-{file_pose}-left.webp",
                    f"{role}-{file_pose}-right.webp",
                )
            )
    return tuple(filenames)


def resolve_path(path: Path) -> Path:
    return path.expanduser().resolve()


def validate_paths(inputs: Sequence[RoleInput], output_dir: Path) -> None:
    for role_input in inputs:
        if not role_input.path.exists():
            raise PipelineError(
                f"Missing {role_input.role} strip: {role_input.path}"
            )
        if not role_input.path.is_file():
            raise PipelineError(
                f"{role_input.role.capitalize()} strip is not a file: "
                f"{role_input.path}"
            )
    if output_dir.exists() and not output_dir.is_dir():
        raise PipelineError(f"Output path is not a directory: {output_dir}")


def existing_targets(output_dir: Path) -> list[Path]:
    names = (*runtime_filenames(), "sprites.json")
    return [
        output_dir / name
        for name in names
        if (output_dir / name).exists() or (output_dir / name).is_symlink()
    ]


def require_pillow() -> tuple[Any, Any, Any]:
    try:
        from PIL import Image, ImageOps, features
    except ImportError as exc:
        raise PipelineError(
            "Pillow is required. Install it with `python3 -m pip install Pillow`."
        ) from exc
    if not features.check("webp"):
        raise PipelineError(
            "This Pillow build has no WebP support. Install a Pillow build "
            "linked with libwebp."
        )
    return Image, ImageOps, features


def image_has_alpha(image: Any) -> bool:
    return "A" in image.getbands() or "transparency" in image.info


def load_role(role_input: RoleInput, image_module: Any) -> LoadedRole:
    try:
        with image_module.open(role_input.path) as opened:
            opened.load()
            if not image_has_alpha(opened):
                raise PipelineError(
                    f"{role_input.role.capitalize()} strip has no alpha channel: "
                    f"{role_input.path}"
                )
            strip = opened.convert("RGBA")
    except PipelineError:
        raise
    except Exception as exc:
        raise PipelineError(
            f"Could not read {role_input.role} strip "
            f"{role_input.path}: {exc}"
        ) from exc

    frame_count = len(role_input.poses)
    if strip.width < frame_count:
        raise PipelineError(
            f"{role_input.role.capitalize()} strip width {strip.width} cannot "
            f"contain {frame_count} slots: {role_input.path}"
        )
    original_size = strip.size
    trimmed_right = strip.width % frame_count
    if trimmed_right:
        remainder = strip.crop(
            (strip.width - trimmed_right, 0, strip.width, strip.height)
        )
        if remainder.getchannel("A").getbbox() is not None:
            raise PipelineError(
                f"{role_input.role.capitalize()} strip width {strip.width} is "
                f"not evenly divisible by {frame_count} slots, and its "
                f"{trimmed_right}-pixel trailing remainder is not transparent: "
                f"{role_input.path}"
            )
        strip = strip.crop((0, 0, strip.width - trimmed_right, strip.height))
    if strip.getchannel("A").getextrema()[0] == 255:
        raise PipelineError(
            f"{role_input.role.capitalize()} strip has no transparent pixels: "
            f"{role_input.path}"
        )

    slot_width = strip.width // frame_count
    if slot_width < 1 or strip.height < 1:
        raise PipelineError(
            f"{role_input.role.capitalize()} strip has invalid dimensions "
            f"{strip.width}x{strip.height}: {role_input.path}"
        )

    frames: list[Any] = []
    for index, (file_pose, _) in enumerate(role_input.poses):
        slot = strip.crop(
            (index * slot_width, 0, (index + 1) * slot_width, strip.height)
        )
        bounds = slot.getchannel("A").getbbox()
        if bounds is None:
            raise PipelineError(
                f"{role_input.role.capitalize()} slot {index + 1} "
                f"({file_pose}) is empty: {role_input.path}"
            )
        frames.append(slot.crop(bounds))

    usable_width = CANVAS_WIDTH - SAFE_PADDING * 2
    usable_height = ANCHOR_Y - SAFE_PADDING
    widest = max(frame.width for frame in frames)
    tallest = max(frame.height for frame in frames)
    scale = min(usable_width / widest, usable_height / tallest)
    if scale <= 0:
        raise PipelineError(
            f"Could not compute a positive scale for {role_input.role} strip"
        )

    return LoadedRole(
        role=role_input.role,
        path=role_input.path,
        strip_size=original_size,
        slot_width=slot_width,
        poses=role_input.poses,
        frames=tuple(frames),
        scale=scale,
        trimmed_right=trimmed_right,
    )


def normalize_frame(frame: Any, scale: float, image_module: Any) -> Any:
    width = max(1, round(frame.width * scale))
    height = max(1, round(frame.height * scale))
    resized = frame.resize(
        (width, height),
        resample=image_module.Resampling.NEAREST,
    )
    x = ANCHOR_X - width // 2
    y = ANCHOR_Y - height

    if (
        x < SAFE_PADDING
        or x + width > CANVAS_WIDTH - SAFE_PADDING
        or y < SAFE_PADDING
        or y + height > ANCHOR_Y
    ):
        raise PipelineError(
            "Internal normalization error: scaled frame escaped the safe area "
            f"at ({x}, {y}, {width}, {height})"
        )

    canvas = image_module.new(
        "RGBA", (CANVAS_WIDTH, CANVAS_HEIGHT), TRANSPARENT
    )
    # Paste without a mask. This copies RGBA values exactly instead of alpha
    # compositing them, which keeps the source palette and partial alpha intact.
    canvas.paste(resized, (x, y))
    return canvas


def pixel_data(image: Any) -> Any:
    """Return flat pixels without warning on either old or new Pillow."""
    flattened = getattr(image, "get_flattened_data", None)
    return flattened() if flattened is not None else image.getdata()


def remove_detached_release_prop(image: Any) -> Any:
    """Remove a small ball above the QB release pose.

    The simulated football is rendered independently, so a detached ball baked
    into the release frame would briefly create two footballs. Preserve the
    normalized scale and clear only an isolated upper component separated from
    the athlete by a transparent horizontal gap.
    """
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        return image

    first_row, last_row = bounds[1], bounds[3]
    gap_start: int | None = None
    for y in range(first_row, last_row):
        occupied = alpha.crop((0, y, image.width, y + 1)).getbbox() is not None
        if occupied:
            if gap_start is not None and y - gap_start >= 4:
                upper = alpha.crop((0, first_row, image.width, gap_start))
                lower = alpha.crop((0, y, image.width, last_row))
                upper_count = sum(1 for value in pixel_data(upper) if value)
                lower_count = sum(1 for value in pixel_data(lower) if value)
                if upper_count >= 16 and upper_count * 5 < lower_count:
                    cleaned = image.copy()
                    cleaned.paste(TRANSPARENT, (0, 0, image.width, y))
                    return cleaned
            gap_start = None
        elif gap_start is None:
            gap_start = y
    return image


def verify_palette(source_frames: Iterable[Any], outputs: Iterable[Any]) -> None:
    source_colors = {TRANSPARENT}
    for source in source_frames:
        source_colors.update(pixel_data(source))
    for output in outputs:
        unexpected = set(pixel_data(output)).difference(source_colors)
        if unexpected:
            sample = next(iter(unexpected))
            raise PipelineError(
                "Palette preservation check failed; normalized output introduced "
                f"color {sample}"
            )


def prepare_outputs(
    loaded_roles: Sequence[LoadedRole], image_module: Any, image_ops: Any
) -> tuple[list[OutputFrame], list[tuple[str, str]]]:
    by_role = {loaded.role: loaded for loaded in loaded_roles}
    outputs: list[OutputFrame] = []
    mirror_pairs: list[tuple[str, str]] = []

    qb = by_role["quarterback"]
    qb_images = [normalize_frame(frame, qb.scale, image_module) for frame in qb.frames]
    qb_images[2] = remove_detached_release_prop(qb_images[2])
    verify_palette(qb.frames, qb_images)
    for (_, manifest_pose), image in zip(qb.poses, qb_images, strict=True):
        outputs.append(
            OutputFrame(
                filename=f"qb-{manifest_pose}.webp",
                role="quarterback",
                pose=manifest_pose,
                direction="rear",
                image=image,
            )
        )

    for role in ("receiver", "defender"):
        loaded = by_role[role]
        right_images = [
            normalize_frame(frame, loaded.scale, image_module)
            for frame in loaded.frames
        ]
        verify_palette(loaded.frames, right_images)
        for (file_pose, manifest_pose), right_image in zip(
            loaded.poses, right_images, strict=True
        ):
            right_filename = f"{role}-{file_pose}-right.webp"
            left_filename = f"{role}-{file_pose}-left.webp"
            left_image = (
                image_ops.mirror(right_image)
                if role == "receiver"
                else right_image.copy()
            )
            outputs.extend(
                (
                    OutputFrame(
                        filename=left_filename,
                        role=role,
                        pose=manifest_pose,
                        direction="left",
                        image=left_image,
                    ),
                    OutputFrame(
                        filename=right_filename,
                        role=role,
                        pose=manifest_pose,
                        direction="right",
                        image=right_image,
                    ),
                )
            )
            if role == "receiver":
                mirror_pairs.append((left_filename, right_filename))

    expected = runtime_filenames()
    actual = tuple(frame.filename for frame in outputs)
    if actual != expected:
        raise PipelineError(
            "Internal output contract error: runtime filename order changed"
        )
    return outputs, mirror_pairs


def encode_lossless_webp(image: Any, image_module: Any) -> tuple[bytes, Any]:
    buffer = io.BytesIO()
    try:
        image.save(
            buffer,
            format="WEBP",
            lossless=True,
            quality=100,
            method=6,
            exact=True,
        )
    except Exception as exc:
        raise PipelineError(f"Could not encode lossless WebP: {exc}") from exc

    encoded = buffer.getvalue()
    try:
        with image_module.open(io.BytesIO(encoded)) as decoded_file:
            if decoded_file.format != "WEBP":
                raise PipelineError("Encoded frame did not identify as WebP")
            decoded = decoded_file.convert("RGBA")
    except PipelineError:
        raise
    except Exception as exc:
        raise PipelineError(f"Could not verify encoded WebP: {exc}") from exc

    if decoded.size != (CANVAS_WIDTH, CANVAS_HEIGHT):
        raise PipelineError(
            f"Encoded WebP has unexpected dimensions {decoded.size}"
        )
    if decoded.tobytes() != image.tobytes():
        raise PipelineError(
            "WebP lossless round-trip changed pixel data; check Pillow/libwebp"
        )
    alpha_min, alpha_max = decoded.getchannel("A").getextrema()
    if alpha_min != 0 or alpha_max == 0:
        raise PipelineError(
            "Encoded WebP must contain both transparent and visible pixels"
        )
    return encoded, decoded


def content_bounds(image: Any) -> dict[str, int]:
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        return {"x": 0, "y": 0, "width": 0, "height": 0}
    left, top, right, bottom = bounds
    return {
        "x": left,
        "y": top,
        "width": right - left,
        "height": bottom - top,
    }


def encode_and_verify(
    outputs: Sequence[OutputFrame],
    mirror_pairs: Sequence[tuple[str, str]],
    image_module: Any,
    image_ops: Any,
) -> tuple[dict[str, bytes], dict[str, Any]]:
    encoded: dict[str, bytes] = {}
    decoded: dict[str, Any] = {}
    for frame in outputs:
        encoded[frame.filename], decoded[frame.filename] = encode_lossless_webp(
            frame.image, image_module
        )

    for left_filename, right_filename in mirror_pairs:
        expected_left = image_ops.mirror(decoded[right_filename])
        if decoded[left_filename].tobytes() != expected_left.tobytes():
            raise PipelineError(
                f"Mirror verification failed for {left_filename} and "
                f"{right_filename}"
            )
    return encoded, decoded


def build_manifest(
    outputs: Sequence[OutputFrame],
    encoded: dict[str, bytes],
    decoded: dict[str, Any],
    scales: dict[str, float],
) -> dict[str, Any]:
    frames = []
    for frame in outputs:
        frames.append(
            {
                "src": f"/assets/characters/{frame.filename}",
                "role": frame.role,
                "pose": frame.pose,
                "direction": frame.direction,
                "width": CANVAS_WIDTH,
                "height": CANVAS_HEIGHT,
                "anchor": {"x": ANCHOR_X, "y": ANCHOR_Y},
                "contentBounds": content_bounds(decoded[frame.filename]),
                "bytes": len(encoded[frame.filename]),
            }
        )

    return {
        "version": 2,
        "generator": "scripts/process-pixel-character-strips.py",
        "canvas": {
            "width": CANVAS_WIDTH,
            "height": CANVAS_HEIGHT,
            "anchor": {"x": ANCHOR_X, "y": ANCHOR_Y},
        },
        "render": {
            "engine": "PILLOW",
            "format": "webp",
            "quality": 100,
            "lossless": True,
            "resampling": "nearest",
            "camera": (
                "rear QB, mirrored left/right receivers, square defenders "
                "reused in both directions"
            ),
            "releaseBall": (
                "detached QB release prop removed; runtime projectile is "
                "authoritative"
            ),
            "background": "transparent",
            "safePadding": SAFE_PADDING,
            "scaleByRole": {
                role: round(scale, 8) for role, scale in scales.items()
            },
        },
        "teams": {
            "offense": {"name": "Nova City Comets", "palette": OFFENSE},
            "defense": {"name": "Iron Bay Phantoms", "palette": DEFENSE},
        },
        "frames": frames,
    }


def write_outputs(
    output_dir: Path,
    encoded: dict[str, bytes],
    manifest: dict[str, Any],
    force: bool,
) -> None:
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(
        prefix=".pixel-character-strips-", dir=output_dir.parent
    ) as temp_name:
        temp_dir = Path(temp_name)
        for filename, payload in encoded.items():
            (temp_dir / filename).write_bytes(payload)
        (temp_dir / "sprites.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )

        conflicts = existing_targets(output_dir)
        if conflicts and not force:
            raise PipelineError(overwrite_message(conflicts))

        for filename in (*runtime_filenames(), "sprites.json"):
            os.replace(temp_dir / filename, output_dir / filename)


def overwrite_message(conflicts: Sequence[Path]) -> str:
    preview = ", ".join(path.name for path in conflicts[:6])
    if len(conflicts) > 6:
        preview += f", and {len(conflicts) - 6} more"
    return (
        f"Refusing to overwrite {len(conflicts)} existing output(s) in "
        f"{conflicts[0].parent}: {preview}. Re-run with --force to replace "
        "the runtime sprite set."
    )


def print_summary(
    loaded_roles: Sequence[LoadedRole],
    output_dir: Path,
    conflict_count: int,
    dry_run: bool,
) -> None:
    status = "Dry run complete" if dry_run else "Generated sprite set"
    print(f"{status}: 26 lossless WebPs and sprites.json")
    print(
        f"Canvas: {CANVAS_WIDTH}x{CANVAS_HEIGHT}; "
        f"anchor: [{ANCHOR_X}, {ANCHOR_Y}]; safe padding: {SAFE_PADDING}px"
    )
    for loaded in loaded_roles:
        trim_note = (
            f"; trimmed {loaded.trimmed_right} transparent trailing columns"
            if loaded.trimmed_right
            else ""
        )
        print(
            f"{loaded.role}: {loaded.strip_size[0]}x{loaded.strip_size[1]} "
            f"({len(loaded.poses)} slots at {loaded.slot_width}px); "
            f"shared scale {loaded.scale:.8f}{trim_note}"
        )
    print(f"Output: {output_dir}")
    print(
        "Verified: non-empty slots, nearest-neighbor palette preservation, "
        "384x512 transparency, lossless pixel round-trip, six receiver mirror "
        "pairs, and square defender direction pairs."
    )
    if dry_run:
        if conflict_count:
            print(
                f"Existing targets: {conflict_count}; an actual write would "
                "require --force."
            )
        print("No files written.")


def run(args: argparse.Namespace) -> None:
    output_dir = resolve_path(args.output_dir)
    inputs = (
        RoleInput(
            "quarterback",
            resolve_path(args.qb_strip),
            QB_POSES,
        ),
        RoleInput(
            "receiver",
            resolve_path(args.receiver_strip),
            RECEIVER_POSES,
        ),
        RoleInput(
            "defender",
            resolve_path(args.defender_strip),
            DEFENDER_POSES,
        ),
    )
    validate_paths(inputs, output_dir)

    conflicts = existing_targets(output_dir)
    if conflicts and not args.force and not args.dry_run:
        raise PipelineError(overwrite_message(conflicts))

    image_module, image_ops, _ = require_pillow()
    loaded_roles = tuple(load_role(role_input, image_module) for role_input in inputs)
    outputs, mirror_pairs = prepare_outputs(
        loaded_roles, image_module, image_ops
    )
    encoded, decoded = encode_and_verify(
        outputs, mirror_pairs, image_module, image_ops
    )
    scales = {loaded.role: loaded.scale for loaded in loaded_roles}
    manifest = build_manifest(outputs, encoded, decoded, scales)

    if not args.dry_run:
        write_outputs(output_dir, encoded, manifest, args.force)
    print_summary(
        loaded_roles,
        output_dir,
        conflict_count=len(conflicts),
        dry_run=args.dry_run,
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        run(args)
    except PipelineError as exc:
        parser.exit(2, f"error: {exc}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
