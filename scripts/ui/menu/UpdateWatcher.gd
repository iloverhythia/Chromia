extends Node

# While you're in the menu, checks every few minutes for a new release and
# pops up an "Update available" box on its own (no need to press Settings >
# Check for Updates). Update downloads it and restarts the game (iOS: loads
# it the next time the app is opened). Later hides it for that version until
# the game is restarted.
#
# menu2.gd installs it once; it stays (on the root) for the whole session
# and only does anything while the menu is showing.

const INTERVAL := 180.0         # between checks (GitHub allows 60 an hour)

var _busy := false
var _last := 0.0                # the game checks at startup, so wait a full interval first
var _skip := ""                 # the version "Later" was picked for

static func install(root: Node):
	if root == null or root.has_node("UpdateWatcher"):
		return
	var w = load("res://scripts/ui/menu/UpdateWatcher.gd").new()
	w.name = "UpdateWatcher"
	root.call_deferred("add_child", w)

func _ready():
	if not Online.can_self_update():
		return
	_last = OS.get_ticks_msec() / 1000.0
	var t := Timer.new()
	t.wait_time = 5.0
	t.autostart = true
	t.connect("timeout", self, "_tick")
	add_child(t)

# right away (a tester account just signed in)
func check_now():
	_last = -INTERVAL

func _tick():
	if _busy or not is_inside_tree():
		return
	var now := OS.get_ticks_msec() / 1000.0
	if now - _last < INTERVAL or not _can_show():
		return
	_last = now
	_check()

# Only on the menu, with no other box open.
func _can_show() -> bool:
	if not ProjectSettings.get_setting("application/networking/enabled"):
		return false
	if Globals.confirm_prompt == null or Globals.confirm_prompt.is_open:
		return false
	if Globals.string_prompt != null and Globals.string_prompt.is_open:
		return false
	var scene = get_tree().current_scene
	return scene != null and (scene.name == "Menu" or scene.name == "VRMenuHolder") # VR: the box shows on the menu screen

func _check():
	_busy = true
	Online.call_deferred("check_latest_version")
	var latest = yield(Online, "latest_version")
	var current: String = ProjectSettings.get_setting("application/config/version")
	latest = String(latest)
	if latest == current or latest == _skip or not _can_show():
		_busy = false
		return
	var data = Online.latest_version_data if typeof(Online.latest_version_data) == TYPE_DICTIONARY else {}
	# (only a release marked -a updates without asking; testers are asked too:
	# test builds come out many times a day)
	var silent := String(data.get("body", "")).begins_with("-a")
	if not silent and Online.update_snoozed(): # ("Remind me in a day")
		_busy = false
		return
	if not silent:
		Globals.confirm_prompt.open(
			"Version %s just came out (you have %s).\nUpdate now? The game restarts when it's done." % [latest, current]
				if not Online.updates_by_pack() else
			"Version %s just came out (you have %s).\nDownload it now? It loads the next time you open Chromia." % [latest, current],
			"Update Available",
			[{text = "Later", wait = 0}, {text = "Remind me in a day", wait = 0}, {text = "Update", wait = 0}]
		)
		var sel = yield(Globals.confirm_prompt, "option_selected")
		Globals.confirm_prompt.close()
		yield(Globals.confirm_prompt, "done_closing")
		if int(sel) != 2:
			if int(sel) == 1:
				Online.snooze_updates()
				Globals.notify(Globals.NOTIFY_INFO, "No update reminders for a day. Settings > Check for Updates still works.", "Updates")
			_skip = latest
			_busy = false
			return
	Globals.notify(Globals.NOTIFY_INFO, "Downloading version %s..." % latest, "Updating")
	Online.attempt_update()
	yield(Online, "update_finished")
	if not Online.update_installed:
		Globals.notify(Globals.NOTIFY_WARN, Online.update_blocked_reason if Online.update_blocked_reason != "" else "The update couldn't be downloaded. It'll try again in a few minutes.", "Update Failed")
		_busy = false
		return
	if Online.updates_by_pack():
		# iOS can't restart itself
		_skip = latest
		Globals.confirm_prompt.open(
			"Version %s is downloaded. %s" % [latest, Online.restart_hint()],
			"Update Downloaded",
			[{text = "OK", wait = 0}]
		)
		yield(Globals.confirm_prompt, "option_selected")
		Globals.confirm_prompt.close()
		_busy = false
		return
	Rhythia.save_settings()
	Rhythia.restart_game() # (marks this session closed first: not a crash)
