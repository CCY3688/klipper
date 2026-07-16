#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
import subprocess
from pathlib import Path


DEFAULTS = {
    "group_x_offset": 0,
    "group_y_offset": -80,
    "logo_scale": 0.5,
    "logo_x_offset": 0,
    "logo_y_offset": 0,
    "slogan_scale": 0.65,
    "slogan_x_offset": 0,
    "slogan_y_offset": 0,
    "slogan_gap": 8,
}


def find_klipperscreen_dir():
    script_dir = Path(__file__).resolve().parent
    if (script_dir / "panels").exists() and (script_dir / "styles").exists():
        return script_dir
    if (script_dir.parent / "panels").exists() and (script_dir.parent / "styles").exists():
        return script_dir.parent
    return Path("/home/umeko/KlipperScreen")


KLIPPERSCREEN_DIR = find_klipperscreen_dir()
LAYOUT_FILE = KLIPPERSCREEN_DIR / "styles" / "official_brand_layout.json"


def load_layout():
    layout = DEFAULTS.copy()
    if LAYOUT_FILE.exists():
        with LAYOUT_FILE.open("r", encoding="utf-8") as config:
            saved = json.load(config)
        if isinstance(saved, dict):
            layout.update({key: saved[key] for key in DEFAULTS if key in saved})
    return layout


def save_layout(layout):
    LAYOUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LAYOUT_FILE.open("w", encoding="utf-8") as config:
        json.dump(layout, config, ensure_ascii=False, indent=2)
        config.write("\n")


def ask_float(prompt, default=None):
    suffix = f" [{default}]" if default is not None else ""
    value = input(f"{prompt}{suffix}: ").strip()
    if value == "":
        return default
    return float(value)


def move(layout, target, direction, distance):
    if direction == "none" or distance == 0:
        return
    if target == "both":
        keys = ["logo", "slogan"]
    elif target in ("logo", "slogan"):
        keys = [target]
    else:
        keys = ["group"]

    dx = dy = 0
    if direction == "up":
        dy = -distance
    elif direction == "down":
        dy = distance
    elif direction == "left":
        dx = -distance
    elif direction == "right":
        dx = distance
    else:
        raise ValueError("方向只能输入 up/down/left/right/none")

    for key in keys:
        layout[f"{key}_x_offset"] = float(layout[f"{key}_x_offset"]) + dx
        layout[f"{key}_y_offset"] = float(layout[f"{key}_y_offset"]) + dy


def update_scale(layout, target):
    if target in ("logo", "both"):
        layout["logo_scale"] = ask_float("logo 缩放比例，例如 0.50", layout["logo_scale"])
    if target in ("slogan", "both"):
        layout["slogan_scale"] = ask_float("slogan 缩放比例，例如 0.65", layout["slogan_scale"])
    if target == "group":
        print("group 只控制整体位置；logo/slogan 的大小请分别调整。")


def print_layout(layout):
    print("\n当前配置:")
    print(json.dumps(layout, ensure_ascii=False, indent=2))


def main():
    layout = load_layout()
    print("官方 logo / 口号位置与大小调整脚本")
    print(f"配置文件: {LAYOUT_FILE}")
    print_layout(layout)

    target = input("\n调整对象 logo/slogan/group/both [logo]: ").strip().lower() or "logo"
    if target not in ("logo", "slogan", "group", "both"):
        raise ValueError("调整对象只能输入 logo/slogan/group/both")

    direction = input("移动方向 up/down/left/right/none [none]: ").strip().lower() or "none"
    distance = ask_float("移动距离，单位 px", 20)
    move(layout, target, direction, distance)
    update_scale(layout, target)

    if target in ("slogan", "both"):
        layout["slogan_gap"] = ask_float("logo 与口号之间的间距 px", layout["slogan_gap"])

    save_layout(layout)
    print_layout(layout)
    print("\n已保存。")

    restart = input("是否立即重启 KlipperScreen.service 生效？ y/N: ").strip().lower()
    if restart == "y":
        subprocess.run(["sudo", "systemctl", "restart", "KlipperScreen.service"], check=True)
        subprocess.run(["systemctl", "is-active", "KlipperScreen.service"], check=False)


if __name__ == "__main__":
    main()
