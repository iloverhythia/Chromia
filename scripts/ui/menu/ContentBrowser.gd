extends ReferenceRect
# "Content Browser" sidebar page (it was the Map Browser): tabs for Maps,
# Colorsets, Note Meshes, Settings Profiles and Cursors. Maps can come from
# rhythia.com (the old Map Browser, MapBrowser.gd, unchanged), from what
# Chromia players uploaded, or from any GitHub repository you paste the link
# of (GithubMaps.gd); the other tabs list players' uploads. Anything can
# be downloaded straight into the game (handy on a standalone VR headset), and
# you can upload your own files or share the colorset / mesh / cursor /
# settings you use now. The server checks each file and its size
# (savia_web server/src/content.js).

const SITE := "https://savia.nysr.host"
const API := SITE + "/savia-content"
const TABS := [["map", "Maps"], ["colorset", "Colorsets"], ["mesh", "Note Meshes"], ["profile", "Settings Profiles"], ["cursor", "Cursors"], ["hitsound", "Hit Sounds"], ["skin", "Skins"]]
const EXT := {"map": "sspm", "colorset": "txt", "mesh": "obj", "profile": "json", "cursor": "png", "hitsound": "ogg", "skin": "cskin"}
const PICK := {"map": "*.sspm ; Maps (.sspm)", "colorset": "*.txt ; Colorsets (.txt)", "mesh": "*.obj ; Note meshes (.obj)",
	"profile": "*.json ; Settings profiles (.json)", "cursor": "*.png, *.jpg, *.jpeg, *.webp ; Pictures",
	"hitsound": "*.ogg, *.mp3, *.wav ; Sounds", "skin": "*.cskin ; Chromia skins (.cskin)"}
const LIMITS := {"map": "30 MB", "colorset": "64 KB", "mesh": "6 MB", "profile": "512 KB", "cursor": "2 MB", "hitsound": "2 MB", "skin": "30 MB"}
const NOUN := {"map": "map", "colorset": "colorset", "mesh": "note mesh", "profile": "settings profile", "cursor": "cursor", "hitsound": "hit sound", "skin": "skin"}
const SORTS := [["new", "Newest"], ["popular", "Most downloaded"], ["name", "Name"]]
const DOWNLOAD_DIR := "user://content_downloads"

const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)
const LILAC := Color(0.764706, 0.65098, 0.8)
const CARD_BG := Color(0.11, 0.105, 0.14, 1)
const BTN_BG := Color(0.1, 0.095, 0.125, 1)
const BTN_HOVER := Color(0.14, 0.13, 0.18, 1)
const BTN_SEL := Color(0.2, 0.17, 0.25, 1)
const CARD_W := 250
const HEAD_H := 104

var kind := "map"
var source := "rhythia" # Maps tab: "rhythia" (rhythia.com), "players" or "github"
var page := 1
var pages := 1
var sort_idx := 0

var _built := false
var f_title: DynamicFont
var f_bold: DynamicFont
var f_reg: DynamicFont
var f_small: DynamicFont
var f_big: DynamicFont
var tab_buttons := {}
var src_buttons := {}
var src_box: HBoxContainer
var rhythia_page: ReferenceRect
var community: VBoxContainer
var github_page: VBoxContainer
var search: LineEdit
var sort_pick: OptionButton
var mine_box: CheckBox
var share_btn: Button
var upload_btn: Button
var info: Label
var scroll: ScrollContainer
var grid: GridContainer
var page_label: Label
var prev_btn: Button
var next_btn: Button
var _qid := 0
var _pics := {} # url -> Texture
var _busy := {} # item id -> true while downloading
var _name_dialog: Control
var _name_edit: LineEdit
var _pending_upload := {} # {path, kind}

func _ready():
	connect("visibility_changed", self, "_on_visibility")

func _on_visibility():
	if is_visible_in_tree() and not _built:
		_built = true
		_build()
		_show_tab("map")

# ------------------------------------------------------------------ building

func _font(path: String, size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return f

func _flat(bg: Color, radius := 4, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _label(text: String, font: Font, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", font)
	l.add_color_override("font_color", col)
	return l

func _button(text: String, method: String, args := [], toggle := false, target: Object = null) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.toggle_mode = toggle
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	b.add_font_override("font", f_bold)
	b.add_stylebox_override("normal", _flat(BTN_BG))
	b.add_stylebox_override("hover", _flat(BTN_HOVER))
	b.add_stylebox_override("pressed", _flat(BTN_SEL, 4, ACCENT, 1))
	b.add_stylebox_override("disabled", _flat(Color(0.08, 0.075, 0.1, 1)))
	b.add_color_override("font_color", TEXT)
	b.add_color_override("font_color_pressed", ACCENT)
	b.add_color_override("font_color_hover", TEXT)
	b.add_color_override("font_color_disabled", DIM)
	b.connect("pressed", target if target != null else self, method, args)
	return b

func _build():
	f_title = _font("res://assets/font/Lato/Lato-Black.ttf", 28)
	f_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 15)
	f_reg = _font("res://assets/font/Lato/Lato-Regular.ttf", 15)
	f_small = _font("res://assets/font/Lato/Lato-Regular.ttf", 13)
	f_big = _font("res://assets/font/Lato/Lato-Black.ttf", 40)

	# header: the title, the tabs, and (Maps) where the maps come from
	var head := VBoxContainer.new()
	head.anchor_right = 1.0
	head.margin_left = 76
	head.margin_right = -24
	head.margin_top = 14
	head.add_constant_override("separation", 8)
	add_child(head)
	var top := HBoxContainer.new()
	top.add_constant_override("separation", 10)
	head.add_child(top)
	top.add_child(_label("Content Browser", f_title))
	var sp := Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(sp)
	src_box = HBoxContainer.new()
	src_box.add_constant_override("separation", 4)
	top.add_child(src_box)
	src_box.add_child(_label("Maps from", f_reg, DIM))
	for s in [["rhythia", "rhythia.com"], ["players", "Chromia players"], ["github", "GitHub"]]:
		var b := _button(s[1], "_on_source", [s[0]], true)
		src_box.add_child(b)
		src_buttons[s[0]] = b
	var tabs := HBoxContainer.new()
	tabs.add_constant_override("separation", 6)
	head.add_child(tabs)
	for t in TABS:
		var b := _button(t[1], "_show_tab", [t[0]], true)
		b.rect_min_size = Vector2(0, 36)
		tabs.add_child(b)
		tab_buttons[t[0]] = b

	# Maps from rhythia.com: the old Map Browser (its own margins fit under the header)
	rhythia_page = ReferenceRect.new()
	rhythia_page.name = "RhythiaMaps"
	rhythia_page.border_color = Color(0, 0, 0, 0)
	rhythia_page.anchor_right = 1.0
	rhythia_page.anchor_bottom = 1.0
	rhythia_page.margin_top = HEAD_H - 16
	rhythia_page.visible = false
	rhythia_page.set_script(load("res://scripts/ui/menu/MapBrowser.gd"))
	add_child(rhythia_page)

	# players' uploads
	community = VBoxContainer.new()
	community.anchor_right = 1.0
	community.anchor_bottom = 1.0
	community.margin_left = 76
	community.margin_right = -24
	community.margin_top = HEAD_H
	community.margin_bottom = -56
	community.add_constant_override("separation", 10)
	add_child(community)
	var bar := HBoxContainer.new()
	bar.add_constant_override("separation", 8)
	community.add_child(bar)
	search = LineEdit.new()
	search.placeholder_text = "Search names and players"
	search.size_flags_horizontal = SIZE_EXPAND_FILL
	search.rect_min_size = Vector2(0, 36)
	search.add_font_override("font", f_reg)
	search.connect("text_entered", self, "_on_search")
	bar.add_child(search)
	sort_pick = OptionButton.new()
	for s in SORTS:
		sort_pick.add_item(s[1])
	sort_pick.add_font_override("font", f_bold)
	sort_pick.rect_min_size = Vector2(170, 36)
	sort_pick.connect("item_selected", self, "_on_sort")
	bar.add_child(sort_pick)
	mine_box = CheckBox.new()
	mine_box.text = "Mine"
	mine_box.focus_mode = FOCUS_NONE
	mine_box.add_font_override("font", f_bold)
	mine_box.connect("toggled", self, "_on_mine")
	bar.add_child(mine_box)
	share_btn = _button("Share yours", "_on_share")
	bar.add_child(share_btn)
	upload_btn = _button("Upload a file", "_on_upload")
	bar.add_child(upload_btn)
	info = _label("", f_small, DIM)
	info.autowrap = true
	community.add_child(info)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	community.add_child(scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_constant_override("hseparation", 10)
	grid.add_constant_override("vseparation", 10)
	scroll.add_child(grid)
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGN_CENTER
	pager.add_constant_override("separation", 12)
	community.add_child(pager)
	prev_btn = _button("< Previous", "_go_page", [-1])
	pager.add_child(prev_btn)
	page_label = _label("", f_bold, DIM)
	pager.add_child(page_label)
	next_btn = _button("Next >", "_go_page", [1])
	pager.add_child(next_btn)
	# Maps from GitHub: any repository you paste the link of (GithubMaps.gd)
	github_page = VBoxContainer.new()
	github_page.name = "GithubMaps"
	github_page.anchor_right = 1.0
	github_page.anchor_bottom = 1.0
	github_page.margin_left = 76
	github_page.margin_right = -24
	github_page.margin_top = HEAD_H
	github_page.margin_bottom = -56
	github_page.visible = false
	github_page.set_script(load("res://scripts/ui/menu/GithubMaps.gd"))
	add_child(github_page)
	github_page.setup(self)
	connect("resized", self, "_relayout")
	_build_name_dialog()

func _relayout():
	if grid == null:
		return
	var w: float = max(scroll.rect_size.x - 14, CARD_W)
	grid.columns = int(max(1, floor((w + 10) / (CARD_W + 10))))

# ------------------------------------------------------------------ tabs

func _show_tab(k: String):
	kind = k
	page = 1
	for t in tab_buttons:
		tab_buttons[t].pressed = t == k
	src_box.visible = k == "map"
	for s in src_buttons:
		src_buttons[s].pressed = s == source
	var players := k != "map" or source == "players"
	var github := k == "map" and source == "github"
	rhythia_page.visible = not players and not github
	community.visible = players
	github_page.visible = github
	if github:
		github_page.opened()
	if players:
		share_btn.visible = k != "map"
		share_btn.hint_tooltip = "Upload the %s you use now" % NOUN[k]
		upload_btn.hint_tooltip = "Upload a %s file (%s at most)" % [NOUN[k], LIMITS[k]]
		call_deferred("_relayout")
		_load()

func _on_source(s: String):
	source = s
	_show_tab("map")

func _on_search(_t := ""):
	page = 1
	_load()

func _on_sort(i: int):
	sort_idx = i
	page = 1
	_load()

func _on_mine(_on: bool):
	page = 1
	_load()

func _go_page(d: int):
	page = int(clamp(page + d, 1, pages))
	_load()

# ------------------------------------------------------------------ the list

func _client_id() -> String:
	return String(Rhythia._ensure_client_id())

func _load():
	_qid += 1
	var qid := _qid
	for c in grid.get_children():
		c.queue_free()
	info.text = "Loading..."
	var url := "%s?kind=%s&sort=%s&page=%d&client_id=%s" % [API, kind, SORTS[sort_idx][0], page, _client_id().http_escape()]
	if search.text.strip_edges() != "":
		url += "&q=" + search.text.strip_edges().http_escape()
	if mine_box.pressed:
		url += "&mine=1"
	var r := HTTPRequest.new()
	r.timeout = 20
	r.use_threads = OS.can_use_threads()
	add_child(r)
	r.connect("request_completed", self, "_on_list", [r, qid])
	if r.request(url) != OK:
		r.queue_free()
		info.text = "Couldn't reach the server."

func _on_list(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, qid: int):
	r.queue_free()
	if qid != _qid:
		return # (an older search)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		info.text = "Couldn't load the list (the server may be down). Try again in a moment."
		return
	var p := JSON.parse(body.get_string_from_utf8())
	if p.error != OK or not (p.result is Dictionary):
		info.text = "The server sent something unexpected."
		return
	var d: Dictionary = p.result
	pages = int(d.get("pages", 1))
	page = int(d.get("page", 1))
	page_label.text = "Page %d of %d" % [page, pages]
	prev_btn.disabled = page <= 1
	next_btn.disabled = page >= pages
	var items: Array = d.get("items", [])
	var total := int(d.get("total", items.size()))
	if items.empty():
		info.text = ("You haven't uploaded any %ss yet." % NOUN[kind]) if mine_box.pressed else ("No %ss here yet. Be the first: upload one (%s at most)." % [NOUN[kind], LIMITS[kind]])
	else:
		info.text = "%d %s%s. Uploads: %s at most each." % [total, NOUN[kind], "" if total == 1 else "s", LIMITS[kind]]
	for it in items:
		if it is Dictionary:
			grid.add_child(_card(it))
	_relayout()

static func _size_text(n: int) -> String:
	if n >= 1048576:
		return "%.1f MB" % (n / 1048576.0)
	return "%d KB" % int(max(1, round(n / 1024.0)))

func _card(it: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.rect_min_size = Vector2(CARD_W, 0)
	var sb := _flat(CARD_BG, 4, Color(1, 1, 1, 0.06), 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 4)
	card.add_child(v)
	v.add_child(_preview(it))
	var name_l := _label(Globals.s(it.get("name", "")), f_bold)
	name_l.clip_text = true
	name_l.hint_tooltip = name_l.text
	v.add_child(name_l)
	var by := _label("by %s" % Globals.s(it.get("by_name", "?")), f_small, LILAC)
	by.clip_text = true
	v.add_child(by)
	var dl := int(it.get("downloads", 0))
	if bool(it.get("server", false)):
		# (a map on the Chromia server: no download count)
		var notes := int(it.get("note_count", 0))
		v.add_child(_label("%s%s%s" % ["Ranked · " if bool(it.get("ranked", false)) else "On the server · ", ("%d notes · " % notes) if notes > 0 else "", _size_text(int(it.get("size", 0)))], f_small, ACCENT if bool(it.get("ranked", false)) else DIM))
	else:
		v.add_child(_label("%s · %d download%s" % [_size_text(int(it.get("size", 0))), dl, "" if dl == 1 else "s"], f_small, DIM))
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 6)
	v.add_child(row)
	var verb: String = {"map": "Download", "colorset": "Add", "mesh": "Add", "profile": "Add", "cursor": "Use", "hitsound": "Use", "skin": "Get"}.get(String(it.get("kind", kind)), "Download")
	var get_btn := _button(verb, "_on_get", [it])
	get_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	get_btn.name = "Get"
	row.add_child(get_btn)
	if String(it.get("kind", kind)) == "hitsound":
		row.add_child(_button("Play", "_on_play", [it]))
	if bool(it.get("mine", false)):
		row.add_child(_button("Delete", "_on_delete", [it]))
	return card

func _preview(it: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.rect_min_size = Vector2(0, 96)
	box.add_stylebox_override("panel", _flat(Color(0.06, 0.055, 0.08, 1), 3))
	var k := String(it.get("kind", kind))
	if k == "colorset" and it.get("colors") is Array:
		var h := HBoxContainer.new()
		h.add_constant_override("separation", 2)
		var cols: Array = it.colors
		for i in range(min(cols.size(), 16)):
			var cr := ColorRect.new()
			cr.color = Color(String(cols[i]))
			cr.size_flags_horizontal = SIZE_EXPAND_FILL
			cr.size_flags_vertical = SIZE_EXPAND_FILL
			h.add_child(cr)
		box.add_child(h)
	elif k == "cursor" and String(it.get("preview", "")) != "":
		var t := TextureRect.new()
		t.expand = true
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(t)
		_show_pic(SITE + String(it.preview), t)
	else:
		var glyph: String = {"map": "♪", "mesh": "◆", "profile": "{ }", "hitsound": "♫", "skin": "✦"}.get(k, "?")
		var l := _label(glyph, f_big, LILAC)
		l.align = Label.ALIGN_CENTER
		l.valign = Label.VALIGN_CENTER
		box.add_child(l)
		if k == "map" and String(it.get("preview", "")).begins_with("/"):
			# the map's cover (a small picture from the server), over the note
			# sign, which stays for a map with none
			var t := TextureRect.new()
			t.expand = true
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			t.mouse_filter = MOUSE_FILTER_IGNORE
			box.rect_clip_content = true
			var edge := _flat(Color(0.06, 0.055, 0.08, 1), 3)
			for m in [MARGIN_LEFT, MARGIN_TOP, MARGIN_RIGHT, MARGIN_BOTTOM]:
				edge.set_default_margin(m, 0) # (the cover fills the box)
			box.add_stylebox_override("panel", edge)
			box.add_child(t)
			_show_pic(SITE + String(it.preview), t)
	return box

# pictures are fetched a few at a time (a page of maps is 30 of them)
const MAX_PICS := 4
var _pic_queue := [] # [url, TextureRect]
var _pic_active := 0
var _no_pic := {} # url -> true (the server has none)

func _show_pic(url: String, t: TextureRect):
	if _pics.has(url):
		t.texture = _pics[url]
		return
	if _no_pic.has(url):
		return
	_pic_queue.append([url, t])
	_next_pic()

func _next_pic():
	while _pic_active < MAX_PICS and not _pic_queue.empty():
		var q: Array = _pic_queue.pop_front()
		var url: String = q[0]
		var t = q[1]
		if not is_instance_valid(t):
			continue # (its card is gone: another page or search)
		if _pics.has(url):
			t.texture = _pics[url]
			continue
		var r := HTTPRequest.new()
		r.timeout = 15
		r.use_threads = OS.can_use_threads()
		add_child(r)
		r.connect("request_completed", self, "_on_pic", [r, url, t])
		if r.request(url) != OK:
			r.queue_free()
			continue
		_pic_active += 1

# png, jpg or webp, told by its first bytes
static func _decode_pic(body: PoolByteArray) -> Image:
	if body.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if body[0] == 0x89 and body[1] == 0x50:
		err = img.load_png_from_buffer(body)
	elif body[0] == 0xff and body[1] == 0xd8:
		err = img.load_jpg_from_buffer(body)
	elif body[0] == 0x52 and body[1] == 0x49 and body[8] == 0x57 and body[9] == 0x45:
		err = img.load_webp_from_buffer(body)
	return img if err == OK and not img.is_empty() else null

func _on_pic(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, url: String, t):
	r.queue_free()
	_pic_active = int(max(0, _pic_active - 1))
	call_deferred("_next_pic")
	if result != HTTPRequest.RESULT_SUCCESS:
		return
	if code != 200:
		if code == 404:
			_no_pic[url] = true
		return
	var img := _decode_pic(body)
	if img == null:
		_no_pic[url] = true
		return
	var tex := ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	_pics[url] = tex
	if _pics.size() > 400:
		_pics.erase(_pics.keys()[0])
	if is_instance_valid(t):
		t.texture = tex

# ------------------------------------------------------------------ getting one

func _on_get(it: Dictionary):
	var id := String(it.get("id", ""))
	if id == "" or _busy.has(id):
		return
	_busy[id] = true
	var r := HTTPRequest.new()
	r.timeout = 180
	r.use_threads = OS.can_use_threads()
	add_child(r)
	r.connect("request_completed", self, "_on_got", [r, it])
	if r.request(_file_url(it)) != OK:
		r.queue_free()
		_busy.erase(id)
	else:
		Globals.notify(Globals.NOTIFY_INFO, "Downloading %s..." % Globals.s(it.get("name", "")), "Content Browser")

# where a list item's file comes from: a map on the server has its own link
func _file_url(it: Dictionary) -> String:
	var u := Globals.s(it.get("url", ""))
	if u.begins_with("/savia-maps/"):
		return SITE + u
	return "%s/file/%s" % [API, String(it.get("id", ""))]

# the file type: a hit sound keeps its own (.ogg / .mp3 / .wav)
func _ext_of(it: Dictionary) -> String:
	var e := Globals.s(it.get("ext", "")).to_lower()
	if e in ["ogg", "mp3", "wav"]:
		return e
	return EXT.get(String(it.get("kind", kind)), "bin")

# a hit sound heard before using it
var _sounds := {} # item id -> AudioStream
var _player: AudioStreamPlayer
func _on_play(it: Dictionary):
	var id := String(it.get("id", ""))
	if _sounds.has(id):
		_play(_sounds[id])
		return
	var r := HTTPRequest.new()
	r.timeout = 30
	add_child(r)
	r.connect("request_completed", self, "_on_play_got", [r, id])
	if r.request(_file_url(it)) != OK:
		r.queue_free()

func _on_play_got(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, id: String):
	r.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.empty():
		return
	var st = Globals.audioLoader.load_buffer(body)
	if st == null or st == Globals.error_sound or not (st is AudioStream):
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't play that sound.", "Content Browser")
		return
	_sounds[id] = st
	_play(st)

func _play(st: AudioStream):
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
		add_child(_player)
	_player.stream = st
	_player.play()

static func _safe_name(n: String) -> String:
	var out := ""
	for ch in n:
		out += ch if (ch.is_valid_identifier() or ch in [" ", "-", "(", ")", "."] or (ch >= "0" and ch <= "9")) else "_"
	out = out.strip_edges()
	return out.left(60) if out != "" else "download"

func _on_got(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, it: Dictionary):
	r.queue_free()
	_busy.erase(String(it.get("id", "")))
	var k := String(it.get("kind", kind))
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.empty():
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't download that %s. Try again in a moment." % NOUN.get(k, "file"), "Content Browser")
		return
	var d := Directory.new()
	d.make_dir_recursive(Globals.p(DOWNLOAD_DIR))
	var path: String = Globals.p(DOWNLOAD_DIR).plus_file("%s.%s" % [_safe_name(Globals.s(it.get("name", ""))), _ext_of(it)])
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't save the download.", "Content Browser")
		return
	f.store_buffer(body)
	f.close()
	_install(k, path, Globals.s(it.get("name", "")))
	# (the count went up)
	if community.visible:
		_load()

func _install(k: String, path: String, title: String):
	install(get_tree(), k, path, title)

# puts a downloaded file to use (the Content Browser and chat share links)
static func install(tree: SceneTree, k: String, path: String, title: String):
	match k:
		"map":
			var run = Rhythia.menu_node("Main/Maps/Results/Results/RS/H1/Info/Run")
			var song = null
			if run and run.has_method("_import_sspm"):
				song = run._import_sspm(path)
			else:
				# (not in the menu, e.g. watching someone: the import works the
				# same without the menu's button)
				var tmp = load("res://scripts/ui/menu/buttons/RunMapButton.gd").new()
				song = tmp._import_sspm(path)
				tmp.free()
			var list = Rhythia.menu_node("Main/Maps/MapRegistry/S/VBoxContainer")
			if list and list.has_method("refresh_songs"):
				list.refresh_songs()
			if song != null:
				Globals.notify(Globals.NOTIFY_SUCCEED, "'%s' is in your map list now." % title, "Map Downloaded")
			return song
		"hitsound":
			# (a new hit sound in Settings, picked now)
			var snd = _same_hit_sound(path)
			if snd == null:
				snd = Rhythia.create_named_sound_from_file("hit", title if title != "" else "Downloaded", path)
			if snd != null:
				Rhythia.select_hit_sound(snd)
				Rhythia.save_settings()
				Globals.notify(Globals.NOTIFY_SUCCEED, "'%s' is your hit sound now (Settings > Video & Audio to change it)." % title, "Hit Sound")
			else:
				Globals.notify(Globals.NOTIFY_WARN, "Couldn't add that hit sound.", "Content Browser")
		"cursor":
			for ext in ["png", "jpg", "jpeg", "webp", "bmp", "gif"]:
				var old: String = Globals.p("user://cursor." + ext)
				if File.new().file_exists(old):
					Directory.new().remove(old)
			if Directory.new().copy(path, Globals.p("user://cursor.png")) == OK:
				Globals.notify(Globals.NOTIFY_SUCCEED, "'%s' is your cursor now (Settings > World & Cursor to change it)." % title, "Cursor")
		"skin":
			# kept in My skins, and shown in Settings > Skins to put on (it says
			# what it has and keeps your look first)
			var Skin = load("res://scripts/Skin.gd")
			var r: Dictionary = Skin.read_file(path)
			if r.has("error"):
				Globals.notify(Globals.NOTIFY_WARN, String(r.error), "Skin")
				return
			Directory.new().make_dir_recursive(Globals.p(Skin.SKINS_DIR))
			var dst: String = Globals.p(Skin.SKINS_DIR).plus_file(Skin._clean_name((title if title != "" else String(r.data.name)) + "." + Skin.EXT, "skin." + Skin.EXT))
			if Directory.new().copy(path, dst) != OK:
				dst = path
			var sb = Rhythia.menu_node("Sidebar")
			var settings = Rhythia.menu_node("Main/Settings")
			if sb != null and settings != null and sb.has_method("press_page"):
				sb.press_page(settings)
			if load("res://scripts/ui/settings/SkinsTab.gd").import_dropped(tree, dst):
				Globals.notify(Globals.NOTIFY_SUCCEED, "'%s' is in My skins. Press Put on in Settings > Skins to wear it." % title, "Skin")
			else:
				Globals.notify(Globals.NOTIFY_SUCCEED, "'%s' is in My skins (Settings > Skins)." % title, "Skin")
		_:
			# colorsets, note meshes and settings profiles: added like Settings > Import Content
			if not load("res://scripts/ui/settings/Profiles.gd").import_dropped(tree, PoolStringArray([path])):
				Globals.notify(Globals.NOTIFY_WARN, "Open Settings once, then press it again.", "Content Browser")

# ------------------------------------------------------------------ uploading

func _on_upload():
	Globals.file_sel.open_file(self, "_on_upload_picked", PoolStringArray([PICK[kind]]), false, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))

func _on_upload_picked(files):
	if files == null or files.size() == 0:
		return
	var p := String(files[0])
	_ask_name(p, kind, p.get_file().get_basename())

# the colorset / mesh / cursor / settings you use now
func _on_share():
	var d: Dictionary = prepare_share(kind)
	if d.has("error"):
		Globals.notify(Globals.NOTIFY_WARN, String(d.error), "Content Browser")
		return
	_ask_name(String(d.path), kind, String(d.name))

# the file to share for one kind of content, from your current settings:
# {path, name} or {error} (the Share button and the chat's /share)
static func prepare_share(k: String) -> Dictionary:
	var spec = load("res://scripts/SpectateSettings.gd")
	var d := Directory.new()
	d.make_dir_recursive(Globals.p(DOWNLOAD_DIR))
	match k:
		"colorset":
			var cs = Rhythia.selected_colorset
			if cs == null or cs.colors.empty():
				return {"error": "Pick a colorset in Settings first."}
			var lines := PoolStringArray()
			for c in cs.colors:
				lines.append("#" + Color(c).to_html(false))
			if bool(cs.get("mirror")):
				lines.append("m")
			var p: String = Globals.p(DOWNLOAD_DIR).plus_file("share_colorset.txt")
			var f := File.new()
			if f.open(p, File.WRITE) != OK:
				return {"error": "Couldn't write the colorset file."}
			f.store_string(lines.join("\n") + "\n")
			f.close()
			return {"path": p, "name": String(cs.name)}
		"mesh":
			var m: String = spec.own_mesh_file()
			if m == "":
				return {"error": "Your note mesh comes with the game, so everyone has it already. Pick one of your own meshes in Settings > Meshes to share it."}
			return {"path": m, "name": m.get_file().get_basename()}
		"cursor":
			var c: String = spec.own_cursor_file()
			if c == "":
				return {"error": "You use the default cursor. Set a cursor picture in Settings > World & Cursor to share it."}
			return {"path": c, "name": "My cursor"}
		"hitsound":
			var hs = Rhythia.selected_hit_sound
			var hp := ""
			if hs != null and String(hs.path) != "":
				hp = _audio_file(String(hs.path))
			else:
				hp = _audio_file("user://hit")
			if hp == "":
				return {"error": "You use the game's own hit sound. Add one of yours in Settings first to share it."}
			return {"path": hp, "name": String(hs.name) if hs != null and String(hs.path) != "" else "My hit sound"}
		"profile":
			var p2: String = Globals.p(DOWNLOAD_DIR).plus_file("share_settings.json")
			Rhythia.save_settings(p2)
			return {"path": p2, "name": "My settings"}
		"skin":
			# everything you have on, as a Chromia skin (Settings > Skins)
			var Skin = load("res://scripts/Skin.gd")
			var sname: String = "%s's look" % Skin.author_name() if Skin.author_name() != "" else "My look"
			var p3: String = Globals.p(DOWNLOAD_DIR).plus_file("share_skin.cskin")
			var r: Dictionary = Skin.save_to(p3, sname)
			if r.has("error"):
				return {"error": String(r.error)}
			return {"path": p3, "name": sname}
		"map":
			var song = Rhythia.selected_song
			if song == null:
				return {"error": "Pick a map first."}
			var mp := String(song.get("filePath")) if song.get("filePath") != null else ""
			if not mp.to_lower().ends_with(".sspm") or not File.new().file_exists(mp):
				var conv: String = Globals.p("user://maps/%s.sspm" % String(song.id))
				mp = conv if File.new().file_exists(conv) else ""
			if mp == "":
				return {"error": "Only .sspm maps can be shared. Convert this map to .sspm first (in the map's menu)."}
			var nm := String(song.name)
			if String(song.creator) != "":
				nm += " - " + String(song.creator)
			return {"path": mp, "name": nm.left(60), "song_id": String(song.id)}
	return {"error": "That can't be shared."}

# a hit sound you have already with this very file (used again, not copied)
static func _same_hit_sound(path: String):
	var sha: String = File.new().get_sha256(path)
	for snd in Rhythia.registry_hit_sound.get_items():
		if String(snd.path) == "":
			continue
		var p := _audio_file(String(snd.path))
		if p != "" and File.new().get_sha256(p) == sha:
			return snd
	return null

# a sound's real file (its path may leave out .ogg / .mp3 / .wav)
static func _audio_file(base: String) -> String:
	var p: String = Globals.p(base)
	var f := File.new()
	if f.file_exists(p) and p.get_extension().to_lower() in ["ogg", "mp3", "wav"]:
		return p
	for e in ["ogg", "mp3", "wav"]:
		if f.file_exists(p + "." + e):
			return p + "." + e
	return ""

func _build_name_dialog():
	_name_dialog = ColorRect.new()
	_name_dialog.color = Color(0, 0, 0, 0.6)
	_name_dialog.anchor_right = 1.0
	_name_dialog.anchor_bottom = 1.0
	_name_dialog.visible = false
	add_child(_name_dialog)
	var c := CenterContainer.new()
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	_name_dialog.add_child(c)
	var panel := PanelContainer.new()
	var sb := _flat(Color(0.09, 0.085, 0.12, 1), 4, Color(1, 1, 1, 0.12), 1)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_stylebox_override("panel", sb)
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.rect_min_size = Vector2(420, 0)
	v.add_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label("Name it", f_title))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 60
	_name_edit.rect_min_size = Vector2(0, 38)
	_name_edit.add_font_override("font", f_reg)
	_name_edit.connect("text_entered", self, "_on_name_ok")
	v.add_child(_name_edit)
	v.add_child(_label("Everyone can see and download it. Upload only what you made or may share.", f_small, DIM))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGN_END
	row.add_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(_button("Cancel", "_on_name_cancel"))
	row.add_child(_button("Upload", "_on_name_ok"))

func _ask_name(path: String, k: String, suggested: String):
	_pending_upload = {"path": path, "kind": k}
	_name_edit.text = suggested.left(60)
	_name_dialog.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()

func _on_name_cancel():
	_name_dialog.visible = false
	_pending_upload = {}

func _on_name_ok(_t := ""):
	_name_dialog.visible = false
	if _pending_upload.empty():
		return
	var up: Dictionary = _pending_upload
	_pending_upload = {}
	var f := File.new()
	if f.open(String(up.path), File.READ) != OK:
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't open that file.", "Upload")
		return
	var data := f.get_buffer(f.get_len())
	f.close()
	var r := HTTPRequest.new()
	r.timeout = 300
	r.use_threads = OS.can_use_threads()
	add_child(r)
	r.connect("request_completed", self, "_on_uploaded", [r, String(up.kind)])
	var url := "%s/upload/%s?client_id=%s&name=%s" % [API, String(up.kind), _client_id().http_escape(), _name_edit.text.strip_edges().http_escape()]
	if r.request_raw(url, ["Content-Type: application/octet-stream"], true, HTTPClient.METHOD_POST, data) != OK:
		r.queue_free()
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't reach the server.", "Upload")
	else:
		Globals.notify(Globals.NOTIFY_INFO, "Uploading...", "Upload")

func _on_uploaded(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, k: String):
	r.queue_free()
	var p = JSON.parse(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
	if p == null or p.error != OK or not (p.result is Dictionary):
		Globals.notify(Globals.NOTIFY_WARN, "The upload didn't go through (HTTP %d). Try again in a moment." % code, "Upload")
		return
	var d: Dictionary = p.result
	if not bool(d.get("ok", false)):
		Globals.notify(Globals.NOTIFY_WARN, "Not uploaded: %s." % Globals.s(d.get("error", "unknown error")), "Upload")
		return
	if bool(d.get("existing", false)):
		Globals.notify(Globals.NOTIFY_INFO, "That %s is in the Content Browser already." % NOUN.get(k, "file"), "Upload")
	else:
		Globals.notify(Globals.NOTIFY_SUCCEED, "Uploaded! Everyone can download it now.", "Upload")
	if kind == k and community.visible:
		_load()

func _on_delete(it: Dictionary):
	var r := HTTPRequest.new()
	r.timeout = 20
	add_child(r)
	r.connect("request_completed", self, "_on_deleted", [r])
	var url := "%s/delete/%s?client_id=%s" % [API, String(it.get("id", "")), _client_id().http_escape()]
	if r.request(url, [], true, HTTPClient.METHOD_POST, "") != OK:
		r.queue_free()

func _on_deleted(_result: int, _code: int, _h, body: PoolByteArray, r: HTTPRequest):
	r.queue_free()
	var p := JSON.parse(body.get_string_from_utf8())
	if p.error == OK and p.result is Dictionary and bool(p.result.get("ok", false)):
		Globals.notify(Globals.NOTIFY_SUCCEED, "Deleted.", "Content Browser")
	else:
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't delete it.", "Content Browser")
	_load()
