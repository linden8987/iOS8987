import os
import sys
import lvgl as lv
import subprocess

# Initialize LVGL display and input drivers
lv.init()

# --- BASE PATH CONFIGURATION ---
SCRIPTS_DIR = "/home/root/iOS8987/scripts"

# --- STYLES ---
style_btn_normal = lv.style_t()
style_btn_normal.init()
style_btn_normal.set_bg_color(lv.color_hex(0x222222))
style_btn_normal.set_radius(8)

style_btn_danger = lv.style_t()
style_btn_danger.init()
style_btn_danger.set_bg_color(lv.color_hex(0x8B0000))  # Dark Red for Jailbreak
style_btn_danger.set_radius(8)

# --- SCREENS ---
scr_main = lv.obj()
scr_settings = lv.obj()

def load_main_screen(e):
    lv.scr_load(scr_main)

# --- MAIN MENU SETUP ---
welcome_label = lv.label(scr_main)
welcome_label.set_text("iOS8987 - Standalone iOS Tool")
welcome_label.align(lv.ALIGN.TOP_MID, 0, 20)

# 1. Sideload Button
btn_sideload = lv.btn(scr_main)
btn_sideload.set_size(200, 50)
btn_sideload.align(lv.ALIGN.CENTER, 0, -50)
btn_sideload.add_style(style_btn_normal, lv.STATE.DEFAULT)
lbl_side = lv.label(btn_sideload)
lbl_side.set_text("Sideload")
lbl_side.center()

def sideload_click_cb(e):
    script_path = os.path.join(SCRIPTS_DIR, "sideload.sh")
    subprocess.run([script_path])

btn_sideload.add_event_cb(sideload_click_cb, lv.EVENT.CLICKED, None)

# 2. Jailbreak Button (Red Text / Red Theme)
btn_jb = lv.btn(scr_main)
btn_jb.set_size(200, 50)
btn_jb.align(lv.ALIGN.CENTER, 0, 15)
btn_jb.add_style(style_btn_danger, lv.STATE.DEFAULT)
lbl_jb = lv.label(btn_jb)
lbl_jb.set_text("Jailbreak")
lbl_jb.center()

def jailbreak_click_cb(e):
    script_path = os.path.join(SCRIPTS_DIR, "jailbreak.sh")
    subprocess.run([script_path])

btn_jb.add_event_cb(jailbreak_click_cb, lv.EVENT.CLICKED, None)

# 3. Settings Button
btn_settings = lv.btn(scr_main)
btn_settings.set_size(200, 40)
btn_settings.align(lv.ALIGN.BOTTOM_MID, 0, -20)
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

# Update Software Button
btn_up_sw = lv.btn(scr_settings)
btn_up_sw.set_size(220, 40)
btn_up_sw.align(lv.ALIGN.CENTER, 0, -40)
lbl_sw = lv.label(btn_up_sw)
lbl_sw.set_text("Update Software")
lbl_sw.center()

def update_sw_cb(e):
    script_path = os.path.join(SCRIPTS_DIR, "update.sh")
    subprocess.run([script_path, "software"])

btn_up_sw.add_event_cb(update_sw_cb, lv.EVENT.CLICKED, None)

# Update Scripts Button
btn_up_sc = lv.btn(scr_settings)
btn_up_sc.set_size(220, 40)
btn_up_sc.align(lv.ALIGN.CENTER, 0, 10)
lbl_sc = lv.label(btn_up_sc)
lbl_sc.set_text("Update Scripts")
lbl_sc.center()

def update_sc_cb(e):
    script_path = os.path.join(SCRIPTS_DIR, "update.sh")
    subprocess.run([script_path, "scripts"])

btn_up_sc.add_event_cb(update_sc_cb, lv.EVENT.CLICKED, None)

# Back Button
btn_back = lv.btn(scr_settings)
btn_back.set_size(100, 35)
btn_back.align(lv.ALIGN.BOTTOM_MID, 0, -20)
lbl_bk = lv.label(btn_back)
lbl_bk.set_text("Back")
lbl_bk.center()
btn_back.add_event_cb(load_main_screen, lv.EVENT.CLICKED, None)

# Load default main screen
lv.scr_load(scr_main)
