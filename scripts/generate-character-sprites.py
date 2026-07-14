"""Generate Pocket Vector's original pre-rendered football character sprites.

Run from the repository root with Blender 5.x:

    blender -b --python scripts/generate-character-sprites.py

The generator intentionally writes only transparent WebP frames and metadata to
``public/assets/characters``. The game runtime is wired separately.
"""

from __future__ import annotations

import json
import math
from array import array
from pathlib import Path
from typing import Any

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "public" / "assets" / "characters"
CANVAS_WIDTH = 384
CANVAS_HEIGHT = 512
ANCHOR_X = 192
ANCHOR_Y = 496
WEBP_QUALITY = 88

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

# The reference receivers run in a pronounced travel-facing three-quarter
# profile. Defenders remain almost square to the quarterback and work through a
# slower, crouched shuffle instead of sharing the receiver sprint silhouette.
RECEIVER_TRAVEL_YAW = math.radians(65)
RECEIVER_UPPER_BODY_COUNTER_YAW = math.radians(-28)
RECEIVER_HEAD_COUNTER_YAW = math.radians(-23)
DEFENDER_SHUFFLE_YAW = 0.0


def srgb(hex_color: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    value = hex_color.removeprefix("#")
    channels = tuple(int(value[index : index + 2], 16) / 255 for index in (0, 2, 4))
    # Literal shader values are linear-light in Blender.
    return tuple(channel**2.2 for channel in channels) + (alpha,)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(collection):
            if datablock.users == 0:
                collection.remove(datablock)


def make_material(
    name: str,
    color: str,
    *,
    metallic: float = 0.0,
    roughness: float = 0.52,
    alpha: float = 1.0,
) -> bpy.types.Material:
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    result.diffuse_color = srgb(color, alpha)
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = srgb(color, alpha)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Alpha"].default_value = alpha
    if alpha < 1.0 and hasattr(result, "surface_render_method"):
        result.surface_render_method = "DITHERED"
    return result


def apply_material(obj: bpy.types.Object, value: bpy.types.Material) -> bpy.types.Object:
    obj.data.materials.append(value)
    return obj


def smooth(obj: bpy.types.Object) -> bpy.types.Object:
    if hasattr(obj.data, "polygons"):
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def sphere(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    value: bpy.types.Material,
    *,
    segments: int = 24,
    rings: int = 12,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return smooth(apply_material(obj, value))


def rounded_box(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    value: bpy.types.Material,
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.12,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = obj.modifiers.new("Arcade form bevel", "BEVEL")
    modifier.width = bevel
    modifier.segments = 4
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return smooth(apply_material(obj, value))


def tapered_torso(
    name: str,
    location: tuple[float, float, float],
    *,
    waist_radius: float,
    chest_radius: float,
    depth_scale: float,
    height: float,
    value: bpy.types.Material,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Create an athletic jersey shell with a readable chest-to-waist taper."""
    bpy.ops.mesh.primitive_cone_add(
        vertices=20,
        radius1=waist_radius,
        radius2=chest_radius,
        depth=height,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale.y = depth_scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = obj.modifiers.new("Jersey edge softness", "BEVEL")
    modifier.width = 0.075
    modifier.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return smooth(apply_material(obj, value))


def capsule(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    value: bpy.types.Material,
) -> bpy.types.Object:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    midpoint = (a + b) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=20,
        radius=radius,
        depth=max(direction.length, 0.001),
        location=midpoint,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    smooth(apply_material(obj, value))
    sphere(f"{name}.start", start, (radius * 1.02,) * 3, value, segments=16, rings=8)
    sphere(f"{name}.end", end, (radius * 1.02,) * 3, value, segments=16, rings=8)
    return obj


def add_number(
    number: str,
    location: tuple[float, float, float],
    value: bpy.types.Material,
    *,
    size: float,
    yaw: float = 0.0,
) -> None:
    # Default text faces -Y after this rotation, which is the sprite camera.
    bpy.ops.object.text_add(location=location, rotation=(math.pi / 2, 0.0, yaw))
    obj = bpy.context.object
    obj.name = f"Uniform number {number}"
    obj.data.body = number
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.004
    obj.data.bevel_depth = 0.003
    obj.data.materials.append(value)


def add_football(
    location: tuple[float, float, float],
    value: bpy.types.Material,
    *,
    rotation: tuple[float, float, float] = (0.0, -0.18, -0.25),
) -> None:
    ball = sphere("Football", location, (0.24, 0.135, 0.135), value, segments=24, rings=12)
    ball.rotation_euler = rotation


def add_shadow(width: float, depth: float, value: bpy.types.Material) -> None:
    sphere("Soft oval ground shadow", (0.0, 0.08, 0.035), (width, depth, 0.025), value)


def add_runner_helmet(
    center: tuple[float, float, float],
    _direction: int,
    shell: bpy.types.Material,
    accent: bpy.types.Material,
    cage: bpy.types.Material,
    skin: bpy.types.Material,
    *,
    head_turn: float = 0.0,
    is_receiver: bool = False,
) -> None:
    existing_objects = set(bpy.context.scene.objects.keys())
    x, y, z = center
    sphere(
        "Neck",
        (x, y + 0.01, z - 0.40),
        (0.14, 0.12, 0.18),
        skin,
        segments=20,
        rings=10,
    )
    sphere(
        "Player head",
        (x, y - 0.15, z - 0.08),
        (0.18, 0.14, 0.21) if is_receiver else (0.20, 0.15, 0.23),
        skin,
        segments=28,
        rings=14,
    )
    sphere(
        "Helmet shell",
        (x, y + 0.02, z + 0.08),
        (0.27, 0.25, 0.29) if is_receiver else (0.31, 0.28, 0.31),
        shell,
        segments=32,
        rings=16,
    )
    sphere(
        "Face and nose",
        (x, y - 0.27, z - 0.08),
        (0.15, 0.07, 0.17) if is_receiver else (0.18, 0.08, 0.19),
        skin,
        segments=20,
        rings=10,
    )
    # Two small brow/eye marks keep the oversized, expressive arcade face
    # readable. A full cage reduced the face to a robot-like grid at game scale.
    for eye_x in (-0.065, 0.065):
        rounded_box(
            f"Eye mark {eye_x}",
            (x + eye_x, y - 0.346, z - 0.025),
            (0.033, 0.008, 0.014),
            cage,
            bevel=0.008,
        )

    if is_receiver:
        visible_side = -_direction
        sphere(
            "Profile eye white",
            (x + visible_side * 0.165, y - 0.15, z - 0.015),
            (0.030, 0.022, 0.038),
            accent,
            segments=16,
            rings=8,
        )
        sphere(
            "Profile pupil",
            (x + visible_side * 0.185, y - 0.155, z - 0.015),
            (0.014, 0.014, 0.020),
            cage,
            segments=12,
            rings=6,
        )

    if head_turn:
        pivot = Matrix.Translation(Vector(center))
        turn = Matrix.Rotation(head_turn, 4, "Z")
        unpivot = Matrix.Translation(-Vector(center))
        for obj in bpy.context.scene.objects:
            if obj.name not in existing_objects:
                obj.matrix_world = pivot @ turn @ unpivot @ obj.matrix_world


def add_qb_helmet(
    center: tuple[float, float, float],
    shell: bpy.types.Material,
    accent: bpy.types.Material,
    cage: bpy.types.Material,
    skin: bpy.types.Material,
    *,
    yaw: float,
) -> None:
    x, y, z = center
    rear_x = math.sin(yaw)
    rear_y = -math.cos(yaw)
    front_x = -rear_x
    sphere(
        "QB neck",
        (x, y + 0.02, z - 0.40),
        (0.15, 0.13, 0.19),
        skin,
        segments=20,
        rings=10,
    )
    sphere(
        "Rear helmet shell",
        (x, y + 0.01, z + 0.04),
        (0.30, 0.28, 0.33),
        shell,
        segments=32,
        rings=16,
    )
    capsule(
        "Rear helmet stripe",
        (x, y - 0.285, z - 0.20),
        (x, y - 0.285, z + 0.31),
        0.025,
        accent,
    )
    # Only expose a face/cage sliver for a meaningful head turn. The reference
    # QB is almost square in rear view through the wind-up and release.
    if abs(yaw) >= 0.12:
        side_x = x + front_x * 0.31
        side_y = y + rear_y * 0.16
        sphere(
            "QB side face",
            (side_x, side_y, z - 0.09),
            (0.15, 0.055, 0.15),
            skin,
            segments=20,
            rings=10,
        )
        capsule(
            "QB visible cage",
            (side_x + front_x * 0.02, side_y + rear_y * 0.04, z - 0.08),
            (side_x + front_x * 0.22, side_y + rear_y * 0.04, z - 0.12),
            0.022,
            cage,
        )


def mirrored(point: tuple[float, float, float], direction: int) -> tuple[float, float, float]:
    return (point[0] * direction, point[1], point[2])


def rotate_point_about_z(
    point: tuple[float, float, float],
    pivot: tuple[float, float, float],
    angle: float,
) -> tuple[float, float, float]:
    offset = Vector(point) - Vector(pivot)
    rotated = Matrix.Rotation(angle, 4, "Z") @ offset
    result = Vector(pivot) + rotated
    return (result.x, result.y, result.z)


def rotate_objects_about_z(
    objects: list[bpy.types.Object],
    pivot: tuple[float, float, float],
    angle: float,
) -> None:
    pivot_matrix = Matrix.Translation(Vector(pivot))
    turn = Matrix.Rotation(angle, 4, "Z")
    unpivot = Matrix.Translation(-Vector(pivot))
    for obj in objects:
        obj.matrix_world = pivot_matrix @ turn @ unpivot @ obj.matrix_world


def turn_character_rig(
    direction: int,
    yaw_radians: float,
    *,
    screen_lean_radians: float = 0.0,
) -> None:
    """Turn an assembled character while leaving its contact shadow level."""
    members = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type not in {"CAMERA", "LIGHT"} and obj.name != "Soft oval ground shadow"
    ]
    root = bpy.data.objects.new("Travel-facing character rig", None)
    bpy.context.collection.objects.link(root)
    for obj in members:
        obj.parent = root
    root.matrix_world = Matrix.Rotation(
        screen_lean_radians * direction,
        4,
        "Y",
    ) @ Matrix.Rotation(yaw_radians * direction, 4, "Z")


RUNNER_POSES: dict[str, dict[str, Any]] = {
    "run1": {
        # Flight: lead knee high, opposite arm driving toward travel.
        "hips": ((-0.15, 0.10, 1.24), (0.15, -0.10, 1.24)),
        "knees": ((-0.45, 0.12, 0.70), (0.48, -0.13, 1.03)),
        "ankles": ((-0.72, 0.10, 0.24), (0.40, -0.16, 0.62)),
        "feet": ((-0.55, -0.01, 0.12), (0.61, -0.18, 0.52)),
        "shoulders": ((-0.42, 0.08, 1.96), (0.45, -0.08, 1.96)),
        "elbows": ((-0.10, -0.16, 1.76), (0.62, 0.12, 1.62)),
        "hands": ((0.18, -0.22, 1.88), (0.78, 0.18, 1.38)),
        "torso": (0.03, 0.0, 1.69),
        "helmet": (0.13, -0.02, 2.55),
        "lean": 0.18,
    },
    "run2": {
        # Reach/contact: lead foot extends and the body compresses over it.
        "hips": ((-0.15, 0.10, 1.21), (0.15, -0.10, 1.21)),
        "knees": ((-0.28, 0.12, 0.82), (0.58, -0.13, 0.72)),
        "ankles": ((-0.50, 0.10, 0.38), (0.82, -0.16, 0.23)),
        "feet": ((-0.34, -0.01, 0.32), (0.98, -0.18, 0.12)),
        "shoulders": ((-0.42, 0.08, 1.92), (0.45, -0.08, 1.92)),
        "elbows": ((-0.18, -0.14, 1.70), (0.52, 0.12, 1.60)),
        "hands": ((0.05, -0.20, 1.74), (0.68, 0.18, 1.45)),
        "torso": (0.04, 0.0, 1.65),
        "helmet": (0.14, -0.02, 2.51),
        "lean": 0.21,
    },
    "run3": {
        # Opposite flight phase.
        "hips": ((-0.15, 0.10, 1.24), (0.15, -0.10, 1.24)),
        "knees": ((0.48, 0.12, 1.03), (-0.45, -0.13, 0.70)),
        "ankles": ((0.40, 0.10, 0.62), (-0.72, -0.16, 0.24)),
        "feet": ((0.61, -0.01, 0.52), (-0.55, -0.18, 0.12)),
        "shoulders": ((-0.42, 0.08, 1.96), (0.45, -0.08, 1.96)),
        "elbows": ((-0.62, 0.12, 1.62), (0.10, -0.16, 1.76)),
        "hands": ((-0.78, 0.18, 1.38), (-0.18, -0.22, 1.88)),
        "torso": (0.03, 0.0, 1.69),
        "helmet": (0.13, -0.02, 2.55),
        "lean": 0.18,
    },
    "run4": {
        # Opposite reach/contact phase.
        "hips": ((-0.15, 0.10, 1.21), (0.15, -0.10, 1.21)),
        "knees": ((0.58, 0.12, 0.72), (-0.28, -0.13, 0.82)),
        "ankles": ((0.82, 0.10, 0.23), (-0.50, -0.16, 0.38)),
        "feet": ((0.98, -0.01, 0.12), (-0.34, -0.18, 0.32)),
        "shoulders": ((-0.42, 0.08, 1.92), (0.45, -0.08, 1.92)),
        "elbows": ((-0.52, 0.12, 1.60), (0.18, -0.14, 1.70)),
        "hands": ((-0.68, 0.18, 1.45), (-0.05, -0.20, 1.74)),
        "torso": (0.04, 0.0, 1.65),
        "helmet": (0.14, -0.02, 2.51),
        "lean": 0.21,
    },
    "catch": {
        "hips": ((-0.16, 0.10, 1.27), (0.16, -0.10, 1.27)),
        "knees": ((-0.29, 0.11, 0.70), (0.31, -0.13, 0.73)),
        "ankles": ((-0.39, 0.09, 0.23), (0.48, -0.15, 0.24)),
        "feet": ((-0.27, -0.01, 0.11), (0.63, -0.18, 0.12)),
        "shoulders": ((-0.42, 0.07, 2.04), (0.49, -0.08, 2.03)),
        "elbows": ((0.14, 0.02, 2.03), (0.32, -0.18, 1.78)),
        "hands": ((0.66, -0.10, 2.10), (0.66, -0.26, 1.88)),
        "torso": (0.03, 0.0, 1.69),
        "helmet": (0.10, -0.02, 2.55),
        "lean": 0.12,
    },
    "touchdown": {
        "hips": ((-0.16, 0.10, 1.27), (0.16, -0.10, 1.27)),
        "knees": ((-0.28, 0.11, 0.71), (0.30, -0.13, 0.72)),
        "ankles": ((-0.38, 0.09, 0.23), (0.43, -0.15, 0.23)),
        "feet": ((-0.26, -0.01, 0.11), (0.58, -0.18, 0.11)),
        "shoulders": ((-0.43, 0.07, 2.04), (0.49, -0.08, 2.03)),
        "elbows": ((-0.54, 0.01, 2.48), (0.60, -0.15, 2.47)),
        "hands": ((-0.44, -0.07, 2.83), (0.69, -0.22, 2.82)),
        "torso": (0.0, 0.0, 1.68),
        "helmet": (0.04, -0.02, 2.54),
        "lean": 0.0,
    },
}


DEFENDER_POSES: dict[str, dict[str, Any]] = {
    "run1": {
        # Low left-foot weight shift with elbows bent and palms open.
        "hips": ((-0.17, 0.10, 1.20), (0.17, -0.10, 1.20)),
        "knees": ((-0.43, 0.11, 0.64), (0.35, -0.13, 0.70)),
        "ankles": ((-0.55, 0.09, 0.21), (0.44, -0.15, 0.24)),
        "feet": ((-0.69, -0.01, 0.10), (0.57, -0.18, 0.12)),
        "shoulders": ((-0.50, 0.03, 1.93), (0.50, -0.03, 1.93)),
        "elbows": ((-0.72, -0.11, 1.78), (0.70, -0.13, 1.78)),
        "hands": ((-0.84, -0.30, 1.84), (0.82, -0.31, 1.92)),
        "torso": (-0.03, 0.0, 1.59),
        "helmet": (-0.03, -0.02, 2.44),
        "lean": -0.03,
    },
    "run2": {
        "hips": ((-0.17, 0.10, 1.18), (0.17, -0.10, 1.18)),
        "knees": ((-0.36, 0.11, 0.64), (0.36, -0.13, 0.64)),
        "ankles": ((-0.48, 0.09, 0.21), (0.48, -0.15, 0.21)),
        "feet": ((-0.62, -0.01, 0.10), (0.62, -0.18, 0.10)),
        "shoulders": ((-0.50, 0.03, 1.90), (0.50, -0.03, 1.90)),
        "elbows": ((-0.66, -0.12, 1.77), (0.66, -0.14, 1.77)),
        "hands": ((-0.78, -0.31, 1.84), (0.78, -0.32, 1.84)),
        "torso": (0.0, 0.0, 1.56),
        "helmet": (0.0, -0.02, 2.41),
        "lean": 0.0,
    },
    "run3": {
        # Mirror the weight shift while keeping the chest square to the QB.
        "hips": ((-0.17, 0.10, 1.20), (0.17, -0.10, 1.20)),
        "knees": ((-0.35, 0.11, 0.70), (0.43, -0.13, 0.64)),
        "ankles": ((-0.44, 0.09, 0.24), (0.55, -0.15, 0.21)),
        "feet": ((-0.57, -0.01, 0.12), (0.69, -0.18, 0.10)),
        "shoulders": ((-0.50, 0.03, 1.93), (0.50, -0.03, 1.93)),
        "elbows": ((-0.70, -0.11, 1.78), (0.72, -0.13, 1.78)),
        "hands": ((-0.82, -0.30, 1.92), (0.84, -0.31, 1.84)),
        "torso": (0.03, 0.0, 1.59),
        "helmet": (0.03, -0.02, 2.44),
        "lean": 0.03,
    },
    "run4": {
        "hips": ((-0.17, 0.10, 1.18), (0.17, -0.10, 1.18)),
        "knees": ((-0.36, 0.11, 0.64), (0.36, -0.13, 0.64)),
        "ankles": ((-0.48, 0.09, 0.21), (0.48, -0.15, 0.21)),
        "feet": ((-0.62, -0.01, 0.10), (0.62, -0.18, 0.10)),
        "shoulders": ((-0.50, 0.03, 1.91), (0.50, -0.03, 1.91)),
        "elbows": ((-0.65, -0.12, 1.78), (0.65, -0.14, 1.78)),
        "hands": ((-0.76, -0.31, 1.86), (0.76, -0.32, 1.86)),
        "torso": (0.0, 0.0, 1.57),
        "helmet": (0.0, -0.02, 2.42),
        "lean": 0.0,
    },
    "interception": {
        "hips": ((-0.16, 0.10, 1.23), (0.16, -0.10, 1.23)),
        "knees": ((-0.34, 0.11, 0.67), (0.35, -0.13, 0.68)),
        "ankles": ((-0.47, 0.09, 0.22), (0.51, -0.15, 0.22)),
        "feet": ((-0.34, -0.01, 0.10), (0.66, -0.18, 0.10)),
        "shoulders": ((-0.44, 0.07, 1.95), (0.49, -0.08, 1.94)),
        "elbows": ((0.05, 0.02, 2.17), (0.36, -0.17, 2.13)),
        "hands": ((0.52, -0.08, 2.47), (0.69, -0.24, 2.32)),
        "torso": (0.0, 0.0, 1.58),
        "helmet": (0.0, -0.02, 2.43),
        "lean": 0.0,
    },
}


QB_POSES: dict[str, dict[str, Any]] = {
    "idle": {
        "hips": ((-0.20, 0.13, 1.27), (0.20, -0.12, 1.27)),
        "knees": ((-0.34, 0.11, 0.72), (0.35, -0.12, 0.72)),
        "ankles": ((-0.44, 0.08, 0.23), (0.46, -0.13, 0.23)),
        "feet": ((-0.33, -0.02, 0.11), (0.59, -0.16, 0.11)),
        "shoulders": ((-0.52, 0.18, 2.03), (0.52, -0.18, 2.03)),
        "elbows": ((-0.56, -0.08, 1.70), (0.57, -0.12, 1.72)),
        "hands": ((-0.45, -0.25, 1.23), (0.47, -0.28, 1.25)),
        "ball": None,
        "torso": (0.0, 0.0, 1.71),
        "helmet": (0.0, 0.02, 2.60),
        "yaw": 0.03,
    },
    "aim": {
        "hips": ((-0.22, 0.14, 1.27), (0.19, -0.13, 1.27)),
        "knees": ((-0.36, 0.11, 0.72), (0.38, -0.12, 0.73)),
        "ankles": ((-0.48, 0.08, 0.23), (0.51, -0.13, 0.24)),
        "feet": ((-0.36, -0.02, 0.11), (0.65, -0.16, 0.11)),
        "shoulders": ((-0.53, 0.19, 2.03), (0.52, -0.19, 2.04)),
        "elbows": ((0.10, -0.10, 2.08), (0.72, -0.18, 2.27)),
        "hands": ((0.41, -0.31, 2.34), (0.60, -0.36, 2.48)),
        "ball": (0.62, -0.43, 2.49),
        "torso": (0.0, 0.0, 1.71),
        "helmet": (0.0, 0.02, 2.60),
        "yaw": 0.07,
    },
    "throw": {
        "hips": ((-0.23, 0.15, 1.27), (0.20, -0.14, 1.27)),
        "knees": ((-0.39, 0.12, 0.72), (0.42, -0.13, 0.75)),
        "ankles": ((-0.53, 0.08, 0.23), (0.58, -0.14, 0.25)),
        "feet": ((-0.41, -0.02, 0.11), (0.72, -0.17, 0.12)),
        "shoulders": ((-0.54, 0.20, 2.02), (0.53, -0.17, 2.05)),
        "elbows": ((-0.04, -0.03, 2.07), (0.68, 0.03, 2.48)),
        "hands": ((0.22, 0.06, 2.20), (0.29, 0.30, 2.82)),
        "ball": None,
        "torso": (0.0, 0.01, 1.71),
        "helmet": (0.0, 0.03, 2.60),
        "yaw": 0.10,
    },
    "recovery": {
        "hips": ((-0.22, 0.14, 1.27), (0.20, -0.13, 1.27)),
        "knees": ((-0.37, 0.11, 0.72), (0.40, -0.12, 0.74)),
        "ankles": ((-0.49, 0.08, 0.23), (0.54, -0.13, 0.24)),
        "feet": ((-0.37, -0.02, 0.11), (0.68, -0.16, 0.11)),
        "shoulders": ((-0.53, 0.19, 2.03), (0.52, -0.18, 2.04)),
        "elbows": ((-0.44, -0.15, 1.88), (0.16, -0.18, 1.98)),
        "hands": ((-0.25, -0.32, 1.75), (-0.18, -0.34, 1.82)),
        "ball": None,
        "torso": (0.0, 0.01, 1.71),
        "helmet": (0.0, 0.03, 2.60),
        "yaw": 0.06,
    },
}


def make_palette(name: str, colors: dict[str, str]) -> dict[str, bpy.types.Material]:
    return {
        "jersey": make_material(f"{name} jersey", colors["jersey"], roughness=0.58),
        "pads": make_material(f"{name} pads", colors["pads"], roughness=0.54),
        "pants": make_material(f"{name} pants", colors["pants"], roughness=0.56),
        "helmet": make_material(
            f"{name} helmet", colors["helmet"], metallic=0.02, roughness=0.45
        ),
        "accent": make_material(
            f"{name} accent", colors["accent"], metallic=0.01, roughness=0.48
        ),
        "socks": make_material(f"{name} socks", colors["socks"], roughness=0.58),
        "number": make_material(f"{name} number", colors["number"], roughness=0.40),
        "gloves": make_material(
            f"{name} gloves", colors.get("gloves", "#F6F1E7"), roughness=0.42
        ),
        "shoes": make_material(f"{name} cleats", "#17202A", metallic=0.08, roughness=0.35),
        "cage": make_material(f"{name} cage", "#151A20", metallic=0.32, roughness=0.18),
        "skin": make_material(f"{name} skin", "#D19A66", roughness=0.66),
        "leather": make_material(f"{name} football", "#8A3C22", roughness=0.48),
        "shadow": make_material(f"{name} shadow", "#091019", roughness=0.95, alpha=0.25),
    }


def add_uniform_body(
    pose: dict[str, Any],
    materials: dict[str, bpy.types.Material],
    *,
    direction: int,
    number: str,
    role: str,
) -> None:
    if role == "receiver":
        thigh_radius, shin_radius = 0.11, 0.075
        upper_arm_radius, forearm_radius = 0.085, 0.065
        shoe_scale = (0.21, 0.10, 0.075)
        glove_scale = (0.075, 0.055, 0.085)
        torso_profile = (0.23, 0.34, 0.62, 0.74)
        pad_scale = (0.18, 0.20, 0.12)
        bridge_scale = (0.15, 0.18, 0.075)
        hip_scale = (0.26, 0.20, 0.15)
        yoke_width = 0.24
        surface_depth = 0.25
        shoulder_width_scale = 0.81
        hip_width_scale = 0.87
    elif role == "quarterback":
        thigh_radius, shin_radius = 0.145, 0.105
        upper_arm_radius, forearm_radius = 0.12, 0.085
        shoe_scale = (0.25, 0.13, 0.095)
        glove_scale = (0.09, 0.07, 0.095)
        torso_profile = (0.29, 0.43, 0.66, 0.77)
        pad_scale = (0.23, 0.25, 0.14)
        bridge_scale = (0.22, 0.23, 0.09)
        hip_scale = (0.33, 0.25, 0.18)
        yoke_width = 0.29
        surface_depth = 0.30
        shoulder_width_scale = 0.85
        hip_width_scale = 0.86
    else:
        thigh_radius, shin_radius = 0.12, 0.085
        upper_arm_radius, forearm_radius = 0.10, 0.075
        shoe_scale = (0.23, 0.12, 0.085)
        glove_scale = (0.095, 0.06, 0.105)
        torso_profile = (0.27, 0.40, 0.64, 0.74)
        pad_scale = (0.21, 0.23, 0.13)
        bridge_scale = (0.18, 0.21, 0.08)
        hip_scale = (0.29, 0.22, 0.16)
        yoke_width = 0.27
        surface_depth = 0.28
        shoulder_width_scale = 0.76
        hip_width_scale = 0.76

    hips = tuple(
        mirrored((point[0] * hip_width_scale, point[1], point[2]), direction)
        for point in pose["hips"]
    )
    knees = tuple(mirrored(point, direction) for point in pose["knees"])
    ankles = tuple(mirrored(point, direction) for point in pose["ankles"])
    feet = tuple(mirrored(point, direction) for point in pose["feet"])
    shoulders = tuple(
        mirrored((point[0] * shoulder_width_scale, point[1], point[2]), direction)
        for point in pose["shoulders"]
    )
    elbows = tuple(mirrored(point, direction) for point in pose["elbows"])
    hands = tuple(mirrored(point, direction) for point in pose["hands"])

    for side in (0, 1):
        capsule(f"Thigh {side}", hips[side], knees[side], thigh_radius, materials["pants"])
        capsule(f"Shin {side}", knees[side], ankles[side], shin_radius, materials["socks"])
        shoe = sphere(
            f"Cleat {side}",
            feet[side],
            shoe_scale,
            materials["shoes"],
            segments=20,
            rings=10,
        )
        shoe.rotation_euler[1] = 0.10 * direction
        capsule(
            f"Upper arm {side}",
            shoulders[side],
            elbows[side],
            upper_arm_radius,
            materials["jersey"],
        )
        capsule(
            f"Forearm {side}",
            elbows[side],
            hands[side],
            forearm_radius,
            materials["skin"],
        )
        sphere(
            f"Oversized glove {side}",
            hands[side],
            glove_scale,
            materials["skin"],
            segments=20,
            rings=10,
        )
        if role == "defender":
            outward = -1.0 if hands[side][0] < 0 else 1.0
            for finger_index, height_offset in enumerate((-0.04, 0.0, 0.04)):
                capsule(
                    f"Open palm finger {side}.{finger_index}",
                    (
                        hands[side][0] + outward * 0.02,
                        hands[side][1],
                        hands[side][2] + height_offset * 0.45,
                    ),
                    (
                        hands[side][0] + outward * 0.095,
                        hands[side][1] - 0.012,
                        hands[side][2] + height_offset,
                    ),
                    0.014,
                    materials["skin"],
                )

    torso = mirrored(pose["torso"], direction)
    lean = pose.get("lean", 0.0) * direction
    yaw = pose.get("yaw", 0.0) * direction
    waist_radius, chest_radius, depth_scale, torso_height = torso_profile
    tapered_torso(
        "Jersey torso",
        torso,
        waist_radius=waist_radius,
        chest_radius=chest_radius,
        depth_scale=depth_scale,
        height=torso_height,
        value=materials["jersey"],
        rotation=(0.0, lean, yaw),
    )
    # Separate, flattened pad caps preserve an angular human shoulder line
    # instead of either a continuous bar or disconnected toy-like spheres.
    for side, shoulder in enumerate(shoulders):
        rounded_box(
            f"Shoulder pad cap {side}",
            (shoulder[0], shoulder[1], shoulder[2]),
            pad_scale,
            materials["pads"],
            rotation=(0.0, 0.0, yaw),
            bevel=0.105,
        )
    sphere(
        "Shoulder pad bridge",
        (torso[0], torso[1], torso[2] + 0.31),
        bridge_scale,
        materials["pads"],
        segments=24,
        rings=12,
    )
    sphere(
        "Padded hips",
        (
            torso[0] - 0.015 * direction,
            torso[1],
            (hips[0][2] + hips[1][2]) * 0.5 + 0.03,
        ),
        hip_scale,
        materials["pants"],
    )
    # A restrained yoke and number preserve team readability without flattening
    # the torso into a billboard.
    rear_x = math.sin(yaw)
    rear_y = -math.cos(yaw)
    rounded_box(
        "Uniform yoke",
        (
            torso[0] + rear_x * surface_depth,
            torso[1] + rear_y * surface_depth,
            torso[2] + 0.25,
        ),
        (yoke_width, 0.018, 0.055),
        materials["accent"],
        rotation=(0.0, 0.0, yaw),
        bevel=0.018,
    )
    add_number(
        number,
        (
            torso[0] + rear_x * (surface_depth + 0.014),
            torso[1] + rear_y * (surface_depth + 0.014),
            torso[2] + 0.01,
        ),
        materials["number"],
        size=0.31 if len(number) == 1 else 0.245,
        yaw=yaw,
    )


def build_runner(role: str, pose_name: str, direction: int) -> None:
    is_receiver = role == "receiver"
    pose = (RUNNER_POSES if is_receiver else DEFENDER_POSES)[pose_name]
    materials = make_palette("Comets" if is_receiver else "Phantoms", OFFENSE if is_receiver else DEFENSE)
    add_shadow(0.54 if is_receiver else 0.58, 0.22, materials["shadow"])
    add_uniform_body(
        pose,
        materials,
        direction=direction,
        number="11" if is_receiver else "24",
        role=role,
    )
    helmet_center = mirrored(pose["helmet"], direction)
    if is_receiver:
        torso_center = mirrored(pose["torso"], direction)
        counter_yaw = RECEIVER_UPPER_BODY_COUNTER_YAW * direction
        upper_body_prefixes = (
            "Jersey torso",
            "Shoulder pad",
            "Upper arm",
            "Forearm",
            "Oversized glove",
            "Uniform yoke",
            "Uniform number",
        )
        rotate_objects_about_z(
            [
                obj
                for obj in bpy.context.scene.objects
                if obj.name.startswith(upper_body_prefixes)
            ],
            torso_center,
            counter_yaw,
        )
        helmet_center = rotate_point_about_z(
            helmet_center,
            torso_center,
            counter_yaw,
        )
    add_runner_helmet(
        helmet_center,
        direction,
        materials["helmet"],
        materials["accent"],
        materials["cage"],
        materials["skin"],
        head_turn=RECEIVER_HEAD_COUNTER_YAW * direction if is_receiver else 0.0,
        is_receiver=is_receiver,
    )
    turn_character_rig(
        direction,
        RECEIVER_TRAVEL_YAW if is_receiver else DEFENDER_SHUFFLE_YAW,
        screen_lean_radians=math.radians(10) if is_receiver else 0.0,
    )


def build_quarterback(pose_name: str) -> None:
    pose = QB_POSES[pose_name]
    materials = make_palette("Comets", OFFENSE)
    add_shadow(0.62, 0.24, materials["shadow"])
    add_uniform_body(pose, materials, direction=1, number="7", role="quarterback")
    add_qb_helmet(
        pose["helmet"],
        materials["helmet"],
        materials["accent"],
        materials["cage"],
        materials["skin"],
        yaw=pose["yaw"],
    )
    if pose["ball"] is not None:
        add_football(pose["ball"], materials["leather"])


def add_light(
    name: str,
    location: tuple[float, float, float],
    energy: float,
    color: str,
    size: float,
) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = srgb(color)[:3]
    data.shape = "DISK"
    data.size = size
    data.use_shadow = True
    light = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(light)
    light.location = location
    target = Vector((0.0, 0.0, 1.45))
    light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()


def setup_render_scene() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = CANVAS_WIDTH
    scene.render.resolution_y = CANVAS_HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "WEBP"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.quality = WEBP_QUALITY
    scene.render.film_transparent = True
    scene.render.use_file_extension = True
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    # No Freestyle outlines: form comes from soft volume, highlights, and AO-like fill.
    scene.render.use_freestyle = False

    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = srgb("#283746")
    background.inputs["Strength"].default_value = 0.24

    camera_data = bpy.data.cameras.new("SharedSpriteCamera")
    camera = bpy.data.objects.new("SharedSpriteCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0.0, -11.5, 3.05)
    target = Vector((0.0, 0.0, 1.48))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 3.52
    camera.data.lens = 60
    scene.camera = camera

    # Bright upper-left/front stadium key, restrained cool fill, and soft rear rim.
    add_light("Stadium key", (-4.6, -5.8, 7.5), 750, "#FFF0D7", 5.2)
    add_light("Cool fill", (4.0, -3.2, 4.6), 350, "#ACD7FF", 4.4)
    add_light("Aqua rim", (1.6, 4.5, 6.2), 300, "#B4FFF5", 3.8)


def image_content_bounds(path: Path) -> dict[str, int]:
    image = bpy.data.images.load(str(path), check_existing=False)
    width, height = image.size
    pixels = array("f", [0.0]) * (width * height * 4)
    image.pixels.foreach_get(pixels)
    min_x, min_y = width, height
    max_x = max_y = -1
    for pixel_index in range(width * height):
        if pixels[pixel_index * 4 + 3] <= 0.015:
            continue
        x = pixel_index % width
        y = pixel_index // width
        min_x = min(min_x, x)
        min_y = min(min_y, y)
        max_x = max(max_x, x)
        max_y = max(max_y, y)
    bpy.data.images.remove(image)
    if max_x < min_x or max_y < min_y:
        return {"x": 0, "y": 0, "width": 0, "height": 0}
    return {
        "x": min_x,
        "y": height - 1 - max_y,
        "width": max_x - min_x + 1,
        "height": max_y - min_y + 1,
    }


def frame_metadata(filename: str, role: str, pose: str, direction: str) -> dict[str, Any]:
    path = OUTPUT_DIR / filename
    return {
        "src": f"/assets/characters/{filename}",
        "role": role,
        "pose": pose,
        "direction": direction,
        "width": CANVAS_WIDTH,
        "height": CANVAS_HEIGHT,
        "anchor": {"x": ANCHOR_X, "y": ANCHOR_Y},
        "contentBounds": image_content_bounds(path),
        "bytes": path.stat().st_size,
    }


def render_frame(filename: str, role: str, pose: str, direction: str) -> dict[str, Any]:
    clear_scene()
    setup_render_scene()
    if role == "quarterback":
        build_quarterback(pose)
    else:
        build_runner(role, pose, 1 if direction == "right" else -1)
    output_path = OUTPUT_DIR / filename
    bpy.context.scene.render.filepath = str(output_path)
    bpy.ops.render.render(write_still=True)
    print(f"Rendered {filename}")
    return frame_metadata(filename, role, pose, direction)


FRAME_SPECS = [
    ("qb-idle.webp", "quarterback", "idle", "rear"),
    ("qb-aim.webp", "quarterback", "aim", "rear"),
    ("qb-throw.webp", "quarterback", "throw", "rear"),
    ("qb-recovery.webp", "quarterback", "recovery", "rear"),
]

for runner_role, poses in (
    ("receiver", ("run1", "run2", "run3", "run4", "catch", "touchdown")),
    ("defender", ("run1", "run2", "run3", "run4", "interception")),
):
    for runner_pose in poses:
        output_pose = {
            "run1": "run-1",
            "run2": "run-2",
            "run3": "run-3",
            "run4": "run-4",
        }.get(runner_pose, runner_pose)
        for runner_direction in ("left", "right"):
            FRAME_SPECS.append(
                (
                    f"{runner_role}-{output_pose}-{runner_direction}.webp",
                    runner_role,
                    runner_pose,
                    runner_direction,
                )
            )


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    expected_files = {spec[0] for spec in FRAME_SPECS}
    for existing in OUTPUT_DIR.glob("*.webp"):
        if existing.name not in expected_files:
            existing.unlink()

    frames = [render_frame(*spec) for spec in FRAME_SPECS]
    manifest = {
        "version": 2,
        "generator": "scripts/generate-character-sprites.py",
        "canvas": {
            "width": CANVAS_WIDTH,
            "height": CANVAS_HEIGHT,
            "anchor": {"x": ANCHOR_X, "y": ANCHOR_Y},
        },
        "render": {
            "engine": "BLENDER_EEVEE",
            "format": "webp",
            "quality": WEBP_QUALITY,
            "camera": "fixed orthographic rear QB, travel-facing receiver, square defender camera",
            "background": "transparent",
        },
        "teams": {
            "offense": {"name": "Nova City Comets", "palette": OFFENSE},
            "defense": {"name": "Iron Bay Phantoms", "palette": DEFENSE},
        },
        "frames": frames,
    }
    manifest_path = OUTPUT_DIR / "sprites.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    total_bytes = sum((OUTPUT_DIR / filename).stat().st_size for filename in expected_files)
    print(f"Generated {len(frames)} frames in {OUTPUT_DIR}")
    print(f"Total WebP bytes: {total_bytes}")


if __name__ == "__main__":
    main()
