extends Node

# Reactions under chat lines and an emoji picker for chat boxes.
#   ChatReactions.add(rich_text_label, line_id, lobby_manager, size_px)
#     after a line's text: its reactions (click one to add / take back yours)
#     and a small "+" that opens the reaction picker
#   ChatReactions.picker_button(line_edit, size_px) -> Button
#     a button that opens a grid of emoji and types the one you click
# The reactions are the server's own list (savia_web lobbies.js REACTIONS).

const REACTIONS := ["👍", "❤️", "😂", "😮", "😢", "🔥", "🎉", "👀", "💀", "😭", "🙏", "💯"]
const PICKER := [
	"😀", "😁", "😂", "🤣", "😊", "😍", "🥰", "😘", "😎", "🤩", "🥳", "😏",
	"😮", "😳", "🥺", "😢", "😭", "😤", "😡", "🤯", "😱", "🤔", "🙄", "😴",
	"💀", "👻", "🤡", "😈", "👍", "👎", "👏", "🙌", "🙏", "💪", "👀", "😅",
	"❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "💔", "✨", "🔥", "💯", "⭐",
	"🎉", "🎵", "🎶", "🎮", "🏆", "🥇", "⚡", "🌈", "🐱", "🐶", "🦊", "🐸",
]
const META_W := "chromia_who:" # (a writer's name: <line id>:<name>)
const META_R := "chromia_react:"
const META_P := "chromia_reactpick:"
const DIM := Color(0.6, 0.57, 0.68)
const MINE := Color(1, 0.756863, 0.960784)

# the Emoji pack's key for an emoji ("1f44d", "2764" ...)
static func _key(e: String) -> String:
	var parts := []
	for c in load("res://scripts/ui/Emoji.gd")._codepoints(e):
		if c[0] != 0xFE0F:
			parts.append("%x" % c[0])
	return PoolStringArray(parts).join("-")

static func _tex(e: String) -> Texture:
	var E = load("res://scripts/ui/Emoji.gd")
	if not E._data().ok:
		return null
	return E._texture(_key(e))

# Returns how many lines it added under the message (0 or 1).
static func add(rtl: RichTextLabel, mid: String, lm, px: int = 16, indent: int = 1) -> int:
	if mid == "" or lm == null or not ("chat_reactions" in lm):
		return 0
	_hook(rtl, lm)
	var E = load("res://scripts/ui/Emoji.gd")
	var r = lm.chat_reactions.get(mid)
	var any := false
	if r is Dictionary:
		for e in REACTIONS:
			if int(r.counts.get(e, 0)) > 0:
				any = true
	if not any:
		# (no reactions yet: just a faint + at the end of the message)
		rtl.add_text("  ")
		_plus(rtl, mid)
		return 0
	# the reactions on their own line under the message
	rtl.newline()
	rtl.push_indent(indent)
	for e in REACTIONS: # (always in the same order)
		var n := int(r.counts.get(e, 0))
		if n <= 0:
			continue
		var mine: bool = e in r.mine
		rtl.push_meta(META_R + mid + ":" + e)
		rtl.push_color(MINE if mine else DIM)
		E.add_text(rtl, e, px)
		rtl.add_text(" %d" % n)
		rtl.pop()
		rtl.pop()
		rtl.add_text("   ")
	_plus(rtl, mid)
	rtl.pop()
	return 1

static func _plus(rtl: RichTextLabel, mid: String):
	rtl.push_meta(META_P + mid)
	rtl.push_color(Color(DIM.r, DIM.g, DIM.b, 0.55))
	rtl.add_text("+")
	rtl.pop()
	rtl.pop()

# Staff (Owner / Admin tag) right-click a name in chat: delete that message
# for everyone, or ban its writer from chat (the server checks it's staff).
# Chat boxes put the name between name_start and name_end.
static func name_start(rtl: RichTextLabel, mid: String, name: String, lm) -> bool:
	if mid == "" or lm == null or not lm.has_method("staff_delete_chat"):
		return false
	_hook(rtl, lm)
	rtl.push_meta(META_W + mid + ":" + name)
	return true

static func name_end(rtl: RichTextLabel, started: bool):
	if started:
		rtl.pop()

# a plain Label line (the menu's small global chat): right-click it
static func moderate_label(label: Control, mid: String, name: String, lm):
	if mid == "" or lm == null or not lm.has_method("staff_delete_chat"):
		return
	label.set_meta("chat_mid", mid)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	var h = load("res://scripts/ui/ChatReactions.gd").new()
	h.name = "Moderate"
	h._lm = lm
	h._hover_who = mid + ":" + name
	label.add_child(h)
	label.connect("gui_input", h, "_on_input", [label])

static func _hook(rtl: RichTextLabel, lm):
	if rtl.has_meta("_reactions"):
		return
	rtl.set_meta("_reactions", true)
	rtl.meta_underlined = false
	var h = load("res://scripts/ui/ChatReactions.gd").new()
	h.name = "Reactions"
	h._lm = lm
	h._rtl = rtl
	rtl.add_child(h)
	rtl.connect("meta_clicked", h, "_on_meta")
	rtl.connect("meta_hover_started", h, "_on_hover", [true])
	rtl.connect("meta_hover_ended", h, "_on_hover", [false])
	rtl.connect("gui_input", h, "_on_input", [rtl])

var _lm
var _rtl: RichTextLabel
var _pop: PopupPanel

var _hover_who := "" # (the name under the mouse: <line id>:<name>)
var _menu: PopupMenu

func _is_staff() -> bool:
	return is_instance_valid(_lm) and bool(_lm.get("i_am_staff"))

func _on_input(ev, ctl: Control):
	if _hover_who == "" or not (ev is InputEventMouseButton) or not ev.pressed or ev.button_index != BUTTON_RIGHT or not _is_staff():
		return
	ctl.accept_event()
	var at := _hover_who.find(":")
	var mid := _hover_who.substr(0, at)
	var who := _hover_who.substr(at + 1)
	if _menu == null or not is_instance_valid(_menu):
		_menu = PopupMenu.new()
		ctl.add_child(_menu) # (on its owner's layer: above the Spectate window)
		_menu.connect("id_pressed", self, "_on_mod_pick")
	_menu.clear()
	_menu.add_item("Delete message", 0)
	_menu.add_item("Chat ban %s" % who, 1)
	_menu.set_meta("mid", mid)
	_menu.set_meta("who", who)
	var vp := ctl.get_viewport()
	var pos: Vector2 = vp.get_mouse_position()
	_menu.rect_size = Vector2()
	_menu.popup(Rect2(pos, Vector2(1, 1)))
	var sz: Vector2 = _menu.get_combined_minimum_size()
	var vs: Vector2 = vp.get_visible_rect().size
	_menu.rect_global_position = Vector2(clamp(pos.x, 4, vs.x - sz.x - 4), clamp(pos.y, 4, vs.y - sz.y - 4))

func _on_mod_pick(id: int):
	if not is_instance_valid(_lm):
		return
	var mid := String(_menu.get_meta("mid"))
	if id == 0:
		_lm.staff_delete_chat(mid)
	elif id == 1:
		Globals.confirm_prompt.open("Ban %s from chat? Undo it in the admin panel (Bans)." % String(_menu.get_meta("who")), "Chat ban", [{text = "Cancel"}, {text = "Ban"}])
		var option = yield(Globals.confirm_prompt, "option_selected")
		Globals.confirm_prompt.close()
		if option == 1 and is_instance_valid(_lm):
			_lm.staff_chat_ban(mid)

func _on_hover(meta, on: bool):
	var m := String(meta)
	if m.begins_with(META_W):
		_hover_who = m.substr(META_W.length()) if on else ""
		if _is_staff():
			_rtl.hint_tooltip = "Right-click: delete / chat ban" if on else ""
		return
	if m.begins_with(META_R) or m.begins_with(META_P):
		_rtl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
		if on:
			_rtl.hint_tooltip = "React" if m.begins_with(META_P) else "Add yours / take it back"
		else:
			_rtl.hint_tooltip = ""

func _on_meta(meta):
	var m := String(meta)
	if m.begins_with(META_R):
		var rest := m.substr(META_R.length())
		var at := rest.find(":")
		if at > 0 and is_instance_valid(_lm):
			_lm.send_chat_reaction(rest.substr(0, at), rest.substr(at + 1))
	elif m.begins_with(META_P):
		_open_picker(m.substr(META_P.length()))

func _open_picker(mid: String):
	if _pop == null or not is_instance_valid(_pop):
		_pop = _grid_popup(REACTIONS, 30, self, "_on_pick")
		_rtl.add_child(_pop) # (a popup draws on its owner's layer: above the Spectate window)
	_pop.set_meta("mid", mid)
	_popup_at_mouse(_pop, _rtl)

func _on_pick(e: String, pop: PopupPanel):
	pop.hide()
	if is_instance_valid(_lm):
		_lm.send_chat_reaction(String(pop.get_meta("mid")), e)

static func _popup_at_mouse(pop: PopupPanel, from: Control):
	var vp := from.get_viewport()
	var at: Vector2 = vp.get_mouse_position()
	pop.rect_size = Vector2()
	pop.popup(Rect2(at, Vector2(1, 1)))
	# (kept on screen)
	var sz: Vector2 = pop.get_combined_minimum_size()
	var vs: Vector2 = vp.get_visible_rect().size
	pop.rect_global_position = Vector2(clamp(at.x - sz.x * 0.5, 4, vs.x - sz.x - 4), clamp(at.y - sz.y - 8, 4, vs.y - sz.y - 4))

# a popup with a grid of emoji buttons: target.method(emoji, popup) on a click
static func _grid_popup(list: Array, px: int, target: Object, method: String) -> PopupPanel:
	var pop := PopupPanel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.095, 0.13, 0.98)
	sb.border_color = Color(0.45, 0.4, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	pop.add_stylebox_override("panel", sb)
	var grid := GridContainer.new()
	grid.columns = 6 if list.size() <= 12 else 12
	grid.add_constant_override("hseparation", 4)
	grid.add_constant_override("vseparation", 4)
	pop.add_child(grid)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.12)
	hover.set_corner_radius_all(6)
	var none := StyleBoxEmpty.new()
	for e in list:
		var b := Button.new()
		b.rect_min_size = Vector2(px + 8, px + 8)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_stylebox_override("normal", none)
		b.add_stylebox_override("hover", hover)
		b.add_stylebox_override("pressed", hover)
		b.add_stylebox_override("focus", none)
		var t := _tex(e)
		if t != null:
			var tr := TextureRect.new()
			tr.texture = t
			tr.expand = true
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.anchor_right = 1
			tr.anchor_bottom = 1
			tr.margin_left = 4
			tr.margin_top = 4
			tr.margin_right = -4
			tr.margin_bottom = -4
			b.add_child(tr)
		else:
			b.text = e
		b.connect("pressed", target, method, [e, pop])
		grid.add_child(b)
	return pop

# ------------------------------------------------------------------ typing emoji

static func picker_button(le: LineEdit, px: int = 22) -> Button:
	var b := Button.new()
	b.name = "EmojiButton"
	b.hint_tooltip = "Emoji"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.rect_min_size = Vector2(px + 16, px + 10)
	var t := _tex("🙂")
	if t != null:
		b.icon = t
		b.expand_icon = true
	else:
		b.text = ":)"
	var h = load("res://scripts/ui/ChatReactions.gd").new()
	h.name = "Picker"
	h._le = le
	b.add_child(h)
	b.connect("pressed", h, "_open_typing")
	return b

var _le: LineEdit
func _open_typing():
	if not is_instance_valid(_le):
		return
	if _pop == null or not is_instance_valid(_pop):
		_pop = _grid_popup(PICKER, 26, self, "_on_type")
		get_parent().add_child(_pop)
	_popup_at_mouse(_pop, get_parent())

func _on_type(e: String, _pop_unused: PopupPanel):
	if not is_instance_valid(_le) or not _le.editable:
		return
	var at: int = _le.caret_position
	var t := _le.text
	if t.length() + e.length() > _le.max_length and _le.max_length > 0:
		return
	_le.text = t.substr(0, at) + e + t.substr(at)
	_le.caret_position = at + e.length()
	_le.emit_signal("text_changed", _le.text) # (the field draws its emoji: Emoji.gd)
	_le.grab_focus()

func _exit_tree():
	if _pop != null and is_instance_valid(_pop):
		_pop.queue_free()
