extends Button

# Settings > "Check for Updates": same update check the game runs at startup.
var _busy: bool = false

func _pressed():
	if _busy:
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
	if not Directory.new().file_exists(Online.local_pck_path() + ".old"):
		Globals.notify(Globals.NOTIFY_WARN, "The update couldn't be downloaded. Try again later.", "Update Failed")
		_reset()
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
