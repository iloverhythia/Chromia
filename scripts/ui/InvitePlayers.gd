extends PanelContainer

# Online > your lobby > Invite players: its own window (not the Spectate
# one): everyone online in a list with a search box and an Invite button
# each. People who turned invites off, or are already in your lobby, can't be
# invited (the button says why). The list comes from the server's online
# players feed (LobbyManager subscribe_online / online_players_received).

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")

var S
var lm
var _list: VBoxContainer
var _search: LineEdit
var _empty: Label
var _players := []
var _me := -1
var _sent := {} # number -> true (invited from this window)

static func open_on(parent: Node):
	var tree = parent.get_tree()
	var old = tree.root.get_node_or_null("InvitePlayersLayer")
	if old != null:
		old.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 110
	layer.name = "InvitePlayersLayer"
	tree.root.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	layer.add_child(dim)
	var m = load("res://scripts/ui/InvitePlayers.gd").new()
	m.name = "InvitePlayers"
	layer.add_child(m)
	dim.connect("gui_input", m, "_on_dim")
	return m

func _init():
	S = OnlineStyle.new()
	add_stylebox_override("panel", OnlineStyle.flat(S.WINDOW_BG, 6, Color(1, 1, 1, 0.1), 1, 20, 16))
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t: Label = S.heading("Invite players")
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "Close"
	S.button(x, false, true)
	x.connect("pressed", self, "close")
	head.add_child(x)
	v.add_child(S.label("They get a notice with your name and can join with one click.", S.f_small, S.DIM, true))
	_search = LineEdit.new()
	_search.placeholder_text = "Search players"
	_search.clear_button_enabled = true
	S.field(_search)
	_search.connect("text_changed", self, "_refill")
	v.add_child(_search)
	var sc := ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	sc.size_flags_vertical = SIZE_EXPAND_FILL
	S.scroll(sc)
	v.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_constant_override("separation", 6)
	sc.add_child(_list)
	_empty = S.label("Loading who's online...", S.f_small, S.DIM)
	_list.add_child(_empty)

func _ready():
	lm = get_node_or_null("/root/LobbyManager")
	if lm != null:
		lm.connect("online_players_received", self, "_on_players")
		lm.subscribe_online()
		if not lm.online_players.empty():
			_on_players(lm.online_players, lm.my_player_number)
	get_viewport().connect("size_changed", self, "_place")
	call_deferred("_place")
	_search.call_deferred("grab_focus")

func _exit_tree():
	if lm != null and is_instance_valid(lm):
		lm.unsubscribe_online()

func _place():
	var vp := get_viewport_rect().size
	rect_size = Vector2(min(520.0, vp.x - 40.0), min(560.0, vp.y - 60.0))
	rect_position = ((vp - rect_size) / 2.0).floor()

func _on_dim(ev):
	if ev is InputEventMouseButton and ev.pressed:
		close()

func _input(ev):
	if ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()

func close():
	var layer = get_parent()
	if layer is CanvasLayer:
		layer.queue_free()
	else:
		queue_free()

func _on_players(list: Array, me: int):
	# (only when who's there or what they do changed: the feed repeats)
	var sig := []
	for p in list:
		if p is Dictionary:
			sig.append([p.get("number"), p.get("name"), p.get("status"), p.get("in_lobby"), p.get("allow_invites"), p.get("song_name")])
	if var2str(sig) == var2str(_players_sig()) and me == _me:
		return
	_players = list
	_me = me
	_refill()

func _players_sig() -> Array:
	var sig := []
	for p in _players:
		if p is Dictionary:
			sig.append([p.get("number"), p.get("name"), p.get("status"), p.get("in_lobby"), p.get("allow_invites"), p.get("song_name")])
	return sig

func _refill(_t = null):
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var q := _search.text.strip_edges().to_lower()
	var mine := _lobby_names()
	var shown := 0
	for p in _players:
		if not (p is Dictionary):
			continue
		var n := int(p.get("number", -1)) if p.get("number") != null else -1
		if n <= 0 or n == _me:
			continue
		var nm := String(p.get("name", "Player"))
		if q != "" and nm.to_lower().find(q) == -1:
			continue
		_list.add_child(_row(p, n, nm, bool(p.get("in_lobby", false)) and mine.has(nm)))
		shown += 1
	if shown == 0:
		_empty = S.label("Nobody to invite right now." if q == "" else "Nobody online is called that.", S.f_small, S.DIM)
		_list.add_child(_empty)

# the names in your lobby (they're already there)
func _lobby_names() -> Dictionary:
	var out := {}
	if lm == null:
		return out
	for p in lm.players:
		if p is Dictionary:
			out[String(p.get("name", ""))] = true
	return out

func _row(p: Dictionary, n: int, nm: String, here: bool) -> Control:
	var h: HBoxContainer = S.card(_list)
	var card: Control = h.get_parent()
	card.get_stylebox("panel").content_margin_top = 6
	card.get_stylebox("panel").content_margin_bottom = 6
	h.add_constant_override("separation", 10)
	var pic: Control = S.avatar(nm, load("res://scripts/ui/AnimPic.gd").pic_url(p), self)
	pic.rect_min_size = Vector2(32, 32)
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGN_CENTER
	v.add_constant_override("separation", 0)
	h.add_child(v)
	var l: Label = S.label(nm, S.f_bold, S.TEXT)
	l.clip_text = true
	v.add_child(l)
	var st := String(p.get("status", ""))
	var what := "In the menu"
	if st == "playing":
		what = "Playing " + String(p.get("song_name", "a map"))
	elif bool(p.get("in_lobby", false)):
		what = "In a lobby"
	var sub: Label = S.label(what, S.f_small, S.DIM)
	sub.clip_text = true
	v.add_child(sub)
	var b := Button.new()
	S.button(b, true, true)
	b.rect_min_size.x = 96
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	if here:
		b.text = "In lobby"
		b.disabled = true
	elif p.get("allow_invites") == false:
		b.text = "Invites off"
		b.disabled = true
		b.hint_tooltip = "%s turned lobby invites off" % nm
	elif _sent.has(n):
		b.text = "Invited"
		b.disabled = true
	else:
		b.text = "Invite"
		b.connect("pressed", self, "_invite", [n, b])
	h.add_child(b)
	return card

func _invite(n: int, b: Button):
	if lm == null:
		return
	lm.invite_player(n)
	_sent[n] = true
	b.text = "Invited"
	b.disabled = true
