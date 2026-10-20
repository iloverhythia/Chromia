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
	Online.attempt_update()
	yield(Online, "update_finished")
	if not Online.update_installed:
		Globals.notify(Globals.NOTIFY_WARN, Online.update_blocked_reason if Online.update_blocked_reason != "" else "The update couldn't be downloaded. Try again later.", "Update Failed")
		_reset()
		return
	if Online.updates_by_pack():
		# iOS: the app can't restart itself
		Globals.confirm_prompt.open(
			"Version %s is downloaded. Close Chromia completely (swipe it away in the app switcher) and open it again to use it." % latest,
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
		OS.execute(OS.get_executable_path(), [], false)
		Rhythia.quit_game()
	else:
		text = "Restart to update"

func _reset():
	_busy = false
	disabled = false
	text = "Check for Updates"
