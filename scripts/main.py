#!/usr/bin/env python3
"""
Enhanced LVGL GUI for iOS8987 (main.py)
- Dynamic repo discovery via IOSTOOL_ROOT or script location
- Improved UI: header, status, progress spinner, log viewer modal, confirmations
- Async script execution with start/finish status, cancel support, and log viewing
- Settings screen shows IPA dir and allows invoking setup/update scripts

Note: LVGL bindings and platform display/input must be initialized for this to run.
"""
import os
import sys
import time
import threading
import subprocess

try:
    import lvgl as lv
except Exception as exc:
    raise SystemExit(f"LVGL Python bindings are required. Error: {exc}")

# --- Paths and configuration ---
REPO_ROOT = os.environ.get("IOSTOOL_ROOT")
if not REPO_ROOT:
    THIS_FILE = os.path.realpath(__file__)
    THIS_DIR = os.path.dirname(THIS_FILE)
    REPO_ROOT = os.path.abspath(os.path.join(THIS_DIR, ".."))
    if not os.path.isdir(REPO_ROOT):
        REPO_ROOT = "/home/root/iOS8987"

SCRIPTS_DIR = os.path.join(REPO_ROOT, "scripts")
LOG_DIR = os.path.join(REPO_ROOT, "logs")
IOSTOOL_IPA_DIR = os.environ.get("IOSTOOL_IPA_DIR", "/mnt/storage/IPAs")
os.makedirs(LOG_DIR, exist_ok=True)

APP_VERSION = "0.2.0"

# Initialize LVGL
lv.init()

# Utility: write small logs to internal GUI log file
def _gui_log(msg):
    try:
        with open(os.path.join(LOG_DIR, "gui.log"), "a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")
    except Exception:
        pass


# Helper: create timestamped log path for a script run
def _log_path(script_name):
    ts = time.strftime("%Y%m%d-%H%M%S")
    safe_name = os.path.basename(script_name).replace("/", "_")
    return os.path.join(LOG_DIR, f"{safe_name}-{ts}.log")


# Run script asynchronously, streaming to log file. Returns a dict with proc and log.
def run_script_async(script_filename, args=None):
    if args is None:
        args = []
    script_path = os.path.realpath(os.path.join(SCRIPTS_DIR, script_filename))
    if not os.path.isfile(script_path):
        _gui_log(f"Script not found: {script_path}")
        return None

    log_path = _log_path(script_filename)
    try:
        logf = open(log_path, "wb")
    except Exception as exc:
        _gui_log(f"Cannot open log file {log_path}: {exc}")
        return None

    cmd = ["/bin/bash", script_path] + list(args)
    try:
        proc = subprocess.Popen(cmd, stdout=logf, stderr=subprocess.STDOUT, cwd=REPO_ROOT)
    except Exception as exc:
        _gui_log(f"Failed to start {script_path}: {exc}")
        logf.close()
        return None

    return {"proc": proc, "log": log_path, "logf": logf}


# Helper: run usb_helper.check_device_connected by sourcing the helper and calling it
# Returns (success: bool, output: str)
def check_device_connected():
    helper = os.path.join(SCRIPTS_DIR, "usb_helper.sh")
    if not os.path.isfile(helper):
        return False, "usb_helper.sh missing"
    cmd = f"source {helper} >/dev/null 2>&1 && check_device_connected"
    try:
        res = subprocess.run(["/bin/bash", "-c", cmd], capture_output=True, text=True, timeout=8)
    except Exception as exc:
        return False, str(exc)
    if res.returncode == 0 and res.stdout.strip():
        return True, res.stdout.strip()
    elif res.returncode == 1:
        return False, "No device detected"
    else:
        # return stderr or stdout for diagnostics
        return False, (res.stderr.strip() or res.stdout.strip())


# UI helpers and global state
current_task = {"proc": None, "log": None}

# --- STYLES ---
style_btn_normal = lv.style_t()
style_btn_normal.init()
style_btn_normal.set_bg_color(lv.color_hex(0x222222))
style_btn_normal.set_radius(8)

style_btn_danger = lv.style_t()
style_btn_danger.init()
style_btn_danger.set_bg_color(lv.color_hex(0x8B0000))
style_btn_danger.set_radius(8)

style_header = lv.style_t()
style_header.init()
style_header.set_bg_color(lv.color_hex(0x111111))

# --- SCREENS ---
scr_main = lv.obj()
scr_settings = lv.obj()
scr_logs = lv.obj()

# Header
header = lv.obj(scr_main)
header.set_width(lv.pct(100))
header.set_height(48)
header.align(lv.ALIGN.TOP_MID, 0, 0)
header.add_style(style_header, lv.STATE.DEFAULT)

lbl_title = lv.label(header)
lbl_title.set_text(f"iOS8987 — {APP_VERSION}")
lbl_title.align(lv.ALIGN.LEFT_MID, 8, 0)

# Status bar
status_label = lv.label(scr_main)
status_label.set_text("")
status_label.align(lv.ALIGN.BOTTOM_MID, 0, -6)

spinner = None
progress_bar = None


def set_status(text, timeout=None):
    try:
        status_label.set_text(text)
    except Exception:
        pass
    if timeout:
        def clear():
            time.sleep(timeout)
            try:
                status_label.set_text("")
            except Exception:
                pass
        threading.Thread(target=clear, daemon=True).start()


# Simple modal: confirmation box

def confirm_dialog(title, message, on_confirm):
    mbox = lv.msgbox(scr_main)
    mbox.set_text(message)
    mbox.set_title(title)
    btns = ["Yes", "No"]
    mbox.add_button(btns[0])
    mbox.add_button(btns[1])

    def _cb(obj, evt):
        if evt == lv.EVENT.VALUE_CHANGED:
            txt = obj.get_active_btn_text()
            if txt == "Yes":
                on_confirm()
            obj.del_async()

    mbox.add_event_cb(_cb, lv.EVENT.VALUE_CHANGED, None)
    mbox.center()


# Log viewer screen
scr_logs = lv.obj()
lbl_logs_title = lv.label(scr_logs)
lbl_logs_title.set_text("Logs")
lbl_logs_title.align(lv.ALIGN.TOP_MID, 0, 8)

log_area = lv.textarea(scr_logs)
log_area.set_size(lv.pct(100), lv.pct(80))
log_area.align(lv.ALIGN.CENTER, 0, 10)
log_area.set_text("")
log_area.set_readonly(True)

btn_close_logs = lv.btn(scr_logs)
btn_close_logs.set_size(120, 40)
btn_close_logs.align(lv.ALIGN.BOTTOM_MID, 0, -8)
lbl_close = lv.label(btn_close_logs)
lbl_close.set_text("Close")

btn_close_logs.add_event_cb(lambda e: lv.scr_load(scr_main), lv.EVENT.CLICKED, None)

# --- MAIN MENU CONTROLS ---
welcome = lv.label(scr_main)
welcome.set_text("iOS8987 - Standalone iOS Tool")
welcome.align(lv.ALIGN.TOP_MID, 0, 24)

btn_sideload = lv.btn(scr_main)
btn_sideload.set_size(220, 56)
btn_sideload.align(lv.ALIGN.CENTER, 0, -46)
btn_sideload.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_sd = lv.label(btn_sideload)
lbl_sd.set_text("Sideload")
lbl_sd.center()

btn_jailbreak = lv.btn(scr_main)
btn_jailbreak.set_size(220, 56)
btn_jailbreak.align(lv.ALIGN.CENTER, 0, 18)
btn_jailbreak.add_style(style_btn_danger, lv.STATE.DEFAULT)
lbl_jb = lv.label(btn_jailbreak)
lbl_jb.set_text("Jailbreak")
lbl_jb.center()

btn_settings = lv.btn(scr_main)
btn_settings.set_size(200, 40)
btn_settings.align(lv.ALIGN.BOTTOM_MID, 0, -36)
btn_settings.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_set = lv.label(btn_settings)
lbl_set.set_text("Settings")
lbl_set.center()

# Last log quick open
btn_last_log = lv.btn(scr_main)
btn_last_log.set_size(160, 36)
btn_last_log.align(lv.ALIGN.BOTTOM_LEFT, 8, -8)
lbl_last_log = lv.label(btn_last_log)
lbl_last_log.set_text("Open Last Log")


# Helper to tail a log file into the log_area widget
def show_log_file(path):
    if not os.path.isfile(path):
        set_status("Log file not found", timeout=4)
        return
    try:
        # tail last 2000 chars safely
        with open(path, "r", errors="ignore") as f:
            data = f.read()[-20000:]
    except Exception as exc:
        data = f"Error reading log: {exc}"
    log_area.set_text(data)
    lv.scr_load(scr_logs)


# Functionality: start task with device check (for sideload/jailbreak)

def start_task_with_device_check(script_name, args=None, start_text=None, finish_text=None):
    def _start():
        ok, info = check_device_connected()
        if not ok:
            set_status(f"No device: {info}", timeout=6)
            return
        set_status(start_text or f"Running {script_name}...")
        res = run_script_async(script_name, args)
        if res is None:
            set_status("Failed to start script", timeout=6)
            return

        current_task['proc'] = res['proc']
        current_task['log'] = res['log']

        # Monitor
        def monitor():
            p = res['proc']
            p.wait()
            try:
                res['logf'].close()
            except Exception:
                pass
            if p.returncode == 0:
                set_status(finish_text or f"{script_name} finished", timeout=8)
            else:
                set_status(f"{script_name} failed — see log", timeout=10)

        threading.Thread(target=monitor, daemon=True).start()

    # Confirm with user
    confirm_dialog(f"Run {script_name}", f"This will run {script_name}. Continue?", _start)


# Sideload callback
btn_sideload.add_event_cb(lambda e: start_task_with_device_check("sideload.sh", start_text="Sideload starting...", finish_text="Sideload completed"), lv.EVENT.CLICKED, None)

# Jailbreak callback (extra warning)
def jb_confirm_cb():
    start_task_with_device_check("jailbreak.sh", start_text="Jailbreak starting...", finish_text="Jailbreak flow completed")

btn_jailbreak.add_event_cb(lambda e: confirm_dialog("Jailbreak — WARNING", "Jailbreaking may modify device state. Proceed only if you understand the risks.", jb_confirm_cb), lv.EVENT.CLICKED, None)

# Settings screen layout
lbl_set_title = lv.label(scr_settings)
lbl_set_title.set_text("Settings & Updates")
lbl_set_title.align(lv.ALIGN.TOP_MID, 0, 20)

btn_setup = lv.btn(scr_settings)
btn_setup.set_size(260, 46)
btn_setup.align(lv.ALIGN.CENTER, 0, -60)
btn_setup.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_setup = lv.label(btn_setup)
lbl_setup.set_text("Setup & Fetch Tools")
lbl_setup.center()

btn_update_scripts = lv.btn(scr_settings)
btn_update_scripts.set_size(240, 44)
btn_update_scripts.align(lv.ALIGN.CENTER, 0, -6)
btn_update_scripts.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_updates = lv.label(btn_update_scripts)
lbl_updates.set_text("Update Scripts")
lbl_updates.center()

btn_update_software = lv.btn(scr_settings)
btn_update_software.set_size(240, 44)
btn_update_software.align(lv.ALIGN.CENTER, 0, 54)
btn_update_software.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_upsw = lv.label(btn_update_software)
lbl_upsw.set_text("Update Software")
lbl_upsw.center()

lbl_ipadir = lv.label(scr_settings)
lbl_ipadir.set_text(f"IPA Dir: {IOSTOOL_IPA_DIR}")
lbl_ipadir.align(lv.ALIGN.BOTTOM_MID, 0, -60)

btn_back = lv.btn(scr_settings)
btn_back.set_size(120, 40)
btn_back.align(lv.ALIGN.BOTTOM_MID, 0, -12)
btn_back.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_back = lv.label(btn_back)
lbl_back.set_text("Back")
lbl_back.center()

# Settings actions
btn_setup.add_event_cb(lambda e: run_and_monitor("setup_tools.sh", start_text="Setting up tools...", finish_text="Setup complete"), lv.EVENT.CLICKED, None)
btn_update_scripts.add_event_cb(lambda e: run_and_monitor("update.sh", args=["scripts"], start_text="Updating scripts...", finish_text="Scripts updated"), lv.EVENT.CLICKED, None)
btn_update_software.add_event_cb(lambda e: run_and_monitor("update.sh", args=["software"], start_text="Updating software...", finish_text="Software update complete"), lv.EVENT.CLICKED, None)
btn_back.add_event_cb(lambda e: lv.scr_load(scr_main), lv.EVENT.CLICKED, None)

# Last log open

def open_last_log_cb(e):
    # find last log file in LOG_DIR
    try:
        files = [os.path.join(LOG_DIR, f) for f in os.listdir(LOG_DIR) if os.path.isfile(os.path.join(LOG_DIR, f))]
        if not files:
            set_status("No logs available", timeout=3)
            return
        files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        show_log_file(files[0])
    except Exception as exc:
        set_status(f"Error opening logs: {exc}", timeout=4)

btn_last_log.add_event_cb(open_last_log_cb, lv.EVENT.CLICKED, None)

# Also allow viewing current running task log

def open_current_log_cb(e):
    logp = current_task.get('log')
    if not logp:
        set_status("No current task log", timeout=3)
        return
    show_log_file(logp)

# Create a small button to open current task log next to last-log
btn_cur_log = lv.btn(scr_main)
btn_cur_log.set_size(120, 36)
btn_cur_log.align(lv.ALIGN.BOTTOM_RIGHT, -8, -8)
lbl_cur = lv.label(btn_cur_log)
lbl_cur.set_text("Open Task Log")
btn_cur_log.add_event_cb(open_current_log_cb, lv.EVENT.CLICKED, None)

# Function used in settings to run scripts and show log at completion

def run_and_monitor(script_name, args=None, start_text=None, finish_text=None):
    if start_text:
        set_status(start_text)
    res = run_script_async(script_name, args)
    if res is None:
        set_status("Failed to start: " + script_name, timeout=6)
        return

    def monitor():
        p = res['proc']
        log = res['log']
        p.wait()
        try:
            res['logf'].close()
        except Exception:
            pass
        if p.returncode == 0:
            set_status(finish_text or f"{script_name} finished", timeout=8)
        else:
            set_status(f"{script_name} failed — see {log}", timeout=12)

    threading.Thread(target=monitor, daemon=True).start()


# Load main screen
lv.scr_load(scr_main)

# End of main.py
