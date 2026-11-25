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

const AnimPic = preload("res://scripts/ui/AnimPic.gd")
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const ACCENT_HOVER = Color(0.913725, 0.74902, 0.94902)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)
const FAINT = Color(0.62, 0.6, 0.68, 0.5)
const PLAYING = Color(0.55, 0.9, 0.65)
const WINDOW_BG = Color(0.035, 0.03, 0.05, 0.985)
const SECTION_BG = Color(1, 1, 1, 0.025)
const CARD_BG = Color(0.075, 0.068, 0.1, 1)
const CARD_HOVER = Color(0.11, 0.1, 0.145, 1)
const FIELD_BG = Color(0.13, 0.125, 0.165, 1)
const BTN_BG = Color(0.1, 0.095, 0.125, 1)
const BTN_HOVER = Color(0.14, 0.13, 0.18, 1)
const HEART = Color(1, 0.45, 0.62)
const PINK = Color(0.96, 0.6, 0.78) # section headings (like the profile page)
const RULE = Color(1, 1, 1, 0.16)
const MAX_IMG_CACHE = 160
const CHAT_MAX_LINES = 200
const DEVICE_NAMES = {"pc": "PC", "vr": "VR", "quest": "VR", "mobile": "Phone", "web": "Browser"}
# the game's difficulties (Globals.DIFF_EASY = 0 ... 4); -1 = none set
const DIFF_NAMES = ["Easy", "Medium", "Hard", "Logic", "Tasukete"]

var font_regular: DynamicFont
var font_bold: DynamicFont
var font_title: DynamicFont
var font_small: DynamicFont
var font_tiny: DynamicFont
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
var grid: Control # (the cards are placed in it by hand: _show_visible)
var chat_panel: PanelContainer
var chat: RichTextLabel
var chat_input: LineEdit
var chat_send: Button
var chat_muted: Label
var chat_row: HBoxContainer
# the chat's channels
var _chat_tab := "global" # "global", "dms", "news"
var _chat_tabs := {}
var _dm_with := 0 # the conversation open in DMs (0: the list)
var dm_head: HBoxContainer
var dm_title: Label
var dm_view: VBoxContainer
var dm_find: LineEdit
var dm_scroll: ScrollContainer
var dm_box: VBoxContainer
var _dm_found_q := ""
var _dm_found := []
var _news_new := false
var _notice_dm := 0 # the notice by the eye is a direct message from them

var _lm = null
var _open := false
var _k := 1.0 # size scale for this screen
var _cards := {} # player number -> {card, refs...}
# Only the cards on screen (and a row above and below) exist and are kept up to
# date: with a few hundred people online, everyone else is a line in _order
# and nothing more until they are scrolled to. The cards are all one size, so
# each one's place follows from its number in the order (no container).
var _order := [] # everyone shown, in order: {p, card (null until on screen), ...}
var _seen := [] # the ones on screen
var _cols := 1
var _more := false # cards on screen still to be made (a few a frame)
var _gen := 0 # (which list a card was last in)
const GAP := 10.0 # between cards
const BUILD_USEC := 4000 # making cards stops for this frame after this long
var _styles := {} # the cards' panel looks, shared between cards that look the same
var _list: Array = []
var _you: int = -1
var _img_cache := {} # url -> texture
var _img_order := []
var _img_waiting := {} # url -> [TextureRect]
var _pending_number := -1
var _pending_t := 0.0
var _chat_lines := 0
var _cw := 0.0 # a card's width
var _eye_px := 0
var _heart_on: Texture
var _heart_off: Texture
var _heart_filter_off: Texture

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
	b.add_stylebox_override("normal", _pad(_flat(LILAC if accent else BTN_BG, 3), 16, 6))
	b.add_stylebox_override("hover", _pad(_flat(ACCENT_HOVER if accent else BTN_HOVER, 3), 16, 6))
	b.add_stylebox_override("pressed", _pad(_flat(ACCENT if accent else BTN_HOVER, 3), 16, 6))
	b.add_stylebox_override("disabled", _pad(_flat(Color(0.09, 0.085, 0.11, 1), 3), 16, 6))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())

# a thin lilac scrollbar instead of the theme's
func _style_scroll(bar: ScrollBar):
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.04)
	track.set_corner_radius_all(2)
	track.content_margin_left = 3
	track.content_margin_right = 3
	var grab := _flat(Color(LILAC.r, LILAC.g, LILAC.b, 0.45), 2)
	var grab_hi := _flat(Color(LILAC.r, LILAC.g, LILAC.b, 0.75), 2)
	bar.add_stylebox_override("scroll", track)
	bar.add_stylebox_override("scroll_focus", track)
	bar.add_stylebox_override("grabber", grab)
	bar.add_stylebox_override("grabber_highlight", grab_hi)
	bar.add_stylebox_override("grabber_pressed", grab_hi)
	bar.rect_min_size.x = 8

func _style_field(e: LineEdit):
	e.add_font_override("font", font_regular)
	e.add_color_override("font_color", TEXT)
	e.add_color_override("font_color_uneditable", DIM)
	e.add_stylebox_override("normal", _pad(_flat(FIELD_BG, 3), 14, 8))
	e.add_stylebox_override("focus", _pad(_flat(FIELD_BG, 3, LILAC, 1), 14, 8))
	e.add_stylebox_override("read_only", _pad(_flat(FIELD_BG, 3), 14, 8))

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

# ------------------------------------------------------------------ icons
# Drawn into textures from distance fields (each pixel's coverage worked out,
# so edges are smooth), made at twice the size they're shown and filtered
# down: sharp at any scale, never jagged.

static func _cov(d: float) -> float:
	return clamp(0.5 - d, 0.0, 1.0)

static func _over(dst: Color, src: Color, a: float) -> Color:
	var sa := src.a * a
	var oa := sa + dst.a * (1.0 - sa)
	if oa <= 0.0:
		return Color(0, 0, 0, 0)
	var c := (Color(src.r, src.g, src.b) * sa + Color(dst.r, dst.g, dst.b) * dst.a * (1.0 - sa)) / oa
	return Color(c.r, c.g, c.b, oa)

static func _to_tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	var tex := ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	return tex

static func _tex_cache() -> Dictionary:
	if not Engine.has_meta("spectate_tex_cache"):
		Engine.set_meta("spectate_tex_cache", {})
	return Engine.get_meta("spectate_tex_cache")

# heart (Inigo Quilez's heart distance), filled or as an outline
static func heart_texture(px: int, filled: bool, col: Color) -> ImageTexture:
	# (drawn pixel by pixel: once per size and colour, then kept)
	var key := "heart_texture|" + str([px, filled, col])
	var c: Dictionary = _tex_cache()
	if not c.has(key):
		c[key] = _heart_texture_make(px, filled, col)
	return c[key]

static func _heart_texture_make(px: int, filled: bool, col: Color) -> ImageTexture:
	var img := Image.new()
	img.create(px, px, false, Image.FORMAT_RGBA8)
	img.lock()
	var sc := px * 0.78
	var stroke := px * 0.075
	for y in range(px):
		for x in range(px):
			var q := Vector2((x + 0.5 - px * 0.5) / sc, (px * 0.86 - (y + 0.5)) / sc)
			q.x = abs(q.x)
			var d: float
			if q.y + q.x > 1.0:
				d = q.distance_to(Vector2(0.25, 0.75)) - sqrt(2.0) / 4.0
			else:
				var m := 0.5 * max(q.x + q.y, 0.0)
				d = sqrt(min(q.distance_squared_to(Vector2(0, 1)), q.distance_squared_to(Vector2(m, m)))) * sign(q.x - q.y)
			d *= sc
			var a := _cov(d) if filled else _cov(abs(d + stroke * 0.5) - stroke * 0.5)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	img.unlock()
	return _to_tex(img)

# the eye button: a dark circle with a thin ring, an eye outline and pupil
static func eye_texture(px: int, ring: Color) -> ImageTexture:
	# (drawn pixel by pixel: once per size and colour, then kept)
	var key := "eye_texture|" + str([px, ring])
	var c: Dictionary = _tex_cache()
	if not c.has(key):
		c[key] = _eye_texture_make(px, ring)
	return c[key]

static func _eye_texture_make(px: int, ring: Color) -> ImageTexture:
	var img := Image.new()
	img.create(px, px, false, Image.FORMAT_RGBA8)
	img.lock()
	var c := Vector2(px, px) * 0.5
	var R := px * 0.5 - 1.0
	var ring_w := max(1.5, px * 0.035)
	# the eye: a horizontal almond (vesica) of half-length L and half-height H
	var L := R * 0.52
	var H := R * 0.29
	var vr := (L * L / H + H) * 0.5
	var vd := (L * L / H - H) * 0.5
	var eye_w := max(1.5, px * 0.045)
	var bg := Color(0.07, 0.062, 0.095, 0.96)
	for y in range(px):
		for x in range(px):
			var p := Vector2(x + 0.5, y + 0.5) - c
			var dc := p.length() - R
			var col := Color(0, 0, 0, 0)
			col = _over(col, bg, _cov(dc))
			col = _over(col, ring, _cov(abs(dc + ring_w * 0.5) - ring_w * 0.5))
			# vesica distance (along y), with x and y swapped so it lies flat
			var q := Vector2(abs(p.y), abs(p.x))
			var dv: float
			if (q.y - L) * vd > q.x * L:
				dv = q.distance_to(Vector2(0, L))
			else:
				dv = q.distance_to(Vector2(-vd, 0)) - vr
			col = _over(col, ring, _cov(abs(dv) - eye_w * 0.5))
			col = _over(col, ring, _cov(p.length() - R * 0.15))
			img.set_pixel(x, y, col)
	img.unlock()
	return _to_tex(img)

# The eye button: the drawn texture, brighter while pointed at. Held and
# moved, it goes where it's dragged (mouse, finger or VR pointer); a click
# that doesn't move opens the window; a right click puts it back in its corner.
class EyeButton extends TextureRect:
	signal pressed
	signal dragged(to) # being moved: where its top left corner should be (on the screen)
	signal dropped
	signal put_back
	var down := false
	var dragging := false
	var _grab := Vector2()
	var _from := Vector2()
	var tex_normal: Texture
	var tex_hover: Texture

	func _init():
		expand = true
		stretch_mode = STRETCH_SCALE
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		mouse_filter = MOUSE_FILTER_STOP
		connect("mouse_entered", self, "_set_hover", [true])
		connect("mouse_exited", self, "_set_hover", [false])

	func _set_hover(on: bool):
		if dragging:
			return # (the pointer got ahead of the button for a moment)
		texture = tex_hover if on else tex_normal
		if not on and not down:
			rect_scale = Vector2(1, 1)

	func _gui_input(ev):
		if ev is InputEventMouseButton and ev.button_index == BUTTON_RIGHT:
			if ev.pressed and not down:
				emit_signal("put_back")
			accept_event()
		elif ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
			rect_pivot_offset = rect_size / 2.0
			if ev.pressed:
				down = true
				dragging = false
				_grab = ev.position
				_from = ev.global_position
				rect_scale = Vector2(0.94, 0.94)
			elif down:
				down = false
				rect_scale = Vector2(1, 1)
				if dragging:
					dragging = false
					emit_signal("dropped")
					if not Rect2(Vector2(), rect_size).has_point(ev.position):
						texture = tex_normal
				elif Rect2(Vector2(), rect_size).has_point(ev.position):
					emit_signal("pressed")
				else:
					texture = tex_normal
			accept_event()
		elif ev is InputEventMouseMotion and down:
			# (a click's small wobble isn't a move: a fifth of the button first)
			if not dragging and ev.global_position.distance_to(_from) > max(8.0, rect_size.x * 0.2):
				dragging = true
				rect_scale = Vector2(1, 1)
			if dragging:
				emit_signal("dragged", ev.global_position - _grab)
			accept_event()

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
	font_tiny = _font("res://assets/font/Lato/Lato-Bold.ttf", 11)
	font_name = _font("res://assets/font/Lato/Lato-Black.ttf", 17)
	font_rank = _font("res://assets/font/Lato/Lato-Black.ttf", 26)
	font_initial = _font("res://assets/font/Lato/Lato-Black.ttf", 20)
	font_chat = _font("res://assets/font/Lato/Lato-Regular.ttf", 15)
	font_chat_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 15)
	_heart_on = heart_texture(48, true, HEART)
	_heart_off = heart_texture(48, false, Color(DIM.r, DIM.g, DIM.b, 0.85))
	_heart_filter_off = heart_texture(48, false, DIM)
	_build_eye()
	_build_notice()
	_build_window()
	if _lm != null:
		_lm.connect("global_chat_message_received", self, "_on_chat_message")
		_lm.connect("chat_ban_changed", self, "_on_chat_ban")
		if _lm.has_signal("chat_reactions_changed"):
			_lm.connect("chat_reactions_changed", self, "_on_chat_reactions")
		if _lm.has_signal("chat_message_deleted"):
			_lm.connect("chat_message_deleted", self, "_on_chat_deleted")
		if _lm.has_signal("blocked_changed"):
			_lm.connect("blocked_changed", self, "_on_chat_deleted", [""]) # (drawn again: folded or unfolded)
		if _lm.has_signal("dm_message"):
			_lm.connect("dm_message", self, "_on_dm_message")
			_lm.connect("dm_list_changed", self, "_on_dm_changed")
			_lm.connect("dm_history_loaded", self, "_on_dm_history")
			_lm.connect("players_found", self, "_on_players_found")
			_lm.connect("announcements_changed", self, "_on_news_changed")
			_lm.connect("social_changed", self, "_on_dm_changed")
	add_to_group("spectate_page")
	get_viewport().connect("size_changed", self, "_resize")
	_resize()
	set_process(true)
	get_tree().create_timer(1.5).connect("timeout", self, "_prewarm")

func _build_eye():
	eye = EyeButton.new()
	eye.name = "SpectateButton"
	eye.hint_tooltip = "Spectate and chat\nDrag it to move it, right-click to put it back in its corner"
	eye.connect("pressed", self, "open")
	eye.connect("dragged", self, "_on_eye_dragged")
	eye.connect("dropped", self, "_on_eye_dropped")
	eye.connect("put_back", self, "_on_eye_put_back")
	add_child(eye)
	_eye_at = _load_eye_place()

# --- the eye goes where it's dragged ------------------------------------------------
# Kept as its centre's share of the screen (0..1 each way), so it stays in the
# same spot of a bigger or smaller window; null = its corner (bottom right).
const EYE_CFG := "user://settings.cfg"
var _eye_at = null

func _load_eye_place():
	var config := ConfigFile.new()
	if config.load(EYE_CFG) != OK:
		return null
	var v = config.get_value("ui", "spectate_eye", null)
	return v if v is Vector2 else null

func _save_eye_place():
	var config := ConfigFile.new()
	config.load(EYE_CFG)
	if _eye_at == null:
		if config.has_section_key("ui", "spectate_eye"):
			config.erase_section_key("ui", "spectate_eye")
	else:
		config.set_value("ui", "spectate_eye", _eye_at)
	config.save(EYE_CFG)

# (always whole on the screen)
func _eye_clamped(pos: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var edge := 4.0 * _k
	return Vector2(clamp(pos.x, edge, max(edge, vp.x - eye.rect_size.x - edge)), clamp(pos.y, edge, max(edge, vp.y - eye.rect_size.y - edge))).floor()

func _on_eye_dragged(to: Vector2):
	eye.rect_position = _eye_clamped(to - rect_global_position)
	notice.visible = false
	_place_notice()

func _on_eye_dropped():
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		return
	_eye_at = (eye.rect_position + eye.rect_size / 2.0) / vp
	_save_eye_place()

func _on_eye_put_back():
	if _eye_at == null:
		return
	_eye_at = null
	_save_eye_place()
	_resize()

# ------------------------------------------------------------------ chat notification
# A new global chat message while the window is closed: a small bubble left
# of the eye ("name: text", for a few seconds) and an unread count on the eye.
# Settings > Online > Chat Notifications turns it off.
const NOTICE_TIME := 6.0
var notice: PanelContainer
var notice_name: Label
var notice_text: Label
var badge: Label
var _unread := 0
var _notice_tween: Tween

func _build_notice():
	notice = PanelContainer.new()
	notice.visible = false
	notice.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	notice.add_stylebox_override("panel", _pad(_flat(Color(0.07, 0.062, 0.095, 0.97), 3, Color(1, 1, 1, 0.12), 1), 12, 8))
	notice.connect("gui_input", self, "_on_notice_input")
	add_child(notice)
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 6)
	h.mouse_filter = MOUSE_FILTER_IGNORE
	notice.add_child(h)
	notice_name = _label("", font_bold, LILAC)
	h.add_child(notice_name)
	notice_text = _label("", font_regular, TEXT)
	h.add_child(notice_text)
	badge = _label("", font_tiny, Color(0.1, 0.07, 0.12))
	badge.align = Label.ALIGN_CENTER
	badge.valign = Label.VALIGN_CENTER
	badge.add_stylebox_override("normal", _pad(_flat(PINK, 2), 4, 1))
	badge.visible = false
	add_child(badge)
	_notice_tween = Tween.new()
	add_child(_notice_tween)

func _notify_chat(client_id: String, name: String, text: String):
	if not Rhythia.spectate_chat_notify or (client_id != "" and client_id == Rhythia.cid):
		return
	if _lm != null and _lm.has_method("is_blocked_chat") and _lm.is_blocked_chat(String(_lm.get("last_chat_id"))):
		return # (someone you blocked)
	_unread += 1
	_notice_dm = 0
	_badge_text()
	_place_notice()
	if not eye.visible:
		return
	var max_w := 300.0 * _k
	notice_name.text = _fit(name, font_bold, max_w * 0.4) + ":"
	text = preload("res://scripts/ui/ChatCommands.gd").plain(text)
	notice_text.text = _fit(text, font_regular, max_w - font_bold.get_string_size(notice_name.text).x)
	notice.rect_size = Vector2()
	notice.visible = true
	_place_notice()
	call_deferred("_place_notice") # (once the labels have their new sizes)
	_notice_tween.remove_all()
	notice.modulate.a = 0.0
	_notice_tween.interpolate_property(notice, "modulate:a", 0.0, 1.0, 0.18, Tween.TRANS_SINE, Tween.EASE_OUT)
	_notice_tween.interpolate_property(notice, "modulate:a", 1.0, 0.0, 0.4, Tween.TRANS_SINE, Tween.EASE_IN, NOTICE_TIME)
	_notice_tween.interpolate_callback(self, NOTICE_TIME + 0.4, "_hide_notice")
	_notice_tween.start()

func _hide_notice():
	notice.visible = false

func _clear_notice():
	_unread = 0
	badge.visible = false
	_notice_tween.remove_all()
	notice.visible = false

func _place_notice():
	if notice == null:
		return
	var sz := notice.get_combined_minimum_size()
	notice.rect_size = sz
	var nx: float = eye.rect_position.x - sz.x - 10 * _k
	if nx < 4.0:
		nx = eye.rect_position.x + eye.rect_size.x + 10 * _k # (the eye is at the left edge: the message goes on its right)
	var ny: float = clamp(eye.rect_position.y + (eye.rect_size.y - sz.y) / 2.0, 0.0, max(0.0, get_viewport_rect().size.y - sz.y))
	notice.rect_position = Vector2(nx, ny).floor()
	var bs := badge.get_combined_minimum_size()
	bs.x = max(bs.x, bs.y)
	badge.rect_size = bs
	badge.rect_position = (eye.rect_position + Vector2(eye.rect_size.x - bs.x * 0.75, -bs.y * 0.25)).floor()

func _on_notice_input(ev):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		if _notice_dm > 0:
			open_dm(_notice_dm)
		else:
			open()

func _dm_unread() -> int:
	return int(_lm.dm_unread_total) if _lm != null and _lm.get("dm_unread_total") != null else 0

func _badge_text():
	var n := _unread + _dm_unread()
	badge.text = str(n) if n < 100 else "99+"

func _build_window():
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.visible = false
	add_child(overlay)
	# the menu dims behind it; clicking there closes it
	var dim := ColorRect.new()
	dim.add_to_group("wheel_blocker") # (the map list behind it does not scroll: Savia.wheel_blocked)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0, 0, 0, 0.55)
	dim.connect("gui_input", self, "_on_dim_input")
	overlay.add_child(dim)

	window = Panel.new()
	window.add_stylebox_override("panel", _flat(WINDOW_BG, 4, Color(1, 1, 1, 0.07), 1))
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
	fav_filter.hint_tooltip = "Only your favorites (heart someone on their card)"
	fav_filter.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	fav_filter.add_stylebox_override("normal", _flat(FIELD_BG, 3))
	fav_filter.add_stylebox_override("hover", _flat(BTN_HOVER, 3))
	fav_filter.add_stylebox_override("pressed", _flat(FIELD_BG, 3, HEART, 1))
	fav_filter.add_stylebox_override("hover_pressed", _flat(BTN_HOVER, 3, HEART, 1))
	fav_filter.add_stylebox_override("focus", StyleBoxEmpty.new())
	var fh := TextureRect.new()
	fh.name = "Heart"
	fh.texture = _heart_filter_off
	fh.expand = true
	fh.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fh.mouse_filter = MOUSE_FILTER_IGNORE
	fh.anchor_right = 1.0
	fh.anchor_bottom = 1.0
	fh.margin_left = 9
	fh.margin_top = 9
	fh.margin_right = -9
	fh.margin_bottom = -9
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

	var rule := ColorRect.new()
	rule.color = RULE
	rule.rect_min_size = Vector2(0, 1)
	rule.mouse_filter = MOUSE_FILTER_IGNORE
	root.add_child(rule)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_constant_override("separation", 12)
	root.add_child(body)

	# players: square cards
	var players := PanelContainer.new()
	players.size_flags_horizontal = SIZE_EXPAND_FILL
	players.add_stylebox_override("panel", _pad(_flat(SECTION_BG, 3), 12, 12))
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
	grid = Control.new()
	grid.mouse_filter = MOUSE_FILTER_PASS
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(grid)
	scroll.connect("resized", self, "_relayout")
	scroll.get_v_scrollbar().connect("value_changed", self, "_on_scrolled")
	_style_scroll(scroll.get_v_scrollbar())

	# the global chat, a column on the right
	chat_panel = PanelContainer.new()
	chat_panel.add_stylebox_override("panel", _pad(_flat(SECTION_BG, 3), 14, 12))
	body.add_child(chat_panel)
	var cv := VBoxContainer.new()
	cv.add_constant_override("separation", 8)
	chat_panel.add_child(cv)
	# the chat's channels: Global (everyone), DMs (your friends), Announcements
	var tabs := HBoxContainer.new()
	tabs.add_constant_override("separation", 6)
	cv.add_child(tabs)
	for k in [["global", "Global"], ["dms", "DMs"], ["news", "Announcements"]]:
		var tb := Button.new()
		tb.text = k[1]
		tb.clip_text = true
		tb.size_flags_horizontal = SIZE_EXPAND_FILL
		tb.size_flags_stretch_ratio = 1.6 if k[0] == "news" else 1.0
		tb.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		tb.connect("pressed", self, "_pick_chat_tab", [k[0]])
		tabs.add_child(tb)
		_chat_tabs[k[0]] = tb
	# a conversation: back to the list, who it is with
	dm_head = HBoxContainer.new()
	dm_head.add_constant_override("separation", 8)
	dm_head.visible = false
	cv.add_child(dm_head)
	var back := Button.new()
	back.text = "< Back"
	_style_button(back)
	back.add_font_override("font", font_small)
	back.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	back.connect("pressed", self, "_dm_back")
	dm_head.add_child(back)
	dm_title = _label("", font_bold, TEXT)
	dm_title.clip_text = true
	dm_title.size_flags_horizontal = SIZE_EXPAND_FILL
	dm_head.add_child(dm_title)
	# the DMs list: add a friend, friend requests, your friends and conversations
	dm_view = VBoxContainer.new()
	dm_view.size_flags_vertical = SIZE_EXPAND_FILL
	dm_view.add_constant_override("separation", 8)
	dm_view.visible = false
	cv.add_child(dm_view)
	var find_row := HBoxContainer.new()
	find_row.add_constant_override("separation", 6)
	dm_view.add_child(find_row)
	dm_find = LineEdit.new()
	dm_find.placeholder_text = "Add a friend: name or #number"
	dm_find.size_flags_horizontal = SIZE_EXPAND_FILL
	dm_find.max_length = 64
	_style_field(dm_find)
	dm_find.connect("text_entered", self, "_dm_find_go")
	dm_find.connect("text_changed", self, "_dm_find_changed")
	find_row.add_child(dm_find)
	var find_btn := Button.new()
	find_btn.text = "Find"
	_style_button(find_btn, true)
	find_btn.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	find_btn.connect("pressed", self, "_dm_find_go", [""])
	find_row.add_child(find_btn)
	dm_scroll = ScrollContainer.new()
	dm_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	dm_scroll.scroll_horizontal_enabled = false
	_style_scroll(dm_scroll.get_v_scrollbar())
	dm_view.add_child(dm_scroll)
	dm_box = VBoxContainer.new()
	dm_box.size_flags_horizontal = SIZE_EXPAND_FILL
	dm_box.add_constant_override("separation", 6)
	dm_scroll.add_child(dm_box)
	chat = RichTextLabel.new()
	chat.size_flags_vertical = SIZE_EXPAND_FILL
	chat.scroll_following = true
	chat.selection_enabled = true
	chat.add_font_override("normal_font", font_chat)
	chat.add_font_override("bold_font", font_chat_bold)
	chat.add_color_override("default_color", TEXT)
	chat.add_constant_override("line_separation", 3)
	_style_scroll(chat.get_v_scroll())
	cv.add_child(chat)
	chat_muted = _label("Global chat is muted (Settings > Online).", font_small, DIM)
	chat_muted.autowrap = true
	chat_muted.visible = false
	cv.add_child(chat_muted)
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 8)
	cv.add_child(row)
	chat_row = row
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Write a message... (/help for commands)"
	chat_input.size_flags_horizontal = SIZE_EXPAND_FILL
	chat_input.max_length = 300
	_style_field(chat_input)
	preload("res://scripts/ui/Emoji.gd").field(chat_input) # (emoji show as you type)
	chat_input.connect("text_entered", self, "_on_chat_entered")
	row.add_child(chat_input)
	preload("res://scripts/ui/ChatMention.gd").attach(chat_input, _lm) # (@ + Tab: names)
	var emo: Button = preload("res://scripts/ui/ChatReactions.gd").picker_button(chat_input, int(20 * _k))
	_style_button(emo)
	emo.add_stylebox_override("normal", _pad(_flat(BTN_BG, 3), 8, 5))
	emo.add_stylebox_override("hover", _pad(_flat(BTN_HOVER, 3), 8, 5))
	emo.add_stylebox_override("pressed", _pad(_flat(BTN_HOVER, 3), 8, 5))
	emo.rect_min_size = Vector2(40, 34) * _k
	row.add_child(emo)
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
	font_small.size = int(13 * _k)
	font_tiny.size = int(11 * _k)
	font_name.size = int(16 * _k)
	font_rank.size = int(22 * _k)
	font_initial.size = int(18 * _k)
	font_chat.size = int(16 * _k)
	font_chat_bold.size = int(16 * _k)
	# the eye: bottom right, clear of the edges
	var d := 46.0 * _k
	var m := 20.0 * _k
	eye.rect_size = Vector2(d, d)
	eye.rect_position = vp - Vector2(d + m, d + m)
	if Rhythia.vr:
		# (the VR screen's resize handle is in that corner: the eye goes beside it)
		eye.rect_position.x -= load("res://vr/MenuResize.gd").ICON + 12.0
	if _eye_at is Vector2:
		eye.rect_position = _eye_clamped(_eye_at * vp - eye.rect_size / 2.0)
	var tpx := int(ceil(d * 2.0))
	if tpx != _eye_px:
		_eye_px = tpx
		eye.tex_normal = eye_texture(tpx, LILAC)
		eye.tex_hover = eye_texture(tpx, ACCENT)
		eye.texture = eye.tex_normal
	_place_notice()
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
	search.rect_min_size.y = fav_filter.rect_min_size.y # (same height as the heart)
	chat_panel.rect_min_size.x = clamp(window.rect_size.x * 0.3, 260, 520)
	_relayout()

# the button hides where it would cover something (the map editor's own
# controls sit in that corner) or while the window is open
func _process(delta):
	var editor = get_node_or_null("../../../Main/MapEditor")
	var show_eye: bool = not _open and not (editor != null and editor.visible and editor.get("ed") != null and editor.ed != null and editor.ed.is_visible_in_tree())
	if eye.visible != show_eye:
		eye.visible = show_eye
		if not show_eye:
			notice.visible = false
	badge.visible = show_eye and (_unread + _dm_unread()) > 0
	if _open:
		_prog_tick += delta
		if _prog_tick >= 0.5:
			_prog_tick = 0.0
			for c in _seen:
				if c.get("prog") is Dictionary:
					_draw_prog(c)
		if _more:
			_show_visible()
		if _late_list != null and OS.get_ticks_msec() - _list_at >= CROWD_GAP_MS:
			var late = _late_list
			_late_list = null
			_on_list(late[0], late[1])
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

# opening: the window rises a little, grows from 96.5% and fades in while the
# menu dims behind it; closing is the same backwards, quicker. To keep it
# smooth, the motion starts a frame after the window appears (that frame does
# the setup work) and the cards / chat are filled once it has finished (a list
# that comes in meanwhile waits). The window is drawn once, unseen, after the
# menu loads, so its text is ready the first time it opens.
const SLIDE_IN := 0.34
const SLIDE_OUT := 0.18
const RISE := 26.0
const FROM_SCALE := 0.965
var _tween: Tween
var _animating := false
var _held_list = null # [list, you] that came in while opening

func _slide(opening: bool):
	if _tween == null:
		_tween = Tween.new()
		add_child(_tween)
	_tween.remove_all()
	var home := window.rect_position
	var away := home + Vector2(0, RISE * _k)
	window.rect_pivot_offset = window.rect_size / 2.0
	var dim = overlay.get_child(0)
	if opening:
		window.rect_position = away
		window.rect_scale = Vector2.ONE * FROM_SCALE
		window.modulate.a = 0.0
		dim.modulate.a = 0.0
		_tween.interpolate_property(window, "rect_position", away, home, SLIDE_IN, Tween.TRANS_QUART, Tween.EASE_OUT)
		_tween.interpolate_property(window, "rect_scale", window.rect_scale, Vector2.ONE, SLIDE_IN, Tween.TRANS_QUART, Tween.EASE_OUT)
		_tween.interpolate_property(window, "modulate:a", 0.0, 1.0, SLIDE_IN * 0.7, Tween.TRANS_SINE, Tween.EASE_OUT)
		_tween.interpolate_property(dim, "modulate:a", 0.0, 1.0, SLIDE_IN * 0.8, Tween.TRANS_SINE, Tween.EASE_OUT)
		_tween.interpolate_callback(self, SLIDE_IN, "_opened")
	else:
		var to := window.rect_position + Vector2(0, RISE * 0.5 * _k)
		_tween.interpolate_property(window, "rect_position", window.rect_position, to, SLIDE_OUT, Tween.TRANS_QUAD, Tween.EASE_IN)
		_tween.interpolate_property(window, "rect_scale", window.rect_scale, Vector2.ONE * 0.985, SLIDE_OUT, Tween.TRANS_QUAD, Tween.EASE_IN)
		_tween.interpolate_property(window, "modulate:a", window.modulate.a, 0.0, SLIDE_OUT, Tween.TRANS_SINE, Tween.EASE_IN)
		_tween.interpolate_property(dim, "modulate:a", dim.modulate.a, 0.0, SLIDE_OUT, Tween.TRANS_SINE, Tween.EASE_IN)
		_tween.interpolate_callback(self, SLIDE_OUT, "_closed")
	_tween.start()

func _opened():
	_animating = false
	if not _open:
		return
	if _held_list != null:
		var h = _held_list
		_held_list = null
		_on_list(h[0], h[1])
	_fill_chat()
	_update_info()

func _closed():
	if not _open:
		overlay.visible = false
		window.rect_scale = Vector2.ONE
		_resize() # (back where it belongs for next time)

# drawn once, unseen, so the first open doesn't stop to make its text
func _prewarm():
	if _open or overlay == null:
		return
	overlay.visible = true
	window.modulate.a = 0.02
	overlay.get_child(0).modulate.a = 0.0
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	if not _open:
		overlay.visible = false
		window.modulate.a = 1.0
		overlay.get_child(0).modulate.a = 1.0

func open():
	if _open:
		return
	_open = true
	_animating = true
	overlay.visible = true
	_resize()
	window.modulate.a = 0.0 # (unseen until the motion starts next frame)
	overlay.get_child(0).modulate.a = 0.0
	_clear_notice()
	if _lm != null:
		if not _lm.is_connected("online_players_received", self, "_on_list"):
			_lm.connect("online_players_received", self, "_on_list")
			_lm.connect("spectate_denied", self, "_on_denied")
			_lm.connect("presence_support_changed", self, "_on_support")
		_lm.subscribe_online()
		if not _lm.online_players.empty():
			_held_list = [_lm.online_players, _lm.my_player_number]
	_update_info()
	# ready to type in the chat (not on phones: it would pop the keyboard up)
	if chat_input.editable and chat_input.is_visible_in_tree() and not Rhythia.device("mobile"):
		chat_input.call_deferred("grab_focus")
	yield(get_tree(), "idle_frame")
	if _open:
		_slide(true)

func close():
	if not _open:
		return
	_open = false
	_animating = false
	_held_list = null
	_slide(false)
	if chat_input.has_focus():
		chat_input.release_focus()
	if search.has_focus():
		search.release_focus()
	if _lm != null and _lm.get("dm_open_with") != null:
		_lm.dm_open_with = 0 # (a message that comes now is unread)
		_lm.dm_list_open = false
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
	elif fav_filter.pressed and _order.empty():
		text = "None of your favorites are online. Heart someone on their card to add them."
	elif not Rhythia.allow_spectators:
		text = "Spectators are off for you (Settings > Online), so nobody can watch you."
	info.text = text
	info.visible = text != ""

# With a crowd online, a headset or a phone takes a new list every other
# second (the server sends one a second): going through a few hundred people
# is a few milliseconds there, and the cards' progress lines move on by the
# clock in between anyway.
const CROWD := 100
const CROWD_GAP_MS := 2000
var _list_at := 0
var _late_list = null # [list, you]: one that came too soon after the last

func _on_list(lst: Array, you: int):
	if _animating:
		_held_list = [lst, you] # (after the opening motion)
		return
	var now := OS.get_ticks_msec()
	if lst.size() > CROWD and (Rhythia.vr or Rhythia.device("mobile")) and now - _list_at < CROWD_GAP_MS:
		_late_list = [lst, you]
		return
	_late_list = null
	_list_at = now
	_list = lst
	_you = you
	_rebuild()
	_update_info()

static func _rank_of(p: Dictionary) -> int:
	var r = p.get("rank", null)
	return int(r) if (typeof(r) == TYPE_INT or typeof(r) == TYPE_REAL) and int(r) > 0 else 1 << 30

func _by_rank(a: Dictionary, b: Dictionary) -> bool:
	var ra := _rank_of(a)
	var rb := _rank_of(b)
	if ra != rb:
		return ra < rb
	return String(a.get("name", "")).to_lower() < String(b.get("name", "")).to_lower()

func _on_filter_changed(_v = null):
	_rebuild()
	_update_info()

func _on_fav_filter(on: bool):
	fav_filter.get_node("Heart").texture = _heart_on if on else _heart_filter_off
	_on_filter_changed()

func _is_fav(n: int) -> bool:
	return Rhythia.spectate_favorites.has(n)

func _matches(p: Dictionary, q: String, favs: bool) -> bool:
	if favs and not _is_fav(int(p.get("number", -1))):
		return false
	if q == "":
		return true
	return String(p.get("name", "")).to_lower().find(q) != -1 or String(p.get("song_name", "")).to_lower().find(q) != -1

# (their place and name in small letters are worked out once for each, not at every comparison)
func _by_key(a: Dictionary, b: Dictionary) -> bool:
	if a.rk != b.rk:
		return a.rk < b.rk
	return a.low_name < b.low_name

func _by_key3(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return a[1] < b[1]

# square cards of one size (not stretched to the width)
const CARD_SIDE := 160.0
const CARD_EXTRA := 24.0 # (taller than wide: room for the progress line and bar)

func _relayout():
	if grid == null:
		return
	var w: float = scroll.rect_size.x - 12
	var side := floor(CARD_SIDE * _k)
	_cols = int(clamp(floor((w + GAP) / (side + GAP)), 1, 10))
	if side != _cw:
		_cw = side
		_styles.clear()
		for n in _cards:
			var c: Dictionary = _cards[n]
			c.filled = null # (their text is fitted to the new width when next on screen)
			c.sb = null
	_show_visible()

func _on_scrolled(_v = null):
	_show_visible()

const NO_RANK := 1 << 30
func _rebuild():
	if grid == null:
		return
	# in leaderboard order (SP rank; unranked players after, by name).
	# (Favourites don't jump to the front: cards moved under the pointer when hearted.)
	# One pass over everyone online, as little as possible for each: this runs
	# once a second with the whole list.
	var q := search.text.strip_edges().to_lower()
	var favs: bool = fav_filter.pressed
	var all: bool = q == "" and not favs
	_gen += 1
	var fresh := [] # the ones who weren't in the list before
	var n_shown := 0
	var playing := 0
	for p in _list:
		if not (p is Dictionary):
			continue
		if p.get("status") == "playing":
			playing += 1
		if not all and not _matches(p, q, favs):
			continue
		var n := int(p.get("number", -1))
		var c = _cards.get(n)
		if c == null:
			c = _new_card()
			_cards[n] = c
			fresh.append(c)
		c.p = p
		c.number = n
		c.gen = _gen
		# (what they are sorted by: their place, then their name)
		var r = p.get("rank")
		c.rk = int(r) if (typeof(r) == TYPE_INT or typeof(r) == TYPE_REAL) and r >= 1 else NO_RANK
		var nm = p.get("name", "")
		if nm != c.raw_name:
			c.raw_name = nm
			c.low_name = String(nm).to_lower()
		n_shown += 1
	var head := "%d online   ·   %d playing" % [_list.size(), playing]
	if header.text != head:
		header.text = head
	# whoever left (or is filtered out now) goes; the others keep their order
	var order := _order
	if order.size() + fresh.size() != n_shown:
		order = []
		for c in _order:
			if c.gen == _gen:
				order.append(c)
			else:
				if c.card != null:
					c.card.queue_free()
					c.card = null
				c.shown = false
				_cards.erase(c.number)
	# does that order still hold (most seconds it does)? Then the newcomers are
	# put in their places; else everyone is sorted again
	var holds := true
	for i in range(1, order.size()):
		var a: Dictionary = order[i - 1]
		var b: Dictionary = order[i]
		if a.rk > b.rk or (a.rk == b.rk and a.low_name > b.low_name):
			holds = false
			break
	if holds and fresh.size() <= 12:
		for c in fresh:
			var lo := 0
			var hi := order.size()
			while lo < hi:
				var mid := (lo + hi) / 2
				if _by_key(order[mid], c):
					lo = mid + 1
				else:
					hi = mid
			order.insert(lo, c)
	else:
		# (as [place, name, card]: quicker to compare than the cards themselves)
		var keys := []
		for c in _cards.values():
			keys.append([c.rk, c.low_name, c])
		keys.sort_custom(self, "_by_key3")
		order = []
		for k in keys:
			order.append(k[2])
	_order = order
	_show_visible()

# The cards on screen (and a row above and below) are made if they weren't yet
# (a few a frame), put in their place and brought up to date; the ones that
# left the screen are hidden.
func _show_visible():
	if grid == null:
		return
	var side := floor(CARD_SIDE * _k)
	var tall := floor((CARD_SIDE + CARD_EXTRA) * _k)
	var step := tall + GAP
	var rows := int(ceil(_order.size() / float(_cols)))
	var want := Vector2(_cols * (side + GAP) - GAP, max(0.0, rows * step - GAP))
	if grid.rect_min_size != want:
		grid.rect_min_size = want
	var top := float(scroll.scroll_vertical)
	var first := int(max(0.0, floor(top / step) - 1.0)) * _cols
	var last := int(min(_order.size(), (int(floor((top + scroll.rect_size.y) / step)) + 2) * _cols))
	var made := 0
	var t0 := OS.get_ticks_usec()
	_more = false
	var seen := []
	for i in range(first, last):
		var c: Dictionary = _order[i]
		if c.card == null:
			# (one at least, then as many as fit in a few milliseconds: fewer a frame on a slow device)
			if made > 0 and OS.get_ticks_usec() - t0 > BUILD_USEC:
				_more = true
				continue
			_make_card(c)
			made += 1
		var at := Vector2((i % _cols) * (side + GAP), (i / _cols) * step)
		if c.card.rect_position != at:
			c.card.rect_position = at
		if c.card.rect_size != Vector2(side, tall):
			c.card.rect_size = Vector2(side, tall)
		if not c.shown:
			c.shown = true
			c.card.visible = true
			c.filled = null
			c.sig = 0
		if c.filled != c.p:
			c.filled = c.p
			_fill_card(c, c.p)
		c.on = true
		seen.append(c)
	for c in _seen:
		if not c.on and c.shown:
			c.shown = false
			if c.card != null:
				c.card.visible = false
	for c in seen:
		c.on = false
	_seen = seen

# a card's panel look: one object for all the cards that look the same
func _panel_style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var key := "%s|%s|%d" % [bg.to_html(), border.to_html(), bw]
	var sb = _styles.get(key)
	if sb == null:
		if _styles.size() > 400:
			_styles.clear()
		sb = _pad(_flat(bg, 3, border, bw), 8 * _k, 8 * _k)
		_styles[key] = sb
	return sb

# someone in the list: no card yet (it is made when they are on screen: _make_card)
static func _new_card() -> Dictionary:
	return {"card": null, "built": false, "shown": false, "on": false, "gen": 0, "rk": 0, "raw_name": null, "low_name": "", "p": null, "filled": null, "sig": 0, "sb": null, "fx": "", "img_url": "", "frame_sig": "", "prog": null, "url": "", "number": -1,
		"can": false, "anyway": false, "nm": "", "rank_text": "", "hover": false, "is_you": false, "name_full": "", "status_full": ""}

func _make_card(c: Dictionary):
	var card := PanelContainer.new()
	card.mouse_filter = MOUSE_FILTER_STOP
	card.connect("gui_input", self, "_on_card_input", [c])
	card.connect("mouse_entered", self, "_on_card_hover", [c, true])
	card.connect("mouse_exited", self, "_on_card_hover", [c, false])
	c.card = card
	grid.add_child(card)
	_build_card(c)

# a square card: the role tag and device in the top corners, the picture,
# name, what they're doing and their leaderboard place, the heart bottom right
func _build_card(c: Dictionary):
	var card: PanelContainer = c.card
	var box := Control.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(box)
	# their card's own picture (profile > Cards, an admin's upload), behind
	# everything, dimmed so the text reads
	var bgimg := TextureRect.new()
	bgimg.anchor_right = 1.0
	bgimg.anchor_bottom = 1.0
	bgimg.margin_left = -6 * _k
	bgimg.margin_top = -6 * _k
	bgimg.margin_right = 6 * _k
	bgimg.margin_bottom = 6 * _k
	bgimg.expand = true
	bgimg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bgimg.mouse_filter = MOUSE_FILTER_IGNORE
	bgimg.modulate = Color(0.62, 0.62, 0.62)
	bgimg.visible = false
	box.add_child(bgimg)
	# a moving card (Supporter's hearts: CardFx.gd), over the picture, under
	# the text; it reaches the card's edge so its lights run along the border
	var cfx = load("res://scripts/ui/CardFx.gd").new()
	cfx.anchor_right = 1.0
	cfx.anchor_bottom = 1.0
	cfx.margin_left = -8 * _k
	cfx.margin_top = -8 * _k
	cfx.margin_right = 8 * _k
	cfx.margin_bottom = 8 * _k
	cfx.inset = 1.0
	cfx.visible = false
	box.add_child(cfx)
	var v := VBoxContainer.new()
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.margin_top = 12 * _k # (between the corner tags: the picture is in the middle)
	v.alignment = BoxContainer.ALIGN_CENTER
	v.add_constant_override("separation", int(2 * _k))
	v.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(v)
	var av := Control.new()
	av.rect_min_size = Vector2(48, 48) * _k
	av.size_flags_horizontal = SIZE_SHRINK_CENTER
	av.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(av)
	# (room under the picture for its frame: profile > Frames reaches about
	# 1.45 x its radius, so the name doesn't sit under the frame)
	var under := Control.new()
	under.rect_min_size = Vector2(0, 10) * _k
	under.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(under)
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
	# their frame round the picture (profile > Frames)
	var fv = load("res://scripts/ui/FrameView.gd").new()
	av.add_child(fv)
	var name_l = _label("", font_name, TEXT)
	name_l.align = Label.ALIGN_CENTER
	name_l.clip_text = true
	v.add_child(name_l)
	var status_l = _label("", font_small, DIM)
	status_l.align = Label.ALIGN_CENTER
	status_l.clip_text = true
	v.add_child(status_l)
	# while they play: the speed, how far in and the time left, and a bar
	var prog_l = _label(" ", font_tiny, DIM)
	prog_l.align = Label.ALIGN_CENTER
	prog_l.clip_text = true
	v.add_child(prog_l)
	var bar := ColorRect.new()
	bar.rect_min_size = Vector2(0, 3) * _k
	bar.color = Color(1, 1, 1, 0)
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(bar)
	var bar_fill := ColorRect.new()
	bar_fill.anchor_bottom = 1.0
	bar_fill.color = PLAYING
	bar_fill.mouse_filter = MOUSE_FILTER_IGNORE
	bar_fill.visible = false
	bar.add_child(bar_fill)
	var rank_l = _label("", font_rank, FAINT)
	rank_l.set_meta("no_outline", true) # (faint, with no outline round it: WaveMenuBG.gd)
	rank_l.align = Label.ALIGN_CENTER
	v.add_child(rank_l)

	# corners: role tag (staff) top left, device top right, heart bottom right
	var tag = _label("", font_tiny, ACCENT)
	tag.add_stylebox_override("normal", _pad(_flat(FIELD_BG, 2), 6 * _k, 2 * _k))
	box.add_child(tag)
	var device := _label("", font_tiny, DIM)
	device.anchor_left = 1.0
	device.anchor_right = 1.0
	device.grow_horizontal = GROW_DIRECTION_BEGIN
	device.add_stylebox_override("normal", _pad(_flat(FIELD_BG, 2), 6 * _k, 2 * _k))
	box.add_child(device)
	# (an icon, not a button: the card handles the click, so pointing at the
	# heart doesn't take the pointer away from the card)
	var heart := TextureRect.new()
	heart.expand = true
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.mouse_filter = MOUSE_FILTER_IGNORE
	heart.texture = _heart_off
	heart.anchor_left = 1.0
	heart.anchor_top = 1.0
	heart.anchor_right = 1.0
	heart.anchor_bottom = 1.0
	heart.margin_left = -20 * _k
	heart.margin_top = -20 * _k
	box.add_child(heart)

	# bottom left: "..." opens the menu (View stats, Spectate, their profile),
	# like right-clicking the card; a label, the card takes the click
	var dots := _label("•••", font_tiny, DIM) # (small: the "watching" line sits under it)
	dots.anchor_top = 1.0
	dots.anchor_bottom = 1.0
	dots.margin_left = 0
	dots.margin_right = 22 * _k
	dots.margin_top = -16 * _k
	dots.align = Label.ALIGN_CENTER
	dots.valign = Label.VALIGN_CENTER
	dots.mouse_filter = MOUSE_FILTER_IGNORE
	dots.hint_tooltip = "View stats, spectate, profile"
	box.add_child(dots)

	# the very bottom left: how many are watching them (hidden at 0); the
	# "..." moves up above it while it shows (_fill_card)
	var watching := _label("", font_tiny, DIM)
	watching.anchor_top = 1.0
	watching.anchor_bottom = 1.0
	watching.grow_vertical = GROW_DIRECTION_BEGIN
	watching.margin_left = 2 * _k
	watching.margin_bottom = 1 * _k
	watching.mouse_filter = MOUSE_FILTER_IGNORE
	watching.visible = false
	box.add_child(watching)

	# (player 6's game: see _card_alt)
	var alt := TextureRect.new()
	alt.anchor_right = 1.0
	alt.anchor_bottom = 1.0
	alt.margin_left = -8 * _k
	alt.margin_top = -8 * _k
	alt.margin_right = 8 * _k
	alt.margin_bottom = 8 * _k
	alt.expand = true
	alt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	alt.mouse_filter = MOUSE_FILTER_IGNORE
	alt.visible = false
	box.add_child(alt)

	var refs := {"box": box, "bgimg": bgimg, "cfx": cfx, "fv": fv, "dots": dots, "alt": alt, "circle": circle, "initial": initial, "pic": pic, "name": name_l, "tag": tag,
		"status": status_l, "prog_l": prog_l, "bar": bar, "bar_fill": bar_fill, "heart": heart, "rank": rank_l, "device": device, "watching": watching}
	for k in refs:
		c[k] = refs[k]
	c.built = true

# a card's picture (FrameImages.gd keeps it; it may still be coming)
func _card_img(c: Dictionary):
	var fi = load("res://scripts/ui/FrameImages.gd").instance()
	if not fi.is_connected("loaded", self, "_on_art_loaded"):
		fi.connect("loaded", self, "_on_art_loaded")
	var tex = fi.pic(c.img_url) if c.img_url != "" else null
	c.bgimg.texture = tex
	c.bgimg.visible = tex != null

func _on_art_loaded(url: String):
	for c in _cards.values():
		if c.built and c.img_url == url:
			_card_img(c)

# (a label's text or colour is only set when it changes: setting it again
# costs a redraw and a new layout of the card, every second for every card)
static func _text(l: Label, t: String):
	if l.text != t:
		l.text = t

static func _colour(c: Dictionary, key: String, l: Control, col: Color):
	if c.get(key) != col:
		c[key] = col
		l.add_color_override("font_color", col)

func _card_style(c: Dictionary):
	if not c.built:
		return
	var lit: bool = c.hover and c.can
	# (their card from profile > Cards: its background and border)
	var cbg = c.get("card_bg")
	var cbd = c.get("card_border")
	var base: Color = cbg if cbg is Color else CARD_BG
	var idle_border: Color = cbd if cbd is Color else Color(1, 1, 1, 0.04)
	var border := ACCENT if c.is_you else (LILAC if lit else idle_border)
	var wide: bool = c.is_you or lit or cbd is Color
	var sb := _panel_style(base.lightened(0.06) if lit else base, border, 2 if wide else 1)
	if c.sb != sb:
		c.sb = sb
		c.card.add_stylebox_override("panel", sb)
	c.card.mouse_default_cursor_shape = CURSOR_POINTING_HAND if c.can else CURSOR_ARROW
	var fav := _is_fav(int(c.number))
	var heart_tex := _heart_on if fav else _heart_off
	if c.heart.texture != heart_tex:
		c.heart.texture = heart_tex
	# the heart shows on a favourite, or while you point at the card
	c.heart.visible = not c.is_you and (fav or c.hover)
	_colour(c, "dots_col", c.dots, TEXT if c.hover else FAINT)
	var tw := _cw - 22.0 * _k
	var fit_key := "%s|%s|%d" % [c.name_full, c.status_full, int(tw)]
	if c.get("fit_key") != fit_key:
		c["fit_key"] = fit_key
		c.name.text = _fit(c.name_full, font_name, tw)
		c.status.text = _fit(c.status_full, font_small, tw)
	var rank_h := font_rank.get_height() # (no jump when it says Spectate)
	if c.rank.rect_min_size.y != rank_h:
		c.rank.rect_min_size.y = rank_h
	var joining := _pending_number == int(c.number)
	var rank_font: DynamicFont
	if joining or lit:
		_text(c.rank, "Joining..." if joining else ("Spectate anyway" if c.anyway else "Spectate"))
		rank_font = font_bold
		_colour(c, "rank_col", c.rank, ACCENT)
	else:
		_text(c.rank, c.rank_text if c.rank_text != "" else "Unranked")
		rank_font = font_rank if c.rank_text != "" else font_small
		_colour(c, "rank_col", c.rank, FAINT)
	if c.get("rank_font") != rank_font:
		c["rank_font"] = rank_font
		c.rank.add_font_override("font", rank_font)

# a card's progress line and bar, moved on by the clock between lists
static func _mmss(s: float) -> String:
	var t := int(max(s, 0.0))
	return "%d:%02d" % [t / 60, t % 60]

static func _speed_text(sp: float) -> String:
	var t := ("%.2f" % sp).rstrip("0").rstrip(".")
	return t + "x"

static func _prog_now(d: Dictionary) -> float:
	var pos: float = d.pos + (0.0 if d.paused else float(OS.get_ticks_msec() - int(d.t)) * d.speed)
	return min(pos, d.dur) if d.dur > 0 else pos

static func _prog_text(d: Dictionary, long: bool) -> String:
	var pos := _prog_now(d)
	var into := _mmss(max(pos, 0.0) / d.speed / 1000.0)
	var sp := _speed_text(d.speed)
	if d.dur <= 0:
		return "%s  ·  %s in" % [sp, into]
	var left := _mmss(max(d.dur - pos, 0.0) / d.speed / 1000.0)
	if d.paused:
		return ("%s  ·  Paused  ·  %s left" if long else "%s · Paused · %s") % [sp, left]
	return ("%s  ·  %s in  ·  %s left" if long else "%s · %s · -%s") % [sp, into, left]

func _draw_prog(c: Dictionary):
	if not c.built:
		return
	var d = c.get("prog")
	if not (d is Dictionary):
		_text(c.prog_l, " ")
		if c.bar.color.a != 0.0:
			c.bar.color = Color(1, 1, 1, 0)
		c.bar_fill.visible = false
		return
	var tw := _cw - 22.0 * _k
	var t := _prog_text(d, true)
	if font_tiny.get_string_size(t).x > tw:
		t = _prog_text(d, false)
	if c.get("prog_t") != t:
		c["prog_t"] = t
		c.prog_l.text = _fit(t, font_tiny, tw)
	_colour(c, "prog_col", c.prog_l, DIM if d.paused else PLAYING)
	if c.bar.color.a == 0.0:
		c.bar.color = Color(1, 1, 1, 0.08)
	c.bar_fill.visible = d.dur > 0
	if d.dur > 0:
		c.bar_fill.anchor_right = clamp(_prog_now(d) / d.dur, 0.0, 1.0)
		c.bar_fill.margin_right = 0

var _prog_tick := 0.0

# Player 6's game, one start in ten: every card is this picture for that session
const CARD_ALT_PLAYER := 6
func _card_alt() -> bool:
	if int(_you) != CARD_ALT_PLAYER:
		return false
	if not Engine.has_meta("card_alt"):
		randomize()
		Engine.set_meta("card_alt", randi() % 10 == 0)
	return bool(Engine.get_meta("card_alt"))

# what of a player's line the card shows, as one number: the card is only
# filled in again when it changes (not for how far into the map they are,
# which moves every second and has its own line)
func _sig(p: Dictionary) -> int:
	var q := p.duplicate()
	for k in ["pos_ms", "since_s", "len_ms", "speed", "paused"]:
		q.erase(k)
	return hash([q, _you, _cw, _lm != null and _lm.i_am_staff, Rhythia.allow_spectators, _pending_number == int(p.get("number", -1))])

func _fill_card(c: Dictionary, p: Dictionary):
	var status := String(p.get("status", ""))
	var playing := status == "playing"
	# how far into the map (newer servers: speed, pos_ms, len_ms, paused)
	c.prog = null
	if playing and p.has("pos_ms") and p.get("pos_ms") != null and float(p.get("speed", 0)) > 0:
		c.prog = {"pos": float(p.pos_ms), "dur": float(p.get("len_ms")) if p.get("len_ms") != null else 0.0,
			"speed": float(p.speed), "paused": bool(p.get("paused", false)), "t": OS.get_ticks_msec()}
	var sig := _sig(p)
	if sig == c.sig:
		_draw_prog(c)
		return
	c.sig = sig
	var cd = p.get("card")
	c["card_bg"] = Color(String(cd.get("bg", ""))) if cd is Dictionary and String(cd.get("bg", "")).is_valid_html_color() else null
	c["card_border"] = Color(String(cd.get("border", ""))) if cd is Dictionary and String(cd.get("border", "")).is_valid_html_color() else null
	var iu: String = String(cd.get("image_url", "")) if cd is Dictionary and cd.get("image_url") != null else ""
	if iu != c.img_url:
		c.img_url = iu
		_card_img(c)
	var fx: String = String(cd.get("fx", "")) if cd is Dictionary and cd.get("fx") != null else ""
	# (the effect takes the card's border colour: set again when either changes)
	var fx_sig: String = fx + "|" + (c.card_border.to_html() if c.card_border != null else "")
	if fx_sig != c.fx:
		c.fx = fx_sig
		c.cfx.set_fx(fx, c.card_border)
	var fsig := var2str(p.get("frame"))
	if fsig != c.frame_sig:
		c.frame_sig = fsig
		c.fv.set_frame(p.get("frame"))
	var n := int(p.get("number", -1))
	c.number = n
	c.is_you = n == _you
	var alt_on := _card_alt()
	c.alt.visible = alt_on
	if alt_on and c.alt.texture == null:
		c.alt.texture = load("res://assets/images/card_alt.png")
	var nm := String(p.get("name", ""))
	if nm == "":
		nm = "Player #%d" % n
	c.nm = nm
	c.name_full = nm + (" (you)" if c.is_you else "")
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
	if c.get("circle_nm") != nm:
		c["circle_nm"] = nm
		c.circle.add_stylebox_override("panel", _flat(_name_color(nm), int(av_size / 2)))
		c.initial.text = nm.substr(0, 1).to_upper()
	var url := AnimPic.pic_url(p) # (a moving GIF when they have one)
	if url != c.url:
		c.url = url
		c.pic.visible = false
		if url.begins_with("https://"):
			_load_avatar(url, c.pic)
	# what they're doing
	var song := String(p.get("song_name", ""))
	if playing:
		c.status_full = "Playing " + (song if song != "" else "a map") + ("  ·  Spin" if bool(p.get("spin", false)) else "")
		c.status.add_color_override("font_color", PLAYING)
	elif status == "afk" or status == "away":
		c.status_full = "AFK"
		c.status.add_color_override("font_color", DIM)
	else:
		c.status_full = "Idle" if status == "menu" or status == "" else status.capitalize()
		c.status.add_color_override("font_color", DIM)
	_draw_prog(c)
	var n_watch := int(p.get("watchers", 0))
	c.watching.visible = n_watch > 0
	c.watching.text = "%d watching" % n_watch
	# (the "..." just above the watching line, so they never overlap)
	c.dots.margin_bottom = -15 * _k if n_watch > 0 else 0.0
	c.dots.margin_top = c.dots.margin_bottom - 16 * _k
	c.device.text = DEVICE_NAMES.get(String(p.get("device", "pc")), "PC")
	# watching: someone playing who allows it (the server checks again); staff
	# can watch someone with spectators off too ("Spectate anyway")
	c.anyway = not bool(p.get("can_spectate", false)) and _lm != null and _lm.i_am_staff and bool(p.get("can_spectate_staff", false))
	c.can = (bool(p.get("can_spectate", false)) or c.anyway) and not c.is_you
	c.card.hint_tooltip = _card_tip(c, p)
	_card_style(c)

# the rest of what is known of them, for the tooltip (made again when the
# pointer comes to the card: it says how long they have been playing)
func _card_tip(c: Dictionary, p: Dictionary) -> String:
	var nm: String = c.nm
	var status := String(p.get("status", ""))
	var playing := status == "playing"
	var song := String(p.get("song_name", ""))
	var tip := [nm]
	tip.append("%s  ·  %s" % [c.rank_text if c.rank_text != "" else "Unranked", DEVICE_NAMES.get(String(p.get("device", "pc")), "PC")])
	if c.prog is Dictionary:
		tip.append(_prog_text(c.prog, true))
	if playing:
		var bits := [_fmt_dur(int(p.get("since_s", 0)))]
		var creator := String(p.get("song_creator", ""))
		if creator != "":
			bits.append("mapped by " + creator)
		var d := int(p.get("difficulty", -1))
		if d >= 0 and d < DIFF_NAMES.size():
			bits.append(DIFF_NAMES[d])
		if bool(p.get("spin", false)):
			bits.append("on Spin")
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
	if c.can:
		tip.append("Click to spectate")
	return PoolStringArray(tip).join("\n")

func _on_card_hover(c: Dictionary, on: bool):
	c.hover = on
	if not c.built:
		return
	if on and c.p is Dictionary:
		c.card.hint_tooltip = _card_tip(c, c.p)
	_card_style(c)

func _on_card_input(ev, c: Dictionary):
	if not c.built:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_RIGHT:
		_card_menu(c, ev.global_position)
		c.card.accept_event()
		return
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT):
		return
	# the "..." (bigger than it looks, so it's easy to hit): the card's menu
	if c.dots.get_global_rect().grow(5 * _k).has_point(ev.global_position):
		var r: Rect2 = c.dots.get_global_rect()
		_card_menu(c, Vector2(r.position.x, r.end.y))
		c.card.accept_event()
		return
	# the heart (a little bigger than it looks, so it's easy to hit)
	if not c.is_you and c.heart.get_global_rect().grow(6 * _k).has_point(ev.global_position):
		_on_heart(c)
		c.card.accept_event()
		return
	if c.can:
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
		_update_info()

func _refresh_buttons():
	for c in _seen:
		_card_style(c)

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

const GLOBAL_HINT := "Write a message... (/help for commands)"
func _fill_chat():
	if chat == null:
		return
	for k in _chat_tabs:
		var tb: Button = _chat_tabs[k]
		_style_button(tb, k == _chat_tab)
		tb.add_font_override("font", font_small)
		for sbn in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = tb.get_stylebox(sbn)
			sb.content_margin_left = 6
			sb.content_margin_right = 6
	_tab_titles()
	var listing: bool = _chat_tab == "dms" and _dm_with <= 0
	dm_view.visible = listing
	dm_head.visible = _chat_tab == "dms" and _dm_with > 0
	chat.visible = not listing
	chat_muted.visible = false
	chat_row.visible = _chat_tab == "global" or (_chat_tab == "dms" and _dm_with > 0)
	if _lm != null and _lm.get("dm_open_with") != null:
		_lm.dm_open_with = _dm_with if (_open and _chat_tab == "dms") else 0
		_lm.dm_list_open = _open and _chat_tab == "dms"
	if _chat_tab == "dms":
		if _dm_with > 0:
			_fill_dm_thread()
		else:
			_fill_dm_list()
	elif _chat_tab == "news":
		_fill_news()
	else:
		_fill_global()

func _tab_titles():
	if _chat_tabs.empty():
		return
	var n := _dm_unread()
	_chat_tabs["dms"].text = "DMs (%d)" % n if n > 0 else "DMs"
	_chat_tabs["news"].text = "Announcements *" if _news_new else "Announcements"

func _pick_chat_tab(k: String):
	if k == _chat_tab and not (k == "dms" and _dm_with > 0):
		return
	_chat_tab = k
	_dm_with = 0
	if k == "news":
		_news_new = false
	_fill_chat()
	if k == "dms" and _lm != null:
		_lm.request_dm_list() # (fresh: who's online, what's unread)
		_lm.refresh_social()

# ---- DMs: the list (add a friend, friend requests, friends and conversations)

func _dm_back():
	_dm_with = 0
	_fill_chat()

# from anywhere (the Friends window's Message, the notice by the eye)
func open_dm(number: int):
	if number <= 0:
		return
	_chat_tab = "dms"
	_dm_with = number
	if _open:
		_fill_chat()
		if chat_input.editable and not Rhythia.device("mobile"):
			chat_input.call_deferred("grab_focus")
	else:
		open()

func _dm_note(text: String):
	var l := _label(text, font_small, DIM)
	l.autowrap = true
	dm_box.add_child(l)

func _dm_heading(text: String):
	var l := _label(text, font_small, PINK)
	dm_box.add_child(l)

func _dm_person_row(name: String, sub: String, online, unread: int) -> HBoxContainer:
	var card := PanelContainer.new()
	card.add_stylebox_override("panel", _pad(_flat(CARD_BG, 3), 10, 7))
	dm_box.add_child(card)
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 8)
	card.add_child(h)
	if online != null:
		var dot := _label("●", font_small, PLAYING if online else FAINT)
		dot.hint_tooltip = "Online" if online else "Offline"
		dot.mouse_filter = MOUSE_FILTER_IGNORE
		h.add_child(dot)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_constant_override("separation", 0)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	h.add_child(v)
	var l := _label(name, font_bold, TEXT)
	l.clip_text = true
	l.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(l)
	if sub != "":
		var s := _label(sub, font_small, TEXT if unread > 0 else DIM)
		s.clip_text = true
		s.mouse_filter = MOUSE_FILTER_IGNORE
		v.add_child(s)
	if unread > 0:
		var b := _label(str(unread) if unread < 100 else "99+", font_small, Color(0.1, 0.07, 0.12))
		b.add_stylebox_override("normal", _pad(_flat(HEART, 9), 7, 1))
		b.size_flags_vertical = SIZE_SHRINK_CENTER
		b.mouse_filter = MOUSE_FILTER_IGNORE
		h.add_child(b)
	return h

func _dm_small_button(h: HBoxContainer, text: String, accent: bool, method: String, binds: Array) -> Button:
	var b := Button.new()
	b.text = text
	_style_button(b, accent)
	b.add_font_override("font", font_small)
	for sbn in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBoxFlat = b.get_stylebox(sbn)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	b.connect("pressed", self, method, binds + [b])
	h.add_child(b)
	return b

func _dm_social(action: String, number: int, b: Button):
	if _lm == null:
		return
	b.disabled = true
	_lm.social_action(action, number)
	if action == "request":
		b.text = "Sent"

func _dm_find_changed(t: String):
	if t.strip_edges() == "" and _dm_found_q != "":
		_dm_found_q = ""
		_dm_found = []
		_fill_dm_list()

func _dm_find_go(_t = "", _b = null):
	if _lm == null:
		return
	var q := dm_find.text.strip_edges()
	if q == "":
		return
	var n := q.trim_prefix("#")
	if n.is_valid_integer() and int(n) > 0:
		# (a player number: straight to the friend request)
		_lm.social_action("request", int(n))
		dm_find.text = ""
		return
	if not bool(_lm.get("find_supported")):
		Globals.notify(Globals.NOTIFY_WARN, "This server can't look players up by name yet: type their player number (#123, it's on their profile).", "Friends")
		return
	_dm_found_q = q
	_dm_found = []
	_lm.find_players(q)

func _on_players_found(q: String, found: Array):
	if q != _dm_found_q:
		return
	_dm_found = found
	if dm_view != null and dm_view.visible:
		_fill_dm_list()

static func _by_online_name(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.online) != bool(b.online):
		return bool(a.online)
	return String(a.name).to_lower() < String(b.name).to_lower()

func _fill_dm_list():
	for c in dm_box.get_children():
		dm_box.remove_child(c)
		c.queue_free()
	if _lm == null:
		return
	if Rhythia.offline_mode:
		_dm_note("Offline Mode is on: no friends or messages (Settings > Online).")
		return
	if not bool(_lm.get("dms_supported")):
		_dm_note("Direct messages aren't on this server yet. Adding friends works.")
	# players found by name
	if _dm_found_q != "":
		_dm_heading("Players named \"%s\"" % _dm_found_q)
		if _dm_found.empty():
			_dm_note("Nobody found yet by that name. Their player number works too: #123.")
		for p in _dm_found:
			if not (p is Dictionary) or p.get("number") == null:
				continue
			var num := int(p.number)
			var h := _dm_person_row(String(p.get("name", "")), "#%d" % num, null, 0)
			match String(_lm.relation(num)):
				"friends": _dm_small_button(h, "Message", true, "_dm_open_from_row", [num])
				"outgoing": _dm_small_button(h, "Sent", false, "_dm_social", ["request", num]).disabled = true
				"incoming": _dm_small_button(h, "Accept", true, "_dm_social", ["accept", num])
				"blocked": _dm_small_button(h, "Blocked", false, "_dm_social", ["request", num]).disabled = true
				_: _dm_small_button(h, "Add friend", true, "_dm_social", ["request", num])
	# friend requests to you
	if not _lm.friend_requests_in.empty():
		_dm_heading("Friend requests")
		for p in _lm.friend_requests_in:
			var h := _dm_person_row(String(p.name), "wants to be friends", null, 0)
			_dm_small_button(h, "Accept", true, "_dm_social", ["accept", int(p.number)])
			_dm_small_button(h, "Decline", false, "_dm_social", ["decline", int(p.number)])
	# conversations (the newest first), then the friends you haven't written with
	var seen := {}
	var rows := 0
	var online_of := {}
	for p in _lm.friends:
		online_of[int(p.number)] = bool(p.online)
	if not _lm.dm_conversations.empty() or not _lm.friends.empty():
		_dm_heading("Friends")
	for c in _lm.dm_conversations:
		var num := int(c.number)
		seen[num] = true
		var pre := ("You: " if int(c.last_from) == int(_lm.my_player_number) else "") + preload("res://scripts/ui/ChatCommands.gd").plain(String(c.last_text))
		var on = online_of.get(num, bool(c.online)) if _lm.relation(num) == "friends" else null
		var h := _dm_person_row(String(c.name), pre, on, int(c.unread))
		_dm_row_click(h, num)
		rows += 1
	var rest := []
	for p in _lm.friends:
		if not seen.has(int(p.number)):
			rest.append(p)
	rest.sort_custom(self, "_by_online_name")
	for p in rest:
		var h := _dm_person_row(String(p.name), "Online" if p.online else "Offline", bool(p.online), 0)
		_dm_row_click(h, int(p.number))
		rows += 1
	if rows == 0 and _lm.friend_requests_in.empty() and _dm_found_q == "":
		_dm_note("No friends yet. Type a player's name above, or right-click someone in the list on the left (or their name in chat) and pick Add friend. Friends can message each other here.")
	var more := Button.new()
	more.text = "Manage friends (requests sent, remove, blocked)..."
	more.flat = true
	more.focus_mode = FOCUS_NONE
	more.add_font_override("font", font_small)
	more.add_color_override("font_color", DIM)
	more.add_color_override("font_color_hover", TEXT)
	more.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	more.connect("pressed", self, "_dm_manage")
	dm_box.add_child(more)

func _dm_manage():
	preload("res://scripts/ui/FriendsWindow.gd").open_on(self)

# the whole row opens the conversation
func _dm_row_click(h: HBoxContainer, number: int):
	var card: Control = h.get_parent()
	card.mouse_filter = MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	card.connect("gui_input", self, "_on_dm_row_input", [number])
	card.connect("mouse_entered", self, "_dm_row_hover", [card, true])
	card.connect("mouse_exited", self, "_dm_row_hover", [card, false])

func _dm_row_hover(card: Control, on: bool):
	if is_instance_valid(card):
		card.add_stylebox_override("panel", _pad(_flat(CARD_HOVER if on else CARD_BG, 3), 10, 7))

func _on_dm_row_input(ev, number: int):
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT and not ev.pressed:
		open_dm(number)

func _dm_open_from_row(number: int, _b = null):
	open_dm(number)

var _dm_refill := false
func _on_dm_changed():
	_tab_titles()
	if badge != null:
		_badge_text()
	if _open and dm_view != null and dm_view.visible and not _dm_refill:
		_dm_refill = true
		call_deferred("_dm_refill_now")

func _dm_refill_now():
	_dm_refill = false
	if _open and dm_view.visible:
		_fill_dm_list()

# ---- DMs: a conversation

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
# the time, with the day when it wasn't today
static func _stamp(ts: float) -> String:
	var t := int(ts / 1000.0) if ts > 100000000000.0 else int(ts)
	if t <= 0:
		t = OS.get_unix_time()
	var bias := int(OS.get_time_zone_info().get("bias", 0)) * 60
	var d := OS.get_datetime_from_unix_time(t + bias)
	var now := OS.get_datetime_from_unix_time(OS.get_unix_time() + bias)
	var clock := "%02d:%02d" % [int(d.hour), int(d.minute)]
	if int(d.day) == int(now.day) and int(d.month) == int(now.month) and int(d.year) == int(now.year):
		return clock
	return "%s %d, %s" % [MONTHS[int(d.month) - 1], int(d.day), clock]

func _dm_name(number: int) -> String:
	var nm: String = String(_lm.dm_name(number)) if _lm != null else ""
	return nm if nm != "" else "player #%d" % number

func _chat_hint(text: String):
	chat.push_color(DIM)
	chat.add_text(text)
	chat.pop()
	_chat_lines = -1 # (goes when the first message comes)

func _fill_dm_thread():
	chat.clear()
	_chat_lines = 0
	_chat_sizes = []
	var nm := _dm_name(_dm_with)
	dm_title.text = nm
	if _lm == null or Rhythia.offline_mode:
		chat_muted.text = "Offline Mode is on: no messages (Settings > Online)."
		chat_muted.visible = true
		chat.visible = false
		chat_input.editable = false
		chat_send.disabled = true
		return
	var friends: bool = String(_lm.relation(_dm_with)) == "friends"
	var can: bool = friends and bool(_lm.dms_supported)
	chat_input.set_meta("chat_placeholder", ("Message %s..." % nm) if can else ("You can only message friends." if not friends else "Direct messages aren't on this server yet."))
	preload("res://scripts/ui/ChatBan.gd").apply(chat_input, chat_send, bool(_lm.get("chat_banned")))
	if not can:
		chat_input.editable = false
		chat_send.disabled = true
	if not _lm.dm_threads.has(_dm_with):
		_lm.request_dm_history(_dm_with)
		_chat_hint("Loading..." if bool(_lm.dms_supported) else "")
		return
	var th: Array = _lm.dm_threads[_dm_with]
	if th.empty():
		_chat_hint("No messages yet. Say hi!")
	for m in th:
		_add_dm_line(m)
	_lm.mark_dm_read(_dm_with)

func _add_dm_line(m: Dictionary):
	if _chat_lines == -1:
		chat.clear()
		_chat_lines = 0
	if _chat_lines > 0:
		chat.newline()
	chat.push_color(FAINT)
	chat.add_text(_stamp(float(m.ts)) + "  ")
	chat.pop()
	var mine: bool = _lm != null and int(m.from) == int(_lm.my_player_number)
	var nm := _dm_name(_dm_with)
	chat.push_font(font_chat_bold)
	chat.push_color(ACCENT if mine else _name_color(nm))
	chat.add_text(("You" if mine else nm) + ": ")
	chat.pop()
	chat.pop()
	preload("res://scripts/ui/ChatCommands.gd").add_text(chat, String(m.text), 18)
	_chat_sizes.append(1)
	_chat_lines += 1
	if _chat_lines > CHAT_MAX_LINES:
		for _i in int(_chat_sizes.pop_front()):
			chat.remove_line(0)
		_chat_lines -= 1

func _on_dm_history(number: int):
	if _open and _chat_tab == "dms" and _dm_with == number:
		_fill_dm_thread()

func _on_dm_message(number: int):
	if _lm == null:
		return
	var th: Array = _lm.dm_threads.get(number, [])
	if _open and _chat_tab == "dms" and _dm_with == number:
		if not th.empty():
			_add_dm_line(th[th.size() - 1])
		return
	if _open:
		return # (the tab's count and the list say so)
	# closed: a note by the eye, as for the global chat
	var c = _lm.dm_conversation(number)
	if c == null or int(c.last_from) == int(_lm.my_player_number) or Rhythia.chat_hidden():
		return
	_badge_text()
	_place_notice()
	if not eye.visible or not Rhythia.spectate_chat_notify:
		return
	_notice_dm = number
	var max_w := 300.0 * _k
	notice_name.text = _fit(String(c.name), font_bold, max_w * 0.4) + " (DM):"
	notice_text.text = _fit(preload("res://scripts/ui/ChatCommands.gd").plain(String(c.last_text)), font_regular, max_w - font_bold.get_string_size(notice_name.text).x)
	notice.rect_size = Vector2()
	notice.visible = true
	_place_notice()
	call_deferred("_place_notice")
	_notice_tween.remove_all()
	notice.modulate.a = 0.0
	_notice_tween.interpolate_property(notice, "modulate:a", 0.0, 1.0, 0.18, Tween.TRANS_SINE, Tween.EASE_OUT)
	_notice_tween.interpolate_property(notice, "modulate:a", 1.0, 0.0, 0.4, Tween.TRANS_SINE, Tween.EASE_IN, NOTICE_TIME)
	_notice_tween.interpolate_callback(self, NOTICE_TIME + 0.4, "_hide_notice")
	_notice_tween.start()

# ---- Announcements: the server's last ones, to read

func _fill_news():
	chat.clear()
	_chat_lines = 0
	_chat_sizes = []
	if _lm == null or _lm.get("announcements") == null or _lm.announcements.empty():
		_chat_hint("No announcements yet. News from the team shows up here.")
		return
	for a in _lm.announcements:
		if _chat_lines > 0:
			chat.newline()
			chat.newline()
		chat.push_color(FAINT)
		chat.add_text(_stamp(float(a.ts)) + "  ")
		chat.pop()
		chat.push_font(font_chat_bold)
		chat.push_color(PINK)
		chat.add_text(String(a.from_name) if String(a.from_name) != "" else "Announcement")
		chat.pop()
		chat.pop()
		chat.newline()
		preload("res://scripts/ui/ChatCommands.gd").add_text(chat, String(a.text), 18)
		_chat_lines += 1

func _on_news_changed():
	if _open and _chat_tab == "news":
		_fill_news()
	else:
		_news_new = _lm != null and not _lm.announcements.empty() and _news_seen
	_news_seen = true # (the first list, at sign-in, isn't news)
	_tab_titles()
var _news_seen := false

# ---- the Global channel

func _fill_global():
	chat.clear()
	_chat_lines = 0
	_chat_sizes = []
	chat_input.set_meta("chat_placeholder", GLOBAL_HINT)
	var muted: bool = Rhythia.chat_hidden()
	chat_muted.text = "Offline Mode is on: no chat (Settings > Online)." if Rhythia.offline_mode else "Global chat is muted (Settings > Online)."
	chat_muted.visible = muted
	chat.visible = not muted
	var banned: bool = _lm != null and bool(_lm.get("chat_banned"))
	preload("res://scripts/ui/ChatBan.gd").apply(chat_input, chat_send, banned)
	if muted:
		chat_input.editable = false
		chat_send.disabled = true
	if muted or _lm == null:
		return
	if _lm.global_chat_history.empty():
		chat.push_color(DIM)
		chat.add_text("No messages yet. Say hi!")
		chat.pop()
		_chat_lines = -1 # (the hint goes when the first message comes)
		return
	# (a run of lines by people you blocked: one "N blocked messages  Show"
	# line, and the lines themselves under it once shown: BlockedChat.gd)
	var run := []
	for e in _lm.global_chat_history:
		var emid := String(e.get("mid", ""))
		if _lm.has_method("is_blocked_chat") and _lm.is_blocked_chat(emid):
			run.append(e)
			continue
		_add_blocked_run(run)
		run = []
		_add_chat_line(String(e.get("client_id", "")), String(e.get("name", "")), String(e.get("text", "")), float(e.get("ts", 0)), emid)
	_add_blocked_run(run)

func _add_blocked_run(run: Array):
	if run.empty():
		return
	var BC = preload("res://scripts/ui/BlockedChat.gd")
	var mids := []
	for e in run:
		mids.append(String(e.get("mid", "")))
	if _chat_lines > 0:
		chat.newline()
	BC.rtl_fold(chat, mids, _lm, self, "_redraw_for_reactions")
	_chat_sizes.append(1)
	_chat_lines += 1
	if BC.rtl_open(_lm, mids):
		for e in run:
			_add_chat_line(String(e.get("client_id", "")), String(e.get("name", "")), String(e.get("text", "")), float(e.get("ts", 0)), String(e.get("mid", "")))

func _on_chat_ban(_banned):
	if chat_input != null:
		_fill_chat()

func _on_chat_message(client_id: String, name: String, text: String, ts: float):
	if Rhythia.chat_hidden():
		return
	if not _open:
		_notify_chat(client_id, name, text)
		return
	if _chat_tab != "global":
		return # (it's in the history: drawn when Global is picked again)
	if _chat_lines == -1:
		chat.clear()
		_chat_lines = 0
	var mid: String = String(_lm.get("last_chat_id")) if _lm != null and _lm.get("last_chat_id") != null else ""
	if _lm != null and _lm.has_method("is_blocked_chat") and _lm.is_blocked_chat(mid):
		# (someone you blocked: drawn again, so it joins the fold before it)
		if not _react_redraw:
			_react_redraw = true
			call_deferred("_redraw_for_reactions")
		return
	_add_chat_line(client_id, name, text, ts, mid)

# someone reacted: the chat is drawn again (once a frame at most)
var _react_redraw := false
func _on_chat_reactions(mid: String):
	if not _open or _lm == null or _react_redraw:
		return
	for e in _lm.global_chat_history:
		if String(e.get("mid", "")) == mid:
			_react_redraw = true
			call_deferred("_redraw_for_reactions")
			return

# a message deleted by staff: the chat drawn again without it
func _on_chat_deleted(_mid):
	if _open and not _react_redraw:
		_react_redraw = true
		call_deferred("_redraw_for_reactions")

func _redraw_for_reactions():
	_react_redraw = false
	if chat != null and _open:
		var v := chat.get_v_scroll()
		var at_end: bool = v.value >= v.max_value - v.page - 4
		var keep: float = v.value
		_fill_chat()
		if not at_end:
			chat.scroll_following = false
			yield(get_tree(), "idle_frame")
			v.value = keep
			chat.scroll_following = true

static func _clock(ts: float) -> String:
	var t := int(ts / 1000.0) if ts > 100000000000.0 else int(ts)
	if t <= 0:
		t = OS.get_unix_time()
	t += int(OS.get_time_zone_info().get("bias", 0)) * 60
	var d := OS.get_datetime_from_unix_time(t)
	return "%02d:%02d" % [int(d.hour), int(d.minute)]

var _chat_sizes := []
func _add_chat_line(client_id: String, name: String, text: String, ts: float, mid: String = ""):
	if _chat_lines > 0:
		chat.newline()
	chat.push_color(FAINT)
	chat.add_text(_clock(ts) + "  ")
	chat.pop()
	var is_you := client_id != "" and client_id == Rhythia.cid
	var who: bool = preload("res://scripts/ui/ChatReactions.gd").name_start(chat, mid, name, _lm) # (staff: right-click)
	chat.push_font(font_chat_bold)
	chat.push_color(ACCENT if is_you else _name_color(name))
	chat.add_text(name + ": ")
	chat.pop()
	chat.pop()
	preload("res://scripts/ui/ChatReactions.gd").name_end(chat, who)
	# @mentions stand out (yours most); names with spaces count too
	for part in preload("res://scripts/ui/ChatMention.gd").split(text, _lm):
		if part[1]:
			chat.push_font(font_chat_bold)
			chat.push_color(HEART if part[2] else LILAC)
			chat.add_text(part[0])
			chat.pop()
			chat.pop()
		else:
			preload("res://scripts/ui/ChatCommands.gd").add_text(chat, part[0], 18) # (emoji as pictures, share links)
	var extra: int = preload("res://scripts/ui/ChatReactions.gd").add(chat, mid, _lm, 16, 3) # (reactions under it, and + to react)
	_chat_sizes.append(1 + extra) # (the label's lines this message takes)
	_chat_lines += 1
	if _chat_lines > CHAT_MAX_LINES:
		for _i in int(_chat_sizes.pop_front()):
			chat.remove_line(0)
		_chat_lines -= 1

func _on_chat_entered(_t: String):
	_send_chat()

func _send_chat():
	if _lm == null or (Rhythia.chat_hidden() and not (_chat_tab == "dms" and not Rhythia.offline_mode)):
		return
	var text := chat_input.text.strip_edges()
	if text == "":
		return
	if _chat_tab == "dms":
		if _dm_with > 0:
			_lm.send_dm(_dm_with, text)
			chat_input.text = ""
			chat_input.grab_focus()
		return
	if _chat_tab != "global":
		return
	# /share, /profile, /report, /help (ChatCommands.gd)
	if preload("res://scripts/ui/ChatCommands.gd").handle(self, text, _lm, "send_global_chat_message"):
		chat_input.text = ""
		chat_input.grab_focus()
		return
	_lm.send_global_chat_message(text)
	chat_input.text = ""
	chat_input.grab_focus()

# ------------------------------------------------------------------ avatars

func _load_avatar(url: String, pic: TextureRect):
	if url.begins_with("/"): # (a picture on the server, given without its address)
		url = "https://chromia.lol" + url
	if not url.begins_with("http"):
		return
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
	if AnimPic.is_gif(data):
		# a moving picture: decoded on a thread, round, then shown (AnimPic.gd)
		AnimPic.load_async(data, url, 96, true, self, "_on_gif_avatar", [url, waiting])
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

func _on_gif_avatar(tex, url: String, waiting: Array):
	if tex == null:
		return
	_img_cache[url] = tex
	_img_order.append(url)
	while _img_order.size() > MAX_IMG_CACHE:
		_img_cache.erase(_img_order.pop_front())
	for pic in waiting:
		if is_instance_valid(pic):
			pic.texture = tex
			pic.visible = true

# --- right-click a card: View stats -------------------------------------------------
# Their profile (the same as the website's: level, XP and SP with their places,
# passes, bio, last online) and their best plays, in a box over the window.
const STATS_SITE := "https://chromia.lol"
var _ctx: PopupMenu = null
var _ctx_card = null
var _stats: Control = null
var _stats_box: VBoxContainer = null
var _stats_for := -1

func _card_menu(c: Dictionary, at: Vector2):
	if _ctx == null or not is_instance_valid(_ctx):
		_ctx = PopupMenu.new()
		_ctx.add_font_override("font", font_regular)
		_ctx.connect("id_pressed", self, "_on_card_menu")
		window.add_child(_ctx)
	_ctx.clear()
	_ctx.add_item("View stats", 0)
	if c.can and not c.is_you:
		_ctx.add_item("Spectate", 1)
	_ctx.add_item("Open their profile on the website", 2)
	# (you're in a lobby: bring them in)
	if _lm != null and _lm.lobby_active and not _lm.watch_mode and not c.is_you:
		_ctx.add_item("Invite to your lobby", 3)
	# friends and blocking (LobbyManager social_action), like a name in chat
	if _lm != null and not c.is_you and int(c.number) > 0:
		_ctx.add_separator()
		match String(_lm.relation(int(c.number))):
			"none": _ctx.add_item("Add friend", 4)
			"incoming": _ctx.add_item("Accept friend request", 5)
		if String(_lm.relation(int(c.number))) == "blocked":
			_ctx.add_item("Unblock", 7)
		else:
			_ctx.add_item("Block", 6)
	_ctx_card = c
	_ctx.popup(Rect2(at, Vector2(1, 1)))

func _on_card_menu(id: int):
	var c = _ctx_card
	if not (c is Dictionary):
		return
	match id:
		0:
			_show_stats(int(c.number), String(c.nm))
		1:
			_spectate(c)
		2:
			OS.shell_open(STATS_SITE + "/profile?id=%d" % int(c.number))
		3:
			if _lm != null:
				_lm.invite_player(int(c.number))
		4, 5, 7:
			if _lm != null:
				_lm.social_action({4: "request", 5: "accept", 7: "unblock"}[id], int(c.number))
		6:
			if _lm != null:
				_lm.confirm_block(int(c.number), String(c.nm))

func _show_stats(number: int, nm: String):
	if number <= 0:
		return
	_close_stats()
	_stats_for = number
	_stats = ColorRect.new()
	_stats.color = Color(0, 0, 0, 0.55)
	_stats.anchor_right = 1.0
	_stats.anchor_bottom = 1.0
	_stats.mouse_filter = MOUSE_FILTER_STOP
	_stats.connect("gui_input", self, "_on_stats_bg_input")
	window.add_child(_stats)
	var card := PanelContainer.new()
	card.add_stylebox_override("panel", _pad(_flat(CARD_BG, 10, ACCENT, 2), 22 * _k, 18 * _k))
	card.rect_min_size = Vector2(560, 0) * _k
	_stats.add_child(card)
	_stats_box = VBoxContainer.new()
	_stats_box.add_constant_override("separation", int(10 * _k))
	card.add_child(_stats_box)
	_stats_box.add_child(_label("%s  #%d" % [nm, number], font_title, TEXT))
	_stats_box.add_child(_label("Loading their stats...", font_regular, DIM))
	call_deferred("_center_stats", card)
	_stats_get(STATS_SITE + "/savia-public/api/player/%d" % number, "_on_stats_profile")

func _center_stats(card: Control):
	if is_instance_valid(card) and is_instance_valid(_stats):
		card.rect_size = Vector2.ZERO # (back to what its contents need)
		card.rect_position = ((_stats.rect_size - card.rect_size) / 2.0).floor()

func _on_stats_bg_input(ev):
	if ev is InputEventMouseButton and ev.pressed and _stats is Control:
		var card = _stats.get_child(0) if _stats.get_child_count() > 0 else null
		if card == null or not card.get_global_rect().has_point(ev.global_position):
			_close_stats()

func _close_stats():
	if _stats != null and is_instance_valid(_stats):
		_stats.queue_free()
	_stats = null
	_stats_box = null

func _stats_get(url: String, method: String):
	var r := HTTPRequest.new()
	r.timeout = 15
	add_child(r)
	r.connect("request_completed", self, "_on_stats_http", [r, method, _stats_for])
	if r.request(url) != OK:
		r.queue_free()
		call(method, null, _stats_for)

func _on_stats_http(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, method: String, number: int):
	r.queue_free()
	var j = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		j = parse_json(body.get_string_from_utf8())
	call(method, j, number)

func _stat_cell(grid: GridContainer, title: String, value: String, sub: String = "", icon: Texture = null, col = null):
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 0)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_child(_label(title, font_tiny, DIM))
	var vl := _label(value, font_name, col if col is Color else ACCENT)
	if icon != null:
		# (a little picture before the number: the trophy)
		var h := HBoxContainer.new()
		h.add_constant_override("separation", int(4 * _k))
		var t := TextureRect.new()
		t.texture = icon
		t.expand = true
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.rect_min_size = Vector2(1, 1) * float(font_name.get_height()) * 0.8
		t.size_flags_vertical = SIZE_SHRINK_CENTER
		h.add_child(t)
		h.add_child(vl)
		v.add_child(h)
	else:
		v.add_child(vl)
	if sub != "":
		v.add_child(_label(sub, font_tiny, DIM))
	grid.add_child(v)

static func _num(n) -> String:
	var s := str(int(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(s.length() - 3) + out
		s = s.left(s.length() - 3)
	return s + out

func _on_stats_profile(p, number: int):
	if _stats_box == null or number != _stats_for:
		return
	for ch in _stats_box.get_children():
		_stats_box.remove_child(ch) # (now: it still counted for the box's size until freed)
		ch.queue_free()
	if not (p is Dictionary):
		_stats_box.add_child(_label("No stats yet", font_title, TEXT))
		_stats_box.add_child(_label("They haven't passed a ranked map (or the server couldn't be reached).", font_regular, DIM))
		_stats_buttons(number)
		return
	var head := HBoxContainer.new()
	head.add_constant_override("separation", int(14 * _k))
	_stats_box.add_child(head)
	var av := TextureRect.new()
	av.rect_min_size = Vector2(64, 64) * _k
	av.expand = true
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	av.visible = false
	head.add_child(av)
	var url := Globals.s(p.get("avatar_url", ""))
	if url != "":
		_load_avatar(url, av)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGN_CENTER
	head.add_child(names)
	var tag = p.get("tag")
	var title := Globals.s(p.get("name", "Player"))
	names.add_child(_label(title, font_title, TEXT))
	var line2 := "Player #%d" % int(p.get("number", number))
	if tag is Dictionary and Globals.s(tag.get("text", "")) != "":
		line2 += "  ·  " + Globals.s(tag.get("text", ""))
	if bool(p.get("online", false)):
		line2 += "  ·  online now"
	elif p.get("last_seen") != null:
		line2 += "  ·  last online " + _ago_text(int(float(p.get("last_seen")) / 1000.0))
	names.add_child(_label(line2, font_small, DIM))
	# their badges (Map of the Day, Ranker, the ones the admins gave)
	var badges = load("res://scripts/ui/BadgeRow.gd").make(p, font_small, _k)
	badges.rect_min_size = Vector2(516, 0) * _k
	_stats_box.add_child(badges)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_constant_override("hseparation", int(16 * _k))
	_stats_box.add_child(grid)
	var lv = p.get("level")
	var lv_text := "-"
	if lv is Dictionary:
		lv_text = str(int(lv.get("level", 0)))
		if int(lv.get("prestige", 0)) > 0:
			lv_text += "  (P%d)" % int(lv.get("prestige", 0))
	_stat_cell(grid, "LEVEL", lv_text)
	_stat_cell(grid, "XP", _num(p.get("xp", 0)), ("#%d" % int(p.xp_rank)) if p.get("xp_rank") != null else "")
	_stat_cell(grid, "SP", _num(p.get("sp", 0)), ("#%d" % int(p.sp_rank)) if p.get("sp_rank") != null else "")
	# trophies: the ranked maps they're #1 on (Trophy.gd)
	var TR = load("res://scripts/ui/Trophy.gd")
	_stat_cell(grid, "TROPHIES", _num(p.get("trophies", 0)), ("#%d" % int(p.trophies_rank)) if p.get("trophies_rank") != null else "", TR.texture(), TR.GOLD)
	_stat_cell(grid, "PASSES", _num(p.get("pass_count", 0)), "%d maps" % int(p.get("map_count", 0)))
	var bio := Globals.s(p.get("bio", "")).strip_edges()
	if bio != "":
		var b := _label(bio, font_small, TEXT)
		b.autowrap = true
		b.rect_min_size = Vector2(516, 0) * _k
		_stats_box.add_child(b)
	_stats_box.add_child(_label("Best plays", font_bold, LILAC))
	var plays := VBoxContainer.new()
	plays.name = "Plays"
	plays.add_constant_override("separation", int(4 * _k))
	_stats_box.add_child(plays)
	plays.add_child(_label("Loading...", font_small, DIM))
	_stats_buttons(number)
	_stats_get(STATS_SITE + "/savia-public/api/player/%d/scores" % number, "_on_stats_scores")
	call_deferred("_center_stats", _stats_box.get_parent())

func _on_stats_scores(j, number: int):
	if _stats_box == null or number != _stats_for:
		return
	var plays = _stats_box.get_node_or_null("Plays")
	if plays == null:
		return
	for ch in plays.get_children():
		plays.remove_child(ch)
		ch.queue_free()
	var rows: Array = j.get("scores", []) if j is Dictionary and j.get("scores") is Array else []
	var best := []
	for r in rows:
		if r is Dictionary and float(r.get("sp_weighted", 0)) > 0:
			best.append(r)
	best.sort_custom(self, "_by_sp_weighted")
	if not (j is Dictionary):
		plays.add_child(_label("Couldn't load their plays.", font_small, DIM))
	elif best.empty():
		plays.add_child(_label("No ranked passes yet.", font_small, DIM))
	for i in range(min(5, best.size())):
		var r: Dictionary = best[i]
		var h := HBoxContainer.new()
		h.add_constant_override("separation", int(10 * _k))
		plays.add_child(h)
		var nm := _label(Globals.s(r.get("song_name", "")), font_small, TEXT)
		nm.clip_text = true
		nm.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(nm)
		var spd := float(r.get("speed", 1.0))
		var extra := "%.2f%%" % (float(r.get("accuracy", 0)) * 100.0)
		if abs(spd - 1.0) > 0.001:
			extra += "  %.2fx" % spd
		h.add_child(_label(extra, font_small, DIM))
		h.add_child(_label("%s SP" % _num(r.get("sp_weighted", 0)), font_small, ACCENT))
	call_deferred("_center_stats", _stats_box.get_parent())

func _by_sp_weighted(a, b) -> bool:
	return float(a.get("sp_weighted", 0)) > float(b.get("sp_weighted", 0))

func _stats_buttons(number: int):
	var row := HBoxContainer.new()
	row.add_constant_override("separation", int(10 * _k))
	row.alignment = BoxContainer.ALIGN_END
	_stats_box.add_child(row)
	var web := Button.new()
	web.text = "Open on the website"
	web.add_font_override("font", font_regular)
	web.connect("pressed", OS, "shell_open", [STATS_SITE + "/profile?id=%d" % number])
	row.add_child(web)
	var close := Button.new()
	close.text = "Close"
	close.add_font_override("font", font_bold)
	close.connect("pressed", self, "_close_stats")
	row.add_child(close)

static func _ago_text(ts: int) -> String:
	var d := OS.get_unix_time() - ts
	if d < 3600:
		return "%d min ago" % int(max(1, d / 60))
	if d < 86400:
		return "%d h ago" % int(d / 3600)
	return "%d days ago" % int(d / 86400)
