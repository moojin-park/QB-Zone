#!/usr/bin/env python3
"""Synchronize native-assets.json with the physical GameAssets inventory."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


IOS_ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = IOS_ROOT / "PocketVector" / "Resources" / "GameAssets"
MANIFEST_PATH = ASSET_ROOT / "native-assets.json"
NON_BUNDLED_SIDECARS = {ASSET_ROOT / "AGENTS.md"}
IMAGE_SUFFIXES = {".png", ".webp"}
AUDIO_SUFFIXES = {".wav"}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Synchronize native-assets.json with the sorted physical asset inventory."
    )
    result.add_argument(
        "--check",
        action="store_true",
        help="fail if the manifest is stale without rewriting it",
    )
    return result


def inventory() -> list[dict[str, str]]:
    assets: list[dict[str, str]] = []
    for path in sorted(ASSET_ROOT.rglob("*")):
        if not path.is_file() or path == MANIFEST_PATH or path in NON_BUNDLED_SIDECARS:
            continue
        suffix = path.suffix.lower()
        if suffix in IMAGE_SUFFIXES:
            kind = "image"
        elif suffix in AUDIO_SUFFIXES:
            kind = "audio"
        else:
            raise SystemExit(f"Unsupported native asset type: {path}")
        assets.append({"path": path.relative_to(ASSET_ROOT).as_posix(), "kind": kind})
    return assets


def main() -> int:
    args = parser().parse_args()
    document = json.loads(MANIFEST_PATH.read_text())
    expected = inventory()
    if document.get("assets") == expected:
        print(f"Native asset manifest is current: {len(expected)} assets")
        return 0
    if args.check:
        print(
            "Native asset manifest is stale: "
            f"declares {len(document.get('assets', []))}, physical inventory has {len(expected)}"
        )
        return 1
    document["assets"] = expected
    MANIFEST_PATH.write_text(json.dumps(document, indent=2) + "\n")
    print(f"Synchronized native asset manifest: {len(expected)} assets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
