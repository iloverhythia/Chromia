extends PanelContainer

# @mentions in the global chat.
#   ChatMention.attach(line_edit, lobby_manager)  typing "@" + the start of a
#       name lists matching players above the box: Tab (or a click) puts the
#       name in, Up / Down picks, Escape hides the list
#   ChatMention.split(text, lm)     the message in pieces, [text, mention?, you?]
#   ChatMention.mentions_me(text, lm)
# Names come from who's online and who wrote in the chat recently; names with
# spaces work too (the longest known name after the "@" counts).
# LobbyManager tells you when someone mentions you (a notification, even
# while you play).

const MAX_SHOWN := 6
const NAME_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789_"

# ── names ──
static func known_names(lm) -> Array:
	var seen := {}
	var out := []
	if lm == null:
		return out
	var lists := []
	if lm.get("online_players") is Array:
		for p in lm.online_players:
			if p is Dictionary:
				lists.append(String(p.get("name", "")))
	if lm.get("global_chat_history") is Array:
		for e in lm.global_chat_history:
			if e is Dictionary:
				lists.append(String(e.get("name", "")))
	for n in lists:
		n = n.strip_edges()
		if n != "" and not seen.has(n.to_lower()):
			seen[n.to_lower()] = true
			out.append(n)
	return out

# your names, lower case: the name the server shows for you, and the one in
# Multiplayer settings
static func my_names(lm) -> Array:
	var out := []
	if lm == null:
		return out
	var you := int(lm.get("my_player_number")) if lm.get("my_player_number") != null else -1
	if lm.get("online_players") is Array:
		for p in lm.online_players:
			if p is Dictionary and int(p.get("number", -2)) == you:
				var n := String(p.get("name", "")).strip_edges().to_lower()
				if n != "":
					out.append(n)
	var pn := String(lm.get("player_name")).strip_edges().to_lower() if lm.get("player_name") != null else ""
	if pn != "" and not out.has(pn):
		out.append(pn)
	# (names from your own chat messages)
	if lm.get("global_chat_history") is Array:
		for e in lm.global_chat_history:
			if e is Dictionary and String(e.get("client_id", "")) != "" and String(e.get("client_id", "")) == Rhythia.cid:
				var n2 := String(e.get("name", "")).strip_edges().to_lower()
				if n2 != "" and not out.has(n2):
					out.append(n2)
	return out

# longest first (so "@Big Tom" wins over "@Big")
static func _longest_first(arr: Array) -> Array:
	var out := []
	for n in arr:
		var k := 0
		while k < out.size() and String(out[k]).length() >= String(n).length():
			k += 1
		out.insert(k, n)
	return out

# the mention right after text[at] == "@": its length without the "@" (0 if none)
static func _mention_len(text: String, at: int, names: Array) -> int:
	var low := text.to_lower()
	for n in names:
		var nl: String = n.to_lower()
		if low.substr(at + 1, nl.length()) == nl:
			var after := at + 1 + nl.length()
			if after >= text.length() or NAME_CHARS.find(low[after]) == -1:
				return nl.length()
	# an unknown name: up to the next space
	var e := at + 1
	while e < text.length() and text[e] != " ":
		e += 1
	return e - at - 1

# [[text, is_mention, is_you], ...]
static func split(text: String, lm) -> Array:
	var names := known_names(lm)
	var mine := my_names(lm)
	for m in mine:
		names.append(m)
	names = _longest_first(names)
	var out := []
	var i := 0
	var start := 0
	while i < text.length():
		if text[i] == "@" and (i == 0 or NAME_CHARS.find(text[i - 1].to_lower()) == -1):
			var l := _mention_len(text, i, names)
			if l > 0:
				if i > start:
					out.append([text.substr(start, i - start), false, false])
				var who := text.substr(i + 1, l).to_lower()
				out.append([text.substr(i, l + 1), true, mine.has(who)])
				i += l + 1
				start = i
				continue
		i += 1
	if start < text.length():
		out.append([text.substr(start), false, false])
	return out

static func mentions_me(text: String, lm) -> bool:
	if text.find("@") == -1:
		return false
	for part in split(text, lm):
		if part[2]:
			return true
	return false

# ── the list while typing ──
static func attach(le: LineEdit, lm):
	var m = load("res://scripts/ui/ChatMention.gd").new()
	m.name = "MentionList"
	m.field = le
	m.lm = lm
	le.add_child(m)
	return m

var field: LineEdit
var lm
var _box: VBoxContainer
var _matches := []
var _pick := 0
var _at := -1 # where the "@" being typed is

func _ready():
	set_as_toplevel(true)
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.062, 0.095, 0.98)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_stylebox_override("panel", sb)
	_box = VBoxContainer.new()
	_box.add_constant_override("separation", 0)
	add_child(_box)
	field.connect("text_changed", self, "_on_text")
	field.connect("gui_input", self, "_on_key")
	field.connect("focus_exited", self, "_on_focus_lost")

func _on_focus_lost():
	# (a click on the list takes the focus first: hide a moment later)
	yield(get_tree().create_timer(0.15), "timeout")
	if is_instance_valid(field) and not field.has_focus():
		_hide()

func _hide():
	visible = false
	_matches = []
	_at = -1

func _on_text(_t = ""):
	var text := field.text
	var caret := field.caret_position
	var i := caret - 1
	_at = -1
	while i >= 0 and caret - i <= 40:
		if text[i] == "@":
			if i == 0 or text[i - 1] == " ":
				_at = i
			break
		i -= 1
	if _at == -1:
		return _hide()
	var typed := text.substr(_at + 1, caret - _at - 1).to_lower()
	var mine := my_names(lm)
	var starts := []
	var inside := []
	for n in known_names(lm):
		var nl: String = n.to_lower()
		if mine.has(nl) or nl == typed:
			continue
		if nl.begins_with(typed):
			starts.append(n)
		elif typed != "" and nl.find(typed) != -1:
			inside.append(n)
	starts.sort_custom(self, "_alpha")
	inside.sort_custom(self, "_alpha")
	_matches = (starts + inside).slice(0, MAX_SHOWN - 1) if not (starts + inside).empty() else []
	if _matches.empty():
		return _hide()
	_pick = 0
	_show_list()

func _alpha(a: String, b: String) -> bool:
	return a.to_lower() < b.to_lower()

func _show_list():
	for c in _box.get_children():
		c.queue_free()
	var font: Font = field.get_font("font")
	for k in range(_matches.size()):
		var b := Button.new()
		b.text = "@" + String(_matches[k])
		b.flat = true
		b.align = Button.ALIGN_LEFT
		b.focus_mode = FOCUS_NONE
		b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		b.add_font_override("font", font)
		var on := k == _pick
		var col := Color(1, 0.55, 0.8) if on else Color(0.9, 0.92, 1)
		for s in ["font_color", "font_color_hover", "font_color_pressed"]:
			b.add_color_override(s, col)
		if on:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.08)
			sb.set_corner_radius_all(2)
			b.add_stylebox_override("normal", sb)
			b.add_stylebox_override("hover", sb)
		b.connect("pressed", self, "_choose", [k])
		_box.add_child(b)
	visible = true
	rect_size = Vector2()
	call_deferred("_place")

func _place():
	if not visible or not is_instance_valid(field):
		return
	var sz := get_combined_minimum_size()
	sz.x = max(sz.x, min(field.rect_size.x, 260.0))
	rect_size = sz
	rect_global_position = (field.rect_global_position - Vector2(0, sz.y + 4)).floor()

func _on_key(ev):
	if not visible or not (ev is InputEventKey) or not ev.pressed:
		return
	match ev.scancode:
		KEY_TAB:
			_choose(_pick)
		KEY_UP:
			_pick = (_pick - 1 + _matches.size()) % _matches.size()
			_show_list()
		KEY_DOWN:
			_pick = (_pick + 1) % _matches.size()
			_show_list()
		KEY_ESCAPE:
			_hide()
		_:
			return
	field.accept_event()

func _choose(k: int):
	if _at == -1 or k < 0 or k >= _matches.size():
		return
	var text := field.text
	var caret := field.caret_position
	var put := "@" + String(_matches[k]) + " "
	var after := text.substr(caret)
	if after.begins_with(" "):
		after = after.substr(1)
	field.text = (text.substr(0, _at) + put + after).substr(0, field.max_length if field.max_length > 0 else 100000)
	field.caret_position = min(_at + put.length(), field.text.length())
	_hide()
	field.grab_focus()
