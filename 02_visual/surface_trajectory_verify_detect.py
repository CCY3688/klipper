#!/usr/bin/env python3
"""Detect platform tag positions in surface trajectory verification images."""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

import cv2
import numpy as np

VISUAL_DIR = Path(__file__).resolve().parent
ROOT = VISUAL_DIR.parent
if str(VISUAL_DIR) not in sys.path:
    sys.path.insert(0, str(VISUAL_DIR))

from stage0_machine_frame import (  # noqa: E402
    DEFAULT_BOARD_ORIGIN,
    DEFAULT_CHARUCO,
    DEFAULT_INTRINSICS,
    detect_platform_tag,
    load_intrinsics,
    load_json,
    load_t_camera_from_board,
    project_board_up_points,
    save_json,
)

MACHINE_TRANSFORM_CANDIDATES = [
    VISUAL_DIR / "stage4_coordinate_fit_latest.json",
    VISUAL_DIR / "T_machine_from_board_initial.json",
]
DEFAULT_MACHINE_TRANSFORM = next(
    (path for path in MACHINE_TRANSFORM_CANDIDATES if path.exists()),
    MACHINE_TRANSFORM_CANDIDATES[0],
)
DEFAULT_SURFACE_CORRECTION = VISUAL_DIR / "surface_trajectory_correction_latest.json"


def machine_from_board_up(
    point_board_up: np.ndarray,
    t_machine_from_board_up: np.ndarray,
) -> np.ndarray:
    point = np.array(
        [point_board_up[0], point_board_up[1], point_board_up[2], 1.0],
        dtype=np.float64,
    )
    return (t_machine_from_board_up @ point)[:3]


def board_up_from_machine(
    point_machine: np.ndarray,
    t_machine_from_board_up: np.ndarray,
) -> np.ndarray:
    point = np.array(
        [point_machine[0], point_machine[1], point_machine[2], 1.0],
        dtype=np.float64,
    )
    return (np.linalg.inv(t_machine_from_board_up) @ point)[:3]


def local_from_machine_xy(
    machine_x: float,
    machine_y: float,
    center_x: float,
    center_y: float,
    yaw_deg: float,
) -> tuple[float, float]:
    yaw = math.radians(yaw_deg)
    dx = machine_x - center_x
    dy = machine_y - center_y
    cos_yaw = math.cos(yaw)
    sin_yaw = math.sin(yaw)
    return (
        dx * cos_yaw + dy * sin_yaw,
        -dx * sin_yaw + dy * cos_yaw,
    )


def fit_machine_to_local_affine(captures: list[dict]) -> np.ndarray | None:
    rows: list[list[float]] = []
    values: list[list[float]] = []
    for capture in captures:
        if not isinstance(capture, dict):
            continue
        target = capture.get("target") if isinstance(capture.get("target"), dict) else {}
        local_x = float(target.get("local_x_mm", np.nan))
        local_y = float(target.get("local_y_mm", np.nan))
        machine_x = float(target.get("machine_x_mm", np.nan))
        machine_y = float(target.get("machine_y_mm", np.nan))
        if not np.isfinite([local_x, local_y, machine_x, machine_y]).all():
            continue
        rows.append([1.0, machine_x, machine_y])
        values.append([local_x, local_y])
    if len(rows) < 3:
        return None
    design = np.array(rows, dtype=np.float64)
    targets = np.array(values, dtype=np.float64)
    try:
        coeffs, *_ = np.linalg.lstsq(design, targets, rcond=None)
    except np.linalg.LinAlgError:
        return None
    if not np.isfinite(coeffs).all():
        return None
    return coeffs


def local_from_machine_xy_affine(
    machine_x: float,
    machine_y: float,
    coeffs: np.ndarray | None,
) -> tuple[float, float] | None:
    if coeffs is None:
        return None
    row = np.array([1.0, machine_x, machine_y], dtype=np.float64)
    local = row @ coeffs
    if not np.isfinite(local).all():
        return None
    return float(local[0]), float(local[1])


def annotate_detection(
    capture: dict,
    detection: dict,
    machine: np.ndarray,
    target_image_px: np.ndarray | None,
    args: argparse.Namespace,
    overlay_path: Path,
    machine_to_local_affine: np.ndarray | None,
) -> None:
    target = capture.get("target") if isinstance(capture.get("target"), dict) else {}
    local_source = "target_machine_xy_affine"
    local = local_from_machine_xy_affine(
        float(machine[0]),
        float(machine[1]),
        machine_to_local_affine,
    )
    if local is None:
        local_source = "surface_center_yaw_fallback"
        local_x, local_y = local_from_machine_xy(
            float(machine[0]),
            float(machine[1]),
            args.surface_center_x,
            args.surface_center_y,
            args.surface_yaw_deg,
        )
    else:
        local_x, local_y = local
    target_image_px_from_manifest = np.array(
        [
            float(target.get("image_x_px", np.nan)),
            float(target.get("image_y_px", np.nan)),
        ],
        dtype=np.float64,
    )
    target_machine = np.array(
        [
            float(target.get("machine_x_mm", np.nan)),
            float(target.get("machine_y_mm", np.nan)),
            float(target.get("machine_z_mm", np.nan)),
        ],
        dtype=np.float64,
    )
    error = machine - target_machine
    has_target = np.isfinite(target_machine).all()

    observed = {
        "source": "platform_tag_image_detection",
        "local_source": local_source,
        "tag_id": int(args.tag_id),
        "local_x_mm": float(local_x),
        "local_y_mm": float(local_y),
        "machine_x_mm": float(machine[0]),
        "machine_y_mm": float(machine[1]),
        "machine_z_mm": float(machine[2]),
        "board_x_mm": float(detection["center_board_up_mm"][0]),
        "board_y_mm": float(detection["center_board_up_mm"][1]),
        "board_z_mm": float(detection["center_board_up_mm"][2]),
        "image_center_x_px": float(detection["center_image_px"][0]),
        "image_center_y_px": float(detection["center_image_px"][1]),
        "image_points_px": detection["image_points_px"],
        "reprojection_mean_px": float(detection["mean_reprojection_error_px"]),
        "reprojection_max_px": float(detection["max_reprojection_error_px"]),
        "overlay_path": str(overlay_path),
    }
    if has_target:
        if np.isfinite(target_image_px_from_manifest).all():
            target["image_x_px"] = float(target_image_px_from_manifest[0])
            target["image_y_px"] = float(target_image_px_from_manifest[1])
        elif target_image_px is not None and np.isfinite(target_image_px).all():
            target["image_x_px"] = float(target_image_px[0])
            target["image_y_px"] = float(target_image_px[1])
        observed.update(
            {
                "error_x_mm": float(error[0]),
                "error_y_mm": float(error[1]),
                "error_z_mm": float(error[2]),
                "error_xy_mm": float(np.linalg.norm(error[:2])),
                "error_xyz_mm": float(np.linalg.norm(error)),
            }
        )

    capture["detect_ok"] = True
    capture["actual"] = observed
    capture["observed"] = observed
    capture["detected"] = observed


def detect_manifest(args: argparse.Namespace) -> dict:
    manifest_path = Path(args.manifest)
    manifest = load_json(manifest_path)
    captures = manifest.get("captures")
    if not isinstance(captures, list):
        raise RuntimeError(f"No captures list in manifest: {manifest_path}")

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
    machine_to_local_affine = fit_machine_to_local_affine(captures)

    overlay_dir = manifest_path.parent / "detected_overlays"
    overlay_dir.mkdir(parents=True, exist_ok=True)

    detected_count = 0
    failed_count = 0
    errors_xyz: list[np.ndarray] = []
    for index, capture in enumerate(captures, start=1):
        if not isinstance(capture, dict):
            continue
        image_path = Path(str(capture.get("image_path", "")))
        if not image_path.exists():
            capture["detect_ok"] = False
            capture["detect_error"] = f"image not found: {image_path}"
            failed_count += 1
            continue

        image = cv2.imread(str(image_path))
        if image is None:
            capture["detect_ok"] = False
            capture["detect_error"] = f"failed to read image: {image_path}"
            failed_count += 1
            continue

        detection = detect_platform_tag(
            image,
            camera_matrix,
            dist_coeffs,
            t_camera_from_board,
            args.tag_size,
            args.tag_id,
            args.dictionary,
        )
        overlay = detection.pop("overlay")
        overlay_path = overlay_dir / f"{image_path.stem}_detected.jpg"
        cv2.imwrite(str(overlay_path), overlay)

        if not detection.get("detect_ok"):
            capture["detect_ok"] = False
            capture["detect_error"] = detection.get("error", "detection failed")
            capture["detected_overlay_path"] = str(overlay_path)
            failed_count += 1
            continue

        board = np.array(detection["center_board_up_mm"], dtype=np.float64)
        machine = machine_from_board_up(board, t_machine_from_board_up)
        target_image_px = None
        target = capture.get("target") if isinstance(capture.get("target"), dict) else {}
        target_machine = np.array(
            [
                float(target.get("machine_x_mm", np.nan)),
                float(target.get("machine_y_mm", np.nan)),
                float(target.get("machine_z_mm", np.nan)),
            ],
            dtype=np.float64,
        )
        if np.isfinite(target_machine).all():
            target_board = board_up_from_machine(
                target_machine,
                t_machine_from_board_up,
            )
            projected = project_board_up_points(
                target_board.reshape(1, 3),
                camera_matrix,
                dist_coeffs,
                t_camera_from_board,
            )
            target_image_px = projected.reshape(-1, 2)[0]
        annotate_detection(
            capture,
            detection,
            machine,
            target_image_px,
            args,
            overlay_path,
            machine_to_local_affine,
        )
        error_xy = capture["actual"].get("error_xy_mm")
        if error_xy is not None:
            errors_xyz.append(
                np.array(
                    [
                        float(capture["actual"]["error_x_mm"]),
                        float(capture["actual"]["error_y_mm"]),
                        float(capture["actual"]["error_z_mm"]),
                    ],
                    dtype=np.float64,
                )
            )
        detected_count += 1
        print(
            f"[{index}/{len(captures)}] detected "
            f"machine=({machine[0]:.3f},{machine[1]:.3f},{machine[2]:.3f}) "
            f"local=({capture['actual']['local_x_mm']:.3f},{capture['actual']['local_y_mm']:.3f})"
        )

    manifest["detection"] = {
        "method": "platform_tag_image_detection",
        "detected_count": detected_count,
        "failed_count": failed_count,
        "tag_id": int(args.tag_id),
        "tag_size_mm": float(args.tag_size),
        "dictionary": args.dictionary,
        "intrinsics": str(Path(args.intrinsics)),
        "charuco_extrinsic": str(Path(args.charuco_extrinsic)),
        "machine_transform": str(Path(args.machine_transform)),
        "board_origin": args.board_origin,
        "surface_center_machine_mm": [
            float(args.surface_center_x),
            float(args.surface_center_y),
        ],
        "surface_yaw_deg": float(args.surface_yaw_deg),
        "created_at": time.time(),
    }
    if machine_to_local_affine is not None:
        manifest["detection"]["machine_xy_to_local_affine"] = [
            [float(v) for v in row] for row in machine_to_local_affine.tolist()
        ]
    if errors_xyz:
        errors = np.vstack(errors_xyz)
        xy = np.linalg.norm(errors[:, :2], axis=1)
        xyz = np.linalg.norm(errors, axis=1)
        mean_error = np.mean(errors, axis=0)
        corrected = errors - mean_error
        corrected_xy = np.linalg.norm(corrected[:, :2], axis=1)
        corrected_xyz = np.linalg.norm(corrected, axis=1)
        metrics = {
            "sample_count": int(len(errors_xyz)),
            "rms_xyz_error_mm": float(math.sqrt(np.mean(xyz**2))),
            "rms_xy_error_mm": float(math.sqrt(np.mean(xy**2))),
            "mean_abs_error_mm": [float(v) for v in np.mean(np.abs(errors), axis=0)],
            "max_abs_error_mm": [float(v) for v in np.max(np.abs(errors), axis=0)],
            "mean_error_mm": [float(v) for v in mean_error],
            "max_xy_error_mm": float(np.max(xy)),
            "mean_z_error_mm": float(np.mean(errors[:, 2])),
            "rms_z_error_mm": float(math.sqrt(np.mean(errors[:, 2] ** 2))),
        }
        offset_corrected_metrics = {
            "rms_xyz_error_mm": float(math.sqrt(np.mean(corrected_xyz**2))),
            "rms_xy_error_mm": float(math.sqrt(np.mean(corrected_xy**2))),
            "mean_abs_error_mm": [
                float(v) for v in np.mean(np.abs(corrected), axis=0)
            ],
            "max_abs_error_mm": [float(v) for v in np.max(np.abs(corrected), axis=0)],
            "mean_error_mm": [float(v) for v in np.mean(corrected, axis=0)],
            "max_xy_error_mm": float(np.max(corrected_xy)),
            "mean_z_error_mm": float(np.mean(corrected[:, 2])),
            "rms_z_error_mm": float(math.sqrt(np.mean(corrected[:, 2] ** 2))),
        }
        z_design_rows: list[list[float]] = []
        z_error_values: list[float] = []
        for capture in captures:
            if not isinstance(capture, dict):
                continue
            target = capture.get("target") if isinstance(capture.get("target"), dict) else {}
            actual = capture.get("actual") if isinstance(capture.get("actual"), dict) else {}
            machine_x = float(target.get("machine_x_mm", np.nan))
            machine_y = float(target.get("machine_y_mm", np.nan))
            machine_z = float(target.get("machine_z_mm", np.nan))
            error_z = float(actual.get("error_z_mm", np.nan))
            if not np.isfinite([machine_x, machine_y, machine_z, error_z]).all():
                continue
            z_design_rows.append([1.0, machine_x, machine_y, machine_z])
            z_error_values.append(error_z)
        z_error_model = None
        z_error_model_metrics = None
        z_error_samples = []
        if len(z_design_rows) >= 4:
            design = np.array(z_design_rows, dtype=np.float64)
            measured_z_error = np.array(z_error_values, dtype=np.float64)
            try:
                coeffs, *_ = np.linalg.lstsq(design, measured_z_error, rcond=None)
            except np.linalg.LinAlgError:
                coeffs = np.full(4, np.nan, dtype=np.float64)
            if np.isfinite(coeffs).all():
                predicted_z_error = design @ coeffs
                residual_z = measured_z_error - predicted_z_error
                z_error_model = {
                    "type": "linear_machine_xyz",
                    "features": [
                        "1",
                        "machine_x_mm",
                        "machine_y_mm",
                        "machine_z_mm",
                    ],
                    "coefficients": [float(v) for v in coeffs],
                    "command_precompensation": "machine_z_mm -= predicted_error_z_mm",
                }
                z_error_model_metrics = {
                    "sample_count": int(len(measured_z_error)),
                    "rms_z_error_before_mm": float(
                        math.sqrt(np.mean(measured_z_error**2))
                    ),
                    "rms_z_error_after_model_mm": float(
                        math.sqrt(np.mean(residual_z**2))
                    ),
                    "max_abs_z_error_after_model_mm": float(
                        np.max(np.abs(residual_z))
                    ),
                    "mean_z_error_after_model_mm": float(np.mean(residual_z)),
                }
        for capture in captures:
            if not isinstance(capture, dict):
                continue
            target = capture.get("target") if isinstance(capture.get("target"), dict) else {}
            actual = capture.get("actual") if isinstance(capture.get("actual"), dict) else {}
            machine_x = float(target.get("machine_x_mm", np.nan))
            machine_y = float(target.get("machine_y_mm", np.nan))
            machine_z = float(target.get("machine_z_mm", np.nan))
            local_x = float(target.get("local_x_mm", np.nan))
            local_y = float(target.get("local_y_mm", np.nan))
            surface_height = float(target.get("surface_height_mm", np.nan))
            error_z = float(actual.get("error_z_mm", np.nan))
            if not np.isfinite(
                [machine_x, machine_y, machine_z, local_x, local_y, surface_height, error_z]
            ).all():
                continue
            z_error_samples.append(
                {
                    "machine_x_mm": machine_x,
                    "machine_y_mm": machine_y,
                    "machine_z_mm": machine_z,
                    "local_x_mm": local_x,
                    "local_y_mm": local_y,
                    "surface_height_mm": surface_height,
                    "error_z_mm": error_z,
                }
            )
        manifest["detection"].update(
            {
                "mean_error_xy_mm": float(np.mean(xy)),
                "max_error_xy_mm": float(np.max(xy)),
                "metrics": metrics,
                "offset_corrected_metrics": offset_corrected_metrics,
            }
        )
        if z_error_model is not None and z_error_model_metrics is not None:
            manifest["detection"]["z_error_model"] = z_error_model
            manifest["detection"]["z_error_model_metrics"] = z_error_model_metrics
        if z_error_samples:
            manifest["detection"]["z_error_samples"] = z_error_samples
        correction = {
            "method": "surface_trajectory_local_mean_error_precompensation",
            "scope": "local_trajectory_and_setup",
            "source_manifest": str(manifest_path),
            "created_at": time.time(),
            "sample_count": int(len(errors_xyz)),
            "mean_error_mm": [float(v) for v in mean_error],
            "command_precompensation_mm": [float(-v) for v in mean_error],
            "raw_metrics": metrics,
            "expected_after_offset_correction": offset_corrected_metrics,
            "z_error_model": z_error_model,
            "z_error_samples": z_error_samples,
            "expected_after_z_error_model": z_error_model_metrics,
            "note": (
                "Apply command_precompensation_mm to machine commands only; "
                "keep verification targets unchanged. If z_error_model is present, "
                "predict error_z from the uncorrected machine command and subtract "
                "that predicted error from the commanded Z. These corrections are "
                "local residual precompensations for the same surface setup and "
                "trajectory family, not replacements for the global coordinate "
                "calibration."
            ),
        }
        save_json(Path(args.surface_correction_output), correction)
        manifest["detection"]["surface_correction_output"] = str(
            Path(args.surface_correction_output)
        )

    manifest["status"] = "ready" if detected_count else "warn"
    manifest["summary"] = (
        f"Detected platform tag in {detected_count}/{len(captures)} verification images."
    )
    manifest["note"] = (
        "actual/observed/detected coordinates are measured from platform tag "
        "image detection after all verification moves finished."
    )
    save_json(manifest_path, manifest)
    return manifest


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Detect platform tag positions in a surface verification manifest.",
    )
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--intrinsics", default=str(DEFAULT_INTRINSICS))
    parser.add_argument("--charuco-extrinsic", default=str(DEFAULT_CHARUCO))
    parser.add_argument("--machine-transform", default=str(DEFAULT_MACHINE_TRANSFORM))
    parser.add_argument("--board-origin", choices=("center", "corner"), default=DEFAULT_BOARD_ORIGIN)
    parser.add_argument("--tag-id", type=int, default=0)
    parser.add_argument("--tag-size", type=float, default=20.0)
    parser.add_argument("--dictionary", default="DICT_APRILTAG_36h11")
    parser.add_argument("--surface-center-x", type=float, required=True)
    parser.add_argument("--surface-center-y", type=float, required=True)
    parser.add_argument("--surface-yaw-deg", type=float, required=True)
    parser.add_argument(
        "--surface-correction-output",
        default=str(DEFAULT_SURFACE_CORRECTION),
    )
    return parser


def main() -> None:
    args = build_parser().parse_args()
    manifest = detect_manifest(args)
    detection = manifest.get("detection", {})
    print(
        "Surface verification detection complete: "
        f"{detection.get('detected_count', 0)} detected, "
        f"{detection.get('failed_count', 0)} failed"
    )


if __name__ == "__main__":
    main()
