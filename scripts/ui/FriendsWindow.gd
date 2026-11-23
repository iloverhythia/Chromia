extends PanelContainer

# Online > Friends: its own window (like Invite players). Three tabs:
#   Friends   your friends (online ones first): Invite (when you're in a
#             lobby) and Remove
#   Requests  friend requests to you (Accept / Decline) and yours (Cancel)
#   Blocked   who you blocked (Unblock), and Block by player number
# and "Add a friend" by player number (on Blocked: block one). Block is in
# the Spectate list's player menu too, and on a friend request. Right-click a name in any chat to add
# a friend or block someone too (ChatReactions.gd). The lists are the
# server's (LobbyManager social_state, savia_web social.js); the website's
# profile has the same ones.

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")

var S
var lm
var _tab := "friends"
var _tabs := {}
var _list: VBoxContainer
var _number: LineEdit
var _go: Button

static func open_on(parent: Node, tab: String = ""):
	var tree = parent.get_tree()
	var old = tree.root.find_node("FriendsLayer", true, false)
	if old != null:
		old.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 110
	layer.name = "FriendsLayer"
	# (on the screen the button is on: in VR the menu screen)
	parent.get_viewport().add_child(layer)
	var dim := ColorRect.new()
	dim.add_to_group("wheel_blocker") # (the map list behind it does not scroll: Savia.wheel_blocked)
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	layer.add_child(dim)
	var m = load("res://scripts/ui/FriendsWindow.gd").new()
	m.name = "Friends"
	if tab != "":
		m._tab = tab
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
	var t: Label = S.heading("Friends")
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "Close"
	S.button(x, false, true)
	x.connect("pressed", self, "close")
	head.add_child(x)

	var tabs := HBoxContainer.new()
	tabs.add_constant_override("separation", 6)
	v.add_child(tabs)
	for k in [["friends", "Friends"], ["requests", "Requests"], ["blocked", "Blocked"]]:
		var b := Button.new()
		b.text = k[1]
		S.button(b, false, true)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.connect("pressed", self, "_pick_tab", [k[0]])
		tabs.add_child(b)
		_tabs[k[0]] = b

	# add one by their player number (on their profile, and in the Spectate list)
	var add := HBoxContainer.new()
	add.add_constant_override("separation", 6)
	v.add_child(add)
	_number = LineEdit.new()
	_number.placeholder_text = "Add a friend by player number"
	_number.size_flags_horizontal = SIZE_EXPAND_FILL
	S.field(_number)
	_number.connect("text_entered", self, "_add_by_number")
	add.add_child(_number)
	_go = Button.new()
	_go.text = "Send request"
	S.button(_go, true, true)
	_go.connect("pressed", self, "_add_by_number", [""])
	add.add_child(_go)

	var sc := ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	sc.size_flags_vertical = SIZE_EXPAND_FILL
	S.scroll(sc)
	v.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_constant_override("separation", 6)
	sc.add_child(_list)

func _ready():
	lm = get_node_or_null("/root/LobbyManager")
	if lm != null:
		lm.connect("social_changed", self, "_refill")
		lm.refresh_social() # (who's online now)
	get_viewport().connect("size_changed", self, "_place")
	call_deferred("_place")
	_refill()

func _place():
	var vp := get_viewport_rect().size
	rect_size = Vector2(min(540.0, vp.x - 40.0), min(600.0, vp.y - 60.0))
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

func _pick_tab(k: String):
	_tab = k
	_refill()

func _add_by_number(_t = ""):
	var s := _number.text.strip_edges().trim_prefix("#")
	if not s.is_valid_integer() or int(s) <= 0:
		Globals.notify(Globals.NOTIFY_WARN, "Type their player number (it's on their profile).", "Friends")
		return
	if lm != null:
		if _tab == "blocked":
			lm.confirm_block(int(s))
		else:
			lm.social_action("request", int(s))
	_number.text = ""

func _refill(_x = null):
	for k in _tabs:
		_tabs[k].pressed = k == _tab
	_number.placeholder_text = "Block someone by player number" if _tab == "blocked" else "Add a friend by player number"
	_go.text = "Block" if _tab == "blocked" else "Send request"
	var n_in: int = lm.friend_requests_in.size() if lm != null else 0
	_tabs["requests"].text = "Requests (%d)" % n_in if n_in > 0 else "Requests"
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if lm == null:
		return
	var shown := 0
	if _tab == "friends":
		var in_lobby: bool = bool(lm.get("lobby_active"))
		for p in lm.friends:
			var btns := []
			if in_lobby and p.online:
				btns.append(["Invite", "invite", true])
			btns.append(["Remove", "remove", false])
			_row(p, "Online" if p.online else "#%d" % p.number, btns)
			shown += 1
		if shown == 0:
			_note("No friends yet. Right-click someone's name in chat, or type their player number above.")
	elif _tab == "requests":
		for p in lm.friend_requests_in:
			_row(p, "Wants to be friends", [["Accept", "accept", true], ["Decline", "decline", false], ["Block", "block", false]])
			shown += 1
		for p in lm.friend_requests_out:
			_row(p, "Request sent", [["Cancel", "cancel", false]])
			shown += 1
		if shown == 0:
			_note("No friend requests.")
	else:
		for p in lm.blocked_players:
			_row(p, "Their chat messages are folded away", [["Unblock", "unblock", false]])
			shown += 1
		if shown == 0:
			_note("You haven't blocked anyone. Type a player number above, right-click a name in chat, or use the ... on someone in Spectate.")

func _note(text: String):
	_list.add_child(S.label(text, S.f_small, S.DIM, true))

func _row(p: Dictionary, what: String, btns: Array):
	var h: HBoxContainer = S.card(_list)
	var card: Control = h.get_parent()
	card.get_stylebox("panel").content_margin_top = 6
	card.get_stylebox("panel").content_margin_bottom = 6
	h.add_constant_override("separation", 10)
	var url := String(p.get("avatar_url", ""))
	if url.begins_with("/"):
		url = "https://chromia.lol" + url
	var pic: Control = S.avatar(String(p.name), url, self)
	pic.rect_min_size = Vector2(32, 32)
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGN_CENTER
	v.add_constant_override("separation", 0)
	h.add_child(v)
	var l: Label = S.label(String(p.name), S.f_bold, S.TEXT)
	l.clip_text = true
	v.add_child(l)
	var sub: Label = S.label(what, S.f_small, Color(0.55, 0.9, 0.6) if what == "Online" else S.DIM)
	sub.clip_text = true
	v.add_child(sub)
	for b in btns:
		var bt := Button.new()
		bt.text = b[0]
		S.button(bt, b[2], true)
		bt.size_flags_vertical = SIZE_SHRINK_CENTER
		bt.connect("pressed", self, "_act", [b[1], int(p.number), bt])
		h.add_child(bt)

func _act(action: String, number: int, bt: Button):
	if lm == null:
		return
	if action == "invite":
		lm.invite_player(number)
		bt.text = "Invited"
		bt.disabled = true
		return
	if action == "block":
		lm.confirm_block(number)
		return
	bt.disabled = true
	lm.social_action(action, number)
