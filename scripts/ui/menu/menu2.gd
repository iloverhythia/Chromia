extends Node

var _status_error_until_msec: int = 0

var lobby_canvas: CanvasLayer
var lobby_panel: PanelContainer
var lobby_status_label: Label
var lobby_error_label: Label
var lobby_code_label: Label
var lobby_map_label: Label
var lobby_player_label: Label
var lobby_name_input: LineEdit
var discord_button: Button
var discord_status_label: Label
var xp_total_label: Label
var sp_total_label: Label
var profile_canvas: CanvasLayer
var profile_toggle_button: Button
var profile_panel: PanelContainer
var leaderboard_list_box: VBoxContainer
var _leaderboard_loaded: bool = false
var leaderboard_mode_additive_btn: Button
var leaderboard_mode_weighted_btn: Button
var _leaderboard_mode: int = 0
var _leaderboard_weighted_loaded: bool = false
var _leaderboard_entries_additive: Array = []
var _leaderboard_entries_weighted: Array = []

var lobby_code_input: LineEdit
var lobby_host_button: Button
var lobby_join_button: Button
var lobby_start_button: Button
var lobby_toggle_button: Button
var lobby_close_button: Button
var lobby_leave_button: Button
var lobby_map_button: Button
var lobby_selected_map_label: Label

var lobby_setup_box: VBoxContainer
var lobby_active_box: VBoxContainer
var lobby_player_list_box: VBoxContainer
var lobby_copy_code_button: Button

var lobby_public_checkbox: CheckBox
var lobby_browse_button: Button
var lobby_public_list_box: VBoxContainer
var _lobby_public_scroll: ScrollContainer
var _browsing_public: bool = false

var lobby_chat_box: VBoxContainer
var lobby_chat_log_box: VBoxContainer
var lobby_chat_scroll: ScrollContainer
var lobby_chat_input: LineEdit
const LOBBY_CHAT_MAX_LINES: int = 200

var global_chat_box: VBoxContainer
var global_chat_log_box: VBoxContainer
var global_chat_scroll: ScrollContainer
var global_chat_input: LineEdit
const GLOBAL_CHAT_MAX_LINES: int = 200

var admin_canvas: CanvasLayer
var admin_toggle_button: Button
var admin_panel: PanelContainer
var admin_ban_input: LineEdit
var admin_ban_reason_input: LineEdit
var admin_scope_multiplayer_check: CheckBox
var admin_scope_chat_check: CheckBox
var admin_scope_leaderboard_check: CheckBox
var admin_bans_list_box: VBoxContainer
var admin_lobbies_list_box: VBoxContainer
var admin_live_bans_list_box: VBoxContainer
var admin_tag_id_input: LineEdit
var admin_tag_text_input: LineEdit
var admin_tag_color_input: LineEdit
var admin_tags_list_box: VBoxContainer
var admin_ranker_id_input: LineEdit
var admin_announcement_input: LineEdit
var admin_rankers_list_box: VBoxContainer

var admin_key_canvas: CanvasLayer
var admin_key_input: LineEdit

var _rebinding_action: String = ""
var _rebinding_button: Button = null

var ranker_canvas: CanvasLayer
var ranker_toggle_button: Button
var ranker_panel: PanelContainer
var ranker_song_label: Label
var ranker_xp_input: SpinBox
var ranker_status_label: Label
var ranker_republish_button: Button
var ranker_republish_status_label: Label

func _build_lobby_ui():
	if lobby_canvas != null:
		return
	var ui_theme = load("res://uitheme.tres")
	lobby_canvas = CanvasLayer.new()
	lobby_canvas.layer = 2
	add_child(lobby_canvas)

	lobby_toggle_button = Button.new()
	lobby_toggle_button.text = " Online"
	lobby_toggle_button.rect_min_size = Vector2(120, 36)
	lobby_toggle_button.theme = ui_theme
	lobby_toggle_button.connect("pressed", self, "_toggle_lobby_panel")
	lobby_canvas.add_child(lobby_toggle_button)

	lobby_panel = PanelContainer.new()
	lobby_panel.rect_size = Vector2(340, 600)
	lobby_panel.rect_min_size = Vector2(340, 600)
	lobby_panel.theme = ui_theme
	lobby_panel.visible = false
	lobby_canvas.add_child(lobby_panel)

	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 26)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 14)
	margin.add_constant_override("margin_bottom", 26)
	margin.rect_min_size = lobby_panel.rect_min_size
	lobby_panel.add_child(margin)

	var body_scroll = ScrollContainer.new()
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(body_scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_constant_override("separation", 10)
	vbox.theme = ui_theme
	body_scroll.add_child(vbox)

	var header_hbox = HBoxContainer.new()
	var title = Label.new()
	title.text = "Online Lobby"
	title.add_font_override("font", load("res://assets/font/Lato/Lato-Bold.ttf"))
	header_hbox.add_child(title)
	var header_spacer = Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header_spacer)
	lobby_status_label = Label.new()
	lobby_status_label.text = "● Not connected"
	lobby_status_label.theme = ui_theme
	lobby_status_label.clip_text = true
	lobby_status_label.rect_min_size = Vector2(120, 0)
	header_hbox.add_child(lobby_status_label)
	vbox.add_child(header_hbox)

	lobby_error_label = Label.new()
	lobby_error_label.autowrap = true
	lobby_error_label.visible = false
	lobby_error_label.theme = ui_theme
	lobby_error_label.add_color_override("font_color", Color(1, 0.55, 0.45))
	lobby_error_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(lobby_error_label)

	vbox.add_child(HSeparator.new())

	lobby_setup_box = VBoxContainer.new()
	lobby_setup_box.add_constant_override("separation", 8)
	vbox.add_child(lobby_setup_box)

	lobby_public_checkbox = CheckBox.new()
	lobby_public_checkbox.text = "Public lobby"
	lobby_public_checkbox.pressed = true
	lobby_public_checkbox.theme = ui_theme
	lobby_setup_box.add_child(lobby_public_checkbox)

	lobby_code_input = LineEdit.new()
	lobby_code_input.placeholder_text = "Enter lobby code to join"
	lobby_code_input.rect_min_size = Vector2(0, 34)
	lobby_code_input.theme = ui_theme
	lobby_setup_box.add_child(lobby_code_input)

	var host_hbox = HBoxContainer.new()
	host_hbox.add_constant_override("separation", 8)
	lobby_host_button = _make_button("Host Lobby", ui_theme)
	lobby_host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_host_button.connect("pressed", self, "_on_host_lobby_pressed")
	host_hbox.add_child(lobby_host_button)
	lobby_join_button = _make_button("Join Lobby", ui_theme)
	lobby_join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_join_button.connect("pressed", self, "_on_join_lobby_pressed")
	host_hbox.add_child(lobby_join_button)
	lobby_setup_box.add_child(host_hbox)

	lobby_browse_button = _make_button("Browse Public Lobbies", ui_theme)
	lobby_browse_button.connect("pressed", self, "_on_browse_public_pressed")
	lobby_setup_box.add_child(lobby_browse_button)

	var public_scroll = ScrollContainer.new()
	public_scroll.rect_min_size = Vector2(0, 110)
	public_scroll.size_flags_vertical = Control.SIZE_FILL
	public_scroll.visible = false
	lobby_setup_box.add_child(public_scroll)
	lobby_public_list_box = VBoxContainer.new()
	lobby_public_list_box.add_constant_override("separation", 4)
	lobby_public_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	public_scroll.add_child(lobby_public_list_box)
	_lobby_public_scroll = public_scroll

	lobby_active_box = VBoxContainer.new()
	lobby_active_box.add_constant_override("separation", 8)
	lobby_active_box.visible = false
	vbox.add_child(lobby_active_box)

	var code_row = HBoxContainer.new()
	code_row.add_constant_override("separation", 8)
	var code_caption = Label.new()
	code_caption.text = "Lobby Code"
	code_caption.theme = ui_theme
	code_row.add_child(code_caption)
	var code_spacer = Control.new()
	code_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code_spacer)
	lobby_code_label = Label.new()
	lobby_code_label.text = "-"
	lobby_code_label.add_font_override("font", load("res://assets/font/Lato/Lato-Bold.ttf"))
	code_row.add_child(lobby_code_label)
	lobby_copy_code_button = _make_button(" Copy ", ui_theme)
	lobby_copy_code_button.connect("pressed", self, "_on_copy_code_pressed")
	code_row.add_child(lobby_copy_code_button)
	lobby_active_box.add_child(code_row)

	lobby_map_label = Label.new()
	lobby_map_label.text = "Map: none"
	lobby_map_label.autowrap = true
	lobby_map_label.theme = ui_theme
	lobby_active_box.add_child(lobby_map_label)

	lobby_map_button = _make_button("Use Current Map", ui_theme)
	lobby_map_button.connect("pressed", self, "_on_use_current_map_pressed")
	lobby_active_box.add_child(lobby_map_button)

	lobby_selected_map_label = Label.new()
	lobby_selected_map_label.text = "Selected: none"
	lobby_selected_map_label.autowrap = true
	lobby_selected_map_label.theme = ui_theme
	lobby_active_box.add_child(lobby_selected_map_label)

	vbox.add_child(HSeparator.new())

	var players_caption = Label.new()
	players_caption.text = "Players"
	players_caption.theme = ui_theme
	vbox.add_child(players_caption)

	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(0, 130)
	scroll.rect_size = Vector2(0, 130)
	scroll.size_flags_vertical = Control.SIZE_FILL
	vbox.add_child(scroll)

	lobby_player_list_box = VBoxContainer.new()
	lobby_player_list_box.add_constant_override("separation", 4)
	lobby_player_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lobby_player_list_box)

	lobby_chat_box = VBoxContainer.new()
	lobby_chat_box.add_constant_override("separation", 8)
	vbox.add_child(lobby_chat_box)

	lobby_chat_box.add_child(HSeparator.new())

	var chat_caption = Label.new()
	chat_caption.text = "Chat"
	chat_caption.theme = ui_theme
	lobby_chat_box.add_child(chat_caption)

	lobby_chat_scroll = ScrollContainer.new()
	lobby_chat_scroll.rect_min_size = Vector2(0, 110)
	lobby_chat_scroll.rect_size = Vector2(0, 110)
	lobby_chat_scroll.size_flags_vertical = Control.SIZE_FILL
	lobby_chat_box.add_child(lobby_chat_scroll)

	lobby_chat_log_box = VBoxContainer.new()
	lobby_chat_log_box.add_constant_override("separation", 2)
	lobby_chat_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_chat_scroll.add_child(lobby_chat_log_box)

	var chat_row = HBoxContainer.new()
	chat_row.add_constant_override("separation", 8)
	lobby_chat_input = LineEdit.new()
	lobby_chat_input.placeholder_text = "Message..."
	lobby_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_chat_input.max_length = 300
	lobby_chat_input.connect("text_entered", self, "_on_lobby_chat_submitted")
	chat_row.add_child(lobby_chat_input)
	var chat_send_button = _make_button("Send", ui_theme)
	chat_send_button.connect("pressed", self, "_on_lobby_chat_send_pressed")
	chat_row.add_child(chat_send_button)
	lobby_chat_box.add_child(chat_row)

	vbox.add_child(HSeparator.new())

	lobby_start_button = _make_button("Start Game", ui_theme)
	lobby_start_button.rect_min_size = Vector2(0, 40)
	lobby_start_button.connect("pressed", self, "_on_start_game_pressed")
	vbox.add_child(lobby_start_button)

	var footer_hbox = HBoxContainer.new()
	footer_hbox.add_constant_override("separation", 8)
	lobby_leave_button = _make_button("Leave Lobby", ui_theme)
	lobby_leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_leave_button.connect("pressed", self, "_on_leave_lobby_pressed")
	footer_hbox.add_child(lobby_leave_button)
	lobby_close_button = _make_button("Close Panel", ui_theme)
	lobby_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_close_button.connect("pressed", self, "_on_close_lobby_ui_pressed")
	footer_hbox.add_child(lobby_close_button)
	vbox.add_child(footer_hbox)

	vbox.add_child(HSeparator.new())

	global_chat_box = VBoxContainer.new()
	global_chat_box.add_constant_override("separation", 8)
	vbox.add_child(global_chat_box)

	var global_chat_caption = Label.new()
	global_chat_caption.text = "Global Chat"
	global_chat_caption.add_font_override("font", load("res://assets/font/Lato/Lato-Bold.ttf"))
	global_chat_box.add_child(global_chat_caption)

	global_chat_scroll = ScrollContainer.new()
	global_chat_scroll.rect_min_size = Vector2(0, 110)
	global_chat_scroll.rect_size = Vector2(0, 110)
	global_chat_scroll.size_flags_vertical = Control.SIZE_FILL
	global_chat_box.add_child(global_chat_scroll)

	global_chat_log_box = VBoxContainer.new()
	global_chat_log_box.add_constant_override("separation", 2)
	global_chat_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	global_chat_scroll.add_child(global_chat_log_box)

	var global_chat_row = HBoxContainer.new()
	global_chat_row.add_constant_override("separation", 8)
	global_chat_input = LineEdit.new()
	global_chat_input.placeholder_text = "Message everyone..."
	global_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	global_chat_input.max_length = 300
	global_chat_input.connect("text_entered", self, "_on_global_chat_submitted")
	global_chat_row.add_child(global_chat_input)
	var global_chat_send_button = _make_button("Send", ui_theme)
	global_chat_send_button.connect("pressed", self, "_on_global_chat_send_pressed")
	global_chat_row.add_child(global_chat_send_button)
	global_chat_box.add_child(global_chat_row)

	_apply_chat_mute_visibility()
	_replay_chat_history()

func _replay_chat_history():
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	for entry in lobby_manager.lobby_chat_history:
		_on_chat_message_received(entry.peer_id, entry.name, entry.text, entry.ts)
	for entry in lobby_manager.global_chat_history:
		_on_global_chat_message_received(entry.client_id, entry.name, entry.text, entry.ts)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	if lobby_chat_scroll != null:
		lobby_chat_scroll.scroll_vertical = int(lobby_chat_scroll.get_v_scrollbar().max_value)
	if global_chat_scroll != null:
		global_chat_scroll.scroll_vertical = int(global_chat_scroll.get_v_scrollbar().max_value)

func _make_button(text: String, ui_theme: Theme) -> Button:
	var b = Button.new()
	b.text = text
	b.theme = ui_theme
	b.rect_min_size = Vector2(0, 36)
	return b

func _get_lobby_manager():
	return get_node_or_null("/root/LobbyManager")

func _add_admin_slider(parent: Control, ui_theme: Theme, label_text: String, min_v: float, max_v: float, step_v: float, initial: float, callback: String) -> HSlider:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	var label = Label.new()
	label.text = label_text
	label.theme = ui_theme
	label.rect_min_size = Vector2(140, 0)
	row.add_child(label)
	var slider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.connect("value_changed", self, callback)
	row.add_child(slider)
	parent.add_child(row)
	return slider

func _load_admin_ui_hidden() -> bool:
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return false
	return bool(config.get_value("admin", "ui_hidden", false))

func _save_admin_ui_hidden(hidden: bool):
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("admin", "ui_hidden", hidden)
	config.save("user://settings.cfg")

func _build_profile_ui():
	if profile_canvas != null:
		return
	var ui_theme = load("res://uitheme.tres")
	profile_canvas = CanvasLayer.new()
	profile_canvas.layer = 2
	add_child(profile_canvas)

	profile_toggle_button = Button.new()
	profile_toggle_button.text = "Profile"
	profile_toggle_button.rect_min_size = Vector2(100, 32)
	profile_toggle_button.anchor_top = 1.0
	profile_toggle_button.anchor_bottom = 1.0
	profile_toggle_button.margin_left = 16
	profile_toggle_button.margin_right = 116
	profile_toggle_button.margin_top = -48
	profile_toggle_button.margin_bottom = -50
	profile_toggle_button.theme = ui_theme
	profile_toggle_button.connect("pressed", self, "_toggle_profile_panel")
	profile_canvas.add_child(profile_toggle_button)

	profile_panel = PanelContainer.new()
	profile_panel.rect_min_size = Vector2(340, 360)
	profile_panel.anchor_top = 1.0
	profile_panel.anchor_bottom = 1.0
	profile_panel.margin_left = 16
	profile_panel.margin_right = 356
	profile_panel.margin_top = -420
	profile_panel.margin_bottom = -60
	profile_panel.theme = ui_theme
	profile_panel.visible = false
	profile_canvas.add_child(profile_panel)

	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 16)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 14)
	margin.add_constant_override("margin_bottom", 14)
	profile_panel.add_child(margin)

	var tabs = TabContainer.new()
	tabs.theme = ui_theme
	margin.add_child(tabs)

	var pvbox = VBoxContainer.new()
	pvbox.name = "Profile"
	pvbox.add_constant_override("separation", 8)
	tabs.add_child(pvbox)

	var discord_hbox = HBoxContainer.new()
	discord_hbox.add_constant_override("separation", 8)
	discord_button = _make_button("Connect Discord", ui_theme)
	discord_button.connect("pressed", self, "_on_discord_button_pressed")
	discord_hbox.add_child(discord_button)
	discord_status_label = Label.new()
	discord_status_label.theme = ui_theme
	discord_status_label.autowrap = true
	discord_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	discord_hbox.add_child(discord_status_label)
	pvbox.add_child(discord_hbox)

	xp_total_label = Label.new()
	xp_total_label.theme = ui_theme
	xp_total_label.text = "XP: %d" % Rhythia.jp
	pvbox.add_child(xp_total_label)

	sp_total_label = Label.new()
	sp_total_label.theme = ui_theme
	sp_total_label.text = "SP: %d" % Rhythia.sp
	pvbox.add_child(sp_total_label)

	lobby_name_input = LineEdit.new()
	lobby_name_input.placeholder_text = "Your display name"
	lobby_name_input.text = "Player"
	lobby_name_input.rect_min_size = Vector2(0, 34)
	lobby_name_input.theme = ui_theme
	lobby_name_input.connect("text_changed", self, "_on_lobby_name_changed")
	pvbox.add_child(lobby_name_input)

	var lvbox = VBoxContainer.new()
	lvbox.name = "Leaderboard"
	lvbox.add_constant_override("separation", 8)
	tabs.add_child(lvbox)

	var mode_hbox = HBoxContainer.new()
	mode_hbox.add_constant_override("separation", 8)
	leaderboard_mode_additive_btn = _make_button("Additive", ui_theme)
	leaderboard_mode_additive_btn.connect("pressed", self, "_on_leaderboard_mode_pressed", [0])
	mode_hbox.add_child(leaderboard_mode_additive_btn)
	leaderboard_mode_weighted_btn = _make_button("Weighted", ui_theme)
	leaderboard_mode_weighted_btn.connect("pressed", self, "_on_leaderboard_mode_pressed", [1])
	mode_hbox.add_child(leaderboard_mode_weighted_btn)
	lvbox.add_child(mode_hbox)
	_update_leaderboard_mode_buttons()

	var refresh_btn = _make_button("Refresh", ui_theme)
	refresh_btn.connect("pressed", self, "_on_refresh_leaderboard_pressed")
	lvbox.add_child(refresh_btn)

	var leaderboard_scroll = ScrollContainer.new()
	leaderboard_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lvbox.add_child(leaderboard_scroll)

	leaderboard_list_box = VBoxContainer.new()
	leaderboard_list_box.add_constant_override("separation", 4)
	leaderboard_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leaderboard_scroll.add_child(leaderboard_list_box)

	tabs.connect("tab_changed", self, "_on_profile_tab_changed")

	profile_canvas.visible = not _load_profile_ui_hidden()

func _toggle_profile_panel():
	profile_panel.visible = not profile_panel.visible

func _on_profile_tab_changed(tab_index: int):

	if tab_index == 1 and not _leaderboard_loaded:
		_leaderboard_loaded = true
		_update_leaderboard_mode_buttons()
		Rhythia.fetch_leaderboard()

func _on_refresh_leaderboard_pressed():
	if _leaderboard_mode == 1:
		Rhythia.fetch_leaderboard_sp()
	else:
		Rhythia.fetch_leaderboard()

func _on_leaderboard_mode_pressed(mode: int):
	_leaderboard_mode = mode
	_update_leaderboard_mode_buttons()
	if mode == 1:
		_build_leaderboard_rows(leaderboard_list_box, _leaderboard_entries_weighted, "sp", "SP")
		if not _leaderboard_weighted_loaded:
			_leaderboard_weighted_loaded = true
			Rhythia.fetch_leaderboard_sp()
	else:
		_build_leaderboard_rows(leaderboard_list_box, _leaderboard_entries_additive, "xp", "XP")

func _update_leaderboard_mode_buttons():
	if leaderboard_mode_additive_btn == null or leaderboard_mode_weighted_btn == null:
		return
	leaderboard_mode_additive_btn.disabled = _leaderboard_mode == 0
	leaderboard_mode_weighted_btn.disabled = _leaderboard_mode == 1

func _build_leaderboard_rows(list_box: VBoxContainer, entries: Array, value_key: String = "xp", unit: String = "XP"):
	if list_box == null:
		return
	for child in list_box.get_children():
		child.queue_free()
	if entries.size() == 0:
		var empty = Label.new()
		empty.text = "No leaderboard data yet."
		list_box.add_child(empty)
		return
	var ui_theme = load("res://uitheme.tres")
	for i in range(entries.size()):
		var e = entries[i]
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 8)
		var rank_label = Label.new()
		rank_label.text = "#%d" % (i + 1)
		rank_label.theme = ui_theme
		rank_label.rect_min_size = Vector2(36, 0)
		row.add_child(rank_label)
		var name_label = Label.new()
		name_label.text = String(e.get("name", "Player"))
		name_label.theme = ui_theme
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var value_label = Label.new()
		value_label.text = "%d %s" % [int(e.get(value_key, 0)), unit]
		value_label.theme = ui_theme
		row.add_child(value_label)
		list_box.add_child(row)

func _on_leaderboard_received(entries: Array):
	_leaderboard_entries_additive = entries
	if _leaderboard_mode == 0:
		_build_leaderboard_rows(leaderboard_list_box, entries, "xp", "XP")

func _on_leaderboard_sp_received(entries: Array):
	_leaderboard_entries_weighted = entries
	if _leaderboard_mode == 1:
		_build_leaderboard_rows(leaderboard_list_box, entries, "sp", "SP")

func _load_profile_ui_hidden() -> bool:
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return false
	return bool(config.get_value("profile", "ui_hidden", false))

func _save_profile_ui_hidden(hidden: bool):
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("profile", "ui_hidden", hidden)
	config.save("user://settings.cfg")

func _build_admin_ui():
	var ui_theme = load("res://uitheme.tres")
	admin_canvas = CanvasLayer.new()
	admin_canvas.layer = 11
	add_child(admin_canvas)

	admin_toggle_button = Button.new()
	admin_toggle_button.text = "Admin"
	admin_toggle_button.rect_min_size = Vector2(90, 32)
	admin_toggle_button.rect_position = Vector2(16, 16)
	admin_toggle_button.theme = ui_theme
	admin_toggle_button.connect("pressed", self, "_toggle_admin_panel")
	admin_canvas.add_child(admin_toggle_button)

	admin_panel = PanelContainer.new()
	admin_panel.rect_size = Vector2(360, 520)
	admin_panel.rect_min_size = Vector2(360, 520)
	admin_panel.rect_position = Vector2(16, 56)
	admin_panel.theme = ui_theme
	admin_panel.visible = false
	admin_canvas.add_child(admin_panel)
	admin_canvas.visible = not _load_admin_ui_hidden()

	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 20)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 14)
	margin.add_constant_override("margin_bottom", 20)
	margin.rect_min_size = admin_panel.rect_min_size
	admin_panel.add_child(margin)

	var body_scroll = ScrollContainer.new()
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(body_scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_constant_override("separation", 8)
	vbox.theme = ui_theme
	body_scroll.add_child(vbox)

	var title = Label.new()
	title.text = "Admin"
	title.add_font_override("font", load("res://assets/font/Lato/Lato-Bold.ttf"))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var ban_caption = Label.new()
	ban_caption.text = "Ban / unban by client id"
	ban_caption.theme = ui_theme
	vbox.add_child(ban_caption)

	admin_ban_input = LineEdit.new()
	admin_ban_input.placeholder_text = "client id"
	admin_ban_input.rect_min_size = Vector2(0, 32)
	admin_ban_input.theme = ui_theme
	vbox.add_child(admin_ban_input)

	admin_ban_reason_input = LineEdit.new()
	admin_ban_reason_input.placeholder_text = "reason (optional)"
	admin_ban_reason_input.rect_min_size = Vector2(0, 32)
	admin_ban_reason_input.theme = ui_theme
	vbox.add_child(admin_ban_reason_input)

	var scopes_grid = GridContainer.new()
	scopes_grid.columns = 2
	scopes_grid.add_constant_override("hseparation", 12)
	admin_scope_multiplayer_check = CheckBox.new()
	admin_scope_multiplayer_check.text = "Multiplayer"
	admin_scope_multiplayer_check.theme = ui_theme
	admin_scope_multiplayer_check.pressed = true
	scopes_grid.add_child(admin_scope_multiplayer_check)
	admin_scope_chat_check = CheckBox.new()
	admin_scope_chat_check.text = "Chat (future)"
	admin_scope_chat_check.theme = ui_theme
	scopes_grid.add_child(admin_scope_chat_check)
	admin_scope_leaderboard_check = CheckBox.new()
	admin_scope_leaderboard_check.text = "Leaderboard (future)"
	admin_scope_leaderboard_check.theme = ui_theme
	scopes_grid.add_child(admin_scope_leaderboard_check)
	vbox.add_child(scopes_grid)

	var ban_hbox = HBoxContainer.new()
	ban_hbox.add_constant_override("separation", 8)
	var ban_btn = _make_button("Ban", ui_theme)
	ban_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ban_btn.connect("pressed", self, "_on_admin_ban_pressed")
	ban_hbox.add_child(ban_btn)
	var unban_btn = _make_button("Unban", ui_theme)
	unban_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unban_btn.connect("pressed", self, "_on_admin_unban_pressed")
	ban_hbox.add_child(unban_btn)
	vbox.add_child(ban_hbox)

	vbox.add_child(HSeparator.new())

	var live_ban_caption = Label.new()
	live_ban_caption.text = "Live ban"
	live_ban_caption.theme = ui_theme
	vbox.add_child(live_ban_caption)

	var live_ban_hbox = HBoxContainer.new()
	live_ban_hbox.add_constant_override("separation", 8)
	var live_ban_btn = _make_button("Live Ban", ui_theme)
	live_ban_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_ban_btn.connect("pressed", self, "_on_admin_live_ban_pressed")
	live_ban_hbox.add_child(live_ban_btn)
	var live_unban_btn = _make_button("Live Unban", ui_theme)
	live_unban_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_unban_btn.connect("pressed", self, "_on_admin_live_unban_pressed")
	live_ban_hbox.add_child(live_unban_btn)
	vbox.add_child(live_ban_hbox)

	var live_bans_scroll = ScrollContainer.new()
	live_bans_scroll.rect_min_size = Vector2(0, 80)
	vbox.add_child(live_bans_scroll)
	admin_live_bans_list_box = VBoxContainer.new()
	admin_live_bans_list_box.add_constant_override("separation", 4)
	admin_live_bans_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_bans_scroll.add_child(admin_live_bans_list_box)

	vbox.add_child(HSeparator.new())

	var tags_caption = Label.new()
	tags_caption.text = "Player tags"
	tags_caption.theme = ui_theme
	vbox.add_child(tags_caption)

	admin_tag_id_input = LineEdit.new()
	admin_tag_id_input.placeholder_text = "client id"
	admin_tag_id_input.rect_min_size = Vector2(0, 32)
	admin_tag_id_input.theme = ui_theme
	vbox.add_child(admin_tag_id_input)

	var tag_fields_hbox = HBoxContainer.new()
	tag_fields_hbox.add_constant_override("separation", 8)
	admin_tag_text_input = LineEdit.new()
	admin_tag_text_input.placeholder_text = "tag text, e.g. DJ"
	admin_tag_text_input.rect_min_size = Vector2(0, 32)
	admin_tag_text_input.theme = ui_theme
	admin_tag_text_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_fields_hbox.add_child(admin_tag_text_input)
	admin_tag_color_input = LineEdit.new()
	admin_tag_color_input.placeholder_text = "#rrggbb"
	admin_tag_color_input.rect_min_size = Vector2(100, 32)
	admin_tag_color_input.theme = ui_theme
	tag_fields_hbox.add_child(admin_tag_color_input)
	vbox.add_child(tag_fields_hbox)

	var tag_btns_hbox = HBoxContainer.new()
	tag_btns_hbox.add_constant_override("separation", 8)
	var set_tag_btn = _make_button("Set Tag", ui_theme)
	set_tag_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_tag_btn.connect("pressed", self, "_on_admin_set_tag_pressed")
	tag_btns_hbox.add_child(set_tag_btn)
	var remove_tag_btn = _make_button("Remove Tag", ui_theme)
	remove_tag_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_tag_btn.connect("pressed", self, "_on_admin_remove_tag_pressed")
	tag_btns_hbox.add_child(remove_tag_btn)
	vbox.add_child(tag_btns_hbox)

	var tags_scroll = ScrollContainer.new()
	tags_scroll.rect_min_size = Vector2(0, 80)
	vbox.add_child(tags_scroll)
	admin_tags_list_box = VBoxContainer.new()
	admin_tags_list_box.add_constant_override("separation", 4)
	admin_tags_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tags_scroll.add_child(admin_tags_list_box)

	vbox.add_child(HSeparator.new())

	var rankers_caption = Label.new()
	rankers_caption.text = "Rankers"
	rankers_caption.theme = ui_theme
	vbox.add_child(rankers_caption)

	admin_ranker_id_input = LineEdit.new()
	admin_ranker_id_input.placeholder_text = "client id"
	admin_ranker_id_input.rect_min_size = Vector2(0, 32)
	admin_ranker_id_input.theme = ui_theme
	vbox.add_child(admin_ranker_id_input)

	var ranker_btns_hbox = HBoxContainer.new()
	ranker_btns_hbox.add_constant_override("separation", 8)
	var add_ranker_btn = _make_button("Add Ranker", ui_theme)
	add_ranker_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_ranker_btn.connect("pressed", self, "_on_admin_add_ranker_pressed")
	ranker_btns_hbox.add_child(add_ranker_btn)
	var remove_ranker_btn = _make_button("Remove Ranker", ui_theme)
	remove_ranker_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_ranker_btn.connect("pressed", self, "_on_admin_remove_ranker_pressed")
	ranker_btns_hbox.add_child(remove_ranker_btn)
	vbox.add_child(ranker_btns_hbox)

	var rankers_scroll = ScrollContainer.new()
	rankers_scroll.rect_min_size = Vector2(0, 60)
	vbox.add_child(rankers_scroll)
	admin_rankers_list_box = VBoxContainer.new()
	admin_rankers_list_box.add_constant_override("separation", 4)
	admin_rankers_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rankers_scroll.add_child(admin_rankers_list_box)

	vbox.add_child(HSeparator.new())

	var announce_caption = Label.new()
	announce_caption.text = "Announcement"
	announce_caption.theme = ui_theme
	announce_caption.autowrap = true
	vbox.add_child(announce_caption)

	admin_announcement_input = LineEdit.new()
	admin_announcement_input.placeholder_text = "Message..."
	admin_announcement_input.rect_min_size = Vector2(0, 32)
	admin_announcement_input.max_length = 300
	admin_announcement_input.theme = ui_theme
	admin_announcement_input.connect("text_entered", self, "_on_admin_send_announcement_pressed")
	vbox.add_child(admin_announcement_input)

	var send_announcement_btn = _make_button("Send Announcement", ui_theme)
	send_announcement_btn.connect("pressed", self, "_on_admin_send_announcement_pressed")
	vbox.add_child(send_announcement_btn)

	vbox.add_child(HSeparator.new())

	var bans_caption = Label.new()
	bans_caption.text = "Currently banned"
	bans_caption.theme = ui_theme
	vbox.add_child(bans_caption)

	var bans_scroll = ScrollContainer.new()
	bans_scroll.rect_min_size = Vector2(0, 80)
	vbox.add_child(bans_scroll)
	admin_bans_list_box = VBoxContainer.new()
	admin_bans_list_box.add_constant_override("separation", 4)
	admin_bans_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bans_scroll.add_child(admin_bans_list_box)

	vbox.add_child(HSeparator.new())

	var lobbies_hbox = HBoxContainer.new()
	var lobbies_caption = Label.new()
	lobbies_caption.text = "All lobbies"
	lobbies_caption.theme = ui_theme
	lobbies_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobbies_hbox.add_child(lobbies_caption)
	var refresh_btn = _make_button("Refresh", ui_theme)
	refresh_btn.connect("pressed", self, "_on_admin_refresh_pressed")
	lobbies_hbox.add_child(refresh_btn)
	vbox.add_child(lobbies_hbox)

	var lobbies_scroll = ScrollContainer.new()
	lobbies_scroll.rect_min_size = Vector2(0, 110)
	vbox.add_child(lobbies_scroll)
	admin_lobbies_list_box = VBoxContainer.new()
	admin_lobbies_list_box.add_constant_override("separation", 4)
	admin_lobbies_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobbies_scroll.add_child(admin_lobbies_list_box)

func _build_ranker_ui():
	if ranker_canvas != null:
		return
	var ui_theme = load("res://uitheme.tres")
	ranker_canvas = CanvasLayer.new()
	ranker_canvas.layer = 11
	add_child(ranker_canvas)

	ranker_toggle_button = Button.new()
	ranker_toggle_button.text = "Rank Map"
	ranker_toggle_button.rect_min_size = Vector2(110, 32)
	ranker_toggle_button.rect_position = Vector2(114, 16)
	ranker_toggle_button.theme = ui_theme
	ranker_toggle_button.connect("pressed", self, "_toggle_ranker_panel")
	ranker_canvas.add_child(ranker_toggle_button)

	ranker_panel = PanelContainer.new()
	ranker_panel.rect_size = Vector2(320, 260)
	ranker_panel.rect_min_size = Vector2(320, 260)
	ranker_panel.rect_position = Vector2(114, 56)
	ranker_panel.theme = ui_theme
	ranker_panel.visible = false
	ranker_canvas.add_child(ranker_panel)

	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 20)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 14)
	margin.add_constant_override("margin_bottom", 20)
	ranker_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "Rank Selected Map"
	title.add_font_override("font", load("res://assets/font/Lato/Lato-Bold.ttf"))
	vbox.add_child(title)

	ranker_song_label = Label.new()
	ranker_song_label.text = "Selected: none"
	ranker_song_label.autowrap = true
	ranker_song_label.theme = ui_theme
	vbox.add_child(ranker_song_label)

	var xp_hbox = HBoxContainer.new()
	xp_hbox.add_constant_override("separation", 8)
	var xp_label = Label.new()
	xp_label.text = "XP:"
	xp_label.theme = ui_theme
	xp_hbox.add_child(xp_label)
	ranker_xp_input = SpinBox.new()
	ranker_xp_input.min_value = 0
	ranker_xp_input.max_value = 1000000000000000
	ranker_xp_input.step = 1
	ranker_xp_input.rect_min_size = Vector2(120, 32)
	ranker_xp_input.theme = ui_theme
	ranker_xp_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_hbox.add_child(ranker_xp_input)
	vbox.add_child(xp_hbox)

	var set_rank_btn = _make_button("Set Rank", ui_theme)
	set_rank_btn.connect("pressed", self, "_on_set_map_rank_pressed")
	vbox.add_child(set_rank_btn)

	ranker_status_label = Label.new()
	ranker_status_label.autowrap = true
	ranker_status_label.theme = ui_theme
	vbox.add_child(ranker_status_label)

	vbox.add_child(HSeparator.new())

	ranker_republish_button = _make_button("Republish Missing Ranked Maps", ui_theme)
	ranker_republish_button.connect("pressed", self, "_on_republish_missing_pressed")
	vbox.add_child(ranker_republish_button)

	ranker_republish_status_label = Label.new()
	ranker_republish_status_label.autowrap = true
	ranker_republish_status_label.theme = ui_theme
	vbox.add_child(ranker_republish_status_label)

	ranker_canvas.visible = admin_canvas.visible if admin_canvas != null else not _load_admin_ui_hidden()

func _toggle_ranker_panel():
	ranker_panel.visible = not ranker_panel.visible
	if ranker_panel.visible:
		_refresh_ranker_panel_for_selected_song()

func _refresh_ranker_panel_for_selected_song():
	if ranker_song_label == null:
		return
	ranker_song_label.text = "Selected: %s" % _get_selected_song_name()
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null and Rhythia.selected_song != null:
		lobby_manager.get_map_rank(String(Rhythia.selected_song.id))
	ranker_status_label.text = ""

func _on_set_map_rank_pressed():
	if Rhythia.selected_song == null:
		ranker_status_label.text = "No map selected."
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	ranker_status_label.text = "Setting..."
	lobby_manager.set_map_rank(String(Rhythia.selected_song.id), _get_selected_song_name(), int(ranker_xp_input.value), Rhythia.selected_song.compute_chart_hash())
	lobby_manager.publish_map_to_server(String(Rhythia.selected_song.id))

func _on_ranker_status_received(is_ranker: bool):
	if not is_ranker:
		return
	_build_ranker_ui()
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null and not lobby_manager.is_connected("map_rank_info_received", self, "_on_map_rank_info_received"):
		lobby_manager.connect("map_rank_info_received", self, "_on_map_rank_info_received")
		lobby_manager.connect("set_map_rank_result", self, "_on_set_map_rank_result_received")
		lobby_manager.connect("unpublished_ranked_maps_received", self, "_on_unpublished_ranked_maps_received")

func _on_republish_missing_pressed():
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	ranker_republish_status_label.text = "Checking for ranked maps missing from the server..."
	lobby_manager.list_unpublished_ranked_maps()

func _on_unpublished_ranked_maps_received(song_ids: Array):
	if ranker_republish_status_label == null:
		return
	var lobby_manager = _get_lobby_manager()
	if song_ids.size() == 0:
		ranker_republish_status_label.text = "Every ranked map is already on the server."
		return
	var queued = 0
	for song_id in song_ids:
		if Rhythia.registry_song and Rhythia.registry_song.get_item(String(song_id), Globals.SEARCH_ID):
			lobby_manager.publish_map_to_server(String(song_id))
			queued += 1
	if queued > 0:
		ranker_republish_status_label.text = "%d ranked maps missing from the server — uploading %d you have locally..." % [song_ids.size(), queued]
	else:
		ranker_republish_status_label.text = "%d ranked maps missing from the server, but you don't have any of them locally." % song_ids.size()

func _compute_auto_xp(note_count: int, last_ms: float) -> int:
	var duration_s = last_ms / 1000.0
	if note_count <= 0 or duration_s <= 0:
		return 0
	var nps = note_count / duration_s
	var xp = 0.32 * pow(nps, 1.8) * pow(duration_s, 0.3)
	return int(clamp(round(xp), 1, 10000))

func _on_map_rank_info_received(song_id: String, ranked: bool, xp: int, _content_hash: String):
	if ranker_status_label == null or Rhythia.selected_song == null or String(Rhythia.selected_song.id) != song_id:
		return
	if ranked:
		ranker_xp_input.value = xp
		ranker_status_label.text = "Currently ranked: %d XP" % xp
	else:
		var suggested = _compute_auto_xp(Rhythia.selected_song.note_count, Rhythia.selected_song.last_ms)
		ranker_xp_input.value = suggested
		ranker_status_label.text = "Not currently ranked. Suggested: %d XP." % suggested

func _on_set_map_rank_result_received(ok: bool, song_id: String, xp: int):
	if ranker_status_label == null:
		return
	ranker_status_label.text = ("Set to %d XP." % xp) if ok else "Failed — you may have been removed as a ranker."

func _unhandled_input(event: InputEvent):
	if _rebinding_action != "":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.scancode != KEY_ESCAPE:
				_set_action_key(_rebinding_action, event)
			_cancel_keybind_rebind()
			get_tree().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed:
			_cancel_keybind_rebind()
			return

	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_A and event.control and event.shift:
		if admin_canvas != null:
			admin_canvas.visible = not admin_canvas.visible
			if ranker_canvas != null:
				ranker_canvas.visible = admin_canvas.visible
			_save_admin_ui_hidden(not admin_canvas.visible)
		else:
			_toggle_admin_key_prompt()

	if event.is_action_pressed("toggle_profile") and not event.echo and profile_canvas != null:
		profile_canvas.visible = not profile_canvas.visible
		_save_profile_ui_hidden(not profile_canvas.visible)

const KEYBIND_ALLOWED_ACTIONS = [
	"pause",
	"give_up",
	"retry",
	"fullscreen",
	"ui_quicksettings",
	"fps",
	"volumeslider",
	"toggle_profile",
	"quit_game"
]

func _build_keybinds_settings_tab():
	var tab_container = get_node_or_null("Main/Settings/S/F/TabContainer")
	if tab_container == null or tab_container.has_node("Keybinds"):
		return
	var ui_theme = load("res://uitheme.tres")

	var tab = VBoxContainer.new()
	tab.name = "Keybinds"
	tab.add_constant_override("separation", 4)

	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 16)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 12)
	margin.add_constant_override("margin_bottom", 12)
	tab.add_child(margin)

	var list = VBoxContainer.new()
	list.add_constant_override("separation", 6)
	margin.add_child(list)

	var hint = Label.new()
	hint.text = "\"Yo, I got that reference\""
	hint.theme = ui_theme
	hint.autowrap = true
	list.add_child(hint)
	list.add_child(HSeparator.new())

	for action in KEYBIND_ALLOWED_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 10)

		var name_label = Label.new()
		name_label.text = action
		name_label.theme = ui_theme
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var key_btn = _make_button(_get_action_key_text(action), ui_theme)
		key_btn.rect_min_size = Vector2(160, 32)
		key_btn.connect("pressed", self, "_on_keybind_button_pressed", [key_btn, action])
		row.add_child(key_btn)

		list.add_child(row)

	tab_container.add_child(tab)
	tab_container.connect("tab_changed", self, "_on_settings_tab_changed")

func _on_settings_tab_changed(_tab_index):
	_cancel_keybind_rebind()

func _get_action_key_text(action: String) -> String:
	for event in InputMap.get_action_list(action):
		if event is InputEventKey:
			return event.as_text()
	return "(unbound)"

func _on_keybind_button_pressed(btn: Button, action: String):
	if _rebinding_button != null and _rebinding_button != btn:
		_rebinding_button.text = _get_action_key_text(_rebinding_action)
	_rebinding_action = action
	_rebinding_button = btn
	btn.text = "Press a key..."

func _cancel_keybind_rebind():
	if _rebinding_button != null:
		_rebinding_button.text = _get_action_key_text(_rebinding_action)
	_rebinding_action = ""
	_rebinding_button = null

func _set_action_key(action: String, event: InputEventKey):
	InputMap.action_erase_events(action)
	var new_event = InputEventKey.new()
	new_event.scancode = event.scancode
	InputMap.action_add_event(action, new_event)
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("keybinds", action, event.scancode)
	config.save("user://settings.cfg")
	if _rebinding_button != null:
		_rebinding_button.text = _get_action_key_text(action)

func _toggle_admin_key_prompt():
	if admin_key_canvas != null:
		admin_key_canvas.queue_free()
		admin_key_canvas = null
		return
	var ui_theme = load("res://uitheme.tres")
	admin_key_canvas = CanvasLayer.new()
	admin_key_canvas.layer = 12
	add_child(admin_key_canvas)

	var panel = PanelContainer.new()
	panel.rect_size = Vector2(320, 110)
	panel.rect_min_size = Vector2(320, 110)
	panel.rect_position = Vector2(16, 16)
	panel.theme = ui_theme
	admin_key_canvas.add_child(panel)

	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 16)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 12)
	margin.add_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 8)
	margin.add_child(vbox)

	var label = Label.new()
	label.text = "Admin key"
	label.theme = ui_theme
	vbox.add_child(label)

	admin_key_input = LineEdit.new()
	admin_key_input.placeholder_text = "paste key, press Enter"
	admin_key_input.secret = true
	admin_key_input.rect_min_size = Vector2(0, 32)
	admin_key_input.theme = ui_theme
	admin_key_input.connect("text_entered", self, "_on_admin_key_submitted")
	vbox.add_child(admin_key_input)
	admin_key_input.grab_focus()

	var save_btn = _make_button("Save", ui_theme)
	save_btn.connect("pressed", self, "_on_admin_key_submitted", [""])
	vbox.add_child(save_btn)

func _on_admin_key_submitted(_text: String = ""):
	var key = admin_key_input.text.strip_edges()
	if admin_key_canvas != null:
		admin_key_canvas.queue_free()
		admin_key_canvas = null
	if key == "":
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	lobby_manager.set_admin_key(key)
	if admin_canvas == null:
		_build_admin_ui()
		lobby_manager.connect("admin_bans_received", self, "_on_admin_bans_received")
		lobby_manager.connect("admin_all_lobbies_received", self, "_on_admin_lobbies_received")
		lobby_manager.connect("admin_live_bans_received", self, "_on_admin_live_bans_received")
		lobby_manager.connect("admin_player_tags_received", self, "_on_admin_player_tags_received")
		lobby_manager.connect("admin_rankers_received", self, "_on_admin_rankers_received")

func _toggle_admin_panel():
	admin_panel.visible = not admin_panel.visible
	if admin_panel.visible:
		var lobby_manager = _get_lobby_manager()
		if lobby_manager != null:
			lobby_manager.admin_list_bans()
			lobby_manager.admin_list_all_lobbies()
			lobby_manager.admin_list_live_bans()
			lobby_manager.admin_list_player_tags()
			lobby_manager.admin_list_rankers()

func _get_checked_admin_scopes() -> Array:
	var scopes = []
	if admin_scope_multiplayer_check.pressed: scopes.append("multiplayer")
	if admin_scope_chat_check.pressed: scopes.append("chat")
	if admin_scope_leaderboard_check.pressed: scopes.append("leaderboard")
	return scopes

func _on_admin_ban_pressed():
	var client_id = admin_ban_input.text.strip_edges()
	if client_id == "":
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		var scopes = _get_checked_admin_scopes()
		if scopes.size() == 0:
			scopes = ["multiplayer"]
		lobby_manager.admin_ban_user(client_id, scopes, admin_ban_reason_input.text.strip_edges())
	admin_ban_input.text = ""
	admin_ban_reason_input.text = ""

func _on_admin_unban_pressed():
	var client_id = admin_ban_input.text.strip_edges()
	if client_id == "":
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_unban_user(client_id, _get_checked_admin_scopes())
	admin_ban_input.text = ""

func _on_admin_refresh_pressed():
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_list_bans()
		lobby_manager.admin_list_all_lobbies()
		lobby_manager.admin_list_live_bans()
		lobby_manager.admin_list_player_tags()

func _on_admin_live_ban_pressed():
	var client_id = admin_ban_input.text.strip_edges()
	if client_id == "":
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_live_ban_user(client_id, admin_ban_reason_input.text.strip_edges())
	admin_ban_input.text = ""
	admin_ban_reason_input.text = ""

func _on_admin_live_unban_pressed():
	var client_id = admin_ban_input.text.strip_edges()
	if client_id == "":
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_live_unban_user(client_id)
	admin_ban_input.text = ""

func _on_admin_live_unban_row_pressed(client_id: String):
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_live_unban_user(client_id)

func _on_admin_live_bans_received(bans: Array):
	for child in admin_live_bans_list_box.get_children():
		child.queue_free()
	if bans.size() == 0:
		var empty = Label.new()
		empty.text = "No live bans."
		admin_live_bans_list_box.add_child(empty)
		return
	var ui_theme = load("res://uitheme.tres")
	for b in bans:
		var client_id = String(b.get("client_id", ""))
		var reason = String(b.get("reason", ""))

		var row = VBoxContainer.new()
		var top_row = HBoxContainer.new()
		var label = Label.new()
		label.text = client_id
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap = true
		top_row.add_child(label)
		var unban_btn = Button.new()
		unban_btn.text = "Unban"
		unban_btn.theme = ui_theme
		unban_btn.rect_min_size = Vector2(0, 26)
		unban_btn.connect("pressed", self, "_on_admin_live_unban_row_pressed", [client_id])
		top_row.add_child(unban_btn)
		row.add_child(top_row)
		if reason != "":
			var reason_label = Label.new()
			reason_label.text = "reason: %s" % reason
			reason_label.add_color_override("font_color", Color(0.7, 0.7, 0.7))
			reason_label.autowrap = true
			row.add_child(reason_label)
		admin_live_bans_list_box.add_child(row)

func _on_admin_set_tag_pressed():
	var client_id = admin_tag_id_input.text.strip_edges()
	var text = admin_tag_text_input.text.strip_edges()
	var color = admin_tag_color_input.text.strip_edges()
	if client_id == "" or text == "" or color == "":
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_set_player_tag(client_id, text, color)
	admin_tag_id_input.text = ""
	admin_tag_text_input.text = ""
	admin_tag_color_input.text = ""

func _on_admin_remove_tag_pressed():
	var client_id = admin_tag_id_input.text.strip_edges()
	if client_id == "":
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_remove_player_tag(client_id)
	admin_tag_id_input.text = ""

func _on_admin_remove_tag_row_pressed(client_id: String):
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_remove_player_tag(client_id)

func _on_admin_player_tags_received(tags: Array):
	for child in admin_tags_list_box.get_children():
		child.queue_free()
	if tags.size() == 0:
		var empty = Label.new()
		empty.text = "No player tags."
		admin_tags_list_box.add_child(empty)
		return
	var ui_theme = load("res://uitheme.tres")
	for t in tags:
		var client_id = String(t.get("client_id", ""))
		var text = String(t.get("text", ""))
		var color = String(t.get("color", ""))

		var row = HBoxContainer.new()
		var label = Label.new()
		label.text = "%s  ●[%s]" % [client_id, text]
		label.add_color_override("font_color", Color(color) if color != "" else Color(1, 1, 1))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap = true
		row.add_child(label)
		var remove_btn = Button.new()
		remove_btn.text = "Remove"
		remove_btn.theme = ui_theme
		remove_btn.rect_min_size = Vector2(0, 26)
		remove_btn.connect("pressed", self, "_on_admin_remove_tag_row_pressed", [client_id])
		row.add_child(remove_btn)
		admin_tags_list_box.add_child(row)

func _on_admin_add_ranker_pressed():
	var client_id = admin_ranker_id_input.text.strip_edges()
	if client_id == "":
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_add_ranker(client_id)
	admin_ranker_id_input.text = ""

func _on_admin_remove_ranker_pressed():
	var client_id = admin_ranker_id_input.text.strip_edges()
	if client_id == "":
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_remove_ranker(client_id)
	admin_ranker_id_input.text = ""

func _on_admin_send_announcement_pressed(_text_arg = null):
	var text = admin_announcement_input.text.strip_edges()
	if text == "":
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_send_announcement(text)
	admin_announcement_input.text = ""

func _on_admin_remove_ranker_row_pressed(client_id: String):
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_remove_ranker(client_id)

func _on_admin_rankers_received(rankers: Array):
	for child in admin_rankers_list_box.get_children():
		child.queue_free()
	if rankers.size() == 0:
		var empty = Label.new()
		empty.text = "No rankers."
		admin_rankers_list_box.add_child(empty)
		return
	var ui_theme = load("res://uitheme.tres")
	for client_id_raw in rankers:
		var client_id = String(client_id_raw)
		var row = HBoxContainer.new()
		var label = Label.new()
		label.text = client_id
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap = true
		row.add_child(label)
		var remove_btn = Button.new()
		remove_btn.text = "Remove"
		remove_btn.theme = ui_theme
		remove_btn.rect_min_size = Vector2(0, 26)
		remove_btn.connect("pressed", self, "_on_admin_remove_ranker_row_pressed", [client_id])
		row.add_child(remove_btn)
		admin_rankers_list_box.add_child(row)

func _on_admin_bans_received(bans: Array):
	for child in admin_bans_list_box.get_children():
		child.queue_free()
	if bans.size() == 0:
		var empty = Label.new()
		empty.text = "No bans."
		admin_bans_list_box.add_child(empty)
		return
	var ui_theme = load("res://uitheme.tres")
	for b in bans:
		var client_id = String(b.get("client_id", ""))
		var scopes = b.get("scopes", [])
		var reason = String(b.get("reason", ""))

		var row = VBoxContainer.new()
		var top_row = HBoxContainer.new()
		var label = Label.new()
		var scopes_text = ", ".join(PoolStringArray(scopes))
		label.text = "%s  [%s]" % [client_id, scopes_text]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap = true
		top_row.add_child(label)
		var unban_btn = Button.new()
		unban_btn.text = "Unban"
		unban_btn.theme = ui_theme
		unban_btn.rect_min_size = Vector2(0, 26)
		unban_btn.connect("pressed", self, "_on_admin_unban_row_pressed", [client_id])
		top_row.add_child(unban_btn)
		row.add_child(top_row)
		if reason != "":
			var reason_label = Label.new()
			reason_label.text = "reason: %s" % reason
			reason_label.add_color_override("font_color", Color(0.7, 0.7, 0.7))
			reason_label.autowrap = true
			row.add_child(reason_label)
		admin_bans_list_box.add_child(row)

func _on_admin_unban_row_pressed(client_id: String):
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.admin_unban_user(client_id)

func _on_admin_lobbies_received(lobbies: Array):
	for child in admin_lobbies_list_box.get_children():
		child.queue_free()
	if lobbies.size() == 0:
		var empty = Label.new()
		empty.text = "No active lobbies."
		admin_lobbies_list_box.add_child(empty)
		return
	var ui_theme = load("res://uitheme.tres")
	for l in lobbies:
		var row = HBoxContainer.new()
		var label = Label.new()
		var visibility = "public" if l.get("is_public", true) else "private"
		var status = "started" if l.get("started", false) else "waiting"
		var code = String(l.get("code", ""))
		label.text = "%s - %s (%s, %s, %s players)" % [
			code, String(l.get("host_name", "Player")),
			visibility, status, int(l.get("player_count", 0)),
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap = true
		row.add_child(label)
		var copy_btn = Button.new()
		copy_btn.text = "Copy"
		copy_btn.theme = ui_theme
		copy_btn.rect_min_size = Vector2(0, 26)
		copy_btn.connect("pressed", self, "_on_admin_copy_lobby_code_pressed", [code])
		row.add_child(copy_btn)
		admin_lobbies_list_box.add_child(row)

func _on_admin_copy_lobby_code_pressed(code: String):
	OS.clipboard = code

func _update_lobby_ui():
	var lobby_manager = _get_lobby_manager()
	if lobby_canvas == null or lobby_manager == null:
		return
	var lobby_active = lobby_manager.lobby_active
	var is_host = lobby_manager.is_host

	lobby_start_button.disabled = not lobby_active or not is_host or not lobby_manager.all_players_ready()
	lobby_start_button.text = "Start Game" if (not lobby_active or lobby_manager.all_players_ready()) else "Waiting for maps..."
	lobby_leave_button.disabled = not lobby_active
	lobby_host_button.disabled = lobby_active
	lobby_join_button.disabled = lobby_active

	lobby_setup_box.visible = not lobby_active
	lobby_active_box.visible = lobby_active
	lobby_chat_box.visible = lobby_active and not Rhythia.mute_lobby_chat

	if lobby_error_label.visible and OS.get_ticks_msec() >= _status_error_until_msec:
		lobby_error_label.visible = false

	if not lobby_active:
		lobby_status_label.text = "● Not connected"
		for child in lobby_player_list_box.get_children():
			child.queue_free()
		var empty = Label.new()
		empty.text = "Not in lobby..."
		lobby_player_list_box.add_child(empty)
		_clear_lobby_chat()
		return

	var state = lobby_manager.lobby_state
	lobby_status_label.text = "● %s" % ("Hosting" if is_host else "Connected")
	lobby_code_label.text = lobby_manager.lobby_code
	lobby_map_label.text = "Map: %s" % (state.get("song_name", "") if state.get("song_name", "") != "" else "none")
	lobby_selected_map_label.text = "Selected: %s" % _get_selected_song_name()
	lobby_map_button.disabled = not is_host

	_rebuild_player_list(lobby_manager.players, lobby_manager.local_peer_id)

func _format_mods(mods: Dictionary) -> String:
	if mods.empty():
		return "none"
	var parts = []
	if mods.get("nofail", false): parts.append("Nofail")
	var speed_level = mods.get("speed_level", Globals.SPEED_NORMAL)
	if speed_level != Globals.SPEED_NORMAL:
		match speed_level:
			Globals.SPEED_MMM: parts.append("Speed---")
			Globals.SPEED_MM: parts.append("Speed--")
			Globals.SPEED_M: parts.append("Speed-")
			Globals.SPEED_P: parts.append("Speed+")
			Globals.SPEED_PP: parts.append("Speed++")
			Globals.SPEED_PPP: parts.append("Speed+++")
			Globals.SPEED_PPPP: parts.append("Speed++++")
			Globals.SPEED_CUSTOM: parts.append("Speed %s%%" % [mods.get("speed_custom", 1.0) * 100])
	if mods.get("sudden_death", false): parts.append("SuddenDeath")
	if mods.get("extra_energy", false): parts.append("Energy+")
	if mods.get("no_regen", false): parts.append("NoRegen")
	if mods.get("mirror_x", false) or mods.get("mirror_y", false):
		var mirrorst = "Mirror"
		if mods.get("mirror_x", false): mirrorst += "X"
		if mods.get("mirror_y", false): mirrorst += "Y"
		parts.append(mirrorst)
	if mods.get("ghost", false): parts.append("Ghost")
	if mods.get("nearsighted", false): parts.append("Nearsight")
	if mods.get("hardrock", false): parts.append("Hard Rock")
	if mods.get("mod_360", false): parts.append("360x%s" % mods.get("mod_360_speed", 1))
	if mods.get("strobe", false): parts.append("Strobe!!!")
	var start_offset = float(mods.get("start_offset", 0.0))
	if start_offset != 0.0: parts.append("Start %+dms" % int(start_offset))

	if parts.size() == 0:
		return "none"
	var txt = ""
	for i in range(parts.size()):
		if i != 0: txt += ", "
		txt += parts[i]
	return txt

func _make_player_tag_label(p: Dictionary) -> Label:
	var tag_text = String(p.get("tag_text", ""))
	if tag_text == "":
		return null
	var tag_color_str = String(p.get("tag_color", ""))
	var tag_color = Color(tag_color_str) if tag_color_str != "" else Color(1, 1, 1)
	var label = Label.new()
	label.text = "● [%s]" % tag_text
	label.add_color_override("font_color", tag_color)
	return label

func _rebuild_player_list(players: Array, local_peer_id: int):
	for child in lobby_player_list_box.get_children():
		child.queue_free()
	if players.size() == 0:
		var empty = Label.new()
		empty.text = "Waiting for players…"
		lobby_player_list_box.add_child(empty)
		return
	var lobby_manager = _get_lobby_manager()
	var viewer_is_host = lobby_manager != null and lobby_manager.is_host
	var ui_theme = load("res://uitheme.tres")
	for p in players:
		var row = HBoxContainer.new()
		var name_label = Label.new()
		var prefix = "(host) " if p.get("is_host", false) else "• "
		var you_suffix = "" if int(p.get("peer_id", -1)) == local_peer_id else ""
		var map_suffix = ""
		if p.get("missing_map", false):
			map_suffix = "  [downloading map...]"
		elif not p.get("map_ready", false):
			map_suffix = "  [checking map...]"
		name_label.text = "%s%s%s%s" % [prefix, p.get("name", "Player"), you_suffix, map_suffix]
		if p.get("missing_map", false):
			name_label.add_color_override("font_color", Color(1, 0.5, 0.4))
		elif not p.get("map_ready", false):
			name_label.add_color_override("font_color", Color(1, 0.85, 0.4))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var tag_label = _make_player_tag_label(p)
		if tag_label != null:
			row.add_child(tag_label)

		var stats_label = Label.new()
		var total = int(p.get("total_notes", 0))
		if total > 0:
			var acc_pct = float(p.get("accuracy", 0.0)) * 100.0
			stats_label.text = ""
		else:
			stats_label.text = "-"
		row.add_child(stats_label)

		var target_peer_id = int(p.get("peer_id", -1))
		if viewer_is_host and not p.get("is_host", false) and target_peer_id != local_peer_id:
			var make_host_btn = Button.new()
			make_host_btn.text = "Make Host"
			make_host_btn.theme = ui_theme
			make_host_btn.rect_min_size = Vector2(0, 28)
			make_host_btn.connect("pressed", self, "_on_make_host_pressed", [target_peer_id])
			row.add_child(make_host_btn)

		lobby_player_list_box.add_child(row)

func _on_make_host_pressed(target_peer_id: int):
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.transfer_host(target_peer_id)

func _on_copy_code_pressed():
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null and lobby_manager.lobby_code != "":
		OS.clipboard = lobby_manager.lobby_code
		lobby_status_label.text = "● Code copied!"

func _on_lobby_chat_send_pressed():
	_send_lobby_chat_from_input()

func _on_lobby_chat_submitted(_text: String):
	_send_lobby_chat_from_input()

func _send_lobby_chat_from_input():
	if lobby_chat_input == null:
		return
	var text = lobby_chat_input.text
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.send_chat_message(text)
	lobby_chat_input.text = ""
	lobby_chat_input.grab_focus()

func _on_chat_message_received(peer_id: int, name: String, text: String, _ts: float):
	if lobby_chat_log_box == null or Rhythia.mute_lobby_chat:
		return
	var lobby_manager = _get_lobby_manager()
	var is_you = lobby_manager != null and peer_id == lobby_manager.local_peer_id
	var line = Label.new()
	line.text = "%s: %s" % [name, text]
	line.autowrap = true
	if is_you:
		line.add_color_override("font_color", Color(0.65, 0.85, 1.0))
	lobby_chat_log_box.add_child(line)
	while lobby_chat_log_box.get_child_count() > LOBBY_CHAT_MAX_LINES:
		lobby_chat_log_box.get_child(0).queue_free()
	if lobby_chat_scroll != null:
		yield(get_tree(), "idle_frame")
		lobby_chat_scroll.scroll_vertical = int(lobby_chat_scroll.get_v_scrollbar().max_value)

func _clear_lobby_chat():
	if lobby_chat_log_box == null:
		return
	for child in lobby_chat_log_box.get_children():
		child.queue_free()

func _on_global_chat_send_pressed():
	_send_global_chat_from_input()

func _on_global_chat_submitted(_text: String):
	_send_global_chat_from_input()

func _send_global_chat_from_input():
	if global_chat_input == null:
		return
	var text = global_chat_input.text
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.send_global_chat_message(text)
	global_chat_input.text = ""
	global_chat_input.grab_focus()

func _on_global_chat_message_received(client_id: String, name: String, text: String, _ts: float):
	if global_chat_log_box == null or Rhythia.mute_global_chat:
		return
	var is_you = client_id != "" and client_id == Rhythia.cid
	var line = Label.new()
	line.text = "%s: %s" % [name, text]
	line.autowrap = true
	if is_you:
		line.add_color_override("font_color", Color(0.65, 0.85, 1.0))
	global_chat_log_box.add_child(line)
	while global_chat_log_box.get_child_count() > GLOBAL_CHAT_MAX_LINES:
		global_chat_log_box.get_child(0).queue_free()
	if global_chat_scroll != null:
		yield(get_tree(), "idle_frame")
		global_chat_scroll.scroll_vertical = int(global_chat_scroll.get_v_scrollbar().max_value)

func _layout_lobby_ui():
	if lobby_canvas == null:
		return
	var viewport_size = get_viewport().size
	var margin = 16

	if lobby_toggle_button != null:
		var btn_size = lobby_toggle_button.rect_size
		if btn_size == Vector2.ZERO:
			btn_size = lobby_toggle_button.rect_min_size
		lobby_toggle_button.rect_position = Vector2(
			viewport_size.x - btn_size.x - margin,
			viewport_size.y - btn_size.y - margin
		)

	if lobby_panel != null:
		var panel_size = lobby_panel.rect_size
		if panel_size == Vector2.ZERO:
			panel_size = lobby_panel.rect_min_size
		var x = viewport_size.x - panel_size.x - margin
		var y = viewport_size.y - panel_size.y - margin
		x = clamp(x, margin, viewport_size.x - panel_size.x - margin)
		y = clamp(y, margin, viewport_size.y - panel_size.y - margin)
		lobby_panel.rect_position = Vector2(x, y)

func _toggle_lobby_panel():
	if lobby_panel != null:
		lobby_panel.visible = not lobby_panel.visible
		lobby_toggle_button.text = "Hide Online" if lobby_panel.visible else "Online"
		if lobby_panel.visible:
			_apply_chat_mute_visibility()
		_layout_lobby_ui()

func _apply_chat_mute_visibility():
	if global_chat_box != null:
		global_chat_box.visible = not Rhythia.mute_global_chat
	_update_lobby_ui()

func _on_close_lobby_ui_pressed():
	if lobby_panel != null:
		lobby_panel.visible = false
		lobby_toggle_button.text = "Online"

func _on_leave_lobby_pressed():
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.close_lobby()
		_update_lobby_ui()
		lobby_panel.visible = false
		lobby_toggle_button.text = "Online"

func _on_lobby_name_changed(new_text):
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.set_player_name(new_text)
	_update_lobby_ui()

func _on_discord_button_pressed():
	if Rhythia.discord_user.has("username"):
		return
	discord_button.disabled = true
	discord_status_label.text = "Opening your browser…"
	Rhythia.start_discord_login()

func _on_discord_login_changed():
	if discord_button == null or discord_status_label == null:
		return
	if Rhythia.discord_user.has("username") and String(Rhythia.discord_user.username) != "":
		discord_button.visible = false
		discord_status_label.text = "✓ Discord: %s" % String(Rhythia.discord_user.username)

		if lobby_name_input != null and lobby_name_input.text.strip_edges() in ["", "Player"]:
			lobby_name_input.text = String(Rhythia.discord_user.username)
			_on_lobby_name_changed(lobby_name_input.text)
	else:
		discord_button.visible = true
		discord_button.text = "Connect Discord"
		discord_button.disabled = false
		discord_status_label.text = Rhythia.discord_login_error

func _on_jp_changed(awarded):
	if xp_total_label != null:
		xp_total_label.text = "XP: %d" % Rhythia.jp

func _on_sp_changed(awarded):
	if sp_total_label != null:
		sp_total_label.text = "SP: %d" % Rhythia.sp

func _on_use_current_map_pressed():
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null and lobby_manager.lobby_active and lobby_manager.is_host:
		lobby_manager.set_lobby_song(Rhythia.selected_song)
		lobby_manager.push_current_mods()
	_update_lobby_ui()

func _get_selected_song_name() -> String:
	if Rhythia.selected_song == null:
		return "none"
	if Rhythia.selected_song.has_method("get"):
		var name_value = Rhythia.selected_song.get("name")
		if name_value != null:
			return str(name_value)
	return "selected song"

func _on_host_lobby_pressed():
	var name_text = lobby_name_input.text.strip_edges()
	if name_text == "":
		name_text = "Host"
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.create_lobby(name_text, lobby_public_checkbox.pressed)
		lobby_status_label.text = "Connecting..."
		lobby_panel.visible = true
		lobby_toggle_button.text = "Hide Online"

func _on_join_lobby_pressed():
	var name_text = lobby_name_input.text.strip_edges()
	if name_text == "":
		name_text = "Guest"
	var code = lobby_code_input.text.strip_edges().to_upper()
	if code == "":
		lobby_status_label.text = "Enter a lobby code"
		return
	_join_by_code(code, name_text)

func _join_by_code(code: String, name_text: String):
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null and lobby_manager.join_lobby(code, name_text):
		_update_lobby_ui()
		lobby_status_label.text = "Joining lobby %s" % code
		lobby_panel.visible = true
		lobby_toggle_button.text = "Hide Online"
	else:
		lobby_status_label.text = "Failed to join lobby"

func _on_browse_public_pressed():
	_browsing_public = not _browsing_public
	lobby_code_input.visible = not _browsing_public
	_lobby_public_scroll.visible = _browsing_public
	lobby_browse_button.text = "Back" if _browsing_public else "Browse Public Lobbies"
	var lobby_manager = _get_lobby_manager()
	if _browsing_public:
		if lobby_manager != null:
			lobby_manager.list_public_lobbies()
		for child in lobby_public_list_box.get_children():
			child.queue_free()
		var loading = Label.new()
		loading.text = "Loading..."
		lobby_public_list_box.add_child(loading)
	else:
		if lobby_manager != null:
			lobby_manager.unsubscribe_public_lobbies()

func _on_public_lobbies_received(lobbies: Array):
	if not _browsing_public:
		return
	for child in lobby_public_list_box.get_children():
		child.queue_free()
	if lobbies.size() == 0:
		var empty = Label.new()
		empty.text = "No public lobbies right now."
		lobby_public_list_box.add_child(empty)
		return
	var ui_theme = load("res://uitheme.tres")
	for l in lobbies:
		var row = HBoxContainer.new()
		var label = Label.new()
		var started = bool(l.get("started", false))
		label.text = "%s (%s)%s" % [
			String(l.get("host_name", "Player")), int(l.get("player_count", 0)),
			"  [in progress]" if started else "",
		]
		if started:
			label.add_color_override("font_color", Color(0.8, 0.8, 0.6))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var join_btn = Button.new()
		join_btn.text = "Spectate" if started else "Join"
		join_btn.theme = ui_theme
		join_btn.rect_min_size = Vector2(0, 28)
		var code = String(l.get("code", ""))
		join_btn.connect("pressed", self, "_on_join_public_pressed", [code])
		row.add_child(join_btn)
		lobby_public_list_box.add_child(row)

func _on_join_public_pressed(code: String):
	var name_text = lobby_name_input.text.strip_edges()
	if name_text == "":
		name_text = "Guest"
	_join_by_code(code, name_text)

func _on_start_game_pressed():
	print("[savia] Start Game button pressed")
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null or not lobby_manager.is_host:
		print("[savia] aborting — lobby_manager null? ", lobby_manager == null, " is_host=", lobby_manager.is_host if lobby_manager else "n/a")
		return
	lobby_manager.push_current_mods()
	lobby_manager.start_game()

func _on_selected_song_changed(_song):
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null and lobby_manager.lobby_active and lobby_manager.is_host:
		lobby_manager.set_lobby_song(Rhythia.selected_song)
	_update_lobby_ui()
	if ranker_panel != null and ranker_panel.visible:
		_refresh_ranker_panel_for_selected_song()

func _on_lobby_created(code):
	lobby_code_label.text = "Code: %s" % code
	lobby_status_label.text = "Lobby created. Share the code."
	_update_lobby_ui()

func _on_lobby_error(reason):
	lobby_error_label.text = reason
	lobby_error_label.visible = true
	_status_error_until_msec = OS.get_ticks_msec() + 6000
	if lobby_panel != null and not lobby_panel.visible:
		lobby_panel.visible = true
		lobby_toggle_button.text = "Hide Online"

	var t = get_tree().create_timer(6.0)
	t.connect("timeout", self, "_on_error_label_timeout")

func _on_error_label_timeout():
	if OS.get_ticks_msec() >= _status_error_until_msec:
		lobby_error_label.visible = false

func _on_map_download_complete(_song_id):
	lobby_error_label.text = "Map ready."
	lobby_error_label.visible = true
	_status_error_until_msec = OS.get_ticks_msec() + 3000

func _on_map_download_progress(_song_id, bytes_received: int, total_bytes: int):
	if total_bytes <= 0:
		return
	var pct = int(clamp(float(bytes_received) / float(total_bytes), 0.0, 1.0) * 100.0)
	lobby_error_label.text = "Downloading map: %d%%" % pct
	lobby_error_label.visible = true

func _on_map_upload_progress(_song_id, bytes_sent: int, total_bytes: int):
	if total_bytes <= 0:
		return
	var pct = int(clamp(float(bytes_sent) / float(total_bytes), 0.0, 1.0) * 100.0)
	lobby_error_label.text = "Sending map to server: %d%%" % pct
	lobby_error_label.visible = true

func idle_status():
	if OS.has_feature("HTML5"): return

	var lobby_manager = _get_lobby_manager()
	if lobby_canvas == null or lobby_manager == null:
		return
	var lobby_active = lobby_manager.lobby_active
	var is_host = lobby_manager.is_host
	var activity = Discord.Activity.new()
	activity.set_type(Discord.ActivityType.Playing)
	activity.set_details("Main Menu")
	if OS.has_feature("debug"):
		if lobby_active:
			if is_host:
				activity.set_details("Main Menu - Developing and hosting a lobby")
				activity.set_state("Idle while listening to oh oh ooh saavvyyyy")
			else:
				activity.set_details("Main Menu - Developing and in a lobby")
				activity.set_state("Idle while listening to oh oh ooh saavvyyyy")
		else:
			activity.set_details("Main Menu - Developing")
			activity.set_state("Idle while listening to oh oh ooh saavvyyyy")
	else:
		if lobby_active:
			if is_host:
				activity.set_details("Main Menu - Hosting a lobby")
				activity.set_state("Idle while listening to oh oh ooh saavvyyyy")
			else:
				activity.set_details("Main Menu - In a lobby")
				activity.set_state("Idle while listening to oh oh ooh saavvyyyy")
		else:
			activity.set_details("Main Menu")
			activity.set_state("Idle while listening to oh oh ooh saavvyyyy")

	var assets = activity.get_assets()
	assets.set_large_image("icon-bg")

	Discord.activity_manager.update_activity(activity)

func _ready():
	get_tree().paused = false
	Rhythia.disarm_post_death_quick_restart()
	_build_lobby_ui()
	_build_profile_ui()
	_layout_lobby_ui()
	_build_keybinds_settings_tab()
	var settings_tab_container = get_node_or_null("Main/Settings/S/F/TabContainer")
	if settings_tab_container != null and settings_tab_container.has_node("Online") and settings_tab_container.has_node("Keybinds"):
		settings_tab_container.move_child(settings_tab_container.get_node("Online"), settings_tab_container.get_node("Keybinds").get_index() + 1)
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		if lobby_manager.lobby_active and lobby_manager.lobby_state.get("started", false):
			lobby_manager.reset_lobby_round()
		lobby_name_input.text = lobby_manager.player_name

	Rhythia.connect("selected_song_changed", self, "_on_selected_song_changed")
	Rhythia.connect("discord_login_changed", self, "_on_discord_login_changed")
	_on_discord_login_changed()
	Rhythia.connect("jp_changed", self, "_on_jp_changed")
	Rhythia.connect("sp_changed", self, "_on_sp_changed")
	Rhythia.connect("leaderboard_received", self, "_on_leaderboard_received")
	Rhythia.connect("leaderboard_sp_received", self, "_on_leaderboard_sp_received")
	if lobby_manager != null:
		lobby_manager.connect("ranker_status_received", self, "_on_ranker_status_received")
		lobby_manager.check_ranker_status()
		lobby_manager.connect("lobby_created", self, "_on_lobby_created")
		lobby_manager.connect("lobby_joined", self, "_update_lobby_ui")
		lobby_manager.connect("lobby_closed", self, "_update_lobby_ui")
		lobby_manager.connect("lobby_state_changed", self, "_update_lobby_ui")
		lobby_manager.connect("game_started", self, "_update_lobby_ui")
		lobby_manager.connect("lobby_error", self, "_on_lobby_error")
		lobby_manager.connect("map_download_complete", self, "_on_map_download_complete")
		lobby_manager.connect("map_download_progress", self, "_on_map_download_progress")
		lobby_manager.connect("map_upload_progress", self, "_on_map_upload_progress")
		lobby_manager.connect("public_lobbies_received", self, "_on_public_lobbies_received")
		lobby_manager.connect("chat_message_received", self, "_on_chat_message_received")
		lobby_manager.connect("global_chat_message_received", self, "_on_global_chat_message_received")
		if lobby_manager.has_admin_key():
			_build_admin_ui()
			lobby_manager.connect("admin_bans_received", self, "_on_admin_bans_received")
			lobby_manager.connect("admin_all_lobbies_received", self, "_on_admin_lobbies_received")
			lobby_manager.connect("admin_live_bans_received", self, "_on_admin_live_bans_received")
			lobby_manager.connect("admin_rankers_received", self, "_on_admin_rankers_received")
		lobby_manager.connect("admin_player_tags_received", self, "_on_admin_player_tags_received")


	if AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Music")) > 0:
		AudioServer.remove_bus_effect(AudioServer.get_bus_index("Music"), 0)

	$BlackFade.visible = true
	$BlackFade.color = Color(0, 0, 0, black_fade)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if ProjectSettings.get_setting("application/config/discord_rpc"):
		if not OS.has_feature("HTML5"):
			var lobby_active = lobby_manager.lobby_active
			var is_host = lobby_manager.is_host
			var activity = Discord.Activity.new()
			activity.set_type(Discord.ActivityType.Playing)
			if OS.has_feature("debug"):
				if lobby_active:
					if is_host:
						activity.set_details("Main Menu - Developing and hosting a lobby")
						activity.set_state("Selecting a song")
					else:
						activity.set_details("Main Menu - Developing and in a lobby")
						activity.set_state("Selecting a song")
				else:
					activity.set_details("Main Menu - Developing")
					activity.set_state("Selecting a song")
			else:
				if lobby_active:
					if is_host:
						activity.set_details("Main Menu - Hosting a lobby")
						activity.set_state("Selecting a song")
					else:
						activity.set_details("Main Menu - In a lobby")
						activity.set_state("Selecting a song")
				else:
					activity.set_details("Main Menu")
					activity.set_state("Selecting a song")

			var assets = activity.get_assets()
			assets.set_large_image("icon-bg")

			Discord.activity_manager.update_activity(activity)

			get_tree().create_timer(300).connect("timeout", self, "idle_status")
var black_fade_target: bool = false
var black_fade: float = 1

func _on_mods_changed_for_lobby():
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null and lobby_manager.lobby_active and lobby_manager.is_host:
		lobby_manager.push_current_mods()
		lobby_manager.lobby_state.mods = lobby_manager._collect_current_mods()
		_update_lobby_ui()

func _process(delta):
	_layout_lobby_ui()
	if lobby_toggle_button != null:
		var sidebar = get_node_or_null("Sidebar")
		var on_main_menu = sidebar != null and sidebar.get("pages") != null and sidebar.pages.size() > 0 and bool(sidebar.pages[0].visible)
		lobby_toggle_button.visible = on_main_menu
	if Input.is_action_just_pressed("ui_end") and Input.is_key_pressed(KEY_SHIFT):
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")

	if black_fade_target and black_fade != 1:
		black_fade = min(black_fade + (delta / 0.3), 1)
		$BlackFade.color = Color(0, 0, 0, black_fade)
	elif not black_fade_target and black_fade != 0:
		black_fade = max(black_fade - (delta / 0.5), 0)
		$BlackFade.color = Color(0, 0, 0, black_fade)
	$BlackFade.visible = (black_fade != 0)
