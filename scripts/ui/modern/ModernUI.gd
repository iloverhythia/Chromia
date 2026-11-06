extends Control

# Experimental: Modern UI (Settings > Replays & Misc > Experimental). A new
# main screen drawn over the classic menu, after the design in the owner's
# video: a top bar (you, the page icons, Multiplayer / Collections / All Maps
# and the search), the selected map on the left (its cover, the leaderboard,
# title, difficulty, mapper, ranked / stars / notes / length, a preview bar,
# Play and the mods) and every map as a cover card in a grid on the right.
# It uses the classic menu underneath for everything it does (the map list's
# filters, sorting and search, the music preview, starting a map), so both
# always agree. The other pages (Settings, Content Browser, Online...) open in
# the classic menu for now, with a button back.

const SITE := "https://savia.nysr.host"
const MIcon = preload("res://scripts/ui/modern/MIcon.gd")
const CoverSq = preload("res://scripts/ui/modern/CoverSq.gd")
const ScoreHistory = preload("res://scripts/ScoreHistory.gd") # (also used by ModernPanels.gd)

const BG := Color("#0c0b10")
const TEXT := Color("#f2f2f5")
const DIM := Color("#9a99a3")
const FAINT := Color("#5d5c66")
const PANEL := Color(1, 1, 1, 0.035)
const PANEL_HI := Color(1, 1, 1, 0.07)
const RANKED := Color("#4b63d8")
const RANK_GOLD := Color("#e9b949")
const ACCENT := Color("#ffffff")

const COLS := 4
const GAP := 13.0
const CARD := 142.0 # (at 720 px high; everything scales with the window)

var k := 1.0
var f := {} # fonts by name
var list = null # the classic map list (v3MapList.gd)
var covers = null # CoverSq.gd
var _maps := []
var _sel = null

# parts
var bg_cover: TextureRect
var bg_shade: Control
var top: Control
var avatar: TextureRect
var name_l: Label
var rp_l: Label
var tabs := {}
var search: LineEdit
var left: Control
var cover: TextureRect
var board: VBoxContainer
var board_msg: Label
var pb_label: Label
var pb_row: Control
var local_btn: Button
var title_l: Label
var diff_l: Label
var mapper_l: Label
var stats := {}
var prev_btn: Control
var prev_t0: Label
var prev_t1: Label
var prev_bar: HSlider
var play_btn: Button
var play_sub: Label
var eye_btn: Button
var save_btn: Button
var mods_row: HBoxContainer
var mod_btns := {}
var grid: Control
var cards := []
var scroll := 0.0
var scroll_to := 0.0
var vbar: VScrollBar
var panels # ModernPanels.gd
var online # ModernOnline.gd (the Online Players window)

# the classic menu's parts drawn over the page area, hidden while this is on
const CLASSIC_HIDE := ["Quit", "SidebarClick", "Sidebar", "VersionNumber", "VersionNumberB"]

static func attach(menu: Node):
	if menu == null or menu.has_node("ModernUI"):
		return
	var m = load("res://scripts/ui/modern/ModernUI.gd").new()
	m.name = "ModernUI"
	menu.add_child(m)
	# under the classic page area (Main), so a classic page can show inside the
	# Modern UI's panel (ModernPanels.gd) and work as it always did
	var main = menu.get_node_or_null("Main")
	if main != null:
		menu.move_child(m, main.get_index())
	m._classic(false)

static func detach(menu: Node):
	if menu == null:
		return
	var m = menu.get_node_or_null("ModernUI")
	if m != null:
		m._classic(true)
		m.queue_free()
	var b = menu.get_node_or_null("ModernBack")
	if b != null:
		b.queue_free()

# the classic menu shown (true) or hidden behind this (false)
func _classic(on: bool):
	var menu = get_parent()
	if menu == null:
		return
	for n in CLASSIC_HIDE + ["Main"]:
		var c = menu.get_node_or_null(n)
		if c is CanvasItem:
			c.visible = on

func _font(file: String, size: int) -> DynamicFont:
	var df := DynamicFont.new()
	df.font_data = load("res://assets/font/Nunito/Nunito-%s.ttf" % file)
	df.size = int(round(size * k))
	df.use_filter = true
	df.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return df

func _fonts():
	f = {
		"name": _font("ExtraBold", 18), "rp": _font("Bold", 12), "tab": _font("ExtraBold", 15),
		"search": _font("SemiBold", 14), "title": _font("ExtraBold", 22), "diff": _font("Bold", 16),
		"mapper": _font("Bold", 17), "stat": _font("Bold", 15), "small": _font("Bold", 9),
		"rowname": _font("ExtraBold", 11), "rowsub": _font("Bold", 8), "rank": _font("ExtraBold", 11),
		"grade": _font("ExtraBold", 16), "play": _font("ExtraBold", 17), "playsub": _font("Bold", 8),
		"time": _font("Bold", 9), "card_t": _font("ExtraBold", 12), "card_s": _font("Bold", 8),
		"pill": _font("ExtraBold", 7), "mod": _font("ExtraBold", 13), "local": _font("Bold", 9),
	}

func _flat(c: Color, r: float = 6.0, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(round(r * k)))
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.anti_aliasing = true
	return sb

func _label(t: String, font: Font, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_font_override("font", font)
	l.add_color_override("font_color", col)
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	l.add_constant_override("shadow_offset_x", 0)
	l.add_constant_override("shadow_offset_y", 0)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l

func _button(flat_col: Color, hover_col: Color, r: float = 6.0) -> Button:
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	b.add_stylebox_override("normal", _flat(flat_col, r))
	b.add_stylebox_override("hover", _flat(hover_col, r))
	b.add_stylebox_override("pressed", _flat(hover_col, r))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_stylebox_override("disabled", _flat(flat_col, r))
	return b

# ------------------------------------------------------------------ setup

func _ready():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_STOP
	covers = CoverSq.get_cache()
	covers.connect("ready", self, "_on_cover_ready")
	list = Rhythia.menu_node("Main/Maps/MapRegistry/S/VBoxContainer")
	k = max(0.6, get_viewport_rect().size.y / 720.0)
	_fonts()
	_build()
	get_viewport().connect("size_changed", self, "_on_resize")
	Rhythia.connect("selected_song_changed", self, "_on_song")
	if Rhythia.has_signal("mods_changed"):
		Rhythia.connect("mods_changed", self, "_refresh_mods")
	if Rhythia.has_signal("speed_mod_changed"):
		Rhythia.connect("speed_mod_changed", self, "_refresh_mods")
	if list != null and list.has_signal("search_updated"):
		list.connect("search_updated", self, "_on_list_changed")
	call_deferred("_on_resize")
	call_deferred("_reload_maps")
	call_deferred("_on_song", Rhythia.selected_song)
	call_deferred("_load_me")

func _on_resize():
	var nk: float = max(0.6, get_viewport_rect().size.y / 720.0)
	if abs(nk - k) > 0.01:
		k = nk
		for c in get_children():
			c.queue_free()
		cards = []
		_fonts()
		_build()
		_on_song(Rhythia.selected_song)
		_reload_maps()
	_layout()
	if online != null and is_instance_valid(online):
		online.layout()

func _build():
	# the background: the selected cover, blurred and dark
	var base := ColorRect.new()
	base.color = BG
	base.anchor_right = 1
	base.anchor_bottom = 1
	base.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(base)
	bg_cover = TextureRect.new()
	bg_cover.expand = true
	bg_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_cover.modulate = Color(0.55, 0.5, 0.55, 0.32)
	bg_cover.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg_cover)
	bg_shade = Control.new()
	bg_shade.anchor_right = 1
	bg_shade.anchor_bottom = 1
	bg_shade.mouse_filter = MOUSE_FILTER_IGNORE
	bg_shade.connect("draw", self, "_draw_shade")
	add_child(bg_shade)

	_build_grid()
	_build_left()
	_build_top()
	panels = load("res://scripts/ui/modern/ModernPanels.gd").new(self)
	panels.name = "Panels"
	add_child(panels)
	online = load("res://scripts/ui/modern/ModernOnline.gd").new(self)
	add_child(online)

	# (bottom right: the people button (SpectatePage.gd, on its own layer) opens `online`)

func _draw_shade():
	var s := bg_shade.rect_size
	# darker towards the right, where the grid is
	var cols := PoolColorArray([Color(BG.r, BG.g, BG.b, 0.25), Color(BG.r, BG.g, BG.b, 0.92), Color(BG.r, BG.g, BG.b, 0.92), Color(BG.r, BG.g, BG.b, 0.25)])
	bg_shade.draw_polygon(PoolVector2Array([Vector2(0, 0), Vector2(s.x * 0.62, 0), Vector2(s.x * 0.62, s.y), Vector2(0, s.y)]), PoolColorArray([cols[0], cols[1], cols[2], cols[3]]))
	bg_shade.draw_rect(Rect2(s.x * 0.62, 0, s.x * 0.38, s.y), Color(BG.r, BG.g, BG.b, 0.92))
	# the top bar's shade
	bg_shade.draw_rect(Rect2(0, 0, s.x, 46 * k), Color(0.05, 0.05, 0.07, 0.55))

# --- the top bar ----------------------------------------------------------------

func _build_top():
	top = Control.new()
	top.mouse_filter = MOUSE_FILTER_PASS
	add_child(top)
	var me := Control.new()
	me.name = "Me"
	me.mouse_filter = MOUSE_FILTER_STOP
	me.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	me.connect("gui_input", self, "_on_me_input")
	top.add_child(me)
	avatar = TextureRect.new()
	avatar.expand = true
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar.material = _round_mat(6.0 / 33.0)
	avatar.mouse_filter = MOUSE_FILTER_IGNORE
	me.add_child(avatar)
	name_l = _label("You", f.name)
	me.add_child(name_l)
	rp_l = _label("", f.rp, DIM)
	me.add_child(rp_l)
	var icons := [["heart", "Favorites only", "_toggle_favs"], ["gear", "Settings", "_open_settings"],
		["cloud_down", "Online Workshop (Content Browser)", "_open_workshop"], ["list", "Leaderboards", "_open_leaderboard"],
		["sort", "Sort & Filter", "_open_filters"], ["bookmark_plus", "Add this map to a collection", "_open_collection_add"],
		["layout", "Classic menu", "_open_classic_maps"]]
	for i in icons.size():
		var b := _button(Color(0, 0, 0, 0), Color(1, 1, 1, 0.08), 6)
		b.name = "Icon_" + String(icons[i][0])
		b.hint_tooltip = icons[i][1]
		var ic = MIcon.make(icons[i][0], 21 * k, Color("#d7d6dc"), 2.0)
		b.add_child(ic)
		b.connect("pressed", self, icons[i][2])
		top.add_child(b)
	for t in [["multiplayer", "Multiplayer"], ["collections", "Collections"], ["all", "All Maps"]]:
		var b := _button(Color(0, 0, 0, 0), Color(1, 1, 1, 0.06), 6)
		b.text = t[1]
		b.add_font_override("font", f.tab)
		b.add_color_override("font_color", Color("#d9d8de"))
		b.add_color_override("font_color_hover", TEXT)
		b.connect("pressed", self, "_on_tab", [t[0]])
		top.add_child(b)
		tabs[t[0]] = b
	tabs["all"].connect("draw", self, "_draw_tab_line", [tabs["all"]])
	search = LineEdit.new()
	search.placeholder_text = "Search map"
	search.add_font_override("font", f.search)
	search.add_color_override("font_color", TEXT)
	search.add_color_override("font_color_placeholder", Color("#8d8c95"))
	var ssb := _flat(Color(1, 1, 1, 0.06), 6)
	ssb.content_margin_left = 10 * k
	search.add_stylebox_override("normal", ssb)
	search.add_stylebox_override("focus", _flat(Color(1, 1, 1, 0.09), 6))
	search.connect("text_changed", self, "_on_search")
	if list != null and "search_text" in list:
		search.text = String(list.search_text)
	top.add_child(search)
	if Engine.get_main_loop().root.has_node("/root/Rhythia"):
		pass
	preload("res://scripts/ui/Emoji.gd").field(search)

func _draw_tab_line(b: Button):
	b.draw_rect(Rect2(6 * k, b.rect_size.y - 3 * k, b.rect_size.x - 12 * k, 2.5 * k), ACCENT)

func _round_mat(radius: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _round_shader()
	m.set_shader_param("radius", radius)
	return m

static func _round_shader() -> Shader:
	var root = Engine.get_main_loop().root
	if root.has_meta("modern_round_shader"):
		return root.get_meta("modern_round_shader")
	var s := Shader.new()
	s.code = """shader_type canvas_item;
uniform float radius = 0.08;
uniform float dim = 1.0;
void fragment() {
	vec2 p = abs(UV - vec2(0.5)) - vec2(0.5 - radius);
	float d = length(max(p, vec2(0.0))) - radius;
	vec4 c = texture(TEXTURE, UV);
	float a = 1.0 - smoothstep(-0.006, 0.006, d);
	COLOR = vec4(c.rgb * dim, c.a * a);
}"""
	root.set_meta("modern_round_shader", s)
	return s

# --- the selected map (left) ----------------------------------------------------

func _build_left():
	left = Control.new()
	left.mouse_filter = MOUSE_FILTER_PASS
	add_child(left)
	var shadow := Panel.new()
	shadow.name = "CoverShadow"
	var shsb := _flat(Color(0, 0, 0, 0.0), 8)
	shsb.shadow_color = Color(0, 0, 0, 0.55)
	shsb.shadow_size = int(18 * k)
	shadow.add_stylebox_override("panel", shsb)
	shadow.mouse_filter = MOUSE_FILTER_IGNORE
	left.add_child(shadow)
	cover = TextureRect.new()
	cover.expand = true
	cover.stretch_mode = TextureRect.STRETCH_SCALE
	cover.material = _round_mat(0.03)
	cover.mouse_filter = MOUSE_FILTER_IGNORE
	left.add_child(cover)

	board = VBoxContainer.new()
	board.add_constant_override("separation", int(2 * k))
	board.mouse_filter = MOUSE_FILTER_PASS
	left.add_child(board)
	board_msg = _label("", f.local, DIM)
	board_msg.align = Label.ALIGN_CENTER
	board_msg.autowrap = true
	left.add_child(board_msg)
	pb_label = _label("Personal best", f.small, DIM)
	left.add_child(pb_label)
	pb_row = Control.new()
	pb_row.mouse_filter = MOUSE_FILTER_IGNORE
	left.add_child(pb_row)
	local_btn = _button(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.07), 4)
	local_btn.text = "Go to local scores"
	local_btn.add_font_override("font", f.local)
	local_btn.add_color_override("font_color", Color("#c9c8cf"))
	local_btn.connect("pressed", self, "_open_classic_maps")
	left.add_child(local_btn)

	title_l = _label("", f.title)
	title_l.align = Label.ALIGN_CENTER
	title_l.clip_text = true
	left.add_child(title_l)
	diff_l = _label("", f.diff, Color("#6e5b93"))
	diff_l.align = Label.ALIGN_CENTER
	left.add_child(diff_l)
	mapper_l = _label("", f.mapper, Color("#a8a7b0"))
	mapper_l.align = Label.ALIGN_CENTER
	mapper_l.clip_text = true
	left.add_child(mapper_l)
	for s in [["status", "cloud"], ["stars", "star"], ["notes", "layers"], ["length", "clock"]]:
		var h := HBoxContainer.new()
		h.add_constant_override("separation", int(9 * k))
		h.mouse_filter = MOUSE_FILTER_IGNORE
		var ic = MIcon.make(s[1], 17 * k, Color("#cfced5"), 1.8)
		ic.size_flags_vertical = SIZE_SHRINK_CENTER
		if s[1] == "star":
			ic.filled = true
		h.add_child(ic)
		var l := _label("", f.stat, Color("#e7e6eb"))
		h.add_child(l)
		left.add_child(h)
		stats[s[0]] = [h, l, ic]

	prev_btn = _button(Color(0, 0, 0, 0), Color(1, 1, 1, 0.06), 4)
	prev_btn.add_child(MIcon.make("pause", 14 * k, TEXT, 2.4))
	prev_btn.connect("pressed", self, "_toggle_preview")
	left.add_child(prev_btn)
	prev_t0 = _label("00:00", f.time, Color("#cfced5"))
	left.add_child(prev_t0)
	prev_t1 = _label("00:00", f.time, Color("#cfced5"))
	left.add_child(prev_t1)
	prev_bar = HSlider.new()
	prev_bar.min_value = 0
	prev_bar.max_value = 1
	prev_bar.step = 0.001
	prev_bar.focus_mode = FOCUS_NONE
	prev_bar.add_stylebox_override("slider", _bar_style(Color(1, 1, 1, 0.12)))
	prev_bar.add_stylebox_override("grabber_area", _bar_style(Color(1, 1, 1, 0.85)))
	prev_bar.add_stylebox_override("grabber_area_highlight", _bar_style(Color(1, 1, 1, 0.95)))
	prev_bar.add_icon_override("grabber", _dot_tex(int(13 * k)))
	prev_bar.add_icon_override("grabber_highlight", _dot_tex(int(14 * k)))
	prev_bar.connect("value_changed", self, "_on_seek")
	left.add_child(prev_bar)

	eye_btn = _button(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.1), 5)
	eye_btn.hint_tooltip = "Watch it played by Autoplay"
	eye_btn.add_child(MIcon.make("eye", 22 * k, TEXT, 1.8))
	eye_btn.connect("pressed", self, "_watch_auto")
	left.add_child(eye_btn)
	play_btn = _button(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.1), 5)
	play_btn.add_font_override("font", f.play)
	play_btn.add_color_override("font_color", TEXT)
	play_btn.add_color_override("font_color_hover", TEXT)
	play_btn.connect("pressed", self, "_play")
	left.add_child(play_btn)
	play_sub = _label("", f.playsub, DIM)
	play_sub.align = Label.ALIGN_CENTER
	play_btn.add_child(play_sub)
	save_btn = _button(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.1), 5)
	save_btn.hint_tooltip = "Add to a collection"
	save_btn.add_child(MIcon.make("bookmark_plus", 22 * k, TEXT, 1.8))
	save_btn.connect("pressed", self, "_open_collection_add")
	left.add_child(save_btn)

	mods_row = HBoxContainer.new()
	mods_row.add_constant_override("separation", int(6 * k))
	left.add_child(mods_row)
	# the mods, each tinted with its own colour like the video
	var mods := [["speed", "S+", null, Color("#6b8cff")], ["nofail", "NF", null, Color("#7ad37a")],
		["sudden_death", "", "skull", Color("#ff6b7a")], ["hard_mode", "", "hand", Color("#ff8a5c")],
		["ghost", "", "ghost", Color("#a98bff")], ["chaos", "", "shuffle", Color("#ff6bd6")],
		["360", "", "disc", Color("#7aa8ff")], ["mirror_x", "", "mirror", Color("#6be0ff")],
		["flashlight", "", "glasses", Color("#ffb86b")]]
	for m in mods:
		var b := Button.new()
		b.focus_mode = FOCUS_NONE
		b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		b.rect_min_size = Vector2(46, 46) * k
		b.toggle_mode = m[0] != "speed"
		b.hint_tooltip = _mod_tip(m[0])
		b.set_meta("tint", m[3])
		if m[2] != null:
			var ic = MIcon.make(m[2], 22 * k, m[3], 1.9)
			ic.anchor_left = 0.5; ic.anchor_top = 0.5; ic.anchor_right = 0.5; ic.anchor_bottom = 0.5
			ic.margin_left = -11 * k; ic.margin_top = -11 * k; ic.margin_right = 11 * k; ic.margin_bottom = 11 * k
			b.add_child(ic)
		else:
			b.text = m[1]
			b.add_font_override("font", f.mod)
			b.add_color_override("font_color", m[3])
			b.add_color_override("font_color_hover", m[3])
			b.add_color_override("font_color_pressed", m[3])
		b.connect("pressed", self, "_on_mod", [m[0], b])
		mods_row.add_child(b)
		mod_btns[m[0]] = b
	_refresh_mods()

func _mod_tip(m: String) -> String:
	return {"speed": "Speed (click: faster, right-click: slower)", "nofail": "No Fail", "sudden_death": "Sudden Death",
		"hard_mode": "Hard Mode", "ghost": "Ghost", "chaos": "Chaos", "360": "360", "mirror_x": "Mirror",
		"flashlight": "Flashlight"}.get(m, m)

func _bar_style(c: Color) -> StyleBoxFlat:
	var sb := _flat(c, 3)
	sb.content_margin_top = 2 * k
	sb.content_margin_bottom = 2 * k
	return sb

func _dot_tex(px: int) -> ImageTexture:
	var img := Image.new()
	img.create(px, px, false, Image.FORMAT_RGBA8)
	img.lock()
	var r := px / 2.0
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(1, 1, 1, clamp(r - d, 0.0, 1.0)))
	img.unlock()
	var t := ImageTexture.new()
	t.create_from_image(img)
	return t

# --- the map grid (right) -------------------------------------------------------

class Card extends Control:
	var ui
	var song = null
	var index := -1
	var tex: TextureRect
	var over: Control
	var sel := false
	var hover := false

	func _init(owner_ui):
		ui = owner_ui
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		tex = TextureRect.new()
		tex.expand = true
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.mouse_filter = MOUSE_FILTER_IGNORE
		tex.material = owner_ui._round_mat(0.045)
		add_child(tex)
		# (the labels on top of the cover: a child drawn after it)
		over = Control.new()
		over.mouse_filter = MOUSE_FILTER_IGNORE
		over.connect("draw", self, "_draw_over")
		add_child(over)
		connect("mouse_entered", self, "_hover", [true])
		connect("mouse_exited", self, "_hover", [false])

	func _hover(on: bool):
		hover = on
		over.update()

	func update():
		.update()
		if over != null:
			over.update()

	func set_song(s, i: int):
		song = s
		index = i
		visible = s != null
		if s == null:
			return
		var t = ui.covers.tex_for(s)
		tex.texture = t
		update()

	func _gui_input(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT and song != null:
			ui._on_card(self)

	func _draw():
		if song == null:
			return
		tex.rect_size = rect_size
		over.rect_size = rect_size
		if tex.texture == null:
			draw_style_box(ui._flat(Color(1, 1, 1, 0.05), 6), Rect2(Vector2(), rect_size))

	func _draw_over():
		if song == null:
			return
		var k: float = ui.k
		var s := rect_size
		# the bottom shade with the text
		var h0 := s.y * 0.42
		over.draw_polygon(PoolVector2Array([Vector2(0, s.y - h0), Vector2(s.x, s.y - h0), Vector2(s.x, s.y), Vector2(0, s.y)]),
			PoolColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.88), Color(0, 0, 0, 0.88)]))
		var f: Dictionary = ui.f
		var x := 8.0 * k
		var w := s.x - 16 * k
		over.draw_string(f.card_t, Vector2(x, s.y - 30 * k), ui._fit(String(song.name), f.card_t, w), Color(1, 1, 1))
		over.draw_string(f.card_s, Vector2(x, s.y - 18 * k), ui._fit("Mapped by " + String(song.creator), f.card_s, w), Color(0.78, 0.78, 0.82))
		over.draw_string(f.card_s, Vector2(x, s.y - 7 * k), ui._fit("%s - %s" % [ui._diff_name(song), ui._len(song)], f.card_s, w), Color(0.86, 0.86, 0.9))
		# the pills
		var ranked: bool = ui._is_ranked(song)
		var pt := "RANKED" if ranked else "UNRANKED"
		var pw: float = f.pill.get_string_size(pt).x + 10 * k
		var pr := Rect2(6 * k, 6 * k, pw, 13 * k)
		over.draw_style_box(ui._flat(ui.RANKED if ranked else Color(0.09, 0.09, 0.11, 0.86), 3), pr)
		over.draw_string(f.pill, Vector2(pr.position.x + 5 * k, pr.position.y + 9.6 * k), pt, Color(1, 1, 1))
		var stars: float = song.star_rating_shown() # (at your speed)
		if stars > 0:
			var st := "%.2f" % stars
			var sw: float = f.pill.get_string_size(st).x + 20 * k
			var sr := Rect2(s.x - 6 * k - sw, 6 * k, sw, 13 * k)
			over.draw_style_box(ui._flat(Color(0.09, 0.09, 0.11, 0.86), 3), sr)
			_star(Vector2(sr.position.x + 8 * k, sr.position.y + 6.5 * k), 4.2 * k)
			over.draw_string(f.pill, Vector2(sr.position.x + 14 * k, sr.position.y + 9.6 * k), st, Color(1, 1, 1))
		# the edge: white when picked, the difficulty's colour otherwise
		var dc: Color = Globals.difficulty_colors.get(int(song.difficulty), Color(1, 1, 1))
		var edge := Color(1, 1, 1, 0.95) if sel else (Color(1, 1, 1, 0.35) if hover else Color(dc.r, dc.g, dc.b, 0.28))
		var sb: StyleBoxFlat = ui._flat(Color(0, 0, 0, 0), 6, edge, int(max(1, round((2.0 if sel else 1.0) * k))))
		sb.draw_center = false
		over.draw_style_box(sb, Rect2(Vector2(), s))

	func _star(c: Vector2, r: float):
		var pts := PoolVector2Array()
		for i in range(10):
			var a := deg2rad(-90 + 36 * i)
			var rr := r if i % 2 == 0 else r * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		over.draw_colored_polygon(pts, Color(1, 1, 1))

func _build_grid():
	grid = Control.new()
	grid.rect_clip_content = true
	grid.mouse_filter = MOUSE_FILTER_STOP
	grid.connect("gui_input", self, "_on_grid_input")
	add_child(grid)
	vbar = VScrollBar.new()
	vbar.add_stylebox_override("scroll", _flat(Color(1, 1, 1, 0.0), 3))
	vbar.add_stylebox_override("grabber", _flat(Color(1, 1, 1, 0.25), 3))
	vbar.add_stylebox_override("grabber_highlight", _flat(Color(1, 1, 1, 0.4), 3))
	vbar.add_stylebox_override("grabber_pressed", _flat(Color(1, 1, 1, 0.5), 3))
	vbar.connect("value_changed", self, "_on_vbar")
	add_child(vbar)

func _fit(t: String, font: Font, w: float) -> String:
	if font.get_string_size(t).x <= w:
		return t
	var lo := 0
	var hi := t.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if font.get_string_size(t.substr(0, mid) + "...").x <= w:
			lo = mid
		else:
			hi = mid - 1
	return t.substr(0, lo) + "..."

func _diff_name(s) -> String:
	var dn = s.custom_data.get("difficulty_name", null) if s.custom_data is Dictionary else null
	if dn != null and String(dn) != "":
		return String(dn)
	return {-1: "N/A", 0: "Easy", 1: "Medium", 2: "Hard", 3: "Logic", 4: "助"}.get(int(s.difficulty), "N/A")

func _len(s) -> String:
	var t := int(float(s.last_ms) / 1000.0)
	return "%02d:%02d" % [t / 60, t % 60]

func _is_ranked(s) -> bool:
	if list != null and list.has_method("canon_key") and "ranked_song_ids" in list:
		return list.ranked_song_ids.has(list.canon_key(String(s.id)))
	return false

# ------------------------------------------------------------------ layout

func _layout():
	var vs := rect_size
	k = max(0.6, vs.y / 720.0)
	var right_w: float = COLS * CARD * k + (COLS - 1) * GAP * k
	var gx: float = vs.x - right_w - 26 * k
	# the top bar
	top.rect_position = Vector2()
	top.rect_size = Vector2(vs.x, 46 * k)
	var me = top.get_node("Me")
	me.rect_position = Vector2(12 * k, 6 * k)
	me.rect_size = Vector2(220 * k, 34 * k)
	avatar.rect_position = Vector2()
	avatar.rect_size = Vector2(33, 33) * k
	name_l.rect_position = Vector2(41 * k, -3 * k)
	rp_l.rect_position = Vector2(41 * k, 17 * k)
	var x: float = vs.x - 14 * k
	search.rect_size = Vector2(146 * k, 28 * k)
	x -= search.rect_size.x
	search.rect_position = Vector2(x, 9 * k)
	x -= 8 * k
	for t in ["all", "collections", "multiplayer"]:
		var b: Button = tabs[t]
		var w: float = f.tab.get_string_size(b.text).x + 20 * k
		x -= w
		b.rect_position = Vector2(x, 6 * k)
		b.rect_size = Vector2(w, 34 * k)
		x -= 4 * k
	x -= 6 * k
	var names := ["layout", "bookmark_plus", "sort", "list", "cloud_down", "gear", "heart"]
	for n in names:
		var b: Button = top.get_node("Icon_" + n)
		x -= 36 * k
		b.rect_position = Vector2(x + 2 * k, 6 * k)
		b.rect_size = Vector2(34, 34) * k
		var ic = b.get_child(0)
		ic.rect_position = Vector2(6.5, 6.5) * k
		ic.rect_size = Vector2(21, 21) * k
	# the map grid
	grid.rect_position = Vector2(gx, 0)
	grid.rect_size = Vector2(right_w + 4 * k, vs.y)
	vbar.rect_position = Vector2(vs.x - 12 * k, 52 * k)
	vbar.rect_size = Vector2(5 * k, vs.y - 60 * k)
	_place_cards()
	# the left panel: everything centred in the space left of the grid
	var lw: float = gx - 20 * k
	left.rect_position = Vector2()
	left.rect_size = Vector2(lw, vs.y)
	var cx: float = lw * 0.5
	var cs: float = 214 * k
	var row_w: float = 300 * k
	var block_w: float = cs + 14 * k + row_w
	var bx: float = max(16 * k, cx - block_w / 2.0)
	cover.rect_position = Vector2(bx, 84 * k)
	cover.rect_size = Vector2(cs, cs)
	cover.rect_pivot_offset = Vector2(cs, cs) / 2
	cover.rect_rotation = -2.0
	var sh = left.get_node("CoverShadow")
	sh.rect_position = cover.rect_position
	sh.rect_size = cover.rect_size
	sh.rect_pivot_offset = cover.rect_pivot_offset
	sh.rect_rotation = cover.rect_rotation
	var rx: float = bx + cs + 14 * k
	board.rect_position = Vector2(rx, 85 * k)
	board.rect_size = Vector2(row_w, 4 * 42 * k)
	board_msg.rect_position = Vector2(rx, 140 * k)
	board_msg.rect_size = Vector2(row_w, 40 * k)
	pb_label.rect_position = Vector2(rx, 255 * k)
	pb_row.rect_position = Vector2(rx, 268 * k)
	pb_row.rect_size = Vector2(row_w, 40 * k)
	local_btn.rect_position = Vector2(rx, 314 * k)
	local_btn.rect_size = Vector2(row_w, 18 * k)
	title_l.rect_position = Vector2(8 * k, 363 * k)
	title_l.rect_size = Vector2(lw - 16 * k, 32 * k)
	diff_l.rect_position = Vector2(0, 395 * k)
	diff_l.rect_size = Vector2(lw, 22 * k)
	mapper_l.rect_position = Vector2(8 * k, 416 * k)
	mapper_l.rect_size = Vector2(lw - 16 * k, 24 * k)
	var sx0: float = cx - 128 * k
	var sx1: float = cx + 38 * k
	stats.status[0].rect_position = Vector2(sx0, 470 * k)
	stats.stars[0].rect_position = Vector2(sx1, 470 * k)
	stats.notes[0].rect_position = Vector2(sx0, 497 * k)
	stats.length[0].rect_position = Vector2(sx1, 497 * k)
	var py := 540 * k
	prev_btn.rect_position = Vector2(cx - 122 * k, py)
	prev_btn.rect_size = Vector2(18, 18) * k
	prev_btn.get_child(0).rect_position = Vector2(2, 2) * k
	prev_btn.get_child(0).rect_size = Vector2(14, 14) * k
	prev_t0.rect_position = Vector2(cx - 99 * k, py + 2 * k)
	prev_bar.rect_position = Vector2(cx - 66 * k, py + 1 * k)
	prev_bar.rect_size = Vector2(150 * k, 16 * k)
	prev_t1.rect_position = Vector2(cx + 94 * k, py + 2 * k)
	var by := 580 * k
	eye_btn.rect_position = Vector2(cx - 136 * k, by)
	eye_btn.rect_size = Vector2(46, 46) * k
	eye_btn.get_child(0).rect_position = Vector2(12, 12) * k
	eye_btn.get_child(0).rect_size = Vector2(22, 22) * k
	play_btn.rect_position = Vector2(cx - 84 * k, by)
	play_btn.rect_size = Vector2(167, 46) * k
	play_sub.rect_position = Vector2(0, 30 * k)
	play_sub.rect_size = Vector2(167 * k, 12 * k)
	save_btn.rect_position = Vector2(cx + 89 * k, by)
	save_btn.rect_size = Vector2(46, 46) * k
	save_btn.get_child(0).rect_position = Vector2(12, 12) * k
	save_btn.get_child(0).rect_size = Vector2(22, 22) * k
	var mw: float = 9 * 46 * k + 8 * 6 * k
	mods_row.rect_position = Vector2(cx - mw / 2, 638 * k)
	mods_row.rect_size = Vector2(mw, 46 * k)
	# the background cover
	bg_cover.rect_position = Vector2(-40 * k, -40 * k)
	bg_cover.rect_size = Vector2(lw + 160 * k, vs.y + 80 * k)
	bg_shade.update()
	if panels != null and panels.panel != null:
		panels.layout()

# ------------------------------------------------------------------ the grid's maps

func _on_list_changed(_a = null, _b = null, _c = null):
	call_deferred("_reload_maps")

func _reload_maps():
	if list == null:
		return
	if list.has_method("build_list"):
		list.build_list()
	_maps = list.disp.duplicate() if "disp" in list else []
	if _favs_only:
		var only := []
		for m in _maps:
			if Rhythia.is_favorite(m.id):
				only.append(m)
		_maps = only
	scroll = clamp(scroll, 0.0, _max_scroll())
	scroll_to = scroll
	_place_cards()

func _rows() -> int:
	return int(ceil(float(_maps.size()) / COLS))

func _cell() -> float:
	return (CARD + GAP) * k

func _max_scroll() -> float:
	return max(0.0, _rows() * _cell() + 56 * k - rect_size.y)

func _place_cards():
	if grid == null:
		return
	var cell := _cell()
	var need: int = int(ceil(rect_size.y / cell) + 2) * COLS
	while cards.size() < need:
		var c := Card.new(self)
		grid.add_child(c)
		cards.append(c)
	var first_row: int = int(floor(max(0.0, scroll - 52 * k) / cell))
	var top_y: float = 52 * k - scroll
	for i in cards.size():
		var c: Card = cards[i]
		var idx: int = first_row * COLS + i
		if i >= need or idx >= _maps.size():
			c.set_song(null, -1)
			continue
		var row := idx / COLS
		var col := idx % COLS
		c.rect_position = Vector2(col * cell, top_y + row * cell)
		c.rect_size = Vector2(CARD, CARD) * k
		if c.song != _maps[idx] or c.index != idx:
			c.set_song(_maps[idx], idx)
		var was: bool = c.sel
		c.sel = _maps[idx] == Rhythia.selected_song
		if c.tex.texture == null:
			c.tex.texture = covers.tex_for(_maps[idx])
		if was != c.sel or true:
			c.update()
	vbar.max_value = max(1.0, _max_scroll() + rect_size.y)
	vbar.page = rect_size.y
	vbar.visible = _max_scroll() > 0
	if abs(vbar.value - scroll) > 0.5:
		vbar.set_block_signals(true)
		vbar.value = scroll
		vbar.set_block_signals(false)

func _on_vbar(v: float):
	scroll = v
	scroll_to = v
	_place_cards()

var _drag_from := -1.0
var _drag_scroll := 0.0
var _dragged := false
func _on_grid_input(ev):
	if ev is InputEventMouseButton:
		if ev.button_index == BUTTON_WHEEL_DOWN and ev.pressed:
			scroll_to = clamp(scroll_to + _cell() * 0.75, 0.0, _max_scroll())
		elif ev.button_index == BUTTON_WHEEL_UP and ev.pressed:
			scroll_to = clamp(scroll_to - _cell() * 0.75, 0.0, _max_scroll())

var _hide_t := 0.0
func _process(delta: float):
	# (the classic menu shows its version labels again a frame after a page change)
	_hide_t += delta
	if visible and _hide_t > 0.2:
		_hide_t = 0.0
		var menu = get_parent()
		for n in CLASSIC_HIDE:
			var c = menu.get_node_or_null(n) if menu != null else null
			if c is CanvasItem and c.visible:
				c.visible = false
	if abs(scroll_to - scroll) > 0.5:
		scroll = lerp(scroll, scroll_to, min(1.0, delta * 14.0))
		_place_cards()
	_update_preview_bar()

func _on_cover_ready(song):
	for c in cards:
		if c.song == song:
			c.tex.texture = covers.tex_for(song)
			c.update()
	if song == Rhythia.selected_song:
		_set_cover(song)

func _on_card(c):
	if c.song == Rhythia.selected_song:
		_play()
		return
	Rhythia.select_song(c.song)

func _on_search(t: String):
	if list != null and list.has_method("update_search_text"):
		list.update_search_text(t)
		# (the list waits a moment after typing: then search_updated)
		get_tree().create_timer(0.3).connect("timeout", self, "_reload_maps")

# ------------------------------------------------------------------ the selected map

func _on_song(s = null):
	_sel = s
	for c in cards:
		var on: bool = c.song != null and c.song == s
		if on != c.sel:
			c.sel = on
			c.update()
	if s == null:
		title_l.text = "Pick a map"
		diff_l.text = ""
		mapper_l.text = ""
		return
	title_l.text = String(s.name)
	diff_l.text = "< %s >" % _diff_name(s)
	var dc: Color = Globals.difficulty_colors.get(int(s.difficulty), Color(1, 1, 1))
	diff_l.add_color_override("font_color", dc.darkened(0.35) if dc.v > 0.6 else dc.lightened(0.25))
	mapper_l.text = "Mapped by " + String(s.creator)
	var ranked := _is_ranked(s)
	stats.status[1].text = "Ranked" if ranked else "Unranked"
	var stars: float = s.star_rating_shown() # (at your speed)
	stats.stars[1].text = ("%.2f stars" % stars) if stars > 0 else "- stars"
	stats.notes[1].text = "%d notes" % int(s.note_count)
	stats.length[1].text = _len(s)
	_set_cover(s)
	_refresh_play()
	_load_board(s)
	_load_pb(s)

func _set_cover(s):
	var t = covers.tex_for(s) if s != null else null
	if t == null and s != null and s.has_cover:
		t = s.get_cover_thumb()
	cover.texture = t
	bg_cover.texture = _blurred(t)

# the background: the cover shrunk to a few pixels and stretched back (a soft blur)
var _blur_cache := {}
func _blurred(t: Texture) -> Texture:
	if t == null:
		return null
	if _blur_cache.has(t):
		return _blur_cache[t]
	var img: Image = t.get_data()
	if img == null or img.is_empty():
		return t
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.resize(12, 12, Image.INTERPOLATE_BILINEAR)
	img.resize(48, 48, Image.INTERPOLATE_CUBIC)
	var bt := ImageTexture.new()
	bt.create_from_image(img, Texture.FLAG_FILTER)
	if _blur_cache.size() > 20:
		_blur_cache.clear()
	_blur_cache[t] = bt
	return bt

func _refresh_play():
	var s = Rhythia.selected_song
	var ok: bool = Rhythia.offline_rp_rules_ok() if Rhythia.has_method("offline_rp_rules_ok") else true
	var stars: float = s.star_rating_cached() if s != null else -1.0
	play_btn.text = "PLAY" if ok else "PRACTICE"
	var speed: float = Rhythia.current_speed_multiplier() if Rhythia.has_method("current_speed_multiplier") else 1.0
	if ok and stars > 0:
		play_sub.text = "MAX %d RP" % int(round(preload("res://scripts/RhythiaPoints.gd").max_rp(stars, speed)))
	else:
		play_sub.text = ""
	play_btn.add_constant_override("hseparation", 0)
	# (the label sits under the button's text)
	play_btn.align = Button.ALIGN_CENTER

# the map's leaderboard: the first four and you
var _board_req: HTTPRequest
func _load_board(s):
	for c in board.get_children():
		c.queue_free()
	board_msg.text = "Loading the leaderboard..."
	board_msg.visible = true
	if _board_req != null and is_instance_valid(_board_req):
		_board_req.cancel_request()
		_board_req.queue_free()
	_board_req = HTTPRequest.new()
	_board_req.timeout = 12
	add_child(_board_req)
	_board_req.connect("request_completed", self, "_on_board", [_board_req, String(s.id)])
	if _board_req.request(SITE + "/savia-public/api/map/" + String(s.id).http_escape()) != OK:
		board_msg.text = "Couldn't load the leaderboard."

func _on_board(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, id: String):
	r.queue_free()
	if r != _board_req:
		return
	_board_req = null
	if Rhythia.selected_song == null or String(Rhythia.selected_song.id) != id:
		return
	if result != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 404):
		board_msg.text = "Couldn't load the leaderboard."
		return
	var rows := []
	if code == 200:
		var j = parse_json(body.get_string_from_utf8())
		if j is Dictionary and j.get("leaderboard") is Array:
			rows = j.leaderboard
	if code == 404:
		board_msg.text = "This map isn't ranked: no leaderboard."
		return
	if rows.empty():
		board_msg.text = "No passes yet. Be the first!"
		return
	board_msg.visible = false
	for i in min(4, rows.size()):
		if rows[i] is Dictionary:
			board.add_child(_score_row(rows[i]))

func _score_row(e: Dictionary) -> Control:
	var row := Control.new()
	row.rect_min_size = Vector2(300, 40) * k
	row.mouse_filter = MOUSE_FILTER_PASS
	row.set_meta("e", e)
	row.connect("draw", self, "_draw_row", [row])
	if String(e.get("avatar_url", "")) != "":
		_load_pic(String(e.avatar_url), row)
	return row

func _draw_row(row: Control):
	var e: Dictionary = row.get_meta("e")
	var s := row.rect_size
	row.draw_style_box(_flat(PANEL, 4), Rect2(Vector2(), s))
	var rank := int(e.get("rank", 0))
	var rc := RANK_GOLD if rank == 1 else (Color("#d9d9e0") if rank == 2 else (Color("#d08a4f") if rank == 3 else Color("#d9d9e0")))
	var rt := "#%d" % rank
	row.draw_string(f.rank, Vector2(10 * k, s.y / 2 + 4 * k), rt, rc)
	var ax: float = 10 * k + max(f.rank.get_string_size(rt).x, 18 * k) + 6 * k
	var c := Vector2(ax + 11 * k, s.y / 2)
	var pic = row.get_meta("pic") if row.has_meta("pic") else null
	if pic != null:
		row.draw_texture_rect(pic, Rect2(c - Vector2(11, 11) * k, Vector2(22, 22) * k), false)
	else:
		row.draw_circle(c, 11 * k, Color(1, 1, 1, 0.12))
	var nm := Globals.s(e.get("name", "Player #%d" % int(e.get("number", 0))))
	row.draw_string(f.rowname, Vector2(ax + 28 * k, s.y / 2 - 1 * k), _fit(nm, f.rowname, s.x * 0.55), TEXT)
	var acc := float(e.get("accuracy", 0.0))
	if acc <= 1.0:
		acc *= 100.0
	var rp := float(e.get("sp", e.get("rp", 0)))
	var sub := "%drp  •  %.2f%%  •  %sx" % [int(round(rp)), acc, String(stepify(float(e.get("speed", 1.0)), 0.01))]
	row.draw_string(f.rowsub, Vector2(ax + 28 * k, s.y / 2 + 11 * k), sub, Color("#b9b8c0"))
	var g: Array = ScoreHistory.grade_for(acc / 100.0, false)
	var gw: float = f.grade.get_string_size(g[0]).x
	row.draw_string(f.grade, Vector2(s.x - 14 * k - gw, s.y / 2 + 6 * k), g[0], _grade_col(g[0]))

func _grade_col(g: String) -> Color:
	return {"SS": Color("#ffd36b"), "S": Color("#6f8dff"), "A": Color("#5fd38a"), "B": Color("#a9d36b"), "C": Color("#d3c36b"), "D": Color("#d39a6b"), "F": Color("#ff6b6b")}.get(g, TEXT)

var _pics := {}
func _load_pic(url: String, row: Control):
	if url.begins_with("/"):
		url = SITE + url
	if _pics.has(url):
		row.set_meta("pic", _pics[url])
		row.update()
		return
	var r := HTTPRequest.new()
	r.timeout = 10
	add_child(r)
	r.connect("request_completed", self, "_on_pic", [r, url, row])
	if r.request(url) != OK:
		r.queue_free()

func _on_pic(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, url: String, row):
	r.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var img := Image.new()
	if img.load_png_from_buffer(body) != OK and img.load_jpg_from_buffer(body) != OK and img.load_webp_from_buffer(body) != OK:
		return
	var t := _round_tex(img, 128)
	_pics[url] = t
	if is_instance_valid(row):
		row.set_meta("pic", t)
		row.update()

# a picture made round (smooth edge), sharp when drawn small or large
static func _round_tex(img: Image, px: int) -> ImageTexture:
	var im: Image = img.duplicate()
	im.convert(Image.FORMAT_RGBA8)
	# square, from the middle
	var side: int = min(im.get_width(), im.get_height())
	if im.get_width() != im.get_height():
		im = im.get_rect(Rect2((im.get_width() - side) / 2, (im.get_height() - side) / 2, side, side))
	im.resize(px, px, Image.INTERPOLATE_LANCZOS if side > px else Image.INTERPOLATE_CUBIC)
	var c := (px - 1) / 2.0
	var rad := px / 2.0
	im.lock()
	for y in px:
		for x in px:
			var d := Vector2(x - c, y - c).length()
			if d > rad - 1.5:
				var cc := im.get_pixel(x, y)
				cc.a *= clamp((rad - d) / 1.5, 0.0, 1.0)
				im.set_pixel(x, y, cc)
	im.unlock()
	var t := ImageTexture.new()
	t.create_from_image(im, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	return t

func _load_pb(s):
	for c in pb_row.get_children():
		c.queue_free()
	var entries: Array = ScoreHistory.rank(ScoreHistory.load_entries(String(s.id)))
	pb_label.visible = not entries.empty()
	pb_row.visible = not entries.empty()
	if entries.empty():
		return
	var e: Dictionary = entries[0]
	var acc := ScoreHistory.accuracy(e)
	var me := {"rank": 0, "name": ScoreHistory.player_name(), "accuracy": acc * 100.0, "speed": float(e.get("speed", e.get("s", 1.0))), "sp": 0}
	var row := _score_row(me)
	row.rect_size = Vector2(300, 40) * k
	row.disconnect("draw", self, "_draw_row")
	row.connect("draw", self, "_draw_pb_row", [row])
	pb_row.add_child(row)

func _draw_pb_row(row: Control):
	var e: Dictionary = row.get_meta("e")
	var s := row.rect_size
	row.draw_style_box(_flat(PANEL, 4), Rect2(Vector2(), s))
	row.draw_circle(Vector2(20 * k, s.y / 2), 11 * k, Color(1, 1, 1, 0.12))
	row.draw_string(f.rowname, Vector2(38 * k, s.y / 2 - 1 * k), _fit(String(e.name), f.rowname, s.x * 0.55), TEXT)
	row.draw_string(f.rowsub, Vector2(38 * k, s.y / 2 + 11 * k), "%.2f%%  •  %sx" % [float(e.accuracy), String(stepify(float(e.speed), 0.01))], Color("#b9b8c0"))
	var g: Array = ScoreHistory.grade_for(float(e.accuracy) / 100.0, false)
	var gw: float = f.grade.get_string_size(g[0]).x
	row.draw_string(f.grade, Vector2(s.x - 14 * k - gw, s.y / 2 + 6 * k), g[0], _grade_col(g[0]))

# ------------------------------------------------------------------ you (top left)

var _me_req: HTTPRequest
func _load_me():
	var lm = get_node_or_null("/root/LobbyManager")
	var nm: String = ScoreHistory.player_name()
	name_l.text = nm if nm != "" else "You"
	var rp: float = 0.0
	if rp_l.text == "":
		rp_l.text = "- SP"
	var n: int = int(lm.my_player_number) if lm != null else -1
	if n <= 0:
		get_tree().create_timer(5.0).connect("timeout", self, "_load_me")
		return
	_me_req = HTTPRequest.new()
	_me_req.timeout = 12
	add_child(_me_req)
	_me_req.connect("request_completed", self, "_on_me", [_me_req, rp])
	_me_req.request(SITE + "/savia-public/api/player/%d" % n)

func _on_me(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, rp: float):
	r.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var p = parse_json(body.get_string_from_utf8())
	if not (p is Dictionary):
		return
	name_l.text = Globals.s(p.get("name", name_l.text))
	# (the server's SP and your place on the SP leaderboard)
	var rank = p.get("sp_rank", null)
	rp_l.text = "%d SP" % int(round(float(p.get("sp", 0)))) + (("  #%s" % String(rank)) if rank != null else "")
	var av := Globals.s(p.get("avatar_url", ""))
	if av != "":
		var holder := Control.new()
		holder.visible = false
		add_child(holder)
		holder.connect("draw", self, "_noop")
		_load_pic(av, holder)
		yield(get_tree().create_timer(3.0), "timeout")
		if is_instance_valid(holder) and holder.has_meta("pic"):
			avatar.texture = holder.get_meta("pic")
		if is_instance_valid(holder):
			holder.queue_free()

func _noop():
	pass

func _on_me_input(ev):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		panels.open_profile()

# ------------------------------------------------------------------ the preview

func _player():
	var ps = Rhythia.menu_node("Main/Maps/Results/Results/RS/H1/Info/PlaySong")
	if ps == null:
		ps = _find_script(Rhythia.menu_node(), "PlaySong.gd")
	return ps

func _find_script(n: Node, file: String):
	if n == null:
		return null
	var s = n.get_script()
	if s != null and String(s.resource_path).ends_with(file):
		return n
	for c in n.get_children():
		var r = _find_script(c, file)
		if r != null:
			return r
	return null

var _ps = null
var _seeking := false
func _update_preview_bar():
	if _ps == null or not is_instance_valid(_ps):
		_ps = _player()
		if _ps == null:
			return
	var a: AudioStreamPlayer = _ps.get_node_or_null("Song")
	if a == null:
		return
	var len_s: float = a.stream.get_length() if a.stream != null else 0.0
	var pos: float = a.get_playback_position() if a.playing else 0.0
	prev_btn.get_child(0).set_icon("pause" if a.playing else "play")
	if len_s > 0:
		_seeking = true
		prev_bar.value = pos / len_s
		_seeking = false
		prev_t0.text = "%02d:%02d" % [int(pos) / 60, int(pos) % 60]
		prev_t1.text = "%02d:%02d" % [int(len_s) / 60, int(len_s) % 60]

func _toggle_preview():
	if _ps == null:
		_ps = _player()
	if _ps != null:
		_ps._pressed()

func _on_seek(v: float):
	if _seeking or _ps == null:
		return
	var a: AudioStreamPlayer = _ps.get_node_or_null("Song")
	if a != null and a.stream != null and a.playing:
		a.seek(v * a.stream.get_length())

# ------------------------------------------------------------------ mods

func _on_mod(m: String, b: Button):
	match m:
		"speed":
			var lvls := [Globals.SPEED_MMM, Globals.SPEED_MM, Globals.SPEED_M, Globals.SPEED_NORMAL, Globals.SPEED_P, Globals.SPEED_PP, Globals.SPEED_PPP]
			var i: int = lvls.find(Rhythia.mod_speed_level)
			var right: bool = Input.is_mouse_button_pressed(BUTTON_RIGHT) or Input.is_key_pressed(KEY_SHIFT)
			i = (i + (-1 if right else 1) + lvls.size()) % lvls.size() if i >= 0 else 3
			Rhythia.mod_speed_level = lvls[i]
			if Rhythia.has_signal("speed_mod_changed"):
				Rhythia.emit_signal("speed_mod_changed")
		_:
			Rhythia.set("mod_" + m, b.pressed)
	_refresh_mods()
	_refresh_play()

func _refresh_mods(_a = null):
	# (the stars are at your speed: shown again)
	var sel = Rhythia.selected_song
	if sel != null and stats.has("stars"):
		var st: float = sel.star_rating_shown()
		stats.stars[1].text = ("%.2f stars" % st) if st > 0 else "- stars"
	for c in cards:
		if is_instance_valid(c):
			c.update()
			for ch in c.get_children():
				if ch is Control:
					ch.update()
	for m in mod_btns:
		var b: Button = mod_btns[m]
		var tint: Color = b.get_meta("tint")
		var on := false
		if m == "speed":
			on = Rhythia.mod_speed_level != Globals.SPEED_NORMAL
			b.text = _speed_text()
		else:
			on = Rhythia.get("mod_" + m) == true
			b.pressed = on
		var bgc := Color(tint.r, tint.g, tint.b, 0.16 if on else 0.07)
		var edge := Color(tint.r, tint.g, tint.b, 0.9 if on else 0.0)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := _flat(bgc if st != "hover" else Color(tint.r, tint.g, tint.b, bgc.a + 0.06), 5, edge, int(round(2 * k)) if on else 0)
			b.add_stylebox_override(st, sb)

func _speed_text() -> String:
	var m: float = Globals.speed_multi[Rhythia.mod_speed_level] if Rhythia.mod_speed_level < Globals.speed_multi.size() else 1.0
	if abs(m - 1.0) < 0.001:
		return "S"
	return ("S+" if m > 1.0 else "S-")

# ------------------------------------------------------------------ actions

func _play():
	if Rhythia.selected_song == null:
		return
	var run = Rhythia.menu_node("Main/Maps/Results/Results/RS/H1/Info/Run")
	if run != null and run.has_method("_pressed"):
		run._pressed()

func _watch_auto():
	if Rhythia.selected_song == null:
		return
	Rhythia.replaying = true
	Rhythia.replay = Replay.new()
	Rhythia.replay_path = "user://__autoplay__"
	var menu = Rhythia.menu_node()
	if menu != null and "black_fade_target" in menu:
		menu.black_fade_target = true
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

func _on_tab(t: String):
	match t:
		"multiplayer":
			panels.open_page("Multiplayer", "Browse, create, or join a multiplayer lobby", "Online")
		"collections":
			panels.open_collections()
		"all":
			search.text = ""
			_on_search("")

var _favs_only := false
func _toggle_favs():
	_favs_only = not _favs_only
	var b: Button = top.get_node("Icon_heart")
	b.get_child(0).filled = _favs_only
	b.get_child(0).update()
	scroll = 0.0
	scroll_to = 0.0
	_reload_maps()

func _open_settings():
	panels.open_settings()

func _open_workshop():
	panels.open_page("Online Workshop", "Browse, download and install maps, skins and skin assets", "MapBrowser")

func _open_leaderboard():
	panels.open_leaderboard()

func _open_filters():
	panels.open_filters()

func _open_collection_add():
	var b = _find_script(Rhythia.menu_node(), "MapFolderAdd.gd")
	if b != null and b is MenuButton:
		if b.has_method("_build"):
			b._build()
		var pop: PopupMenu = b.get_popup()
		pop.popup(Rect2(get_global_mouse_position(), Vector2(1, 1)))

func _open_spectate():
	var sb = Rhythia.menu_node("Sidebar")
	if sb != null and sb.get("spectate") != null:
		sb.spectate.open()

func _open_classic_maps():
	_open_classic_page("Maps")

# a page of the classic menu, with a button back here
func _open_classic_page(page: String):
	var menu = Rhythia.menu_node()
	var sb = Rhythia.menu_node("Sidebar")
	var p = Rhythia.menu_node("Main/" + page)
	if p == null and page == "MapBrowser":
		p = _find_named(Rhythia.menu_node("Main"), "MapBrowser")
	visible = false
	_classic(true)
	if sb != null and p != null and sb.has_method("press_page"):
		sb.press_page(p)
	if menu != null and not menu.has_node("ModernBack"):
		var b := _button(Color(0.1, 0.1, 0.13, 0.92), Color(0.18, 0.18, 0.22, 0.95), 8)
		b.name = "ModernBack"
		b.text = "  Back to Modern UI  "
		b.add_font_override("font", f.local)
		b.add_color_override("font_color", TEXT)
		b.anchor_left = 0.5
		b.anchor_right = 0.5
		b.margin_left = -75 * k
		b.margin_right = 75 * k
		b.margin_top = 6 * k
		b.margin_bottom = 32 * k
		b.connect("pressed", self, "_back_from_classic")
		menu.add_child(b)

func _find_named(n: Node, nm: String):
	if n == null:
		return null
	for c in n.get_children():
		if c.name == nm:
			return c
		var r = _find_named(c, nm)
		if r != null:
			return r
	return null

func _back_from_classic():
	var menu = Rhythia.menu_node()
	var b = menu.get_node_or_null("ModernBack") if menu != null else null
	if b != null:
		b.queue_free()
	var sb = Rhythia.menu_node("Sidebar")
	if sb != null and sb.has_method("press"):
		sb.press(0, true)
	visible = true
	_classic(false)
	_reload_maps()
	_on_song(Rhythia.selected_song)
