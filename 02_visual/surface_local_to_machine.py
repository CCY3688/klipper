#!/usr/bin/env python3
"""Map surface GUI local trajectory points to machine coordinates.

The GUI trajectory is defined in the manually aligned workpiece photo.  This
script uses the camera intrinsics, ChArUco camera pose, and board-to-machine
fit to convert those visible image points into machine XY commands.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import cv2
import numpy as np

VISUAL_DIR = Path(__file__).resolve().parent
if str(VISUAL_DIR) not in sys.path:
    sys.path.insert(0, str(VISUAL_DIR))

from stage0_machine_frame import (  # noqa: E402
    DEFAULT_BOARD_ORIGIN,
    DEFAULT_CHARUCO,
    DEFAULT_INTRINSICS,
    load_intrinsics,
    load_json,
    load_t_camera_from_board,
)
from surface_trajectory_verify_detect import DEFAULT_MACHINE_TRANSFORM  # noqa: E402


def _local_to_image_px(local: np.ndarray, alignment: dict, image_size: dict) -> np.ndarray:
    yaw = math.radians(float(alignment["yaw_deg"]))
    cos_yaw = math.cos(yaw)
    sin_yaw = math.sin(yaw)
    center = alignment["center_px"]
    offset = alignment["center_offset_px"]
    scale = float(alignment["scale_px_per_mm"])
    local_px_x = local[0] * scale
    local_px_y = -local[1] * scale
    rotated_x = local_px_x * cos_yaw - local_px_y * sin_yaw
    rotated_y = local_px_x * sin_yaw + local_px_y * cos_yaw
    width = float(image_size["width"])
    height = float(image_size["height"])
    center_x = float(center.get("x", width / 2.0))
    center_y = float(center.get("y", height / 2.0))
    return np.array(
        [
            center_x + float(offset["x"]) + rotated_x,
            center_y + float(offset["y"]) + rotated_y,
        ],
        dtype=np.float64,
    )


def _image_px_to_board_up(
    image_px: np.ndarray,
    z_up_mm: float,
    camera_matrix: np.ndarray,
    dist_coeffs: np.ndarray,
    t_camera_from_board: np.ndarray,
) -> np.ndarray:
    undistorted = cv2.undistortPoints(
        image_px.reshape(1, 1, 2).astype(np.float64),
        camera_matrix,
        dist_coeffs,
    ).reshape(2)
    ray_camera = np.array([undistorted[0], undistorted[1], 1.0], dtype=np.float64)

    t_board_from_camera = np.linalg.inv(t_camera_from_board)
    origin_board_raw = t_board_from_camera @ np.array([0.0, 0.0, 0.0, 1.0])
    direction_board_raw = t_board_from_camera[:3, :3] @ ray_camera
    raw_z = -float(z_up_mm)
    if abs(direction_board_raw[2]) < 1e-9:
        raise RuntimeError("Camera ray is parallel to the requested board plane.")
    lam = (raw_z - origin_board_raw[2]) / direction_board_raw[2]
    raw = origin_board_raw[:3] + lam * direction_board_raw
    return np.array([raw[0], raw[1], float(z_up_mm)], dtype=np.float64)


def _machine_from_board_up(
    board_up: np.ndarray,
    t_machine_from_board_up: np.ndarray,
) -> np.ndarray:
    point = np.array([board_up[0], board_up[1], board_up[2], 1.0], dtype=np.float64)
    return (t_machine_from_board_up @ point)[:3]


def convert(payload: dict, args: argparse.Namespace) -> dict:
    alignment = payload["manual_alignment"]
    image_size = payload["image_size_px"]
    points = payload["points"]
    camera_matrix, dist_coeffs = load_intrinsics(Path(args.intrinsics))
    t_camera_from_board = load_t_camera_from_board(
        Path(args.charuco_extrinsic),
        args.board_origin,
    )
    transform_payload = load_json(Path(args.machine_transform))
    t_machine_from_board_up = np.array(
        transform_payload["T_machine_from_board_up"],
        dtype=np.float64,
    )

    mapped = []
    for point in points:
        local = np.array(
            [float(point["local_x_mm"]), float(point["local_y_mm"])],
            dtype=np.float64,
        )
        z_up = float(point.get("surface_height_mm", 0.0))
        image_px = _local_to_image_px(local, alignment, image_size)
        board_up = _image_px_to_board_up(
            image_px,
            z_up,
            camera_matrix,
            dist_coeffs,
            t_camera_from_board,
        )
        machine = _machine_from_board_up(board_up, t_machine_from_board_up)
        mapped.append(
            {
                "index": int(point["index"]),
                "local_x_mm": float(local[0]),
                "local_y_mm": float(local[1]),
                "surface_height_mm": z_up,
                "image_x_px": float(image_px[0]),
                "image_y_px": float(image_px[1]),
                "board_x_mm": float(board_up[0]),
                "board_y_mm": float(board_up[1]),
                "board_z_mm": float(board_up[2]),
                "machine_x_mm": float(machine[0]),
                "machine_y_mm": float(machine[1]),
                "machine_z_from_board_mm": float(machine[2]),
            }
        )

    return {
        "method": "surface_photo_local_to_machine",
        "machine_transform": str(Path(args.machine_transform)),
        "charuco_extrinsic": str(Path(args.charuco_extrinsic)),
        "intrinsics": str(Path(args.intrinsics)),
        "board_origin": args.board_origin,
        "points": mapped,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert surface GUI-local points to calibrated machine XY.",
    )
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--intrinsics", default=str(DEFAULT_INTRINSICS))
    parser.add_argument("--charuco-extrinsic", default=str(DEFAULT_CHARUCO))
    parser.add_argument("--machine-transform", default=str(DEFAULT_MACHINE_TRANSFORM))
    parser.add_argument("--board-origin", choices=("center", "corner"), default=DEFAULT_BOARD_ORIGIN)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    with Path(args.input).open("r", encoding="utf-8") as f:
        payload = json.load(f)
    result = convert(payload, args)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"mapped {len(result['points'])} surface points")


if __name__ == "__main__":
    main()
