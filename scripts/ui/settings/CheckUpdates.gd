extends Button

# Settings > "Check for Updates": same update check the game runs at startup.
var _busy: bool = false

func _pressed():
	if _busy:
		return
	if not Online.can_self_update():
		if OS.has_feature("JavaScript"):
			Globals.notify(Globals.NOTIFY_SUCCEED, "The browser version is always the latest one.", "No Updates")
		else:
			# macOS and phones install new versions from the releases page
			OS.shell_open("https://github.com/%s/releases/latest" % Online.UPDATE_REPO)
		return
	_busy = true
	disabled = true
	text = "Checking..."
	# Started next frame so we're already listening when the answer arrives.
	Online.call_deferred("check_latest_version")
	var latest = yield(Online, "latest_version")
	var current: String = ProjectSettings.get_setting("application/config/version")
	if String(latest) == current:
		Globals.notify(Globals.NOTIFY_SUCCEED, "You're on the latest version (%s)." % current, "No Updates")
		_reset()
		return

	Globals.confirm_prompt.open(
		"Version %s is available (you have %s).\nDownload and install it now?" % [latest, current],
		"Update Available",
		[{text = "Not now", wait = 0}, {text = "Update", wait = 0}]
	)
	var sel = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	yield(Globals.confirm_prompt, "done_closing")
	if not bool(sel):
		_reset()
		return

	text = "Downloading..."
	Online.attempt_update(true)
	yield(Online, "update_finished")
	if not Online.update_installed:
		Globals.notify(Globals.NOTIFY_WARN, Online.update_blocked_reason if Online.update_blocked_reason != "" else "The update couldn't be downloaded. Try again later.", "Update Failed")
		_reset()
		return
	if Online.updates_by_pack():
		# iOS: the app can't restart itself
		Globals.confirm_prompt.open(
			"Version %s is downloaded. %s" % [latest, Online.restart_hint()],
			"Update Downloaded",
			[{text = "OK", wait = 0}]
		)
		yield(Globals.confirm_prompt, "option_selected")
		Globals.confirm_prompt.close()
		text = "Reopen to update"
		return

	Globals.confirm_prompt.open(
		"Version %s is installed. Restart the game now to use it?" % latest,
		"Update Installed",
		[{text = "Later", wait = 0}, {text = "Restart", wait = 0}]
	)
	sel = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	if bool(sel):
		Rhythia.save_settings()
		Rhythia.restart_game() # (marks this session closed first: not a crash)
	else:
		text = "Restart to update"

func _reset():
	_busy = false
	disabled = false
	text = "Check for Updates"

# Settings > Crash Reports (next to this button): the saved reports of past
# crashes (Rhythia.saved_crash_reports), to copy and send any time.
var _side_buttons_added := false # (once: the row is moved into the settings header, entering the tree again)
func _enter_tree():
	if _side_buttons_added or get_parent() == null or get_parent().has_node("CrashReports"):
		return
	_side_buttons_added = true
	var b := Button.new()
	b.name = "CrashReports"
	b.text = "Crash Reports"
	b.theme = theme
	b.size_flags_horizontal = size_flags_horizontal
	b.size_flags_vertical = size_flags_vertical
	b.connect("pressed", self, "_on_crash_reports")
	get_parent().call_deferred("add_child", b)
	if Online.can_self_update() and Online.shows_channel_switch():
		var ch := Button.new()
		ch.name = "UpdateChannel"
		ch.theme = theme
		ch.size_flags_horizontal = size_flags_horizontal
		ch.size_flags_vertical = size_flags_vertical
		ch.connect("pressed", self, "_on_channel", [ch])
		_channel_text(ch)
		get_parent().call_deferred("add_child", ch)

# Settings > Update channel: Stable (everyone) or Test (test builds: new
# things before they're released, on the test server).
func _channel_text(ch: Button):
	if Online.is_tester():
		ch.text = "Update channel: %s (tester account)" % ("Test" if Online.wanted_channel() == "test" else "Stable")
		return
	ch.text = "Update channel: %s" % ("Test" if Online.wanted_channel() == "test" else "Stable")

func _on_channel(ch: Button):
	if Online.is_tester():
		# tester accounts switch right away, no questions
		Rhythia.tester_channel = "stable" if Online.wanted_channel() == "test" else "test"
		Rhythia.update_channel = Rhythia.tester_channel
		Rhythia.save_settings()
		_channel_text(ch)
		Globals.notify(Globals.NOTIFY_INFO, "Getting the %s build..." % ("test" if Rhythia.tester_channel == "test" else "stable"), "Update Channel")
		_pressed() # get that channel's build now
		return
	var to_test: bool = Online.wanted_channel() != "test"
	Globals.confirm_prompt.open(
		("Switch to test builds?\nThey get new things before everyone else and may have bugs. They play on the test server: scores there don't count on the real leaderboards (the test server starts as a copy of them)." if to_test
		else "Switch back to the stable version?\nYou go back to the normal server and the latest release."),
		"Update Channel",
		[{text = "Cancel", wait = 0}, {text = "Switch", wait = 0}]
	)
	var sel = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	yield(Globals.confirm_prompt, "done_closing")
	if not bool(sel):
		return
	Rhythia.update_channel = "test" if to_test else "stable"
	Rhythia.save_settings()
	_channel_text(ch)
	_pressed() # get that channel's build now

func _on_crash_reports():
	var reports: Array = Rhythia.saved_crash_reports()
	if reports.empty():
		Globals.notify(Globals.NOTIFY_SUCCEED, "No crashes saved. If Chromia ever closes unexpectedly, its report shows up here.", "Crash Reports")
		return
	var f := File.new()
	var text := ""
	if f.open(reports[0], File.READ) == OK:
		text = f.get_as_text()
		f.close()
	var lines := Array(text.strip_edges().split("\n"))
	var shown := []
	for i in range(max(1, lines.size() - 6), lines.size()):
		var l := String(lines[i])
		var cut := l.find("] ")
		shown.append(l.substr(cut + 2) if cut != -1 else l)
	Globals.confirm_prompt.open(
		"%d saved crash report(s). The newest ended with:\n\n%s\n\nCopy it and paste it in a message to the developer." % [reports.size(), PoolStringArray(shown).join("\n")],
		"Crash Reports",
		[{text = "Close", wait = 0}, {text = "Copy newest", wait = 0}]
	)
	var picked = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	if picked == 1:
		OS.clipboard = text
		Globals.notify(Globals.NOTIFY_SUCCEED, "The crash report is copied.", "Copied")
