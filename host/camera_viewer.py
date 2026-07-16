import os
import socket
import threading
import time
from collections import deque

import paramiko
from flask import Flask, Response, render_template_string, request


HOST = os.getenv("CAMERA_SSH_HOST", "192.168.67.182")
USER = os.getenv("CAMERA_SSH_USER", "umeko")
PASSWORD = os.getenv("CAMERA_SSH_PASSWORD", "1234")
DEVICE = os.getenv("CAMERA_DEVICE", "")
WIDTH = int(os.getenv("CAMERA_WIDTH", "640"))
HEIGHT = int(os.getenv("CAMERA_HEIGHT", "480"))
INPUT_FPS = int(os.getenv("CAMERA_INPUT_FPS", "10"))
FPS = int(os.getenv("CAMERA_FPS", "3"))
JPEG_QUALITY = int(os.getenv("CAMERA_JPEG_QUALITY", "6"))
REENCODE = os.getenv("CAMERA_REENCODE", "1") != "0"
INPUT_FORMATS = [
    value.strip()
    for value in os.getenv("CAMERA_INPUT_FORMATS", "yuyv422,mjpeg").split(",")
    if value.strip()
]
PORT = int(os.getenv("CAMERA_VIEWER_PORT", "8765"))
RESET_USB_ON_START = os.getenv("CAMERA_RESET_USB_ON_START", "0") != "0"
CAMERA_NAME = os.getenv("CAMERA_NAME", "LRCP USB2.0")
SNAPSHOT_TIMEOUT = float(os.getenv("CAMERA_SNAPSHOT_TIMEOUT", "8.0"))
STREAM_IDLE_TIMEOUT = float(os.getenv("CAMERA_STREAM_IDLE_TIMEOUT", "8.0"))
DIRECT_CAPTURE_TIMEOUT = float(os.getenv("CAMERA_DIRECT_CAPTURE_TIMEOUT", "8.0"))
DIRECT_CAPTURE_FRAMES = int(os.getenv("CAMERA_DIRECT_CAPTURE_FRAMES", "1"))
DIRECT_CAPTURE_RELEASE_TIMEOUT = float(os.getenv("CAMERA_DIRECT_CAPTURE_RELEASE_TIMEOUT", "3.0"))
DIRECT_CAPTURE_RETRIES = int(os.getenv("CAMERA_DIRECT_CAPTURE_RETRIES", "2"))

app = Flask(__name__)


PAGE = """
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>USB Camera Preview</title>
  <style>
    :root {
      color-scheme: dark;
      font-family: "Segoe UI", Arial, sans-serif;
      background: #101316;
      color: #f3f6f8;
    }
    * { box-sizing: border-box; }
    body {
      min-height: 100vh;
      margin: 0;
      display: grid;
      grid-template-rows: auto 1fr;
      background: #101316;
    }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      padding: 14px 18px;
      border-bottom: 1px solid #2a3138;
      background: #171c21;
    }
    h1 {
      margin: 0;
      font-size: 16px;
      font-weight: 650;
      letter-spacing: 0;
    }
    .meta {
      color: #aeb8c2;
      font-size: 13px;
      white-space: nowrap;
    }
    main {
      min-height: 0;
      display: grid;
      place-items: center;
      padding: 18px;
    }
    .stage {
      width: min(100%, 1100px);
      aspect-ratio: 4 / 3;
      display: grid;
      place-items: center;
      background: #050607;
      border: 1px solid #303840;
      border-radius: 8px;
      overflow: hidden;
    }
    img {
      width: 100%;
      height: 100%;
      object-fit: contain;
      display: block;
    }
    @media (max-width: 620px) {
      header {
        align-items: flex-start;
        flex-direction: column;
      }
      .meta { white-space: normal; }
      main { padding: 10px; }
    }
  </style>
</head>
<body>
  <header>
    <h1>LRCP USB2.0 Camera</h1>
    <div class="meta">{{ user }}@{{ host }} {{ device }} - {{ width }}x{{ height }} @ {{ fps }}fps</div>
  </header>
  <main>
    <div class="stage">
      <img src="/stream" alt="camera stream">
    </div>
  </main>
</body>
</html>
"""


def open_ssh_client():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        HOST,
        username=USER,
        password=PASSWORD,
        timeout=10,
        look_for_keys=False,
        allow_agent=False,
    )
    return client


def run_remote(client, command, timeout=10):
    _, stdout, stderr = client.exec_command(command, timeout=timeout)
    code = stdout.channel.recv_exit_status()
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    return code, out, err


def cleanup_remote_camera(client):
    run_remote(
        client,
        "pkill -9 -x ffmpeg 2>/dev/null; pkill -9 -x v4l2-ctl 2>/dev/null; true",
        timeout=5,
    )


def wait_remote_camera_release(client, timeout=DIRECT_CAPTURE_RELEASE_TIMEOUT):
    deadline = time.time() + timeout
    while True:
        _, out, _ = run_remote(
            client,
            "pgrep -x ffmpeg >/dev/null 2>&1; echo $?",
            timeout=3,
        )
        if out.strip().endswith("1"):
            return True
        if time.time() >= deadline:
            return False
        cleanup_remote_camera(client)
        time.sleep(0.2)


def reset_usb_camera(client):
    if not RESET_USB_ON_START:
        return
    command = (
        "printf '%s\\n' " + sh_quote(PASSWORD) + " | sudo -S sh -c "
        "'echo 1-1.3 > /sys/bus/usb/drivers/usb/unbind'; "
        "sleep 2; "
        "printf '%s\\n' " + sh_quote(PASSWORD) + " | sudo -S sh -c "
        "'echo 1-1.3 > /sys/bus/usb/drivers/usb/bind'; "
        "sleep 4"
    )
    run_remote(client, command, timeout=20)


def sh_quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"


def extract_jpegs(payload):
    frames = []
    offset = 0
    while True:
        start = payload.find(b"\xff\xd8", offset)
        if start < 0:
            break
        end = payload.find(b"\xff\xd9", start + 2)
        if end < 0:
            break
        end += 2
        frames.append(payload[start:end])
        offset = end
    return frames


def run_remote_bytes(client, command, timeout):
    channel = client.get_transport().open_session()
    channel.settimeout(1.0)
    channel.exec_command(command)
    stdout = bytearray()
    stderr = bytearray()
    deadline = time.time() + timeout
    try:
        while True:
            if channel.recv_ready():
                stdout.extend(channel.recv(65536))
            if channel.recv_stderr_ready():
                stderr.extend(channel.recv_stderr(65536))
            if channel.exit_status_ready():
                while channel.recv_ready():
                    stdout.extend(channel.recv(65536))
                while channel.recv_stderr_ready():
                    stderr.extend(channel.recv_stderr(65536))
                return channel.recv_exit_status(), bytes(stdout), stderr.decode("utf-8", "replace")
            if time.time() > deadline:
                raise TimeoutError(f"remote command timed out after {timeout:.1f}s")
            time.sleep(0.02)
    finally:
        channel.close()


def run_remote_jpegs(client, command, min_frames, timeout):
    channel = client.get_transport().open_session()
    channel.settimeout(1.0)
    channel.exec_command(command)
    stdout = bytearray()
    stderr = bytearray()
    deadline = time.time() + timeout
    try:
        while True:
            if channel.recv_ready():
                stdout.extend(channel.recv(65536))
                frames = extract_jpegs(stdout)
                if len(frames) >= min_frames:
                    return 0, frames, stderr.decode("utf-8", "replace")
            if channel.recv_stderr_ready():
                stderr.extend(channel.recv_stderr(65536))
            if channel.exit_status_ready():
                while channel.recv_ready():
                    stdout.extend(channel.recv(65536))
                while channel.recv_stderr_ready():
                    stderr.extend(channel.recv_stderr(65536))
                return channel.recv_exit_status(), extract_jpegs(stdout), stderr.decode("utf-8", "replace")
            if time.time() > deadline:
                raise TimeoutError(f"remote jpeg capture timed out after {timeout:.1f}s")
            time.sleep(0.02)
    finally:
        channel.close()


def detect_camera_device(client):
    if DEVICE:
        return DEVICE
    code, out, err = run_remote(client, "v4l2-ctl --list-devices 2>/dev/null || true", timeout=5)
    lines = out.splitlines()
    for index, line in enumerate(lines):
        if CAMERA_NAME.lower() not in line.lower():
            continue
        for candidate in lines[index + 1 : index + 8]:
            candidate = candidate.strip()
            if candidate.startswith("/dev/video"):
                return candidate
    raise RuntimeError(f"Camera device containing {CAMERA_NAME!r} not found")


def ffmpeg_input_args(device, input_format, input_fps):
    format_arg = f"-input_format {input_format} " if input_format else ""
    return (
        f"-f v4l2 -thread_queue_size 1 {format_arg}"
        f"-framerate {input_fps} -video_size {WIDTH}x{HEIGHT} -i {device}"
    )


def input_fps_for_format(input_format):
    if input_format == "yuyv422" and WIDTH == 640 and HEIGHT == 480:
        return 30
    return INPUT_FPS if REENCODE else FPS


def v4l2_mjpeg_stream_command(device):
    return (
        "v4l2-ctl "
        f"-d {device} "
        f"--set-fmt-video=width={WIDTH},height={HEIGHT},pixelformat=MJPG "
        "--stream-mmap=3 --stream-to=-"
    )


def open_mpjpeg_channel(client, device, input_format):
    if input_format == "mjpeg":
        command = v4l2_mjpeg_stream_command(device)
        channel = client.get_transport().open_session()
        channel.settimeout(1.0)
        channel.exec_command(command)
        return channel
    input_fps = input_fps_for_format(input_format)
    if REENCODE:
        output_args = f"-vf fps={FPS} -c:v mjpeg -q:v {JPEG_QUALITY}"
    else:
        output_args = "-c:v copy"
    command = (
        "ffmpeg -hide_banner -nostdin -loglevel error "
        "-fflags nobuffer -flags low_delay -avioflags direct "
        f"{ffmpeg_input_args(device, input_format, input_fps)} "
        f"-an {output_args} -flush_packets 1 -f mpjpeg -"
    )
    channel = client.get_transport().open_session()
    channel.settimeout(1.0)
    channel.exec_command(command)
    return channel


class CameraHub:
    def __init__(self):
        self.lock = threading.Lock()
        self.new_frame = threading.Condition(self.lock)
        self.direct_lock = threading.Lock()
        self.started = False
        self.suspend_stream = False
        self.active_channel = None
        self.frame = None
        self.frame_id = 0
        self.last_frame_at = None
        self.last_error = None
        self.frame_times = deque(maxlen=60)
        self.device = DEVICE

    def start(self):
        with self.lock:
            if self.started:
                return
            self.started = True
        thread = threading.Thread(target=self._run, name="camera-hub", daemon=True)
        thread.start()

    def _set_error(self, error):
        with self.lock:
            self.frame = None
            self.last_error = str(error)
            self.new_frame.notify_all()

    def _set_frame(self, frame):
        with self.lock:
            self.frame = frame
            self.frame_id += 1
            self.last_frame_at = time.time()
            self.frame_times.append(self.last_frame_at)
            self.last_error = None
            self.new_frame.notify_all()

    def _set_active_channel(self, channel):
        with self.lock:
            self.active_channel = channel

    def _clear_active_channel(self, channel):
        with self.lock:
            if self.active_channel is channel:
                self.active_channel = None

    def _pause_stream(self):
        with self.lock:
            self.suspend_stream = True
            channel = self.active_channel
            self.frame = None
            self.last_error = "stream paused for direct snapshot"
            self.new_frame.notify_all()
        if channel is not None:
            try:
                channel.close()
            except Exception:
                pass

    def _resume_stream(self):
        with self.lock:
            self.suspend_stream = False
            self.new_frame.notify_all()

    def _run(self):
        first_start = True
        while True:
            client = None
            channel = None
            try:
                with self.lock:
                    if self.suspend_stream:
                        self.new_frame.wait_for(lambda: not self.suspend_stream, timeout=0.5)
                        continue
                client = open_ssh_client()
                cleanup_remote_camera(client)
                if first_start:
                    reset_usb_camera(client)
                    first_start = False
                time.sleep(1.0)
                self.device = detect_camera_device(client)
                errors = []
                for input_format in INPUT_FORMATS:
                    channel = open_mpjpeg_channel(client, self.device, input_format)
                    self._set_active_channel(channel)
                    try:
                        self._read_frames(channel)
                        raise RuntimeError("remote ffmpeg stream ended")
                    except Exception as exc:
                        errors.append(f"{input_format}: {exc}")
                    finally:
                        try:
                            channel.close()
                        except Exception:
                            pass
                        self._clear_active_channel(channel)
                        channel = None
                raise RuntimeError("; ".join(errors) or "no camera input formats configured")
            except Exception as exc:
                self._set_error(exc)
                print(f"camera hub error: {exc}", flush=True)
                time.sleep(2.0)
            finally:
                if channel is not None:
                    try:
                        channel.close()
                    except Exception:
                        pass
                    self._clear_active_channel(channel)
                if client is not None:
                    try:
                        cleanup_remote_camera(client)
                    except Exception:
                        pass
                    client.close()

    def _read_frames(self, channel):
        buffer = bytearray()
        stderr = bytearray()
        last_data_at = time.time()
        last_frame_at = time.time()
        last_published_at = 0.0
        min_publish_interval = 1.0 / max(FPS, 1)
        while True:
            if channel.recv_stderr_ready():
                stderr.extend(channel.recv_stderr(65536))
            try:
                chunk = channel.recv(65536)
            except socket.timeout:
                if channel.recv_stderr_ready():
                    stderr.extend(channel.recv_stderr(65536))
                if channel.exit_status_ready():
                    break
                now = time.time()
                idle_for = now - max(last_data_at, last_frame_at)
                if idle_for > STREAM_IDLE_TIMEOUT:
                    detail = stderr.decode("utf-8", "replace").strip()
                    if detail:
                        raise RuntimeError(f"remote stream idle for {idle_for:.1f}s; ffmpeg: {detail}")
                    raise RuntimeError(f"remote stream idle for {idle_for:.1f}s")
                continue
            if not chunk:
                break

            last_data_at = time.time()
            buffer.extend(chunk)
            while True:
                start = buffer.find(b"\xff\xd8")
                if start < 0:
                    if len(buffer) > 1048576:
                        buffer.clear()
                    break
                end = buffer.find(b"\xff\xd9", start + 2)
                if end < 0:
                    if start:
                        del buffer[:start]
                    break
                end += 2
                frame = bytes(buffer[start:end])
                del buffer[:end]
                last_frame_at = time.time()
                if last_frame_at - last_published_at < min_publish_interval:
                    continue
                last_published_at = last_frame_at
                self._set_frame(frame)
        if stderr:
            detail = stderr.decode("utf-8", "replace").strip()
            if detail:
                raise RuntimeError(f"remote ffmpeg stream ended: {detail}")

    def frames(self):
        self.start()
        last_seen = -1
        while True:
            with self.lock:
                self.new_frame.wait_for(lambda: self.frame_id != last_seen, timeout=10)
                if self.frame is None:
                    continue
                frame = self.frame
                last_seen = self.frame_id
            yield (
                b"--frame\r\n"
                b"Content-Type: image/jpeg\r\n"
                b"Content-Length: " + str(len(frame)).encode("ascii") + b"\r\n\r\n"
                + frame
                + b"\r\n"
            )

    def snapshot(self, require_fresh=True, timeout=SNAPSHOT_TIMEOUT):
        self.start()
        with self.lock:
            start_id = self.frame_id
            if require_fresh:
                self.new_frame.wait_for(lambda: self.frame is not None and self.frame_id > start_id, timeout=timeout)
                if self.frame is None or self.frame_id <= start_id:
                    return None, start_id, self.frame_id, None
            else:
                self.new_frame.wait_for(lambda: self.frame is not None, timeout=15)
                if self.frame is None:
                    return None, start_id, self.frame_id, None
            frame_age = None if self.last_frame_at is None else time.time() - self.last_frame_at
            return self.frame, start_id, self.frame_id, frame_age

    def snapshot_direct(self):
        with self.direct_lock:
            self._pause_stream()
            client = None
            started_at = time.time()
            try:
                time.sleep(0.5)
                client = open_ssh_client()
                cleanup_remote_camera(client)
                wait_remote_camera_release(client)
                self.device = detect_camera_device(client)
                attempts = max(DIRECT_CAPTURE_RETRIES, 1)
                target_frames = max(DIRECT_CAPTURE_FRAMES, 1)
                frames = []
                errors = []
                for input_format in INPUT_FORMATS:
                    input_fps = input_fps_for_format(input_format)
                    command = (
                        "ffmpeg -hide_banner -nostdin -loglevel error "
                        f"{ffmpeg_input_args(self.device, input_format, input_fps)} -an "
                        "-c:v mjpeg -frames:v "
                        f"{target_frames} -f image2pipe -"
                    )
                    for attempt in range(attempts):
                        code, frames, err = run_remote_jpegs(
                            client,
                            command,
                            min_frames=target_frames,
                            timeout=DIRECT_CAPTURE_TIMEOUT,
                        )
                        if code == 0 and frames:
                            break
                        detail = err.strip() or f"ffmpeg exit={code}, frames={len(frames)}"
                        errors.append(f"{input_format}: {detail}")
                        if "Device or resource busy" not in detail or attempt == attempts - 1:
                            break
                        cleanup_remote_camera(client)
                        wait_remote_camera_release(client)
                        time.sleep(0.5)
                    if frames:
                        break
                if not frames:
                    raise RuntimeError(f"direct snapshot failed: {'; '.join(errors)}")
                frame = frames[-1]
                with self.lock:
                    self.frame = frame
                    self.frame_id += 1
                    self.last_frame_at = time.time()
                    self.frame_times.append(self.last_frame_at)
                    self.last_error = None
                    self.new_frame.notify_all()
                    frame_id = self.frame_id
                    frame_age = time.time() - self.last_frame_at
                return frame, frame_id, frame_age, len(frames), time.time() - started_at
            finally:
                if client is not None:
                    try:
                        cleanup_remote_camera(client)
                    except Exception:
                        pass
                    client.close()
                with self.lock:
                    self.suspend_stream = False
                    self.new_frame.notify_all()

    def status(self):
        with self.lock:
            age = None if self.last_frame_at is None else round(time.time() - self.last_frame_at, 2)
            received_fps = 0.0
            if len(self.frame_times) >= 2:
                span = self.frame_times[-1] - self.frame_times[0]
                if span > 0:
                    received_fps = (len(self.frame_times) - 1) / span
            max_frame_age = max(STREAM_IDLE_TIMEOUT, 2.0 / max(FPS, 1))
            stream_alive = self.frame is not None and age is not None and age <= max_frame_age
            return {
                "ok": stream_alive and self.last_error is None,
                "host": HOST,
                "device": self.device,
                "camera_name": CAMERA_NAME,
                "width": WIDTH,
                "height": HEIGHT,
                "input_fps": INPUT_FPS,
                "requested_fps": FPS,
                "jpeg_quality": JPEG_QUALITY,
                "reencode": REENCODE,
                "input_formats": INPUT_FORMATS,
                "stream_idle_timeout_seconds": STREAM_IDLE_TIMEOUT,
                "direct_capture_timeout_seconds": DIRECT_CAPTURE_TIMEOUT,
                "direct_capture_frames": DIRECT_CAPTURE_FRAMES,
                "direct_capture_release_timeout_seconds": DIRECT_CAPTURE_RELEASE_TIMEOUT,
                "direct_capture_retries": DIRECT_CAPTURE_RETRIES,
                "frame_id": self.frame_id,
                "frame_age_seconds": age,
                "max_frame_age_seconds": round(max_frame_age, 2),
                "received_fps": round(received_fps, 2),
                "last_error": self.last_error,
            }


camera = CameraHub()


@app.get("/")
def index():
    return render_template_string(
        PAGE,
        host=HOST,
        user=USER,
        device=camera.device or DEVICE or CAMERA_NAME,
        width=WIDTH,
        height=HEIGHT,
        fps=FPS,
    )


@app.get("/stream")
def stream():
    return Response(
        camera.frames(),
        mimetype="multipart/x-mixed-replace; boundary=frame",
        headers={"Cache-Control": "no-store"},
    )


@app.get("/snapshot")
def snapshot():
    fresh_arg = request.args.get("fresh", "1").lower()
    require_fresh = fresh_arg not in {"0", "false", "no"}
    timeout = request.args.get("timeout", type=float) or SNAPSHOT_TIMEOUT
    frame, start_id, end_id, frame_age = camera.snapshot(require_fresh=require_fresh, timeout=timeout)
    if frame is None:
        return Response(
            f"fresh camera frame unavailable; start_id={start_id}, end_id={end_id}\n",
            status=503,
        )
    headers = {
        "Cache-Control": "no-store",
        "X-Camera-Start-Frame-Id": str(start_id),
        "X-Camera-Frame-Id": str(end_id),
    }
    if frame_age is not None:
        headers["X-Camera-Frame-Age-Seconds"] = f"{frame_age:.3f}"
    return Response(frame, mimetype="image/jpeg", headers=headers)


@app.get("/snapshot_direct")
def snapshot_direct():
    try:
        frame, frame_id, frame_age, captured_frames, elapsed = camera.snapshot_direct()
    except Exception as exc:
        return Response(f"{exc}\n", status=503)
    headers = {
        "Cache-Control": "no-store",
        "X-Camera-Frame-Id": str(frame_id),
        "X-Camera-Frame-Age-Seconds": f"{frame_age:.3f}",
        "X-Camera-Capture-Mode": "direct",
        "X-Camera-Captured-Frames": str(captured_frames),
        "X-Camera-Capture-Elapsed-Seconds": f"{elapsed:.3f}",
    }
    return Response(frame, mimetype="image/jpeg", headers=headers)


@app.get("/health")
def health():
    status = camera.status()
    code = 200 if status["ok"] else 503
    return status, code


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=PORT, threaded=True)
