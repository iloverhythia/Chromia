extends VBoxContainer

# Settings > Transfer: move your settings and custom content (not maps) to
# another device with a transfer code, or with a file. SettingsTransfer.gd
# packs and unpacks; this tab shows it and does the network part:
#  - Send: makes a code, then waits (up to 15 minutes, while the game is open)
#    for the other device to connect with it and sends the bundle.
#  - Receive: you type the other device's code; it connects, downloads, shows
#    what came, and Apply writes it and restarts the menu with it.
# Both devices have to be on the same network (Wi-Fi). The browser version
# can't make direct connections: files only.

const ST = preload("res://scripts/SettingsTransfer.gd")
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)
const GOOD := Color(0.6, 1, 0.7)
const BAD := Color(1, 0.55, 0.55)
const HELLO := "CHXF"
const WAIT_MS := 15 * 60 * 1000
const CHUNK := 256 * 1024

var f_body: DynamicFont
var f_bold: DynamicFont
var f_title: DynamicFont
var f_code: DynamicFont
var box: VBoxContainer

var _code_l: Label
var _send_status: Label
var _send_btn: Button
var _stop_btn: Button
var _code_in: LineEdit
var _recv_status: Label
var _recv_btn: Button
var _apply_box: HBoxContainer
var _file_status: Label

# sending
var _server: TCP_Server = null
var _pin = 0
var _payload = PoolByteArray()
var _server_until = 0
var _peer: StreamPeerTCP = null
var _peer_buf = PoolByteArray()
var _peer_since = 0
var _sent = 0
var _sending = false
var _bad_tries = 0

# receiving
var _client: StreamPeerTCP = null
var _client_since = 0
var _client_hello_sent = false
var _got = PoolByteArray()
var _want = -1
var _received = null # bundle data waiting for Apply
# maps (Include maps): sent after the settings, a file at a time
var _include_maps: CheckBox
var _map_src = null # ST.MapSource while sending
var _out := PoolByteArray() # (what the connection didn't take yet)
var _sink = null # ST.MapSink while receiving
var _maps_total := 0
var _file_out: File = null # saving a file with maps
var _file_in: File = null # opening one
var _file_in_left := 0

static func web() -> bool:
	return OS.get_name() == "HTML5"

static func add_tab(tab_container) -> void:
	if tab_container == null or not is_instance_valid(tab_container) or tab_container.has_node("Transfer"):
		return
	var t = load("res://scripts/ui/settings/TransferTab.gd").new()
	t.name = "Transfer"
	tab_container.add_child(t)
	var after = tab_container.get_node_or_null("Replays & Misc")
	if after:
		tab_container.move_child(t, after.get_index() + 1)

func _font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	return f

func _ready():
	f_body = _font("res://assets/font/Lato/Lato-Regular.ttf", 17)
	f_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 18)
	f_title = _font("res://assets/font/Lato/Lato-Black.ttf", 26)
	f_code = _font("res://assets/font/Lato/Lato-Black.ttf", 44)
	var m = MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_constant_override("margin_" + side, 18)
	add_child(m)
	box = VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_constant_override("separation", 8)
	m.add_child(box)

	_build_store_move()
	if not web():
		_build_maps_only()
	_label("Transfer settings", f_title, ACCENT)
	_label("Copy your settings and custom content (colorsets, meshes, sounds, backgrounds, profiles, keybinds) to another device. Scores aren't included; maps are if you tick Include maps.", f_body, DIM, true)
	_include_maps = CheckBox.new()
	_include_maps.text = "Include maps (all of them: can take a while)"
	_include_maps.theme = load("res://uitheme.tres")
	_include_maps.add_font_override("font", f_bold)
	_include_maps.connect("toggled", self, "_on_include_maps")
	box.add_child(_include_maps)

	if not web():
		box.add_child(HSeparator.new())
		_label("Send from this device", f_title, ACCENT)
		_label("Make a code and enter it on the other device. Both need Chromia open on the same Wi-Fi.", f_body, DIM, true)
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 10)
		box.add_child(h)
		_send_btn = _button(h, "Generate code", "_start_send")
		_stop_btn = _button(h, "Stop", "_stop_send")
		_stop_btn.visible = false
		_code_l = _label("", f_code, TEXT)
		_code_l.visible = false
		_send_status = _label("", f_body, TEXT, true)

		box.add_child(HSeparator.new())
		_label("Receive on this device", f_title, ACCENT)
		_label("Enter the code from the other device.", f_body, DIM, true)
		var h2 = HBoxContainer.new()
		h2.add_constant_override("separation", 10)
		box.add_child(h2)
		_code_in = LineEdit.new()
		_code_in.theme = load("res://uitheme.tres")
		_code_in.add_font_override("font", f_bold)
		_code_in.placeholder_text = "XXXX-XXXX-XXXX"
		_code_in.rect_min_size = Vector2(260, 40)
		_code_in.max_length = 20
		_code_in.connect("text_entered", self, "_on_code_entered")
		h2.add_child(_code_in)
		_recv_btn = _button(h2, "Enter code", "_start_receive")
		_recv_status = _label("", f_body, TEXT, true)
		_apply_box = HBoxContainer.new()
		_apply_box.add_constant_override("separation", 10)
		_apply_box.visible = false
		box.add_child(_apply_box)
		_button(_apply_box, "Apply", "_apply")
		_button(_apply_box, "Cancel", "_cancel_apply")

	box.add_child(HSeparator.new())
	_label("Or use a file", f_title, ACCENT)
	_label("Save everything to one file and open it on the other device." + (" The browser version can only use files." if web() else ""), f_body, DIM, true)
	var h3 = HBoxContainer.new()
	h3.add_constant_override("separation", 10)
	box.add_child(h3)
	_button(h3, "Save to file", "_save_file")
	_button(h3, "Load from file", "_load_file")
	_file_status = _label("", f_body, TEXT, true)
	_build_backups()
	set_process(false)

# --- Transfer maps only (scripts/MapTransfer.gd) ---------------------------------
# Only your maps, only the ones the other device doesn't have, on a thread of
# their own (no lag), added to the map list as they come (no restart).
const MT = preload("res://scripts/MapTransfer.gd")
var _mt = null
var _mt_send: Button
var _mt_get: Button
var _mt_stop: Button
var _mt_code: Label
var _mt_in: LineEdit
var _mt_bar: ProgressBar
var _mt_status: Label
var _mt_queue := [] # maps that came, for the map list
var _mt_vfolders := {} # Vulnus map folders that came (added at the end)
var _mt_added := 0
var _mt_said := 0
var _mt_was_busy := false

func _build_maps_only():
	_label("Transfer maps only", f_title, ACCENT)
	_label("Send your maps to another device on the same Wi-Fi, without settings. Only the maps it doesn't have yet are sent, in the background, so both games keep running smoothly, and they show up in its map list as they arrive.", f_body, DIM, true)
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 10)
	box.add_child(h)
	_mt_send = _button(h, "Send my maps", "_mt_start_send")
	_mt_stop = _button(h, "Stop", "_mt_stop_now")
	_mt_stop.visible = false
	_mt_code = _label("", f_code, TEXT)
	_mt_code.visible = false
	var h2 := HBoxContainer.new()
	h2.add_constant_override("separation", 10)
	box.add_child(h2)
	_mt_in = LineEdit.new()
	_mt_in.theme = load("res://uitheme.tres")
	_mt_in.add_font_override("font", f_bold)
	_mt_in.placeholder_text = "Code from the other device"
	_mt_in.rect_min_size = Vector2(260, 40)
	_mt_in.max_length = 20
	_mt_in.connect("text_entered", self, "_mt_start_get")
	h2.add_child(_mt_in)
	_mt_get = _button(h2, "Get maps", "_mt_start_get")
	_mt_bar = ProgressBar.new()
	_mt_bar.theme = load("res://uitheme.tres")
	_mt_bar.min_value = 0.0
	_mt_bar.max_value = 1.0
	_mt_bar.step = 0.001
	_mt_bar.percent_visible = false
	_mt_bar.rect_min_size = Vector2(0, 14)
	_mt_bar.visible = false
	box.add_child(_mt_bar)
	_mt_status = _label("", f_body, TEXT, true)
	box.add_child(HSeparator.new())

func _mt_dirs() -> Dictionary:
	return {"maps": Rhythia.user_map_dir, "vmaps": Rhythia.user_vmap_dir}

func _mt_busy_ui(on: bool):
	_mt_send.disabled = on
	_mt_get.disabled = on
	_mt_in.editable = not on
	_mt_stop.visible = on
	_mt_bar.visible = on
	if on:
		_mt_bar.value = 0.0

func _mt_start_send():
	if _mt != null and _mt.busy():
		return
	_mt = MT.new(_mt_dirs())
	var code: String = _mt.send()
	if code == "":
		_say(_mt_status, String(_mt.state().text), BAD)
		_mt = null
		return
	_mt_code.text = code
	_mt_code.visible = true
	_mt_busy_ui(true)
	_mt_was_busy = true
	_say(_mt_status, "Type this code under \"Transfer maps only\" on the other device and press Get maps. Both need Chromia open on the same Wi-Fi.")
	Rhythia.trail("map transfer: sending")
	set_process(true)

func _mt_start_get(_t = ""):
	if _mt != null and _mt.busy():
		return
	_mt = MT.new(_mt_dirs())
	if not _mt.receive(_mt_in.text):
		_say(_mt_status, String(_mt.state().text), BAD)
		_mt = null
		return
	_mt_code.visible = false
	_mt_queue = []
	_mt_vfolders = {}
	_mt_added = 0
	_mt_busy_ui(true)
	_mt_was_busy = true
	Rhythia.trail("map transfer: receiving")
	set_process(true)

func _mt_stop_now():
	if _mt != null:
		_mt.stop()

func _process_maps_only():
	if _mt == null:
		return
	var s: Dictionary = _mt.state()
	# the maps that came: into the map list, a few at a time (it's the game's thread)
	_mt_queue.append_array(_mt.take_added())
	var until := OS.get_ticks_usec() + 3000
	while not _mt_queue.empty() and OS.get_ticks_usec() < until:
		var path: String = _mt_queue.pop_front()
		if path.begins_with(Rhythia.user_vmap_dir):
			_mt_vfolders[path.get_base_dir()] = true
		elif path.get_extension().to_lower() in ["sspm", "chrm"] and Rhythia.registry_song != null:
			if Rhythia.registry_song.add_sspm_map(path):
				_mt_added += 1
	# what it's doing (a few times a second)
	if OS.get_ticks_msec() - _mt_said > 200 or not s.busy:
		_mt_said = OS.get_ticks_msec()
		if int(s.maps) > 0 and s.busy:
			var mb := "%s / %s" % [ST.human_size(int(s.bytes_done)), ST.human_size(int(s.bytes))]
			_say(_mt_status, "%s %d / %d maps (%s)%s" % ["Sending" if _mt_code.visible else "Receiving", int(s.maps_done), int(s.maps), mb,
				(", %d it has already" % int(s.skipped)) if int(s.skipped) > 0 else ""])
			_mt_bar.value = float(s.bytes_done) / max(1.0, float(s.bytes))
		elif s.busy and String(s.text) != "" and not _mt_code.visible:
			_say(_mt_status, String(s.text))
	if s.busy or not _mt_was_busy:
		return
	# finished
	_mt_was_busy = false
	_mt.reap()
	_mt_busy_ui(false)
	_mt_code.visible = false
	if not _mt_queue.empty():
		_mt_was_busy = true # (the map list catches up first)
		return
	for folder in _mt_vfolders.keys():
		if File.new().file_exists(String(folder).plus_file("meta.json")) and Rhythia.registry_song != null:
			Rhythia.registry_song.add_vulnus_map(folder)
			_mt_added += 1
	_mt_vfolders = {}
	var text := String(s.text)
	if _mt_added > 0:
		var map_list = Rhythia.menu_node("Main/Maps/MapRegistry/S/VBoxContainer")
		if map_list != null and map_list.has_method("refresh_songs"):
			map_list.refresh_songs()
		text += " They're in your map list."
		Globals.notify(Globals.NOTIFY_SUCCEED, "%d map(s) added from the other device." % _mt_added, "Maps transferred")
	_say(_mt_status, text, GOOD if s.ok else BAD)
	Rhythia.trail("map transfer: %s" % text)
	_mt = null

# --- Settings backups (scripts/SettingsBackup.gd) ------------------------------
# --- Meta Quest: the sideloaded app to the store app (StoreTransfer.gd) --------------
# The sideloaded game: "Send everything", then the code it got. The store
# game: a box for that code. Other builds: nothing.
const MOVE = preload("res://scripts/StoreTransfer.gd")
var _mv = null
var _mv_status: Label
var _mv_code: Label
var _mv_btn: Button
var _mv_stop: Button
var _mv_quit: Button
var _mv_maps: CheckBox
var _mv_replays: CheckBox
var _mv_in: LineEdit
var _mv_bar: ProgressBar
var _mv_thread: Thread = null
var _mv_surveyed := false

func _build_store_move():
	var store: bool = MOVE.is_store()
	if not store and not MOVE.can_send():
		return
	_mv = MOVE.new()
	add_child(_mv)
	_mv.connect("progress", self, "_mv_progress")
	_mv.connect("finished", self, "_mv_finished")
	if store:
		_label("Bring everything over from the sideloaded version", f_title, ACCENT)
		_label("Played the sideloaded Chromia VR before? Everything can come over: your account, settings, profiles, scores, level, colorsets, meshes, skins, hands, maps and replays. In the sideloaded version, open Settings > Transfer and press \"Send everything\": it shows a code. Come back here (the store version) and type that code below. What this version has under the same names is replaced.", f_body, DIM, true)
		var h := HBoxContainer.new()
		h.add_constant_override("separation", 10)
		box.add_child(h)
		_mv_in = LineEdit.new()
		_mv_in.theme = load("res://uitheme.tres")
		_mv_in.add_font_override("font", f_bold)
		_mv_in.placeholder_text = "The code: XXXX XXXX"
		_mv_in.rect_min_size = Vector2(260, 40)
		_mv_in.max_length = 12
		_mv_in.connect("text_entered", self, "_mv_receive")
		h.add_child(_mv_in)
		_mv_btn = _button(h, "Bring it over", "_mv_receive")
		_mv_stop = _button(h, "Stop", "_mv_stop_now")
	else:
		_label("Move to the store version", f_title, ACCENT)
		_label("Chromia is on the Meta Horizon Store now. The store version is a different app to the headset and can't see this one's files, so everything goes over through the game's server: your account, settings, profiles, scores, level, colorsets, meshes, skins, hands, and the maps and replays ticked below. Press \"Send everything\", wait for the code, then open the store version, go to Settings > Transfer and type the code there. Nothing is removed here. The code works once, for a day.", f_body, DIM, true)
		_mv_maps = _check("Include my maps", true, "_mv_noop", "Your downloaded and imported maps. Without them the store version starts with the built-in maps, and you download the others again.")
		_mv_replays = _check("Include my replays", true, "_mv_noop", "Your saved replays")
		var h := HBoxContainer.new()
		h.add_constant_override("separation", 10)
		box.add_child(h)
		_mv_btn = _button(h, "Send everything", "_mv_send")
		_mv_stop = _button(h, "Stop", "_mv_stop_now")
		_mv_code = _label("", f_code, TEXT)
		_mv_code.visible = false
		connect("visibility_changed", self, "_mv_survey")
	_mv_stop.visible = false
	_mv_bar = ProgressBar.new()
	_mv_bar.theme = load("res://uitheme.tres")
	_mv_bar.min_value = 0.0
	_mv_bar.max_value = 1.0
	_mv_bar.step = 0.001
	_mv_bar.percent_visible = false
	_mv_bar.rect_min_size = Vector2(0, 14)
	_mv_bar.visible = false
	box.add_child(_mv_bar)
	_mv_status = _label("", f_body, TEXT, true)
	if store:
		_mv_quit = _button(box, "Close Chromia now", "_mv_quit_now")
		_mv_quit.visible = false
	box.add_child(HSeparator.new())

func _mv_noop(_on = false):
	pass

# how much there is, counted off the main thread the first time the page shows
func _mv_survey():
	if _mv_surveyed or not is_visible_in_tree() or _mv_maps == null:
		return
	_mv_surveyed = true
	if OS.can_use_threads():
		_mv_thread = Thread.new()
		if _mv_thread.start(self, "_mv_survey_job", null) == OK:
			return
		_mv_thread = null
	_mv_surveyed_now(MOVE.survey())

func _mv_survey_job(_u):
	call_deferred("_mv_surveyed_now", MOVE.survey())

func _mv_surveyed_now(sv: Dictionary):
	if _mv_thread != null:
		_mv_thread.wait_to_finish()
		_mv_thread = null
	if _mv_maps == null or not is_instance_valid(_mv_maps):
		return
	_mv_maps.text = "Include my maps (%d files, %s)" % [sv.maps[0], MOVE.mb(sv.maps[1])]
	_mv_replays.text = "Include my replays (%d files, %s)" % [sv.replays[0], MOVE.mb(sv.replays[1])]
	if _mv_status.text == "":
		_say(_mv_status, "Without maps and replays: %d files, %s." % [sv.rest[0], MOVE.mb(sv.rest[1])], DIM)

func _mv_busy(on: bool):
	_mv_btn.disabled = on
	_mv_stop.visible = on
	_mv_bar.visible = on
	if _mv_in != null:
		_mv_in.editable = not on

func _mv_send():
	if _mv.busy:
		return
	_mv_code.visible = false
	_mv_busy(true)
	_mv.send(_mv_maps.pressed, _mv_replays.pressed)

func _mv_receive(_t = ""):
	if _mv.busy:
		return
	_mv_busy(true)
	_mv.receive(_mv_in.text)

func _mv_stop_now():
	_mv.stop()

func _mv_progress(text: String, part: float):
	_say(_mv_status, text)
	_mv_bar.value = clamp(part, 0.0, 1.0)

func _mv_finished(ok: bool, text: String, code: String):
	_mv_busy(false)
	if code != "":
		_mv_code.text = code.substr(0, 4) + " " + code.substr(4)
		_mv_code.visible = true
		text += " Now open the store version of Chromia, go to Settings > Transfer and type this code."
	_say(_mv_status, text, GOOD if ok else BAD)
	if ok and _mv_quit != null:
		_mv_quit.visible = true
		_mv_btn.disabled = true
		Globals.notify(Globals.NOTIFY_SUCCEED, "Everything from the sideloaded version is here. Close Chromia and open it again to use it.", "Transfer", 12)

func _mv_quit_now():
	Rhythia.quit_game()

const SB = preload("res://scripts/SettingsBackup.gd")
var _backup_on: CheckBox
var _backup_only: CheckBox
var _backup_status: Label

func _check(text: String, on: bool, method: String, tip: String) -> CheckBox:
	var c = CheckBox.new()
	c.text = text
	c.theme = load("res://uitheme.tres")
	c.add_font_override("font", f_bold)
	c.pressed = on
	c.hint_tooltip = tip
	c.connect("toggled", self, method)
	box.add_child(c)
	return c

func _build_backups():
	box.add_child(HSeparator.new())
	_label("Settings backups", f_title, ACCENT)
	_label("Copies of your settings are kept in a backups folder (the newest %d), so you can get them back if they are ever lost or reset. Restore a backup adds the one you pick as a profile." % SB.KEEP, f_body, DIM, true)
	_backup_on = _check("Back Up Settings", bool(Rhythia.settings_backup), "_on_backup_on", "keeps copies of your settings in the settings_backups folder")
	_backup_only = _check("Only When Saving a New Profile", bool(Rhythia.settings_backup_profile_only), "_on_backup_only", "on: a copy is made when you make a new profile (Select Profile > Create New From Current). Off: a copy every time your settings change")
	_backup_only.disabled = not _backup_on.pressed
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	box.add_child(h)
	_button(h, "Back up now", "_backup_now")
	_button(h, "Restore a backup", "_restore_backup")
	if not web() and not OS.has_feature("mobile") and not OS.has_feature("quest"):
		_button(h, "Open backups folder", "_open_backups")
	_backup_status = _label("", f_body, TEXT, true)
	_backup_count()

func _backup_count(extra: String = "", col: Color = TEXT):
	var all: Array = SB.list()
	var t := "No backups yet." if all.empty() else "%d backup%s. Newest: %s" % [all.size(), "" if all.size() == 1 else "s", String(all[0].name).trim_suffix(".json")]
	_say(_backup_status, (extra + "\n" if extra != "" else "") + t, col)

func _on_backup_on(on: bool):
	Rhythia.settings_backup = on
	_backup_only.disabled = not on
	Rhythia.save_settings()

func _on_backup_only(on: bool):
	Rhythia.settings_backup_profile_only = on
	Rhythia.save_settings()
	_backup_count("A copy is made when you make a new profile." if on else "A copy is made every time your settings change.")

func _backup_now():
	Rhythia.save_settings()
	var path: String = Rhythia.settings_backup_now("settings")
	if path == "":
		_backup_count("Your settings are the same as the newest backup: no new copy needed.")
	else:
		_backup_count("Backed up.", GOOD)

func _open_backups():
	var d := Directory.new()
	if not d.dir_exists(SB.folder()):
		d.make_dir_recursive(SB.folder())
	OS.shell_open(ProjectSettings.globalize_path(SB.folder()))

func _restore_backup():
	if SB.list().empty():
		_backup_count("There are no backups to restore yet.", BAD)
		return
	Globals.file_sel.raise()
	Globals.file_sel.open_file(self, "_on_backup_picked", PoolStringArray(["*.json ; Settings backup"]), false, SB.DIR)

func _on_backup_picked(files):
	if not (files is PoolStringArray) or files.empty() or String(files[0]) == "":
		return
	# (added as a profile next to yours: Select Profile switches to it)
	if not load("res://scripts/ui/settings/Profiles.gd").import_dropped(get_tree(), PoolStringArray([files[0]])):
		_backup_count("Couldn't add it: open Settings once and try again.", BAD)
		return
	_backup_count("Added as a profile. Pick it under Select Profile to use it.", GOOD)

func _label(text: String, f: Font, col: Color, wrap: bool = false, parent: Node = null) -> Label:
	var l = Label.new()
	l.autowrap = wrap
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	(parent if parent != null else box).add_child(l)
	return l

func _button(parent: Node, text: String, method: String) -> Button:
	var b = Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", f_bold)
	b.rect_min_size = Vector2(180, 40)
	b.size_flags_horizontal = 0
	b.connect("pressed", self, method)
	parent.add_child(b)
	return b

func _say(l: Label, text: String, col: Color = TEXT):
	if l == null:
		return
	l.text = text
	l.add_color_override("font_color", col)

# --- Sending -----------------------------------------------------------------
func _on_include_maps(on: bool):
	if on:
		var maps: Array = ST.list_maps()
		_include_maps.text = "Include maps (%d, %s)" % [maps.size(), ST.human_size(ST.maps_size(maps))]
	else:
		_include_maps.text = "Include maps (all of them: can take a while)"

func _maps_wanted() -> Array:
	return ST.list_maps() if _include_maps != null and _include_maps.pressed else []

func _start_send():
	_stop_send()
	var ip: String = ST.local_ip()
	if ip == "":
		_say(_send_status, "Not on Wi-Fi. Connect, or use a file below.", BAD)
		return
	_say(_send_status, "Packing...")
	_send_btn.disabled = true
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var maps: Array = _maps_wanted()
	var b: Dictionary = ST.build_bundle(maps)
	_payload = b.bytes
	_map_src = ST.MapSource.new(maps) if not maps.empty() else null
	_maps_total = maps.size()
	_out = PoolByteArray()
	_server = TCP_Server.new()
	var idx = -1
	for i in range(ST.PORTS.size()):
		if _server.listen(ST.PORTS[i]) == OK:
			idx = i
			break
	_send_btn.disabled = false
	if idx < 0:
		_server = null
		_say(_send_status, "Couldn't open a connection (ports %d-%d are in use)." % [ST.PORTS[0], ST.PORTS[-1]], BAD)
		return
	randomize()
	_pin = randi() & 0x3ffffff
	_bad_tries = 0
	_server_until = OS.get_ticks_msec() + WAIT_MS
	_code_l.text = ST.make_code(ip, idx, _pin)
	_code_l.visible = true
	_stop_btn.visible = true
	var extra = ""
	if not b.skipped.empty():
		extra = "\nLeft out %d file(s), too big: %s" % [b.skipped.size(), PoolStringArray(b.skipped).join(", ")]
	var with_maps := ""
	if not maps.empty():
		with_maps = " and %d maps (%s)" % [maps.size(), ST.human_size(ST.maps_size(maps))]
	_say(_send_status, "Code ready (%d files, %s%s). Enter it on the other device.%s" % [b.files, ST.human_size(b.size), with_maps, extra])
	Rhythia.trail("transfer: sending from %s port %d" % [ip, ST.PORTS[idx]])
	set_process(true)

func _stop_send(text: String = ""):
	if _server != null:
		_server.stop()
	_server = null
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	_sending = false
	_payload = PoolByteArray()
	_map_src = null
	_out = PoolByteArray()
	if _code_l:
		_code_l.visible = false
	if _stop_btn:
		_stop_btn.visible = false
	if text != "":
		_say(_send_status, text)
	elif _send_status:
		_say(_send_status, "")

func _process_send():
	if _server == null:
		return
	if OS.get_ticks_msec() > _server_until and not _sending:
		_stop_send("Code expired. Make a new one.")
		return
	if _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
		_peer.set_no_delay(true)
		_peer_buf = PoolByteArray()
		_peer_since = OS.get_ticks_msec()
		_sent = 0
		_sending = false
	if _peer == null:
		return
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if _sending:
			_say(_send_status, "The other device stopped. Try again there.", BAD)
		_peer = null
		_sending = false
		return
	if not _sending:
		var n = _peer.get_available_bytes()
		if n > 0:
			var r = _peer.get_partial_data(n)
			if r[0] == OK:
				_peer_buf.append_array(r[1])
		if _peer_buf.size() >= 8:
			var sp = StreamPeerBuffer.new()
			sp.data_array = _peer_buf
			var hello = sp.get_data(4)[1].get_string_from_ascii()
			var pin = sp.get_u32()
			var ok: bool = hello == HELLO and pin == _pin
			var reply = StreamPeerBuffer.new()
			if ok:
				reply.put_data("OK".to_ascii())
				reply.put_u64(_payload.size())
				_peer.put_data(reply.data_array)
				_sending = true
				_sent = 0
				Rhythia.trail("transfer: sending %d bytes" % _payload.size())
			else:
				reply.put_data("NO".to_ascii())
				_peer.put_data(reply.data_array)
				_peer.disconnect_from_host()
				_peer = null
				_bad_tries += 1
				if _bad_tries >= 10:
					_stop_send("Too many wrong codes. Make a new one.")
			return
		if OS.get_ticks_msec() - _peer_since > 10000:
			_peer.disconnect_from_host()
			_peer = null
		return
	# send a piece each frame: the settings, then the maps
	var budget = 8
	while budget > 0:
		if _out.empty():
			if _sent < _payload.size():
				var end: int = min(_sent + CHUNK, _payload.size())
				_out = _payload.subarray(_sent, end - 1)
				_sent = end
			elif _map_src != null:
				_out = _map_src.next(CHUNK)
			if _out.empty():
				break
		budget -= 1
		var r = _peer.put_partial_data(_out)
		if r[0] != OK:
			break
		var n: int = int(r[1])
		_out = _out.subarray(n, _out.size() - 1) if n < _out.size() else PoolByteArray()
		if not _out.empty():
			break # the connection is full: more next frame
	if _map_src != null and _sent >= _payload.size():
		_say(_send_status, "Sending maps... %d / %d" % [_map_src.sent_maps, _maps_total])
	else:
		_say(_send_status, "Sending... %d %%" % int(100.0 * _sent / max(1, _payload.size())))
	if _sent >= _payload.size() and _out.empty() and (_map_src == null or _map_src.ended):
		Rhythia.trail("transfer: sent%s" % ((" with %d maps" % _maps_total) if _map_src != null else ""))
		var p = _peer
		_peer = null
		_stop_send("Sent! Apply it on the other device.")
		_send_status.add_color_override("font_color", GOOD)
		# let the last bytes go out before closing
		get_tree().create_timer(5.0).connect("timeout", self, "_close_later", [p])

func _close_later(p):
	if p != null:
		p.disconnect_from_host()

# --- Receiving ---------------------------------------------------------------
func _on_code_entered(_t):
	_start_receive()

func _start_receive():
	_stop_receive()
	_apply_box.visible = false
	_received = null
	var c: Dictionary = ST.parse_code(_code_in.text)
	if c.empty():
		_say(_recv_status, "Not a valid code (it looks like 7K2M-9QXA-4T0B).", BAD)
		return
	_client = StreamPeerTCP.new()
	if _client.connect_to_host(c.ip, c.port) != OK:
		_client = null
		_say(_recv_status, "Couldn't connect. Are both on the same Wi-Fi?", BAD)
		return
	_client.set_no_delay(true)
	_client_since = OS.get_ticks_msec()
	_client_hello_sent = false
	_got = PoolByteArray()
	_want = -1
	_sink = null
	set_meta("pin", c.pin)
	_say(_recv_status, "Connecting to %s..." % c.ip)
	Rhythia.trail("transfer: receiving from %s:%d" % [c.ip, c.port])
	set_process(true)

func _stop_receive():
	if _client != null:
		_client.disconnect_from_host()
	_client = null

func _process_receive():
	if _client == null:
		return
	var st = _client.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTING:
		if OS.get_ticks_msec() - _client_since > 10000:
			_stop_receive()
			_say(_recv_status, "No answer. Check the code and the Wi-Fi.", BAD)
		return
	if st != StreamPeerTCP.STATUS_CONNECTED:
		_stop_receive()
		if _sink != null:
			_maps_done(_recv_status) # (says how many came)
			return
		_say(_recv_status, "The connection was lost%s." % (" (wrong or used code?)" if _want < 0 else ""), BAD)
		return
	if not _client_hello_sent:
		var hello = StreamPeerBuffer.new()
		hello.put_data(HELLO.to_ascii())
		hello.put_u32(int(get_meta("pin")))
		_client.put_data(hello.data_array)
		_client_hello_sent = true
		_say(_recv_status, "Connected, waiting...")
	var n = _client.get_available_bytes()
	if n > 0:
		var r = _client.get_partial_data(n)
		if r[0] == OK:
			_got.append_array(r[1])
	if _want < 0:
		if _got.size() >= 2 and _got.subarray(0, 1).get_string_from_ascii() == "NO":
			_stop_receive()
			_say(_recv_status, "Wrong code.", BAD)
			return
		if _got.size() >= 10:
			var sp = StreamPeerBuffer.new()
			sp.data_array = _got.subarray(2, 9)
			_want = sp.get_u64()
			_got = _got.subarray(10, _got.size() - 1) if _got.size() > 10 else PoolByteArray()
		elif OS.get_ticks_msec() - _client_since > 30000:
			_stop_receive()
			_say(_recv_status, "No answer. Try again.", BAD)
		return
	if _sink != null:
		# the maps after the settings
		_sink.feed(_got)
		_got = PoolByteArray()
		_say(_recv_status, "Receiving maps... %d / %d" % [_sink.got, _maps_total])
		if _sink.done or _sink.failed:
			_stop_receive()
			_maps_done(_recv_status)
		return
	_say(_recv_status, "Receiving... %d %%  (%s)" % [int(100.0 * _got.size() / max(1, _want)), ST.human_size(_want)])
	if _got.size() >= _want:
		var rest: PoolByteArray = _got.subarray(_want, _got.size() - 1) if _got.size() > _want else PoolByteArray()
		var bundle: PoolByteArray = _got.subarray(0, _want - 1) if _want > 0 else PoolByteArray()
		_got = PoolByteArray()
		if _start_maps(bundle, _recv_status):
			_got = rest # (the first maps' bytes, if they came already)
			return
		_stop_receive()
		_got_bundle(bundle, _recv_status)

# true: the settings came and maps follow (received into the maps folder as
# they come; Apply is offered once they're all here)
func _start_maps(bytes: PoolByteArray, status: Label) -> bool:
	var r: Dictionary = ST.read_bundle(bytes)
	if r.has("error") or int(r.data.get("maps", 0)) <= 0:
		return false
	_received = r.data
	_maps_total = int(r.data.maps)
	_sink = ST.MapSink.new()
	_say(status, "Receiving maps... 0 / %d (%s)" % [_maps_total, ST.human_size(int(r.data.get("maps_size", 0)))])
	return true

func _maps_done(status: Label):
	var s = _sink
	_sink = null
	if s.failed or not s.done:
		_say(status, "The maps stopped coming (%d of %d arrived and were added)." % [s.added, _maps_total], BAD)
	Rhythia.trail("transfer: maps %d added, %d already here, %d failed" % [s.added, s.kept, s.errors])
	_show_apply(status, "\nMaps: %d added%s%s." % [s.added, (", %d you had already" % s.kept) if s.kept > 0 else "", (", %d couldn't be saved" % s.errors) if s.errors > 0 else ""])

func _got_bundle(bytes: PoolByteArray, status: Label):
	var r: Dictionary = ST.read_bundle(bytes)
	if r.has("error"):
		_say(status, r.error, BAD)
		return
	_received = r.data
	_show_apply(status, "")

func _show_apply(status: Label, maps_note: String):
	var from: String = str(_received.get("from", "another device"))
	_say(status, "Got %d files (%s) from %s.%s Apply them? Your current settings are kept as the profile 'before transfer'." % [_received.files.size(), ST.human_size(int(_received.size)), from, maps_note], GOOD)
	if _apply_box == null:
		# browser: no apply row in the code part, so ask here
		_apply_box = HBoxContainer.new()
		_apply_box.add_constant_override("separation", 10)
		box.add_child(_apply_box)
		_button(_apply_box, "Apply", "_apply")
		_button(_apply_box, "Cancel", "_cancel_apply")
	box.move_child(_apply_box, status.get_index() + 1)
	_apply_box.visible = true

func _cancel_apply():
	_received = null
	_apply_box.visible = false
	_say(_recv_status, "")
	_say(_file_status, "")

func _apply():
	if _received == null:
		return
	var r: Dictionary = ST.apply_bundle(_received)
	_received = null
	_apply_box.visible = false
	Rhythia.trail("transfer: applied %d files (%d failed)" % [r.written, r.failed])
	# like picking a profile: the menu starts again with everything loaded
	var path: String = Rhythia.get_startup_settings_path()
	var menu = Rhythia.menu_node()
	if menu != null and "black_fade_target" in menu:
		menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/init.tscn")
	Rhythia.load_saved_settings(path)
	Rhythia.save_settings()

# --- Files -------------------------------------------------------------------
func _save_file():
	Globals.file_sel.save_file(self, "_save_picked", PoolStringArray(["*.chromiasettings ; Chromia settings"]), "user://chromia.chromiasettings")

func _save_picked(path: String):
	if path == "":
		return
	if path.get_extension() != "chromiasettings":
		path += ".chromiasettings"
	var maps: Array = _maps_wanted()
	var b: Dictionary = ST.build_bundle(maps, not maps.empty())
	var f = File.new()
	if f.open(path, File.WRITE) != OK:
		_say(_file_status, "Couldn't write %s." % path, BAD)
		return
	f.store_buffer(b.bytes)
	if maps.empty():
		f.close()
		_say(_file_status, "Saved %d files (%s) to %s" % [b.files, ST.human_size(b.size), path], GOOD)
		return
	# the maps after it, a piece each frame (_process)
	_file_out = f
	_map_src = ST.MapSource.new(maps)
	_maps_total = maps.size()
	set_meta("file_note", "Saved %d files (%s) and %d maps (%s) to %s" % [b.files, ST.human_size(b.size), maps.size(), ST.human_size(ST.maps_size(maps)), path])
	set_process(true)

func _process_file_out():
	if _file_out == null:
		return
	var until := OS.get_ticks_msec() + 12
	while OS.get_ticks_msec() < until:
		var piece: PoolByteArray = _map_src.next(CHUNK * 4)
		if piece.empty() and _map_src.ended:
			_file_out.close()
			_file_out = null
			_map_src = null
			_say(_file_status, String(get_meta("file_note")), GOOD)
			return
		_file_out.store_buffer(piece)
	_say(_file_status, "Saving maps... %d / %d" % [_map_src.sent_maps, _maps_total])

func _load_file():
	Globals.file_sel.open_file(self, "_load_picked", PoolStringArray(["*.chromiasettings ; Chromia settings"]), false)

func _load_picked(files: PoolStringArray):
	if files.empty():
		return
	var f = File.new()
	if f.open(files[0], File.READ) != OK:
		_say(_file_status, "Couldn't open %s." % files[0], BAD)
		return
	var head: PoolByteArray = f.get_buffer(min(64, f.get_len()))
	var blen: int = ST.bundle_length(head, f.get_len())
	if blen <= 0 or blen > f.get_len():
		f.close()
		_got_bundle(head, _file_status) # (says what's wrong)
		return
	f.seek(0)
	var bytes = f.get_buffer(blen)
	if blen < f.get_len() and _start_maps(bytes, _file_status):
		# the maps after it, a piece each frame (_process)
		_file_in = f
		_file_in_left = f.get_len() - blen
		set_process(true)
		return
	f.close()
	_got_bundle(bytes, _file_status)

func _process_file_in():
	if _file_in == null:
		return
	var until := OS.get_ticks_msec() + 12
	while OS.get_ticks_msec() < until and _file_in_left > 0 and not _sink.done and not _sink.failed:
		var n: int = min(CHUNK * 4, _file_in_left)
		_sink.feed(_file_in.get_buffer(n))
		_file_in_left -= n
	_say(_file_status, "Adding maps... %d / %d" % [_sink.got, _maps_total])
	if _sink.done or _sink.failed or _file_in_left <= 0:
		_file_in.close()
		_file_in = null
		_maps_done(_file_status)

func _process(_d):
	_process_send()
	_process_receive()
	_process_file_out()
	_process_file_in()
	_process_maps_only()
	if _server == null and _client == null and _file_out == null and _file_in == null and _mt == null:
		set_process(false)

func _exit_tree():
	if _mt != null:
		_mt.stop()
		_mt = null
	if _mv_thread != null:
		_mv_thread.wait_to_finish()
		_mv_thread = null
	_stop_send()
	_stop_receive()
	if _file_out != null:
		_file_out.close()
		_file_out = null
	if _file_in != null:
		_file_in.close()
		_file_in = null
