#!/usr/bin/env python3
"""Read, apply, and persist Hyprland pointer settings for the Mouse panel."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path(os.environ.get("HOME", str(Path.home())))
HYPR_DIR = HOME / ".config" / "hypr"
MOUSE_LUA = HYPR_DIR / "mouse.lua"
HYPRLAND_LUA = HYPR_DIR / "hyprland.lua"
INPUT_DEVICES = Path("/proc/bus/input/devices")

OPTIONS = {
    "sensitivity": "input:sensitivity",
    "accelProfile": "input:accel_profile",
    "naturalScroll": "input:natural_scroll",
    "scrollFactor": "input:scroll_factor",
    "leftHanded": "input:left_handed",
    "touchpadNaturalScroll": "input:touchpad:natural_scroll",
    "touchpadScrollFactor": "input:touchpad:scroll_factor",
    "disableWhileTyping": "input:touchpad:disable_while_typing",
    "tapToClick": "input:touchpad:tap-to-click",
    "clickfingerBehavior": "input:touchpad:clickfinger_behavior",
}

# Hyprland has no way to read a per-device value back, so the touchpad's own
# speed, acceleration and primary button live in mouse.lua as one hl.device line
# per touchpad and are read from there.
TOUCHPAD_OVERRIDE = re.compile(
    r'^hl\.device\(\{ name = "((?:[^"\\]|\\.)*)", (.*) \}\)$',
    re.MULTILINE,
)

SENSITIVITY_KEYS = {"sensitivity", "touchpadSensitivity"}
FLOAT_KEYS = SENSITIVITY_KEYS | {"scrollFactor", "touchpadScrollFactor"}
ACCEL_KEYS = {"accelProfile", "touchpadAccelProfile"}
BOOL_KEYS = {
    "naturalScroll",
    "leftHanded",
    "touchpadLeftHanded",
    "touchpadNaturalScroll",
    "disableWhileTyping",
    "tapToClick",
    "clickfingerBehavior",
}


def run(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, check=False, text=True, capture_output=True)


def hypr_option(name: str) -> dict:
    proc = run(["hyprctl", "-j", "getoption", name])
    if proc.returncode != 0 or not proc.stdout.strip():
        return {}
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {}


def option_str(data: dict) -> str:
    value = data.get("str")
    if value in (None, "", "[[EMPTY]]"):
        return ""
    return str(value)


def option_bool(data: dict, fallback: bool) -> bool:
    if "bool" in data:
        return bool(data["bool"])
    return fallback


def option_float(data: dict, fallback: float) -> float:
    if "float" in data:
        try:
            return float(data["float"])
        except (TypeError, ValueError):
            return fallback
    if "int" in data:
        try:
            return float(data["int"])
        except (TypeError, ValueError):
            return fallback
    return fallback


def connected_touchpads() -> list[str]:
    proc = run(["hyprctl", "-j", "devices"])
    if proc.returncode != 0 or not proc.stdout.strip():
        return []
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []
    names = []
    for mouse in payload.get("mice") or []:
        name = str(mouse.get("name") or "")
        lowered = name.lower()
        if "touchpad" in lowered or "trackpad" in lowered:
            names.append(name)
    return names


def connected_mouse() -> bool:
    """Whether a real mouse is attached, as opposed to a node that only looks like one.

    Keyboards expose a mouse node for mouse keys, gaming mice expose keyboard
    nodes for macros, and touchpads expose a mouse twin. All of them report the
    same capabilities, so what tells them apart is the function a physical
    device registers first. If the devices can't be read, assume a mouse rather
    than hide its settings.
    """
    try:
        text = INPUT_DEVICES.read_text(encoding="utf-8")
    except OSError:
        return True
    physical_devices: dict[tuple, list[tuple[str, str]]] = {}
    for block in text.split("\n\n"):
        identity = re.search(r"Bus=(\w+) Vendor=(\w+) Product=(\w+)", block)
        name = re.search(r'^N: Name="(.*)"$', block, re.MULTILINE)
        handlers = re.search(r"^H: Handlers=(.*)$", block, re.MULTILINE)
        if not (identity and name and handlers):
            continue
        uniq = re.search(r"^U: Uniq=(.*)$", block, re.MULTILINE)
        phys = re.search(r"^P: Phys=(.*)$", block, re.MULTILINE)
        location = (uniq and uniq.group(1)) or (phys and phys.group(1).rsplit("/", 1)[0]) or ""
        key = (*identity.groups(), location)
        physical_devices.setdefault(key, []).append((name.group(1).lower(), handlers.group(1)))
    for nodes in physical_devices.values():
        if any("touchpad" in node or "trackpad" in node for node, _ in nodes):
            continue
        functions = [h for _, h in nodes if re.search(r"\b(mouse\d+|kbd)\b", h)]
        if functions and re.search(r"\bmouse\d+\b", functions[0]):
            return True
    return False


def saved_touchpad_overrides() -> dict[str, dict]:
    try:
        text = MOUSE_LUA.read_text(encoding="utf-8")
    except OSError:
        return {}
    overrides: dict[str, dict] = {}
    for name, fields in TOUCHPAD_OVERRIDE.findall(text):
        override: dict = {}
        speed = re.search(r"sensitivity = (-?\d+(?:\.\d+)?)", fields)
        accel = re.search(r'accel_profile = "([^"]*)"', fields)
        left_handed = re.search(r"left_handed = (true|false)", fields)
        if speed:
            override["sensitivity"] = float(speed.group(1))
        if accel:
            override["accelProfile"] = accel.group(1)
        if left_handed:
            override["leftHanded"] = left_handed.group(1) == "true"
        overrides[re.sub(r"\\(.)", r"\1", name)] = override
    return overrides


def normalize_accel(value: object) -> str:
    text = str(value or "").strip().lower()
    if text in ("", "[[empty]]", "adaptive", "default"):
        return "adaptive"
    if text == "flat":
        return "flat"
    if text.startswith("custom"):
        return str(value).strip()
    return "adaptive"


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def current_state() -> dict:
    accel = normalize_accel(option_str(hypr_option(OPTIONS["accelProfile"])))
    if accel.startswith("custom"):
        accel_profile = accel
    else:
        accel_profile = "flat" if accel == "flat" else "adaptive"
    sensitivity = clamp(option_float(hypr_option(OPTIONS["sensitivity"]), 0.0), -1.0, 1.0)
    touchpads = connected_touchpads()
    overrides = saved_touchpad_overrides()
    override = next(iter(overrides.values()), {})
    left_handed = option_bool(hypr_option(OPTIONS["leftHanded"]), False)
    return {
        "sensitivity": sensitivity,
        "accelProfile": accel_profile,
        "naturalScroll": option_bool(hypr_option(OPTIONS["naturalScroll"]), False),
        "scrollFactor": clamp(option_float(hypr_option(OPTIONS["scrollFactor"]), 1.0), 0.1, 2.0),
        "leftHanded": left_handed,
        "touchpadNaturalScroll": option_bool(hypr_option(OPTIONS["touchpadNaturalScroll"]), False),
        "touchpadScrollFactor": clamp(
            option_float(hypr_option(OPTIONS["touchpadScrollFactor"]), 0.4), 0.1, 2.0
        ),
        "disableWhileTyping": option_bool(hypr_option(OPTIONS["disableWhileTyping"]), True),
        "tapToClick": option_bool(hypr_option(OPTIONS["tapToClick"]), True),
        "clickfingerBehavior": option_bool(hypr_option(OPTIONS["clickfingerBehavior"]), True),
        # Until an override exists the touchpad follows the global settings.
        "touchpadSensitivity": clamp(override.get("sensitivity", sensitivity), -1.0, 1.0),
        "touchpadAccelProfile": normalize_accel(override.get("accelProfile", accel_profile)),
        "touchpadLeftHanded": override.get("leftHanded", left_handed),
        # Saved names stay so a disconnected touchpad keeps its speed.
        "touchpadNames": sorted({*touchpads, *overrides}),
        "hasMouse": connected_mouse(),
        "hasTouchpad": bool(touchpads),
    }


def merge_state(raw: object) -> dict:
    state = current_state()
    if not isinstance(raw, dict):
        return state
    for key in state:
        if key not in raw:
            continue
        if key in BOOL_KEYS:
            state[key] = bool(raw[key])
        elif key in FLOAT_KEYS:
            try:
                number = float(raw[key])
            except (TypeError, ValueError):
                continue
            if key in SENSITIVITY_KEYS:
                state[key] = clamp(number, -1.0, 1.0)
            else:
                state[key] = clamp(number, 0.1, 2.0)
        elif key in ACCEL_KEYS:
            state[key] = normalize_accel(raw[key])
    return state


def keyword_value(key: str, value: object) -> str:
    if key in BOOL_KEYS:
        return "true" if value else "false"
    if key in FLOAT_KEYS:
        return f"{float(value):.2f}"
    if key in ACCEL_KEYS:
        profile = normalize_accel(value)
        return "flat" if profile == "flat" else ("adaptive" if profile == "adaptive" else profile)
    return str(value)


def lua_bool(value: bool) -> str:
    return "true" if value else "false"


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_config(state: dict, pretty: bool = False) -> str:
    accel = keyword_value("accelProfile", state["accelProfile"])
    compact = (
        "hl.config({ input = { "
        f"sensitivity = {float(state['sensitivity']):.2f}, "
        f"accel_profile = {lua_string(accel)}, "
        f"natural_scroll = {lua_bool(bool(state['naturalScroll']))}, "
        f"scroll_factor = {float(state['scrollFactor']):.2f}, "
        f"left_handed = {lua_bool(bool(state['leftHanded']))}, "
        "touchpad = { "
        f"natural_scroll = {lua_bool(bool(state['touchpadNaturalScroll']))}, "
        f"scroll_factor = {float(state['touchpadScrollFactor']):.2f}, "
        f"disable_while_typing = {lua_bool(bool(state['disableWhileTyping']))}, "
        f"tap_to_click = {lua_bool(bool(state['tapToClick']))}, "
        f"clickfinger_behavior = {lua_bool(bool(state['clickfingerBehavior']))} "
        "} } })"
    )
    if not pretty:
        return compact
    return f"""hl.config({{
  input = {{
    sensitivity = {float(state["sensitivity"]):.2f},
    accel_profile = {lua_string(accel)},
    natural_scroll = {lua_bool(bool(state["naturalScroll"]))},
    scroll_factor = {float(state["scrollFactor"]):.2f},
    left_handed = {lua_bool(bool(state["leftHanded"]))},
    touchpad = {{
      natural_scroll = {lua_bool(bool(state["touchpadNaturalScroll"]))},
      scroll_factor = {float(state["touchpadScrollFactor"]):.2f},
      disable_while_typing = {lua_bool(bool(state["disableWhileTyping"]))},
      tap_to_click = {lua_bool(bool(state["tapToClick"]))},
      clickfinger_behavior = {lua_bool(bool(state["clickfingerBehavior"]))},
    }},
  }},
}})"""


def lua_touchpad_overrides(state: dict) -> str:
    fields = (
        f'sensitivity = {float(state["touchpadSensitivity"]):.2f}, '
        f'accel_profile = {lua_string(keyword_value("touchpadAccelProfile", state["touchpadAccelProfile"]))}, '
        f'left_handed = {lua_bool(bool(state["touchpadLeftHanded"]))}'
    )
    # Device names come from hardware; only printable ones can go in Lua.
    return "".join(
        f"hl.device({{ name = {lua_string(name)}, {fields} }})\n"
        for name in state["touchpadNames"]
        if name.isprintable()
    )


def apply_live(state: dict) -> None:
    # Lua-parser sessions reject `hyprctl keyword`; eval applies the same table
    # the persisted mouse.lua uses.
    proc = run(["hyprctl", "eval", lua_config(state) + "\n" + lua_touchpad_overrides(state)])
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr or proc.stdout or "hyprctl eval failed\n")


def persist_lua(state: dict) -> None:
    HYPR_DIR.mkdir(parents=True, exist_ok=True)
    body = (
        "-- Generated by the Mouse panel plugin (io.github.wouldja.mouse). Use the panel to edit.\n"
        + lua_config(state, pretty=True)
        + "\n"
        + lua_touchpad_overrides(state)
    )
    tmp = MOUSE_LUA.with_suffix(".lua.tmp")
    tmp.write_text(body, encoding="utf-8")
    tmp.replace(MOUSE_LUA)


def ensure_hyprland_require() -> None:
    if not HYPRLAND_LUA.exists():
        return
    text = HYPRLAND_LUA.read_text(encoding="utf-8")
    if 'require("hypr.mouse")' in text or "require('hypr.mouse')" in text:
        return
    backup = HYPRLAND_LUA.with_suffix(f".lua.bak.{os.getpid()}")
    backup.write_text(text, encoding="utf-8")
    needle = 'require("hypr.input")'
    insert = 'require("hypr.input")\nrequire("hypr.mouse")'
    if needle in text:
        text = text.replace(needle, insert, 1)
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += '\nrequire("hypr.mouse")\n'
    HYPRLAND_LUA.write_text(text, encoding="utf-8")


def read_payload() -> dict:
    if len(sys.argv) >= 3:
        raw = " ".join(sys.argv[2:])
    else:
        raw = sys.stdin.read()
    raw = raw.strip()
    if not raw:
        return {}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid json: {exc}") from exc
    if not isinstance(parsed, dict):
        raise SystemExit("payload must be a json object")
    return parsed


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        sys.stderr.write("usage: apply.py get | devices | live [json] | apply [json] | ensure\n")
        return 2

    command = sys.argv[1]
    if command == "get":
        json.dump(current_state(), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    if command == "devices":
        devices = {"hasMouse": connected_mouse(), "hasTouchpad": bool(connected_touchpads())}
        json.dump(devices, sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    if command == "ensure":
        state = current_state()
        persist_lua(state)
        ensure_hyprland_require()
        json.dump(state, sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    if command in ("live", "apply"):
        state = merge_state(read_payload())
        apply_live(state)
        if command == "apply":
            persist_lua(state)
            ensure_hyprland_require()
        json.dump(state, sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    sys.stderr.write(f"unknown command: {command}\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
