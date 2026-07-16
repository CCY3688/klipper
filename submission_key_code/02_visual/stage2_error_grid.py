#!/usr/bin/env python3
"""Stage 2 visual error-grid collection for mechanism calibration.

This stage samples a rectangular XY grid at one or more commanded Z heights.
Each sample records:
  - commanded machine XYZ,
  - visually measured AprilTag center in the ChArUco/board frame,
  - the same visual point transformed into the initial machine frame,
  - EMM driver angles and gear-ratio converted arm angles.

The visual Z value is preserved for inspection, but summary statistics focus on
XY because the current camera setup has larger Z variance.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
import time
import urllib.error
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
VISUAL_DIR = ROOT / "02_visual"
if str(VISUAL_DIR) not in sys.path:
    sys.path.insert(0, str(VISUAL_DIR))

from stage0_machine_frame import (  # noqa: E402
    DEFAULT_BOARD_ORIGIN,
    DEFAULT_CHARUCO,
    DEFAULT_INTRINSICS,
    detect_platform_tag,
    ensure_motion_ready,
    load_intrinsics,
    load_json,
    load_t_camera_from_board,
    read_emm_positions,
    read_emm_statuses,
    run_gcode,
    save_json,
    snapshot_image,
    wait_emm_reached,
)


DEFAULT_STAGE0_TRANSFORM = VISUAL_DIR / "T_machine_from_board_initial.json"
DEFAULT_OUT_DIR = VISUAL_DIR / "stage2_error_grid"
DEFAULT_LATEST_RESULT = VISUAL_DIR / "stage2_error_grid_latest.json"


@dataclass(frozen=True)
class GridPoint:
    name: str
    ix: int
    iy: int
    layer: int
    x: float
    y: float
    z: float


def parse_z_levels(text: str) -> list[float]:
    values = []
    for part in text.replace(";", ",").split(","):
        token = part.strip()
        if not token:
            continue
        values.append(float(token))
    if not values:
        raise ValueError("At least one Z level is required")
    return values


def parse_gear_ratio(text: str) -> tuple[float, float]:
    normalized = text.strip().replace("/", ":")
    if ":" not in normalized:
        value = float(normalized)
        if value == 0:
            raise ValueError("gear ratio cannot be zero")
        return value, 1.0
    left, right = normalized.split(":", 1)
    numerator = float(left.strip())
    denominator = float(right.strip())
    if numerator == 0 or denominator == 0:
        raise ValueError("gear ratio values cannot be zero")
    return numerator, denominator


def gear_reduction(numerator: float, denominator: float) -> float:
    return numerator / denominator


def motor_to_arm_angle(driver_angle_deg: float, numerator: float, denominator: float) -> float:
    return driver_angle_deg / gear_reduction(numerator, denominator)


def grid_axis(min_v: float, max_v: float, count: int) -> list[float]:
    if count <= 0:
        raise ValueError("grid counts must be positive")
    if count == 1:
        return [(min_v + max_v) * 0.5]
    return np.linspace(min_v, max_v, count).astype(float).tolist()


def grid_points(args: argparse.Namespace) -> list[GridPoint]:
    xs = grid_axis(args.x_min, args.x_max, args.x_count)
    ys = grid_axis(args.y_min, args.y_max, args.y_count)
    zs = parse_z_levels(args.z_levels)
    points: list[GridPoint] = []
    for layer, z in enumerate(zs):
        for iy, y in enumerate(ys):
            row_xs = xs if iy % 2 == 0 else list(reversed(xs))
            for local_ix, x in enumerate(row_xs):
                ix = local_ix if iy % 2 == 0 else len(xs) - 1 - local_ix
                points.append(
                    GridPoint(
                        name=f"z{layer}_x{ix}_y{iy}",
                        ix=ix,
                        iy=iy,
                        layer=layer,
                        x=float(x),
                        y=float(y),
                        z=float(z),
                    )
                )
    return points


def machine_from_board_up(point_board_up: np.ndarray, t_machine_from_board_up: np.ndarray) -> np.ndarray:
    point = np.array(
        [point_board_up[0], point_board_up[1], point_board_up[2], 1.0],
        dtype=np.float64,
    )
    return (t_machine_from_board_up @ point)[:3]


def rows_to_csv(path: Path, rows: list[dict]) -> None:
    fieldnames = [
        "sample_id",
        "name",
        "repeat",
        "layer",
        "grid_ix",
        "grid_iy",
        "timestamp",
        "board_origin",
        "cmd_x",
        "cmd_y",
        "cmd_z",
        "detect_ok",
        "tag_x_board_up",
        "tag_y_board_up",
        "tag_z_board_up",
        "measured_x_machine",
        "measured_y_machine",
        "measured_z_machine",
        "error_x_mm",
        "error_y_mm",
        "error_z_mm",
        "error_xy_mm",
        "reprojection_mean_px",
        "reprojection_max_px",
        "gear_ratio",
        "gear_reduction",
        "emm_wait_reached",
        "emm_wait_s",
        "settle_s",
        "captured_at",
        "emm_id1_deg",
        "emm_id2_deg",
        "emm_id3_deg",
        "arm_id1_deg",
        "arm_id2_deg",
        "arm_id3_deg",
        "emm_id1_reached",
        "emm_id2_reached",
        "emm_id3_reached",
        "emm_status_json",
        "image",
        "overlay",
        "error",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def read_rows(path: Path) -> list[dict]:
    with path.open("r", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def row_float(row: dict, key: str, default: float = 0.0) -> float:
    try:
        value = row.get(key, "")
        if value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def truthy(value: object) -> bool:
    return str(value).lower() in ("true", "1", "yes")


def summarize_rows(rows: list[dict]) -> dict:
    valid = [row for row in rows if truthy(row.get("detect_ok", ""))]
    all_layers = sorted({row_float(row, "cmd_z") for row in rows})
    if not valid:
        return {
            "method": "stage2_error_grid_summary",
            "valid_sample_count": 0,
            "sample_count": len(rows),
            "z_levels_mm": all_layers,
            "created_at": time.time(),
        }

    errors = np.array(
        [[row_float(row, "error_x_mm"), row_float(row, "error_y_mm"), row_float(row, "error_z_mm")] for row in valid],
        dtype=np.float64,
    )
    error_xy = np.linalg.norm(errors[:, :2], axis=1)
    layer_stats = []
    for z in sorted({row_float(row, "cmd_z") for row in valid}):
        layer_rows = [row for row in valid if abs(row_float(row, "cmd_z") - z) < 1e-6]
        layer_errors = np.array(
            [[row_float(row, "error_x_mm"), row_float(row, "error_y_mm"), row_float(row, "error_z_mm")] for row in layer_rows],
            dtype=np.float64,
        )
        layer_xy = np.linalg.norm(layer_errors[:, :2], axis=1)
        layer_stats.append(
            {
                "z_mm": float(z),
                "valid_sample_count": len(layer_rows),
                "rms_xy_error_mm": float(math.sqrt(np.mean(layer_xy**2))),
                "mean_abs_xy_error_mm": np.mean(np.abs(layer_errors[:, :2]), axis=0).tolist(),
                "max_xy_error_mm": float(np.max(layer_xy)),
                "mean_z_error_mm": float(np.mean(layer_errors[:, 2])),
            }
        )

    return {
        "method": "stage2_error_grid_summary",
        "sample_count": len(rows),
        "valid_sample_count": len(valid),
        "z_levels_mm": all_layers,
        "rms_xy_error_mm": float(math.sqrt(np.mean(error_xy**2))),
        "mean_abs_error_mm": np.mean(np.abs(errors), axis=0).tolist(),
        "max_abs_error_mm": np.max(np.abs(errors), axis=0).tolist(),
        "max_xy_error_mm": float(np.max(error_xy)),
        "mean_z_error_mm": float(np.mean(errors[:, 2])),
        "layer_stats": layer_stats,
        "created_at": time.time(),
    }


def fit_bounds(points: np.ndarray, margin: float = 15.0) -> tuple[float, float, float, float]:
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


def project_xy(point: np.ndarray, bounds: tuple[float, float, float, float], w: int, h: int) -> tuple[int, int]:
    min_x, max_x, min_y, max_y = bounds
    scale_x = (w - 70) / (max_x - min_x)
    scale_y = (h - 95) / (max_y - min_y)
    scale = min(scale_x, scale_y)
    x = 38 + (point[0] - min_x) * scale
    y = h - 42 - (point[1] - min_y) * scale
    return int(round(x)), int(round(y))


def draw_summary(rows: list[dict], result: dict, output_path: Path) -> None:
    valid = [row for row in rows if truthy(row.get("detect_ok", ""))]
    if not valid:
        return

    z_values = sorted({row_float(row, "cmd_z") for row in valid})
    columns = min(2, len(z_values))
    rows_n = int(math.ceil(len(z_values) / columns))
    tile_w = 640
    tile_h = 520
    canvas = np.full((rows_n * tile_h, columns * tile_w, 3), 244, dtype=np.uint8)

    target_xy = np.array([[row_float(row, "cmd_x"), row_float(row, "cmd_y")] for row in valid], dtype=np.float64)
    measured_xy = np.array(
        [[row_float(row, "measured_x_machine"), row_float(row, "measured_y_machine")] for row in valid],
        dtype=np.float64,
    )
    bounds = fit_bounds(np.vstack([target_xy, measured_xy]), margin=22.0)

    for layer_index, z in enumerate(z_values):
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
            cv2.line(tile, project_xy(np.array([gx, min_y]), bounds, tile_w, tile_h), project_xy(np.array([gx, max_y]), bounds, tile_w, tile_h), (228, 228, 228), 1)
            gx += step
        gy = math.floor(min_y / step) * step
        while gy <= max_y:
            cv2.line(tile, project_xy(np.array([min_x, gy]), bounds, tile_w, tile_h), project_xy(np.array([max_x, gy]), bounds, tile_w, tile_h), (228, 228, 228), 1)
            gy += step

        layer_rows = [row for row in valid if abs(row_float(row, "cmd_z") - z) < 1e-6]
        for row in layer_rows:
            target = np.array([row_float(row, "cmd_x"), row_float(row, "cmd_y")], dtype=np.float64)
            measured = np.array([row_float(row, "measured_x_machine"), row_float(row, "measured_y_machine")], dtype=np.float64)
            p_target = project_xy(target, bounds, tile_w, tile_h)
            p_measured = project_xy(measured, bounds, tile_w, tile_h)
            cv2.circle(tile, p_target, 8, (25, 25, 25), 2, cv2.LINE_AA)
            cv2.circle(tile, p_measured, 5, (235, 120, 35), -1, cv2.LINE_AA)
            cv2.line(tile, p_measured, p_target, (40, 40, 220), 2, cv2.LINE_AA)
            cv2.putText(tile, f"{int(row_float(row, 'grid_ix'))},{int(row_float(row, 'grid_iy'))}", (p_target[0] + 9, p_target[1] - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (35, 35, 35), 1, cv2.LINE_AA)

        cv2.putText(tile, f"Stage 2 XY error grid   Z={z:.2f} mm", (28, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.68, (25, 25, 25), 2, cv2.LINE_AA)
        layer_stat = next((item for item in result.get("layer_stats", []) if abs(float(item["z_mm"]) - z) < 1e-6), {})
        cv2.putText(
            tile,
            f"RMS XY={float(layer_stat.get('rms_xy_error_mm', 0.0)):.3f} mm   samples={len(layer_rows)}",
            (28, 72),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            (25, 25, 25),
            1,
            cv2.LINE_AA,
        )
        cv2.putText(tile, "ring=commanded XY, orange=vision XY, red=XY residual", (28, tile_h - 24), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (70, 70, 70), 1, cv2.LINE_AA)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), canvas)


def draw_contact_sheet(rows: list[dict], output_path: Path, thumb_width: int = 360, columns: int = 3) -> None:
    items = []
    for row in rows:
        image_path = Path(row.get("image", ""))
        if not image_path.exists():
            continue
        image = cv2.imread(str(image_path))
        if image is None:
            continue
        h, w = image.shape[:2]
        scale = thumb_width / float(w)
        thumb = cv2.resize(image, (thumb_width, max(1, int(round(h * scale)))), interpolation=cv2.INTER_AREA)
        items.append((row, thumb))
    if not items:
        return

    columns = max(1, min(columns, len(items)))
    header_h = 72
    gap = 12
    tile_h = max(thumb.shape[0] for _, thumb in items) + header_h
    rows_n = int(math.ceil(len(items) / columns))
    canvas = np.full((rows_n * tile_h + (rows_n + 1) * gap, columns * thumb_width + (columns + 1) * gap, 3), 242, dtype=np.uint8)
    for index, (row, thumb) in enumerate(items):
        gy, gx = divmod(index, columns)
        x0 = gap + gx * (thumb_width + gap)
        y0 = gap + gy * (tile_h + gap)
        cv2.rectangle(canvas, (x0, y0), (x0 + thumb_width, y0 + tile_h), (255, 255, 255), -1)
        cv2.rectangle(canvas, (x0, y0), (x0 + thumb_width, y0 + tile_h), (205, 205, 205), 1)
        lines = [
            f"{row.get('sample_id', '')} {row.get('name', '')} detect={row.get('detect_ok', '')}",
            f"cmd=({row_float(row, 'cmd_x'):.1f},{row_float(row, 'cmd_y'):.1f},{row_float(row, 'cmd_z'):.1f})  eXY={row_float(row, 'error_xy_mm'):.2f}",
        ]
        for i, line in enumerate(lines):
            cv2.putText(canvas, line, (x0 + 10, y0 + 26 + i * 24), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (25, 25, 25), 1, cv2.LINE_AA)
        image_y = y0 + header_h
        canvas[image_y : image_y + thumb.shape[0], x0 : x0 + thumb.shape[1]] = thumb

    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), canvas)


def summarize_from_csv(
    samples_path: Path,
    output_path: Path,
    latest_output_path: Path = DEFAULT_LATEST_RESULT,
) -> dict:
    rows = read_rows(samples_path)
    result = summarize_rows(rows)
    summary_path = output_path.with_name("stage2_error_grid_summary.png")
    contact_sheet_path = output_path.with_name("stage2_error_grid_contact_sheet.jpg")
    result["samples_csv"] = str(samples_path)
    result["summary_image"] = str(summary_path)
    result["capture_contact_sheet"] = str(contact_sheet_path)
    draw_summary(rows, result, summary_path)
    try:
        draw_contact_sheet(rows, contact_sheet_path)
    except Exception as exc:
        print(f"Warning: failed to draw contact sheet: {exc}")
    save_json(output_path, result)
    save_json(latest_output_path, result)
    print("Stage 2 error-grid summary:")
    print(f"  samples = {result['sample_count']}")
    print(f"  valid   = {result['valid_sample_count']}")
    print(f"  RMS XY  = {float(result.get('rms_xy_error_mm', 0.0)):.6f} mm")
    print(f"Result written: {output_path}")
    print(f"Summary image written: {summary_path}")
    print(f"Latest copy written: {latest_output_path}")
    return result


def collect(args: argparse.Namespace) -> None:
    points = grid_points(args)
    out_dir = Path(args.output_dir)
    samples_path = out_dir / "stage2_error_grid_samples.csv"
    manifest_path = out_dir / "stage2_error_grid_manifest.json"
    gear_num, gear_den = parse_gear_ratio(args.gear_ratio)
    gear_text = f"{gear_num:g}:{gear_den:g}"
    reduction = gear_reduction(gear_num, gear_den)

    manifest = {
        "method": "stage2_error_grid_collect",
        "execute": bool(args.execute),
        "x_range_mm": [args.x_min, args.x_max],
        "y_range_mm": [args.y_min, args.y_max],
        "x_count": args.x_count,
        "y_count": args.y_count,
        "z_levels_mm": parse_z_levels(args.z_levels),
        "repeats": args.repeats,
        "gear_ratio": gear_text,
        "gear_reduction": reduction,
        "arm_angle_formula": "arm_angle_deg = driver_angle_deg / (gear_ratio_numerator / gear_ratio_denominator)",
        "moonraker_url": args.moonraker_url,
        "snapshot_url": args.snapshot_url,
        "board_origin": args.board_origin,
        "stage0_transform": args.machine_transform,
        "points": [point.__dict__ for point in points],
        "created_at": time.time(),
    }
    save_json(manifest_path, manifest)

    if not args.execute:
        print("Dry run only. Planned Stage 2 points:")
        for point in points:
            print(f"  {point.name}: X{point.x:.3f} Y{point.y:.3f} Z{point.z:.3f}")
        print(f"Total samples per repeat: {len(points)}")
        print(f"Manifest written: {manifest_path}")
        print("Add --execute to move the robot and collect images.")
        return

    camera_matrix, dist_coeffs = load_intrinsics(Path(args.intrinsics))
    t_camera_from_board = load_t_camera_from_board(Path(args.charuco_extrinsic), args.board_origin)
    machine_transform_payload = load_json(Path(args.machine_transform))
    t_machine_from_board_up = np.array(machine_transform_payload["T_machine_from_board_up"], dtype=np.float64)

    ensure_motion_ready(args)

    rows: list[dict] = []
    sample_id = 0
    for repeat_index in range(args.repeats):
        for point in points:
            print(f"Moving to {point.name}: X{point.x:.3f} Y{point.y:.3f} Z{point.z:.3f}")
            run_gcode(
                args.moonraker_url,
                f"G90\nG1 X{point.x:.4f} Y{point.y:.4f} Z{point.z:.4f} F{args.feedrate:.1f}\nM400",
                timeout_s=60.0,
            )
            emm_wait_s = ""
            emm_statuses = {}
            if not args.no_wait_emm_reached:
                print("Waiting for EMM reached flags...")
                emm_wait_s, emm_statuses = wait_emm_reached(
                    args.moonraker_url,
                    args.emm_reached_timeout,
                    args.emm_reached_poll,
                    args.emm_reached_stable,
                )
            time.sleep(args.settle_s)

            emm_positions = {}
            try:
                emm_positions = read_emm_positions(args.moonraker_url)
            except (urllib.error.URLError, KeyError, RuntimeError) as exc:
                print(f"Warning: failed to read EMM positions: {exc}")
            if not emm_statuses:
                try:
                    emm_statuses = read_emm_statuses(args.moonraker_url)
                except (urllib.error.URLError, KeyError, RuntimeError):
                    emm_statuses = {}

            image_path = out_dir / "images" / f"{sample_id:04d}_{point.name}_r{repeat_index}.jpg"
            overlay_path = out_dir / "overlays" / f"{sample_id:04d}_{point.name}_r{repeat_index}_overlay.jpg"
            row = {
                "sample_id": sample_id,
                "name": point.name,
                "repeat": repeat_index,
                "layer": point.layer,
                "grid_ix": point.ix,
                "grid_iy": point.iy,
                "timestamp": time.time(),
                "board_origin": args.board_origin,
                "cmd_x": point.x,
                "cmd_y": point.y,
                "cmd_z": point.z,
                "gear_ratio": gear_text,
                "gear_reduction": reduction,
                "emm_wait_reached": not args.no_wait_emm_reached,
                "emm_wait_s": emm_wait_s,
                "settle_s": args.settle_s,
                "image": str(image_path),
                "overlay": str(overlay_path),
            }
            for driver_id in (1, 2, 3):
                driver_angle = emm_positions.get(str(driver_id), {}).get("angle", "")
                row[f"emm_id{driver_id}_deg"] = driver_angle
                if driver_angle != "":
                    row[f"arm_id{driver_id}_deg"] = motor_to_arm_angle(float(driver_angle), gear_num, gear_den)
                reached = emm_statuses.get(str(driver_id), {}).get("reached", "")
                row[f"emm_id{driver_id}_reached"] = reached
            if emm_statuses:
                row["emm_status_json"] = json.dumps(emm_statuses, ensure_ascii=False, sort_keys=True)

            try:
                row["captured_at"] = time.time()
                image = snapshot_image(args.snapshot_url, image_path)
                detection = detect_platform_tag(
                    image,
                    camera_matrix,
                    dist_coeffs,
                    t_camera_from_board,
                    args.tag_size,
                    args.tag_id,
                    args.dictionary,
                )
                cv2.imwrite(str(overlay_path), detection.pop("overlay"))
                row["detect_ok"] = bool(detection.get("detect_ok"))
                if row["detect_ok"]:
                    board = np.array(detection["center_board_up_mm"], dtype=np.float64)
                    measured = machine_from_board_up(board, t_machine_from_board_up)
                    err = measured - np.array([point.x, point.y, point.z], dtype=np.float64)
                    row["tag_x_board_up"] = float(board[0])
                    row["tag_y_board_up"] = float(board[1])
                    row["tag_z_board_up"] = float(board[2])
                    row["measured_x_machine"] = float(measured[0])
                    row["measured_y_machine"] = float(measured[1])
                    row["measured_z_machine"] = float(measured[2])
                    row["error_x_mm"] = float(err[0])
                    row["error_y_mm"] = float(err[1])
                    row["error_z_mm"] = float(err[2])
                    row["error_xy_mm"] = float(np.linalg.norm(err[:2]))
                    row["reprojection_mean_px"] = detection["mean_reprojection_error_px"]
                    row["reprojection_max_px"] = detection["max_reprojection_error_px"]
                else:
                    row["error"] = detection.get("error", "detection failed")
            except Exception as exc:
                row["detect_ok"] = False
                row["error"] = str(exc)
                print(f"Warning: sample {sample_id} failed: {exc}")

            rows.append(row)
            rows_to_csv(samples_path, rows)
            sample_id += 1

    print(f"Samples written: {samples_path}")
    summarize_from_csv(
        samples_path,
        out_dir / "stage2_error_grid_result.json",
        Path(args.latest_output),
    )


def summarize(args: argparse.Namespace) -> None:
    summarize_from_csv(Path(args.samples), Path(args.output), Path(args.latest_output))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Collect a visual XY error grid at multiple Z heights.")
    sub = parser.add_subparsers(dest="command", required=True)

    collect_parser = sub.add_parser("collect", help="Collect Stage 2 visual grid samples.")
    collect_parser.add_argument("--execute", action="store_true", help="Actually move the robot.")
    collect_parser.add_argument("--home-and-clear", action="store_true", help="Run EMM_HOME_AND_CLEAR first.")
    collect_parser.add_argument("--no-auto-home", action="store_true", help="Fail instead of auto homing if axes are not homed.")
    collect_parser.add_argument("--x-min", type=float, default=-40.0)
    collect_parser.add_argument("--x-max", type=float, default=40.0)
    collect_parser.add_argument("--y-min", type=float, default=-40.0)
    collect_parser.add_argument("--y-max", type=float, default=40.0)
    collect_parser.add_argument("--x-count", type=int, default=3)
    collect_parser.add_argument("--y-count", type=int, default=3)
    collect_parser.add_argument("--z-levels", default="55,65,75")
    collect_parser.add_argument("--repeats", type=int, default=1)
    collect_parser.add_argument("--feedrate", type=float, default=3000.0)
    collect_parser.add_argument("--settle-s", type=float, default=1.0)
    collect_parser.add_argument("--no-wait-emm-reached", action="store_true")
    collect_parser.add_argument("--emm-reached-timeout", type=float, default=10.0)
    collect_parser.add_argument("--emm-reached-poll", type=float, default=0.05)
    collect_parser.add_argument("--emm-reached-stable", type=int, default=2)
    collect_parser.add_argument("--moonraker-url", default="http://192.168.67.182")
    collect_parser.add_argument("--snapshot-url", default="http://127.0.0.1:8765/snapshot")
    collect_parser.add_argument("--intrinsics", default=str(DEFAULT_INTRINSICS))
    collect_parser.add_argument("--charuco-extrinsic", default=str(DEFAULT_CHARUCO))
    collect_parser.add_argument("--machine-transform", default=str(DEFAULT_STAGE0_TRANSFORM))
    collect_parser.add_argument("--board-origin", choices=("center", "corner"), default=DEFAULT_BOARD_ORIGIN)
    collect_parser.add_argument("--output-dir", default=str(DEFAULT_OUT_DIR))
    collect_parser.add_argument("--latest-output", default=str(DEFAULT_LATEST_RESULT))
    collect_parser.add_argument("--tag-id", type=int, default=0)
    collect_parser.add_argument("--tag-size", type=float, default=20.0)
    collect_parser.add_argument("--dictionary", default="DICT_APRILTAG_36h11")
    collect_parser.add_argument("--gear-ratio", default="50:20")
    collect_parser.set_defaults(func=collect)

    summarize_parser = sub.add_parser("summarize", help="Regenerate Stage 2 result JSON and plots from CSV.")
    summarize_parser.add_argument("--samples", default=str(DEFAULT_OUT_DIR / "stage2_error_grid_samples.csv"))
    summarize_parser.add_argument("--output", default=str(DEFAULT_OUT_DIR / "stage2_error_grid_result.json"))
    summarize_parser.add_argument("--latest-output", default=str(DEFAULT_LATEST_RESULT))
    summarize_parser.set_defaults(func=summarize)
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
