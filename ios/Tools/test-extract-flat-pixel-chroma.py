#!/usr/bin/env python3
"""Focused boundary tests for the flat pixel-art chroma extractor."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


TOOL = Path(__file__).with_name("extract-flat-pixel-chroma.py")
TRANSPARENT = (0, 0, 0, 0)
NAVY = (20, 40, 79, 255)
KEY = (255, 0, 255, 255)
DARK_NEAR_KEY = (100, 10, 120, 255)


class FlatPixelChromaTests(unittest.TestCase):
    def run_tool(self, image: Image.Image) -> tuple[subprocess.CompletedProcess[str], Image.Image | None]:
        with tempfile.TemporaryDirectory() as temp_name:
            temp = Path(temp_name)
            source = temp / "source.png"
            output = temp / "output.png"
            image.save(source)
            result = subprocess.run(
                [sys.executable, str(TOOL), "--input", str(source), "--output", str(output)],
                capture_output=True,
                text=True,
                check=False,
            )
            rendered = Image.open(output).convert("RGBA").copy() if output.is_file() else None
            return result, rendered

    def test_no_key_with_small_component_fails(self) -> None:
        image = Image.new("RGBA", (64, 64), TRANSPARENT)
        for y in range(10, 20):
            for x in range(10, 20):
                image.putpixel((x, y), NAVY)

        result, rendered = self.run_tool(image)

        self.assertEqual(result.returncode, 2)
        self.assertIn("No pixels matched", result.stdout)
        self.assertIsNone(rendered)

    def test_exact_enclosed_key_is_removed_globally(self) -> None:
        image = self.large_navy_block()
        image.putpixel((32, 32), KEY)

        result, rendered = self.run_tool(image)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIsNotNone(rendered)
        assert rendered is not None
        self.assertEqual(rendered.getpixel((32, 32)), TRANSPARENT)
        self.assertEqual(rendered.getpixel((31, 32)), NAVY)

    def test_border_connected_dark_near_key_is_removed(self) -> None:
        image = Image.new("RGBA", (64, 64), DARK_NEAR_KEY)
        for y in range(10, 54):
            for x in range(10, 54):
                image.putpixel((x, y), NAVY)
        image.putpixel((0, 0), KEY)

        result, rendered = self.run_tool(image)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        assert rendered is not None
        self.assertEqual(rendered.getpixel((0, 1)), TRANSPARENT)
        self.assertEqual(rendered.getpixel((32, 32)), NAVY)

    def test_enclosed_dark_near_key_is_preserved(self) -> None:
        image = self.large_navy_block()
        image.putpixel((0, 0), KEY)
        image.putpixel((32, 32), DARK_NEAR_KEY)

        result, rendered = self.run_tool(image)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        assert rendered is not None
        self.assertEqual(rendered.getpixel((32, 32)), DARK_NEAR_KEY)

    def test_512_pixel_component_is_removed_and_513_is_preserved(self) -> None:
        image = Image.new("RGBA", (100, 100), TRANSPARENT)
        image.putpixel((0, 0), KEY)
        for y in range(10, 42):
            for x in range(10, 26):
                image.putpixel((x, y), NAVY)
        for y in range(60, 87):
            for x in range(50, 69):
                image.putpixel((x, y), NAVY)

        result, rendered = self.run_tool(image)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        assert rendered is not None
        self.assertEqual(rendered.getpixel((10, 10)), TRANSPARENT)
        self.assertEqual(rendered.getpixel((50, 60)), NAVY)

    @staticmethod
    def large_navy_block() -> Image.Image:
        image = Image.new("RGBA", (64, 64), TRANSPARENT)
        for y in range(10, 54):
            for x in range(10, 54):
                image.putpixel((x, y), NAVY)
        return image


if __name__ == "__main__":
    unittest.main()
