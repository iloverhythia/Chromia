extends Button
signal lock_type
var has_been_pressed: bool = false
var detected_controllers = Input.get_connected_joypads().size()

func _get_lobby_manager():
	return get_node_or_null("/root/LobbyManager")

func _is_settings_json(path: String) -> bool:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return false
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed.result
	return data.has("approach_rate") and data.has("sensitivity") and data.has("hlm_converted")

func _import_settings_json(path: String):
	has_been_pressed = true
	get_viewport().get_node("Menu").black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/init.tscn")
	Rhythia.load_saved_settings(path)
	Rhythia.save_settings()

func _force_focus_window():
	OS.request_attention()
	if OS.has_feature("Windows"):
		var ps := "$sig = '[DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr hWnd);'; Add-Type -MemberDefinition $sig -Name Win32 -Namespace Native; $p = Get-Process -Id %d | Where-Object { $_.MainWindowHandle -ne 0 }; if ($p) { [Native.Win32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null }" % OS.get_process_id()
		OS.execute("powershell", ["-NoProfile", "-WindowStyle", "Hidden", "-Command", ps], false)

func files_dropped(files: PoolStringArray, _screen: int):
	if has_been_pressed: return
	if files.size() == 1 and files[0].get_extension() == "sspre":
		has_been_pressed = true
		_force_focus_window()
		Rhythia.replay = Replay.new()
		Rhythia.replaying = true
		Rhythia.replay_path = files[0]
		get_viewport().get_node("Menu").black_fade_target = true
		yield(get_tree().create_timer(0.35), "timeout")
		get_tree().change_scene("res://scenes/loaders/songload.tscn")
	elif files.size() == 1 and files[0].get_extension() == "json" and _is_settings_json(files[0]):
		_import_settings_json(files[0])
	else:
		var song
		for file in files:
			var ext = file.get_extension()
			if ext == "sspm":
				song = Song.new()
				song.load_from_sspm(file)
				var result = song.convert_to_sspm()
				if result == "Converted!" or result == "File already exists!":
					Rhythia.registry_song.check_and_remove_id(song.id)
					song = Rhythia.registry_song.add_sspm_map("user://maps/%s.sspm" % song.id)
			elif ext == "rhm":
				var importer = RhmImporter.new()
				add_child(importer)
				var import_result = yield(importer.import_rhm(file), "completed")
				importer.queue_free()
				if import_result.song != null:
					song = import_result.song
				elif import_result.error != "":
					Globals.notify(Globals.NOTIFY_WARN, import_result.error, "Map Import Failed")
			elif ext == "rhs":
				var skin_importer = RhsImporter.new()
				add_child(skin_importer)
				var skin_result = yield(skin_importer.import_rhs(file), "completed")
				skin_importer.queue_free()
				if skin_result.errors.size() > 0:
					Globals.notify(Globals.NOTIFY_WARN, PoolStringArray(skin_result.errors).join(", "), "Skin Import")
				elif skin_result.imported.size() > 0:
					Globals.notify(Globals.NOTIFY_SUCCEED, "Skin imported.", "Skin Import")
				else:
					Globals.notify(Globals.NOTIFY_WARN, "Nothing found to import.", "Skin Import")
		var list = $"/root/Menu/Main/Maps/MapRegistry/S/VBoxContainer"
		list.refresh_songs()
		if song:
			Rhythia.select_song(song)
			list.switch_to_play_screen()

func _input(event: InputEvent):
	if not is_visible_in_tree(): return
	var focused = get_focus_owner()
	if focused is LineEdit or focused is TextEdit: return
	if get_viewport().get_node("Menu/Main/Maps/Results").visible == true:
		if not disabled and not has_been_pressed and event is InputEventJoypadButton:
			if event.button_index == JOY_XBOX_A and event.pressed:
				grab_focus()
				grab_click_focus()
				pressed = true
		if not disabled and not has_been_pressed and event is InputEventKey:
			if event.pressed and event.scancode == KEY_SPACE:
				grab_focus()
				grab_click_focus()
				pressed = true

func _pressed():
	if not Rhythia.selected_song: return
	if has_been_pressed: return

	var lobby_manager = _get_lobby_manager()
	var in_lobby = lobby_manager != null and lobby_manager.lobby_active

	if in_lobby and not lobby_manager.is_host:
		return

	emit_signal("lock_type")


	if detected_controllers >= 1 and not Rhythia.ignore_controller_detection:
		var sel = 1
		if sel:
			Rhythia.ignore_controller_detection = true
			_begin_start(in_lobby, lobby_manager)
			return
	else:
		_begin_start(in_lobby, lobby_manager)

func _begin_start(in_lobby: bool, lobby_manager):
	has_been_pressed = true
	if in_lobby:
		if lobby_manager.has_method("push_current_mods"):
			lobby_manager.push_current_mods()
		lobby_manager.start_game()
	else:
		get_viewport().get_node("Menu").black_fade_target = true
		yield(get_tree().create_timer(0.35), "timeout")
		get_tree().change_scene("res://scenes/loaders/songload.tscn")

func _ready():
	get_tree().connect("files_dropped", self, "files_dropped")
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.connect("game_started", self, "_on_lobby_game_started_on_lobby_game_started")

func _on_lobby_game_started():
	if has_been_pressed:
		return
	has_been_pressed = true
	var menu = get_viewport().get_node_or_null("Menu")
	if menu:
		menu.black_fade_target = true
