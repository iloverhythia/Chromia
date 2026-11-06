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
# tag_color, avatar_url), already in order. Only rebuilt when something shown
# changes. "changed" fires after a rebuild (the VR panel draws itself again).

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
var _sig := ""
var f_rank: DynamicFont
var f_score: DynamicFont

func _init(scale := 1.0, with_pictures := true):
	k = scale
	pictures = with_pictures
	S = OnlineStyle.new()
	if k != 1.0:
		S.f_regular = OnlineStyle.font("res://assets/font/Lato/Lato-Regular.ttf", int(16 * k))
		S.f_bold = OnlineStyle.font("res://assets/font/Lato/Lato-Bold.ttf", int(16 * k))
		S.f_small = OnlineStyle.font("res://assets/font/Lato/Lato-Regular.ttf", int(14 * k))
		S.f_head = OnlineStyle.font("res://assets/font/Lato/Lato-Bold.ttf", int(22 * k))
	f_rank = OnlineStyle.font("res://assets/font/Lato/Lato-Black.ttf", int(18 * k))
	f_score = OnlineStyle.font("res://assets/font/Lato/Lato-Black.ttf", int(17 * k))
	mouse_filter = MOUSE_FILTER_PASS
	add_stylebox_override("panel", OnlineStyle.flat(OnlineStyle.WINDOW_BG, 4, Color(1, 1, 1, 0.07), 1, 14 * k, 12 * k))
	var v := VBoxContainer.new()
	v.add_constant_override("separation", int(8 * k))
	add_child(v)
	_title = S.heading("Leaderboard")
	v.add_child(_title)
	v.add_child(S.rule())
	_rows = VBoxContainer.new()
	_rows.add_constant_override("separation", int(6 * k))
	v.add_child(_rows)
	_footer = S.label("", S.f_small, OnlineStyle.DIM)
	_footer.visible = false
	v.add_child(_footer)
	continue_button = Button.new()
	continue_button.text = "Continue"
	S.button(continue_button, true)
	continue_button.visible = false
	v.add_child(continue_button)

func set_board(rows: Array, title: String, footer: String = "", show_continue: bool = false):
	var bits := [title, footer, show_continue]
	for r in rows:
		bits.append([r.name, r.score, r.misses, stepify(float(r.accuracy), 0.0001), r.is_host, r.is_you, r.alive, r.get("tag_text", ""), r.get("finished", false)])
	var sig := var2str(bits)
	if sig == _sig:
		return
	_sig = sig
	_title.text = title
	_footer.text = footer
	_footer.visible = footer != ""
	continue_button.visible = show_continue
	for c in _rows.get_children():
		c.queue_free()
	for i in rows.size():
		_rows.add_child(_row(rows[i], i + 1))
	emit_signal("changed")

func _row(r: Dictionary, rank: int) -> Control:
	var h: HBoxContainer = S.card(_rows)
	var card: PanelContainer = h.get_parent()
	card.add_stylebox_override("panel", OnlineStyle.flat(OnlineStyle.CARD_BG, 4,
		OnlineStyle.ACCENT if r.is_you else Color(1, 1, 1, 0.04), 2 if r.is_you else 1, 12 * k, 8 * k))
	card.set_meta("peer_id", int(r.peer_id))
	card.mouse_filter = MOUSE_FILTER_STOP
	card.connect("gui_input", self, "_on_row_input", [card])
	if not r.alive:
		card.modulate = Color(1, 1, 1, 0.6)
	h.add_constant_override("separation", int(10 * k))
	var rl: Label = S.label("#%d" % rank, f_rank, RANK_COLORS[rank - 1] if rank <= 3 else OnlineStyle.DIM)
	rl.rect_min_size.x = 34 * k
	rl.valign = Label.VALIGN_CENTER
	h.add_child(rl)
	var pic: Control = S.avatar(r.name, String(r.get("avatar_url", "")), self) if pictures else S.initial(r.name)
	pic.rect_min_size = Vector2(36, 36) * k
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGN_CENTER
	v.add_constant_override("separation", 0)
	h.add_child(v)
	var nm: Label = S.label(String(r.name) + ("  (you)" if r.is_you else ""), S.f_bold, OnlineStyle.TEXT)
	nm.clip_text = true
	v.add_child(nm)
	var misses := int(r.misses)
	var sub := "%.2f%%  ·  %d miss%s" % [float(r.accuracy) * 100.0, misses, "" if misses == 1 else "es"]
	v.add_child(S.label(sub, S.f_small, OnlineStyle.DIM))
	if String(r.get("tag_text", "")) != "":
		var tc := String(r.get("tag_color", ""))
		h.add_child(S.badge(String(r.tag_text).to_upper(), Color(tc) if tc.is_valid_html_color() else OnlineStyle.LILAC))
	if not r.alive:
		h.add_child(S.badge("FAILED", OnlineStyle.BAD))
	elif r.get("finished", false):
		h.add_child(S.badge("DONE", OnlineStyle.PLAYING))
	if r.is_host:
		h.add_child(S.badge("HOST", OnlineStyle.PINK))
	var sc: Label = S.label(_commas(int(r.score)), f_score, OnlineStyle.TEXT)
	sc.align = Label.ALIGN_RIGHT
	sc.valign = Label.VALIGN_CENTER
	sc.rect_min_size.x = 70 * k
	h.add_child(sc)
	return card

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
