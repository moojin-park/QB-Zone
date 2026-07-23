#!/usr/bin/env python3
"""Normalize paired generated uniform strips to the shipped source geometry.

The image generator is asked for a whole animation strip on transparent canvas,
but its output canvas is not guaranteed to match Pocket Vector's canonical
source-strip dimensions. This tool divides both generated uniforms into the
same role slots, computes one shared nearest-neighbor scale across the pair,
and aligns each frame to the corresponding shipped reference anchor.

It intentionally does not recolor, mask, or otherwise alter uniform materials.
"""

from __future__ import annotations

import argparse
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class NormalizationError(RuntimeError):
    """An actionable strip input or geometry failure."""


@dataclass(frozen=True)
class RoleSpec:
    frame_count: int
    trailing_columns: int


ROLE_SPECS = {
    "qb": RoleSpec(frame_count=4, trailing_columns=0),
    "receiver": RoleSpec(frame_count=10, trailing_columns=0),
    "defender": RoleSpec(frame_count=5, trailing_columns=3),
}
ISOLATED_ARTIFACT_MAX_PIXELS = 512


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description=(
            "Normalize primary and alternate generated team strips together "
            "using one shared scale and the shipped reference anchors."
        )
    )
    result.add_argument("--role", choices=sorted(ROLE_SPECS), required=True)
    result.add_argument("--reference", type=Path, required=True)
    result.add_argument("--primary-input", type=Path, required=True)
    result.add_argument("--alternate-input", type=Path, required=True)
    result.add_argument("--primary-output", type=Path, required=True)
    result.add_argument("--alternate-output", type=Path, required=True)
    result.add_argument("--force", action="store_true")
    return result


def require_pillow() -> Any:
    try:
        from PIL import Image
    except ImportError as exc:
        raise NormalizationError("Pillow is required") from exc
    return Image


def load_rgba(path: Path, image_module: Any) -> Any:
    if not path.is_file():
        raise NormalizationError(f"Missing image: {path}")
    try:
        with image_module.open(path) as opened:
            opened.load()
            if "A" not in opened.getbands() and "transparency" not in opened.info:
                raise NormalizationError(f"Image has no alpha channel: {path}")
            return opened.convert("RGBA")
    except NormalizationError:
        raise
    except Exception as exc:
        raise NormalizationError(f"Could not read {path}: {exc}") from exc


def split_frames(strip: Any, frame_count: int, label: str) -> tuple[Any, ...]:
    remainder = strip.width % frame_count
    if remainder:
        trailing = strip.crop((strip.width - remainder, 0, strip.width, strip.height))
        if trailing.getchannel("A").getbbox() is not None:
            raise NormalizationError(
                f"{label} width {strip.width} has a nontransparent "
                f"{remainder}-pixel remainder"
            )
        strip = strip.crop((0, 0, strip.width - remainder, strip.height))

    slot_width = strip.width // frame_count
    frames = []
    for index in range(frame_count):
        slot = strip.crop((index * slot_width, 0, (index + 1) * slot_width, strip.height))
        bounds = slot.getchannel("A").getbbox()
        if bounds is None:
            raise NormalizationError(f"{label} slot {index + 1} is empty")
        frames.append(slot.crop(bounds))
    return tuple(frames)


def reference_geometry(reference: Any, spec: RoleSpec) -> tuple[int, int, tuple[tuple[float, int], ...]]:
    usable_width = reference.width - spec.trailing_columns
    if usable_width <= 0 or usable_width % spec.frame_count:
        raise NormalizationError(
            f"Reference width {reference.width} does not satisfy the {spec.frame_count}-slot contract"
        )
    slot_width = usable_width // spec.frame_count
    anchors = []
    for index in range(spec.frame_count):
        slot = reference.crop((index * slot_width, 0, (index + 1) * slot_width, reference.height))
        bounds = slot.getchannel("A").getbbox()
        if bounds is None:
            raise NormalizationError(f"Reference slot {index + 1} is empty")
        left, _, right, bottom = bounds
        anchors.append(((left + right) / 2, bottom))
    return slot_width, reference.height, tuple(anchors)


def remove_isolated_artifacts(image: Any, image_module: Any) -> tuple[Any, int]:
    width, height = image.size
    pixels = list(image.get_flattened_data())
    alpha = [pixel[3] for pixel in pixels]
    visited = bytearray(len(pixels))
    removed = 0

    for start, value in enumerate(alpha):
        if not value or visited[start]:
            continue
        visited[start] = 1
        pending = deque([start])
        component: list[int] = []
        component_size = 0
        while pending:
            index = pending.popleft()
            component_size += 1
            if component_size <= ISOLATED_ARTIFACT_MAX_PIXELS:
                component.append(index)
            x = index % width
            y = index // width
            for neighbor_y in range(max(0, y - 1), min(height, y + 2)):
                row = neighbor_y * width
                for neighbor_x in range(max(0, x - 1), min(width, x + 2)):
                    neighbor = row + neighbor_x
                    if (
                        neighbor != index
                        and not visited[neighbor]
                        and alpha[neighbor]
                    ):
                        visited[neighbor] = 1
                        pending.append(neighbor)
        if component_size <= ISOLATED_ARTIFACT_MAX_PIXELS:
            removed += component_size
            for index in component:
                pixels[index] = (0, 0, 0, 0)

    if not removed:
        return image, 0
    output = image_module.new("RGBA", image.size)
    output.putdata(pixels)
    return output, removed


def normalize_pair(
    primary_frames: tuple[Any, ...],
    alternate_frames: tuple[Any, ...],
    reference: Any,
    spec: RoleSpec,
    image_module: Any,
) -> tuple[Any, Any, float, int]:
    slot_width, target_height, anchors = reference_geometry(reference, spec)
    reference_frames = split_frames(
        reference.crop((0, 0, reference.width - spec.trailing_columns, reference.height)),
        spec.frame_count,
        "reference",
    )
    generated = primary_frames + alternate_frames
    widest = max(frame.width for frame in generated)
    tallest = max(frame.height for frame in generated)
    target_widest = max(frame.width for frame in reference_frames)
    target_tallest = max(frame.height for frame in reference_frames)
    scale = min(target_widest / widest, target_tallest / tallest)
    if scale <= 0:
        raise NormalizationError("Could not compute a positive shared scale")

    target_width = slot_width * spec.frame_count + spec.trailing_columns

    def compose(frames: tuple[Any, ...]) -> tuple[Any, int]:
        output = image_module.new("RGBA", (target_width, target_height), (0, 0, 0, 0))
        removed = 0
        for index, frame in enumerate(frames):
            width = max(1, round(frame.width * scale))
            height = max(1, round(frame.height * scale))
            resized = frame.resize((width, height), image_module.Resampling.NEAREST)
            resized, frame_removed = remove_isolated_artifacts(resized, image_module)
            removed += frame_removed
            center_x, baseline = anchors[index]
            x = index * slot_width + round(center_x - width / 2)
            y = baseline - height
            if x < index * slot_width or x + width > (index + 1) * slot_width or y < 0 or y + height > target_height:
                raise NormalizationError(
                    f"Normalized slot {index + 1} escapes its target cell at {(x, y, width, height)}"
                )
            output.paste(resized, (x, y))
        return output, removed

    primary, primary_removed = compose(primary_frames)
    alternate, alternate_removed = compose(alternate_frames)
    return primary, alternate, scale, primary_removed + alternate_removed


def write(image: Any, path: Path, force: bool) -> None:
    if path.exists() and not force:
        raise NormalizationError(f"Output already exists; pass --force: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False)


def main() -> int:
    args = parser().parse_args()
    image_module = require_pillow()
    spec = ROLE_SPECS[args.role]
    reference = load_rgba(args.reference, image_module)
    primary = load_rgba(args.primary_input, image_module)
    alternate = load_rgba(args.alternate_input, image_module)
    primary_frames = split_frames(primary, spec.frame_count, "primary")
    alternate_frames = split_frames(alternate, spec.frame_count, "alternate")
    normalized_primary, normalized_alternate, scale, removed = normalize_pair(
        primary_frames,
        alternate_frames,
        reference,
        spec,
        image_module,
    )
    write(normalized_primary, args.primary_output, args.force)
    write(normalized_alternate, args.alternate_output, args.force)
    print(
        f"Normalized {args.role}: {spec.frame_count} frames, "
        f"shared scale {scale:.8f}, output {normalized_primary.width}x{normalized_primary.height}, "
        f"removed {removed} isolated artifact pixels"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except NormalizationError as exc:
        print(f"error: {exc}")
        raise SystemExit(2) from exc
