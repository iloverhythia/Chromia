extends Control
# Spectate: a round eye button in the bottom-right corner of the menu (on its
# own layer, above everything but notifications) opens the Spectate window:
# everyone online as square cards (picture, name, what they're doing,
# leaderboard place, device), a search box and favourites filter at the top,
# and the global chat in a column on the right. Click someone who's playing
# to watch them.
#
# The list comes from the server (LobbyManager: online_players, about once a
# second while the window is open); watching goes through
# LobbyManager.spectate_player. Settings > Online > Allow Spectators is the
# other side: off, nobody can watch you. Made by Sidebar.gd.

const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const ACCENT_HOVER = Color(0.913725, 0.74902, 0.94902)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)
const FAINT = Color(0.62, 0.6, 0.68, 0.5)
const PLAYING = Color(0.55, 0.9, 0.65)
const WINDOW_BG = Color(0.055, 0.05, 0.075, 0.97)
const SECTION_BG = Color(0.075, 0.07, 0.1, 1)
const CARD_BG = Color(0.11, 0.105, 0.14, 1)
const CARD_HOVER = Color(0.15, 0.135, 0.19, 1)
const FIELD_BG = Color(0.13, 0.125, 0.165, 1)
const BTN_BG = Color(0.1, 0.095, 0.125, 1)
const BTN_HOVER = Color(0.14, 0.13, 0.18, 1)
const HEART = Color(1, 0.45, 0.62)
const MAX_IMG_CACHE = 160
const CHAT_MAX_LINES = 200
const DEVICE_NAMES = {"pc": "PC", "vr": "PC VR", "quest": "Quest", "mobile": "Phone", "web": "Browser"}
# the game's difficulties (Globals.DIFF_EASY = 0 ... 4); -1 = none set
const DIFF_NAMES = ["Easy", "Medium", "Hard", "Logic", "Tasukete"]

var font_regular: DynamicFont
var font_bold: DynamicFont
var font_title: DynamicFont
var font_small: DynamicFont
var font_name: DynamicFont
var font_rank: DynamicFont
var font_initial: DynamicFont
var font_chat: DynamicFont
var font_chat_bold: DynamicFont

var eye: Control
var overlay: Control
var window: Panel
var header: Label
var search: LineEdit
var fav_filter: Button
var info: Label
var scroll: ScrollContainer
var grid: GridContainer
var chat_panel: PanelContainer
var chat: RichTextLabel
var chat_input: LineEdit
var chat_send: Button
var chat_muted: Label

var _lm = null
var _open := false
var _k := 1.0 # size scale for this screen
var _cards := {} # player number -> {card, refs...}
var _list: Array = []
var _you: int = -1
var _img_cache := {} # url -> texture
var _img_order := []
var _img_waiting := {} # url -> [TextureRect]
var _pending_number := -1
var _pending_t := 0.0
var _chat_lines := 0
var _cw := 0.0 # a card's width

# ------------------------------------------------------------------ helpers

func _font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return f

func _flat(bg: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s

func _pad(sb: StyleBoxFlat, h: float, v: float) -> StyleBoxFlat:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb

func _label(text: String, font: Font, color: Color = TEXT) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", font)
	l.add_color_override("font_color", color)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l

func _style_button(b: Button, accent: bool = false):
	b.focus_mode = FOCUS_NONE
	b.add_font_override("font", font_bold)
	var dark := Color(0.1, 0.07, 0.12)
	b.add_color_override("font_color", dark if accent else TEXT)
	b.add_color_override("font_color_hover", dark if accent else TEXT)
	b.add_color_override("font_color_pressed", dark if accent else TEXT)
	b.add_stylebox_override("normal", _pad(_flat(LILAC if accent else BTN_BG, 8), 16, 6))
	b.add_stylebox_override("hover", _pad(_flat(ACCENT_HOVER if accent else BTN_HOVER, 8), 16, 6))
	b.add_stylebox_override("pressed", _pad(_flat(ACCENT if accent else BTN_HOVER, 8), 16, 6))
	b.add_stylebox_override("disabled", _pad(_flat(Color(0.09, 0.085, 0.11, 1), 8), 16, 6))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())

func _style_field(e: LineEdit):
	e.add_font_override("font", font_regular)
	e.add_color_override("font_color", TEXT)
	e.add_color_override("font_color_uneditable", DIM)
	e.add_stylebox_override("normal", _pad(_flat(FIELD_BG, 8), 14, 8))
	e.add_stylebox_override("focus", _pad(_flat(FIELD_BG, 8, LILAC, 1), 14, 8))
	e.add_stylebox_override("read_only", _pad(_flat(FIELD_BG, 8), 14, 8))

# text cut to fit a width, with "…" (centred labels clip both ends)
static func _fit(text: String, font: Font, width: float) -> String:
	if width <= 0 or font.get_string_size(text).x <= width:
		return text
	var lo := 0
	var hi := text.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if font.get_string_size(text.substr(0, mid) + "…").x <= width:
			lo = mid
		else:
			hi = mid - 1
	return text.substr(0, lo).strip_edges() + "…"

static func _fmt_dur(s: int) -> String:
	if s < 60:
		return "just now"
	if s < 3600:
		return "%d:%02d" % [s / 60, s % 60]
	return "%dh %02dm" % [s / 3600, (s % 3600) / 60]

static func _name_color(name: String) -> Color:
	return Color.from_hsv(fmod(abs(hash(name)) / 1000.0, 1.0), 0.45, 0.9)

# A heart, drawn (fonts may not have one): filled, or an outline
class HeartIcon extends Control:
	var filled := false
	var color := Color(1, 1, 1)
	func _init():
		mouse_filter = MOUSE_FILTER_IGNORE
	func _draw():
		var s: float = min(rect_size.x, rect_size.y)
		var o := (rect_size - Vector2(s, s)) / 2.0
		var pts := PoolVector2Array()
		for i in range(48):
			var t := TAU * i / 48.0
			# the classic heart curve, scaled into the box
			var x := 16.0 * pow(sin(t), 3)
			var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
			pts.append(o + Vector2(s * 0.5 + x * s / 36.0, s * 0.47 + y * s / 36.0))
		if filled:
			draw_colored_polygon(pts, color)
		else:
			pts.append(pts[0])
			draw_polyline(pts, color, max(1.5, s / 11.0), true)

# The eye button, drawn (smooth at any size): a dark glass circle with a
# lilac ring and eye, a soft shadow, glowing while pointed at
class EyeButton extends Control:
	signal pressed
	const RING = Color(0.764706, 0.65098, 0.8)
	const RING_HOVER = Color(1, 0.756863, 0.960784)
	var hover := false
	var down := false
	var _bg := StyleBoxFlat.new()
	var _dot := StyleBoxFlat.new()

	func _init():
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		_bg.anti_aliasing = true
		_dot.anti_aliasing = true
		connect("mouse_entered", self, "_set_hover", [true])
		connect("mouse_exited", self, "_set_hover", [false])

	func _set_hover(on: bool):
		hover = on
		if not on:
			down = false
		update()

	func _gui_input(ev):
		if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
			if ev.pressed:
				down = true
				update()
			elif down:
				down = false
				update()
				if Rect2(Vector2(), rect_size).has_point(ev.position):
					emit_signal("pressed")
			accept_event()

	func _circle(c: Vector2, r: float, col: Color):
		_dot.bg_color = col
		_dot.set_corner_radius_all(int(ceil(r)))
		draw_style_box(_dot, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))

	func _draw():
		var s: float = min(rect_size.x, rect_size.y) * (0.94 if down else 1.0)
		var c := rect_size / 2.0
		var r := s / 2.0
		var ring := RING_HOVER if hover else RING
		# glass circle, ring and shadow (a lilac glow while pointed at)
		_bg.bg_color = Color(0.11, 0.095, 0.15, 0.96) if hover else Color(0.075, 0.065, 0.1, 0.94)
		_bg.set_corner_radius_all(int(ceil(r)))
		_bg.border_color = ring
		_bg.set_border_width_all(int(max(2, round(s * 0.045))))
		_bg.shadow_color = Color(ring.r, ring.g, ring.b, 0.35) if hover else Color(0, 0, 0, 0.5)
		_bg.shadow_size = int(max(4, s * (0.22 if hover else 0.16)))
		_bg.shadow_offset = Vector2(0, 0 if hover else s * 0.04)
		draw_style_box(_bg, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
		# the eye: an almond outline, iris, pupil and a glint
		var w := r * 0.56
		var h := r * 0.34
		var pts := PoolVector2Array()
		var n := 24
		for i in range(n + 1):
			var t := float(i) / n
			pts.append(c + Vector2((t * 2.0 - 1.0) * w, -sin(PI * t) * h))
		for i in range(n - 1, 0, -1):
			var t := float(i) / n
			pts.append(c + Vector2((t * 2.0 - 1.0) * w, sin(PI * t) * h))
		pts.append(pts[0])
		draw_polyline(pts, ring, max(1.5, s * 0.055), true)
		_circle(c, r * 0.21, ring)
		_circle(c, r * 0.095, Color(0.075, 0.065, 0.1))
		_circle(c + Vector2(r * 0.07, -r * 0.07), r * 0.04, Color(1, 1, 1, 0.9))

# ------------------------------------------------------------------ build

func _ready():
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_lm = get_node_or_null("/root/LobbyManager")
	font_regular = _font("res://assets/font/Lato/Lato-Regular.ttf", 15)
	font_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 15)
	font_title = _font("res://assets/font/Lato/Lato-Black.ttf", 20)
	font_small = _font("res://assets/font/Lato/Lato-Bold.ttf", 13)
	font_name = _font("res://assets/font/Lato/Lato-Black.ttf", 17)
	font_rank = _font("res://assets/font/Lato/Lato-Black.ttf", 26)
	font_initial = _font("res://assets/font/Lato/Lato-Black.ttf", 20)
	font_chat = _font("res://assets/font/Lato/Lato-Regular.ttf", 15)
	font_chat_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 15)
	_build_eye()
	_build_window()
	get_viewport().connect("size_changed", self, "_resize")
	_resize()
	set_process(true)

func _build_eye():
	eye = EyeButton.new()
	eye.name = "SpectateButton"
	eye.hint_tooltip = "Spectate: who's online, and the global chat"
	eye.connect("pressed", self, "open")
	add_child(eye)

func _build_window():
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.visible = false
	add_child(overlay)
	# the menu dims behind it; clicking there closes it
	var dim := ColorRect.new()
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0, 0, 0, 0.55)
	dim.connect("gui_input", self, "_on_dim_input")
	overlay.add_child(dim)

	window = Panel.new()
	window.add_stylebox_override("panel", _flat(WINDOW_BG, 14, Color(1, 1, 1, 0.07), 1))
	overlay.add_child(window)
	var root := VBoxContainer.new()
	root.name = "Root"
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.add_constant_override("separation", 12)
	window.add_child(root)

	# header: title and count, search, favourites filter, close
	var head := HBoxContainer.new()
	head.add_constant_override("separation", 10)
	root.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_constant_override("separation", 0)
	titles.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(titles)
	titles.add_child(_label("Spectate", font_title, TEXT))
	header = _label("Connecting...", font_small, DIM)
	titles.add_child(header)
	var gap := Control.new()
	gap.rect_min_size = Vector2(12, 0)
	head.add_child(gap)
	search = LineEdit.new()
	search.placeholder_text = "Search players or maps..."
	search.size_flags_horizontal = SIZE_EXPAND_FILL
	search.size_flags_vertical = SIZE_SHRINK_CENTER
	search.clear_button_enabled = true
	_style_field(search)
	search.connect("text_changed", self, "_on_filter_changed")
	head.add_child(search)
	fav_filter = Button.new()
	fav_filter.toggle_mode = true
	fav_filter.focus_mode = FOCUS_NONE
	fav_filter.size_flags_vertical = SIZE_SHRINK_CENTER
	fav_filter.hint_tooltip = "Only your favourites (heart someone on their card)"
	fav_filter.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	fav_filter.add_stylebox_override("normal", _flat(FIELD_BG, 8))
	fav_filter.add_stylebox_override("hover", _flat(BTN_HOVER, 8))
	fav_filter.add_stylebox_override("pressed", _flat(FIELD_BG, 8, HEART, 1))
	fav_filter.add_stylebox_override("hover_pressed", _flat(BTN_HOVER, 8, HEART, 1))
	fav_filter.add_stylebox_override("focus", StyleBoxEmpty.new())
	var fh := HeartIcon.new()
	fh.name = "Heart"
	fh.anchor_right = 1.0
	fh.anchor_bottom = 1.0
	fh.margin_left = 9
	fh.margin_top = 9
	fh.margin_right = -9
	fh.margin_bottom = -9
	fh.color = DIM
	fav_filter.add_child(fh)
	fav_filter.connect("toggled", self, "_on_fav_filter")
	head.add_child(fav_filter)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = FOCUS_NONE
	close.size_flags_vertical = SIZE_SHRINK_CENTER
	close.hint_tooltip = "Close (Esc)"
	close.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	close.add_font_override("font", font_rank)
	close.add_color_override("font_color", DIM)
	close.add_color_override("font_color_hover", TEXT)
	close.add_color_override("font_color_pressed", ACCENT)
	close.connect("pressed", self, "close")
	head.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_constant_override("separation", 12)
	root.add_child(body)

	# players: square cards
	var players := PanelContainer.new()
	players.size_flags_horizontal = SIZE_EXPAND_FILL
	players.add_stylebox_override("panel", _pad(_flat(SECTION_BG, 12), 12, 12))
	body.add_child(players)
	var pv := VBoxContainer.new()
	pv.add_constant_override("separation", 10)
	players.add_child(pv)
	info = _label("", font_bold, DIM)
	info.autowrap = true
	info.visible = false
	pv.add_child(info)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	pv.add_child(scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_constant_override("hseparation", 10)
	grid.add_constant_override("vseparation", 10)
	scroll.add_child(grid)
	scroll.connect("resized", self, "_relayout")

	# the global chat, a column on the right
	chat_panel = PanelContainer.new()
	chat_panel.add_stylebox_override("panel", _pad(_flat(SECTION_BG, 12), 14, 12))
	body.add_child(chat_panel)
	var cv := VBoxContainer.new()
	cv.add_constant_override("separation", 8)
	chat_panel.add_child(cv)
	cv.add_child(_label("Global chat", font_bold, TEXT))
	chat = RichTextLabel.new()
	chat.size_flags_vertical = SIZE_EXPAND_FILL
	chat.scroll_following = true
	chat.selection_enabled = true
	chat.add_font_override("normal_font", font_chat)
	chat.add_font_override("bold_font", font_chat_bold)
	chat.add_color_override("default_color", TEXT)
	cv.add_child(chat)
	chat_muted = _label("Global chat is muted (Settings > Online).", font_small, DIM)
	chat_muted.autowrap = true
	chat_muted.visible = false
	cv.add_child(chat_muted)
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 8)
	cv.add_child(row)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Write a message..."
	chat_input.size_flags_horizontal = SIZE_EXPAND_FILL
	chat_input.max_length = 300
	_style_field(chat_input)
	chat_input.connect("text_entered", self, "_on_chat_entered")
	row.add_child(chat_input)
	chat_send = Button.new()
	chat_send.text = "Send"
	_style_button(chat_send, true)
	chat_send.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	chat_send.connect("pressed", self, "_send_chat")
	row.add_child(chat_send)

func _resize():
	var vp := get_viewport_rect().size
	_k = clamp(vp.y / 820.0, 0.9, 1.8)
	if Rhythia.device("mobile"):
		_k = max(_k, 1.15)
	font_regular.size = int(16 * _k)
	font_bold.size = int(16 * _k)
	font_title.size = int(21 * _k)
	font_small.size = int(14 * _k)
	font_name.size = int(18 * _k)
	font_rank.size = int(28 * _k)
	font_initial.size = int(21 * _k)
	font_chat.size = int(16 * _k)
	font_chat_bold.size = int(16 * _k)
	# the eye: bottom right, clear of the edges
	var d := 46.0 * _k
	var m := 20.0 * _k
	eye.rect_size = Vector2(d, d)
	eye.rect_position = vp - Vector2(d + m, d + m)
	eye.update()
	# the window: most of the screen
	var mx: float = max(16.0, vp.x * 0.045)
	var my: float = max(12.0, vp.y * 0.035)
	window.rect_position = Vector2(mx, my)
	window.rect_size = vp - Vector2(mx, my) * 2.0
	var root = window.get_node("Root")
	var p := 18.0 * _k
	root.margin_left = p
	root.margin_top = p * 0.8
	root.margin_right = -p
	root.margin_bottom = -p
	fav_filter.rect_min_size = Vector2(38, 38) * _k
	chat_panel.rect_min_size.x = clamp(window.rect_size.x * 0.3, 260, 520)
	_relayout()

# the button hides where it would cover something (the map editor's own
# controls sit in that corner) or while the window is open
func _process(delta):
	var editor = get_node_or_null("../../../Main/MapEditor")
	var show_eye: bool = not _open and not (editor != null and editor.visible and editor.get("ed") != null and editor.ed != null and editor.ed.is_visible_in_tree())
	if eye.visible != show_eye:
		eye.visible = show_eye
	if _pending_number != -1:
		_pending_t -= delta
		if _pending_t <= 0.0 or (_lm != null and _lm.watch_mode):
			_pending_number = -1
			_refresh_buttons()

func _input(ev):
	if _open and ev is InputEventKey and ev.pressed and not ev.echo and ev.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()

func _on_dim_input(ev):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		close()

# ------------------------------------------------------------------ open / close

func open():
	if _open:
		return
	_open = true
	overlay.visible = true
	_resize()
	if _lm != null:
		if not _lm.is_connected("online_players_received", self, "_on_list"):
			_lm.connect("online_players_received", self, "_on_list")
			_lm.connect("spectate_denied", self, "_on_denied")
			_lm.connect("presence_support_changed", self, "_on_support")
			_lm.connect("global_chat_message_received", self, "_on_chat_message")
		_lm.subscribe_online()
		if not _lm.online_players.empty():
			_on_list(_lm.online_players, _lm.my_player_number)
	_fill_chat()
	_update_info()

func close():
	if not _open:
		return
	_open = false
	overlay.visible = false
	if chat_input.has_focus():
		chat_input.release_focus()
	if search.has_focus():
		search.release_focus()
	if _lm != null and not _lm.watch_mode:
		_lm.unsubscribe_online()

func is_open() -> bool:
	return _open

# ------------------------------------------------------------------ list

func _on_support(_supported):
	_update_info()

func _update_info():
	if info == null or _lm == null:
		return
	var text := ""
	if _lm.presence_supported == 0:
		text = "This server doesn't have the Spectate list yet: it needs Savia server 2.1 or newer."
	elif not _lm._connected() or _lm.presence_supported == -1:
		text = "Connecting to the server..."
	elif _list.empty():
		text = "Nobody else is online right now."
	elif fav_filter.pressed and grid.get_child_count() == 0:
		text = "None of your favourites are online. Heart someone on their card to add them."
	elif not Rhythia.allow_spectators:
		text = "Spectators are off for you (Settings > Online), so nobody can watch you."
	info.text = text
	info.visible = text != ""

func _on_list(lst: Array, you: int):
	_list = lst
	_you = you
	var playing := 0
	for p in lst:
		if p is Dictionary and String(p.get("status", "")) == "playing":
			playing += 1
	header.text = "%d online   ·   %d playing" % [lst.size(), playing]
	_rebuild()
	_update_info()

func _on_filter_changed(_v = null):
	_rebuild()
	_update_info()

func _on_fav_filter(on: bool):
	fav_filter.get_node("Heart").filled = on
	fav_filter.get_node("Heart").color = HEART if on else DIM
	fav_filter.get_node("Heart").update()
	_on_filter_changed()

func _is_fav(n: int) -> bool:
	return Rhythia.spectate_favorites.has(n)

func _matches(p: Dictionary) -> bool:
	if fav_filter.pressed and not _is_fav(int(p.get("number", -1))):
		return false
	var q := search.text.strip_edges().to_lower()
	if q == "":
		return true
	return String(p.get("name", "")).to_lower().find(q) != -1 or String(p.get("song_name", "")).to_lower().find(q) != -1

func _relayout():
	if grid == null:
		return
	var w: float = scroll.rect_size.x - 12
	var min_w := 168.0 * _k
	grid.columns = int(clamp(floor((w + 10) / (min_w + 10)), 1, 8))
	var cw: float = floor((w - 10 * (grid.columns - 1)) / grid.columns)
	var refit: bool = cw != _cw
	_cw = cw
	for c in grid.get_children():
		c.rect_min_size = Vector2(cw, cw)
		c.rect_size = Vector2(cw, cw)
	if refit:
		for n in _cards:
			_card_style(_cards[n])

func _rebuild():
	if grid == null:
		return
	var keep := {}
	var order := []
	# you, then favourites, then the server's order (playing first, then by name)
	var you := []
	var favs := []
	var rest := []
	for p in _list:
		if not (p is Dictionary) or not _matches(p):
			continue
		var n := int(p.get("number", -1))
		if n == _you:
			you.append(p)
		elif _is_fav(n):
			favs.append(p)
		else:
			rest.append(p)
	for p in you + favs + rest:
		var n := int(p.get("number", -1))
		keep[n] = true
		var c = _cards.get(n)
		if c == null:
			c = _make_card()
			_cards[n] = c
			grid.add_child(c.card)
		_fill_card(c, p)
		order.append(c.card)
	for n in _cards.keys():
		if not keep.has(n):
			_cards[n].card.queue_free()
			_cards.erase(n)
	for i in range(order.size()):
		grid.move_child(order[i], i)
	_relayout()

# a square card: heart and device in the top corners, the picture, name,
# what they're doing, and their leaderboard place
func _make_card() -> Dictionary:
	var card := PanelContainer.new()
	card.mouse_filter = MOUSE_FILTER_STOP
	var box := Control.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(box)
	var v := VBoxContainer.new()
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.alignment = BoxContainer.ALIGN_CENTER
	v.add_constant_override("separation", int(4 * _k))
	v.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(v)
	var av := Control.new()
	av.rect_min_size = Vector2(64, 64) * _k
	av.size_flags_horizontal = SIZE_SHRINK_CENTER
	av.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(av)
	var circle := Panel.new()
	circle.anchor_right = 1.0
	circle.anchor_bottom = 1.0
	circle.mouse_filter = MOUSE_FILTER_IGNORE
	av.add_child(circle)
	var initial = _label("", font_initial, Color(0.1, 0.07, 0.12))
	initial.anchor_right = 1.0
	initial.anchor_bottom = 1.0
	initial.align = Label.ALIGN_CENTER
	initial.valign = Label.VALIGN_CENTER
	av.add_child(initial)
	var pic := TextureRect.new()
	pic.anchor_right = 1.0
	pic.anchor_bottom = 1.0
	pic.expand = true
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	pic.visible = false
	av.add_child(pic)
	var gap := Control.new()
	gap.rect_min_size = Vector2(0, 2 * _k)
	gap.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(gap)
	var name_l = _label("", font_name, TEXT)
	name_l.align = Label.ALIGN_CENTER
	name_l.clip_text = true
	v.add_child(name_l)
	var tag = _label("", font_small, ACCENT)
	tag.align = Label.ALIGN_CENTER
	v.add_child(tag)
	var status_l = _label("", font_small, DIM)
	status_l.align = Label.ALIGN_CENTER
	status_l.clip_text = true
	v.add_child(status_l)
	var rank_l = _label("", font_rank, FAINT)
	rank_l.align = Label.ALIGN_CENTER
	v.add_child(rank_l)

	var heart := Button.new()
	heart.flat = true
	heart.focus_mode = FOCUS_NONE
	heart.rect_size = Vector2(26, 26) * _k
	heart.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	var hi := HeartIcon.new()
	hi.anchor_right = 1.0
	hi.anchor_bottom = 1.0
	hi.margin_left = 3
	hi.margin_top = 3
	hi.margin_right = -3
	hi.margin_bottom = -3
	heart.add_child(hi)
	box.add_child(heart)

	var device := _label("", font_small, DIM)
	device.anchor_left = 1.0
	device.anchor_right = 1.0
	device.grow_horizontal = GROW_DIRECTION_BEGIN
	device.add_stylebox_override("normal", _pad(_flat(FIELD_BG, 6), 7 * _k, 2 * _k))
	box.add_child(device)

	var c := {"card": card, "circle": circle, "initial": initial, "pic": pic, "name": name_l, "tag": tag,
		"status": status_l, "heart": heart, "heart_icon": hi, "rank": rank_l, "device": device, "url": "", "number": -1,
		"can": false, "anyway": false, "nm": "", "rank_text": "", "hover": false, "is_you": false,
		"name_full": "", "status_full": ""}
	card.connect("gui_input", self, "_on_card_input", [c])
	card.connect("mouse_entered", self, "_on_card_hover", [c, true])
	card.connect("mouse_exited", self, "_on_card_hover", [c, false])
	heart.connect("pressed", self, "_on_heart", [c])
	return c

func _card_style(c: Dictionary):
	var lit: bool = c.hover and c.can
	var border := ACCENT if c.is_you else (LILAC if lit else Color(1, 1, 1, 0.04))
	var sb := _pad(_flat(CARD_HOVER if lit else CARD_BG, 12, border, 2 if (c.is_you or lit) else 1), 10 * _k, 10 * _k)
	c.card.add_stylebox_override("panel", sb)
	c.card.mouse_default_cursor_shape = CURSOR_POINTING_HAND if c.can else CURSOR_ARROW
	var fav := _is_fav(int(c.number))
	c.heart_icon.filled = fav
	c.heart_icon.color = HEART if fav else Color(DIM.r, DIM.g, DIM.b, 0.8)
	c.heart_icon.update()
	# the heart shows on a favourite, or while you point at the card
	c.heart.visible = not c.is_you and (fav or c.hover)
	var tw := _cw - 22.0 * _k
	c.name.text = _fit(c.name_full, font_name, tw)
	c.status.text = _fit(c.status_full, font_small, tw)
	var joining := _pending_number == int(c.number)
	if joining or lit:
		c.rank.text = "Joining..." if joining else ("Spectate anyway" if c.anyway else "Spectate")
		c.rank.add_font_override("font", font_bold)
		c.rank.add_color_override("font_color", ACCENT)
	else:
		c.rank.text = c.rank_text if c.rank_text != "" else "Unranked"
		c.rank.add_font_override("font", font_rank if c.rank_text != "" else font_small)
		c.rank.add_color_override("font_color", FAINT)

func _fill_card(c: Dictionary, p: Dictionary):
	var n := int(p.get("number", -1))
	c.number = n
	c.is_you = n == _you
	var nm := String(p.get("name", ""))
	if nm == "":
		nm = "Player #%d" % n
	c.nm = nm
	c.name_full = nm + ("  (you)" if c.is_you else "")
	var tag_text := String(p.get("tag_text", ""))
	c.tag.visible = tag_text != ""
	if tag_text != "":
		c.tag.text = tag_text
		var tc := String(p.get("tag_color", ""))
		c.tag.add_color_override("font_color", Color(tc) if tc.is_valid_html_color() else ACCENT)
	# their place on the leaderboard (SP), not the player number
	var rank = p.get("rank", null)
	c.rank_text = ("#%d" % int(rank)) if (typeof(rank) == TYPE_INT or typeof(rank) == TYPE_REAL) and int(rank) > 0 else ""
	# picture: their Discord avatar, else a coloured circle with the first letter
	var av_size: float = c.circle.get_parent().rect_min_size.x
	c.circle.add_stylebox_override("panel", _flat(_name_color(nm), int(av_size / 2)))
	c.initial.text = nm.substr(0, 1).to_upper()
	var url := String(p.get("avatar_url", ""))
	if url != c.url:
		c.url = url
		c.pic.visible = false
		if url.begins_with("https://"):
			_load_avatar(url, c.pic)
	# what they're doing
	var status := String(p.get("status", ""))
	var playing := status == "playing"
	var song := String(p.get("song_name", ""))
	if playing:
		c.status_full = "Playing " + (song if song != "" else "a map")
		c.status.add_color_override("font_color", PLAYING)
	elif status == "afk" or status == "away":
		c.status_full = "AFK"
		c.status.add_color_override("font_color", DIM)
	else:
		c.status_full = "Idle" if status == "menu" or status == "" else status.capitalize()
		c.status.add_color_override("font_color", DIM)
	c.device.text = DEVICE_NAMES.get(String(p.get("device", "pc")), "PC")
	# the rest in a tooltip
	var tip := [nm]
	tip.append("%s  ·  %s" % [c.rank_text if c.rank_text != "" else "Unranked", DEVICE_NAMES.get(String(p.get("device", "pc")), "PC")])
	if playing:
		var bits := [_fmt_dur(int(p.get("since_s", 0)))]
		var creator := String(p.get("song_creator", ""))
		if creator != "":
			bits.append("mapped by " + creator)
		var d := int(p.get("difficulty", -1))
		if d >= 0 and d < DIFF_NAMES.size():
			bits.append(DIFF_NAMES[d])
		tip.append((song if song != "" else "a map") + "  (" + PoolStringArray(bits).join(", ") + ")")
	if bool(p.get("in_lobby", false)):
		tip.append("In a lobby (%d players)" % int(p.get("lobby_size", 1)))
	var w := int(p.get("watchers", 0))
	if w > 0:
		tip.append("%d watching" % w)
	if playing and not bool(p.get("allow_spectate", true)) and not c.is_you:
		tip.append("Spectators off")
	if c.is_you and not Rhythia.allow_spectators:
		tip.append("Your spectators are off (Settings > Online)")
	# watching: someone playing who allows it (the server checks again); staff
	# can watch someone with spectators off too ("Spectate anyway")
	c.anyway = not bool(p.get("can_spectate", false)) and _lm != null and _lm.i_am_staff and bool(p.get("can_spectate_staff", false))
	c.can = (bool(p.get("can_spectate", false)) or c.anyway) and not c.is_you
	if c.can:
		tip.append("Click to spectate")
	c.card.hint_tooltip = PoolStringArray(tip).join("\n")
	_card_style(c)

func _on_card_hover(c: Dictionary, on: bool):
	c.hover = on
	_card_style(c)

func _on_card_input(ev, c: Dictionary):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT and c.can:
		_spectate(c)

func _on_heart(c: Dictionary):
	var n := int(c.number)
	if n < 0:
		return
	if _is_fav(n):
		Rhythia.spectate_favorites.erase(n)
	else:
		Rhythia.spectate_favorites.append(n)
	Rhythia.save_settings()
	_card_style(c)
	if fav_filter.pressed:
		_rebuild()

func _refresh_buttons():
	for n in _cards.keys():
		_card_style(_cards[n])

func _spectate(c: Dictionary):
	if _lm == null or _pending_number != -1:
		return
	var n := int(c.number)
	if n < 0:
		return
	if _lm.spectate_player(n):
		_pending_number = n
		_pending_t = 15.0
		_refresh_buttons()
		Globals.notify(Globals.NOTIFY_INFO, "Getting %s's map and play ready..." % c.nm, "Spectating")

func _on_denied(reason: String):
	_pending_number = -1
	_refresh_buttons()
	Globals.notify(Globals.NOTIFY_WARN, reason, "Can't spectate")

# ------------------------------------------------------------------ global chat

func _fill_chat():
	chat.clear()
	_chat_lines = 0
	var muted: bool = Rhythia.mute_global_chat
	chat_muted.visible = muted
	chat.visible = not muted
	chat_input.editable = not muted
	chat_send.disabled = muted
	if muted or _lm == null:
		return
	if _lm.global_chat_history.empty():
		chat.push_color(DIM)
		chat.add_text("No messages yet. Say hi!")
		chat.pop()
		_chat_lines = -1 # (the hint goes when the first message comes)
		return
	for e in _lm.global_chat_history:
		_add_chat_line(String(e.get("client_id", "")), String(e.get("name", "")), String(e.get("text", "")), float(e.get("ts", 0)))

func _on_chat_message(client_id: String, name: String, text: String, ts: float):
	if not _open or Rhythia.mute_global_chat:
		return
	if _chat_lines == -1:
		chat.clear()
		_chat_lines = 0
	_add_chat_line(client_id, name, text, ts)

static func _clock(ts: float) -> String:
	var t := int(ts / 1000.0) if ts > 100000000000.0 else int(ts)
	if t <= 0:
		t = OS.get_unix_time()
	t += int(OS.get_time_zone_info().get("bias", 0)) * 60
	var d := OS.get_datetime_from_unix_time(t)
	return "%02d:%02d" % [int(d.hour), int(d.minute)]

func _add_chat_line(client_id: String, name: String, text: String, ts: float):
	if _chat_lines > 0:
		chat.newline()
	chat.push_color(FAINT)
	chat.add_text(_clock(ts) + "  ")
	chat.pop()
	var is_you := client_id != "" and client_id == Rhythia.cid
	chat.push_font(font_chat_bold)
	chat.push_color(ACCENT if is_you else _name_color(name))
	chat.add_text(name + ": ")
	chat.pop()
	chat.pop()
	# @mentions stand out (yours most)
	var my_name := String(_lm.player_name).to_lower() if _lm != null else ""
	var words := text.split(" ")
	for i in range(words.size()):
		var w: String = words[i]
		var sep := " " if i < words.size() - 1 else ""
		if w.begins_with("@") and w.length() > 1:
			var me := my_name != "" and w.substr(1).to_lower().rstrip(".,!?:;") == my_name
			chat.push_font(font_chat_bold)
			chat.push_color(HEART if me else LILAC)
			chat.add_text(w)
			chat.pop()
			chat.pop()
			chat.add_text(sep)
		else:
			chat.add_text(w + sep)
	_chat_lines += 1
	if _chat_lines > CHAT_MAX_LINES:
		chat.remove_line(0)
		_chat_lines -= 1

func _on_chat_entered(_t: String):
	_send_chat()

func _send_chat():
	if _lm == null or Rhythia.mute_global_chat:
		return
	var text := chat_input.text.strip_edges()
	if text == "":
		return
	_lm.send_global_chat_message(text)
	chat_input.text = ""
	chat_input.grab_focus()

# ------------------------------------------------------------------ avatars

func _load_avatar(url: String, pic: TextureRect):
	if _img_cache.has(url):
		pic.texture = _img_cache[url]
		pic.visible = true
		return
	if _img_waiting.has(url):
		_img_waiting[url].append(pic)
		return
	_img_waiting[url] = [pic]
	var r = HTTPRequest.new()
	r.timeout = 15
	r.use_threads = OS.can_use_threads()
	add_child(r)
	r.connect("request_completed", self, "_on_avatar", [r, url])
	if r.request(url) != OK:
		r.queue_free()
		_img_waiting.erase(url)

func _on_avatar(result: int, code: int, _headers, data: PoolByteArray, r: HTTPRequest, url: String):
	r.queue_free()
	var waiting: Array = _img_waiting.get(url, [])
	_img_waiting.erase(url)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or data.empty():
		return
	var img := Image.new()
	var err := img.load_png_from_buffer(data)
	if err != OK:
		err = img.load_jpg_from_buffer(data)
	if err != OK:
		err = img.load_webp_from_buffer(data)
	if err != OK:
		return
	# a round picture
	var s := 96
	img.resize(s, s, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGBA8)
	img.lock()
	var rr := s / 2.0
	for y in range(s):
		for x in range(s):
			var dist := Vector2(x + 0.5 - rr, y + 0.5 - rr).length()
			if dist > rr:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif dist > rr - 1.0:
				var c := img.get_pixel(x, y)
				c.a *= rr - dist
				img.set_pixel(x, y, c)
	img.unlock()
	var tex := ImageTexture.new()
	tex.create_from_image(img)
	_img_cache[url] = tex
	_img_order.append(url)
	while _img_order.size() > MAX_IMG_CACHE:
		_img_cache.erase(_img_order.pop_front())
	for pic in waiting:
		if is_instance_valid(pic):
			pic.texture = tex
			pic.visible = true
