extends CanvasLayer

# Global chat while you're watching someone (HUD.gd adds it in spectate mode,
# not in VR). The last few messages sit in the bottom-left corner and fade
# when nothing new comes in. Enter (or clicking it) opens the box: Enter sends,
# Esc closes. While you type, the game's keys (give up, pause / skip, Tab) are
# kept from reacting.

const LINES := 7
const FADE_AFTER := 8.0      # seconds without news before it fades
const FADED := 0.35
const NAME_COL := Color(0.75, 0.62, 1.0)
const YOU_COL := Color(1.0, 0.85, 0.2)
const TEXT_COL := Color(0.93, 0.95, 1.0)
const DIM := Color(0.62, 0.66, 0.78)

var _lm = null
var _panel := PanelContainer.new()
var _log := RichTextLabel.new()
var _input := LineEdit.new()
var _hint := Label.new()
var _quiet := 0.0
var _typing := false

static func typing() -> bool:
	return Engine.has_meta("spectate_chat_typing") and bool(Engine.get_meta("spectate_chat_typing"))

static func _font(path: String, size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	return f

func setup(lm):
	_lm = lm

func _ready():
	layer = 51
	pause_mode = PAUSE_MODE_PROCESS
	process_priority = -1000 # (before the game reads its keys)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.62)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_panel.add_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.connect("gui_input", self, "_on_panel_input")
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_constant_override("separation", 6)
	_panel.add_child(v)

	var regular := _font("res://assets/font/Lato/Lato-Regular.ttf", 15)
	_log.add_font_override("normal_font", regular)
	_log.add_font_override("bold_font", _font("res://assets/font/Lato/Lato-Bold.ttf", 15))
	_log.add_color_override("default_color", TEXT_COL)
	_log.scroll_active = false
	_log.scroll_following = true
	_log.fit_content_height = true
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.rect_min_size = Vector2(360, 0)
	v.add_child(_log)

	_input.placeholder_text = "Say something... (Enter sends, Esc closes)"
	_input.max_length = 300
	_input.add_font_override("font", regular)
	_input.visible = false
	_input.connect("text_entered", self, "_on_entered")
	v.add_child(_input)

	_hint.add_font_override("font", _font("res://assets/font/Lato/Lato-Regular.ttf", 13))
	_hint.add_color_override("font_color", DIM)
	v.add_child(_hint)

	if _lm != null:
		_lm.connect("global_chat_message_received", self, "_on_message")
	_rebuild()
	get_viewport().connect("size_changed", self, "_place")
	_place()

func _exit_tree():
	Engine.set_meta("spectate_chat_typing", false)

func _place():
	var vp := get_viewport().get_visible_rect().size
	_panel.rect_size = Vector2(_panel.rect_size.x, 0) # (shrinks to fit)
	_panel.rect_position = Vector2(24, vp.y - _panel.get_combined_minimum_size().y - 24)

func _muted() -> bool:
	return bool(Rhythia.get("mute_global_chat"))

func _rebuild():
	_log.clear()
	if _muted():
		_log.push_color(DIM)
		_log.add_text("Global chat is muted (Settings > Online).")
		_log.pop()
		_hint.visible = false
	else:
		var hist: Array = _lm.global_chat_history if _lm != null else []
		var from: int = max(0, hist.size() - LINES)
		var first := true
		for i in range(from, hist.size()):
			var m = hist[i]
			if not (m is Dictionary):
				continue
			if not first:
				_log.newline()
			first = false
			_line(Globals.s(m.get("client_id", "")), Globals.s(m.get("name", "")), Globals.s(m.get("text", "")))
		if first:
			_log.push_color(DIM)
			_log.add_text("No messages yet.")
			_log.pop()
		_hint.visible = not _typing
		_hint.text = "Enter to chat"
	call_deferred("_place")

func _line(client_id: String, pname: String, text: String):
	var you: bool = client_id != "" and client_id == Rhythia.cid
	_log.push_bold()
	_log.push_color(YOU_COL if you else NAME_COL)
	_log.add_text((pname if pname != "" else "Player") + ": ")
	_log.pop()
	_log.pop()
	_log.add_text(text) # (plain text: no BBCode from other players)

func _on_message(_cid, _name, _text, _ts):
	_quiet = 0.0
	_rebuild()

func _on_panel_input(e):
	if e is InputEventMouseButton and e.pressed and e.button_index == BUTTON_LEFT and not _typing:
		_open()

func _open():
	if _muted() or _typing:
		return
	_typing = true
	Engine.set_meta("spectate_chat_typing", true)
	_input.visible = true
	_hint.visible = false
	_input.grab_focus()
	_quiet = 0.0
	call_deferred("_place")

func _close():
	_typing = false
	Engine.set_meta("spectate_chat_typing", false)
	_input.text = ""
	_input.release_focus()
	_input.visible = false
	_hint.visible = not _muted()
	call_deferred("_place")

func _on_entered(text: String):
	text = text.strip_edges()
	if text != "" and _lm != null and not _muted():
		_lm.send_global_chat_message(text)
	_close()

func _input(e):
	if not (e is InputEventKey):
		return
	if _typing:
		# (released here, before anything checks them this frame; held keys too)
		for a in ["give_up", "pause"]:
			if e.is_action(a):
				Input.action_release(a)
		if e.pressed and not e.echo and e.scancode == KEY_ESCAPE:
			_close()
			get_tree().set_input_as_handled()
		return
	if e.pressed and not e.echo and (e.scancode == KEY_ENTER or e.scancode == KEY_KP_ENTER) and not _muted():
		_open()
		get_tree().set_input_as_handled()

func _process(delta):
	if _typing:
		# the key you're typing shouldn't also give up, skip or pause
		for a in ["give_up", "pause"]:
			if Input.is_action_pressed(a):
				Input.action_release(a)
		if not _input.has_focus():
			_input.grab_focus()
	_quiet += delta
	var target := 1.0 if (_typing or _quiet < FADE_AFTER) else FADED
	_panel.modulate.a = lerp(_panel.modulate.a, target, min(1.0, delta * 4.0))
