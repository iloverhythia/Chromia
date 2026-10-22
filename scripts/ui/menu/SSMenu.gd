extends Control

# Sound Space Mode's map screen, made to look like classic Sound Space's:
#
# - a 3x3 grid of tiles on black with a "1/29" page counter, arrows, a red
#   BACK and a magenta REPLAY on the sides, and your player card and a search
#   button on top. The first tiles are the difficulties (EASY, MEDIUM, HARD,
#   LOGIC? and the white Tasukete one) which filter the maps; the rest are the
#   maps, coloured by difficulty.
# - tapping a map opens its screen over the dimmed grid: the modifiers in a
#   magenta frame, the map's info (mapper, difficulty, length, start from),
#   Favorite? / Hide, your best, PLAY and VS, and your top runs on the right.
#
# It only shows while Sound Space Mode is on, on top of the normal map page,
# and uses the normal map list (search, filters, favourites) underneath.
# menu2.gd installs it.

const ScoreHistory = preload("res://scripts/ScoreHistory.gd")
const PlayerLevel = preload("res://scripts/PlayerLevel.gd")
const PIXEL := "res://assets/font/PressStart2P/PressStart2P-Regular.ttf"
const BOLD := "res://assets/font/Lato/Lato-Black.ttf"
const STAGE := Vector2(1280, 720)
const PER_PAGE := 9

# [border, fill] per difficulty, sampled from Sound Space
const DIFF_COLORS := {
	Globals.DIFF_EASY: [Color8(116, 251, 78), Color8(47, 108, 28)],
	Globals.DIFF_MEDIUM: [Color8(245, 180, 63), Color8(98, 60, 16)],
	Globals.DIFF_HARD: [Color8(235, 50, 37), Color8(108, 18, 10)],
	Globals.DIFF_LOGIC: [Color8(238, 51, 248), Color8(96, 15, 109)],
	Globals.DIFF_AMOGUS: [Color8(239, 238, 229), Color8(100, 101, 96)],
	Globals.DIFF_UNKNOWN: [Color8(101, 216, 250), Color8(27, 72, 100)],
}
const CATEGORIES := [
	[Globals.DIFF_EASY, "EASY"], [Globals.DIFF_MEDIUM, "MEDIUM"], [Globals.DIFF_HARD, "HARD"],
	[Globals.DIFF_LOGIC, "LOGIC?"], [Globals.DIFF_AMOGUS, "包"],
]
const ALL_DIFFS := [Globals.DIFF_UNKNOWN, Globals.DIFF_EASY, Globals.DIFF_MEDIUM, Globals.DIFF_HARD, Globals.DIFF_LOGIC, Globals.DIFF_AMOGUS]

const RED := Color8(225, 55, 45)
const MAGENTA := Color8(255, 40, 200)
const ORANGE := Color8(245, 140, 40)
const YELLOW := Color8(255, 230, 40)
const BLUE := Color8(40, 190, 255)
const PINK := Color8(255, 60, 170)
const CYAN := Color8(0, 220, 255)
const GREEN := Color8(40, 245, 40)

var menu: Node
var list: Node
var maps: Control
var stage: Control
var grid_view: Control
var song_view: Control
var tile_box: Control
var page_label: Label
var prev_btn: Control
var next_btn: Control
var search_edit: LineEdit
var page := 0
var _song = null
var _built_online := false
var _fonts := {}
var _was_visible := false

static func install(menu_node: Node):
	var main = menu_node.get_node_or_null("Main")
	if main == null or main.has_node("SSMenu"):
		return
	var n = load("res://scripts/ui/menu/SSMenu.gd").new()
	n.name = "SSMenu"
	n.menu = menu_node
	main.add_child(n)
	var mp = main.get_node_or_null("Maps")
	if mp:
		main.move_child(n, mp.get_index() + 1)

func _ready():
	anchor_right = 1
	anchor_bottom = 1
	margin_right = 0
	margin_bottom = 0
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	maps = get_parent().get_node_or_null("Maps")
	list = get_parent().get_node_or_null("Maps/MapRegistry/S/VBoxContainer")
	if list and list.has_signal("search_updated"):
		list.connect("search_updated", self, "_on_search_updated")
	stage = Control.new()
	stage.rect_size = STAGE
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(stage)
	_build_grid_view()

func font(path: String, size: int, outline: int = 0, outline_color: Color = Color(0, 0, 0)) -> DynamicFont:
	var key := "%s|%d|%d|%s" % [path, size, outline, outline_color.to_html()]
	if _fonts.has(key):
		return _fonts[key]
	var f := DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.outline_size = outline
	f.outline_color = outline_color
	if path == BOLD:
		# the Tasukete tile's 包 isn't in Lato
		var jp = load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf")
		if jp:
			f.add_fallback(jp)
	_fonts[key] = f
	return f

func label(parent: Node, text: String, f: Font, col: Color, pos: Vector2, size: Vector2, align: int = Label.ALIGN_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.add_color_override("font_outline_modulate", Color(1, 1, 1)) # use the font's own outline colour
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	l.rect_position = pos
	l.rect_size = size
	l.align = align
	l.valign = Label.VALIGN_CENTER
	l.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

# shortens text with "..." to fit a width (like Sound Space's long titles)
func fit(text: String, f: Font, w: float) -> String:
	if f.get_string_size(text).x <= w:
		return text
	var t := text
	while t.length() > 1 and f.get_string_size(t + "...").x > w:
		t = t.substr(0, t.length() - 1)
	return t.strip_edges() + "..."

func _process(_d):
	var want: bool = bool(Rhythia.get("sound_space_mode")) and maps != null and maps.visible
	if want != visible:
		visible = want
	if visible and not _was_visible:
		_refresh()
	_was_visible = visible
	if not visible:
		return
	# centred on the whole window (not just the part right of the sidebar)
	var vp: Vector2 = get_viewport_rect().size
	var k: float = min(vp.x / STAGE.x, vp.y / STAGE.y)
	var ps: float = max(get_global_transform().get_scale().x, 0.001)
	stage.rect_scale = Vector2(k, k) / ps
	stage.rect_global_position = ((vp - STAGE * k) / 2.0).floor()

func _gui_input(e):
	if e is InputEventMouseButton and e.pressed and (e.button_index == BUTTON_WHEEL_DOWN or e.button_index == BUTTON_WHEEL_UP) and song_view == null:
		_turn(1 if e.button_index == BUTTON_WHEEL_DOWN else -1)
		accept_event()

func _unhandled_key_input(e):
	if not visible or not e.pressed:
		return
	if e.scancode == KEY_ESCAPE and song_view != null:
		_close_song()
		get_tree().set_input_as_handled()
	elif song_view == null and e.scancode in [KEY_RIGHT, KEY_LEFT]:
		_turn(1 if e.scancode == KEY_RIGHT else -1)
		get_tree().set_input_as_handled()

# --- the map grid -------------------------------------------------------------

func _build_grid_view():
	grid_view = Control.new()
	grid_view.rect_size = STAGE
	grid_view.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(grid_view)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.rect_position = Vector2(-2000, -2000)
	bg.rect_size = STAGE + Vector2(4000, 4000)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	grid_view.add_child(bg)

	var card := PlayerCard.new()
	card.ui = self
	card.rect_position = Vector2(440, 14)
	card.rect_size = Vector2(380, 96)
	card.connect("clicked", self, "_on_card")
	grid_view.add_child(card)

	var sb := Clickable.new()
	sb.kind = "search"
	sb.rect_position = Vector2(850, 26)
	sb.rect_size = Vector2(74, 70)
	sb.connect("clicked", self, "_toggle_search")
	grid_view.add_child(sb)
	search_edit = LineEdit.new()
	search_edit.rect_position = Vector2(460, 118)
	search_edit.rect_size = Vector2(360, 34)
	search_edit.placeholder_text = "Search maps"
	search_edit.add_font_override("font", font(BOLD, 18))
	search_edit.visible = false
	search_edit.connect("text_changed", self, "_on_search_text")
	grid_view.add_child(search_edit)

	page_label = label(grid_view, "1/1", font(PIXEL, 34, 2, Color(0.25, 0.25, 0.25)), Color8(225, 225, 225), Vector2(440, 140), Vector2(400, 44), Label.ALIGN_CENTER)

	var frame := Frame.new()
	frame.rect_position = Vector2(412, 188)
	frame.rect_size = Vector2(456, 456)
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	grid_view.add_child(frame)
	tile_box = Control.new()
	tile_box.rect_position = Vector2(412, 188)
	tile_box.rect_size = Vector2(456, 456)
	tile_box.mouse_filter = MOUSE_FILTER_IGNORE
	grid_view.add_child(tile_box)

	next_btn = _text_button(grid_view, ">", font(PIXEL, 40), ORANGE, Vector2(880, 386), Vector2(56, 60), "_next")
	prev_btn = _text_button(grid_view, "<", font(PIXEL, 40), ORANGE, Vector2(344, 386), Vector2(56, 60), "_prev")

	# BACK (red, sideways) and REPLAY (magenta, sideways), like Sound Space
	var back := _side_word("BACK", RED, Vector2(236, 416), -90.0, "_on_back")
	var line := ColorRect.new()
	line.color = Color8(220, 220, 220)
	line.rect_position = Vector2(300, 330)
	line.rect_size = Vector2(5, 180)
	line.mouse_filter = MOUSE_FILTER_IGNORE
	grid_view.add_child(line)
	back.hint_tooltip = "Main menu"
	var rep := _side_word("REPLAY", MAGENTA, Vector2(1044, 416), 90.0, "_on_replay")
	rep.hint_tooltip = "Watch a replay (.sspre)"
	var dash := Dashed.new()
	dash.rect_position = Vector2(978, 300)
	dash.rect_size = Vector2(5, 240)
	dash.mouse_filter = MOUSE_FILTER_IGNORE
	grid_view.add_child(dash)

func _text_button(parent: Node, text: String, f: Font, col: Color, pos: Vector2, size: Vector2, method: String) -> Control:
	var b := Clickable.new()
	b.rect_position = pos
	b.rect_size = size
	parent.add_child(b)
	label(b, text, f, col, Vector2.ZERO, size, Label.ALIGN_CENTER)
	b.connect("clicked", self, method)
	return b

func _side_word(text: String, col: Color, center: Vector2, deg: float, method: String) -> Control:
	var f := font(PIXEL, 50, 3, col.darkened(0.55))
	var w: float = f.get_string_size(text).x + 20
	var b := Clickable.new()
	b.rect_size = Vector2(w, 70)
	b.rect_pivot_offset = b.rect_size / 2
	b.rect_position = center - b.rect_size / 2
	b.rect_rotation = deg
	grid_view.add_child(b)
	label(b, text, f, col, Vector2.ZERO, b.rect_size, Label.ALIGN_CENTER)
	b.connect("clicked", self, method)
	return b

func _items() -> Array:
	var out := []
	for c in CATEGORIES:
		out.append({"cat": c[0], "text": c[1]})
	if list != null:
		for s in list.disp:
			out.append({"song": s})
	return out

func _active_filter() -> int:
	if list == null:
		return -99
	var f: Array = list.difficulty_filter
	if f.size() == 1:
		return int(f[0])
	return -99

func _refresh():
	if tile_box == null:
		return
	var items := _items()
	var pages: int = max(1, int(ceil(items.size() / float(PER_PAGE))))
	page = int(clamp(page, 0, pages - 1))
	page_label.text = "%d/%d" % [page + 1, pages]
	prev_btn.visible = page > 0
	next_btn.visible = page < pages - 1
	for c in tile_box.get_children():
		c.queue_free()
	var active := _active_filter()
	var size := 142.0
	var gap := 7.0
	for i in range(PER_PAGE):
		var idx := page * PER_PAGE + i
		if idx >= items.size():
			break
		var it: Dictionary = items[idx]
		var t := Tile.new()
		t.ui = self
		t.rect_position = Vector2(8 + (i % 3) * (size + gap), 8 + (i / 3) * (size + gap))
		t.rect_size = Vector2(size, size)
		if it.has("cat"):
			t.diff = it.cat
			t.dim = active != -99 and active != it.cat
			t.lit = active == it.cat
		else:
			t.song = it.song
			t.diff = it.song.difficulty if DIFF_COLORS.has(it.song.difficulty) else Globals.DIFF_UNKNOWN
		tile_box.add_child(t)
		t.setup(it.get("text", ""))
		t.connect("clicked", self, "_on_tile", [it])

func _turn(d: int):
	page += d
	_refresh()

func _next():
	_turn(1)

func _prev():
	_turn(-1)

func _on_tile(it: Dictionary):
	if it.has("cat"):
		if list == null:
			return
		if _active_filter() == it.cat:
			list.update_search_dfil(ALL_DIFFS.duplicate())
		else:
			list.update_search_dfil([it.cat])
		page = 0
		_refresh()
	else:
		_open_song(it.song)

func _on_search_updated():
	if visible:
		call_deferred("_refresh")

func _toggle_search():
	search_edit.visible = not search_edit.visible
	if search_edit.visible:
		search_edit.grab_focus()
	elif search_edit.text != "":
		search_edit.text = ""
		_on_search_text("")

func _on_search_text(t: String):
	if list:
		list.update_search_text(t)
		page = 0
		# the list rebuilds after a short pause
		get_tree().create_timer(0.3).connect("timeout", self, "_refresh")

# BACK: to Sound Space Mode's main menu, like Sound Space
func _on_back():
	if song_view != null:
		_close_song()
		return
	var hub = menu.get_node_or_null("SSHub")
	if hub:
		hub.open()

func _on_card():
	if Rhythia.discord_user.has("id"):
		return
	var sb = menu.get_node_or_null("Sidebar")
	var prof = menu.get_node_or_null("Main/Profile")
	if sb and prof and sb.has_method("press_page"):
		sb.press_page(prof)

func _on_replay():
	Globals.file_sel.open_file(self, "_on_replay_picked", PoolStringArray(["*.sspre ; Replays"]), false, Globals.p("user://replays"))

func _on_replay_picked(path):
	if typeof(path) == TYPE_STRING_ARRAY or typeof(path) == TYPE_ARRAY:
		path = path[0] if path.size() > 0 else ""
	path = String(path)
	if path == "" or path.get_extension() != "sspre":
		return
	var run = menu.get_node_or_null("Main/Maps/Results/Results/RS/H1/Info/Run")
	if run and run.has_method("files_dropped"):
		run.files_dropped(PoolStringArray([path]), 0)

# --- the map's screen ---------------------------------------------------------

func _open_song(s):
	_song = s
	if s != Rhythia.selected_song:
		Rhythia.select_song(s)
	_build_song_view()

func _close_song():
	if song_view != null:
		song_view.queue_free()
		song_view = null
	_song = null

func _build_song_view():
	if song_view != null:
		song_view.queue_free()
	var s = _song
	_built_online = s.is_online
	song_view = Control.new()
	song_view.rect_size = STAGE
	song_view.rect_position.x = -30 # balanced on screen
	song_view.mouse_filter = MOUSE_FILTER_STOP
	stage.add_child(song_view)
	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.72)
	dimmer.rect_position = Vector2(-2000, -2000)
	dimmer.rect_size = STAGE + Vector2(4000, 4000)
	dimmer.mouse_filter = MOUSE_FILTER_IGNORE
	song_view.add_child(dimmer)
	var cols: Array = DIFF_COLORS[s.difficulty if DIFF_COLORS.has(s.difficulty) else Globals.DIFF_UNKNOWN]

	# left: modifiers
	label(song_view, "MODIFIERS", font(PIXEL, 34, 3, Color(0.3, 0, 0.25)), MAGENTA, Vector2(70, 70), Vector2(420, 50), Label.ALIGN_CENTER)
	var mods_node = menu.get_node_or_null("Main/Maps/Results/Results/RS/H2/Mods")
	if mods_node:
		var mp = load("res://scripts/ui/menu/SSModPanel.gd").make_standalone(mods_node, 2, 3, 340)
		mp.rect_position = Vector2(110, 130)
		song_view.add_child(mp)
	var speed: float = 1.0
	if Rhythia.has_method("current_speed_multiplier"):
		speed = float(Rhythia.current_speed_multiplier())
	var spd := label(song_view, "SPEED x%s" % _num(speed), font(PIXEL, 26, 2, Color(0.3, 0.25, 0)), YELLOW, Vector2(70, 640), Vector2(420, 40), Label.ALIGN_CENTER)
	spd.set_meta("speed_label", true)
	song_view.set_meta("speed_label", spd)

	# top buttons
	var fav := Pill.new()
	fav.rect_position = Vector2(700, 30)
	fav.rect_size = Vector2(250, 54)
	fav.color = ORANGE
	fav.text_color = ORANGE.lightened(0.15)
	fav.font = font(BOLD, 30, 2, Color(0.2, 0.1, 0))
	fav.text = "Favorited!" if Rhythia.is_favorite(s.id) else "Favorite?"
	fav.connect("clicked", self, "_on_favorite", [fav])
	song_view.add_child(fav)
	var hide := Pill.new()
	hide.rect_position = Vector2(966, 24)
	hide.rect_size = Vector2(150, 54)
	hide.color = CYAN
	hide.text_color = CYAN
	hide.font = font(BOLD, 30, 2, Color(0, 0.15, 0.2))
	hide.text = "Hide"
	hide.connect("clicked", self, "_close_song")
	song_view.add_child(hide)

	# cover and info
	var cover := Cover.new()
	cover.ui = self
	cover.song = s
	cover.rect_position = Vector2(530, 108)
	cover.rect_size = Vector2(150, 150)
	song_view.add_child(cover)
	var x := 700.0
	var tf := font(BOLD, 24, 2, Color(0.25, 0.2, 0))
	label(song_view, fit(s.name, tf, 430), tf, YELLOW, Vector2(x, 100), Vector2(430, 34))
	var y := 138.0
	_kv(Vector2(x, y), "Mapper: ", s.creator if s.creator != "" else "?", PINK)
	y += 34
	label(song_view, "Difficulty: ", font(BOLD, 22, 2, Color(0, 0.1, 0.2)), BLUE, Vector2(x, y), Vector2(140, 30))
	var dx := x + 136
	for c in CATEGORIES:
		var sq := DiffSquare.new()
		sq.color = DIFF_COLORS[c[0]][0]
		sq.on = s.difficulty == c[0]
		sq.rect_position = Vector2(dx, y + 3)
		sq.rect_size = Vector2(24, 24)
		song_view.add_child(sq)
		dx += 30
	y += 34
	_kv(Vector2(x, y), "Length: ", _time(s.last_ms), Color(1, 1, 1))
	label(song_view, "Start From:", font(BOLD, 22, 2, Color(0, 0.1, 0.2)), BLUE, Vector2(x + 170, y), Vector2(140, 30))
	var so := LineEdit.new()
	so.rect_position = Vector2(x + 310, y - 4)
	so.rect_size = Vector2(100, 38)
	so.text = _time(Rhythia.start_offset)
	so.align = LineEdit.ALIGN_CENTER
	so.add_font_override("font", font(BOLD, 22))
	so.add_color_override("font_color", MAGENTA)
	var sbx := StyleBoxFlat.new()
	sbx.bg_color = Color(0, 0, 0, 0.6)
	sbx.border_color = Color(1, 1, 1)
	sbx.set_border_width_all(3)
	so.add_stylebox_override("normal", sbx)
	so.add_stylebox_override("focus", sbx)
	so.connect("text_entered", self, "_on_start_from", [so])
	so.connect("focus_exited", self, "_on_start_from_unfocus", [so])
	song_view.add_child(so)

	# the map's name in its difficulty colour
	var bar := Pill.new()
	bar.rect_position = Vector2(530, 292)
	bar.rect_size = Vector2(500, 50)
	bar.color = cols[1].lightened(0.15)
	bar.fill = cols[1]
	bar.radius = 10
	bar.text = s.name
	bar.text_color = cols[0].lightened(0.3)
	bar.font = font(BOLD, 26, 2, Color(0, 0, 0))
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	song_view.add_child(bar)

	# your best
	y = 356
	label(song_view, "Your Best:", font(BOLD, 24, 2, Color(0.25, 0.2, 0)), YELLOW, Vector2(540, y), Vector2(300, 32))
	var best = null
	if Rhythia.selected_song == s and not s.is_online:
		best = Rhythia.get_best()
	var acc := "-"
	var misses := "-"
	var combo := "-"
	if best:
		acc = "%.2f%%" % (100.0 * float(best.hit_notes) / max(1.0, float(best.total_notes)))
		misses = Globals.comma_sep(int(best.total_notes - best.hit_notes))
		combo = Globals.comma_sep(int(best.max_combo)) if int(best.max_combo) >= 0 else "?"
	_kv(Vector2(540, y + 36), "Misses: ", misses, YELLOW, CYAN)
	_kv(Vector2(540, y + 70), "Accuracy: ", acc, YELLOW, CYAN)
	_kv(Vector2(540, y + 104), "Max Combo: ", combo, YELLOW, CYAN)

	# PLAY and VS
	var play := BigButton.new()
	play.rect_position = Vector2(530, 520)
	play.rect_size = Vector2(400, 130)
	play.text = "PLAY" if not s.is_online else "DOWNLOAD"
	play.font = font(BOLD, 84 if not s.is_online else 56, 3, Color(0, 0.15, 0))
	play.connect("clicked", self, "_on_play")
	song_view.add_child(play)
	var vs := BigButton.new()
	vs.rect_position = Vector2(946, 540)
	vs.rect_size = Vector2(134, 110)
	vs.text = "VS"
	vs.font = font(BOLD, 64, 3, Color(0, 0.15, 0))
	vs.hint_tooltip = "Play with others (Online)"
	vs.connect("clicked", self, "_on_vs")
	song_view.add_child(vs)

	# right: your top runs on this map
	var lb := Board.new()
	lb.rect_position = Vector2(1126, 60)
	lb.rect_size = Vector2(126, 600)
	song_view.add_child(lb)
	label(lb, "TOP", font(PIXEL, 28, 3, Color(0.3, 0.2, 0)), YELLOW, Vector2(0, 12), Vector2(126, 40), Label.ALIGN_CENTER)
	var entries := []
	if not s.is_online:
		entries = ScoreHistory.rank(ScoreHistory.load_entries(String(s.id)))
	var ey := 64.0
	for i in range(min(entries.size(), 8)):
		var e: Dictionary = entries[i]
		var nm := String(e.get("nm", "You"))
		label(lb, "#%d" % (i + 1), font(BOLD, 18), Color(0, 0.7, 0.55), Vector2(12, ey), Vector2(40, 26))
		var nf := font(BOLD, 18, 1, Color(0, 0, 0))
		label(lb, fit(nm, nf, 70), nf, CYAN, Vector2(46, ey), Vector2(74, 26))
		label(lb, "%.2f%%" % (100.0 * ScoreHistory.accuracy(e)), font(BOLD, 16), Color(0.75, 0.9, 1), Vector2(12, ey + 24), Vector2(108, 22))
		ey += 64
	if entries.empty():
		label(lb, "No runs yet", font(BOLD, 16), Color(0.4, 0.75, 0.85), Vector2(0, ey), Vector2(126, 26), Label.ALIGN_CENTER)

func _kv(pos: Vector2, k: String, v: String, vcol: Color, kcol: Color = BLUE):
	var kf := font(BOLD, 22, 2, Color(0, 0.1, 0.2))
	var kl := label(song_view, k, kf, kcol, pos, Vector2(200, 30))
	var w: float = kf.get_string_size(k).x
	var vf := font(BOLD, 22, 2, Color(0.15, 0, 0.1))
	label(song_view, fit(v, vf, 420 - w), vf, vcol, pos + Vector2(w, 0), Vector2(420 - w, 30))
	return kl

static func _time(ms: float) -> String:
	var s: int = int(max(0.0, ms) / 1000.0)
	return "%d:%02d" % [s / 60, s % 60]

static func _num(v: float) -> String:
	if abs(v - round(v)) < 0.001:
		return str(int(round(v)))
	return ("%.2f" % v).rstrip("0").rstrip(".")

func _on_favorite(b):
	if _song == null:
		return
	if Rhythia.is_favorite(_song.id):
		Rhythia.remove_favorite(_song.id)
	else:
		Rhythia.add_favorite(_song.id)
	b.text = "Favorited!" if Rhythia.is_favorite(_song.id) else "Favorite?"
	b.update()

func _on_start_from(t: String, box: LineEdit):
	var ms := _parse_time(t)
	if _song != null and _song.last_ms > 0:
		ms = clamp(ms, 0.0, max(0.0, _song.last_ms - 1000.0))
	Rhythia.start_offset = ms
	box.text = _time(ms)
	box.release_focus()

func _on_start_from_unfocus(box: LineEdit):
	_on_start_from(box.text, box)

static func _parse_time(t: String) -> float:
	t = t.strip_edges()
	if t == "":
		return 0.0
	var parts := t.split(":")
	var sec := 0.0
	for p in parts:
		sec = sec * 60.0 + float(p)
	return max(0.0, sec * 1000.0)

func _on_play():
	if _song == null:
		return
	if Rhythia.selected_song != _song:
		Rhythia.select_song(_song)
		return
	if _song.is_online:
		return
	var run = menu.get_node_or_null("Main/Maps/Results/Results/RS/H1/Info/Run")
	if run and run.has_method("_pressed"):
		run._pressed()
	elif list:
		list.play_song()

func _on_vs():
	var sb = menu.get_node_or_null("Sidebar")
	var online = menu.get_node_or_null("Main/Online")
	if sb and online and sb.has_method("press_page"):
		sb.press_page(online)

# keep the map screen in step (a map that was downloading, speed changes)
func _physics_process(_d):
	if song_view == null or _song == null:
		return
	var spd = song_view.get_meta("speed_label") if song_view.has_meta("speed_label") else null
	if spd and Rhythia.has_method("current_speed_multiplier"):
		var t := "SPEED x%s" % _num(float(Rhythia.current_speed_multiplier()))
		if spd.text != t:
			spd.text = t
	if _built_online and not _song.is_online:
		_build_song_view() # it finished downloading

# --- pieces -------------------------------------------------------------------

# controls that draw rounded boxes
class RoundedBox extends Control:
	func _rounded(r: Rect2, rad: float, col: Color):
		var pts := PoolVector2Array()
		rad = min(rad, min(r.size.x, r.size.y) / 2.0)
		var corners := [
			[Vector2(r.end.x - rad, r.position.y + rad), -PI / 2],
			[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
			[Vector2(r.position.x + rad, r.end.y - rad), PI / 2],
			[Vector2(r.position.x + rad, r.position.y + rad), PI],
		]
		for c in corners:
			for i in range(7):
				var a: float = c[1] + (PI / 2) * i / 6
				pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
		draw_colored_polygon(pts, col)

class Clickable extends RoundedBox:
	signal clicked
	var kind := ""
	var hover := false
	func _init():
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		connect("mouse_entered", self, "_h", [true])
		connect("mouse_exited", self, "_h", [false])
	func _h(v):
		hover = v
		modulate = Color(1.15, 1.15, 1.15) if v else Color(1, 1, 1)
		update()
	func _gui_input(e):
		if e is InputEventMouseButton and e.button_index == BUTTON_LEFT and not e.pressed:
			if Rect2(Vector2.ZERO, rect_size).has_point(e.position):
				accept_event()
				emit_signal("clicked")
		elif e is InputEventMouseButton and e.button_index == BUTTON_LEFT and e.pressed:
			accept_event()
	func _draw():
		if kind == "search":
			# white tilted frame with a cyan magnifier
			var r := Rect2(Vector2(4, 4), rect_size - Vector2(8, 8))
			draw_rect(r, Color(0, 0, 0, 0.6))
			draw_rect(r, Color(0.95, 0.95, 0.95), false, 4.0)
			var c := rect_size * Vector2(0.44, 0.44)
			draw_arc(c, rect_size.x * 0.2, 0, TAU, 32, Color8(0, 210, 255), 5.0, true)
			var d := Vector2(1, 1).normalized()
			draw_line(c + d * rect_size.x * 0.2, c + d * rect_size.x * 0.4, Color8(0, 210, 255), 7.0, true)

class Frame extends RoundedBox:
	func _draw():
		var r := Rect2(Vector2.ZERO, rect_size)
		_rounded(r, 10, Color8(235, 235, 235))
		_rounded(r.grow(-5), 6, Color(0, 0, 0))

class Dashed extends Control:
	func _draw():
		var y := 0.0
		while y < rect_size.y:
			draw_rect(Rect2(0, y, rect_size.x, min(22.0, rect_size.y - y)), Color8(220, 220, 220))
			y += 34.0

# One tile of the grid: a difficulty or a map.
class Tile extends Clickable:
	var ui
	var diff := Globals.DIFF_UNKNOWN
	var song = null
	var dim := false
	var lit := false
	func setup(text: String):
		var cols: Array = ui.DIFF_COLORS[diff]
		if song == null:
			var size := 44
			var f = ui.font(ui.BOLD, size, 4, Color(0.12, 0.12, 0.12))
			while size > 16 and f.get_string_size(text).x + 8 > rect_size.x - 26:
				size -= 2
				f = ui.font(ui.BOLD, size, 4, Color(0.12, 0.12, 0.12))
			if text == "包":
				f = ui.font(ui.BOLD, 84, 5, Color(0.15, 0.15, 0.15))
			ui.label(self, text, f, Color(0.95, 0.95, 0.95), Vector2(6, 6), rect_size - Vector2(12, 12), Label.ALIGN_CENTER)
		else:
			var full := String(song.name)
			var artist := ""
			var title := full
			var cut := full.find(" - ")
			if cut > 0:
				artist = full.substr(0, cut)
				title = full.substr(cut + 3)
			var tl = ui.label(self, title, ui.font(ui.BOLD, 15, 2, Color(0.1, 0.05, 0.05)), Color(0.97, 0.97, 0.95), Vector2(12, 16), Vector2(rect_size.x - 24, 54), Label.ALIGN_CENTER)
			tl.autowrap = true
			tl.clip_text = true
			if artist != "":
				var size := 26 if artist.length() <= 9 else (21 if artist.length() <= 14 else 17)
				var al = ui.label(self, artist, ui.font(ui.BOLD, size, 2, Color8(235, 228, 215)), Color(0.06, 0.05, 0.05), Vector2(10, 70), Vector2(rect_size.x - 20, 46), Label.ALIGN_CENTER)
				al.autowrap = true
				al.clip_text = true
			var stars: float = song.star_rating_cached()
			if stars >= 0:
				ui.label(self, str(int(round(stars))), ui.font(ui.BOLD, 18, 2, Color(0.3, 0.15, 0)), Color8(255, 210, 60), Vector2(30, rect_size.y - 36), Vector2(60, 26))
			if song.is_online:
				ui.label(self, "ONLINE", ui.font(ui.BOLD, 12, 1, Color(0, 0, 0)), Color8(120, 220, 255), Vector2(0, 8), Vector2(rect_size.x - 12, 16), Label.ALIGN_RIGHT)
		if dim:
			modulate = Color(1, 1, 1, 0.35)
	func _h(v):
		hover = v
		update()
	func _draw():
		var cols: Array = ui.DIFF_COLORS[diff]
		var r := Rect2(Vector2.ZERO, rect_size)
		if lit:
			_rounded(r.grow(4), 10, Color(1, 1, 1))
		_rounded(r, 8, cols[0])
		_rounded(r.grow(-9), 4, cols[1].lightened(0.12) if hover else cols[1])
		if song != null and song.star_rating_cached() >= 0:
			_star(Vector2(19, rect_size.y - 23), 10.0)
		if song != null and Rhythia.is_favorite(song.id):
			_star(Vector2(rect_size.x - 20, rect_size.y - 22), 9.0)
	func _star(c: Vector2, rad: float):
		var pts := PoolVector2Array()
		for i in range(10):
			var a := -PI / 2 + i * PI / 5
			var rr := rad if i % 2 == 0 else rad * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		var outline := PoolVector2Array()
		for p in pts:
			outline.append(c + (p - c) * 1.35)
		draw_colored_polygon(outline, Color(0.3, 0.15, 0))
		draw_colored_polygon(pts, Color8(255, 200, 40))

# Top of the grid: who's playing. Your Discord login (name and picture) with
# your level; tap it to log in on the Profile page when you aren't.
class PlayerCard extends RoundedBox:
	signal clicked
	const AVATAR_META := "ss_menu_discord_avatar"
	var ui
	var store
	var avatar: TextureRect
	var _http: HTTPRequest
	func _ready():
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		store = ui.PlayerLevel.get_store()
		avatar = TextureRect.new()
		avatar.rect_position = Vector2(14, 10)
		avatar.rect_size = Vector2(76, 76)
		avatar.expand = true
		avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		avatar.mouse_filter = MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = "shader_type canvas_item; void fragment() { vec4 c = texture(TEXTURE, UV); float d = distance(UV, vec2(0.5)); c.a *= 1.0 - smoothstep(0.47, 0.5, d); COLOR = c; }"
		var mat := ShaderMaterial.new()
		mat.shader = sh
		avatar.material = mat
		add_child(avatar)
		Rhythia.connect("discord_login_changed", self, "_rebuild")
		_rebuild()
	func _rebuild():
		for c in get_children():
			if c is Label:
				c.queue_free()
		var du: Dictionary = Rhythia.discord_user if typeof(Rhythia.discord_user) == TYPE_DICTIONARY else {}
		var logged_in := du.has("id") and String(du.get("id", "")) != ""
		var nm := String(du.get("display_name", ""))
		if nm == "":
			nm = String(du.get("username", ""))
		var nf = ui.font(ui.BOLD, 30, 2, Color(0.1, 0.1, 0.1))
		if logged_in:
			ui.label(self, ui.fit(nm, nf, 270), nf, Color(0.93, 0.93, 0.93), Vector2(100, 6), Vector2(270, 40))
			hint_tooltip = "Logged in with Discord as %s" % nm
		else:
			var lf = ui.font(ui.BOLD, 24, 2, Color(0.1, 0.1, 0.1))
			ui.label(self, "Log in with Discord", lf, Color8(140, 155, 255), Vector2(100, 8), Vector2(270, 36))
			hint_tooltip = "Tap to log in with Discord (Profile page)"
		ui.label(self, "Level %d/%d" % [store.level, ui.PlayerLevel.MAX_LEVEL], ui.font(ui.BOLD, 18, 2, Color(0.1, 0.1, 0.1)), Color(0.9, 0.9, 0.9), Vector2(100, 50), Vector2(180, 26))
		ui.label(self, "%s / %s" % [Globals.comma_sep(store.cur_exp), Globals.comma_sep(store.required())], ui.font(ui.BOLD, 12, 1, Color(0, 0, 0)), Color(0.75, 0.75, 0.75), Vector2(100, 74), Vector2(180, 18))
		ui.label(self, "Prestige %d" % store.prestige, ui.font(ui.BOLD, 16, 2, Color(0.2, 0.15, 0)), Color8(255, 200, 40), Vector2(260, 52), Vector2(110, 24), Label.ALIGN_RIGHT)
		avatar.texture = null
		var url := String(du.get("avatar_url", "")) if logged_in else ""
		if url != "":
			if Engine.has_meta(AVATAR_META) and Engine.get_meta(AVATAR_META)[0] == url:
				avatar.texture = Engine.get_meta(AVATAR_META)[1]
			else:
				_download(url)
		update()
	# Discord's CDN: ask for a small still PNG
	static func _small_png(url: String) -> String:
		if url.find("cdn.discordapp.com") == -1 and url.find("media.discordapp.net") == -1:
			return url
		var base := url.split("?")[0]
		if base.get_extension().to_lower() in ["gif", "webp", "jpg", "jpeg", "png"]:
			base = base.get_basename() + ".png"
		return base + "?size=128"
	func _download(url: String):
		if _http == null:
			_http = HTTPRequest.new()
			add_child(_http)
		else:
			_http.cancel_request()
		if _http.is_connected("request_completed", self, "_on_avatar"):
			_http.disconnect("request_completed", self, "_on_avatar")
		_http.connect("request_completed", self, "_on_avatar", [url])
		_http.request(_small_png(url))
	func _on_avatar(result, code, _headers, body: PoolByteArray, url: String):
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.size() < 8:
			return
		var img := Image.new()
		var err := img.load_png_from_buffer(body)
		if err != OK:
			err = img.load_jpg_from_buffer(body)
		if err != OK or img.is_empty():
			return
		var tex := ImageTexture.new()
		tex.create_from_image(img)
		Engine.set_meta(AVATAR_META, [url, tex])
		avatar.texture = tex
		update()
	func _gui_input(e):
		if e is InputEventMouseButton and e.button_index == BUTTON_LEFT and not e.pressed:
			accept_event()
			emit_signal("clicked")
	func _draw():
		var r := Rect2(Vector2.ZERO, rect_size)
		_rounded(r, 10, Color(0.08, 0.08, 0.08, 0.92))
		# checker like Sound Space's card
		var sq := 16.0
		for yy in range(int(rect_size.y / sq)):
			for xx in range(int(rect_size.x / sq)):
				if (xx + yy) % 2 == 0:
					var a: float = 0.06 * (1.0 - float(xx) / (rect_size.x / sq))
					draw_rect(Rect2(xx * sq, yy * sq, sq, sq), Color(1, 1, 1, a))
		var c := Vector2(52, 48)
		if avatar.texture != null:
			draw_circle(c, 41, Color(0.9, 0.9, 0.9))
			return
		# no picture yet: Discord's default (blurple when logged in)
		draw_circle(c, 38, Color8(88, 101, 242) if Rhythia.discord_user.has("id") else Color8(70, 70, 78))
		draw_circle(c + Vector2(0, -6), 13, Color(1, 1, 1, 0.9))
		draw_arc(c + Vector2(0, 26), 22, PI + 0.35, TAU - 0.35, 16, Color(1, 1, 1, 0.9), 9.0, true)

class Cover extends Control:
	var ui
	var song
	func _ready():
		mouse_filter = MOUSE_FILTER_IGNORE
		if not song.has_cover or song.is_online:
			var l = ui.label(self, song.name, ui.font(ui.BOLD, 18, 2, Color(0.95, 0.95, 0.95)), Color(0.1, 0.1, 0.1), Vector2(10, 10), rect_size - Vector2(20, 20), Label.ALIGN_CENTER)
			l.autowrap = true
			l.clip_text = true
		var stars: float = song.star_rating_cached()
		if stars >= 0:
			ui.label(self, "★%d" % int(round(stars)), ui.font(ui.BOLD, 20, 2, Color(0.3, 0.15, 0)), Color8(255, 200, 40), Vector2(-8, rect_size.y - 22), Vector2(80, 28))
	func _draw():
		var r := Rect2(Vector2.ZERO, rect_size)
		draw_rect(r.grow(3), Color8(240, 240, 240))
		draw_rect(r.grow(-6), Color8(120, 125, 130))
		if song.has_cover and not song.is_online:
			var tex = song.cover
			if tex:
				draw_texture_rect(tex, r.grow(-6), false)

class DiffSquare extends Control:
	var color := Color(1, 1, 1)
	var on := false
	func _ready():
		mouse_filter = MOUSE_FILTER_IGNORE
	func _draw():
		var r := Rect2(Vector2.ZERO, rect_size)
		if on:
			draw_rect(r.grow(2), Color(1, 1, 1))
			draw_rect(r.grow(-2), color)
		else:
			draw_rect(r.grow(-2), color.darkened(0.65))
			draw_rect(r.grow(-2), color, false, 3.0)

# rounded outlined button with text (Favorite?, Hide, the map's name bar)
class Pill extends Clickable:
	var color := Color(1, 1, 1)
	var fill := Color(0, 0, 0, 0.75)
	var text_color := Color(1, 1, 1)
	var text := ""
	var font: Font
	var radius := -1.0
	func _draw():
		var r := Rect2(Vector2.ZERO, rect_size)
		var rad := rect_size.y / 2.0 if radius < 0 else radius
		_rounded(r, rad, color)
		_rounded(r.grow(-4), max(0.0, rad - 4), fill)
		if font:
			var t := text
			while t.length() > 3 and font.get_string_size(t).x > rect_size.x - 30:
				t = t.substr(0, t.length() - 4) + "…"
			var w: float = font.get_string_size(t).x
			draw_string(font, Vector2((rect_size.x - w) / 2.0, rect_size.y / 2.0 + font.get_ascent() / 2.0 - 3), t, text_color)

# the big green PLAY / VS buttons
class BigButton extends Pill:
	func _init():
		color = Color8(40, 245, 40)
		fill = Color8(10, 70, 12)
		text_color = Color8(40, 245, 40)
		radius = 18.0

class Board extends Control:
	func _ready():
		mouse_filter = MOUSE_FILTER_IGNORE
	func _draw():
		var r := Rect2(Vector2.ZERO, rect_size)
		draw_rect(r, Color(0, 0, 0, 0.7))
		draw_rect(r.grow(-3), Color8(0, 200, 240), false, 6.0)
