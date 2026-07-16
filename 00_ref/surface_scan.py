# VL53L0X based surface scanning support
#
# This file may be distributed under the terms of the GNU GPLv3 license.
import json, math, os, re, time


def _parse_coord(gcmd, name):
    try:
        values = [float(v.strip()) for v in gcmd.get(name).split(',')]
    except:
        raise gcmd.error("Unable to parse parameter '%s'" % (name,))
    if len(values) != 2:
        raise gcmd.error("Parameter '%s' must be in x,y form" % (name,))
    return values[0], values[1]


def _sanitize_profile_name(name):
    name = name.strip()
    if not name:
        return time.strftime("surface-%Y%m%d-%H%M%S")
    name = re.sub(r"[^A-Za-z0-9_.-]+", "_", name)
    return name.strip("._") or time.strftime("surface-%Y%m%d-%H%M%S")


def _gen_axis_points(start, end, spacing):
    if end < start:
        start, end = end, start
    count = int(math.floor((end - start) / spacing + 1e-9)) + 1
    points = [round(start + i * spacing, 6) for i in range(count)]
    if not points or abs(points[-1] - end) > 1e-6:
        points.append(round(end, 6))
    return points


def generate_scan_points(area_min, area_max, spacing):
    x_points = _gen_axis_points(area_min[0], area_max[0], spacing)
    y_points = _gen_axis_points(area_min[1], area_max[1], spacing)
    points = []
    for row, y in enumerate(y_points):
        row_x = x_points if row % 2 == 0 else list(reversed(x_points))
        for x in row_x:
            points.append((x, y))
    return x_points, y_points, points


class SurfaceScan:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.sensor_name = config.get('sensor')
        self.x_offset = config.getfloat('x_offset', 0.)
        self.y_offset = config.getfloat('y_offset', 0.)
        self.z_offset = config.getfloat('z_offset', 0.)
        self.default_spacing = config.getfloat(
            'default_spacing', 3., above=0.)
        self.default_samples = config.getint(
            'default_samples', 5, minval=1)
        self.default_scan_z = config.getfloat('default_scan_z', 30.)
        self.speed = config.getfloat('speed', 80., above=0.)
        self.lift_speed = config.getfloat('lift_speed', 30., above=0.)
        self.sample_delay = config.getfloat(
            'sample_delay', 0.03, minval=0.)
        self.settle_time = config.getfloat('settle_time', 0.05, minval=0.)
        self.min_distance = config.getfloat('min_distance', 1., minval=0.)
        self.max_distance = config.getfloat('max_distance', 2000.,
                                            above=0.)
        self.warmup_samples = config.getint('warmup_samples', 1, minval=0)
        self.max_valid_status = config.getint('max_valid_status', 0, minval=0)
        self.max_consecutive_failures = config.getint(
            'max_consecutive_failures', 10, minval=1)
        default_dir = '~/printer_data/config/surface_scans'
        self.output_dir = os.path.expanduser(config.get('output_dir',
                                                        default_dir))
        self.last_scan = None
        self.scan_progress = {
            'active': False,
            'profile': None,
            'current': 0,
            'total': 0,
            'remaining': 0,
            'percent': 0,
            'updated': None,
        }

        gcode = self.printer.lookup_object('gcode')
        gcode.register_command('SURFACE_SCAN', self.cmd_SURFACE_SCAN,
                               desc=self.cmd_SURFACE_SCAN_help)
        webhooks = self.printer.lookup_object('webhooks')
        webhooks.register_endpoint("surface_scan/list",
                                   self._handle_list_request)
        webhooks.register_endpoint("surface_scan/get",
                                   self._handle_get_request)
        webhooks.register_endpoint("surface_scan/progress",
                                   self._handle_progress_request)

    def _lookup_sensor(self, gcmd, sensor_name=None):
        sensor_name = sensor_name or self.sensor_name
        sensor = self.printer.lookup_object("vl53l0x " + sensor_name, None)
        if sensor is None:
            raise gcmd.error("Unable to find [vl53l0x %s]" % (sensor_name,))
        if not hasattr(sensor, "read_distance"):
            raise gcmd.error("VL53L0X sensor does not support read_distance")
        return sensor_name, sensor

    def _get_kin_status(self):
        toolhead = self.printer.lookup_object('toolhead')
        eventtime = self.printer.get_reactor().monotonic()
        return toolhead.get_kinematics().get_status(eventtime)

    def _check_homed(self, gcmd):
        kin_status = self._get_kin_status()
        homed_axes = kin_status.get('homed_axes', '')
        for axis in 'xyz':
            if axis not in homed_axes:
                raise gcmd.error("Must home X, Y, and Z before SURFACE_SCAN")
        return kin_status

    def _check_move_bounds(self, gcmd, points, scan_z, kin_status):
        axis_min = kin_status['axis_minimum']
        axis_max = kin_status['axis_maximum']
        move_points = [(x - self.x_offset, y - self.y_offset)
                       for x, y in points]
        xs = [p[0] for p in move_points]
        ys = [p[1] for p in move_points]
        if (min(xs) < axis_min[0] or max(xs) > axis_max[0]
            or min(ys) < axis_min[1] or max(ys) > axis_max[1]):
            raise gcmd.error(
                "SURFACE_SCAN area plus sensor offsets exceeds XY limits")
        if scan_z < axis_min[2] or scan_z > axis_max[2]:
            raise gcmd.error("SURFACE_SCAN Z is outside printer Z limits")

    def _move_and_wait(self, coord, speed):
        toolhead = self.printer.lookup_object('toolhead')
        toolhead.manual_move(coord, speed)
        toolhead.wait_moves()
        if self.settle_time > 0.:
            toolhead.dwell(self.settle_time)

    def _validate_reading(self, reading):
        distance = reading['distance_mm']
        raw_distance = reading.get('raw_mm', distance)
        if raw_distance >= 8190 or distance >= 8190:
            return False, "range overflow distance %smm raw %smm" % (
                distance, raw_distance)
        if distance < self.min_distance or distance > self.max_distance:
            return False, "distance %smm outside %.3f..%.3fmm" % (
                distance, self.min_distance, self.max_distance)
        if reading['status'] > self.max_valid_status:
            return False, "range status %s" % (reading['status'],)
        return True, None

    def _write_csv(self, filename, results):
        with open(filename, "w") as f:
            f.write("x,y,z,distance_mm,raw_mm,status,sigma\n")
            for point in results:
                f.write(
                    "%s,%s,%s,%s,%s,%s,%s\n" % (
                        self._fmt_optional(point['x']),
                        self._fmt_optional(point['y']),
                        self._fmt_optional(point['z']),
                        self._fmt_optional(point['distance_mm']),
                        self._fmt_optional(point['raw_mm']),
                        self._fmt_optional(point['status']),
                        self._fmt_optional(point['sigma'])
                    )
                )

    def _fmt_optional(self, value):
        if value is None:
            return ""
        if isinstance(value, float):
            return "%.6f" % (value,)
        return str(value)

    def _write_json(self, filename, payload):
        with open(filename, "w") as f:
            json.dump(payload, f, indent=2, sort_keys=True)
            f.write("\n")

    def _profile_to_paths(self, profile):
        profile = _sanitize_profile_name(profile)
        return (profile, os.path.join(self.output_dir, profile + ".json"),
                os.path.join(self.output_dir, profile + ".csv"))

    def _load_scan_file(self, json_path):
        with open(json_path, "r") as f:
            payload = json.load(f)
        payload["summary"] = self._build_summary(payload)
        return payload

    def _build_summary(self, payload):
        points = payload.get("points", [])
        valid_points = [p for p in points
                        if p.get("valid", True) and p.get("z") is not None]
        z_values = [p["z"] for p in valid_points]
        summary = {
            "point_count": len(points),
            "valid_count": len(valid_points),
            "invalid_count": len(points) - len(valid_points),
            "z_min": None,
            "z_max": None,
            "z_range": None,
        }
        if z_values:
            z_min = min(z_values)
            z_max = max(z_values)
            summary.update({
                "z_min": z_min,
                "z_max": z_max,
                "z_range": z_max - z_min,
            })
        return summary

    def _iter_scan_profiles(self):
        if not os.path.isdir(self.output_dir):
            return []
        profiles = []
        for filename in os.listdir(self.output_dir):
            if not filename.endswith(".json"):
                continue
            if filename.startswith("_"):
                continue
            json_path = os.path.join(self.output_dir, filename)
            if not os.path.isfile(json_path):
                continue
            profile = filename[:-5]
            csv_path = os.path.join(self.output_dir, profile + ".csv")
            try:
                modified = os.path.getmtime(json_path)
                payload = self._load_scan_file(json_path)
                summary = payload.get("summary", {})
                profile = payload.get("profile", profile)
            except Exception:
                modified = os.path.getmtime(json_path)
                summary = {}
            profiles.append({
                "profile": profile,
                "json_path": json_path,
                "csv_path": csv_path if os.path.exists(csv_path) else None,
                "modified": modified,
                "point_count": summary.get("point_count", 0),
                "invalid_count": summary.get("invalid_count", 0),
            })
        profiles.sort(key=lambda p: p["modified"], reverse=True)
        return profiles

    def _handle_list_request(self, web_request):
        profiles = self._iter_scan_profiles()
        latest = profiles[0]["profile"] if profiles else None
        web_request.send({"profiles": profiles, "latest": latest})

    def _handle_get_request(self, web_request):
        profile = web_request.get_str("PROFILE", None)
        profiles = self._iter_scan_profiles()
        if profile is None:
            if not profiles:
                raise web_request.error("No surface scan profiles found")
            profile = profiles[0]["profile"]
        profile, json_path, csv_path = self._profile_to_paths(profile)
        if not os.path.isfile(json_path):
            raise web_request.error(
                "Surface scan profile '%s' was not found" % (profile,))
        payload = self._load_scan_file(json_path)
        payload["json_path"] = json_path
        payload["csv_path"] = csv_path if os.path.exists(csv_path) else None
        web_request.send(payload)

    def _update_progress(self, profile, current, total, active=True):
        total = max(0, int(total))
        current = max(0, min(int(current), total))
        remaining = max(0, total - current)
        percent = int(round(current * 100. / total)) if total else 0
        self.scan_progress = {
            'active': bool(active),
            'profile': profile,
            'current': current,
            'total': total,
            'remaining': remaining,
            'percent': percent,
            'updated': time.time(),
        }
        return self.scan_progress

    def _handle_progress_request(self, web_request):
        web_request.send(dict(self.scan_progress))

    def _record_invalid(self, point, error=None, reading=None):
        entry = {
            'x': point[0],
            'y': point[1],
            'z': None,
            'distance_mm': None,
            'raw_mm': None,
            'status': None,
            'sigma': None,
            'valid': False,
            'error': error,
        }
        if reading is not None:
            entry.update({
                'distance_mm': reading.get('distance_mm'),
                'raw_mm': reading.get('raw_mm'),
                'status': reading.get('status'),
                'sigma': reading.get('sigma'),
                'samples': reading.get('samples', []),
                'raw_samples': reading.get('raw_samples', []),
                'statuses': reading.get('statuses', []),
            })
        return entry

    cmd_SURFACE_SCAN_help = "Scan surface shape using a VL53L0X distance sensor"
    def cmd_SURFACE_SCAN(self, gcmd):
        sensor_name = gcmd.get('SENSOR', self.sensor_name)
        sensor_name, sensor = self._lookup_sensor(gcmd, sensor_name)
        area_min = _parse_coord(gcmd, 'AREA_MIN')
        area_max = _parse_coord(gcmd, 'AREA_MAX')
        spacing = gcmd.get_float('SPACING', self.default_spacing, above=0.)
        samples = gcmd.get_int('SAMPLES', self.default_samples, minval=1)
        scan_z = gcmd.get_float('Z', self.default_scan_z)
        profile = _sanitize_profile_name(gcmd.get('PROFILE', ''))
        result_method = gcmd.get('RESULT', 'median').lower()

        x_points, y_points, points = generate_scan_points(
            area_min, area_max, spacing)
        kin_status = self._check_homed(gcmd)
        self._check_move_bounds(gcmd, points, scan_z, kin_status)

        os.makedirs(self.output_dir, exist_ok=True)
        csv_path = os.path.join(self.output_dir, profile + ".csv")
        json_path = os.path.join(self.output_dir, profile + ".json")
        progress_path = os.path.join(self.output_dir, "_scan_progress.json")

        gcmd.respond_info(
            "Surface scan '%s': %d points, spacing %.3fmm, z %.3f"
            % (profile, len(points), spacing, scan_z))

        results = []
        invalid_points = []
        consecutive_failures = 0
        start_time = time.time()
        total_points = len(points)
        report_interval = max(1, total_points // 20)

        def _report_progress(current):
            self._update_progress(profile, current, total_points, True)
            data = {'c': current, 't': total_points, 'p': profile, 's': True}
            gcmd.respond_info(
                "SURFACE_SCAN_PROGRESS:" + json.dumps(data))
            try:
                with open(progress_path, "w") as f:
                    json.dump(data, f)
            except Exception:
                pass

        _report_progress(0)
        self._move_and_wait([None, None, scan_z], self.lift_speed)
        scan_loop_complete = False
        try:
            for index, point in enumerate(points):
                sensor_x, sensor_y = point
                move_x = sensor_x - self.x_offset
                move_y = sensor_y - self.y_offset
                self._move_and_wait([move_x, move_y, scan_z], self.speed)
                try:
                    if index == 0 and self.warmup_samples:
                        sensor.read_distance(
                            samples=self.warmup_samples,
                            sample_delay=self.sample_delay,
                            result=result_method)
                    reading = sensor.read_distance(
                        samples=samples, sample_delay=self.sample_delay,
                        result=result_method)
                    surface_z = scan_z + self.z_offset - reading['distance_mm']
                    valid, error = self._validate_reading(reading)
                    entry = {
                        'index': index,
                        'x': sensor_x,
                        'y': sensor_y,
                        'z': surface_z,
                        'toolhead_x': move_x,
                        'toolhead_y': move_y,
                        'toolhead_z': scan_z,
                        'distance_mm': reading['distance_mm'],
                        'raw_mm': reading['raw_mm'],
                        'status': reading['status'],
                        'sigma': reading['sigma'],
                        'mean_mm': reading.get('mean_mm'),
                        'min_mm': reading.get('min_mm'),
                        'max_mm': reading.get('max_mm'),
                        'samples': reading.get('samples', []),
                        'raw_samples': reading.get('raw_samples', []),
                        'statuses': reading.get('statuses', []),
                        'valid': valid,
                    }
                    if valid:
                        consecutive_failures = 0
                    else:
                        consecutive_failures += 1
                        entry['z'] = None
                        entry['error'] = error
                        invalid_points.append(entry)
                    results.append(entry)
                except Exception as e:
                    consecutive_failures += 1
                    entry = self._record_invalid(point, str(e))
                    entry['index'] = index
                    entry['toolhead_x'] = move_x
                    entry['toolhead_y'] = move_y
                    entry['toolhead_z'] = scan_z
                    results.append(entry)
                    invalid_points.append(entry)
                if (index + 1) % report_interval == 0:
                    _report_progress(index + 1)
                if consecutive_failures >= self.max_consecutive_failures:
                    raise gcmd.error(
                        "SURFACE_SCAN stopped after %d consecutive invalid"
                        " points" % (consecutive_failures,))
            scan_loop_complete = True
        finally:
            # Always clean up the progress file
            try:
                os.remove(progress_path)
            except Exception:
                pass
            if not scan_loop_complete:
                self._update_progress(profile, len(results), total_points,
                                      False)

        toolhead = self.printer.lookup_object('toolhead')
        toolhead.get_last_move_time()
        finish_time = time.time()
        payload = {
            'profile': profile,
            'sensor': sensor_name,
            'created_at': time.strftime("%Y-%m-%dT%H:%M:%S%z",
                                        time.localtime(start_time)),
            'duration_s': finish_time - start_time,
            'area_min': list(area_min),
            'area_max': list(area_max),
            'spacing': spacing,
            'scan_z': scan_z,
            'samples': samples,
            'sample_delay': self.sample_delay,
            'settle_time': self.settle_time,
            'warmup_samples': self.warmup_samples,
            'min_distance': self.min_distance,
            'max_distance': self.max_distance,
            'result_method': result_method,
            'max_valid_status': self.max_valid_status,
            'offsets': {
                'x': self.x_offset,
                'y': self.y_offset,
                'z': self.z_offset,
            },
            'grid': {
                'x_count': len(x_points),
                'y_count': len(y_points),
                'x_points': x_points,
                'y_points': y_points,
            },
            'points': results,
            'invalid_points': invalid_points,
            'csv_path': csv_path,
            'json_path': json_path,
        }
        self._write_csv(csv_path, results)
        self._write_json(json_path, payload)
        self.last_scan = payload
        self._update_progress(profile, total_points, total_points, False)
        gcmd.respond_info(
            "SURFACE_SCAN_COMPLETE:" + json.dumps({
                'p': profile,
                'v': len(results) - len(invalid_points),
                'i': len(invalid_points),
            }))
        gcmd.respond_info(
            "Surface scan complete: %d valid, %d invalid\nCSV: %s\nJSON: %s"
            % (len(results) - len(invalid_points), len(invalid_points),
               csv_path, json_path))

    def get_status(self, eventtime):
        progress = dict(self.scan_progress)
        if self.last_scan is None:
            return {
                'last_profile': None,
                'progress': progress,
            }
        return {
            'last_profile': self.last_scan['profile'],
            'last_csv_path': self.last_scan['csv_path'],
            'last_json_path': self.last_scan['json_path'],
            'last_point_count': len(self.last_scan['points']),
            'last_invalid_count': len(self.last_scan['invalid_points']),
            'progress': progress,
        }


def load_config(config):
    return SurfaceScan(config)
