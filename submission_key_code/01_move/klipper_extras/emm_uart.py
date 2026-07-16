# Hardware USART2 controller for EMM/ZDT closed-loop stepper drivers.
#
# Requires the matching MCU-side Klipper patch in emm_usart.c.
#
# Commands:
#   EMM_SEND HEX=010A6D6B [READ=4]
#   EMM_CLEAR_ANGLES [READ=4]
#   EMM_ENABLE [IDS=1,2,3]
#   EMM_DISABLE [IDS=1,2,3]
#   EMM_READ_POSITIONS
#   EMM_READ_STATUS
#   EMM_WAIT_REACHED [IDS=1,2,3] [TIMEOUT=10.0] [POLL=0.05] [STABLE=2]
#   EMM_HOME_AND_CLEAR
#   EMM_VERIFY_ANGLES [IDS=1,2,3] [HOME=1] [AXIS=Z] [DISTANCE=2.0] [CYCLES=2] [FEEDRATE=300] [TOLERANCE=0.2]
#   EMM_RECORD_BEGIN [CLEAR=0]
#   EMM_RECORD_POINT [NAME=<label>] [COMMANDS_B64=<base64url>]
#   EMM_SET_POINT_COMMANDS INDEX=<point> COMMANDS_B64=<base64url>
#   EMM_LIST_POINTS
#   EMM_CLEAR_POINTS
#   EMM_PLAY_POINTS [START=0] [END=<last>] [SEGMENTS=10] [SPEED=<rpm>] [ACCEL=<0-255>] [WAIT=0.0] [PACE_SCALE=1.10] [MIN_SEGMENT_TIME=0.0] [INTER_PACKET_DELAY=0.010] [AUTO_ENABLE=1] CONFIRM=1

import ast
import base64
import json
import os
import time

MIN_INTER_PACKET_DELAY = 0.010


class EmmUart:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.gcode = self.printer.lookup_object("gcode")
        self.enabled = True

        self.baud = config.getint("baud", 115200, minval=1200, maxval=1000000)
        self.timeout_us = config.getint("timeout_us", 20000,
                                        minval=1000, maxval=1000000)
        self.inter_packet_delay = config.getfloat(
            "inter_packet_delay", MIN_INTER_PACKET_DELAY,
            minval=MIN_INTER_PACKET_DELAY
        )
        self.checksum = _parse_byte(config.get("checksum", "0x6B"))
        self.ids = _parse_ids(config.get("ids", "1,2,3"))
        self.default_read_bytes = config.getint(
            "read_bytes", 0, minval=0, maxval=64
        )
        self.pulses_per_rev = config.getfloat(
            "pulses_per_rev", 3200.0, minval=1.0
        )
        self.play_speed = config.getint(
            "play_speed", 120, minval=1, maxval=65535
        )
        self.play_accel = config.getint(
            "play_accel", 10, minval=0, maxval=255
        )
        self.play_direction_inverted = config.getboolean(
            "play_direction_inverted", False
        )
        self.record_file = config.get(
            "record_file",
            os.path.expanduser("~/printer_data/config/emm_points.json"),
        )

        self.mcu = self.printer.lookup_object("mcu")
        self.oid = self.mcu.create_oid()
        self.cmd_queue = self.mcu.alloc_command_queue()
        self.transfer_cmd = None
        self.mutex = self.reactor.mutex()
        self.last_sent = []
        self.last_responses = []
        self.last_positions = {}
        self.last_statuses = {}
        self.motors_enabled = None
        self.points = []
        self.playback_status = {
            "active": False,
            "current": 0,
            "total": 0,
            "progress": 0.0,
            "start": 0,
            "end": 0,
            "message": "idle",
        }
        self._load_points()

        self.mcu.register_config_callback(self._build_config)
        self.gcode.register_command(
            "EMM_SEND", self.cmd_EMM_SEND,
            desc="Send raw bytes to EMM drivers via STM32 USART2 PA2/PA3",
        )
        self.gcode.register_command(
            "EMM_CLEAR_ANGLES", self.cmd_EMM_CLEAR_ANGLES,
            desc="Clear current position angle for configured EMM driver IDs",
        )
        self.gcode.register_command(
            "EMM_ENABLE", self.cmd_EMM_ENABLE,
            desc="Enable configured EMM driver IDs",
        )
        self.gcode.register_command(
            "EMM_DISABLE", self.cmd_EMM_DISABLE,
            desc="Disable configured EMM driver IDs for hand-guided recording",
        )
        self.gcode.register_command(
            "EMM_READ_POSITIONS", self.cmd_EMM_READ_POSITIONS,
            desc="Read realtime EMM driver positions",
        )
        self.gcode.register_command(
            "EMM_READ_STATUS", self.cmd_EMM_READ_STATUS,
            desc="Read EMM driver status flags",
        )
        self.gcode.register_command(
            "EMM_WAIT_REACHED", self.cmd_EMM_WAIT_REACHED,
            desc="Wait until all selected EMM drivers report reached",
        )
        self.gcode.register_command(
            "EMM_HOME_AND_CLEAR", self.cmd_EMM_HOME_AND_CLEAR,
            desc="Run G28, then clear current position angle on EMM drivers",
        )
        self.gcode.register_command(
            "EMM_VERIFY_ANGLES", self.cmd_EMM_VERIFY_ANGLES,
            desc="Home, clear, jog, and verify EMM angles return to zero",
        )
        self.gcode.register_command(
            "EMM_RECORD_BEGIN", self.cmd_EMM_RECORD_BEGIN,
            desc="Disable EMM drivers before hand-guided point recording",
        )
        self.gcode.register_command(
            "EMM_RECORD_POINT", self.cmd_EMM_RECORD_POINT,
            desc="Record current EMM driver angles as one path point",
        )
        self.gcode.register_command(
            "EMM_SET_POINT_COMMANDS", self.cmd_EMM_SET_POINT_COMMANDS,
            desc="Attach G-code commands to a recorded EMM point",
        )
        self.gcode.register_command(
            "EMM_LIST_POINTS", self.cmd_EMM_LIST_POINTS,
            desc="List recorded EMM angle points",
        )
        self.gcode.register_command(
            "EMM_CLEAR_POINTS", self.cmd_EMM_CLEAR_POINTS,
            desc="Clear recorded EMM angle points",
        )
        self.gcode.register_command(
            "EMM_PLAY_POINTS", self.cmd_EMM_PLAY_POINTS,
            desc="Replay recorded EMM angle points in absolute mode",
        )

    def _build_config(self):
        self.mcu.add_config_cmd(
            "config_emm_usart oid=%d baud=%d timeout_us=%d"
            % (self.oid, self.baud, self.timeout_us)
        )
        self.transfer_cmd = self.mcu.lookup_query_command(
            "emm_usart_transfer oid=%c write=%*s read_len=%c timeout_us=%u",
            "emm_usart_response oid=%c response=%*s",
            oid=self.oid, cq=self.cmd_queue, is_async=True,
        )

    def get_status(self, eventtime):
        return {
            "enabled": self.enabled,
            "baud": self.baud,
            "timeout_us": self.timeout_us,
            "ids": self.ids,
            "read_bytes": self.default_read_bytes,
            "last_sent": [_fmt_packet(pkt) for pkt in self.last_sent],
            "last_responses": [_fmt_packet(pkt) for pkt in self.last_responses],
            "last_positions": self.last_positions,
            "last_statuses": self.last_statuses,
            "motors_enabled": self.motors_enabled,
            "points": len(self.points),
            "pulses_per_rev": self.pulses_per_rev,
            "play_direction_inverted": self.play_direction_inverted,
            "playback": dict(self.playback_status),
        }

    def cmd_EMM_SEND(self, gcmd):
        hex_text = gcmd.get("HEX", None)
        if not hex_text:
            raise gcmd.error("Missing HEX, for example: HEX=010A6D6B")
        try:
            packet = _parse_hex_bytes(hex_text)
            read_bytes = gcmd.get_int(
                "READ", self.default_read_bytes, minval=0, maxval=64
            )
            timeout_us = gcmd.get_int(
                "TIMEOUT_US", self.timeout_us, minval=1000, maxval=1000000
            )
            responses = self._send_packets([packet], read_bytes, timeout_us)
        except ValueError as err:
            raise gcmd.error(str(err))
        msg = "EMM USART sent: %s" % _fmt_packet(packet)
        if read_bytes:
            msg += "\nEMM USART response: %s" % (
                _fmt_packet(responses[0]) if responses else "<empty>"
            )
        gcmd.respond_info(msg)

    def cmd_EMM_CLEAR_ANGLES(self, gcmd):
        try:
            ids = _parse_ids(gcmd.get(
                "IDS", ",".join(str(i) for i in self.ids)
            ))
            read_bytes = gcmd.get_int("READ", 4, minval=0, maxval=64)
            timeout_us = gcmd.get_int(
                "TIMEOUT_US", self.timeout_us, minval=1000, maxval=1000000
            )
            packets = [[driver_id, 0x0A, 0x6D, self.checksum]
                       for driver_id in ids]
            responses = self._send_packets(packets, read_bytes, timeout_us)
        except ValueError as err:
            raise gcmd.error(str(err))
        msg = "EMM clear-angle command sent to IDs: %s" % (
            ", ".join(str(i) for i in ids)
        )
        if read_bytes:
            msg += "\nEMM responses: %s" % (
                "; ".join(_fmt_packet(resp) or "<empty>"
                          for resp in responses)
            )
        gcmd.respond_info(msg)

    def cmd_EMM_ENABLE(self, gcmd):
        self._cmd_enable(gcmd, True)

    def cmd_EMM_DISABLE(self, gcmd):
        self._cmd_enable(gcmd, False)

    def cmd_EMM_READ_POSITIONS(self, gcmd):
        try:
            ids = _parse_ids(gcmd.get(
                "IDS", ",".join(str(i) for i in self.ids)
            ))
            timeout_us = gcmd.get_int(
                "TIMEOUT_US", self.timeout_us, minval=1000, maxval=1000000
            )
            responses, positions = self._read_positions(ids, timeout_us)
        except ValueError as err:
            raise gcmd.error(str(err))
        self.last_positions = {
            str(driver_id): {
                "raw": _fmt_packet(resp),
                "angle": pos,
            }
            for driver_id, resp, pos in zip(ids, responses, positions)
        }
        gcmd.respond_info(
            "EMM positions: %s" % "; ".join(
                "ID%d=%s deg" % (driver_id, _fmt_float(pos))
                for driver_id, pos in zip(ids, positions)
            )
        )

    def cmd_EMM_READ_STATUS(self, gcmd):
        try:
            ids = _parse_ids(gcmd.get(
                "IDS", ",".join(str(i) for i in self.ids)
            ))
            timeout_us = gcmd.get_int(
                "TIMEOUT_US", self.timeout_us, minval=1000, maxval=1000000
            )
            responses, statuses = self._read_statuses(ids, timeout_us)
        except ValueError as err:
            raise gcmd.error(str(err))
        self.last_statuses = {
            str(driver_id): _status_dict(resp, status)
            for driver_id, resp, status in zip(ids, responses, statuses)
        }
        gcmd.respond_info(
            "EMM statuses: %s" % "; ".join(
                _fmt_status(driver_id, status)
                for driver_id, status in zip(ids, statuses)
            )
        )

    def cmd_EMM_WAIT_REACHED(self, gcmd):
        try:
            ids = _parse_ids(gcmd.get(
                "IDS", ",".join(str(i) for i in self.ids)
            ))
            timeout_s = gcmd.get_float("TIMEOUT", 10.0, minval=0.1,
                                       maxval=120.0)
            poll_s = gcmd.get_float("POLL", 0.05, minval=0.01, maxval=2.0)
            stable_required = gcmd.get_int("STABLE", 2, minval=1, maxval=20)
            timeout_us = gcmd.get_int(
                "TIMEOUT_US", self.timeout_us, minval=1000, maxval=1000000
            )
            stable_count = 0
            last_statuses = []
            start = self.reactor.monotonic()
            deadline = start + timeout_s
            while True:
                responses, statuses = self._read_statuses(ids, timeout_us)
                self.last_statuses = {
                    str(driver_id): _status_dict(resp, status)
                    for driver_id, resp, status
                    in zip(ids, responses, statuses)
                }
                last_statuses = statuses
                if all(_status_reached(status) for status in statuses):
                    stable_count += 1
                    if stable_count >= stable_required:
                        elapsed = self.reactor.monotonic() - start
                        gcmd.respond_info(
                            "EMM reached after %.3fs: %s" % (
                                elapsed,
                                "; ".join(
                                    _fmt_status(driver_id, status)
                                    for driver_id, status
                                    in zip(ids, statuses)
                                ),
                            )
                        )
                        return
                else:
                    stable_count = 0

                eventtime = self.reactor.monotonic()
                if eventtime >= deadline:
                    raise gcmd.error(
                        "Timed out waiting for EMM reached: %s" % (
                            "; ".join(
                                _fmt_status(driver_id, status)
                                for driver_id, status
                                in zip(ids, last_statuses)
                            )
                        )
                    )
                self.reactor.pause(min(eventtime + poll_s, deadline))
        except ValueError as err:
            raise gcmd.error(str(err))

    def cmd_EMM_HOME_AND_CLEAR(self, gcmd):
        axis = gcmd.get("AXIS", None)
        script = "G28" if axis is None else "G28 %s" % axis.upper()
        self.gcode.run_script_from_command(script)
        toolhead = self.printer.lookup_object("toolhead")
        toolhead.wait_moves()
        self.cmd_EMM_CLEAR_ANGLES(gcmd)

    def cmd_EMM_VERIFY_ANGLES(self, gcmd):
        try:
            ids = _parse_ids(gcmd.get(
                "IDS", ",".join(str(i) for i in self.ids)
            ))
            home = gcmd.get_int("HOME", 1, minval=0, maxval=1)
            axis = gcmd.get("MOVE_AXIS", gcmd.get("AXIS", "Z")).upper()
            if axis not in ("X", "Y", "Z"):
                raise ValueError("AXIS must be X, Y, or Z")
            distance = gcmd.get_float("DISTANCE", 2.0, minval=0.1,
                                      maxval=50.0)
            cycles = gcmd.get_int("CYCLES", 2, minval=1, maxval=20)
            feedrate = gcmd.get_float("FEEDRATE", 300.0, minval=1.0,
                                      maxval=12000.0)
            tolerance = gcmd.get_float("TOLERANCE", 0.2, minval=0.0,
                                       maxval=10.0)
            settle_s = gcmd.get_float("SETTLE", 0.2, minval=0.0,
                                      maxval=10.0)
            timeout_us = gcmd.get_int(
                "TIMEOUT_US", self.timeout_us, minval=1000, maxval=1000000
            )
            clear_read_bytes = gcmd.get_int("READ", 4, minval=0, maxval=64)
        except ValueError as err:
            raise gcmd.error(str(err))

        toolhead = self.printer.lookup_object("toolhead")
        try:
            if home:
                axis = gcmd.get("AXIS", None)
                script = "G28" if axis is None else "G28 %s" % axis.upper()
                self.gcode.run_script_from_command(script)
                toolhead.wait_moves()
                self._clear_angles(ids, clear_read_bytes, timeout_us)
            elif gcmd.get_int("CLEAR", 0, minval=0, maxval=1):
                self._clear_angles(ids, clear_read_bytes, timeout_us)

            if settle_s:
                eventtime = self.reactor.monotonic()
                self.reactor.pause(eventtime + settle_s)
            zero_responses, zero_positions = self._read_positions(
                ids, timeout_us
            )
            self._store_positions(ids, zero_responses, zero_positions)

            move_script = _verify_move_script(axis, distance, cycles, feedrate)
            self.gcode.run_script_from_command(move_script)
            toolhead.wait_moves()

            if settle_s:
                eventtime = self.reactor.monotonic()
                self.reactor.pause(eventtime + settle_s)
            final_responses, final_positions = self._read_positions(
                ids, timeout_us
            )
            self._store_positions(ids, final_responses, final_positions)
        except ValueError as err:
            raise gcmd.error(str(err))

        deltas = _angle_delta(zero_positions, final_positions)
        abs_deltas = [abs(delta) for delta in deltas]
        max_error = max(abs_deltas) if abs_deltas else 0.0
        spread = (max(deltas) - min(deltas)) if deltas else 0.0
        passed = max_error <= tolerance
        summary = (
            "EMM angle verify %s\n"
            "zero: %s\n"
            "final: %s\n"
            "delta: %s\n"
            "max_error=%s deg, spread=%s deg, tolerance=%s deg, "
            "axis=%s, distance=%s mm, cycles=%d, feedrate=%s"
        ) % (
            "PASS" if passed else "FAIL",
            _fmt_angles(ids, zero_positions),
            _fmt_angles(ids, final_positions),
            _fmt_angles(ids, deltas),
            _fmt_float(max_error),
            _fmt_float(spread),
            _fmt_float(tolerance),
            axis,
            _fmt_float(distance),
            cycles,
            _fmt_float(feedrate),
        )
        if not passed:
            raise gcmd.error(summary)
        gcmd.respond_info(summary)

    def cmd_EMM_RECORD_BEGIN(self, gcmd):
        clear = gcmd.get_int("CLEAR", 0, minval=0, maxval=1)
        if clear:
            self.points = []
            self._save_points()
        self._cmd_enable(gcmd, False)

    def cmd_EMM_RECORD_POINT(self, gcmd):
        try:
            ids = _parse_ids(gcmd.get(
                "IDS", ",".join(str(i) for i in self.ids)
            ))
            timeout_us = gcmd.get_int(
                "TIMEOUT_US", self.timeout_us, minval=1000, maxval=1000000
            )
            name = gcmd.get("NAME", "")
            commands = _commands_from_gcmd(gcmd)
            responses, positions = self._read_positions(ids, timeout_us)
        except ValueError as err:
            raise gcmd.error(str(err))
        point = {
            "name": name,
            "time": time.time(),
            "ids": ids,
            "angles": positions,
            "raw": [_fmt_packet(resp) for resp in responses],
            "commands": commands,
        }
        self.points.append(point)
        self._save_points()
        gcmd.respond_info(
            "EMM recorded point #%d%s: %s" % (
                len(self.points) - 1,
                (" %s" % name) if name else "",
                _fmt_point(point),
            )
        )

    def cmd_EMM_SET_POINT_COMMANDS(self, gcmd):
        try:
            index = gcmd.get_int("INDEX", minval=0)
            if index >= len(self.points):
                raise ValueError("Point index out of range: %d" % index)
            commands = _commands_from_gcmd(gcmd)
        except ValueError as err:
            raise gcmd.error(str(err))
        self.points[index]["commands"] = commands
        self._save_points()
        gcmd.respond_info(
            "EMM point #%d commands updated: %d command(s)"
            % (index, len(commands))
        )

    def cmd_EMM_LIST_POINTS(self, gcmd):
        if not self.points:
            gcmd.respond_info("EMM recorded points: <empty>")
            return
        lines = []
        for index, point in enumerate(self.points):
            label = (" %s" % point.get("name")) if point.get("name") else ""
            lines.append("#%d%s: %s" % (index, label, _fmt_point(point)))
        gcmd.respond_info("EMM recorded points:\n" + "\n".join(lines))

    def cmd_EMM_CLEAR_POINTS(self, gcmd):
        count = len(self.points)
        self.points = []
        self._save_points()
        gcmd.respond_info("EMM cleared %d recorded point(s)" % count)

    def cmd_EMM_PLAY_POINTS(self, gcmd):
        if len(self.points) < 1:
            raise gcmd.error("No EMM points recorded")
        try:
            start = gcmd.get_int("START", 0, minval=0)
            end = gcmd.get_int("END", len(self.points) - 1, minval=0)
            segments = gcmd.get_int("SEGMENTS", 10, minval=1, maxval=200)
            speed = gcmd.get_int(
                "SPEED", self.play_speed, minval=1, maxval=65535
            )
            accel = gcmd.get_int(
                "ACCEL", self.play_accel, minval=0, maxval=255
            )
            wait = gcmd.get_float("WAIT", 0.0, minval=0.0, maxval=10.0)
            pace_scale = gcmd.get_float(
                "PACE_SCALE", 1.10, minval=0.1, maxval=5.0
            )
            min_segment_time = gcmd.get_float(
                "MIN_SEGMENT_TIME", 0.0, minval=0.0, maxval=10.0
            )
            inter_packet_delay = gcmd.get_float(
                "INTER_PACKET_DELAY", self.inter_packet_delay,
                minval=MIN_INTER_PACKET_DELAY, maxval=1.0
            )
            timeout_us = gcmd.get_int(
                "TIMEOUT_US", self.timeout_us, minval=1000, maxval=1000000
            )
            confirm = gcmd.get_int("CONFIRM", 0, minval=0, maxval=1)
            auto_enable = gcmd.get_int("AUTO_ENABLE", 1, minval=0, maxval=1)
            points = self._selected_points(gcmd)
            ids = list(points[0]["ids"])
            for point in points:
                if list(point["ids"]) != ids:
                    raise ValueError("All recorded points must use the same IDs")
            steps = _interpolate_point_steps(points, segments, start)
            waypoints = [step["angles"] for step in steps]
            preview_waypoints = [list(angles) for angles in waypoints]
            play_steps = []
            for step in steps:
                play_steps.append({
                    "angles": self._play_angles(step["angles"]),
                    "commands": list(step.get("commands", [])),
                    "point_index": step.get("point_index"),
                })
            compiled_moves = self._compile_play_moves(
                ids, play_steps, speed, accel, pace_scale,
                min_segment_time, wait
            )
        except ValueError as err:
            raise gcmd.error(str(err))

        summary = (
            "EMM play plan: %d recorded point(s), %d target waypoint(s), "
            "segments=%d, speed=%dRPM, accel=%d, wait=%.3fs, "
            "mode=absolute, start=%d, end=%d"
        ) % (len(points), len(waypoints), segments, speed, accel, wait,
             start, end)
        summary += "\nrecorded first: %s" % _fmt_angles(ids, waypoints[0])
        summary += "\nrecorded last: %s" % _fmt_angles(ids, waypoints[-1])
        summary += "\nrecorded delta: %s" % _fmt_angles(
            ids, _angle_delta(preview_waypoints[0], preview_waypoints[-1])
        )
        summary += "\nplay first: %s" % _fmt_angles(ids, preview_waypoints[0])
        summary += "\nplay last: %s" % _fmt_angles(ids, preview_waypoints[-1])
        summary += "\nplay delta: %s" % _fmt_angles(
            ids, _angle_delta(preview_waypoints[0], preview_waypoints[-1])
        )
        summary += "\ncompiled moves: %d, prebuilt packets: %d" % (
            len(compiled_moves), len(compiled_moves) * (len(ids) + 1)
        )
        command_count = sum(len(move["commands"]) for move in compiled_moves)
        summary += "\nattached commands: %d" % command_count
        send_time = (
            len(compiled_moves) * (len(ids) + 1) * inter_packet_delay
        )
        motion_time = sum(move["segment_seconds"] for move in compiled_moves)
        summary += "\npace: scale=%.3f, min_segment_time=%.3fs, inter_packet_delay=%.3fs, planned_time=%.3fs" % (
            pace_scale, min_segment_time,
            inter_packet_delay, motion_time + send_time
        )
        if not confirm:
            summary += "\nAdd CONFIRM=1 to execute."
            gcmd.respond_info(summary)
            return

        total_moves = len(compiled_moves)
        self._set_playback_status(
            active=True,
            current=0,
            total=total_moves,
            progress=0.0,
            start=start,
            end=end,
            message="running",
        )
        move_count = 0
        try:
            if auto_enable:
                self._set_enable(ids, True, timeout_us)
            for move in compiled_moves:
                responses = self._send_packets(
                    move["packets"], 4, timeout_us, inter_packet_delay
                )
                self._check_position_responses(responses)
                sync_response = self._send_packets(
                    [move["sync_packet"]], 4, timeout_us, inter_packet_delay
                )
                self._check_sync_response(sync_response)
                if move["segment_seconds"] > 0.0:
                    eventtime = self.reactor.monotonic()
                    self.reactor.pause(eventtime + move["segment_seconds"])
                self._run_point_commands(move["commands"], move["point_index"])
                move_count += 1
                self._set_playback_status(
                    active=True,
                    current=move_count,
                    total=total_moves,
                    progress=(
                        float(move_count) / float(total_moves)
                        if total_moves else 1.0
                    ),
                    start=start,
                    end=end,
                    message="running",
                )
        except Exception:
            self._set_playback_status(
                active=False,
                current=move_count,
                total=total_moves,
                progress=(
                    float(move_count) / float(total_moves)
                    if total_moves else 0.0
                ),
                start=start,
                end=end,
                message="aborted",
            )
            raise
        self._set_playback_status(
            active=False,
            current=move_count,
            total=total_moves,
            progress=1.0,
            start=start,
            end=end,
            message="complete",
        )
        gcmd.respond_info(
            summary + "\nEMM play executed, move commands sent: %d"
            % move_count
        )

    def _compile_play_moves(self, ids, play_steps, speed, accel,
                            pace_scale, min_segment_time, wait):
        moves = []
        previous_angles = None
        for step in play_steps:
            target_angles = list(step["angles"])
            if previous_angles is None and not any(
                    abs(angle) > 1e-9 for angle in target_angles
            ) and not step.get("commands"):
                previous_angles = target_angles
                continue
            packets = [
                self._position_packet(
                    driver_id, angle, speed, accel, sync=1, absolute=True
                )
                for driver_id, angle in zip(ids, target_angles)
            ]
            if previous_angles is None:
                motion_angles = list(target_angles)
            else:
                motion_angles = _angle_delta(previous_angles, target_angles)
            previous_angles = target_angles
            motion_seconds = self._estimate_motion_seconds(
                motion_angles, speed
            )
            moves.append({
                "packets": packets,
                "sync_packet": [0x00, 0xFF, 0x66, self.checksum],
                "motion_seconds": motion_seconds,
                "segment_seconds": max(
                    motion_seconds * pace_scale, min_segment_time, wait
                ),
                "commands": list(step.get("commands", [])),
                "point_index": step.get("point_index"),
            })
        return moves

    def _run_point_commands(self, commands, point_index):
        if not commands:
            return
        label = (
            "#%d" % point_index if point_index is not None else "interpolated"
        )
        self.gcode.respond_info(
            "EMM running %d attached command(s) at point %s"
            % (len(commands), label)
        )
        self.gcode.run_script_from_command("\n".join(commands))
        toolhead = self.printer.lookup_object("toolhead", None)
        if toolhead is not None:
            toolhead.wait_moves()

    def _send_packets(self, packets, read_bytes, timeout_us,
                      inter_packet_delay=None):
        responses = []
        delay = self._packet_delay(inter_packet_delay)
        with self.mutex:
            for packet in packets:
                params = self.transfer_cmd.send(
                    [self.oid, bytearray(packet), read_bytes, timeout_us]
                )
                responses.append(bytearray(params.get("response", bytearray())))
                if delay:
                    eventtime = self.reactor.monotonic()
                    self.reactor.pause(eventtime + delay)
            self.last_sent = [list(pkt) for pkt in packets]
        self.last_responses = [list(resp) for resp in responses]
        return responses

    def _packet_delay(self, inter_packet_delay):
        if inter_packet_delay is None:
            inter_packet_delay = self.inter_packet_delay
        return max(MIN_INTER_PACKET_DELAY, float(inter_packet_delay))

    def _cmd_enable(self, gcmd, enable):
        try:
            ids = _parse_ids(gcmd.get(
                "IDS", ",".join(str(i) for i in self.ids)
            ))
            timeout_us = gcmd.get_int(
                "TIMEOUT_US", self.timeout_us, minval=1000, maxval=1000000
            )
            responses = self._set_enable(ids, enable, timeout_us)
        except ValueError as err:
            raise gcmd.error(str(err))
        action = "enabled" if enable else "disabled"
        gcmd.respond_info(
            "EMM motors %s for IDs: %s\nEMM responses: %s" % (
                action,
                ", ".join(str(i) for i in ids),
                "; ".join(_fmt_packet(resp) or "<empty>"
                          for resp in responses),
            )
        )

    def _set_enable(self, ids, enable, timeout_us):
        state = 0x01 if enable else 0x00
        packets = [[driver_id, 0xF3, 0xAB, state, 0x00, self.checksum]
                   for driver_id in ids]
        responses = self._send_packets(packets, 4, timeout_us)
        self._check_enable_responses(responses)
        self.motors_enabled = enable
        return responses

    def _check_enable_responses(self, responses):
        for resp in responses:
            if len(resp) != 4 or resp[1] != 0xF3 or resp[2] != 0x02:
                raise ValueError("Invalid EMM enable response: %s"
                                 % _fmt_packet(resp))

    def _read_positions(self, ids, timeout_us):
        packets = [[driver_id, 0x36, self.checksum] for driver_id in ids]
        responses = self._send_packets(packets, 8, timeout_us)
        positions = [_parse_position_response(resp) for resp in responses]
        return responses, positions

    def _clear_angles(self, ids, read_bytes, timeout_us):
        packets = [[driver_id, 0x0A, 0x6D, self.checksum]
                   for driver_id in ids]
        return self._send_packets(packets, read_bytes, timeout_us)

    def _store_positions(self, ids, responses, positions):
        self.last_positions = {
            str(driver_id): {
                "raw": _fmt_packet(resp),
                "angle": pos,
            }
            for driver_id, resp, pos in zip(ids, responses, positions)
        }

    def _read_statuses(self, ids, timeout_us):
        packets = [[driver_id, 0x3A, self.checksum] for driver_id in ids]
        responses = self._send_packets(packets, 4, timeout_us)
        statuses = [
            _parse_status_response(resp, self.checksum)
            for resp in responses
        ]
        return responses, statuses

    def _position_packet(self, driver_id, angle, speed, accel, sync=1,
                         absolute=True):
        direction = 0x01 if angle < 0.0 else 0x00
        pulses = int(round(abs(angle) * self.pulses_per_rev / 360.0))
        if pulses < 0 or pulses > 0xFFFFFFFF:
            raise ValueError("Target angle out of range: %.4f" % angle)
        mode = 0x01 if absolute else 0x00
        return [
            driver_id, 0xFD, direction,
            (speed >> 8) & 0xFF, speed & 0xFF,
            accel & 0xFF,
            (pulses >> 24) & 0xFF, (pulses >> 16) & 0xFF,
            (pulses >> 8) & 0xFF, pulses & 0xFF,
            mode, sync & 0x01, self.checksum,
        ]

    def _check_position_responses(self, responses):
        for resp in responses:
            if len(resp) != 4 or resp[1] != 0xFD or resp[2] != 0x02:
                raise ValueError("Invalid EMM position response: %s"
                                 % _fmt_packet(resp))

    def _check_sync_response(self, responses):
        for resp in responses:
            if len(resp) != 4 or resp[1] != 0xFF or resp[2] != 0x02:
                raise ValueError("Invalid EMM sync response: %s"
                                 % _fmt_packet(resp))

    def _selected_points(self, gcmd):
        start = gcmd.get_int("START", 0, minval=0)
        end = gcmd.get_int("END", len(self.points) - 1, minval=0)
        if start >= len(self.points) or end >= len(self.points) or end < start:
            raise ValueError("Invalid point range START=%d END=%d"
                             % (start, end))
        return self.points[start:end + 1]

    def _play_angles(self, angles):
        if not self.play_direction_inverted:
            return list(angles)
        return [-angle for angle in angles]

    def _estimate_motion_seconds(self, angles, speed_rpm):
        if speed_rpm <= 0:
            return 0.0
        return max(abs(angle) * 60.0 / (360.0 * float(speed_rpm))
                   for angle in angles)

    def _set_playback_status(self, active, current, total, progress,
                             start, end, message):
        self.playback_status = {
            "active": bool(active),
            "current": int(current),
            "total": int(total),
            "progress": max(0.0, min(1.0, float(progress))),
            "start": int(start),
            "end": int(end),
            "message": str(message),
        }

    def _load_points(self):
        self.points = []
        if not self.record_file or not os.path.exists(self.record_file):
            return
        try:
            data = json.loads(open(self.record_file, "r").read())
            if isinstance(data, list):
                self.points = [_normalize_point(point) for point in data]
        except Exception:
            self.points = []

    def _save_points(self):
        if not self.record_file:
            return
        directory = os.path.dirname(self.record_file)
        if directory and not os.path.exists(directory):
            os.makedirs(directory)
        with open(self.record_file, "w") as f:
            json.dump(self.points, f, indent=2, sort_keys=True)


class DisabledEmmUart:
    def __init__(self, config):
        self.enabled = False
        self.baud = config.getint("baud", 115200, minval=1200, maxval=1000000)
        self.timeout_us = config.getint("timeout_us", 20000,
                                        minval=1000, maxval=1000000)
        self.inter_packet_delay = config.getfloat(
            "inter_packet_delay", MIN_INTER_PACKET_DELAY,
            minval=MIN_INTER_PACKET_DELAY
        )
        self.checksum = _parse_byte(config.get("checksum", "0x6B"))
        self.ids = _parse_ids(config.get("ids", "1,2,3"))
        self.default_read_bytes = config.getint(
            "read_bytes", 0, minval=0, maxval=64
        )
        self.pulses_per_rev = config.getfloat(
            "pulses_per_rev", 3200.0, minval=1.0
        )
        self.play_speed = config.getint(
            "play_speed", 120, minval=1, maxval=65535
        )
        self.play_accel = config.getint(
            "play_accel", 10, minval=0, maxval=255
        )
        self.play_direction_inverted = config.getboolean(
            "play_direction_inverted", False
        )
        self.record_file = config.get(
            "record_file",
            os.path.expanduser("~/printer_data/config/emm_points.json"),
        )

    def get_status(self, eventtime):
        return {
            "enabled": self.enabled,
            "baud": self.baud,
            "timeout_us": self.timeout_us,
            "ids": self.ids,
            "read_bytes": self.default_read_bytes,
            "last_statuses": {},
            "points": 0,
            "pulses_per_rev": self.pulses_per_rev,
            "play_direction_inverted": self.play_direction_inverted,
            "playback": {
                "active": False,
                "current": 0,
                "total": 0,
                "progress": 0.0,
                "start": 0,
                "end": 0,
                "message": "disabled",
            },
        }


def _parse_position_response(resp):
    resp = bytearray(resp)
    if len(resp) != 8 or resp[1] != 0x36 or resp[-1] != 0x6B:
        raise ValueError("Invalid EMM position response: %s" % _fmt_packet(resp))
    sign = -1 if resp[2] else 1
    value = ((resp[3] << 24) | (resp[4] << 16) | (resp[5] << 8) | resp[6])
    return sign * value * 360.0 / 65536.0


def _parse_status_response(resp, checksum=0x6B):
    resp = bytearray(resp)
    if len(resp) != 4 or resp[1] != 0x3A or resp[-1] != checksum:
        raise ValueError("Invalid EMM status response: %s" % _fmt_packet(resp))
    return int(resp[2])


def _status_reached(status):
    return bool(status & 0x02)


def _status_dict(resp, status):
    return {
        "raw": _fmt_packet(resp),
        "status": status,
        "enabled": bool(status & 0x01),
        "reached": bool(status & 0x02),
        "stalled": bool(status & 0x04),
        "stall_protection": bool(status & 0x08),
    }


def _fmt_status(driver_id, status):
    flags = []
    if status & 0x01:
        flags.append("enabled")
    if status & 0x02:
        flags.append("reached")
    if status & 0x04:
        flags.append("stalled")
    if status & 0x08:
        flags.append("stall_protection")
    if not flags:
        flags.append("none")
    return "ID%d=0x%02X(%s)" % (driver_id, status, ",".join(flags))


def _normalize_point(point):
    ids = [int(v) for v in point["ids"]]
    angles = [float(v) for v in point["angles"]]
    if len(ids) != len(angles):
        raise ValueError("point ids/angles length mismatch")
    return {
        "name": str(point.get("name", "")),
        "time": float(point.get("time", 0.0)),
        "ids": ids,
        "angles": angles,
        "raw": list(point.get("raw", [])),
        "commands": _normalize_commands(
            point.get("commands", point.get("command", []))
        ),
    }


def _interpolate_points(points, segments):
    return [step["angles"] for step in _interpolate_point_steps(
        points, segments
    )]


def _interpolate_point_steps(points, segments, start_index=0):
    steps = [{
        "angles": list(points[0]["angles"]),
        "commands": list(points[0].get("commands", [])),
        "point_index": start_index,
    }]
    for offset, (left, right) in enumerate(zip(points[:-1], points[1:]), 1):
        a = list(left["angles"])
        b = list(right["angles"])
        if len(a) != len(b):
            raise ValueError("point angle length mismatch")
        for step in range(1, segments + 1):
            t = float(step) / float(segments)
            is_recorded_point = step == segments
            steps.append({
                "angles": [av + (bv - av) * t for av, bv in zip(a, b)],
                "commands": (
                    list(right.get("commands", []))
                    if is_recorded_point else []
                ),
                "point_index": (
                    start_index + offset if is_recorded_point else None
                ),
            })
    return steps


def _fmt_point(point):
    commands = point.get("commands", [])
    suffix = "" if not commands else " + %d command(s)" % len(commands)
    return _fmt_angles(point["ids"], point["angles"]) + suffix


def _commands_from_gcmd(gcmd):
    return _decode_commands_b64(gcmd.get("COMMANDS_B64", ""))


def _decode_commands_b64(value):
    text = str(value or "").strip()
    if not text:
        return []
    padding = "=" * ((4 - len(text) % 4) % 4)
    try:
        decoded = base64.urlsafe_b64decode((text + padding).encode("ascii"))
    except Exception as err:
        raise ValueError("Invalid COMMANDS_B64: %s" % err)
    return _normalize_commands(decoded.decode("utf-8"))


def _normalize_commands(value):
    if value is None:
        return []
    if isinstance(value, str):
        raw_lines = value.splitlines()
    elif isinstance(value, (list, tuple)):
        raw_lines = value
    else:
        raw_lines = [value]
    commands = []
    for line in raw_lines:
        command = str(line).strip()
        if command:
            commands.append(command)
    return commands


def _fmt_angles(ids, angles):
    return ", ".join(
        "ID%d=%s deg" % (driver_id, _fmt_float(angle))
        for driver_id, angle in zip(ids, angles)
    )


def _angle_delta(start, end):
    return [ev - sv for sv, ev in zip(start, end)]


def _verify_move_script(axis, distance, cycles, feedrate):
    distance_text = _fmt_float(distance)
    feedrate_text = _fmt_float(feedrate)
    first = "-%s" % distance_text if axis == "Z" else distance_text
    second = distance_text if axis == "Z" else "-%s" % distance_text
    lines = [
        "SAVE_GCODE_STATE NAME=EMM_VERIFY_ANGLES",
        "G91",
    ]
    for _ in range(cycles):
        lines.extend([
            "G1 %s%s F%s" % (axis, first, feedrate_text),
            "G1 %s%s F%s" % (axis, second, feedrate_text),
        ])
    lines.extend([
        "M400",
        "RESTORE_GCODE_STATE NAME=EMM_VERIFY_ANGLES",
    ])
    return "\n".join(lines)


def _parse_byte(value):
    if isinstance(value, int):
        byte = value
    else:
        byte = int(str(value).strip(), 0)
    if byte < 0 or byte > 0xFF:
        raise ValueError("byte value out of range: %r" % (value,))
    return byte


def _parse_ids(value):
    if isinstance(value, (list, tuple)):
        raw_ids = value
    else:
        text = str(value).strip()
        if text.startswith("["):
            raw_ids = ast.literal_eval(text)
        else:
            raw_ids = [part.strip() for part in text.split(",") if part.strip()]
    ids = []
    for item in raw_ids:
        driver_id = int(item, 0) if isinstance(item, str) else int(item)
        if driver_id < 1 or driver_id > 255:
            raise ValueError("EMM driver ID out of range: %r" % (item,))
        ids.append(driver_id)
    if not ids:
        raise ValueError("At least one EMM driver ID is required")
    return ids


def _parse_hex_bytes(text):
    cleaned = (
        text.replace(",", " ")
        .replace(";", " ")
        .replace("0x", "")
        .replace("0X", "")
    )
    if " " not in cleaned:
        cleaned = cleaned.strip()
        if len(cleaned) % 2:
            raise ValueError("HEX payload must contain whole bytes")
        cleaned = " ".join(
            cleaned[index:index + 2] for index in range(0, len(cleaned), 2)
        )
    packet = []
    for part in cleaned.split():
        byte = int(part, 16)
        if byte < 0 or byte > 0xFF:
            raise ValueError("HEX byte out of range: %r" % part)
        packet.append(byte)
    if not packet:
        raise ValueError("HEX payload is empty")
    return packet


def _fmt_packet(packet):
    return " ".join("%02X" % (byte & 0xFF) for byte in packet)


def _fmt_float(value):
    return "%.4f" % value


def load_config(config):
    if not config.getboolean("enabled", True):
        return DisabledEmmUart(config)
    return EmmUart(config)
