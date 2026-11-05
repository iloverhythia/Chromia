extends Control

# Modern UI (ModernUI.gd): the Online Players window, opened by the people
# button in the bottom-right corner (SpectatePage.gd's button, which hands
# over to this while the Modern UI is on).
#   - a header card: "Online Players", how many are on, close
#   - a search box and the favourites filter
#   - everyone online as wide cards, 4 a row: picture, name, what they're
#     doing, their leaderboard place (their banner behind it, if they have one).
#     Click someone who's playing to watch them; right-click for their profile.
#   - the chat underneath: the channels on the left (Global, and Lobby while
#     you're in one), the messages and the message box on the right
# The list and the chat come from LobbyManager, like the classic Spectate window.

const COLS := 4
const CHAT_MAX := 200

var ui # ModernUI
var lm
var dim: Control
var head: Control
var body: Control
var search: LineEdit
var fav_btn: Button
var fav_icon: Control
var scroll: ScrollContainer
var grid: GridContainer
var info: Label
var chans: VBoxContainer
var chan_box: Control
var chat_box: Control
var chat_title: Label
var chat: RichTextLabel
var chat_input: LineEdit
var send_btn: Button
var join_btn: Button
var close_btn: Button
var title_l: Label
var sub_l: Label

var _open := false
var _list: Array = []
var _you := -1
var _cards := {} # number -> card
var _channel := "global"
var _chat_sizes := []
var _pics := {} # url -> texture
var _waiting := {} # url -> [controls]
var _fonts := {}

func _init(modern):
	ui = modern
	name = "Online"
	anchor_right = 1
	anchor_bottom = 1
	visible = false
	mouse_filter = MOUSE_FILTER_STOP

func _f(file: String, size: int) -> DynamicFont:
	var key := file + String(size)
	if not _fonts.has(key):
		_fonts[key] = ui._font(file, size)
	return _fonts[key]

func _ready():
	lm = get_node_or_null("/root/LobbyManager")
	var k: float = ui.k
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	dim.connect("gui_input", self, "_on_dim")
	add_child(dim)
	head = Control.new()
	head.connect("draw", self, "_draw_card", [head])
	add_child(head)
	title_l = ui._label("Online Players", _f("ExtraBold", 15))
	head.add_child(title_l)
	sub_l = ui._label("", _f("Bold", 12), Color("#b9b8c0"))
	head.add_child(sub_l)
	close_btn = ui._button(Color(0, 0, 0, 0), Color(1, 1, 1, 0.08), 6)
	close_btn.add_child(ui.MIcon.make("x", 20 * k, Color(1, 1, 1), 2.6))
	close_btn.connect("pressed", self, "close")
	head.add_child(close_btn)

	body = Control.new()
	body.connect("draw", self, "_draw_card", [body])
	add_child(body)
	search = LineEdit.new()
	search.placeholder_text = "Search players..."
	_style_field(search, 12)
	search.connect("text_changed", self, "_on_search")
	body.add_child(search)
	fav_btn = ui._button(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.09), 6)
	fav_btn.toggle_mode = true
	fav_btn.hint_tooltip = "Only your favourites"
	fav_icon = ui.MIcon.make("heart", 15 * k, Color("#d7d6dc"))
	fav_btn.add_child(fav_icon)
	fav_btn.connect("toggled", self, "_on_fav_filter")
	body.add_child(fav_btn)
	scroll = ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	_style_scroll(scroll.get_v_scrollbar())
	body.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = COLS
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(grid)
	info = ui._label("", _f("SemiBold", 11), ui.DIM)
	info.visible = false
	body.add_child(info)

	# the chat
	chan_box = Control.new()
	chan_box.connect("draw", self, "_draw_box", [chan_box])
	body.add_child(chan_box)
	chan_box.add_child(ui._label("Channels", _f("Bold", 10), Color("#c9c8cf")))
	chans = VBoxContainer.new()
	chans.add_constant_override("separation", int(5 * k))
	chan_box.add_child(chans)
	join_btn = ui._button(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.09), 5)
	join_btn.text = "Join"
	join_btn.hint_tooltip = "Join a friend's lobby with its code"
	join_btn.add_font_override("font", _f("Bold", 10))
	join_btn.add_color_override("font_color", ui.TEXT)
	join_btn.connect("pressed", self, "_on_join")
	chan_box.add_child(join_btn)
	chat_box = Control.new()
	chat_box.connect("draw", self, "_draw_box", [chat_box])
	body.add_child(chat_box)
	chat_title = ui._label("Global", _f("Bold", 10), ui.TEXT)
	chat_box.add_child(chat_title)
	chat = RichTextLabel.new()
	chat.scroll_following = true
	chat.selection_enabled = true
	chat.add_font_override("normal_font", _f("Bold", 10))
	chat.add_font_override("bold_font", _f("ExtraBold", 10))
	chat.add_color_override("default_color", ui.TEXT)
	_style_scroll(chat.get_v_scroll())
	chat_box.add_child(chat)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Write a message..."
	chat_input.max_length = 300
	_style_field(chat_input, 11)
	chat_input.connect("text_entered", self, "_on_send")
	chat_box.add_child(chat_input)
	var emoji = load("res://scripts/ui/ChatReactions.gd")
	if true:
		var eb = emoji.picker_button(chat_input, int(12 * k))
		eb.name = "Emoji"
		eb.flat = true
		eb.rect_min_size = Vector2(22, 22) * k
		chat_box.add_child(eb)
	send_btn = ui._button(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.09), 5)
	send_btn.text = "Send"
	send_btn.add_font_override("font", _f("ExtraBold", 11))
	send_btn.add_color_override("font_color", ui.TEXT)
	send_btn.connect("pressed", self, "_on_send")
	chat_box.add_child(send_btn)

	if lm != null:
		lm.connect("online_players_received", self, "_on_list")
		lm.connect("global_chat_message_received", self, "_on_chat")
		lm.connect("chat_message_received", self, "_on_lobby_chat")
		if lm.has_signal("chat_reactions_changed"):
			lm.connect("chat_reactions_changed", self, "_on_reactions")
		lm.connect("spectate_denied", self, "_on_denied")
	layout()

func _style_field(e: LineEdit, size: int):
	var k: float = ui.k
	e.add_font_override("font", _f("Bold", size))
	e.add_color_override("font_color", ui.TEXT)
	e.add_color_override("font_color_placeholder", Color("#8d8c95"))
	e.add_color_override("cursor_color", ui.TEXT)
	for st in ["normal", "focus", "read_only"]:
		var sb = ui._flat(Color(1, 1, 1, 0.045 if st != "focus" else 0.07), 6)
		sb.content_margin_left = 9 * k
		sb.content_margin_right = 9 * k
		e.add_stylebox_override(st, sb)

func _style_scroll(bar: ScrollBar):
	var k: float = ui.k
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2 * k
	empty.content_margin_right = 2 * k
	bar.add_stylebox_override("scroll", empty)
	bar.add_stylebox_override("scroll_focus", empty)
	for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_stylebox_override(st, ui._flat(Color(1, 1, 1, 0.22 if st == "grabber" else 0.35), 2))
	bar.rect_min_size.x = 4 * k

func _draw_card(c: Control):
	c.draw_style_box(ui._flat(Color("#101010"), 8 * ui.k, Color(1, 1, 1, 0.075), 1), Rect2(Vector2(), c.rect_size))

func _draw_box(c: Control):
	c.draw_style_box(ui._flat(Color("#0d0d0d"), 7 * ui.k, Color(1, 1, 1, 0.1), 1), Rect2(Vector2(), c.rect_size))

func layout():
	if body == null:
		return
	var k: float = ui.k
	var s: Vector2 = ui.rect_size
	var m := 15.0 * k
	head.rect_position = Vector2(m, 20 * k)
	head.rect_size = Vector2(s.x - m * 2, 56 * k)
	title_l.rect_position = Vector2(13 * k, 9 * k)
	sub_l.rect_position = Vector2(13 * k, 30 * k)
	close_btn.rect_size = Vector2(30, 30) * k
	close_btn.rect_position = Vector2(head.rect_size.x - 42 * k, 13 * k)
	close_btn.get_child(0).rect_position = Vector2(5, 5) * k
	close_btn.get_child(0).rect_size = Vector2(20, 20) * k
	body.rect_position = Vector2(m, 85 * k)
	body.rect_size = Vector2(s.x - m * 2, s.y - 85 * k - 21 * k)
	var bw := body.rect_size.x
	var bh := body.rect_size.y
	var p := 9.0 * k
	search.rect_position = Vector2(p, p)
	search.rect_size = Vector2(bw - p * 3 - 29 * k, 29 * k)
	fav_btn.rect_position = Vector2(bw - p - 29 * k, p)
	fav_btn.rect_size = Vector2(29, 29) * k
	fav_icon.rect_position = Vector2(7, 7) * k
	fav_icon.rect_size = Vector2(15, 15) * k
	var chat_h: float = clamp(bh * 0.33, 150 * k, 230 * k)
	scroll.rect_position = Vector2(p, p + 38 * k)
	scroll.rect_size = Vector2(bw - p * 2 + 6 * k, bh - chat_h - p * 2 - 50 * k)
	info.rect_position = scroll.rect_position + Vector2(4 * k, 8 * k)
	var gap := 7.0 * k
	grid.add_constant_override("hseparation", int(gap))
	grid.add_constant_override("vseparation", int(gap))
	var cw := floor((bw - p * 2 - gap * (COLS - 1) - 2 * k) / COLS)
	for c in grid.get_children():
		c.rect_min_size = Vector2(cw, 56 * k)
	var cy := bh - chat_h - p - 6 * k
	chan_box.rect_position = Vector2(16 * k, cy)
	chan_box.rect_size = Vector2(167 * k, chat_h)
	chan_box.get_child(0).rect_position = Vector2(9 * k, 9 * k)
	chans.rect_position = Vector2(9 * k, 27 * k)
	chans.rect_size = Vector2(149 * k, chat_h - 70 * k)
	join_btn.rect_position = Vector2(9 * k, chat_h - 36 * k)
	join_btn.rect_size = Vector2(149 * k, 27 * k)
	chat_box.rect_position = Vector2(189 * k, cy)
	chat_box.rect_size = Vector2(bw - 189 * k - 26 * k, chat_h)
	var cbw := chat_box.rect_size.x
	chat_title.rect_position = Vector2(9 * k, 9 * k)
	chat.rect_position = Vector2(9 * k, 24 * k)
	chat.rect_size = Vector2(cbw - 18 * k, chat_h - 68 * k)
	chat_input.rect_position = Vector2(9 * k, chat_h - 38 * k)
	var eb = chat_box.get_node_or_null("Emoji")
	var right := 70.0 * k
	if eb != null:
		eb.rect_size = Vector2(22, 22) * k
		eb.rect_position = Vector2(cbw - 102 * k, chat_h - 34.5 * k)
		right = 106.0 * k
	chat_input.rect_size = Vector2(cbw - right - 9 * k, 29 * k)
	send_btn.rect_position = Vector2(cbw - 75 * k, chat_h - 38 * k)
	send_btn.rect_size = Vector2(66, 29) * k
	for c in _cards.values():
		c.update()

# ------------------------------------------------------------------ open / close

func open():
	if _open:
		return
	_open = true
	visible = true
	raise()
	layout()
	_fill_channels()
	_fill_chat()
	if lm != null:
		lm.subscribe_online()
		if not lm.online_players.empty():
			_on_list(lm.online_players, lm.my_player_number)
	_update_sub()
	modulate.a = 0.0 # (fades in: _process)
	if not Rhythia.device("mobile"):
		chat_input.call_deferred("grab_focus")
	set_process(true)

func close():
	if not _open:
		return
	_open = false
	visible = false
	if lm != null and not lm.watch_mode:
		lm.unsubscribe_online()
	if chat_input.has_focus():
		chat_input.release_focus()

func is_open() -> bool:
	return _open

func _process(delta):
	if visible and modulate.a < 1.0:
		modulate.a = min(1.0, modulate.a + delta * 8.0)

func _input(ev):
	if _open and ev is InputEventKey and ev.pressed and not ev.echo and ev.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()

func _on_dim(ev):
	if ev is InputEventMouseButton and ev.pressed:
		close()

# ------------------------------------------------------------------ players

func _update_sub():
	var n := _list.size()
	sub_l.text = "Currently active players: %d" % n
	var t := ""
	if grid.get_child_count() > 0:
		pass
	elif lm == null or lm.presence_supported == 0:
		t = "This server doesn't have the online list yet."
	elif not lm._connected() or lm.presence_supported == -1:
		t = "Connecting to the server..."
	else:
		t = "None of your favourites are online." if fav_btn.pressed else ("Nobody matches that." if search.text != "" else "Nobody else is online right now.")
	info.text = t
	info.visible = t != ""

func _on_list(lst: Array, you: int):
	_list = lst
	_you = you
	if _open:
		_rebuild()

func _on_search(_t):
	_rebuild()

func _on_fav_filter(on: bool):
	fav_icon.filled = on
	fav_icon.color = Color("#ff7aa2") if on else Color("#d7d6dc")
	fav_icon.update()
	_rebuild()

func _matches(p: Dictionary) -> bool:
	if fav_btn.pressed and not Rhythia.spectate_favorites.has(int(p.get("number", -1))):
		return false
	var q := search.text.strip_edges().to_lower()
	return q == "" or String(p.get("name", "")).to_lower().find(q) != -1 or String(p.get("song_name", "")).to_lower().find(q) != -1

static func _rank_of(p: Dictionary) -> int:
	var r = p.get("rank", null)
	return int(r) if (typeof(r) == TYPE_INT or typeof(r) == TYPE_REAL) and int(r) > 0 else 1 << 30

func _by_rank(a: Dictionary, b: Dictionary) -> bool:
	var ra := _rank_of(a)
	var rb := _rank_of(b)
	if ra != rb:
		return ra < rb
	return String(a.get("name", "")).to_lower() < String(b.get("name", "")).to_lower()

func _rebuild():
	var shown := []
	for p in _list:
		if p is Dictionary and _matches(p):
			shown.append(p)
	shown.sort_custom(self, "_by_rank")
	var keep := {}
	var i := 0
	for p in shown:
		var n := int(p.get("number", -1))
		keep[n] = true
		var c = _cards.get(n)
		if c == null or not is_instance_valid(c):
			c = _make_card()
			grid.add_child(c)
			_cards[n] = c
		c.set_meta("p", p)
		grid.move_child(c, i)
		i += 1
		var url := String(p.get("avatar_url", ""))
		if url != "":
			_pic(url, c, "pic")
		var ban := String(p.get("banner_url", ""))
		if ban != "":
			_pic(ban, c, "banner")
		c.hint_tooltip = _tip(p)
		c.mouse_default_cursor_shape = CURSOR_POINTING_HAND if _can_watch(p) else CURSOR_ARROW
		c.update()
	for n in _cards.keys():
		if not keep.has(n):
			if is_instance_valid(_cards[n]):
				_cards[n].queue_free()
			_cards.erase(n)
	layout()
	_update_sub()

func _make_card() -> Control:
	var c := Control.new()
	c.mouse_filter = MOUSE_FILTER_STOP
	c.connect("draw", self, "_draw_player", [c])
	c.connect("gui_input", self, "_on_card_input", [c])
	c.connect("mouse_entered", self, "_hover", [c, true])
	c.connect("mouse_exited", self, "_hover", [c, false])
	return c

func _hover(c: Control, on: bool):
	c.set_meta("hover", on)
	c.update()

func _status(p: Dictionary) -> String:
	var st := String(p.get("status", ""))
	var song := String(p.get("song_name", ""))
	match st:
		"playing":
			return "Playing " + (song if song != "" else "a map")
		"spectating", "watching":
			return "Spectating " + (song if song != "" else "someone")
		"afk":
			return "AFK"
		"mapping", "editing":
			return "Mapping" + ((" " + song) if song != "" else "")
		"lobby":
			return "In a lobby"
	if bool(p.get("in_lobby", false)):
		return "In a lobby"
	return "Idle" if st == "" or st == "menu" or st == "idle" else st.capitalize()

func _can_watch(p: Dictionary) -> bool:
	if int(p.get("number", -1)) == _you:
		return false
	return bool(p.get("can_spectate", false)) or (lm != null and lm.i_am_staff and bool(p.get("can_spectate_staff", false)))

func _tip(p: Dictionary) -> String:
	var bits := [String(p.get("name", ""))]
	bits.append(_status(p))
	if _can_watch(p):
		bits.append("Click to watch")
	elif String(p.get("status", "")) == "playing" and not bool(p.get("allow_spectate", true)):
		bits.append("Spectators are off for them")
	bits.append("Right-click: profile")
	return PoolStringArray(bits).join("\n")

func _draw_player(c: Control):
	var k: float = ui.k
	var p: Dictionary = c.get_meta("p")
	var s := c.rect_size
	var hover: bool = c.has_meta("hover") and c.get_meta("hover")
	var you := int(p.get("number", -1)) == _you
	var ban = c.get_meta("banner") if c.has_meta("banner") else null
	var bg := Color("#161616") if not hover else Color("#1d1d1d")
	c.draw_style_box(ui._flat(bg, 6 * k), Rect2(Vector2(), s))
	if ban != null:
		# the banner fills the card (cropped to it), darker on the left for the text
		var ts: Vector2 = ban.get_size()
		var sc: float = max(s.x / ts.x, s.y / ts.y)
		var src := Rect2((ts - s / sc) / 2.0, s / sc)
		c.draw_texture_rect_region(ban, Rect2(Vector2(2, 2), s - Vector2(4, 4)), src.grow_individual(-2 / sc, -2 / sc, -2 / sc, -2 / sc), Color(0.8, 0.8, 0.8) if not hover else Color(0.95, 0.95, 0.95))
		var grad := PoolColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55)])
		c.draw_polygon(PoolVector2Array([Vector2(2, 2), Vector2(s.x * 0.6, 2), Vector2(s.x * 0.6, s.y - 2), Vector2(2, s.y - 2)]), grad)
	var border := Color(1, 1, 1, 0.07)
	if you:
		border = Color("#c2475e")
	elif hover:
		border = Color(1, 1, 1, 0.16)
	c.draw_style_box(ui._flat(Color(0, 0, 0, 0), 6 * k, border, 1), Rect2(Vector2(), s))
	# the picture
	var r := 17.5 * k
	var ctr := Vector2(8 * k + r, s.y / 2)
	var pic = c.get_meta("pic") if c.has_meta("pic") else null
	if pic != null:
		c.draw_texture_rect(pic, Rect2(ctr - Vector2(r, r), Vector2(r, r) * 2), false)
	else:
		c.draw_circle(ctr, r, Color(1, 1, 1, 0.1))
		var nm0 := String(p.get("name", "?"))
		var ini := nm0.substr(0, 1).to_upper()
		var fi := _f("ExtraBold", 14)
		c.draw_string(fi, ctr - Vector2(fi.get_string_size(ini).x / 2, -fi.get_ascent() / 2 + 2 * k), ini, Color(1, 1, 1, 0.7))
	# the place on the leaderboard (big, grey, on the right)
	var fr := _f("ExtraBold", 22)
	var rank := _rank_of(p)
	var rt := ("#%d" % rank) if rank < (1 << 30) else ""
	var rw := fr.get_string_size(rt).x
	if rt != "":
		c.draw_string(fr, Vector2(s.x - 9 * k - rw, s.y / 2 + fr.get_ascent() / 2 - 3 * k), rt, Color(1, 1, 1, 0.45) if ban == null else Color(1, 1, 1, 0.85))
	# the name and what they're doing
	var x := ctr.x + r + 8 * k
	var tw := s.x - x - rw - 16 * k
	var fn := _f("ExtraBold", 13)
	var fs := _f("Bold", 10)
	var nm := String(p.get("name", ""))
	var tag := String(p.get("tag_text", ""))
	var nx := x
	if tag != "":
		var tc := Color(String(p.get("tag_color", ""))) if String(p.get("tag_color", "")).is_valid_html_color() else ui.RANKED
		var fp: Font = ui.f.pill
		var tt := tag.to_upper()
		var pw: float = fp.get_string_size(tt).x + 8 * k
		c.draw_style_box(ui._flat(Color(tc.r, tc.g, tc.b, 0.28), 3), Rect2(nx, s.y / 2 - 17 * k, pw, 11 * k))
		c.draw_string(fp, Vector2(nx + 4 * k, s.y / 2 - 8.5 * k), tt, tc.lightened(0.35))
		nx += pw + 5 * k
	c.draw_string(fn, Vector2(nx, s.y / 2 - 4 * k), ui._fit(nm, fn, tw - (nx - x)), Color(1, 1, 1))
	var st := _status(p)
	var stc := Color("#dedde3")
	if String(p.get("status", "")) == "playing" and _can_watch(p):
		stc = Color("#e9e8ee")
	c.draw_string(fs, Vector2(x, s.y / 2 + 12 * k), ui._fit(st, fs, tw), stc)
	var w := int(p.get("watchers", 0))
	if w > 0:
		var et := "%d watching" % w
		c.draw_string(ui.f.pill, Vector2(s.x - 9 * k - ui.f.pill.get_string_size(et).x, s.y - 6 * k), et, Color(1, 1, 1, 0.55))

func _on_card_input(ev, c: Control):
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	var p: Dictionary = c.get_meta("p")
	var n := int(p.get("number", -1))
	if ev.button_index == BUTTON_RIGHT and n > 0:
		close()
		ui.panels.open_profile(true, n)
	elif ev.button_index == BUTTON_LEFT and _can_watch(p) and lm != null:
		if lm.spectate_player(n):
			Globals.notify(Globals.NOTIFY_INFO, "Getting %s's map and play ready..." % String(p.get("name", "")), "Spectating")
			close()
	elif ev.button_index == BUTTON_MIDDLE and n > 0:
		# (middle click: favourite or not)
		if Rhythia.spectate_favorites.has(n):
			Rhythia.spectate_favorites.erase(n)
		else:
			Rhythia.spectate_favorites.append(n)
		Rhythia.save_settings()
		_rebuild()

func _on_denied(reason: String):
	if _open:
		Globals.notify(Globals.NOTIFY_ERROR, reason, "Spectating")

# (the round picture: shared with the rest of the Modern UI)
func _pic(url: String, c: Control, key: String):
	if url.begins_with("/"):
		url = ui.SITE + url
	if not url.begins_with("http"):
		return
	if _pics.has(url):
		c.set_meta(key, _pics[url])
		return
	if _waiting.has(url):
		_waiting[url].append([c, key])
		return
	_waiting[url] = [[c, key]]
	var r := HTTPRequest.new()
	r.timeout = 15
	add_child(r)
	r.connect("request_completed", self, "_on_pic", [r, url, key])
	if r.request(url) != OK:
		r.queue_free()
		_waiting.erase(url)

func _on_pic(result: int, code: int, _h, data: PoolByteArray, r: HTTPRequest, url: String, key: String):
	r.queue_free()
	var who: Array = _waiting.get(url, [])
	_waiting.erase(url)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var img := Image.new()
	if img.load_png_from_buffer(data) != OK and img.load_jpg_from_buffer(data) != OK and img.load_webp_from_buffer(data) != OK:
		return
	var tex := ImageTexture.new()
	if key == "pic":
		tex = ui._round_tex(img, 72)
	else:
		if img.get_width() > 640:
			img.resize(640, int(640.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
		tex.create_from_image(img, Texture.FLAG_FILTER)
	_pics[url] = tex
	for w in who:
		if is_instance_valid(w[0]):
			w[0].set_meta(w[1], tex)
			w[0].update()

# ------------------------------------------------------------------ chat

func _fill_channels():
	for ch in chans.get_children():
		ch.queue_free()
	var list := [["global", "Global"]]
	if lm != null and String(lm.lobby_code) != "":
		list.append(["lobby", "Lobby"])
	elif _channel == "lobby":
		_channel = "global"
	var k: float = ui.k
	for c in list:
		var b = ui._button(Color(1, 1, 1, 0.075) if c[0] == _channel else Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.1), 4)
		b.text = c[1]
		b.align = Button.ALIGN_LEFT
		b.rect_min_size = Vector2(0, 26 * k)
		b.add_font_override("font", _f("Bold", 10))
		b.add_color_override("font_color", ui.TEXT)
		var sb = b.get_stylebox("normal")
		if sb is StyleBoxFlat:
			sb.content_margin_left = 8 * k
		b.connect("pressed", self, "_set_channel", [c[0]])
		chans.add_child(b)

func _set_channel(c: String):
	_channel = c
	_fill_channels()
	_fill_chat()

func _on_join():
	close()
	ui.panels.open_page("Multiplayer", "Browse, create, or join a multiplayer lobby", "Online")

func _fill_chat():
	chat.clear()
	_chat_sizes = []
	chat_title.text = "Global" if _channel == "global" else "Lobby"
	if lm == null:
		return
	var muted: bool = Rhythia.mute_global_chat and _channel == "global"
	chat_input.editable = not muted
	send_btn.disabled = muted
	if muted:
		chat.push_color(ui.DIM)
		chat.add_text("The global chat is muted (Settings > Online).")
		chat.pop()
		return
	var hist: Array = lm.global_chat_history if _channel == "global" else lm.lobby_chat_history
	if hist.empty():
		chat.push_color(ui.DIM)
		chat.add_text("No messages yet. Say hi!")
		chat.pop()
		_chat_sizes = [-1]
		return
	for e in hist:
		if e is Dictionary:
			_line(String(e.get("client_id", "")), String(e.get("name", "")), String(e.get("text", "")), float(e.get("ts", 0)), String(e.get("mid", "")))

func _line(cid: String, nm: String, text: String, ts: float, mid: String):
	if _chat_sizes.size() == 1 and _chat_sizes[0] == -1:
		chat.clear()
		_chat_sizes = []
	if not _chat_sizes.empty():
		chat.newline()
	chat.push_color(Color("#b5b4bb"))
	chat.add_text(load("res://scripts/ui/menu/SpectatePage.gd")._clock(ts) + " ")
	chat.pop()
	var me: bool = cid != "" and cid == Rhythia.cid
	chat.push_color(Color("#c79bff") if me else Color.from_hsv(fmod(abs(hash(nm)) / 1000.0, 1.0), 0.45, 0.85))
	chat.add_text(nm + ": ")
	chat.pop()
	for part in preload("res://scripts/ui/ChatMention.gd").split(text, lm):
		if part[1]:
			# @mentions in a box, like the video
			chat.push_color(Color("#9fb3ff") if not part[2] else Color("#ff9bc0"))
			chat.add_text(part[0])
			chat.pop()
		else:
			preload("res://scripts/ui/ChatCommands.gd").add_text(chat, part[0], int(15 * ui.k))
	var extra := 0
	if _channel == "global" and mid != "":
		extra = preload("res://scripts/ui/ChatReactions.gd").add(chat, mid, lm, int(14 * ui.k), 3)
	_chat_sizes.append(1 + extra)
	if _chat_sizes.size() > CHAT_MAX:
		for _i in int(_chat_sizes.pop_front()):
			chat.remove_line(0)

func _on_chat(cid: String, nm: String, text: String, ts: float):
	if _open and _channel == "global" and not Rhythia.mute_global_chat:
		_line(cid, nm, text, ts, String(lm.get("last_chat_id")) if lm.get("last_chat_id") != null else "")

func _on_lobby_chat(_peer, nm: String, text: String, ts: float):
	if _open and _channel == "lobby":
		_line("", nm, text, ts, "")

var _react_redraw := false
func _on_reactions(_mid):
	if _open and _channel == "global" and not _react_redraw:
		_react_redraw = true
		call_deferred("_redraw")

func _redraw():
	_react_redraw = false
	_fill_chat()

func _on_send(_t = null):
	if lm == null:
		return
	var text := chat_input.text.strip_edges()
	if text == "":
		return
	var method := "send_global_chat_message" if _channel == "global" else "send_chat_message"
	if preload("res://scripts/ui/ChatCommands.gd").handle(self, text, lm, method):
		chat_input.text = ""
		return
	lm.call(method, text)
	chat_input.text = ""
	chat_input.grab_focus()
