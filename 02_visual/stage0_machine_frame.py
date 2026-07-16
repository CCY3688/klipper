#!/usr/bin/env python3
"""Stage 0 machine-frame alignment for the writer bot.

This script estimates an initial T_machine_from_board transform from a small
set of commanded Klipper points and visually measured platform AprilTag poses.
It is intentionally split into collection and estimation so each artifact can
be inspected before later mechanical parameter fitting.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
INTRINSICS_CANDIDATES = [
    ROOT / "02_visual" / "摄像头内参" / "camera_calibration_results.json",
    ROOT / "host" / "camera" / "camera_calibration_results.json",
    ROOT / "00_ref" / "camera_calibration_results.json",
]
DEFAULT_INTRINSICS = next(
    (path for path in INTRINSICS_CANDIDATES if path.exists()),
    INTRINSICS_CANDIDATES[0],
)
DEFAULT_CHARUCO = ROOT / "02_visual" / "charuco_manual_extrinsic_latest.json"
DEFAULT_OUT_DIR = ROOT / "02_visual" / "stage0_machine_frame"
DEFAULT_LATEST_TRANSFORM = ROOT / "02_visual" / "T_machine_from_board_initial.json"
DEFAULT_BOARD_ORIGIN = "center"


@dataclass(frozen=True)
class StagePoint:
    name: str
    x: float
    y: float
    z: float


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
        f.write("\n")


def save_latest_copy(payload: dict) -> None:
    save_json(DEFAULT_LATEST_TRANSFORM, payload)


def load_intrinsics(path: Path) -> tuple[np.ndarray, np.ndarray]:
    data = load_json(path)
    if "focal_length_fxfy" in data and "principal_point_cxcy" in data:
        fx, fy = data["focal_length_fxfy"]
        cx, cy = data["principal_point_cxcy"]
        k = np.array([[fx, 0.0, cx], [0.0, fy, cy], [0.0, 0.0, 1.0]], dtype=np.float64)
    else:
        k = np.array(data["intrinsic_matrix_K"], dtype=np.float64)
        if abs(k[2, 2] - 1.0) > 1e-9 or abs(k[0, 2]) < 1e-9:
            k = k.T

    radial = data.get("radial_distortion_k", [0.0, 0.0])
    tangential = data.get("tangential_distortion_p", [0.0, 0.0])
    dist = np.array(
        [radial[0], radial[1], tangential[0], tangential[1], 0.0],
        dtype=np.float64,
    )
    return k, dist


def parse_charuco_squares(value: object) -> tuple[int, int]:
    if isinstance(value, str) and "x" in value.lower():
        left, right = value.lower().split("x", 1)
        return int(left.strip()), int(right.strip())
    if isinstance(value, (list, tuple)) and len(value) == 2:
        return int(value[0]), int(value[1])
    raise ValueError(f"Unsupported ChArUco squares value: {value!r}")


def charuco_center_offset_from_corner(data: dict) -> np.ndarray:
    cols, rows = parse_charuco_squares(data.get("squares", "8x8"))
    square_length = float(data.get("square_length_mm", 14.0))
    return np.array([cols * square_length * 0.5, rows * square_length * 0.5, 0.0], dtype=np.float64)


def load_t_camera_from_board(path: Path, board_origin: str = DEFAULT_BOARD_ORIGIN) -> np.ndarray:
    data = load_json(path)
    t_camera_from_corner = np.array(data["T_camera_from_charuco"], dtype=np.float64)
    if board_origin == "corner":
        return t_camera_from_corner
    if board_origin != "center":
        raise ValueError(f"Unsupported board origin: {board_origin}")

    t_corner_from_center = np.eye(4, dtype=np.float64)
    t_corner_from_center[:3, 3] = charuco_center_offset_from_corner(data)
    return t_camera_from_corner @ t_corner_from_center


def board_up_from_camera(point_camera: np.ndarray, t_camera_from_board: np.ndarray) -> np.ndarray:
    t_board_from_camera = np.linalg.inv(t_camera_from_board)
    p = np.array([point_camera[0], point_camera[1], point_camera[2], 1.0], dtype=np.float64)
    raw = t_board_from_camera @ p
    # The existing ChArUco solve has points above the bed at negative raw Z.
    return np.array([raw[0], raw[1], -raw[2]], dtype=np.float64)


def board_up_to_camera(points_board_up: np.ndarray, t_camera_from_board: np.ndarray) -> np.ndarray:
    points = np.asarray(points_board_up, dtype=np.float64).reshape(-1, 3)
    raw_board = np.column_stack(
        [points[:, 0], points[:, 1], -points[:, 2], np.ones(len(points))]
    )
    return (t_camera_from_board @ raw_board.T).T[:, :3]


def project_board_up_points(
    points_board_up: np.ndarray,
    camera_matrix: np.ndarray,
    dist_coeffs: np.ndarray,
    t_camera_from_board: np.ndarray,
) -> np.ndarray:
    camera_points = board_up_to_camera(points_board_up, t_camera_from_board)
    image_points, _ = cv2.projectPoints(
        camera_points.reshape(-1, 1, 3),
        np.zeros(3, dtype=np.float64),
        np.zeros(3, dtype=np.float64),
        camera_matrix,
        dist_coeffs,
    )
    return image_points.reshape(-1, 2)


def april_tag_dictionary(name: str) -> int:
    normalized = name.upper().replace("H", "h")
    candidates = {
        "DICT_APRILTAG_36h11": cv2.aruco.DICT_APRILTAG_36h11,
        "APRILTAG_36h11": cv2.aruco.DICT_APRILTAG_36h11,
        "TAG36h11": cv2.aruco.DICT_APRILTAG_36h11,
    }
    if normalized in candidates:
        return candidates[normalized]
    raise ValueError(f"Unsupported AprilTag dictionary: {name}")


def detect_platform_tag(
    image_bgr: np.ndarray,
    camera_matrix: np.ndarray,
    dist_coeffs: np.ndarray,
    t_camera_from_board: np.ndarray,
    tag_size_mm: float,
    tag_id: int,
    dictionary_name: str,
) -> dict:
    dictionary = cv2.aruco.getPredefinedDictionary(april_tag_dictionary(dictionary_name))
    detector_params = cv2.aruco.DetectorParameters()
    detector = cv2.aruco.ArucoDetector(dictionary, detector_params)
    corners, ids, _ = detector.detectMarkers(image_bgr)

    overlay = image_bgr.copy()
    if ids is None or len(ids) == 0:
        return {
            "detect_ok": False,
            "error": "no AprilTag detected",
            "overlay": overlay,
        }

    ids_flat = ids.reshape(-1)
    match_indexes = [i for i, found_id in enumerate(ids_flat) if int(found_id) == tag_id]
    if not match_indexes:
        cv2.aruco.drawDetectedMarkers(overlay, corners, ids)
        return {
            "detect_ok": False,
            "error": f"tag id {tag_id} not found; found {ids_flat.tolist()}",
            "overlay": overlay,
        }

    idx = match_indexes[0]
    img_points = corners[idx].reshape(4, 2).astype(np.float64)
    half = tag_size_mm / 2.0
    object_points = np.array(
        [
            [-half, half, 0.0],
            [half, half, 0.0],
            [half, -half, 0.0],
            [-half, -half, 0.0],
        ],
        dtype=np.float64,
    )
    ok, rvec, tvec = cv2.solvePnP(
        object_points,
        img_points,
        camera_matrix,
        dist_coeffs,
        flags=cv2.SOLVEPNP_IPPE_SQUARE,
    )
    if not ok:
        return {
            "detect_ok": False,
            "error": "solvePnP failed",
            "overlay": overlay,
        }

    projected, _ = cv2.projectPoints(object_points, rvec, tvec, camera_matrix, dist_coeffs)
    projected = projected.reshape(4, 2)
    reproj_errors = np.linalg.norm(projected - img_points, axis=1)

    cv2.aruco.drawDetectedMarkers(overlay, [corners[idx]], np.array([[tag_id]], dtype=np.int32))
    try:
        cv2.drawFrameAxes(overlay, camera_matrix, dist_coeffs, rvec, tvec, tag_size_mm * 0.75)
    except cv2.error:
        pass

    center_camera = tvec.reshape(3)
    center_board_up = board_up_from_camera(center_camera, t_camera_from_board)
    center_image = np.mean(img_points, axis=0)
    return {
        "detect_ok": True,
        "tag_id": tag_id,
        "center_camera_mm": center_camera.tolist(),
        "center_board_up_mm": center_board_up.tolist(),
        "center_image_px": center_image.tolist(),
        "rvec": rvec.reshape(3).tolist(),
        "image_points_px": img_points.tolist(),
        "mean_reprojection_error_px": float(np.mean(reproj_errors)),
        "max_reprojection_error_px": float(np.max(reproj_errors)),
        "overlay": overlay,
    }


def http_json(url: str, timeout_s: float = 15.0, body: dict | None = None) -> dict:
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=timeout_s) as response:
        return json.loads(response.read().decode("utf-8"))


def http_bytes(url: str, timeout_s: float = 15.0) -> bytes:
    with urllib.request.urlopen(url, timeout=timeout_s) as response:
        return response.read()


def moonraker_url(base_url: str, path: str) -> str:
    return base_url.rstrip("/") + path


def run_gcode(base_url: str, script: str, timeout_s: float = 30.0) -> dict:
    try:
        return http_json(
            moonraker_url(base_url, "/printer/gcode/script"),
            timeout_s=timeout_s,
            body={"script": script},
        )
    except urllib.error.HTTPError as exc:
        message = exc.reason
        try:
            payload = exc.read().decode("utf-8", errors="replace")
            decoded = json.loads(payload)
            message = decoded.get("error", {}).get("message", message)
        except Exception:
            pass
        raise RuntimeError(f"Moonraker rejected GCode ({exc.code}): {message}") from exc


def read_emm_positions(base_url: str) -> dict:
    run_gcode(base_url, "EMM_READ_POSITIONS", timeout_s=10.0)
    status = http_json(moonraker_url(base_url, "/printer/objects/query?emm_uart"), timeout_s=10.0)
    return status["result"]["status"]["emm_uart"].get("last_positions", {})


def read_emm_statuses(base_url: str) -> dict:
    status = http_json(moonraker_url(base_url, "/printer/objects/query?emm_uart"), timeout_s=10.0)
    return status["result"]["status"]["emm_uart"].get("last_statuses", {})


def wait_emm_reached(base_url: str, timeout_s: float, poll_s: float, stable: int):
    started = time.time()
    run_gcode(
        base_url,
        f"EMM_WAIT_REACHED TIMEOUT={timeout_s:.3f} POLL={poll_s:.3f} STABLE={stable}",
        timeout_s=timeout_s + 10.0,
    )
    elapsed = time.time() - started
    return elapsed, read_emm_statuses(base_url)


def read_homed_axes(base_url: str) -> str:
    status = http_json(moonraker_url(base_url, "/printer/objects/query?toolhead"), timeout_s=10.0)
    return status["result"]["status"]["toolhead"].get("homed_axes", "")


def ensure_motion_ready(args: argparse.Namespace) -> None:
    homed_axes = read_homed_axes(args.moonraker_url)
    if all(axis in homed_axes for axis in "xyz"):
        if args.home_and_clear:
            print("Printer is already homed. Running EMM_HOME_AND_CLEAR anyway...")
            run_gcode(args.moonraker_url, "EMM_HOME_AND_CLEAR", timeout_s=90.0)
        return

    missing = "".join(axis for axis in "xyz" if axis not in homed_axes)
    if args.no_auto_home:
        raise RuntimeError(
            "Printer is not homed. Missing axes: "
            f"{missing}. Enable auto home or run EMM_HOME_AND_CLEAR first."
        )

    print(f"Printer is not homed. Missing axes: {missing}. Running EMM_HOME_AND_CLEAR...")
    run_gcode(args.moonraker_url, "EMM_HOME_AND_CLEAR", timeout_s=90.0)


def snapshot_image(snapshot_url: str, image_path: Path) -> np.ndarray:
    image_path.parent.mkdir(parents=True, exist_ok=True)
    payload = http_bytes(snapshot_url, timeout_s=40.0)
    image_path.write_bytes(payload)
    arr = np.frombuffer(payload, dtype=np.uint8)
    image = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError(f"Failed to decode camera snapshot from {snapshot_url}")
    return image


def stage_points(zsafe: float, distance: float) -> list[StagePoint]:
    return [
        StagePoint("center", 0.0, 0.0, zsafe),
        StagePoint("x_plus", distance, 0.0, zsafe),
        StagePoint("y_plus", 0.0, distance, zsafe),
        StagePoint("x_minus", -distance, 0.0, zsafe),
        StagePoint("y_minus", 0.0, -distance, zsafe),
    ]


def rows_to_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "sample_id",
        "name",
        "repeat",
        "timestamp",
        "board_origin",
        "cmd_x",
        "cmd_y",
        "cmd_z",
        "detect_ok",
        "tag_x_board_up",
        "tag_y_board_up",
        "tag_z_board_up",
        "reprojection_mean_px",
        "reprojection_max_px",
        "emm_wait_reached",
        "emm_wait_s",
        "settle_s",
        "captured_at",
        "emm_id1_deg",
        "emm_id2_deg",
        "emm_id3_deg",
        "emm_id1_reached",
        "emm_id2_reached",
        "emm_id3_reached",
        "emm_status_json",
        "image",
        "overlay",
        "error",
    ]
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def collect(args: argparse.Namespace) -> None:
    points = stage_points(args.zsafe, args.distance)
    out_dir = Path(args.output_dir)
    samples_path = out_dir / "machine_frame_samples.csv"
    manifest_path = out_dir / "machine_frame_collect_manifest.json"

    manifest = {
        "method": "stage0_machine_frame_collect",
        "execute": bool(args.execute),
        "zsafe_mm": args.zsafe,
        "distance_mm": args.distance,
        "repeats": args.repeats,
        "wait_emm_reached": not args.no_wait_emm_reached,
        "emm_reached_timeout_s": args.emm_reached_timeout,
        "emm_reached_poll_s": args.emm_reached_poll,
        "emm_reached_stable": args.emm_reached_stable,
        "moonraker_url": args.moonraker_url,
        "snapshot_url": args.snapshot_url,
        "board_origin": args.board_origin,
        "points": [point.__dict__ for point in points],
        "created_at": time.time(),
    }
    save_json(manifest_path, manifest)

    if not args.execute:
        print("Dry run only. Planned points:")
        if args.preclear_charuco:
            print(
                "  preclear_charuco: "
                f"X{args.preclear_x:.3f} Y{args.preclear_y:.3f} Z{args.preclear_z:.3f}"
            )
        for point in points:
            print(f"  {point.name}: X{point.x:.3f} Y{point.y:.3f} Z{point.z:.3f}")
        print(f"Manifest written: {manifest_path}")
        print("Add --execute to move the robot and collect images.")
        return

    camera_matrix, dist_coeffs = load_intrinsics(Path(args.intrinsics))
    t_camera_from_board = load_t_camera_from_board(Path(args.charuco_extrinsic), args.board_origin)

    ensure_motion_ready(args)

    if args.preclear_charuco:
        print(
            "Moving platform away from ChArUco: "
            f"X{args.preclear_x:.3f} Y{args.preclear_y:.3f} Z{args.preclear_z:.3f}"
        )
        run_gcode(
            args.moonraker_url,
            f"G90\nG1 X{args.preclear_x:.4f} Y{args.preclear_y:.4f} Z{args.preclear_z:.4f} F{args.feedrate:.1f}\nM400",
            timeout_s=60.0,
        )
        time.sleep(args.settle_s)

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

            image_path = out_dir / "images" / f"{sample_id:03d}_{point.name}_r{repeat_index}.jpg"
            overlay_path = out_dir / "overlays" / f"{sample_id:03d}_{point.name}_r{repeat_index}_overlay.jpg"
            row = {
                "sample_id": sample_id,
                "name": point.name,
                "repeat": repeat_index,
                "timestamp": time.time(),
                "board_origin": args.board_origin,
                "cmd_x": point.x,
                "cmd_y": point.y,
                "cmd_z": point.z,
                "emm_wait_reached": not args.no_wait_emm_reached,
                "emm_wait_s": emm_wait_s,
                "settle_s": args.settle_s,
                "image": str(image_path),
                "overlay": str(overlay_path),
            }
            for driver_id in (1, 2, 3):
                value = emm_positions.get(str(driver_id), {}).get("angle", "")
                row[f"emm_id{driver_id}_deg"] = value
                reached = emm_statuses.get(str(driver_id), {}).get("reached", "")
                row[f"emm_id{driver_id}_reached"] = reached
            if emm_statuses:
                row["emm_status_json"] = json.dumps(
                    emm_statuses,
                    ensure_ascii=False,
                    sort_keys=True,
                )

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
                    x, y, z = detection["center_board_up_mm"]
                    row["tag_x_board_up"] = x
                    row["tag_y_board_up"] = y
                    row["tag_z_board_up"] = z
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
    estimate_from_csv(
        samples_path,
        out_dir / "T_machine_from_board_initial.json",
        Path(args.intrinsics),
        Path(args.charuco_extrinsic),
        args.board_origin,
    )


def read_sample_rows(path: Path) -> list[dict]:
    with path.open("r", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def normalize_rows_to_board_origin(
    rows: list[dict],
    charuco_extrinsic_path: Path,
    target_origin: str = DEFAULT_BOARD_ORIGIN,
) -> list[dict]:
    if target_origin != "center":
        return rows

    data = load_json(charuco_extrinsic_path)
    offset = charuco_center_offset_from_corner(data)
    normalized: list[dict] = []
    for row in rows:
        next_row = dict(row)
        source_origin = str(next_row.get("board_origin", "") or "corner").lower()
        if source_origin == "corner" and str(next_row.get("detect_ok", "")).lower() in ("true", "1", "yes"):
            next_row["tag_x_board_up"] = float(next_row["tag_x_board_up"]) - float(offset[0])
            next_row["tag_y_board_up"] = float(next_row["tag_y_board_up"]) - float(offset[1])
            next_row["board_origin_source"] = "corner"
            next_row["board_origin"] = "center"
        normalized.append(next_row)
    return normalized


def _fit_bounds(points: np.ndarray, margin: float = 25.0) -> tuple[float, float, float, float]:
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


def _project_xy(point: np.ndarray, bounds: tuple[float, float, float, float], size: int) -> tuple[int, int]:
    min_x, max_x, min_y, max_y = bounds
    scale_x = (size - 80) / (max_x - min_x)
    scale_y = (size - 80) / (max_y - min_y)
    x = 40 + (point[0] - min_x) * scale_x
    y = size - 40 - (point[1] - min_y) * scale_y
    return int(round(x)), int(round(y))


def draw_stage0_summary(result: dict, output_path: Path, size: int = 960) -> None:
    residuals = result.get("residuals", [])
    if not residuals:
        return

    board_xy = np.array([item["board_up_mm"][:2] for item in residuals], dtype=np.float64)
    machine_xy = np.array([item["cmd_machine_mm"][:2] for item in residuals], dtype=np.float64)
    estimated_machine_xy = np.array([item["estimated_machine_mm"][:2] for item in residuals], dtype=np.float64)
    t_machine_from_board = np.array(result["T_machine_from_board_up"], dtype=np.float64)
    r2 = t_machine_from_board[:2, :2]
    t2 = t_machine_from_board[:2, 3]
    machine_origin_board = -r2.T @ t2
    machine_x_board = machine_origin_board + r2.T @ np.array([60.0, 0.0])
    machine_y_board = machine_origin_board + r2.T @ np.array([0.0, 60.0])
    board_x_axis = np.array([80.0, 0.0])
    board_y_axis = np.array([0.0, 80.0])

    all_points = np.vstack(
        [
            board_xy,
            machine_xy,
            estimated_machine_xy,
            t2.reshape(1, 2),
            machine_origin_board.reshape(1, 2),
            machine_x_board.reshape(1, 2),
            machine_y_board.reshape(1, 2),
            board_x_axis.reshape(1, 2),
            board_y_axis.reshape(1, 2),
        ]
    )
    bounds = _fit_bounds(all_points, margin=45.0)
    canvas = np.full((size, size, 3), 245, dtype=np.uint8)

    def pt(p: np.ndarray) -> tuple[int, int]:
        return _project_xy(p, bounds, size)

    # Grid in board/bed coordinates.
    min_x, max_x, min_y, max_y = bounds
    grid_step = 20.0
    start_x = math.floor(min_x / grid_step) * grid_step
    start_y = math.floor(min_y / grid_step) * grid_step
    x = start_x
    while x <= max_x:
        cv2.line(canvas, pt(np.array([x, min_y])), pt(np.array([x, max_y])), (225, 225, 225), 1)
        x += grid_step
    y = start_y
    while y <= max_y:
        cv2.line(canvas, pt(np.array([min_x, y])), pt(np.array([max_x, y])), (225, 225, 225), 1)
        y += grid_step

    # Board coordinate axes.
    origin = np.array([0.0, 0.0])
    cv2.arrowedLine(canvas, pt(origin), pt(np.array([60.0, 0.0])), (0, 90, 220), 3, tipLength=0.12)
    cv2.arrowedLine(canvas, pt(origin), pt(np.array([0.0, 60.0])), (0, 150, 0), 3, tipLength=0.12)
    cv2.putText(canvas, "Board X", pt(np.array([65.0, 0.0])), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 90, 220), 2)
    cv2.putText(canvas, "Board Y", pt(np.array([0.0, 65.0])), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 150, 0), 2)

    # Machine axes expressed in board coordinates, using inverse transform.
    cv2.arrowedLine(canvas, pt(machine_origin_board), pt(machine_x_board), (40, 40, 40), 3, tipLength=0.12)
    cv2.arrowedLine(canvas, pt(machine_origin_board), pt(machine_y_board), (110, 110, 110), 3, tipLength=0.12)
    cv2.putText(canvas, "Machine X", pt(machine_x_board + np.array([4.0, 0.0])), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (40, 40, 40), 2)
    cv2.putText(canvas, "Machine Y", pt(machine_y_board + np.array([4.0, 0.0])), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (90, 90, 90), 2)

    # Convert commanded machine points back to board coordinates for direct visual comparison.
    commanded_board_xy = ((machine_xy - t2) @ r2)
    estimated_board_xy = board_xy

    order = np.argsort([int(item.get("sample_id", 0)) for item in residuals])
    path_points = [pt(commanded_board_xy[i]) for i in order]
    for a, b in zip(path_points, path_points[1:]):
        cv2.line(canvas, a, b, (180, 180, 180), 1, cv2.LINE_AA)

    for i in order:
        item = residuals[i]
        target = commanded_board_xy[i]
        measured = estimated_board_xy[i]
        cv2.circle(canvas, pt(target), 9, (35, 35, 35), 2, cv2.LINE_AA)
        cv2.circle(canvas, pt(measured), 6, (40, 120, 240), -1, cv2.LINE_AA)
        cv2.line(canvas, pt(measured), pt(target), (20, 20, 220), 2, cv2.LINE_AA)
        label = str(item.get("name", item.get("sample_id", "")))
        cv2.putText(canvas, label, (pt(target)[0] + 10, pt(target)[1] - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (35, 35, 35), 1)

    cv2.rectangle(canvas, (18, 18), (520, 145), (255, 255, 255), -1)
    cv2.rectangle(canvas, (18, 18), (520, 145), (210, 210, 210), 1)
    lines = [
        "Stage 0 coordinate alignment",
        f"yaw={result['yaw_deg']:.4f} deg  tx={result['tx_mm']:.3f}  ty={result['ty_mm']:.3f}  tz={result['tz_mm']:.3f}",
        f"RMS={result['rms_error_mm']:.4f} mm  samples={result['valid_sample_count']}",
        "black ring: commanded target, blue dot: detected AprilTag center",
        "red segment: residual after fitted transform",
    ]
    for index, line in enumerate(lines):
        cv2.putText(canvas, line, (32, 44 + index * 23), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (25, 25, 25), 1, cv2.LINE_AA)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), canvas)


def _row_float(row: dict, key: str, default: float = 0.0) -> float:
    try:
        value = row.get(key, "")
        if value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def draw_stage0_capture_contact_sheet(
    rows: list[dict],
    output_path: Path,
    thumb_width: int = 520,
    columns: int = 2,
) -> None:
    items = []
    for row in rows:
        image_path = Path(row.get("image", ""))
        if not image_path.exists():
            continue
        image = cv2.imread(str(image_path))
        if image is None:
            continue
        items.append((row, image))

    if not items:
        return

    columns = max(1, min(columns, len(items)))
    header_h = 86
    footer_h = 26
    gap = 14
    thumbs = []
    for row, image in items:
        h, w = image.shape[:2]
        scale = thumb_width / float(w)
        thumb_height = max(1, int(round(h * scale)))
        thumb = cv2.resize(image, (thumb_width, thumb_height), interpolation=cv2.INTER_AREA)
        thumbs.append((row, thumb))

    tile_h = max(thumb.shape[0] for _, thumb in thumbs) + header_h + footer_h
    tile_w = thumb_width
    rows_n = int(math.ceil(len(thumbs) / columns))
    canvas_h = rows_n * tile_h + (rows_n + 1) * gap
    canvas_w = columns * tile_w + (columns + 1) * gap
    canvas = np.full((canvas_h, canvas_w, 3), 242, dtype=np.uint8)

    for index, (row, thumb) in enumerate(thumbs):
        grid_y, grid_x = divmod(index, columns)
        x0 = gap + grid_x * (tile_w + gap)
        y0 = gap + grid_y * (tile_h + gap)
        cv2.rectangle(canvas, (x0, y0), (x0 + tile_w, y0 + tile_h), (255, 255, 255), -1)
        cv2.rectangle(canvas, (x0, y0), (x0 + tile_w, y0 + tile_h), (205, 205, 205), 1)

        name = str(row.get("name", row.get("sample_id", "")))
        sample_id = str(row.get("sample_id", ""))
        cmd_x = _row_float(row, "cmd_x")
        cmd_y = _row_float(row, "cmd_y")
        cmd_z = _row_float(row, "cmd_z")
        captured_at = _row_float(row, "captured_at")
        wait_value = row.get("emm_wait_s", "")
        try:
            wait_s = f"{float(wait_value):.2f}s"
        except (TypeError, ValueError):
            wait_s = str(wait_value)
        detect_ok = str(row.get("detect_ok", ""))
        timestamp_text = time.strftime("%H:%M:%S", time.localtime(captured_at)) if captured_at > 0 else "n/a"
        lines = [
            f"{sample_id}  {name}   cmd=({cmd_x:.1f},{cmd_y:.1f},{cmd_z:.1f})",
            f"captured={timestamp_text}   wait={wait_s}   detect={detect_ok}",
        ]
        for line_index, line in enumerate(lines):
            cv2.putText(
                canvas,
                line,
                (x0 + 12, y0 + 28 + line_index * 28),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.58,
                (25, 25, 25),
                1,
                cv2.LINE_AA,
            )

        image_y = y0 + header_h
        canvas[image_y : image_y + thumb.shape[0], x0 : x0 + thumb.shape[1]] = thumb
        footer_text = str(Path(row.get("image", "")).name)
        cv2.putText(
            canvas,
            footer_text,
            (x0 + 12, y0 + tile_h - 8),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.46,
            (90, 90, 90),
            1,
            cv2.LINE_AA,
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), canvas)


def _machine_to_board_up(machine_xyz: np.ndarray, result: dict) -> np.ndarray:
    t_machine_from_board = np.array(result["T_machine_from_board_up"], dtype=np.float64)
    r2 = t_machine_from_board[:2, :2]
    t2 = t_machine_from_board[:2, 3]
    machine = np.asarray(machine_xyz, dtype=np.float64).reshape(3)
    board_xy = r2.T @ (machine[:2] - t2)
    return np.array([board_xy[0], board_xy[1], machine[2] - t_machine_from_board[2, 3]])


def _point_in_image(point: np.ndarray, shape: tuple[int, int, int]) -> bool:
    h, w = shape[:2]
    return 0.0 <= point[0] < w and 0.0 <= point[1] < h


def _draw_label(
    image: np.ndarray,
    text: str,
    point: tuple[int, int],
    color: tuple[int, int, int],
    scale: float = 0.48,
) -> None:
    h, w = image.shape[:2]
    x = int(np.clip(point[0], 6, max(6, w - 160)))
    y = int(np.clip(point[1], 18, max(18, h - 8)))
    cv2.putText(image, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX, scale, (255, 255, 255), 3, cv2.LINE_AA)
    cv2.putText(image, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX, scale, color, 1, cv2.LINE_AA)


def _draw_arrow(
    image: np.ndarray,
    start: np.ndarray,
    end: np.ndarray,
    color: tuple[int, int, int],
    label: str,
) -> None:
    if not (np.all(np.isfinite(start)) and np.all(np.isfinite(end))):
        return
    p0 = tuple(np.round(start).astype(int))
    p1 = tuple(np.round(end).astype(int))
    cv2.arrowedLine(image, p0, p1, color, 3, cv2.LINE_AA, tipLength=0.16)
    _draw_label(image, label, (p1[0] + 6, p1[1] - 6), color)


def draw_stage0_photo_overlay(
    rows: list[dict],
    result: dict,
    output_path: Path,
    camera_matrix: np.ndarray,
    dist_coeffs: np.ndarray,
    t_camera_from_board: np.ndarray,
) -> None:
    valid = [row for row in rows if str(row.get("detect_ok", "")).lower() in ("true", "1", "yes")]
    if not valid:
        return

    base_row = next(
        (row for row in valid if row.get("name") == "center" and Path(row.get("image", "")).exists()),
        None,
    )
    if base_row is None:
        base_row = next((row for row in valid if Path(row.get("image", "")).exists()), None)
    if base_row is None:
        return

    image = cv2.imread(str(Path(base_row["image"])))
    if image is None:
        return

    measured_board = np.array(
        [[float(row["tag_x_board_up"]), float(row["tag_y_board_up"]), float(row["tag_z_board_up"])] for row in valid],
        dtype=np.float64,
    )
    machine_points = np.array(
        [[float(row["cmd_x"]), float(row["cmd_y"]), float(row["cmd_z"])] for row in valid],
        dtype=np.float64,
    )
    target_board = np.array([_machine_to_board_up(point, result) for point in machine_points], dtype=np.float64)
    measured_px = project_board_up_points(measured_board, camera_matrix, dist_coeffs, t_camera_from_board)
    target_px = project_board_up_points(target_board, camera_matrix, dist_coeffs, t_camera_from_board)

    measured_in = sum(1 for point in measured_px if _point_in_image(point, image.shape))
    target_in = sum(1 for point in target_px if _point_in_image(point, image.shape))

    order = np.argsort([int(row.get("sample_id", 0) or 0) for row in valid])
    target_path = [tuple(np.round(target_px[i]).astype(int)) for i in order if np.all(np.isfinite(target_px[i]))]
    for p0, p1 in zip(target_path, target_path[1:]):
        cv2.line(image, p0, p1, (170, 170, 170), 1, cv2.LINE_AA)

    for i in order:
        row = valid[i]
        detected = measured_px[i]
        target = target_px[i]
        if np.all(np.isfinite(detected)) and np.all(np.isfinite(target)):
            cv2.line(
                image,
                tuple(np.round(detected).astype(int)),
                tuple(np.round(target).astype(int)),
                (0, 0, 255),
                2,
                cv2.LINE_AA,
            )
        if np.all(np.isfinite(target)) and _point_in_image(target, image.shape):
            cv2.circle(image, tuple(np.round(target).astype(int)), 10, (25, 25, 25), 2, cv2.LINE_AA)
        if np.all(np.isfinite(detected)) and _point_in_image(detected, image.shape):
            center = tuple(np.round(detected).astype(int))
            cv2.circle(image, center, 5, (255, 120, 30), -1, cv2.LINE_AA)
            _draw_label(image, str(row.get("name", row.get("sample_id", ""))), (center[0] + 8, center[1] - 8), (255, 120, 30))

    t_machine_from_board = np.array(result["T_machine_from_board_up"], dtype=np.float64)
    z_machine_ref = float(np.median(machine_points[:, 2]))
    z_board_ref = z_machine_ref - float(t_machine_from_board[2, 3])
    xy_span = np.max(np.ptp(machine_points[:, :2], axis=0)) if len(machine_points) > 1 else 40.0
    axis_len = float(np.clip(xy_span * 0.65, 35.0, 80.0))

    board_axis_points = np.array(
        [
            [0.0, 0.0, z_board_ref],
            [axis_len, 0.0, z_board_ref],
            [0.0, axis_len, z_board_ref],
        ],
        dtype=np.float64,
    )
    machine_axis_points = np.array(
        [
            _machine_to_board_up(np.array([0.0, 0.0, z_machine_ref]), result),
            _machine_to_board_up(np.array([axis_len, 0.0, z_machine_ref]), result),
            _machine_to_board_up(np.array([0.0, axis_len, z_machine_ref]), result),
        ],
        dtype=np.float64,
    )
    axis_px = project_board_up_points(
        np.vstack([board_axis_points, machine_axis_points]),
        camera_matrix,
        dist_coeffs,
        t_camera_from_board,
    )
    board_o, board_x, board_y, machine_o, machine_x, machine_y = axis_px
    _draw_arrow(image, board_o, board_x, (0, 90, 255), "Board X")
    _draw_arrow(image, board_o, board_y, (0, 190, 0), "Board Y")
    _draw_arrow(image, machine_o, machine_x, (30, 30, 30), "Machine X")
    _draw_arrow(image, machine_o, machine_y, (120, 120, 120), "Machine Y")

    box_lines = [
        "Stage0 photo overlay",
        f"yaw={result['yaw_deg']:.2f}deg  t=({result['tx_mm']:.1f},{result['ty_mm']:.1f},{result['tz_mm']:.1f})",
        f"RMS={result['rms_error_mm']:.2f}mm  Z~{z_machine_ref:.1f}mm",
        f"FOV detected {measured_in}/{len(valid)}  target {target_in}/{len(valid)}",
        "blue=detected  ring=command  red=residual",
    ]
    line_height = 19
    box_w = min(image.shape[1] - 20, 405)
    box_h = 15 + line_height * len(box_lines)
    overlay = image.copy()
    cv2.rectangle(overlay, (10, 10), (10 + box_w, 10 + box_h), (255, 255, 255), -1)
    image[:] = cv2.addWeighted(overlay, 0.58, image, 0.42, 0)
    cv2.rectangle(image, (10, 10), (10 + box_w, 10 + box_h), (40, 40, 40), 1)
    for index, line in enumerate(box_lines):
        cv2.putText(
            image,
            line,
            (20, 33 + index * line_height),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.44,
            (20, 20, 20),
            1,
            cv2.LINE_AA,
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), image)


def describe_axis_mapping(matrix: np.ndarray, source_axes: tuple[str, str], target_axes: tuple[str, str]) -> list[str]:
    descriptions: list[str] = []
    for source_index, source_name in enumerate(source_axes):
        vector = matrix[:, source_index]
        target_index = int(np.argmax(np.abs(vector)))
        sign = "+" if vector[target_index] >= 0 else "-"
        descriptions.append(f"{source_name} -> {sign}{target_axes[target_index]}")
    return descriptions


def estimate_transform(rows: list[dict], xy_transform: str = "orthogonal") -> dict:
    valid = [row for row in rows if str(row.get("detect_ok", "")).lower() in ("true", "1", "yes")]
    if len(valid) < 2:
        raise RuntimeError("At least two valid detected samples are required")
    if xy_transform not in ("rigid", "orthogonal"):
        raise ValueError(f"Unsupported xy_transform: {xy_transform}")

    board_xy = np.array(
        [[float(row["tag_x_board_up"]), float(row["tag_y_board_up"])] for row in valid],
        dtype=np.float64,
    )
    machine_xy = np.array(
        [[float(row["cmd_x"]), float(row["cmd_y"])] for row in valid],
        dtype=np.float64,
    )
    board_z = np.array([float(row["tag_z_board_up"]) for row in valid], dtype=np.float64)
    machine_z = np.array([float(row["cmd_z"]) for row in valid], dtype=np.float64)

    board_centroid = board_xy.mean(axis=0)
    machine_centroid = machine_xy.mean(axis=0)
    p = board_xy - board_centroid
    q = machine_xy - machine_centroid
    h = p.T @ q
    u, _, vt = np.linalg.svd(h)
    r2 = vt.T @ u.T
    if xy_transform == "rigid" and np.linalg.det(r2) < 0:
        vt[-1, :] *= -1
        r2 = vt.T @ u.T
    xy_det = float(np.linalg.det(r2))
    translation_xy = machine_centroid - r2 @ board_centroid
    tz = float(np.mean(machine_z - board_z))

    transformed_xy = (r2 @ board_xy.T).T + translation_xy
    transformed_z = board_z + tz
    residual_xy = transformed_xy - machine_xy
    residual_z = transformed_z - machine_z
    residual_xyz = np.column_stack([residual_xy, residual_z])
    residual_norm = np.linalg.norm(residual_xyz, axis=1)

    yaw = math.atan2(r2[1, 0], r2[0, 0])
    t = [float(translation_xy[0]), float(translation_xy[1]), tz]
    transform = [
        [float(r2[0, 0]), float(r2[0, 1]), 0.0, t[0]],
        [float(r2[1, 0]), float(r2[1, 1]), 0.0, t[1]],
        [0.0, 0.0, 1.0, t[2]],
        [0.0, 0.0, 0.0, 1.0],
    ]

    residual_rows = []
    for row, pred_xy, pred_z, res in zip(valid, transformed_xy, transformed_z, residual_xyz):
        residual_rows.append(
            {
                "sample_id": row.get("sample_id"),
                "name": row.get("name"),
                "cmd_machine_mm": [float(row["cmd_x"]), float(row["cmd_y"]), float(row["cmd_z"])],
                "board_up_mm": [
                    float(row["tag_x_board_up"]),
                    float(row["tag_y_board_up"]),
                    float(row["tag_z_board_up"]),
                ],
                "estimated_machine_mm": [float(pred_xy[0]), float(pred_xy[1]), float(pred_z)],
                "residual_mm": [float(res[0]), float(res[1]), float(res[2])],
                "residual_norm_mm": float(np.linalg.norm(res)),
            }
        )

    return {
        "method": "commanded_points_2d_orthogonal_plus_z_offset",
        "source": "P_machine ~= Axy * P_board_up + [tx, ty, tz]",
        "xy_transform": xy_transform,
        "xy_handedness": "preserved" if xy_det > 0 else "mirrored",
        "xy_determinant": xy_det,
        "board_to_machine_axis_mapping": describe_axis_mapping(
            r2,
            ("Board X", "Board Y"),
            ("Machine X", "Machine Y"),
        ),
        "machine_to_board_axis_mapping": describe_axis_mapping(
            r2.T,
            ("Machine X", "Machine Y"),
            ("Board X", "Board Y"),
        ),
        "board_origin": DEFAULT_BOARD_ORIGIN,
        "valid_sample_count": len(valid),
        "yaw_rad": float(yaw),
        "yaw_deg": float(math.degrees(yaw)),
        "tx_mm": t[0],
        "ty_mm": t[1],
        "tz_mm": t[2],
        "T_machine_from_board_up": transform,
        "rms_error_mm": float(math.sqrt(np.mean(residual_norm**2))),
        "mean_abs_error_mm": np.mean(np.abs(residual_xyz), axis=0).tolist(),
        "max_abs_error_mm": np.max(np.abs(residual_xyz), axis=0).tolist(),
        "residuals": residual_rows,
        "created_at": time.time(),
    }


def estimate_from_csv(
    samples_path: Path,
    output_path: Path,
    intrinsics_path: Path | None = None,
    charuco_extrinsic_path: Path | None = None,
    board_origin: str = DEFAULT_BOARD_ORIGIN,
    xy_transform: str = "orthogonal",
) -> dict:
    rows = read_sample_rows(samples_path)
    charuco_path = charuco_extrinsic_path or DEFAULT_CHARUCO
    rows = normalize_rows_to_board_origin(rows, charuco_path, board_origin)
    result = estimate_transform(rows, xy_transform=xy_transform)
    result["board_origin"] = board_origin
    if board_origin == "center":
        charuco_data = load_json(charuco_path)
        result["board_origin_note"] = "ChArUco center; legacy corner-origin CSV samples are shifted before fitting"
        result["charuco_center_offset_from_corner_mm"] = charuco_center_offset_from_corner(charuco_data).tolist()
    summary_path = output_path.with_name("stage0_coordinate_summary.png")
    photo_overlay_path = output_path.with_name("stage0_photo_overlay.png")
    capture_sheet_path = output_path.with_name("stage0_capture_contact_sheet.jpg")
    result["summary_image"] = str(summary_path)
    result["photo_overlay_image"] = str(photo_overlay_path)
    result["capture_contact_sheet"] = str(capture_sheet_path)
    draw_stage0_summary(result, summary_path)
    try:
        draw_stage0_capture_contact_sheet(rows, capture_sheet_path)
    except Exception as exc:
        print(f"Warning: failed to draw capture contact sheet: {exc}")
    try:
        camera_matrix, dist_coeffs = load_intrinsics(intrinsics_path or DEFAULT_INTRINSICS)
        t_camera_from_board = load_t_camera_from_board(charuco_path, board_origin)
        draw_stage0_photo_overlay(
            rows,
            result,
            photo_overlay_path,
            camera_matrix,
            dist_coeffs,
            t_camera_from_board,
        )
    except Exception as exc:
        print(f"Warning: failed to draw photo overlay: {exc}")
    save_json(output_path, result)
    save_latest_copy(result)
    print("Initial T_machine_from_board estimate:")
    print(f"  yaw = {result['yaw_deg']:.6f} deg")
    print(f"  tx  = {result['tx_mm']:.6f} mm")
    print(f"  ty  = {result['ty_mm']:.6f} mm")
    print(f"  tz  = {result['tz_mm']:.6f} mm")
    print(f"  rms = {result['rms_error_mm']:.6f} mm")
    print(f"Result written: {output_path}")
    print(f"Summary image written: {summary_path}")
    print(f"Capture contact sheet written: {capture_sheet_path}")
    print(f"Photo overlay written: {photo_overlay_path}")
    print(f"Latest copy written: {DEFAULT_LATEST_TRANSFORM}")
    return result


def estimate(args: argparse.Namespace) -> None:
    estimate_from_csv(
        Path(args.samples),
        Path(args.output),
        Path(args.intrinsics),
        Path(args.charuco_extrinsic),
        args.board_origin,
        args.xy_transform,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Collect and estimate Stage 0 T_machine_from_board alignment.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    collect_parser = sub.add_parser("collect", help="Collect commanded-point visual samples.")
    collect_parser.add_argument("--execute", action="store_true", help="Actually move the robot.")
    collect_parser.add_argument("--home-and-clear", action="store_true", help="Run EMM_HOME_AND_CLEAR first.")
    collect_parser.add_argument(
        "--no-auto-home",
        action="store_true",
        help="Fail instead of automatically running EMM_HOME_AND_CLEAR when axes are not homed.",
    )
    collect_parser.add_argument("--zsafe", type=float, default=75.0)
    collect_parser.add_argument("--distance", type=float, default=40.0)
    collect_parser.add_argument("--repeats", type=int, default=1)
    collect_parser.add_argument("--feedrate", type=float, default=3000.0)
    collect_parser.add_argument("--settle-s", type=float, default=1.0)
    collect_parser.add_argument(
        "--no-wait-emm-reached",
        action="store_true",
        help="Capture after M400 and settle only, without waiting for EMM reached flags.",
    )
    collect_parser.add_argument("--emm-reached-timeout", type=float, default=10.0)
    collect_parser.add_argument("--emm-reached-poll", type=float, default=0.05)
    collect_parser.add_argument("--emm-reached-stable", type=int, default=2)
    collect_parser.add_argument("--moonraker-url", default="http://192.168.67.182")
    collect_parser.add_argument("--snapshot-url", default="http://127.0.0.1:8765/snapshot")
    collect_parser.add_argument("--intrinsics", default=str(DEFAULT_INTRINSICS))
    collect_parser.add_argument("--charuco-extrinsic", default=str(DEFAULT_CHARUCO))
    collect_parser.add_argument("--board-origin", choices=("center", "corner"), default=DEFAULT_BOARD_ORIGIN)
    collect_parser.add_argument(
        "--preclear-charuco",
        action="store_true",
        help="Move to a non-occluding pose before collection starts.",
    )
    collect_parser.add_argument("--preclear-x", type=float, default=-60.0)
    collect_parser.add_argument("--preclear-y", type=float, default=-120.0)
    collect_parser.add_argument("--preclear-z", type=float, default=76.0)
    collect_parser.add_argument("--output-dir", default=str(DEFAULT_OUT_DIR))
    collect_parser.add_argument("--tag-id", type=int, default=0)
    collect_parser.add_argument("--tag-size", type=float, default=20.0)
    collect_parser.add_argument("--dictionary", default="DICT_APRILTAG_36h11")
    collect_parser.set_defaults(func=collect)

    estimate_parser = sub.add_parser("estimate", help="Estimate transform from a collected CSV.")
    estimate_parser.add_argument(
        "--samples",
        default=str(DEFAULT_OUT_DIR / "machine_frame_samples.csv"),
    )
    estimate_parser.add_argument(
        "--output",
        default=str(DEFAULT_OUT_DIR / "T_machine_from_board_initial.json"),
    )
    estimate_parser.add_argument("--intrinsics", default=str(DEFAULT_INTRINSICS))
    estimate_parser.add_argument("--charuco-extrinsic", default=str(DEFAULT_CHARUCO))
    estimate_parser.add_argument("--board-origin", choices=("center", "corner"), default=DEFAULT_BOARD_ORIGIN)
    estimate_parser.add_argument(
        "--xy-transform",
        choices=("orthogonal", "rigid"),
        default="orthogonal",
        help="Use orthogonal to allow X/Y swaps or mirror flips; rigid preserves handedness.",
    )
    estimate_parser.set_defaults(func=estimate)
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
