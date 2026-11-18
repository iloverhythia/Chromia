extends PanelContainer

# Your profile > Frames (next to Cards): the frame round your profile picture
# in the game (profile, Spectate grid, Online players) and on your website
# profile. Every card you have gives you its frame (unlock more by unlocking
# cards); you pick the frame on its own, so it can differ from your card.
# Default is no frame. The looks are drawn by FrameDraw.gd; the server keeps
# which one you picked (LobbyManager get_frames / set_frame).

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")
const FrameView = preload("res://scripts/ui/FrameView.gd")

var S
var lm
var _grid: GridContainer
var _scroll: ScrollContainer = null
var _msg: Label
var _chosen := "default"
var _me_name := ""
var _me_pic := ""

static func open_on(parent: Node):
	# (every one that is open, each with its layer and the dimmed screen behind it)
	for old in parent.get_tree().get_nodes_in_group("frames_menu"):
		if not old.is_queued_for_deletion():
			old.close()
	var layer := CanvasLayer.new()
	layer.layer = 110
	layer.name = "FramesMenuLayer"
	# On the screen the button is on: the window, or in VR the menu screen in
	# front of you. (On the window's own layer it opened where nobody in a
	# headset could see or close it, and every press stacked another one.)
	parent.get_viewport().add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	layer.add_child(dim)
	var m = load("res://scripts/ui/FramesMenu.gd").new()
	m.name = "FramesMenu"
	m.add_to_group("frames_menu")
	layer.add_child(m)
	dim.connect("gui_input", m, "_on_dim")
	return m

func _init():
	S = OnlineStyle.new()
	add_stylebox_override("panel", OnlineStyle.flat(S.WINDOW_BG, 6, Color(1, 1, 1, 0.1), 1, 22, 18))
	rect_min_size = Vector2(600, 0)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t: Label = S.heading("Frames")
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "Close"
	S.button(x)
	x.connect("pressed", self, "close")
	head.add_child(x)
	v.add_child(S.label("The frame round your profile picture, in the game and on your website profile. Every card you unlock gives you its frame too.", S.f_small, S.DIM, true))
	v.add_child(S.rule())
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_constant_override("hseparation", 10)
	_grid.add_constant_override("vseparation", 10)
	# (in a list that scrolls once there are more tiles than fit on the screen: _place)
	_scroll = ScrollContainer.new()
	_scroll.scroll_horizontal_enabled = false
	v.add_child(_scroll)
	_scroll.add_child(_grid)
	_msg = S.label("Loading your frames...", S.f_small, S.DIM)
	v.add_child(_msg)

func _ready():
	lm = get_node_or_null("/root/LobbyManager")
	if lm != null:
		_me_name = String(lm.player_name)
	if Rhythia.get("discord_user") is Dictionary:
		_me_pic = String(Rhythia.discord_user.get("avatar_url", ""))
	if lm != null:
		lm.connect("frames_received", self, "_on_frames")
		lm.connect("frame_message", self, "_on_message")
		lm.get_frames()
	get_viewport().connect("size_changed", self, "_place")
	call_deferred("_place_soon")

# The window is as big as what's in it, never taller than the screen (the
# tiles scroll then), in the middle. Its size is worked out afresh each time:
# it used to be set to "at least what's needed" while the old tiles of the
# list were still there next to the new ones, so after picking one it was
# twice as tall and stayed that way, down past the bottom of the screen.
func _place():
	if not is_inside_tree() or _scroll == null:
		return
	var vp := get_viewport_rect().size
	var tiles: Vector2 = _grid.get_combined_minimum_size()
	_scroll.rect_min_size = Vector2(tiles.x, 0)
	var rest: float = get_combined_minimum_size().y # (everything but the tiles)
	var room: float = max(120.0, vp.y - 40.0 - rest)
	var bar: float = 14.0 if tiles.y > room else 0.0
	_scroll.rect_min_size = Vector2(tiles.x + bar, min(tiles.y, room))
	rect_size = get_combined_minimum_size()
	rect_position = ((vp - rect_size) / 2.0).floor()

# (now, and once more when the new tiles and the wrapped text have their sizes)
func _place_soon():
	_place()
	yield(get_tree(), "idle_frame")
	_place()

func _on_dim(ev):
	if ev is InputEventMouseButton and ev.pressed:
		close()

func _input(ev):
	if ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()

func close():
	remove_from_group("frames_menu")
	var layer = get_parent()
	if layer is CanvasLayer:
		layer.queue_free()
	else:
		queue_free()

func _on_frames(frames: Array, chosen: String):
	_chosen = chosen
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	# (as the Cards menu: only the ones you have; admins see them all)
	var see_all: bool = bool(Rhythia.get("is_staff"))
	var locked := 0
	for f in frames:
		if f is Dictionary:
			var have := bool(f.get("unlocked", false))
			if not have and not see_all:
				continue
			_grid.add_child(_tile(f))
			if not have:
				locked += 1
	if locked > 0:
		_msg.text = "%d locked (only admins see these)." % locked
	else:
		_msg.text = "These are the frames you have. Each card you unlock brings its frame."
	call_deferred("_place_soon")

func _tile(f: Dictionary) -> Control:
	var id := String(f.get("id", ""))
	var have := bool(f.get("unlocked", false))
	var picked := id == _chosen
	var b := Button.new()
	b.rect_min_size = Vector2(130, 150)
	b.focus_mode = FOCUS_NONE
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bg: Color = S.CARD_HOVER if st == "hover" else S.CARD_BG
		b.add_stylebox_override(st, OnlineStyle.flat(bg, 6, S.ACCENT if picked else Color(1, 1, 1, 0.08), 2 if picked else 1))
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND if have else CURSOR_ARROW
	b.disabled = not have
	b.hint_tooltip = ("Showing" if picked else "Use this frame") if have else "Locked"
	# your picture with the frame on it
	var pic: Control = S.avatar(_me_name if _me_name != "" else "You", _me_pic, self)
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	pic.rect_min_size = Vector2(56, 56)
	pic.rect_size = Vector2(56, 56)
	pic.rect_position = Vector2(37, 26)
	var sb = pic.get_stylebox("panel")
	if sb is StyleBoxFlat:
		sb.set_corner_radius_all(28)
	b.add_child(pic)
	var fv = FrameView.new()
	fv.set_frame(f)
	pic.add_child(fv)
	var nm: Label = S.label(String(f.get("name", "Frame")), S.f_bold, S.TEXT)
	nm.align = Label.ALIGN_CENTER
	nm.mouse_filter = MOUSE_FILTER_IGNORE
	nm.anchor_right = 1
	nm.margin_top = 104
	nm.clip_text = true
	b.add_child(nm)
	var sub: Label = S.label("Showing" if picked else ("No frame" if String(f.get("style", "")) == "none" else ("" if have else "Locked")), S.f_small, S.ACCENT if picked else S.DIM)
	sub.align = Label.ALIGN_CENTER
	sub.mouse_filter = MOUSE_FILTER_IGNORE
	sub.anchor_right = 1
	sub.margin_top = 124
	b.add_child(sub)
	if not have:
		b.modulate = Color(1, 1, 1, 0.45)
	b.connect("pressed", self, "_pick", [id])
	return b

func _pick(id: String):
	if lm != null:
		_msg.text = "Saving..."
		lm.set_frame(id)

func _on_message(text: String, refresh: bool):
	_msg.text = text
	if refresh and lm != null:
		lm.get_frames()
