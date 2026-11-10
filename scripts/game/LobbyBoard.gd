extends PanelContainer

# The leaderboard during a multiplayer match (and its results), in the Online
# menu's look (OnlineStyle.gd): a dark window, a pink heading, and a card per
# player with their place, picture, name, accuracy and misses, badges (host,
# failed, done) and score. Game.gd shows it on the screen; in VR the HUD shows
# the same board on a panel beside the left grid panel (HUD.gd
# update_leaderboard_vr), drawn in a viewport at `k` times the size.
#
# set_board(rows, title, footer): rows are Game.gd's dictionaries (name,
# score, misses, accuracy, is_host, is_you, peer_id, alive, tag_text,
# tag_color, avatar_url), already in order. Small: a line per player (place,
# picture, name, accuracy, score); Tab hides it (Game.gd). "changed" fires
# when anything shown changed (the VR panel draws itself again).

signal changed
signal row_clicked(peer_id)

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")
const RANK_COLORS := [Color(1.0, 0.84, 0.3), Color(0.82, 0.85, 0.92), Color(0.86, 0.58, 0.32)]

var k := 1.0
var pictures := true # (VR: initials only, the panel draws itself once per change)
var S
var _title: Label
var _rows: VBoxContainer
var _footer: Label
var continue_button: Button
var _set_sig := ""
var _rowmap := {} # peer id -> {card, rank, name, sub, score}
var f_rank: DynamicFont
var f_score: DynamicFont
var f_name: DynamicFont
var f_sub: DynamicFont

func _init(scale := 1.0, with_pictures := true):
	k = scale
	pictures = with_pictures
	S = OnlineStyle.new()
	S.f_small = OnlineStyle.font("res://assets/font/Lato/Lato-Regular.ttf", int(12 * k))
	S.f_bold = OnlineStyle.font("res://assets/font/Lato/Lato-Bold.ttf", int(12 * k))
	S.f_head = OnlineStyle.font("res://assets/font/Lato/Lato-Bold.ttf", int(14 * k))
	f_name = OnlineStyle.font("res://assets/font/Lato/Lato-Bold.ttf", int(12 * k))
	f_sub = OnlineStyle.font("res://assets/font/Lato/Lato-Regular.ttf", int(10 * k))
	f_rank = OnlineStyle.font("res://assets/font/Lato/Lato-Black.ttf", int(12 * k))
	f_score = OnlineStyle.font("res://assets/font/Lato/Lato-Black.ttf", int(12 * k))
	mouse_filter = MOUSE_FILTER_PASS
	add_stylebox_override("panel", OnlineStyle.flat(Color(S.WINDOW_BG.r, S.WINDOW_BG.g, S.WINDOW_BG.b, 0.82), 4, Color(1, 1, 1, 0.07), 1, 7 * k, 6 * k))
	var v := VBoxContainer.new()
	v.add_constant_override("separation", int(4 * k))
	add_child(v)
	_title = S.label("Leaderboard", S.f_head, S.PINK)
	v.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_constant_override("separation", int(3 * k))
	v.add_child(_rows)
	_footer = S.label("", S.f_small, S.DIM)
	_footer.visible = false
	v.add_child(_footer)
	continue_button = Button.new()
	continue_button.text = "Continue"
	S.button(continue_button, true, true)
	continue_button.visible = false
	v.add_child(continue_button)

# Called often (a few times a second while playing): when the same players are
# there with the same badges, only the numbers and the order change in place;
# the rows are only made again when someone joins, leaves, fails or finishes.
# (Making every row again on each note hit was what lagged multiplayer.)
func set_board(rows: Array, title: String, footer: String = "", show_continue: bool = false):
	var keys := []
	for r in rows:
		keys.append(var2str([int(r.peer_id), r.name, r.is_you, r.alive, r.is_host, r.get("tag_text", ""), r.get("finished", false), r.get("avatar_url", "")]))
	keys.sort()
	var set_sig := var2str([keys, show_continue])
	var changed := false
	if set_sig != _set_sig:
		_set_sig = set_sig
		_rebuild(rows, show_continue)
		changed = true
	if _title.text != title:
		_title.text = title
		changed = true
	if _footer.text != footer:
		_footer.text = footer
		_footer.visible = footer != ""
		changed = true
	if continue_button.visible != show_continue:
		continue_button.visible = show_continue
		changed = true
	for i in rows.size():
		var r: Dictionary = rows[i]
		var n = _rowmap.get(int(r.peer_id))
		if n == null:
			continue
		var card: Control = n.card
		if card.get_index() != i:
			_rows.move_child(card, i)
			changed = true
		changed = _set_text(n.rank, "#%d" % (i + 1)) or changed
		n.rank.add_color_override("font_color", RANK_COLORS[i] if i < 3 else S.DIM)
		changed = _set_text(n.score, _commas(int(r.score))) or changed
		changed = _set_text(n.sub, _sub(r)) or changed
	if changed:
		emit_signal("changed")

func _set_text(l: Label, t: String) -> bool:
	if l.text == t:
		return false
	l.text = t
	return true

func _sub(r: Dictionary) -> String:
	if not r.alive:
		return "failed"
	var misses := int(r.misses)
	return "%.2f%%  ·  %d miss%s" % [float(r.accuracy) * 100.0, misses, "" if misses == 1 else "es"]

func _rebuild(rows: Array, results: bool):
	for c in _rows.get_children():
		_rows.remove_child(c) # (now: a freed row kept for a frame made the board jump)
		c.queue_free()
	_rowmap.clear()
	for i in rows.size():
		_row(rows[i], i + 1, results)

func _row(r: Dictionary, rank: int, results: bool):
	var card := PanelContainer.new()
	card.add_stylebox_override("panel", OnlineStyle.flat(S.CARD_BG, 3,
		S.ACCENT if r.is_you else Color(1, 1, 1, 0.04), 1, 6 * k, 3 * k))
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	card.set_meta("peer_id", int(r.peer_id))
	card.mouse_filter = MOUSE_FILTER_STOP
	card.connect("gui_input", self, "_on_row_input", [card])
	if not r.alive:
		card.modulate = Color(1, 1, 1, 0.55)
	_rows.add_child(card)
	var h := HBoxContainer.new()
	h.add_constant_override("separation", int(6 * k))
	card.add_child(h)
	var rl: Label = S.label("#%d" % rank, f_rank, RANK_COLORS[rank - 1] if rank <= 3 else S.DIM)
	rl.rect_min_size.x = 22 * k
	rl.valign = Label.VALIGN_CENTER
	h.add_child(rl)
	var pic: Control = S.avatar(r.name, String(r.get("avatar_url", "")), self) if pictures else S.initial(r.name)
	pic.rect_min_size = Vector2(20, 20) * k
	pic.add_stylebox_override("panel", OnlineStyle.flat(pic.get_stylebox("panel").bg_color if pic.get_stylebox("panel") is StyleBoxFlat else S.CARD_BG, int(10 * k)))
	for c in pic.get_children():
		if c is Label:
			c.add_font_override("font", f_sub)
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGN_CENTER
	v.add_constant_override("separation", int(-1 * k))
	h.add_child(v)
	var nm: Label = S.label(String(r.name), f_name, S.TEXT)
	nm.clip_text = true
	v.add_child(nm)
	var sub: Label = S.label(_sub(r), f_sub, S.BAD if not r.alive else S.DIM)
	sub.clip_text = true
	v.add_child(sub)
	# the badges only on the results (they made the board wide while playing)
	if results:
		if String(r.get("tag_text", "")) != "":
			var tc := String(r.get("tag_color", ""))
			h.add_child(_small_badge(String(r.tag_text).to_upper(), Color(tc) if tc.is_valid_html_color() else S.LILAC))
		if r.get("finished", false) and r.alive:
			h.add_child(_small_badge("DONE", S.PLAYING))
		if r.is_host:
			h.add_child(_small_badge("HOST", S.PINK))
	var sc: Label = S.label(_commas(int(r.score)), f_score, S.TEXT)
	sc.align = Label.ALIGN_RIGHT
	sc.valign = Label.VALIGN_CENTER
	sc.rect_min_size.x = 52 * k
	h.add_child(sc)
	_rowmap[int(r.peer_id)] = {"card": card, "rank": rl, "name": nm, "sub": sub, "score": sc}

func _small_badge(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	p.add_stylebox_override("panel", OnlineStyle.flat(Color(col.r, col.g, col.b, 0.16), 3, Color(col.r, col.g, col.b, 0.5), 1, 4 * k, 1 * k))
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	p.mouse_filter = MOUSE_FILTER_IGNORE
	p.add_child(S.label(text, f_sub, col))
	return p

func _on_row_input(ev, card: Control):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		emit_signal("row_clicked", int(card.get_meta("peer_id")))

static func _commas(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
