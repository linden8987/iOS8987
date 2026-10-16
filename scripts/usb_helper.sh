#!/usr/bin/env python3
"""
LVGL GUI launcher for iOS8987.

This version does not hard-code a repository folder name. It resolves the repo root
from the file location and allows override via the IOSTOOL_ROOT environment var.
"""
import os
import sys
import time
import threading
import subprocess

try:
    import lvgl as lv
except Exception as exc:  # pragma: no cover
    raise SystemExit(f"LVGL Python bindings are required. Error: {exc}")

# Resolve repo root without assuming /home/root/iOS8987
REPO_ROOT = os.environ.get("IOSTOOL_ROOT")
if not REPO_ROOT:
    THIS_FILE = os.path.realpath(__file__)
    THIS_DIR = os.path.dirname(THIS_FILE)
    REPO_ROOT = os.path.abspath(os.path.join(THIS_DIR, ".."))
    if not os.path.isdir(REPO_ROOT):
        REPO_ROOT = "/home/root/iOS8987"

SCRIPTS_DIR = os.path.join(REPO_ROOT, "scripts")
LOG_DIR = os.path.join(REPO_ROOT, "logs")
os.makedirs(LOG_DIR, exist_ok=True)

# Initialize LVGL display and input drivers
lv.init()


def _log_path(script_name):
    ts = time.strftime("%Y%m%d-%H%M%S")
    safe_name = os.path.basename(script_name).replace("/", "_")
    return os.path.join(LOG_DIR, f"{safe_name}-{ts}.log")


def run_script_async(script_filename, args=None):
    if args is None:
        args = []
    script_path = os.path.realpath(os.path.join(SCRIPTS_DIR, script_filename))
    if not os.path.isfile(script_path):
        print(f"[ERROR] Script not found: {script_path}", file=sys.stderr)
        return None

    log_path = _log_path(script_filename)
    try:
        logf = open(log_path, "wb")
    except Exception as exc:
        print(f"[ERROR] Cannot open log file {log_path}: {exc}", file=sys.stderr)
        return None

    cmd = ["/bin/bash", script_path] + list(args)
    try:
        proc = subprocess.Popen(cmd, stdout=logf, stderr=subprocess.STDOUT, cwd=REPO_ROOT)
    except Exception as exc:
        print(f"[ERROR] Failed to start {script_path}: {exc}", file=sys.stderr)
        logf.close()
        return None

    return {"proc": proc, "log": log_path, "logf": logf}


# --- STYLES ---
style_btn_normal = lv.style_t()
style_btn_normal.init()
style_btn_normal.set_bg_color(lv.color_hex(0x222222))
style_btn_normal.set_radius(8)

style_btn_danger = lv.style_t()
style_btn_danger.init()
style_btn_danger.set_bg_color(lv.color_hex(0x8B0000))
style_btn_danger.set_radius(8)

# --- SCREENS ---
scr_main = lv.obj()
scr_settings = lv.obj()


def load_main_screen(e=None):
    lv.scr_load(scr_main)


# Shared status label
status_obj = lv.obj()
status_obj.set_size(lv.pct(100), 40)
status_obj.align(lv.ALIGN.BOTTOM_MID, 0, -2)
status_label = lv.label(status_obj)
status_label.set_text("")
status_label.center()


def set_status(text, timeout=None):
    try:
        status_label.set_text(text)
    except Exception:
        pass
    if timeout:
        def clear_after():
            time.sleep(timeout)
            try:
                status_label.set_text("")
            except Exception:
                pass
        threading.Thread(target=clear_after, daemon=True).start()


def run_and_monitor(script_name, args=None, start_text=None, finish_text=None):
    if start_text:
        set_status(start_text)
    res = run_script_async(script_name, args)
    if res is None:
        set_status(f"Failed to start {script_name}", timeout=6)
        return

    def monitor():
        proc = res["proc"]
        log = res["log"]
        proc.wait()
        try:
            res["logf"].close()
        except Exception:
            pass
        if proc.returncode == 0:
            set_status(finish_text or f"{script_name} finished", timeout=8)
        else:
            set_status(f"{script_name} failed — see {log}", timeout=12)

    threading.Thread(target=monitor, daemon=True).start()


# --- MAIN MENU SETUP ---
welcome_label = lv.label(scr_main)
welcome_label.set_text("iOS8987 - Standalone iOS Tool")
welcome_label.align(lv.ALIGN.TOP_MID, 0, 20)

# 1. Sideload Button
btn_sideload = lv.btn(scr_main)
btn_sideload.set_size(220, 56)
btn_sideload.align(lv.ALIGN.CENTER, 0, -46)
btn_sideload.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_side = lv.label(btn_sideload)
lbl_side.set_text("Sideload")
lbl_side.center()


def sideload_click_cb(e):
    run_and_monitor("sideload.sh", start_text="Sideload started...", finish_text="Sideload finished")


btn_sideload.add_event_cb(sideload_click_cb, lv.EVENT.CLICKED, None)

# 2. Jailbreak Button
btn_jb = lv.btn(scr_main)
btn_jb.set_size(220, 56)
btn_jb.align(lv.ALIGN.CENTER, 0, 18)
btn_jb.add_style(style_btn_danger, lv.STATE.DEFAULT)
lbl_jb = lv.label(btn_jb)
lbl_jb.set_text("Jailbreak")
lbl_jb.center()


def jailbreak_click_cb(e):
    run_and_monitor("jailbreak.sh", start_text="Jailbreak workflow started...", finish_text="Jailbreak finished")


btn_jb.add_event_cb(jailbreak_click_cb, lv.EVENT.CLICKED, None)

# 3. Settings Button
btn_settings = lv.btn(scr_main)
btn_settings.set_size(200, 40)
btn_settings.align(lv.ALIGN.BOTTOM_MID, 0, -36)
btn_settings.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_set = lv.label(btn_settings)
lbl_set.set_text("Settings")
lbl_set.center()


def settings_click_cb(e):
    lv.scr_load(scr_settings)


btn_settings.add_event_cb(settings_click_cb, lv.EVENT.CLICKED, None)

# --- SETTINGS MENU SETUP ---
lbl_set_title = lv.label(scr_settings)
lbl_set_title.set_text("Settings & Updates")
lbl_set_title.align(lv.ALIGN.TOP_MID, 0, 20)

# Setup & Fetch Tools Button
btn_setup = lv.btn(scr_settings)
btn_setup.set_size(260, 46)
btn_setup.align(lv.ALIGN.CENTER, 0, -60)
btn_setup.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_setup = lv.label(btn_setup)
lbl_setup.set_text("Setup & Fetch Tools")
lbl_setup.center()


def setup_tools_cb(e):
    run_and_monitor("setup_tools.sh", start_text="Setting up tools...", finish_text="Setup completed")


btn_setup.add_event_cb(setup_tools_cb, lv.EVENT.CLICKED, None)

# Update Scripts Button
btn_up_sc = lv.btn(scr_settings)
btn_up_sc.set_size(240, 44)
btn_up_sc.align(lv.ALIGN.CENTER, 0, -6)
btn_up_sc.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_sc = lv.label(btn_up_sc)
lbl_sc.set_text("Update Scripts")
lbl_sc.center()


def update_sc_cb(e):
    run_and_monitor("update.sh", args=["scripts"], start_text="Updating scripts...", finish_text="Scripts updated")


btn_up_sc.add_event_cb(update_sc_cb, lv.EVENT.CLICKED, None)

# Update Software Button
btn_up_sw = lv.btn(scr_settings)
btn_up_sw.set_size(240, 44)
btn_up_sw.align(lv.ALIGN.CENTER, 0, 54)
btn_up_sw.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_sw = lv.label(btn_up_sw)
lbl_sw.set_text("Update Software")
lbl_sw.center()


def update_sw_cb(e):
    run_and_monitor("update.sh", args=["software"], start_text="Updating system software...", finish_text="System update finished")


btn_up_sw.add_event_cb(update_sw_cb, lv.EVENT.CLICKED, None)

# Back button
btn_back = lv.btn(scr_settings)
btn_back.set_size(120, 40)
btn_back.align(lv.ALIGN.BOTTOM_MID, 0, -18)
btn_back.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_bk = lv.label(btn_back)
lbl_bk.set_text("Back")
lbl_bk.center()
btn_back.add_event_cb(lambda e: lv.scr_load(scr_main), lv.EVENT.CLICKED, None)

# Load default main screen
lv.scr_load(scr_main)


# Keep the event loop handling to the LVGL runtime; do not add extra blocking code here.
