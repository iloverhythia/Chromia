extends ReferenceRect
# "Spectate" sidebar page: everyone online in a grid, what they're playing,
# and a Spectate button for those who are playing and allow it (in a lobby or
# not). The list comes from the server (LobbyManager: online_players, about
# once a second while this page is open); watching goes through
# LobbyManager.spectate_player. Settings > Online > Allow Spectators is the
# other side: off, nobody gets a Spectate button for you.

const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)
const PLAYING = Color(0.55, 0.9, 0.65)
const CARD_BG = Color(0.11, 0.105, 0.14, 1)
const CARD_YOU = Color(0.14, 0.12, 0.18, 1)
const FIELD_BG = Color(0.13, 0.125, 0.165, 1)
const BTN_BG = Color(0.1, 0.095, 0.125, 1)
const BTN_HOVER = Color(0.14, 0.13, 0.18, 1)
const BTN_SEL = Color(0.2, 0.17, 0.25, 1)
const CARD_MIN_W = 300
const AVATAR = 52
const MAX_IMG_CACHE = 120
const DEVICE_NAMES = {"pc": "PC", "vr": "PC VR", "quest": "Quest", "mobile": "Phone", "web": "Browser"}
const DIFF_NAMES = ["", "Easy", "Medium", "Hard", "Logic", "Tasukete"]

var font_regular: DynamicFont
var font_bold: DynamicFont
var font_title: DynamicFont
var font_small: DynamicFont
var font_name: DynamicFont
var font_initial: DynamicFont

var _built := false
var _lm = null
var grid: GridContainer
var scroll: ScrollContainer
var info: Label
var subtitle: Label
var search: LineEdit
var playing_only: Button
var _cards := {} # player number -> {card, refs...}
var _list: Array = []
var _you: int = -1
var _img_cache := {} # url -> texture
var _img_order := []
var _img_waiting := {} # url -> [TextureRect]
var _pending_number := -1
var _pending_t := 0.0

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

func _style_button(b: Button, toggle: bool = false, accent: bool = false):
	b.focus_mode = FOCUS_NONE
	b.add_font_override("font", font_bold)
	b.add_color_override("font_color", DIM if toggle else (Color(0.1, 0.07, 0.12) if accent else TEXT))
	b.add_color_override("font_color_hover", Color(0.1, 0.07, 0.12) if accent else TEXT)
	b.add_color_override("font_color_pressed", Color(0.1, 0.07, 0.12) if accent else TEXT)
	b.add_color_override("font_color_disabled", Color(0.45, 0.44, 0.5))
	var n := LILAC if accent else BTN_BG
	var h := Color(0.913725, 0.74902, 0.94902) if accent else BTN_HOVER
	b.add_stylebox_override("normal", _pad(_flat(n, 8), 14, 6))
	b.add_stylebox_override("hover", _pad(_flat(h, 8), 14, 6))
	b.add_stylebox_override("pressed", _pad(_flat(h if accent else BTN_SEL, 8, LILAC, 0 if accent else 1), 14, 6))
	b.add_stylebox_override("disabled", _pad(_flat(Color(0.09, 0.085, 0.11, 1), 8), 14, 6))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.toggle_mode = toggle

static func _fmt_dur(s: int) -> String:
	if s < 60:
		return "just now"
	if s < 3600:
		return "%d:%02d" % [s / 60, s % 60]
	return "%dh %02dm" % [s / 3600, (s % 3600) / 60]

static func _name_color(name: String) -> Color:
	return Color.from_hsv(fmod(abs(hash(name)) / 1000.0, 1.0), 0.45, 0.85)

# ------------------------------------------------------------------ build

func _ready():
	connect("visibility_changed", self, "_on_visibility")
	_lm = get_node_or_null("/root/LobbyManager")

func _on_visibility():
	if is_visible_in_tree():
		if not _built:
			_build()
			_built = true
		if _lm != null:
			if not _lm.is_connected("online_players_received", self, "_on_list"):
				_lm.connect("online_players_received", self, "_on_list")
				_lm.connect("spectate_denied", self, "_on_denied")
				_lm.connect("presence_support_changed", self, "_on_support")
			_lm.subscribe_online()
			if not _lm.online_players.empty():
				_on_list(_lm.online_players, _lm.my_player_number)
		_update_info()
		set_process(true)
	else:
		set_process(false)
		if _lm != null and not _lm.watch_mode:
			_lm.unsubscribe_online()

func _build():
	font_regular = _font("res://assets/font/Lato/Lato-Regular.ttf", 15)
	font_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 15)
	font_title = _font("res://assets/font/Lato/Lato-Black.ttf", 28)
	font_small = _font("res://assets/font/Lato/Lato-Bold.ttf", 12)
	font_name = _font("res://assets/font/Lato/Lato-Black.ttf", 18)
	font_initial = _font("res://assets/font/Lato/Lato-Black.ttf", 24)

	var root = VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.margin_left = 76
	root.margin_right = -24
	root.margin_top = 20
	root.margin_bottom = -56
	root.add_constant_override("separation", 12)
	add_child(root)

	var top = HBoxContainer.new()
	top.add_constant_override("separation", 10)
	root.add_child(top)
	var titles = VBoxContainer.new()
	titles.size_flags_horizontal = SIZE_EXPAND_FILL
	titles.add_constant_override("separation", 0)
	top.add_child(titles)
	titles.add_child(_label("Spectate", font_title, TEXT))
	subtitle = _label("Everyone online, and what they're playing", font_regular, DIM)
	titles.add_child(subtitle)

	search = LineEdit.new()
	search.placeholder_text = "Search players or maps"
	search.rect_min_size = Vector2(240, 0)
	search.size_flags_vertical = SIZE_SHRINK_CENTER
	search.add_font_override("font", font_regular)
	search.add_color_override("font_color", TEXT)
	search.add_stylebox_override("normal", _pad(_flat(FIELD_BG, 8), 12, 8))
	search.add_stylebox_override("focus", _pad(_flat(FIELD_BG, 8, LILAC, 1), 12, 8))
	search.connect("text_changed", self, "_on_filter_changed")
	top.add_child(search)
	if Rhythia.device("mobile") or Rhythia.vr:
		search.rect_min_size = Vector2(170, 0)

	playing_only = Button.new()
	playing_only.text = "Playing only"
	_style_button(playing_only, true)
	playing_only.size_flags_vertical = SIZE_SHRINK_CENTER
	playing_only.connect("toggled", self, "_on_filter_changed")
	top.add_child(playing_only)

	info = _label("", font_bold, DIM)
	info.autowrap = true
	root.add_child(info)

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

func _relayout():
	if grid == null:
		return
	var w: float = scroll.rect_size.x - 14
	grid.columns = int(max(1, floor((w + 14) / (CARD_MIN_W + 14))))
	var cw: float = (w - 14 * (grid.columns - 1)) / grid.columns
	for c in grid.get_children():
		c.rect_min_size.x = cw

func _process(delta):
	if _pending_number != -1:
		_pending_t -= delta
		if _pending_t <= 0.0 or (_lm != null and _lm.watch_mode):
			_pending_number = -1
			_refresh_buttons()

# ------------------------------------------------------------------ list

func _on_support(_supported):
	_update_info()

func _update_info():
	if info == null or _lm == null:
		return
	var text := ""
	if _lm.presence_supported == 0:
		text = "This server doesn't have the Spectate list yet: it needs Savia server 2.1 or newer."
	elif not _lm._connected():
		text = "Connecting to the server..."
	elif _lm.presence_supported == -1:
		text = "Connecting to the server..."
	elif _list.empty():
		text = "Nobody else is online right now."
	elif not Rhythia.allow_spectators:
		text = "Spectators are off for you (Settings > Online), so nobody can watch you."
	info.text = text
	info.visible = text != ""

func _on_list(lst: Array, you: int):
	_list = lst
	_you = you
	var playing := 0
	for p in lst:
		if String(p.get("status", "")) == "playing":
			playing += 1
	if subtitle != null:
		subtitle.text = "%d online, %d playing" % [lst.size(), playing]
	_update_info()
	_rebuild()

func _on_filter_changed(_v = null):
	_rebuild()

func _matches(p: Dictionary) -> bool:
	if playing_only != null and playing_only.pressed and String(p.get("status", "")) != "playing":
		return false
	var q := search.text.strip_edges().to_lower() if search != null else ""
	if q == "":
		return true
	return String(p.get("name", "")).to_lower().find(q) != -1 or String(p.get("song_name", "")).to_lower().find(q) != -1

func _rebuild():
	if grid == null:
		return
	var keep := {}
	var order := []
	# you first, then the server's order (playing first, then by name)
	var shown := []
	for p in _list:
		if p is Dictionary and _matches(p):
			if int(p.get("number", -1)) == _you:
				shown.push_front(p)
			else:
				shown.append(p)
	for p in shown:
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

func _make_card() -> Dictionary:
	var card = PanelContainer.new()
	card.rect_min_size = Vector2(CARD_MIN_W, 0)
	card.add_stylebox_override("panel", _pad(_flat(CARD_BG, 10), 14, 12))
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 8)
	card.add_child(v)

	var head = HBoxContainer.new()
	head.add_constant_override("separation", 12)
	v.add_child(head)
	var av = Control.new()
	av.rect_min_size = Vector2(AVATAR, AVATAR)
	av.mouse_filter = MOUSE_FILTER_IGNORE
	head.add_child(av)
	var circle = Panel.new()
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
	var pic = TextureRect.new()
	pic.anchor_right = 1.0
	pic.anchor_bottom = 1.0
	pic.expand = true
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	pic.visible = false
	av.add_child(pic)

	var who = VBoxContainer.new()
	who.size_flags_horizontal = SIZE_EXPAND_FILL
	who.add_constant_override("separation", 2)
	head.add_child(who)
	var name_row = HBoxContainer.new()
	name_row.add_constant_override("separation", 8)
	who.add_child(name_row)
	var name_l = _label("", font_name, TEXT)
	name_l.clip_text = true
	name_l.size_flags_horizontal = SIZE_EXPAND_FILL
	name_row.add_child(name_l)
	var tag = Label.new()
	tag.add_font_override("font", font_small)
	tag.mouse_filter = MOUSE_FILTER_IGNORE
	name_row.add_child(tag)
	var sub_l = _label("", font_small, DIM)
	who.add_child(sub_l)

	var status_l = _label("", font_bold, DIM)
	v.add_child(status_l)
	var song_l = _label("", font_regular, TEXT)
	song_l.autowrap = true
	song_l.max_lines_visible = 2 # (long names: two lines)
	v.add_child(song_l)
	var extra_l = _label("", font_small, DIM)
	v.add_child(extra_l)

	var foot = HBoxContainer.new()
	foot.add_constant_override("separation", 8)
	v.add_child(foot)
	var note_l = _label("", font_small, DIM)
	note_l.size_flags_horizontal = SIZE_EXPAND_FILL
	note_l.size_flags_vertical = SIZE_SHRINK_CENTER
	note_l.autowrap = true
	foot.add_child(note_l)
	var btn = Button.new()
	btn.text = "Spectate"
	_style_button(btn, false, true)
	btn.connect("pressed", self, "_on_spectate", [btn])
	foot.add_child(btn)
	return {"card": card, "circle": circle, "initial": initial, "pic": pic, "name": name_l, "tag": tag, "sub": sub_l,
		"status": status_l, "song": song_l, "extra": extra_l, "note": note_l, "btn": btn, "url": ""}

func _fill_card(c: Dictionary, p: Dictionary):
	var n := int(p.get("number", -1))
	var is_you := n == _you
	var nm := String(p.get("name", ""))
	if nm == "":
		nm = "Player #%d" % n
	c.card.add_stylebox_override("panel", _pad(_flat(CARD_YOU if is_you else CARD_BG, 10, LILAC, 1 if is_you else 0), 14, 12))
	c.name.text = nm + ("  (you)" if is_you else "")
	var tag_text := String(p.get("tag_text", ""))
	c.tag.visible = tag_text != ""
	if tag_text != "":
		c.tag.text = tag_text
		var tc := String(p.get("tag_color", ""))
		c.tag.add_color_override("font_color", Color(tc) if tc.is_valid_html_color() else ACCENT)
	var dev := String(p.get("device", "pc"))
	c.sub.text = "#%d  ·  %s" % [n, DEVICE_NAMES.get(dev, "PC")]
	# avatar: their Discord picture, else a colored circle with the first letter
	var col := _name_color(nm)
	c.circle.add_stylebox_override("panel", _flat(col, AVATAR / 2))
	c.initial.text = nm.substr(0, 1).to_upper()
	var url := String(p.get("avatar_url", ""))
	if url != c.url:
		c.url = url
		c.pic.visible = false
		if url.begins_with("https://"):
			_load_avatar(url, c.pic)

	var playing := String(p.get("status", "")) == "playing"
	var song := String(p.get("song_name", ""))
	if playing:
		c.status.text = "Playing  ·  " + _fmt_dur(int(p.get("since_s", 0)))
		c.status.add_color_override("font_color", PLAYING)
		c.song.text = song if song != "" else "a map"
		c.song.visible = true
		var bits := []
		var creator := String(p.get("song_creator", ""))
		if creator != "":
			bits.append("mapped by " + creator)
		var d := int(p.get("difficulty", -1))
		if d > 0 and d < DIFF_NAMES.size():
			bits.append(DIFF_NAMES[d])
		c.extra.text = "  ·  ".join(bits)
		c.extra.visible = not bits.empty()
	else:
		c.status.text = "In the menu" if String(p.get("status", "")) == "menu" else String(p.get("status", "")).capitalize()
		c.status.add_color_override("font_color", DIM)
		c.song.visible = false
		c.extra.visible = false

	var notes := []
	if bool(p.get("in_lobby", false)):
		notes.append("In a lobby (%d players)" % int(p.get("lobby_size", 1)))
	var w := int(p.get("watchers", 0))
	if w > 0:
		notes.append("%d watching" % w)
	if playing and not bool(p.get("allow_spectate", true)) and not is_you:
		notes.append("Spectators off")
	if is_you and not Rhythia.allow_spectators:
		notes.append("Your spectators are off")
	c.note.text = "  ·  ".join(notes)

	c.btn.set_meta("number", n)
	c.btn.set_meta("name", nm)
	# only for someone playing who allows it (the server checks again)
	c.btn.visible = bool(p.get("can_spectate", false)) and not is_you
	c.btn.disabled = _pending_number != -1
	c.btn.text = "Joining..." if _pending_number == n else "Spectate"

func _refresh_buttons():
	for n in _cards.keys():
		var c = _cards[n]
		c.btn.disabled = _pending_number != -1
		c.btn.text = "Joining..." if _pending_number == n else "Spectate"

func _on_spectate(btn: Button):
	if _lm == null or _pending_number != -1:
		return
	var n := int(btn.get_meta("number", -1))
	if n < 0:
		return
	if _lm.spectate_player(n):
		_pending_number = n
		_pending_t = 15.0
		_refresh_buttons()
		Globals.notify(Globals.NOTIFY_INFO, "Getting %s's map and play ready..." % String(btn.get_meta("name", "their")), "Spectating")

func _on_denied(reason: String):
	_pending_number = -1
	_refresh_buttons()
	Globals.notify(Globals.NOTIFY_WARN, reason, "Can't spectate")

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
	img.resize(AVATAR * 2, AVATAR * 2, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGBA8)
	img.lock()
	var rr := float(AVATAR)
	for y in range(AVATAR * 2):
		for x in range(AVATAR * 2):
			if Vector2(x + 0.5 - rr, y + 0.5 - rr).length() > rr:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
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
