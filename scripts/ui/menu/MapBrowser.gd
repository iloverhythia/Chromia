extends ReferenceRect
# "Map Browser" sidebar page: browse rhythia.com's maps and download them into
# the game without leaving it or restarting. Same data as rhythia.com/maps
# (production.rhythia.com/api/getBeatmaps). Downloaded maps go into
# user://maps like imported ones and show up in the map list right away.

const API = "https://production.rhythia.com/api/getBeatmaps"
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)
const CARD_BG = Color(0.11, 0.105, 0.14, 1)
const FIELD_BG = Color(0.13, 0.125, 0.165, 1)
const BTN_BG = Color(0.1, 0.095, 0.125, 1)
const BTN_HOVER = Color(0.14, 0.13, 0.18, 1)
const BTN_SEL = Color(0.2, 0.17, 0.25, 1)
const CARD_MIN_W = 360
const COVER_H = 150
const MAX_IMG_REQUESTS = 4
const MAX_IMG_CACHE = 300

# [label, sub label, min stars, max stars]
const DIFF_RANGES = [
	["Any", "All difficulties", 0.0, 100000.0],
	["Beginner", "★ 0–3", 0.0, 3.0],
	["Intermediate", "★ 3–5", 3.0, 5.0],
	["Hard", "★ 5–7", 5.0, 7.0],
	["Expert", "★ 7+", 7.0, 100000.0],
]
# [label, api value]
const SORTS = [["Newest", "newest"], ["Most played", "playCount"], ["Difficulty", "starRating"], ["Length", "length"]]
# rhythia.com's difficulty names / colors (index = map "difficulty")
const DIFF_NAMES = ["N/A", "EASY", "MEDIUM", "HARD", "LOGIC", "TASUKETE"]
const DIFF_COLORS = [
	Color(0.35, 0.35, 0.4), Color(0.2, 0.6, 0.3), Color(0.75, 0.6, 0.15),
	Color(0.7, 0.18, 0.2), Color(0.45, 0.25, 0.7), Color(0.25, 0.25, 0.28)]

var font_regular: DynamicFont
var font_bold: DynamicFont
var font_title: DynamicFont
var font_small: DynamicFont
var font_card_title: DynamicFont

var search: LineEdit
var diff_buttons: Array = []
var sort_buttons: Array = []
var grid: GridContainer
var scroll: ScrollContainer
var info: Label
var page_label: Label
var prev_btn: Button
var next_btn: Button

var page: int = 1
var total_pages: int = 1
var diff_idx: int = 0
var sort_idx: int = 0
var sort_desc: bool = true

var _built := false
var _query_id := 0 # newest list request; older answers are dropped
var _search_timer: Timer
var _img_cache: Dictionary = {}   # url -> ImageTexture
var _img_order: Array = []
var _img_queue: Array = []        # [url, TextureRect]
var _img_waiting: Dictionary = {} # url -> [TextureRect...]
var _img_active := 0
var _downloads: Dictionary = {}   # online id -> {req, map, bytes, idle}
var _buttons_by_id: Dictionary = {} # online id -> download Button (current page)
var _maps_by_id: Dictionary = {}    # online id -> map data (current page)
var _extra_by_id: Dictionary = {}   # online id -> small "download anyway" Button
# Which rhythia.com map each download became: online id -> local map id.
# Two different maps can share a name (and the map id inside the file), so the
# name alone can't say if you have *this* version.
const RECORD_PATH = "user://map_browser.json"
const STALL_SECONDS = 30.0
var _record: Dictionary = {}

# ------------------------------------------------------------------ helpers

func _font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	# Lato has no ★ ↓ ▷ etc.; Noto Sans JP does
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return f

func _flat(bg: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
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

func _style_button(b: Button, toggle: bool = false):
	b.focus_mode = FOCUS_NONE
	b.add_font_override("font", font_bold)
	b.add_color_override("font_color", DIM if toggle else TEXT)
	b.add_color_override("font_color_hover", TEXT)
	b.add_color_override("font_color_pressed", TEXT)
	b.add_color_override("font_color_disabled", Color(0.45, 0.44, 0.5))
	b.add_stylebox_override("normal", _pad(_flat(BTN_BG, 8), 12, 6))
	b.add_stylebox_override("hover", _pad(_flat(BTN_HOVER, 8), 12, 6))
	b.add_stylebox_override("pressed", _pad(_flat(BTN_SEL, 8, LILAC, 1), 12, 6))
	b.add_stylebox_override("disabled", _pad(_flat(Color(0.09, 0.085, 0.11, 1), 8), 12, 6))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.toggle_mode = toggle

func _button(text: String, method: String, args: Array = []) -> Button:
	var b = Button.new()
	b.text = text
	_style_button(b)
	b.connect("pressed", self, method, args)
	return b

static func _fmt_len(ms) -> String:
	var s := int(float(ms) / 1000.0)
	return "%02d:%02d" % [s / 60, s % 60]

static func _fmt_count(n) -> String:
	var v := int(n)
	if v >= 1000000:
		return "%.1fM" % (v / 1000000.0)
	if v >= 10000:
		return "%.1fk" % (v / 1000.0)
	return str(v)

static func _star_color(stars: float) -> Color:
	if stars < 3.0: return Color(0.45, 0.85, 0.55)
	if stars < 5.0: return Color(0.4, 0.8, 0.85)
	if stars < 7.0: return Color(0.5, 0.65, 1.0)
	if stars < 9.0: return Color(0.72, 0.55, 1.0)
	if stars < 12.0: return Color(1.0, 0.5, 0.75)
	return Color(1.0, 0.4, 0.4)

# The .sspm's own map id is the tail of the cover image name:
# ".../beatmap-img-<timestamp>-<map id>". Used to tell which maps you have.
static func _local_id(m: Dictionary) -> String:
	var img := Globals.s(m.get("image", ""))
	var fname := img.get_file()
	if not fname.begins_with("beatmap-img-"):
		return ""
	fname = fname.substr(12)
	var dash := fname.find("-")
	if dash == -1:
		return ""
	return fname.substr(dash + 1)

func _song_by_id(id: String):
	if id == "" or Rhythia.registry_song == null or not Rhythia.registry_song.idx_id.has(id):
		return null
	var s = Rhythia.registry_song.get_item(id)
	return s if s is Song else null

# This exact map, downloaded through the browser before.
func _installed_song(m: Dictionary):
	return _song_by_id(String(_record.get(str(m.get("id", "")), "")))

# A map with the same name (map id) that may or may not be this version:
# installed some other way, and not known to belong to another rhythia.com map.
func _same_name_song(m: Dictionary):
	var id := _local_id(m)
	var s = _song_by_id(id)
	if s == null:
		return null
	var oid := str(m.get("id", ""))
	for k in _record.keys():
		if k != oid and String(_record[k]) == id:
			return null # that file is a different rhythia.com map
	return s

func _load_record():
	var f = File.new()
	if f.open(Globals.p(RECORD_PATH), File.READ) == OK:
		var p = JSON.parse(f.get_as_text())
		f.close()
		if p.error == OK and typeof(p.result) == TYPE_DICTIONARY:
			_record = p.result

func _save_record():
	var f = File.new()
	if f.open(Globals.p(RECORD_PATH), File.WRITE) == OK:
		f.store_string(to_json(_record))
		f.close()

# Leftover temp files from the first Map Browser version (oct19-2026-s).
func _clean_partial_files():
	var dir = Directory.new()
	if dir.open(Globals.p("user://maps")) != OK:
		return
	dir.list_dir_begin(true, true)
	var fn = dir.get_next()
	var stale = []
	while fn != "":
		if fn.begins_with(".download_") and fn.ends_with(".part"):
			stale.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	for f in stale:
		var oid = f.trim_prefix(".download_").trim_suffix(".part")
		if not _downloads.has(oid):
			dir.remove(f)

# ------------------------------------------------------------------ build

func _ready():
	connect("visibility_changed", self, "_on_visibility")

func _on_visibility():
	if is_visible_in_tree():
		if not _built:
			_load_record()
			_clean_partial_files()
			_build()
			_built = true
			_load_page()
		else:
			_refresh_buttons()

func _build():
	font_regular = _font("res://assets/font/Lato/Lato-Regular.ttf", 15)
	font_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 15)
	font_title = _font("res://assets/font/Lato/Lato-Black.ttf", 28)
	font_small = _font("res://assets/font/Lato/Lato-Bold.ttf", 12)
	font_card_title = _font("res://assets/font/Lato/Lato-Black.ttf", 18)

	var root = VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.margin_left = 76
	root.margin_right = -24
	root.margin_top = 20
	root.margin_bottom = -56
	root.add_constant_override("separation", 12)
	add_child(root)

	# --- header
	var top = HBoxContainer.new()
	top.add_constant_override("separation", 10)
	root.add_child(top)
	var titles = VBoxContainer.new()
	titles.size_flags_horizontal = SIZE_EXPAND_FILL
	titles.add_constant_override("separation", 0)
	top.add_child(titles)
	titles.add_child(_label("Map Browser", font_title))
	titles.add_child(_label("Download maps from rhythia.com straight into the game", font_regular, DIM))

	var refresh = _button("Refresh", "_load_page")
	refresh.rect_min_size = Vector2(100, 36)
	refresh.size_flags_vertical = SIZE_SHRINK_CENTER
	top.add_child(refresh)

	# --- filters panel: difficulty cards + search
	var fpanel = PanelContainer.new()
	fpanel.add_stylebox_override("panel", _pad(_flat(Color(0.07, 0.065, 0.09, 0.85), 10, Color(1, 1, 1, 0.06), 1), 14, 12))
	root.add_child(fpanel)
	var fv = VBoxContainer.new()
	fv.add_constant_override("separation", 10)
	fpanel.add_child(fv)
	var drow = HBoxContainer.new()
	drow.add_constant_override("separation", 10)
	fv.add_child(drow)
	for i in range(DIFF_RANGES.size()):
		var b = Button.new()
		_style_button(b, true)
		b.rect_min_size = Vector2(0, 54)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_stylebox_override("pressed", _pad(_flat(Color(0.16, 0.14, 0.21, 1), 8, LILAC, 1), 12, 6))
		b.connect("pressed", self, "_on_diff", [i])
		var lv = VBoxContainer.new()
		lv.anchor_right = 1
		lv.anchor_bottom = 1
		lv.margin_left = 14
		lv.alignment = BoxContainer.ALIGN_CENTER
		lv.add_constant_override("separation", 1)
		lv.mouse_filter = MOUSE_FILTER_IGNORE
		lv.add_child(_label(DIFF_RANGES[i][0], font_bold))
		lv.add_child(_label(DIFF_RANGES[i][1], font_small, DIM))
		b.add_child(lv)
		drow.add_child(b)
		diff_buttons.append(b)

	search = LineEdit.new()
	search.placeholder_text = "Search maps by name, author, or genre..."
	search.rect_min_size = Vector2(0, 38)
	search.add_font_override("font", font_regular)
	search.add_color_override("font_color", TEXT)
	search.add_stylebox_override("normal", _pad(_flat(FIELD_BG, 8), 12, 4))
	search.add_stylebox_override("focus", _pad(_flat(FIELD_BG, 8, LILAC, 1), 12, 4))
	search.clear_button_enabled = true
	search.add_color_override("clear_button_color", DIM)
	search.add_color_override("clear_button_color_pressed", TEXT)
	search.connect("text_changed", self, "_on_search_changed")
	search.connect("text_entered", self, "_on_search_entered")
	fv.add_child(search)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.45
	_search_timer.connect("timeout", self, "_on_search_entered", [""])
	add_child(_search_timer)

	# --- sort row
	var srow = HBoxContainer.new()
	srow.add_constant_override("separation", 6)
	root.add_child(srow)
	for i in range(SORTS.size()):
		var b = Button.new()
		_style_button(b, true)
		b.text = SORTS[i][0]
		b.add_stylebox_override("normal", _pad(_flat(Color(0, 0, 0, 0), 6), 10, 4))
		b.add_stylebox_override("hover", _pad(_flat(Color(1, 1, 1, 0.05), 6), 10, 4))
		b.add_stylebox_override("pressed", _pad(_flat(BTN_SEL, 6), 10, 4))
		b.connect("pressed", self, "_on_sort", [i])
		srow.add_child(b)
		sort_buttons.append(b)
	var spacer = Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	srow.add_child(spacer)
	info = _label("", font_regular, DIM)
	info.size_flags_vertical = SIZE_SHRINK_CENTER
	srow.add_child(info)

	# --- cards
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	root.add_child(scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_constant_override("hseparation", 14)
	grid.add_constant_override("vseparation", 14)
	scroll.add_child(grid)
	scroll.connect("resized", self, "_relayout")

	# --- pager
	var prow = HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGN_CENTER
	prow.add_constant_override("separation", 12)
	root.add_child(prow)
	prev_btn = _button("‹  Prev", "_go_page", [-1])
	prev_btn.rect_min_size = Vector2(100, 34)
	prow.add_child(prev_btn)
	page_label = _label("Page 1", font_bold)
	page_label.rect_min_size = Vector2(130, 0)
	page_label.align = Label.ALIGN_CENTER
	page_label.size_flags_vertical = SIZE_SHRINK_CENTER
	prow.add_child(page_label)
	next_btn = _button("Next  ›", "_go_page", [1])
	next_btn.rect_min_size = Vector2(100, 34)
	prow.add_child(next_btn)

	_sync_filter_buttons()
	set_process(false)

func _sync_filter_buttons():
	for i in range(diff_buttons.size()):
		diff_buttons[i].pressed = i == diff_idx
	for i in range(sort_buttons.size()):
		var b: Button = sort_buttons[i]
		b.pressed = i == sort_idx
		var t: String = SORTS[i][0]
		if i == sort_idx:
			t += "  ↓" if sort_desc else "  ↑"
		b.text = t

func _relayout():
	if grid == null:
		return
	var w: float = scroll.rect_size.x - 14
	grid.columns = int(max(1, floor((w + 14) / (CARD_MIN_W + 14))))
	var cw: float = (w - 14 * (grid.columns - 1)) / grid.columns
	for c in grid.get_children():
		c.rect_min_size.x = cw

# ------------------------------------------------------------------ filters

func _on_diff(i: int):
	diff_idx = i
	page = 1
	_sync_filter_buttons()
	_load_page()

func _on_sort(i: int):
	if i == sort_idx:
		sort_desc = not sort_desc
	else:
		sort_idx = i
		sort_desc = true
	page = 1
	_sync_filter_buttons()
	_load_page()

func _on_search_changed(_t: String):
	_search_timer.start()

func _on_search_entered(_t: String):
	_search_timer.stop()
	page = 1
	_load_page()

func _go_page(d: int):
	var p := int(clamp(page + d, 1, max(total_pages, 1)))
	if p == page:
		return
	page = p
	_load_page()

# ------------------------------------------------------------------ loading

func _load_page():
	if not _built and grid == null:
		return
	_query_id += 1
	var qid := _query_id
	info.text = "Loading..."
	prev_btn.disabled = true
	next_btn.disabled = true
	var body := {
		"session": "",
		"page": page,
		"textFilter": search.text.strip_edges(),
		"authorFilter": "",
		"tagsFilter": "",
		"minStars": DIFF_RANGES[diff_idx][2],
		"maxStars": DIFF_RANGES[diff_idx][3],
		"status": "", # all maps; rhythia.com's ranked list isn't Chromia's
		"sort": SORTS[sort_idx][1],
		"sortDirection": "desc" if sort_desc else "asc",
	}
	var r = HTTPRequest.new()
	r.timeout = 20
	r.use_threads = OS.can_use_threads()
	add_child(r)
	r.connect("request_completed", self, "_on_list", [r, qid])
	if r.request(API, PoolStringArray(["Content-Type: application/json"]), true, HTTPClient.METHOD_POST, to_json(body)) != OK:
		r.queue_free()
		_show_error("Couldn't reach rhythia.com.")

func _on_list(result: int, code: int, _headers, data: PoolByteArray, r: HTTPRequest, qid: int):
	r.queue_free()
	if qid != _query_id or not is_instance_valid(grid):
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_show_error("Couldn't load maps from rhythia.com (error %d / %d)." % [result, code])
		return
	var p := JSON.parse(data.get_string_from_utf8())
	if p.error != OK or typeof(p.result) != TYPE_DICTIONARY:
		_show_error("rhythia.com sent something unexpected.")
		return
	var d: Dictionary = p.result
	var maps = d.get("beatmaps", [])
	if typeof(maps) != TYPE_ARRAY:
		maps = []
	var total := int(d.get("total", 0))
	var per := int(max(1, int(d.get("viewPerPage", 50))))
	total_pages = int(max(1, ceil(float(total) / per)))
	page = int(clamp(page, 1, total_pages))
	info.text = "%s maps" % Globals.comma_sep(total) if total != 1 else "1 map"
	page_label.text = "Page %d of %d" % [page, total_pages]
	prev_btn.disabled = page <= 1
	next_btn.disabled = page >= total_pages
	_show_maps(maps)

func _show_error(msg: String):
	info.text = msg
	page_label.text = "Page %d" % page
	prev_btn.disabled = page <= 1
	next_btn.disabled = false

func _show_maps(maps: Array):
	for c in grid.get_children():
		c.queue_free()
	_buttons_by_id.clear()
	_maps_by_id.clear()
	_extra_by_id.clear()
	_img_queue.clear()
	_img_waiting.clear()
	scroll.scroll_vertical = 0
	if maps.empty():
		var l = _label("No maps found. Try another search or difficulty.", font_regular, DIM)
		grid.add_child(l)
		return
	for m in maps:
		if typeof(m) == TYPE_DICTIONARY:
			grid.add_child(_make_card(m))
	_relayout()

# ------------------------------------------------------------------ cards

func _pill(text: String, color: Color, bg: Color = Color(0.03, 0.03, 0.05, 0.78)) -> PanelContainer:
	var p = PanelContainer.new()
	p.mouse_filter = MOUSE_FILTER_IGNORE
	p.add_stylebox_override("panel", _pad(_flat(bg, 11, Color(1, 1, 1, 0.12), 1), 9, 2))
	var l = _label(text, font_small, color)
	p.add_child(l)
	return p

func _make_card(m: Dictionary) -> Control:
	var card = PanelContainer.new()
	var sb = _flat(CARD_BG, 10, Color(1, 1, 1, 0.07), 1)
	card.add_stylebox_override("panel", sb)
	card.rect_min_size = Vector2(CARD_MIN_W, 0)
	card.rect_clip_content = true
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 0)
	card.add_child(v)

	# cover with badges and title on top
	var cover = Control.new()
	cover.rect_min_size = Vector2(0, COVER_H)
	cover.rect_clip_content = true
	cover.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(cover)
	var tex = TextureRect.new()
	tex.anchor_right = 1
	tex.anchor_bottom = 1
	tex.expand = true
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.modulate = Color(0.75, 0.75, 0.78)
	tex.mouse_filter = MOUSE_FILTER_IGNORE
	cover.add_child(tex)
	var shade = TextureRect.new()
	shade.anchor_right = 1
	shade.anchor_bottom = 1
	shade.expand = true
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.texture = _shade_texture()
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	cover.add_child(shade)
	var imgs = m.get("previewImage", {})
	var url := ""
	if typeof(imgs) == TYPE_DICTIONARY:
		url = String(imgs.get("small", ""))
	if url == "":
		url = Globals.s(m.get("image", ""))
	if url != "":
		_request_image(url, tex)

	# badges, top left
	var badges = VBoxContainer.new()
	badges.margin_left = 10
	badges.margin_top = 10
	badges.add_constant_override("separation", 6)
	badges.mouse_filter = MOUSE_FILTER_IGNORE
	cover.add_child(badges)
	var di := int(clamp(int(m.get("difficulty", 0)), 0, DIFF_NAMES.size() - 1))
	var row2 = HBoxContainer.new()
	row2.mouse_filter = MOUSE_FILTER_IGNORE
	row2.add_child(_pill(DIFF_NAMES[di], Color(1, 1, 1), Color(DIFF_COLORS[di].r, DIFF_COLORS[di].g, DIFF_COLORS[di].b, 0.92)))
	badges.add_child(row2)

	# stars / length / plays, top right
	var stats = VBoxContainer.new()
	stats.anchor_left = 1
	stats.anchor_right = 1
	stats.margin_right = -10
	stats.margin_top = 10
	stats.grow_horizontal = GROW_DIRECTION_BEGIN
	stats.add_constant_override("separation", 5)
	stats.mouse_filter = MOUSE_FILTER_IGNORE
	cover.add_child(stats)
	var stars := float(m.get("starRating", 0.0))
	for s in [["%.2f ★" % stars, _star_color(stars)], [_fmt_len(m.get("length", 0)), TEXT], [_fmt_count(m.get("playcount", 0)) + "  ▷", TEXT]]:
		var h = HBoxContainer.new()
		h.alignment = BoxContainer.ALIGN_END
		h.mouse_filter = MOUSE_FILTER_IGNORE
		h.add_child(_pill(s[0], s[1]))
		stats.add_child(h)

	# title, bottom left
	var title = _label(Globals.s(m.get("title", "Untitled")), font_card_title, Color(1, 1, 1))
	title.anchor_top = 1
	title.anchor_bottom = 1
	title.anchor_right = 1
	title.margin_left = 12
	title.margin_right = -12
	title.margin_top = -34
	title.margin_bottom = -8
	title.clip_text = true
	title.hint_tooltip = title.text
	title.mouse_filter = MOUSE_FILTER_PASS
	title.add_color_override("font_color_shadow", Color(0, 0, 0, 0.7))
	title.add_constant_override("shadow_offset_y", 1)
	cover.add_child(title)

	# footer: mapper + download
	var foot = PanelContainer.new()
	foot.add_stylebox_override("panel", _pad(_flat(Color(0, 0, 0, 0), 0), 12, 8))
	v.add_child(foot)
	var fh = HBoxContainer.new()
	fh.add_constant_override("separation", 8)
	foot.add_child(fh)
	var by = HBoxContainer.new()
	by.size_flags_horizontal = SIZE_EXPAND_FILL
	by.add_constant_override("separation", 4)
	by.rect_clip_content = true
	fh.add_child(by)
	var mapped = _label("Mapped by", font_regular, DIM)
	mapped.size_flags_vertical = SIZE_SHRINK_CENTER
	by.add_child(mapped)
	var who = _label(Globals.s(m.get("ownerUsername", "Unknown")), font_bold, LILAC)
	who.size_flags_vertical = SIZE_SHRINK_CENTER
	who.clip_text = true
	who.size_flags_horizontal = SIZE_EXPAND_FILL
	by.add_child(who)

	var dl = Button.new()
	_style_button(dl)
	dl.add_stylebox_override("normal", _pad(_flat(Color(0.2, 0.17, 0.25, 1), 8, Color(LILAC.r, LILAC.g, LILAC.b, 0.45), 1), 12, 6))
	dl.add_stylebox_override("hover", _pad(_flat(Color(0.27, 0.22, 0.33, 1), 8, LILAC, 1), 12, 6))
	dl.rect_min_size = Vector2(118, 32)
	dl.connect("pressed", self, "_on_download_pressed", [m, dl])
	# shown next to Play when you have a map with this name that may be
	# another version: downloads this one too
	var extra = Button.new()
	_style_button(extra)
	extra.text = "↓"
	extra.rect_min_size = Vector2(34, 32)
	extra.hint_tooltip = "You have a map with this name, maybe another version.\nDownload this one too."
	extra.visible = false
	extra.connect("pressed", self, "_start_download", [m, dl])
	fh.add_child(extra)
	fh.add_child(dl)
	var oid := str(m.get("id", ""))
	_buttons_by_id[oid] = dl
	_maps_by_id[oid] = m
	_extra_by_id[oid] = extra
	_update_button(m, dl)
	return card

var _shade_tex: Texture
func _shade_texture() -> Texture:
	if _shade_tex == null:
		var g = Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.05))
		g.set_color(1, Color(0, 0, 0, 0.85))
		g.add_point(0.5, Color(0, 0, 0, 0.2))
		# a 1 px wide vertical strip, stretched over the cover
		var img = Image.new()
		img.create(1, 64, false, Image.FORMAT_RGBA8)
		img.lock()
		for y in range(64):
			img.set_pixel(0, y, g.interpolate(y / 63.0))
		img.unlock()
		var t = ImageTexture.new()
		t.create_from_image(img, Texture.FLAG_FILTER)
		_shade_tex = t
	return _shade_tex

func _update_button(m: Dictionary, b: Button):
	if not is_instance_valid(b):
		return
	var oid := str(m.get("id", ""))
	var extra = _extra_by_id.get(oid)
	if extra != null and is_instance_valid(extra):
		extra.visible = false
	if _downloads.has(oid):
		b.disabled = true
		b.text = "Downloading..."
		b.hint_tooltip = ""
		return
	b.disabled = false
	if _installed_song(m) != null:
		b.text = "▶  Play"
		b.hint_tooltip = "You have this map. Click to pick it in the map list."
	elif _same_name_song(m) != null and Globals.s(m.get("beatmapFile", "")) != "":
		b.text = "▶  Play"
		b.hint_tooltip = "You have a map with this name. Click to pick it in the map list."
		if extra != null and is_instance_valid(extra):
			extra.visible = true
	elif Globals.s(m.get("beatmapFile", "")) == "":
		b.text = "Unavailable"
		b.disabled = true
	else:
		b.text = "↓  Download"
		b.hint_tooltip = "Download this map into the game"

func _refresh_buttons():
	for oid in _buttons_by_id.keys():
		var b = _buttons_by_id[oid]
		if is_instance_valid(b) and _maps_by_id.has(oid):
			_update_button(_maps_by_id[oid], b)

# ------------------------------------------------------------------ images

func _request_image(url: String, target: TextureRect):
	if _img_cache.has(url):
		target.texture = _img_cache[url]
		return
	if _img_waiting.has(url):
		_img_waiting[url].append(target)
		return
	_img_waiting[url] = [target]
	_img_queue.append(url)
	_pump_images()

func _pump_images():
	while _img_active < MAX_IMG_REQUESTS and not _img_queue.empty():
		var url: String = _img_queue.pop_front()
		var r = HTTPRequest.new()
		r.timeout = 20
		r.use_threads = OS.can_use_threads()
		add_child(r)
		r.connect("request_completed", self, "_on_image", [r, url])
		if r.request(url) == OK:
			_img_active += 1
		else:
			r.queue_free()

func _on_image(result: int, code: int, _headers, data: PoolByteArray, r: HTTPRequest, url: String):
	r.queue_free()
	_img_active -= 1
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and data.size() > 0:
		var img = Image.new()
		var err = img.load_webp_from_buffer(data)
		if err != OK: err = img.load_jpg_from_buffer(data)
		if err != OK: err = img.load_png_from_buffer(data)
		if err == OK:
			var t = ImageTexture.new()
			t.create_from_image(img, Texture.FLAG_FILTER)
			_img_cache[url] = t
			_img_order.append(url)
			if _img_order.size() > MAX_IMG_CACHE:
				_img_cache.erase(_img_order.pop_front())
			for target in _img_waiting.get(url, []):
				if is_instance_valid(target):
					target.texture = t
	_img_waiting.erase(url)
	_pump_images()

# ------------------------------------------------------------------ downloads

func _on_download_pressed(m: Dictionary, b: Button):
	var song = _installed_song(m)
	if song == null:
		song = _same_name_song(m)
	if song != null:
		_play(song)
		return
	_start_download(m, b)

func _play(song):
	Rhythia.select_song(song)
	var sidebar = get_node_or_null("../../Sidebar")
	if sidebar != null and sidebar.has_method("press"):
		sidebar.press(0)
	var list = get_node_or_null("../Maps/MapRegistry/S/VBoxContainer")
	if list != null and list.has_method("scroll_to_song"):
		list.call_deferred("scroll_to_song", song.id)

func _start_download(m: Dictionary, b: Button):
	var oid := str(m.get("id", ""))
	var url := Globals.s(m.get("beatmapFile", ""))
	if oid == "" or url == "" or _downloads.has(oid):
		return
	# Downloaded into memory; only the finished map is written to disk (no
	# hidden temp files: antivirus can read those as dropper behaviour).
	var r = HTTPRequest.new()
	r.timeout = 0 # big maps on slow internet; a stalled download is caught in _process
	r.use_threads = OS.can_use_threads()
	r.download_chunk_size = 65536
	add_child(r)
	r.connect("request_completed", self, "_on_download_done", [oid])
	if r.request(url) != OK:
		r.queue_free()
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't start the download.", "Map Browser")
		return
	_downloads[oid] = {"req": r, "map": m, "bytes": 0, "idle": 0.0}
	_update_button(m, b)
	set_process(true)

func _process(delta):
	if _downloads.empty():
		set_process(false)
		return
	for oid in _downloads.keys():
		var d: Dictionary = _downloads[oid]
		var r: HTTPRequest = d.req
		var got := r.get_downloaded_bytes()
		if got != d.bytes:
			d.bytes = got
			d.idle = 0.0
		else:
			d.idle += delta
			if d.idle > STALL_SECONDS:
				r.cancel_request()
				_on_download_done(HTTPRequest.RESULT_TIMEOUT, 0, null, null, oid)
				continue
		var b = _buttons_by_id.get(oid)
		if b == null or not is_instance_valid(b):
			continue
		var total := r.get_body_size()
		if total > 0:
			b.text = "%d%%" % int(100.0 * r.get_downloaded_bytes() / total)
		else:
			b.text = "%.1f MB" % (r.get_downloaded_bytes() / 1048576.0)

func _on_download_done(result: int, code: int, _headers, data, oid: String):
	var d: Dictionary = _downloads.get(oid, {})
	_downloads.erase(oid)
	if d.empty():
		return
	d.req.queue_free()
	var m: Dictionary = d.map
	var title := Globals.s(m.get("title", "map"))
	var dir = Directory.new()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not (data is PoolByteArray) or data.size() < 8:
		var why := "the connection stalled" if result == HTTPRequest.RESULT_TIMEOUT else "error %d / %d" % [result, code]
		Globals.notify(Globals.NOTIFY_WARN, "Download failed (%s). Try again." % why, title)
		_after_download(oid, m)
		return
	# The map id is inside the file, so it's read from a scratch copy first.
	dir.make_dir_recursive(Globals.p("user://cache"))
	var tmp: String = Globals.p("user://cache/browser_map_%s.sspm" % oid)
	if not _write(tmp, data):
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't save the map.", title)
		_after_download(oid, m)
		return
	var song = Song.new()
	var res = song.load_from_sspm(tmp)
	if res is String or String(song.id) == "":
		dir.remove(tmp)
		Globals.notify(Globals.NOTIFY_WARN, "The downloaded file isn't a working map.", title)
		_after_download(oid, m)
		return
	var id := String(song.id)
	var safe_id := id.replace("/", "_").replace("\\", "_").replace(":", "_")
	var existing = _song_by_id(id)
	if existing != null:
		# Same map id as one you have. The very same file? Then you have it.
		# Otherwise it's another version: keep both, this one under its own id.
		if _same_file(tmp, String(existing.filePath)):
			dir.remove(tmp)
			_record[oid] = id
			_save_record()
			Globals.notify(Globals.NOTIFY_INFO, "You already have this map.", title)
			_after_download(oid, m)
			return
		id = id + "__rh" + oid
		safe_id = safe_id + "__rh" + oid
		var mine = _song_by_id(id)
		if mine != null:
			dir.remove(tmp)
			_record[oid] = id
			_save_record()
			Globals.notify(Globals.NOTIFY_INFO, "You already have this map.", title)
			_after_download(oid, m)
			return
	var dest: String = Globals.p("user://maps/%s.sspm" % safe_id)
	dir.remove(tmp)
	if dir.file_exists(dest):
		dir.remove(dest)
	if not _write(dest, data):
		dir.remove(dest)
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't save the map.", title)
		_after_download(oid, m)
		return
	var added = Rhythia.registry_song.add_sspm_map(dest)
	if added:
		_record[oid] = String(added.id)
		_save_record()
		var list = get_node_or_null("../Maps/MapRegistry/S/VBoxContainer")
		if list != null and list.has_method("refresh_songs"):
			list.refresh_songs()
		Globals.notify(Globals.NOTIFY_SUCCEED, "Added to your maps.", title)
	else:
		Globals.notify(Globals.NOTIFY_WARN, "The map downloaded but failed to load.", title)
	_after_download(oid, m)

func _write(path: String, data: PoolByteArray) -> bool:
	var f = File.new()
	if f.open(path, File.WRITE) != OK:
		return false
	f.store_buffer(data)
	f.close()
	return true

func _same_file(a: String, b: String) -> bool:
	var f = File.new()
	if b == "" or not f.file_exists(b) or not f.file_exists(a):
		return false
	var fa = File.new()
	var fb = File.new()
	if fa.open(a, File.READ) != OK:
		return false
	if fb.open(b, File.READ) != OK:
		fa.close()
		return false
	var same: bool = fa.get_len() == fb.get_len()
	fa.close()
	fb.close()
	return same and f.get_sha256(a) == f.get_sha256(b)

func _after_download(oid: String, m: Dictionary):
	var b = _buttons_by_id.get(oid)
	if b != null and is_instance_valid(b):
		_update_button(m, b)

func _exit_tree():
	for oid in _downloads.keys():
		var d: Dictionary = _downloads[oid]
		if is_instance_valid(d.req):
			d.req.cancel_request()
	_downloads.clear()
