import logging
import re

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
from ks_includes.screen_panel import ScreenPanel


class Panel(ScreenPanel):

    def __init__(self, screen, title):
        title = title or "挤出"
        super().__init__(screen, title)

        self.volumes = ["2", "5", "8", "10", "20", "100"]
        self.rates = ["10", "20", "40", "60", "80", "120"]
        self.retracts = ["5", "8", "10", "12", "15", "20"]
        self.distances = ["0.02", "0.05", "0.1", "0.2", "0.5", "1"]
        self.speeds = ["0.05", "0.1", "0.2", "0.5", "1"]

        if self.ks_printer_cfg is not None:
            self.volumes = self.read_numeric_list("paste_volumes", self.volumes)
            self.rates = self.read_numeric_list("paste_rates", self.rates)
            self.retracts = self.read_numeric_list("paste_retracts", self.retracts)
            self.distances = self.read_numeric_list("paste_distances", self.distances)
            self.speeds = self.read_numeric_list("paste_speeds", self.speeds)

        self.volume = self.default_value(self.volumes, "8")
        self.rate = self.default_value(self.rates, "40")
        self.retract = self.default_value(self.retracts, "8")
        self.distance = self.default_value(self.distances, "0.1")
        self.speed = self.default_value(self.speeds, "0.2")
        self.menu.append("extrude_menu")

        self.buttons = {
            "start": self._gtk.Button("extrude", "开始预压", "color4"),
            "stop": self._gtk.Button("retract", "停胶回抽", "color1"),
            "dot": self._gtk.Button("extrude", "单点点胶", "color3"),
            "prime": self._gtk.Button("extrude", "预填充", "color2"),
            "status": self._gtk.Button("info", "状态", "color2"),
            "tune": self._gtk.Button("settings", "应用参数", "color3"),
            "zero": self._gtk.Button("refresh", "软件归零", "color2"),
            "disable": self._gtk.Button("motor-off", "关闭电机", "color1"),
            "push": self._gtk.Button("extrude", "手动推进", "color4"),
            "pull": self._gtk.Button("retract", "手动回抽", "color1"),
        }
        self.buttons["start"].connect("clicked", self.paste_start)
        self.buttons["stop"].connect("clicked", self.paste_stop)
        self.buttons["dot"].connect("clicked", self.paste_dot)
        self.buttons["prime"].connect("clicked", self.paste_prime)
        self.buttons["status"].connect("clicked", self.send_script, "PASTE_STATUS")
        self.buttons["tune"].connect("clicked", self.paste_tune)
        self.buttons["zero"].connect("clicked", self.send_script, "PASTE_ZERO")
        self.buttons["disable"].connect("clicked", self.send_script, "PASTE_DISABLE")
        self.buttons["push"].connect("clicked", self.move_paste, "PASTE_PUSH")
        self.buttons["pull"].connect("clicked", self.move_paste, "PASTE_PULL")

        volume_box = self.build_option_box("点胶量 (uL)", "volume", self.volumes, self.volume, self.change_volume)
        rate_box = self.build_option_box("速率 (uL/s)", "rate", self.rates, self.rate, self.change_rate)
        retract_box = self.build_option_box("停胶回抽 (uL)", "retract", self.retracts, self.retract, self.change_retract)
        distance_box = self.build_option_box("手动行程 (mm)", "dist", self.distances, self.distance, self.change_distance)
        speed_box = self.build_option_box("手动速度 (mm/s)", "speed", self.speeds, self.speed, self.change_speed)

        info = Gtk.Label()
        info.set_line_wrap(True)
        info.set_markup("<b>Sn42/Bi58 CD-LT528</b>  10cc / 18G / paste_pump")
        self.labels["paste_status"] = info

        grid = Gtk.Grid(row_homogeneous=False, column_homogeneous=True)
        grid.set_row_spacing(8)
        grid.set_column_spacing(8)

        if self._screen.vertical_mode:
            grid.attach(self.buttons["start"], 0, 0, 2, 1)
            grid.attach(self.buttons["stop"], 2, 0, 2, 1)
            grid.attach(self.buttons["dot"], 0, 1, 2, 1)
            grid.attach(self.buttons["prime"], 2, 1, 2, 1)
            grid.attach(self.buttons["status"], 0, 2, 1, 1)
            grid.attach(self.buttons["tune"], 1, 2, 1, 1)
            grid.attach(self.buttons["zero"], 2, 2, 1, 1)
            grid.attach(self.buttons["disable"], 3, 2, 1, 1)
            grid.attach(volume_box, 0, 3, 4, 1)
            grid.attach(rate_box, 0, 4, 4, 1)
            grid.attach(retract_box, 0, 5, 4, 1)
            grid.attach(self.buttons["push"], 0, 6, 2, 1)
            grid.attach(self.buttons["pull"], 2, 6, 2, 1)
            grid.attach(distance_box, 0, 7, 4, 1)
            grid.attach(speed_box, 0, 8, 4, 1)
            grid.attach(info, 0, 9, 4, 1)
        else:
            grid.attach(self.buttons["start"], 0, 0, 1, 1)
            grid.attach(self.buttons["stop"], 1, 0, 1, 1)
            grid.attach(self.buttons["dot"], 2, 0, 1, 1)
            grid.attach(self.buttons["prime"], 3, 0, 1, 1)
            grid.attach(self.buttons["status"], 4, 0, 1, 1)
            grid.attach(self.buttons["disable"], 5, 0, 1, 1)
            grid.attach(volume_box, 0, 1, 3, 1)
            grid.attach(rate_box, 3, 1, 3, 1)
            grid.attach(retract_box, 0, 2, 3, 1)
            grid.attach(self.buttons["tune"], 3, 2, 1, 1)
            grid.attach(self.buttons["zero"], 4, 2, 1, 1)
            grid.attach(info, 5, 2, 1, 1)
            grid.attach(self.buttons["push"], 0, 3, 1, 1)
            grid.attach(self.buttons["pull"], 1, 3, 1, 1)
            grid.attach(distance_box, 2, 3, 2, 1)
            grid.attach(speed_box, 4, 3, 2, 1)

        self.labels["extrude_menu"] = grid
        self.content.add(self.labels["extrude_menu"])

    def read_numeric_list(self, key, default):
        values = self.ks_printer_cfg.get(key, "")
        if not re.match(r"^[0-9,\.\s]+$", values):
            return default
        values = [i.strip() for i in values.split(",") if i.strip()]
        return values if 1 < len(values) <= 8 else default

    @staticmethod
    def default_value(values, preferred):
        return preferred if preferred in values else values[0]

    def build_option_box(self, title, prefix, values, active, callback):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.labels[f"{prefix}_title"] = Gtk.Label(title)
        box.pack_start(self.labels[f"{prefix}_title"], True, True, 0)
        box.add(self.build_toggle_grid(prefix, values, active, callback))
        return box

    def build_toggle_grid(self, prefix, values, active, callback):
        grid = Gtk.Grid(column_homogeneous=True)
        for index, value in enumerate(values):
            key = f"{prefix}{value}"
            self.labels[key] = self._gtk.Button(label=value)
            self.labels[key].connect("clicked", callback, value)
            context = self.labels[key].get_style_context()
            context.add_class("horizontal_togglebuttons")
            if self._screen.vertical_mode:
                context.add_class("horizontal_togglebuttons_smaller")
            if value == active:
                context.add_class("horizontal_togglebuttons_active")
            grid.attach(self.labels[key], index, 0, 1, 1)
        return grid

    def activate(self):
        self.enable_buttons(self._printer.state in ("ready", "paused"))

    def enable_buttons(self, enable):
        for button in self.buttons.values():
            button.set_sensitive(enable)

    def process_update(self, action, data):
        if action == "notify_status_update":
            self.enable_buttons(self._printer.state in ("ready", "paused"))
        elif action == "notify_gcode_response" and (
            "Unknown command" in data or "Paste " in data or "error" in data.lower()
        ):
            self._screen.show_popup_message(data)

    def update_active(self, prefix, old_value, new_value):
        self.labels[f"{prefix}{old_value}"].get_style_context().remove_class("horizontal_togglebuttons_active")
        self.labels[f"{prefix}{new_value}"].get_style_context().add_class("horizontal_togglebuttons_active")

    def change_volume(self, widget, volume):
        logging.info(f"Paste volume: {volume} uL")
        self.update_active("volume", self.volume, volume)
        self.volume = volume

    def change_rate(self, widget, rate):
        logging.info(f"Paste rate: {rate} uL/s")
        self.update_active("rate", self.rate, rate)
        self.rate = rate

    def change_retract(self, widget, retract):
        logging.info(f"Paste retract: {retract} uL")
        self.update_active("retract", self.retract, retract)
        self.retract = retract

    def change_distance(self, widget, distance):
        logging.info(f"Paste distance: {distance} mm")
        self.update_active("dist", self.distance, distance)
        self.distance = distance

    def change_speed(self, widget, speed):
        logging.info(f"Paste speed: {speed} mm/s")
        self.update_active("speed", self.speed, speed)
        self.speed = speed

    def send_script(self, widget, script):
        self._screen._send_action(widget, "printer.gcode.script", {"script": script})

    def paste_start(self, widget):
        script = f"PASTE_START UL={float(self.volume):g} RATE={float(self.rate):g}"
        self.send_script(widget, script)

    def paste_stop(self, widget):
        script = f"PASTE_STOP UL={float(self.retract):g} RATE={float(self.rate):g}"
        self.send_script(widget, script)

    def paste_dot(self, widget):
        script = (
            f"PASTE_DOT UL={float(self.volume):g} RATE={float(self.rate):g} "
            f"RETRACT={float(self.retract):g}"
        )
        self.send_script(widget, script)

    def paste_prime(self, widget):
        script = f"PASTE_PRIME_LINE UL={float(self.volume):g} RATE={float(self.rate):g}"
        self.send_script(widget, script)

    def paste_tune(self, widget):
        script = (
            f"PASTE_TUNE PRIME_UL={float(self.volume):g} PRIME_RATE={float(self.rate):g} "
            f"RETRACT_UL={float(self.retract):g} RETRACT_RATE={float(self.rate):g}"
        )
        self.send_script(widget, script)

    def move_paste(self, widget, macro):
        distance = float(self.distance)
        speed = float(self.speed)
        script = f"{macro} MM={distance:g} SPEED={speed:g}"
        self.send_script(widget, script)
