# STL driven surface compensation support
#
# This file may be distributed under the terms of the GNU GPLv3 license.
import json, math, os, re, struct, time

EPSILON = 1.0e-9
AXIS_INDEX = {'x': 0, 'y': 1, 'z': 2}
PLANE_AXES = {
    'x': (1, 2),
    'y': (0, 2),
    'z': (0, 1),
}


def _sanitize_profile_name(name):
    name = (name or "").strip()
    if not name:
        return time.strftime("surface-model-%Y%m%d-%H%M%S")
    name = re.sub(r"[^\w_.-]+", "_", name, flags=re.UNICODE)
    return name.strip("._") or time.strftime("surface-model-%Y%m%d-%H%M%S")


def _expand_path(path):
    return os.path.abspath(os.path.expanduser(path))


def _median(values):
    values = sorted(values)
    middle = len(values) // 2
    if len(values) & 1:
        return values[middle]
    return (values[middle - 1] + values[middle]) / 2.


def _rms(values):
    if not values:
        return 0.
    return math.sqrt(sum([v * v for v in values]) / float(len(values)))


def _percentile(values, pct):
    if not values:
        return 0.
    values = sorted(values)
    index = int(round((len(values) - 1) * pct))
    return values[max(0, min(index, len(values) - 1))]


def _rotate_xy(x, y, theta):
    c = math.cos(theta)
    s = math.sin(theta)
    return x * c - y * s, x * s + y * c


def _inverse_transform_xy(x, y, dx, dy, theta):
    # machine = R(model) + offset, so model = R^-1(machine - offset)
    return _rotate_xy(x - dx, y - dy, -theta)


def _format_float(value):
    return "%.6f" % (value,)


def _normalize_axis(axis):
    axis = (axis or 'z').strip().lower()
    if axis not in AXIS_INDEX:
        raise STLModelError("HEIGHT_AXIS must be X, Y, or Z")
    return axis


class STLModelError(Exception):
    pass


class STLHeightModel:
    def __init__(self, triangles, cell_size=5., height_axis='z'):
        if not triangles:
            raise STLModelError("STL file contains no triangles")
        self.triangles = []
        self.cell_size = max(float(cell_size), 0.001)
        self.height_axis = _normalize_axis(height_axis)
        self.plane_axes = PLANE_AXES[self.height_axis]
        self._load_triangles(triangles)
        self._build_index()

    @staticmethod
    def from_file(path, cell_size=5., height_axis='z'):
        return STLHeightModel(_parse_stl_file(path), cell_size, height_axis)

    def _project_vertex(self, vertex):
        return (vertex[self.plane_axes[0]],
                vertex[self.plane_axes[1]],
                vertex[AXIS_INDEX[self.height_axis]])

    def _load_triangles(self, triangles):
        xs = []
        ys = []
        zs = []
        src_xs = []
        src_ys = []
        src_zs = []
        for tri in triangles:
            for sx, sy, sz in tri:
                src_xs.append(sx)
                src_ys.append(sy)
                src_zs.append(sz)
            v0, v1, v2 = [self._project_vertex(v) for v in tri]
            den = ((v1[1] - v2[1]) * (v0[0] - v2[0])
                   + (v2[0] - v1[0]) * (v0[1] - v2[1]))
            if abs(den) < EPSILON:
                # Triangles parallel to the height axis do not define height.
                continue
            txs = [v0[0], v1[0], v2[0]]
            tys = [v0[1], v1[1], v2[1]]
            tzs = [v0[2], v1[2], v2[2]]
            entry = {
                'verts': (v0, v1, v2),
                'den': den,
                'min_x': min(txs), 'max_x': max(txs),
                'min_y': min(tys), 'max_y': max(tys),
                'min_z': min(tzs), 'max_z': max(tzs),
            }
            self.triangles.append(entry)
            xs.extend(txs)
            ys.extend(tys)
            zs.extend(tzs)
        if not self.triangles:
            raise STLModelError("STL file has no non-vertical top faces")
        self.min_x = min(xs)
        self.max_x = max(xs)
        self.min_y = min(ys)
        self.max_y = max(ys)
        self.min_z = min(zs)
        self.max_z = max(zs)
        self.source_bounds = {
            'min_x': min(src_xs), 'max_x': max(src_xs),
            'min_y': min(src_ys), 'max_y': max(src_ys),
            'min_z': min(src_zs), 'max_z': max(src_zs),
        }

    def _cell_for(self, x, y):
        ix = int(math.floor((x - self.min_x) / self.cell_size))
        iy = int(math.floor((y - self.min_y) / self.cell_size))
        return ix, iy

    def _build_index(self):
        self.index = {}
        for idx, tri in enumerate(self.triangles):
            min_ix, min_iy = self._cell_for(tri['min_x'], tri['min_y'])
            max_ix, max_iy = self._cell_for(tri['max_x'], tri['max_y'])
            for ix in range(min_ix, max_ix + 1):
                for iy in range(min_iy, max_iy + 1):
                    self.index.setdefault((ix, iy), []).append(idx)

    def _triangle_z(self, tri, x, y):
        if (x < tri['min_x'] - EPSILON or x > tri['max_x'] + EPSILON
            or y < tri['min_y'] - EPSILON or y > tri['max_y'] + EPSILON):
            return None
        v0, v1, v2 = tri['verts']
        den = tri['den']
        a = ((v1[1] - v2[1]) * (x - v2[0])
             + (v2[0] - v1[0]) * (y - v2[1])) / den
        b = ((v2[1] - v0[1]) * (x - v2[0])
             + (v0[0] - v2[0]) * (y - v2[1])) / den
        c = 1. - a - b
        if a < -EPSILON or b < -EPSILON or c < -EPSILON:
            return None
        return a * v0[2] + b * v1[2] + c * v2[2]

    def calc_z(self, x, y, outside_policy="error"):
        qx, qy = x, y
        if outside_policy == "clamp":
            qx = min(self.max_x, max(self.min_x, qx))
            qy = min(self.max_y, max(self.min_y, qy))
        elif (qx < self.min_x - EPSILON or qx > self.max_x + EPSILON
              or qy < self.min_y - EPSILON or qy > self.max_y + EPSILON):
            if outside_policy == "passthrough":
                return None
            raise STLModelError(
                "XY %.3f,%.3f is outside STL bounds %.3f..%.3f, %.3f..%.3f"
                % (x, y, self.min_x, self.max_x, self.min_y, self.max_y))
        ix, iy = self._cell_for(qx, qy)
        candidates = self.index.get((ix, iy), [])
        best_z = None
        for tri_index in candidates:
            z = self._triangle_z(self.triangles[tri_index], qx, qy)
            if z is not None and (best_z is None or z > best_z):
                best_z = z
        if best_z is None:
            if outside_policy == "passthrough":
                return None
            raise STLModelError(
                "No STL surface found at XY %.3f,%.3f" % (x, y))
        return best_z

    def get_stats(self):
        return {
            'triangle_count': len(self.triangles),
            'min_x': self.min_x,
            'max_x': self.max_x,
            'min_y': self.min_y,
            'max_y': self.max_y,
            'min_z': self.min_z,
            'max_z': self.max_z,
            'cell_size': self.cell_size,
            'index_cell_count': len(self.index),
            'height_axis': self.height_axis.upper(),
            'plane_axes': [
                'XYZ'[self.plane_axes[0]],
                'XYZ'[self.plane_axes[1]],
            ],
            'source_bounds': self.source_bounds,
        }


def _parse_stl_file(path):
    path = _expand_path(path)
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 15:
        raise STLModelError("STL file is too small: %s" % (path,))
    if _looks_like_binary_stl(data):
        return _parse_binary_stl(data)
    return _parse_ascii_stl(data)


def _looks_like_binary_stl(data):
    if len(data) < 84:
        return False
    tri_count = struct.unpack_from("<I", data, 80)[0]
    expected = 84 + tri_count * 50
    return expected == len(data)


def _parse_binary_stl(data):
    tri_count = struct.unpack_from("<I", data, 80)[0]
    offset = 84
    triangles = []
    for _ in range(tri_count):
        values = struct.unpack_from("<12fH", data, offset)
        offset += 50
        v0 = (values[3], values[4], values[5])
        v1 = (values[6], values[7], values[8])
        v2 = (values[9], values[10], values[11])
        triangles.append((v0, v1, v2))
    return triangles


def _parse_ascii_stl(data):
    try:
        text = data.decode("ascii", "ignore")
    except Exception:
        raise STLModelError("Unable to decode ASCII STL")
    vertices = []
    for match in re.finditer(
            r"vertex\s+([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)"
            r"\s+([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)"
            r"\s+([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)",
            text):
        vertices.append((float(match.group(1)), float(match.group(2)),
                         float(match.group(3))))
    if len(vertices) < 3 or len(vertices) % 3:
        raise STLModelError("ASCII STL has malformed vertex count")
    return [(vertices[i], vertices[i + 1], vertices[i + 2])
            for i in range(0, len(vertices), 3)]


class SurfaceModel:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.gcode = self.printer.lookup_object('gcode')
        default_dir = '~/printer_data/config/surface_models'
        default_scan_dir = '~/printer_data/config/surface_scans'
        self.output_dir = _expand_path(config.get('output_dir', default_dir))
        self.scan_dir = _expand_path(config.get('scan_dir', default_scan_dir))
        self.index_cell_size = config.getfloat(
            'index_cell_size', 5., above=0.)
        self.segment_length = config.getfloat(
            'segment_length', 1., above=0.)
        self.max_z_adjust = config.getfloat(
            'max_z_adjust', 30., above=0.)
        self.max_z_delta_per_mm = config.getfloat(
            'max_z_delta_per_mm', 5., above=0.)
        self.outside_policy = config.getchoice(
            'outside_policy', {'error': 'error', 'clamp': 'clamp',
                               'passthrough': 'passthrough'}, 'error')
        self.align_xy_range = config.getfloat(
            'align_xy_range', 20., minval=0.)
        self.align_angle_range = math.radians(config.getfloat(
            'align_angle_range', 15., minval=0.))
        self.align_xy_step = config.getfloat(
            'align_xy_step', 5., above=0.)
        self.align_angle_step = math.radians(config.getfloat(
            'align_angle_step', 5., above=0.))
        self.align_passes = config.getint('align_passes', 4, minval=1)
        self.min_alignment_points = config.getint(
            'min_alignment_points', 6, minval=3)
        self.max_alignment_rms = config.getfloat(
            'max_alignment_rms', 10., above=0.)

        self.models = {}
        self.active_model = None
        self.active_alignment = None
        self.enabled = False
        self.clearance = 0.
        self.last_adjust = 0.
        self.last_position = [0., 0., 0., 0.]
        self.next_transform = None
        self.toolhead = None

        self.gcode.register_command(
            'SURFACE_MODEL_LOAD', self.cmd_SURFACE_MODEL_LOAD,
            desc=self.cmd_SURFACE_MODEL_LOAD_help)
        self.gcode.register_command(
            'SURFACE_MODEL_ALIGN', self.cmd_SURFACE_MODEL_ALIGN,
            desc=self.cmd_SURFACE_MODEL_ALIGN_help)
        self.gcode.register_command(
            'SET_SURFACE_COMPENSATION',
            self.cmd_SET_SURFACE_COMPENSATION,
            desc=self.cmd_SET_SURFACE_COMPENSATION_help)
        self.gcode.register_command(
            'SURFACE_MODEL_STATUS', self.cmd_SURFACE_MODEL_STATUS,
            desc=self.cmd_SURFACE_MODEL_STATUS_help)

        webhooks = self.printer.lookup_object('webhooks')
        webhooks.register_endpoint("surface_model/status",
                                   self._handle_status_request)
        webhooks.register_endpoint("surface_model/list",
                                   self._handle_list_request)
        webhooks.register_endpoint("surface_model/get",
                                   self._handle_get_request)
        webhooks.register_endpoint("surface_model/preview",
                                   self._handle_preview_request)
        webhooks.register_endpoint("surface_model/rename",
                                   self._handle_rename_request)
        webhooks.register_endpoint("surface_model/delete",
                                   self._handle_delete_request)

        self.printer.register_event_handler("klippy:connect",
                                            self.handle_connect)

    def handle_connect(self):
        self.toolhead = self.printer.lookup_object('toolhead')
        gcode_move = self.printer.lookup_object('gcode_move')
        self.next_transform = gcode_move.set_move_transform(self, force=True)
        self.last_position = list(self.next_transform.get_position())

    def _model_path(self, profile):
        return os.path.join(self.output_dir,
                            "model_" + _sanitize_profile_name(profile)
                            + ".json")

    def _alignment_path(self, profile):
        return os.path.join(self.output_dir,
                            "align_" + _sanitize_profile_name(profile)
                            + ".json")

    def _profile_path(self, profile_type, profile):
        if profile_type == "model":
            return self._model_path(profile)
        if profile_type == "alignment":
            return self._alignment_path(profile)
        raise STLModelError("TYPE must be 'model' or 'alignment'")

    def _load_model(self, profile):
        profile = _sanitize_profile_name(profile)
        model = self.models.get(profile)
        if model is not None:
            return model
        path = self._model_path(profile)
        if not os.path.isfile(path):
            raise self.printer.command_error(
                "Surface model profile '%s' was not found" % (profile,))
        with open(path, "r") as f:
            payload = json.load(f)
        stl_path = payload.get('stl_path')
        if not stl_path:
            raise self.printer.command_error(
                "Surface model profile '%s' has no stl_path" % (profile,))
        height_axis = payload.get('height_axis', 'Z')
        model = STLHeightModel.from_file(
            stl_path, self.index_cell_size, height_axis)
        self.models[profile] = model
        return model

    def _load_model_payload(self, profile):
        profile = _sanitize_profile_name(profile)
        with open(self._model_path(profile), "r") as f:
            return json.load(f)

    def _load_alignment_payload(self, profile):
        profile = _sanitize_profile_name(profile)
        path = self._alignment_path(profile)
        if not os.path.isfile(path):
            raise self.printer.command_error(
                "Surface alignment profile '%s' was not found" % (profile,))
        with open(path, "r") as f:
            return json.load(f)

    def _load_scan_payload(self, scan):
        scan = scan.strip()
        candidate = _expand_path(scan)
        if not os.path.isfile(candidate):
            candidate = os.path.join(self.scan_dir,
                                     _sanitize_profile_name(scan) + ".json")
        if not os.path.isfile(candidate):
            raise self.printer.command_error(
                "Surface scan profile '%s' was not found" % (scan,))
        with open(candidate, "r") as f:
            return json.load(f)

    def _iter_profiles(self, prefix):
        if not os.path.isdir(self.output_dir):
            return []
        result = []
        for filename in os.listdir(self.output_dir):
            if not filename.startswith(prefix) or not filename.endswith(".json"):
                continue
            path = os.path.join(self.output_dir, filename)
            try:
                with open(path, "r") as f:
                    payload = json.load(f)
            except Exception:
                payload = {}
            payload['path'] = path
            payload['modified'] = os.path.getmtime(path)
            result.append(payload)
        result.sort(key=lambda p: p.get('modified', 0.), reverse=True)
        return result

    def _handle_status_request(self, web_request):
        eventtime = self.printer.get_reactor().monotonic()
        web_request.send(self.get_status(eventtime))

    def _handle_list_request(self, web_request):
        web_request.send({
            'models': self._iter_profiles("model_"),
            'alignments': self._iter_profiles("align_"),
        })

    def _handle_get_request(self, web_request):
        profile = web_request.get_str("PROFILE")
        profile_type = web_request.get_str("TYPE", "alignment")
        if profile_type == "model":
            with open(self._model_path(profile), "r") as f:
                web_request.send(json.load(f))
            return
        if profile_type != "alignment":
            raise web_request.error(
                "TYPE must be 'model' or 'alignment'")
        with open(self._alignment_path(profile), "r") as f:
            web_request.send(json.load(f))

    def _write_profile_payload(self, profile_type, profile, payload):
        path = self._profile_path(profile_type, profile)
        with open(path, "w") as f:
            json.dump(payload, f, indent=2, sort_keys=True)
            f.write("\n")

    def _model_is_referenced(self, profile):
        profile = _sanitize_profile_name(profile)
        references = []
        for alignment in self._iter_profiles("align_"):
            if alignment.get("model_profile") == profile:
                references.append(alignment.get("profile"))
        return [r for r in references if r]

    def _replace_model_references(self, old_profile, new_profile):
        updated = []
        for alignment in self._iter_profiles("align_"):
            if alignment.get("model_profile") != old_profile:
                continue
            align_profile = alignment.get("profile")
            if not align_profile:
                continue
            alignment["model_profile"] = new_profile
            self._write_profile_payload("alignment", align_profile, alignment)
            updated.append(align_profile)
        return updated

    def _handle_rename_request(self, web_request):
        profile_type = web_request.get_str("TYPE")
        if profile_type not in ("model", "alignment"):
            raise web_request.error("TYPE must be 'model' or 'alignment'")
        old_profile = _sanitize_profile_name(web_request.get_str("PROFILE"))
        new_profile = _sanitize_profile_name(web_request.get_str("NEW_PROFILE"))
        if old_profile == new_profile:
            web_request.send({"profile": old_profile, "renamed": False})
            return
        old_path = self._profile_path(profile_type, old_profile)
        new_path = self._profile_path(profile_type, new_profile)
        if not os.path.isfile(old_path):
            raise web_request.error(
                "Surface %s profile '%s' was not found"
                % (profile_type, old_profile))
        if os.path.exists(new_path):
            raise web_request.error(
                "Surface %s profile '%s' already exists"
                % (profile_type, new_profile))
        with open(old_path, "r") as f:
            payload = json.load(f)
        payload["profile"] = new_profile
        if profile_type == "model":
            self.models.pop(old_profile, None)
            updated_alignments = self._replace_model_references(
                old_profile, new_profile)
            if self.active_model == old_profile:
                self.active_model = new_profile
            if (self.active_alignment is not None
                and self.active_alignment.get("model_profile") == old_profile):
                self.active_alignment["model_profile"] = new_profile
        else:
            updated_alignments = []
        if (profile_type == "alignment" and self.active_alignment is not None
            and self.active_alignment.get("profile") == old_profile):
            raise web_request.error(
                "Cannot rename the active surface alignment")
        self._write_profile_payload(profile_type, new_profile, payload)
        os.remove(old_path)
        web_request.send({
            "type": profile_type,
            "old_profile": old_profile,
            "profile": new_profile,
            "renamed": True,
            "updated_alignments": updated_alignments,
        })

    def _handle_delete_request(self, web_request):
        profile_type = web_request.get_str("TYPE")
        if profile_type not in ("model", "alignment"):
            raise web_request.error("TYPE must be 'model' or 'alignment'")
        profile = _sanitize_profile_name(web_request.get_str("PROFILE"))
        path = self._profile_path(profile_type, profile)
        if not os.path.isfile(path):
            raise web_request.error(
                "Surface %s profile '%s' was not found"
                % (profile_type, profile))
        if profile_type == "model":
            references = self._model_is_referenced(profile)
            if references:
                raise web_request.error(
                    "Model '%s' is used by alignment profile(s): %s"
                    % (profile, ", ".join(references)))
            if self.active_model == profile:
                raise web_request.error(
                    "Cannot delete the active surface model")
            self.models.pop(profile, None)
        if profile_type == "alignment":
            active = (self.active_alignment is not None
                      and self.active_alignment.get("profile") == profile)
            if active:
                raise web_request.error(
                    "Cannot delete the active surface alignment")
        os.remove(path)
        web_request.send({
            "type": profile_type,
            "profile": profile,
            "deleted": True,
        })

    def _web_float(self, web_request, name, default=None, minval=None):
        value = web_request.get(name, default, types=(int, float, str))
        if value is None:
            return None
        try:
            value = float(value)
        except ValueError:
            raise web_request.error("%s must be a number" % (name,))
        if minval is not None and value < minval:
            raise web_request.error(
                "%s must be at least %.3f" % (name, minval))
        return value

    def _web_int(self, web_request, name, default=None, minval=None,
                 maxval=None):
        value = web_request.get(name, default, types=(int, str))
        if value is None:
            return None
        try:
            value = int(value)
        except ValueError:
            raise web_request.error("%s must be an integer" % (name,))
        if minval is not None and value < minval:
            raise web_request.error("%s must be at least %d" % (name, minval))
        if maxval is not None and value > maxval:
            raise web_request.error("%s must be at most %d" % (name, maxval))
        return value

    def _range_samples(self, min_value, max_value, count):
        if count <= 1:
            return [(min_value + max_value) / 2.]
        step = (max_value - min_value) / float(count - 1)
        return [min_value + step * i for i in range(count)]

    def _preview_axes(self, web_request, model):
        spacing = self._web_float(web_request, "SPACING", None, minval=0.001)
        if spacing is not None:
            x_count = int(math.floor((model.max_x - model.min_x)
                                     / spacing + 1e-9)) + 1
            y_count = int(math.floor((model.max_y - model.min_y)
                                     / spacing + 1e-9)) + 1
            x_count = max(2, x_count)
            y_count = max(2, y_count)
        else:
            x_count = self._web_int(web_request, "X_COUNT", 40,
                                    minval=2, maxval=160)
            y_count = self._web_int(web_request, "Y_COUNT", 40,
                                    minval=2, maxval=160)
        max_points = self._web_int(web_request, "MAX_POINTS", 1600,
                                   minval=4, maxval=10000)
        if x_count * y_count > max_points:
            scale = math.sqrt(float(max_points) / float(x_count * y_count))
            x_count = max(2, int(math.floor(x_count * scale)))
            y_count = max(2, int(math.floor(y_count * scale)))
        return (self._range_samples(model.min_x, model.max_x, x_count),
                self._range_samples(model.min_y, model.max_y, y_count))

    def _sample_surface(self, model, x_values, y_values, alignment=None,
                        clearance=0.):
        fields = ["x", "y", "z", "adjust"]
        points = []
        missing = 0
        theta = 0.
        dx = dy = z_offset = 0.
        if alignment is not None:
            theta = math.radians(alignment['theta_deg'])
            dx = alignment['dx']
            dy = alignment['dy']
            z_offset = alignment['z_offset']
        for my in y_values:
            for mx in x_values:
                try:
                    model_z = model.calc_z(mx, my, "passthrough")
                except Exception:
                    model_z = None
                if model_z is None:
                    missing += 1
                    continue
                x, y = mx, my
                z = model_z
                if alignment is not None:
                    x, y = _rotate_xy(mx, my, theta)
                    x += dx
                    y += dy
                    z += z_offset
                points.append([x, y, z, z + clearance])
        return {
            "fields": fields,
            "points": points,
            "x_count": len(x_values),
            "y_count": len(y_values),
            "sample_count": len(points),
            "missing_count": missing,
        }

    def _transform_preview_point(self, point, alignment=None):
        x, y, z = point
        if alignment is None:
            return [x, y, z]
        theta = math.radians(alignment['theta_deg'])
        x, y = _rotate_xy(x, y, theta)
        return [
            x + alignment['dx'],
            y + alignment['dy'],
            z + alignment['z_offset'],
        ]

    def _preview_mesh(self, web_request, model, alignment=None):
        max_triangles = self._web_int(
            web_request, "MAX_TRIANGLES", 650, minval=0, maxval=3000)
        triangle_count = len(model.triangles)
        if max_triangles <= 0 or triangle_count <= 0:
            return {
                "fields": ["x", "y", "z"],
                "triangles": [],
                "triangle_count": 0,
                "source_triangle_count": triangle_count,
                "decimated": triangle_count > 0,
            }
        step = max(1, int(math.ceil(float(triangle_count)
                                    / float(max_triangles))))
        triangles = []
        for tri in model.triangles[::step]:
            triangles.append([
                self._transform_preview_point(vertex, alignment)
                for vertex in tri['verts']
            ])
        return {
            "fields": ["x", "y", "z"],
            "triangles": triangles,
            "triangle_count": len(triangles),
            "source_triangle_count": triangle_count,
            "decimated": step > 1,
            "sample_step": step,
        }

    def _residual_preview(self, model, alignment, scan_payload):
        fields = [
            "x", "y", "scan_z", "model_z", "residual",
            "distance_mm", "raw_mm", "status", "sigma",
        ]
        points = []
        invalid_points = []
        residuals = []
        theta = math.radians(alignment['theta_deg'])
        dx = alignment['dx']
        dy = alignment['dy']
        z_offset = alignment['z_offset']
        for point in scan_payload.get('points', []):
            x = point.get('x')
            y = point.get('y')
            if not point.get('valid', True) or x is None or y is None:
                invalid_points.append({
                    'x': x, 'y': y, 'error': point.get('error'),
                })
                continue
            scan_z = point.get('z')
            if scan_z is None:
                invalid_points.append({
                    'x': x, 'y': y, 'error': point.get('error'),
                })
                continue
            mx, my = _inverse_transform_xy(float(x), float(y), dx, dy, theta)
            try:
                model_z = model.calc_z(mx, my, "passthrough")
            except Exception:
                model_z = None
            if model_z is None:
                invalid_points.append({
                    'x': x, 'y': y, 'error': "outside_model",
                })
                continue
            model_z += z_offset
            residual = float(scan_z) - model_z
            residuals.append(residual)
            points.append([
                float(x), float(y), float(scan_z), model_z, residual,
                point.get('distance_mm'), point.get('raw_mm'),
                point.get('status'), point.get('sigma'),
            ])
        abs_residuals = [abs(r) for r in residuals]
        summary = {
            "scan_point_count": len(scan_payload.get('points', [])),
            "matched_count": len(points),
            "unmatched_count": len(invalid_points),
            "residual_rms": _rms(residuals),
            "residual_mean_abs": (
                sum(abs_residuals) / float(len(abs_residuals))
                if abs_residuals else 0.),
            "residual_p95_abs": _percentile(abs_residuals, 0.95),
            "residual_max_abs": max(abs_residuals) if abs_residuals else 0.,
        }
        return {
            "fields": fields,
            "points": points,
            "invalid_points": invalid_points,
            "summary": summary,
        }

    def _scan_summary(self, scan_payload):
        points = scan_payload.get("points", [])
        valid = [p for p in points
                 if p.get("valid", True) and p.get("z") is not None]
        invalid = len(points) - len(valid)
        z_values = [float(p["z"]) for p in valid]
        summary = {
            "point_count": len(points),
            "valid_count": len(valid),
            "invalid_count": invalid,
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

    def _handle_preview_request(self, web_request):
        profile_type = web_request.get_str("TYPE", "alignment")
        profile = web_request.get_str("PROFILE")
        clearance = self._web_float(web_request, "CLEARANCE", 0.)
        if profile_type == "model":
            model = self._load_model(profile)
            model_payload = self._load_model_payload(profile)
            x_values, y_values = self._preview_axes(web_request, model)
            web_request.send({
                "type": "model_preview",
                "profile": _sanitize_profile_name(profile),
                "coordinate_space": "model",
                "model": model_payload,
                "surface": self._sample_surface(
                    model, x_values, y_values, clearance=clearance),
                "mesh": self._preview_mesh(web_request, model),
            })
            return
        if profile_type != "alignment":
            raise web_request.error(
                "TYPE must be 'model' or 'alignment'")
        alignment_payload = self._load_alignment_payload(profile)
        model = self._load_model(alignment_payload['model_profile'])
        scan_payload = self._load_scan_payload(alignment_payload['scan_profile'])
        alignment = dict(alignment_payload)
        x_values, y_values = self._preview_axes(web_request, model)
        web_request.send({
            "type": "alignment_preview",
            "profile": _sanitize_profile_name(profile),
            "coordinate_space": "machine",
            "alignment": alignment_payload,
            "scan": {
                "profile": scan_payload.get("profile"),
                "area_min": scan_payload.get("area_min"),
                "area_max": scan_payload.get("area_max"),
                "grid": scan_payload.get("grid"),
                "summary": scan_payload.get("summary")
                           or self._scan_summary(scan_payload),
            },
            "surface": self._sample_surface(
                model, x_values, y_values, alignment, clearance),
            "mesh": self._preview_mesh(web_request, model, alignment),
            "residuals": self._residual_preview(
                model, alignment, scan_payload),
        })

    def _check_homed(self):
        eventtime = self.printer.get_reactor().monotonic()
        kin_status = self.toolhead.get_kinematics().get_status(eventtime)
        homed_axes = kin_status.get('homed_axes', '')
        for axis in 'xyz':
            if axis not in homed_axes:
                raise self.printer.command_error(
                    "Must home X, Y, and Z before surface compensation")

    def _alignment_surface_z(self, alignment, x, y, outside_policy=None):
        model = alignment['model_object']
        dx = alignment['dx']
        dy = alignment['dy']
        theta = math.radians(alignment['theta_deg'])
        mx, my = _inverse_transform_xy(x, y, dx, dy, theta)
        policy = outside_policy or self.outside_policy
        model_z = model.calc_z(mx, my, policy)
        if model_z is None:
            return None
        return model_z + alignment['z_offset']

    def _calc_adjust(self, pos):
        if not self.enabled or self.active_alignment is None:
            return 0.
        surface_z = self._alignment_surface_z(
            self.active_alignment, pos[0], pos[1])
        if surface_z is None:
            return 0.
        adjust = surface_z + self.clearance
        if abs(adjust) > self.max_z_adjust:
            raise self.printer.command_error(
                "Surface compensation %.3fmm exceeds max_z_adjust %.3fmm"
                % (adjust, self.max_z_adjust))
        return adjust

    def _adjusted_pos(self, pos):
        adjust = self._calc_adjust(pos)
        return [pos[0], pos[1], pos[2] + adjust] + pos[3:], adjust

    def get_position(self):
        if self.next_transform is None:
            return list(self.last_position)
        cur_pos = list(self.next_transform.get_position())
        if not self.enabled or self.active_alignment is None:
            self.last_position = list(cur_pos)
            return cur_pos
        try:
            adjust = self._calc_adjust(cur_pos)
        except Exception:
            adjust = self.last_adjust
        cur_pos[2] -= adjust
        self.last_position = list(cur_pos)
        return cur_pos

    def move(self, newpos, speed):
        if self.next_transform is None:
            self.toolhead.move(newpos, speed)
            return
        if not self.enabled or self.active_alignment is None:
            self.next_transform.move(newpos, speed)
            self.last_position[:] = newpos
            return
        start = list(self.last_position)
        end = list(newpos)
        dx = end[0] - start[0]
        dy = end[1] - start[1]
        xy_dist = math.sqrt(dx * dx + dy * dy)
        if xy_dist <= EPSILON:
            adjusted = [end[0], end[1], end[2] + self.last_adjust] + end[3:]
            self.next_transform.move(adjusted, speed)
            self.last_position[:] = newpos
            return
        segments = max(1, int(math.ceil(xy_dist / self.segment_length)))
        prev_adjust = self.last_adjust
        for i in range(1, segments + 1):
            t = float(i) / float(segments)
            pos = [start[j] + (end[j] - start[j]) * t
                   for j in range(len(end))]
            adjusted, adjust = self._adjusted_pos(pos)
            if i > 1 or xy_dist > 0.:
                seg_xy = xy_dist / float(segments) if segments else 0.
                if seg_xy > 0.:
                    slope = abs(adjust - prev_adjust) / seg_xy
                    if slope > self.max_z_delta_per_mm:
                        raise self.printer.command_error(
                            "Surface compensation slope %.3f exceeds %.3f"
                            % (slope, self.max_z_delta_per_mm))
            self.next_transform.move(adjusted, speed)
            prev_adjust = adjust
        self.last_adjust = prev_adjust
        self.last_position[:] = newpos

    def _scan_points(self, payload):
        points = []
        for point in payload.get('points', []):
            if not point.get('valid', True):
                continue
            x = point.get('x')
            y = point.get('y')
            z = point.get('z')
            if x is None or y is None or z is None:
                continue
            points.append((float(x), float(y), float(z)))
        return points

    def _candidate_stats(self, model, points, dx, dy, theta):
        diffs = []
        for x, y, z in points:
            mx, my = _inverse_transform_xy(x, y, dx, dy, theta)
            try:
                model_z = model.calc_z(mx, my, "passthrough")
            except Exception:
                model_z = None
            if model_z is None:
                continue
            diffs.append(z - model_z)
        if len(diffs) < self.min_alignment_points:
            return None
        z_offset = _median(diffs)
        residuals = [d - z_offset for d in diffs]
        return {
            'count': len(diffs),
            'z_offset': z_offset,
            'rms': _rms(residuals),
            'mean_abs': sum([abs(r) for r in residuals]) / float(len(residuals)),
            'max_abs': max([abs(r) for r in residuals]),
            'p95_abs': _percentile([abs(r) for r in residuals], 0.95),
        }

    def _align_model_to_scan(self, model, points, init_dx, init_dy, init_theta,
                             xy_range, angle_range, xy_step, angle_step,
                             passes):
        best = None
        center_dx = init_dx
        center_dy = init_dy
        center_theta = init_theta
        cur_xy_range = xy_range
        cur_angle_range = angle_range
        cur_xy_step = xy_step
        cur_angle_step = angle_step
        for _ in range(passes):
            x_count = int(math.floor(cur_xy_range / cur_xy_step + 1e-9))
            a_count = int(math.floor(cur_angle_range / cur_angle_step + 1e-9))
            for ix in range(-x_count, x_count + 1):
                dx = center_dx + ix * cur_xy_step
                for iy in range(-x_count, x_count + 1):
                    dy = center_dy + iy * cur_xy_step
                    for ia in range(-a_count, a_count + 1):
                        theta = center_theta + ia * cur_angle_step
                        stats = self._candidate_stats(
                            model, points, dx, dy, theta)
                        if stats is None:
                            continue
                        score = (-stats['count'], stats['rms'])
                        if best is None or score < best['score']:
                            best = {
                                'dx': dx, 'dy': dy, 'theta': theta,
                                'stats': stats, 'score': score,
                            }
            if best is None:
                break
            center_dx = best['dx']
            center_dy = best['dy']
            center_theta = best['theta']
            cur_xy_range = max(cur_xy_step, cur_xy_step * 2.)
            cur_angle_range = max(cur_angle_step, cur_angle_step * 2.)
            cur_xy_step = max(cur_xy_step / 2., 0.05)
            cur_angle_step = max(cur_angle_step / 2., math.radians(0.05))
        if best is None:
            raise self.printer.command_error(
                "Unable to align STL model to scan: insufficient overlap")
        return best

    cmd_SURFACE_MODEL_LOAD_help = "Load an STL surface model profile"
    def cmd_SURFACE_MODEL_LOAD(self, gcmd):
        stl_path = _expand_path(gcmd.get('STL'))
        profile = _sanitize_profile_name(gcmd.get('PROFILE', ''))
        height_axis = _normalize_axis(gcmd.get('HEIGHT_AXIS', 'Z'))
        if not os.path.isfile(stl_path):
            raise gcmd.error("STL file '%s' was not found" % (stl_path,))
        model = STLHeightModel.from_file(
            stl_path, self.index_cell_size, height_axis)
        self.models[profile] = model
        os.makedirs(self.output_dir, exist_ok=True)
        payload = {
            'type': 'model',
            'profile': profile,
            'stl_path': stl_path,
            'height_axis': height_axis.upper(),
            'created_at': time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            'stats': model.get_stats(),
        }
        with open(self._model_path(profile), "w") as f:
            json.dump(payload, f, indent=2, sort_keys=True)
            f.write("\n")
        gcmd.respond_info(
            "Surface model '%s' loaded: %d triangles, height_axis=%s, bounds "
            "X %.3f..%.3f Y %.3f..%.3f Z %.3f..%.3f"
            % (profile, payload['stats']['triangle_count'],
               payload['height_axis'],
               payload['stats']['min_x'], payload['stats']['max_x'],
               payload['stats']['min_y'], payload['stats']['max_y'],
               payload['stats']['min_z'], payload['stats']['max_z']))

    cmd_SURFACE_MODEL_ALIGN_help = "Align a loaded STL model to a scan profile"
    def cmd_SURFACE_MODEL_ALIGN(self, gcmd):
        model_profile = _sanitize_profile_name(gcmd.get('MODEL'))
        scan_profile = gcmd.get('SCAN')
        align_profile = _sanitize_profile_name(
            gcmd.get('PROFILE', model_profile + "-" + scan_profile))
        model = self._load_model(model_profile)
        model_payload = self._load_model_payload(model_profile)
        scan_payload = self._load_scan_payload(scan_profile)
        points = self._scan_points(scan_payload)
        if len(points) < self.min_alignment_points:
            raise gcmd.error(
                "Scan has %d valid points, need at least %d"
                % (len(points), self.min_alignment_points))

        scan_cx = sum([p[0] for p in points]) / float(len(points))
        scan_cy = sum([p[1] for p in points]) / float(len(points))
        model_cx = (model.min_x + model.max_x) / 2.
        model_cy = (model.min_y + model.max_y) / 2.
        init_dx = gcmd.get_float('DX', scan_cx - model_cx)
        init_dy = gcmd.get_float('DY', scan_cy - model_cy)
        init_theta = math.radians(gcmd.get_float('THETA', 0.))
        xy_range = gcmd.get_float('XY_RANGE', self.align_xy_range, minval=0.)
        angle_range = math.radians(gcmd.get_float(
            'ANGLE_RANGE', math.degrees(self.align_angle_range), minval=0.))
        xy_step = gcmd.get_float('XY_STEP', self.align_xy_step, above=0.)
        angle_step = math.radians(gcmd.get_float(
            'ANGLE_STEP', math.degrees(self.align_angle_step), above=0.))
        passes = gcmd.get_int('PASSES', self.align_passes, minval=1)
        max_rms = gcmd.get_float(
            'MAX_RMS', self.max_alignment_rms, above=0.)

        best = self._align_model_to_scan(
            model, points, init_dx, init_dy, init_theta,
            xy_range, angle_range, xy_step, angle_step, passes)
        stats = best['stats']
        if stats['rms'] > max_rms:
            raise gcmd.error(
                "Alignment RMS %.3fmm exceeds MAX_RMS %.3fmm"
                % (stats['rms'], max_rms))
        payload = {
            'type': 'alignment',
            'profile': align_profile,
            'model_profile': model_profile,
            'scan_profile': scan_profile,
            'stl_path': model_payload.get('stl_path'),
            'created_at': time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            'dx': best['dx'],
            'dy': best['dy'],
            'theta_deg': math.degrees(best['theta']),
            'z_offset': stats['z_offset'],
            'used_point_count': stats['count'],
            'scan_point_count': len(points),
            'residual_rms': stats['rms'],
            'residual_mean_abs': stats['mean_abs'],
            'residual_p95_abs': stats['p95_abs'],
            'residual_max_abs': stats['max_abs'],
            'model_stats': model.get_stats(),
        }
        os.makedirs(self.output_dir, exist_ok=True)
        with open(self._alignment_path(align_profile), "w") as f:
            json.dump(payload, f, indent=2, sort_keys=True)
            f.write("\n")
        gcmd.respond_info(
            "Surface alignment '%s': dx=%s dy=%s theta=%sdeg "
            "z_offset=%s rms=%s used=%d/%d"
            % (align_profile, _format_float(payload['dx']),
               _format_float(payload['dy']),
               _format_float(payload['theta_deg']),
               _format_float(payload['z_offset']),
               _format_float(payload['residual_rms']),
               payload['used_point_count'], payload['scan_point_count']))

    cmd_SET_SURFACE_COMPENSATION_help = "Enable or disable STL surface Z compensation"
    def cmd_SET_SURFACE_COMPENSATION(self, gcmd):
        enable = gcmd.get_int('ENABLE', None, minval=0, maxval=1)
        if enable is None:
            raise gcmd.error("ENABLE parameter is required")
        gcode_move = self.printer.lookup_object('gcode_move')
        if not enable:
            self.enabled = False
            self.active_alignment = None
            self.active_model = None
            self.last_adjust = 0.
            gcode_move.reset_last_position()
            gcmd.respond_info("Surface compensation disabled")
            return
        self._check_homed()
        profile = _sanitize_profile_name(gcmd.get('PROFILE'))
        clearance = gcmd.get_float('CLEARANCE', 0.)
        payload = self._load_alignment_payload(profile)
        model_profile = payload['model_profile']
        model = self._load_model(model_profile)
        alignment = dict(payload)
        alignment['model_object'] = model
        self.active_model = model_profile
        self.active_alignment = alignment
        self.clearance = clearance
        self.enabled = True
        cur_pos = self.next_transform.get_position()
        self.last_adjust = self._calc_adjust(cur_pos)
        gcode_move.reset_last_position()
        gcmd.respond_info(
            "Surface compensation enabled: profile=%s model=%s "
            "clearance=%.3f current_adjust=%.3f"
            % (profile, model_profile, clearance, self.last_adjust))

    cmd_SURFACE_MODEL_STATUS_help = "Report STL surface model compensation status"
    def cmd_SURFACE_MODEL_STATUS(self, gcmd):
        status = self.get_status()
        if not status['enabled']:
            gcmd.respond_info("Surface compensation: disabled")
            return
        align = status.get('alignment') or {}
        gcmd.respond_info(
            "Surface compensation: enabled\n"
            "model=%s alignment=%s clearance=%.3f current_adjust=%.3f\n"
            "dx=%.6f dy=%.6f theta=%.6f z_offset=%.6f rms=%.6f"
            % (status.get('model_profile'), align.get('profile'),
               status.get('clearance', 0.), status.get('current_adjust', 0.),
               align.get('dx', 0.), align.get('dy', 0.),
               align.get('theta_deg', 0.), align.get('z_offset', 0.),
               align.get('residual_rms', 0.)))

    def get_status(self, eventtime=None):
        alignment = None
        if self.active_alignment is not None:
            alignment = {}
            for key, value in self.active_alignment.items():
                if key == 'model_object':
                    continue
                alignment[key] = value
        return {
            'enabled': self.enabled,
            'model_profile': self.active_model,
            'alignment': alignment,
            'clearance': self.clearance,
            'current_adjust': self.last_adjust,
            'segment_length': self.segment_length,
            'max_z_adjust': self.max_z_adjust,
            'outside_policy': self.outside_policy,
            'output_dir': self.output_dir,
            'scan_dir': self.scan_dir,
        }


def load_config(config):
    return SurfaceModel(config)
