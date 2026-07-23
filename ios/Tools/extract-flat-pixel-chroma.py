#!/usr/bin/env python3
"""Remove only a flat pixel-art chroma field without despill or soft masking."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
from typing import Any


ISOLATED_ARTIFACT_MAX_PIXELS = 512


class ChromaError(RuntimeError):
    """An actionable source or output failure."""


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description=(
            "Make flat magenta background pixels transparent while preserving "
            "every non-key RGB value and alpha byte exactly."
        )
    )
    result.add_argument("--input", type=Path, required=True)
    result.add_argument("--output", type=Path, required=True)
    result.add_argument("--key", default="FF00FF", help="six-digit RGB hex key")
    result.add_argument(
        "--tolerance",
        type=int,
        default=128,
        help=(
            "maximum RGB Euclidean distance for border-connected key pixels "
            "(default: 128)"
        ),
    )
    result.add_argument("--force", action="store_true")
    return result


def require_pillow() -> Any:
    try:
        from PIL import Image
    except ImportError as exc:
        raise ChromaError("Pillow is required") from exc
    return Image


def parse_key(value: str) -> tuple[int, int, int]:
    normalized = value.removeprefix("#")
    if len(normalized) != 6:
        raise ChromaError("--key must be a six-digit RGB hex value")
    try:
        return tuple(int(normalized[index:index + 2], 16) for index in (0, 2, 4))
    except ValueError as exc:
        raise ChromaError("--key must be a six-digit RGB hex value") from exc


def main() -> int:
    args = parser().parse_args()
    if not 0 <= args.tolerance <= 255:
        raise ChromaError("--tolerance must be between 0 and 255")
    if not args.input.is_file():
        raise ChromaError(f"Missing image: {args.input}")
    if args.output.exists() and not args.force:
        raise ChromaError(f"Output exists; pass --force: {args.output}")

    image_module = require_pillow()
    key = parse_key(args.key)
    with image_module.open(args.input) as opened:
        source = opened.convert("RGBA")
    pixels = list(source.get_flattened_data())
    width, height = source.size
    tolerance_squared = args.tolerance * args.tolerance
    candidates = bytearray(len(pixels))
    for index, (red, green, blue, _) in enumerate(pixels):
        distance_squared = (
            ((red - key[0]) * (red - key[0]))
            + ((green - key[1]) * (green - key[1]))
            + ((blue - key[2]) * (blue - key[2]))
        )
        is_dark_magenta_edge = (
            red >= 40
            and blue >= 40
            and green * 100 <= min(red, blue) * 25
            and abs(red - blue) <= 80
        )
        if distance_squared <= tolerance_squared or is_dark_magenta_edge:
            candidates[index] = 1

    keyed = bytearray(len(pixels))
    pending: deque[int] = deque()

    def seed(index: int) -> None:
        if candidates[index] and not keyed[index]:
            keyed[index] = 1
            pending.append(index)

    for x in range(width):
        seed(x)
        seed(((height - 1) * width) + x)
    for y in range(height):
        seed(y * width)
        seed((y * width) + width - 1)

    while pending:
        index = pending.popleft()
        x = index % width
        if x > 0:
            seed(index - 1)
        if x + 1 < width:
            seed(index + 1)
        if index >= width:
            seed(index - width)
        if index + width < len(pixels):
            seed(index + width)

    # Bright key-family pixels are never authored uniform material. Remove them
    # globally so enclosed key islands cannot survive inside pose gaps. Keep the
    # border-connectivity requirement for darker magenta edge shades, where it
    # protects authored violet uniform materials.
    for index, (red, green, blue, _) in enumerate(pixels):
        distance_squared = (
            ((red - key[0]) * (red - key[0]))
            + ((green - key[1]) * (green - key[1]))
            + ((blue - key[2]) * (blue - key[2]))
        )
        if distance_squared <= tolerance_squared:
            keyed[index] = 1

    chroma_keyed_count = sum(keyed)
    if chroma_keyed_count == 0:
        raise ChromaError("No pixels matched the flat chroma key")
    if chroma_keyed_count == len(pixels):
        raise ChromaError("The chroma key removed the entire image")

    visited = bytearray(len(pixels))
    artifact_component_count = 0
    artifact_pixel_count = 0
    for start in range(len(pixels)):
        if keyed[start] or not pixels[start][3] or visited[start]:
            continue
        visited[start] = 1
        component_pending = deque([start])
        component_size = 0
        artifact_indices: list[int] = []
        while component_pending:
            index = component_pending.popleft()
            component_size += 1
            if component_size <= ISOLATED_ARTIFACT_MAX_PIXELS:
                artifact_indices.append(index)
            x = index % width
            y = index // width
            for neighbor_y in range(max(0, y - 1), min(height, y + 2)):
                row = neighbor_y * width
                for neighbor_x in range(max(0, x - 1), min(width, x + 2)):
                    neighbor = row + neighbor_x
                    if (
                        neighbor != index
                        and not visited[neighbor]
                        and not keyed[neighbor]
                        and pixels[neighbor][3]
                    ):
                        visited[neighbor] = 1
                        component_pending.append(neighbor)
        if component_size <= ISOLATED_ARTIFACT_MAX_PIXELS:
            artifact_component_count += 1
            artifact_pixel_count += component_size
            for index in artifact_indices:
                keyed[index] = 1

    keyed_count = sum(keyed)
    output_pixels = [
        (0, 0, 0, 0) if keyed[index] else pixel
        for index, pixel in enumerate(pixels)
    ]

    if keyed_count == len(output_pixels):
        raise ChromaError("The chroma key removed the entire image")

    output = image_module.new("RGBA", source.size)
    output.putdata(output_pixels)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output, format="PNG", optimize=False)
    print(
        f"Removed {keyed_count} flat chroma pixels from {args.input}; "
        f"including {artifact_pixel_count} pixels in "
        f"{artifact_component_count} isolated debris components; "
        "all retained RGBA values were preserved"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ChromaError as exc:
        print(f"error: {exc}")
        raise SystemExit(2) from exc
