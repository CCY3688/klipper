#!/usr/bin/env python3
"""Stage 4 coordinate-frame and equivalent TCP-offset fitting."""

from __future__ import annotations

import argparse
import csv
import json
import math
import time
from pathlib import Path

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
VISUAL_DIR = ROOT / "02_visual"
DEFAULT_SAMPLES = VISUAL_DIR / "stage2_error_grid" / "stage2_error_grid_samples.csv"
DEFAULT_INITIAL_TRANSFORM = VISUAL_DIR / "T_machine_from_board_initial.json"
DEFAULT_OUT_DIR = VISUAL_DIR / "stage4_coordinate_fit"
DEFAULT_RESULT = DEFAULT_OUT_DIR / "stage4_coordinate_fit_result.json"
DEFAULT_LATEST_RESULT = VISUAL_DIR / "stage4_coordinate_fit_latest.json"


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
        f.write("\n")


def row_float(row: dict, key: str) -> float:
    value = row.get(key, "")
    if value == "" or value is None:
        return float("nan")
    return float(value)


def truthy(value: object) -> bool:
    return str(value).lower() in ("true", "1", "yes")


def read_valid_samples(path: Path) -> list[dict]:
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    required = (
        "cmd_x",
        "cmd_y",
        "cmd_z",
        "tag_x_board_up",
        "tag_y_board_up",
        "tag_z_board_up",
        "measured_x_machine",
        "measured_y_machine",
        "measured_z_machine",
    )
    valid = []
    for row in rows:
        if not truthy(row.get("detect_ok", "")):
            continue
        values = [row_float(row, key) for key in required]
        if all(math.isfinite(value) for value in values):
            valid.append(row)
    return valid


def fit_xy_affine(
    source_xy: np.ndarray,
    target_xy: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    design = np.column_stack([source_xy, np.ones(len(source_xy))])
    coef_x, *_ = np.linalg.lstsq(design, target_xy[:, 0], rcond=None)
    coef_y, *_ = np.linalg.lstsq(design, target_xy[:, 1], rcond=None)
    matrix = np.array(
        [[coef_x[0], coef_x[1]], [coef_y[0], coef_y[1]]],
        dtype=np.float64,
    )
    offset = np.array([coef_x[2], coef_y[2]], dtype=np.float64)
    return matrix, offset


def fit_xy_rigid(
    source_xy: np.ndarray,
    target_xy: np.ndarray,
    determinant: int | None,
) -> tuple[np.ndarray, np.ndarray]:
    source_center = np.mean(source_xy, axis=0)
    target_center = np.mean(target_xy, axis=0)
    source_c = source_xy - source_center
    target_c = target_xy - target_center

    def solve(det_sign: int) -> tuple[np.ndarray, np.ndarray, float]:
        h = source_c.T @ target_c
        u, _, vt = np.linalg.svd(h)
        handedness = float(det_sign) * np.linalg.det(vt.T @ u.T)
        candidate = vt.T @ np.diag([1.0, handedness]) @ u.T
        offset = target_center - candidate @ source_center
        residual = (source_xy @ candidate.T + offset) - target_xy
        rmse = float(math.sqrt(np.mean(np.sum(residual**2, axis=1))))
        return candidate, offset, rmse

    candidates = [solve(-1), solve(1)] if determinant is None else [solve(determinant)]
    matrix, offset, _ = min(candidates, key=lambda item: item[2])
    return matrix, offset


def fit_z(
    source_xyz: np.ndarray,
    target_z: np.ndarray,
    mode: str,
) -> tuple[np.ndarray, float]:
    if mode == "none":
        return np.array([0.0, 0.0, 1.0], dtype=np.float64), 0.0
    if mode == "plane":
        design = np.column_stack([source_xyz, np.ones(len(source_xyz))])
        coef, *_ = np.linalg.lstsq(design, target_z, rcond=None)
        return coef[:3], float(coef[3])
    return np.array([0.0, 0.0, 1.0], dtype=np.float64), float(
        np.mean(target_z - source_xyz[:, 2])
    )


def yaw_from_xy_matrix(matrix: np.ndarray) -> float:
    if float(np.linalg.det(matrix)) < 0:
        return math.degrees(math.atan2(matrix[0, 1], matrix[0, 0]))
    return math.degrees(math.atan2(matrix[1, 0], matrix[0, 0]))


def transform_from_parts(
    xy_matrix: np.ndarray,
    xy_offset: np.ndarray,
    z_coef: np.ndarray,
    z_offset: float,
) -> np.ndarray:
    transform = np.eye(4, dtype=np.float64)
    transform[0, 0:2] = xy_matrix[0]
    transform[1, 0:2] = xy_matrix[1]
    transform[0, 3] = xy_offset[0]
    transform[1, 3] = xy_offset[1]
    transform[2, 0:3] = z_coef
    transform[2, 3] = z_offset
    return transform


def predict(source_xyz: np.ndarray, transform: np.ndarray) -> np.ndarray:
    homogeneous = np.column_stack([source_xyz, np.ones(len(source_xyz))])
    return (homogeneous @ transform.T)[:, :3]


def residual_stats(residual: np.ndarray) -> dict:
    xy = np.linalg.norm(residual[:, :2], axis=1)
    norm = np.linalg.norm(residual, axis=1)
    return {
        "rms_xyz_error_mm": float(math.sqrt(np.mean(norm**2))),
        "rms_xy_error_mm": float(math.sqrt(np.mean(xy**2))),
        "max_xy_error_mm": float(np.max(xy)),
        "mean_abs_error_mm": np.mean(np.abs(residual), axis=0).tolist(),
        "max_abs_error_mm": np.max(np.abs(residual), axis=0).tolist(),
        "mean_error_mm": np.mean(residual, axis=0).tolist(),
    }


def fit_bounds(
    points: np.ndarray,
    margin: float = 18.0,
) -> tuple[float, float, float, float]:
    min_xy = np.min(points, axis=0) - margin
    max_xy = np.max(points, axis=0) + margin
    span = np.maximum(max_xy - min_xy, 1.0)
    if span[0] > span[1]:
        pad = (span[0] - span[1]) * 0.5
        min_xy[1] -= pad
        max_xy[1] += pad
    else:
        pad = (span[1] - span[0]) * 0.5
        min_xy[0] -= pad
        max_xy[0] += pad
    return float(min_xy[0]), float(max_xy[0]), float(min_xy[1]), float(max_xy[1])


def project_xy(
    point: np.ndarray,
    bounds: tuple[float, float, float, float],
    width: int,
    height: int,
) -> tuple[int, int]:
    min_x, max_x, min_y, max_y = bounds
    scale = min((width - 76) / (max_x - min_x), (height - 104) / (max_y - min_y))
    x = 38 + (point[0] - min_x) * scale
    y = height - 42 - (point[1] - min_y) * scale
    return int(round(x)), int(round(y))


def draw_summary(
    rows: list[dict],
    target_xyz: np.ndarray,
    initial_xyz: np.ndarray,
    fitted_xyz: np.ndarray,
    output: Path,
) -> None:
    z_values = sorted({row_float(row, "cmd_z") for row in rows})
    columns = min(2, len(z_values))
    rows_n = int(math.ceil(len(z_values) / columns))
    tile_w = 680
    tile_h = 540
    canvas = np.full((rows_n * tile_h, columns * tile_w, 3), 244, dtype=np.uint8)
    bounds = fit_bounds(
        np.vstack([target_xyz[:, :2], initial_xyz[:, :2], fitted_xyz[:, :2]])
    )

    for layer_index, z_value in enumerate(z_values):
        tile_y, tile_x = divmod(layer_index, columns)
        x0 = tile_x * tile_w
        y0 = tile_y * tile_h
        tile = canvas[y0 : y0 + tile_h, x0 : x0 + tile_w]
        cv2.rectangle(tile, (12, 12), (tile_w - 12, tile_h - 12), (255, 255, 255), -1)
        cv2.rectangle(tile, (12, 12), (tile_w - 12, tile_h - 12), (210, 210, 210), 1)

        min_x, max_x, min_y, max_y = bounds
        step = 20.0
        gx = math.floor(min_x / step) * step
        while gx <= max_x:
            cv2.line(
                tile,
                project_xy(np.array([gx, min_y]), bounds, tile_w, tile_h),
                project_xy(np.array([gx, max_y]), bounds, tile_w, tile_h),
                (228, 228, 228),
                1,
            )
            gx += step
        gy = math.floor(min_y / step) * step
        while gy <= max_y:
            cv2.line(
                tile,
                project_xy(np.array([min_x, gy]), bounds, tile_w, tile_h),
                project_xy(np.array([max_x, gy]), bounds, tile_w, tile_h),
                (228, 228, 228),
                1,
            )
            gy += step

        indices = [
            i
            for i, row in enumerate(rows)
            if abs(row_float(row, "cmd_z") - z_value) < 1e-6
        ]
        for i in indices:
            target = target_xyz[i, :2]
            initial = initial_xyz[i, :2]
            fitted = fitted_xyz[i, :2]
            p_target = project_xy(target, bounds, tile_w, tile_h)
            p_initial = project_xy(initial, bounds, tile_w, tile_h)
            p_fitted = project_xy(fitted, bounds, tile_w, tile_h)
            cv2.circle(tile, p_target, 7, (30, 30, 30), 2, cv2.LINE_AA)
            cv2.line(tile, p_initial, p_target, (40, 40, 220), 2, cv2.LINE_AA)
            cv2.circle(tile, p_initial, 4, (40, 40, 220), -1, cv2.LINE_AA)
            cv2.line(tile, p_fitted, p_target, (220, 120, 30), 2, cv2.LINE_AA)
            cv2.circle(tile, p_fitted, 4, (220, 120, 30), -1, cv2.LINE_AA)

        initial_res = initial_xyz[indices, :2] - target_xyz[indices, :2]
        fitted_res = fitted_xyz[indices, :2] - target_xyz[indices, :2]
        initial_rms = math.sqrt(np.mean(np.sum(initial_res**2, axis=1)))
        fitted_rms = math.sqrt(np.mean(np.sum(fitted_res**2, axis=1)))
        cv2.putText(
            tile,
            f"Stage 4 coordinate fit   Z={z_value:.2f} mm",
            (28, 44),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.68,
            (25, 25, 25),
            2,
            cv2.LINE_AA,
        )
        cv2.putText(
            tile,
            f"RMS XY before={initial_rms:.3f} mm   after={fitted_rms:.3f} mm   samples={len(indices)}",
            (28, 72),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (25, 25, 25),
            1,
            cv2.LINE_AA,
        )
        cv2.putText(
            tile,
            "ring=commanded, red=initial residual, blue=fitted residual",
            (28, tile_h - 24),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.48,
            (70, 70, 70),
            1,
            cv2.LINE_AA,
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output), canvas)


def fit_coordinate_frame(args: argparse.Namespace) -> dict:
    samples_path = Path(args.samples)
    initial_path = Path(args.initial_transform)
    output_path = Path(args.output)
    rows = read_valid_samples(samples_path)
    if len(rows) < 4:
        raise RuntimeError(f"Need at least 4 valid samples, got {len(rows)}")

    source_xyz = np.array(
        [
            [
                row_float(row, "tag_x_board_up"),
                row_float(row, "tag_y_board_up"),
                row_float(row, "tag_z_board_up"),
            ]
            for row in rows
        ],
        dtype=np.float64,
    )
    target_xyz = np.array(
        [[row_float(row, "cmd_x"), row_float(row, "cmd_y"), row_float(row, "cmd_z")] for row in rows],
        dtype=np.float64,
    )
    initial_xyz = np.array(
        [
            [
                row_float(row, "measured_x_machine"),
                row_float(row, "measured_y_machine"),
                row_float(row, "measured_z_machine"),
            ]
            for row in rows
        ],
        dtype=np.float64,
    )

    initial_payload = load_json(initial_path)
    initial_transform = np.array(initial_payload["T_machine_from_board_up"], dtype=np.float64)
    det_hint = int(math.copysign(1.0, np.linalg.det(initial_transform[:2, :2])))
    requested_det = None if args.xy_handedness == "auto" else (-1 if args.xy_handedness == "mirrored" else 1)
    determinant = det_hint if args.xy_handedness == "initial" else requested_det

    if args.xy_model == "affine":
        xy_matrix, xy_offset = fit_xy_affine(source_xyz[:, :2], target_xyz[:, :2])
    else:
        xy_matrix, xy_offset = fit_xy_rigid(source_xyz[:, :2], target_xyz[:, :2], determinant)
    z_coef, z_offset = fit_z(source_xyz, target_xyz[:, 2], args.z_model)
    fitted_transform = transform_from_parts(xy_matrix, xy_offset, z_coef, z_offset)
    fitted_xyz = predict(source_xyz, fitted_transform)
    initial_residual = initial_xyz - target_xyz
    fitted_residual = fitted_xyz - target_xyz
    correction_transform = fitted_transform @ np.linalg.inv(initial_transform)
    equivalent_offset = fitted_transform[:3, 3] - initial_transform[:3, 3]
    initial_stats = residual_stats(initial_residual)
    fitted_stats = residual_stats(fitted_residual)

    residual_rows = []
    for row, initial_res, fitted_res, fitted in zip(
        rows,
        initial_residual,
        fitted_residual,
        fitted_xyz,
    ):
        residual_rows.append(
            {
                "sample_id": row.get("sample_id", ""),
                "name": row.get("name", ""),
                "repeat": row.get("repeat", ""),
                "cmd_machine_mm": [
                    row_float(row, "cmd_x"),
                    row_float(row, "cmd_y"),
                    row_float(row, "cmd_z"),
                ],
                "fitted_machine_mm": fitted.tolist(),
                "initial_residual_mm": initial_res.tolist(),
                "fitted_residual_mm": fitted_res.tolist(),
                "residual_mm": fitted_res.tolist(),
                "residual_norm_mm": float(np.linalg.norm(fitted_res)),
                "initial_residual_xy_mm": float(np.linalg.norm(initial_res[:2])),
                "fitted_residual_xy_mm": float(np.linalg.norm(fitted_res[:2])),
            }
        )

    summary_image = output_path.with_name("stage4_coordinate_fit_summary.png")
    draw_summary(rows, target_xyz, initial_xyz, fitted_xyz, summary_image)
    result = {
        "method": "stage4_coordinate_fit",
        "note": "Fits board AprilTag center to commanded TCP. Equivalent offset mixes frame translation and tag-to-TCP offset unless tag orientation is recorded.",
        "samples_csv": str(samples_path),
        "initial_transform": str(initial_path),
        "sample_count": len(rows),
        "valid_sample_count": len(rows),
        "xy_model": args.xy_model,
        "xy_handedness": "mirrored" if np.linalg.det(xy_matrix) < 0 else "normal",
        "xy_determinant": float(np.linalg.det(xy_matrix)),
        "z_model": args.z_model,
        "yaw_deg": float(yaw_from_xy_matrix(xy_matrix)),
        "T_machine_from_board_up": fitted_transform.tolist(),
        "T_machine_from_board_tcp": fitted_transform.tolist(),
        "T_stage4_correction_from_initial_machine": correction_transform.tolist(),
        "equivalent_tcp_offset_from_initial_mm": equivalent_offset.tolist(),
        "initial_stats": initial_stats,
        "fitted_stats": fitted_stats,
        "improvement": {
            "rms_xy_reduction_mm": float(
                initial_stats["rms_xy_error_mm"] - fitted_stats["rms_xy_error_mm"]
            ),
            "rms_xy_reduction_percent": float(
                100.0
                * (
                    1.0
                    - fitted_stats["rms_xy_error_mm"]
                    / max(initial_stats["rms_xy_error_mm"], 1e-12)
                )
            ),
        },
        "summary_image": str(summary_image),
        "residuals": residual_rows,
        "created_at": time.time(),
    }
    save_json(output_path, result)
    save_json(DEFAULT_LATEST_RESULT, result)
    print("Stage 4 coordinate fit:")
    print(f"  samples        = {len(rows)}")
    print(f"  initial RMS XY = {initial_stats['rms_xy_error_mm']:.6f} mm")
    print(f"  fitted RMS XY  = {fitted_stats['rms_xy_error_mm']:.6f} mm")
    print(f"  reduction      = {result['improvement']['rms_xy_reduction_percent']:.2f}%")
    print(f"Result written: {output_path}")
    print(f"Summary image written: {summary_image}")
    print(f"Latest copy written: {DEFAULT_LATEST_RESULT}")
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fit Stage 4 coordinate frame and equivalent TCP offset from Stage 2 samples."
    )
    parser.add_argument("--samples", default=str(DEFAULT_SAMPLES))
    parser.add_argument("--initial-transform", default=str(DEFAULT_INITIAL_TRANSFORM))
    parser.add_argument("--output", default=str(DEFAULT_RESULT))
    parser.add_argument("--xy-model", choices=("rigid", "affine"), default="rigid")
    parser.add_argument(
        "--xy-handedness",
        choices=("initial", "auto", "mirrored", "normal"),
        default="initial",
    )
    parser.add_argument("--z-model", choices=("offset", "plane", "none"), default="offset")
    return parser


def main() -> None:
    args = build_parser().parse_args()
    fit_coordinate_frame(args)


if __name__ == "__main__":
    main()
