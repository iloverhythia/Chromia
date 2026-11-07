extends PanelContainer

# The small notice in the bottom right when someone invites you into their
# lobby (LobbyManager._on_lobby_invite): who it is, the lobby's map and size,
# and Join / Later. It goes away by itself after a few seconds; the invite
# stays on the Online tab (a dot on its button, and a list on the page).
# During a song there's no Join button: join from the Online tab afterwards.

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")
const SHOW_SEC := 12.0

var S
var inv: Dictionary
var _t := 0.0

static func show_invite(invite: Dictionary):
	var tree: SceneTree = Engine.get_main_loop()
	if Rhythia.vr:
		# (VR: the headset doesn't show the window's layers; the usual notices do)
		Globals.notify(Globals.NOTIFY_INFO, "%s invited you to their lobby. Join from the Online tab." % String(invite.from_name), "Lobby invite")
		return
	var layer = tree.root.get_node_or_null("InviteToastLayer")
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "InviteToastLayer"
		layer.layer = 125
		layer.pause_mode = Node.PAUSE_MODE_PROCESS
		tree.root.add_child(layer)
	for old in layer.get_children():
		old.queue_free()
	var t = load("res://scripts/ui/InviteToast.gd").new()
	t.inv = invite
	layer.add_child(t)

func _init():
	S = OnlineStyle.new()
	pause_mode = PAUSE_MODE_PROCESS
	mouse_filter = MOUSE_FILTER_STOP
	var sb = OnlineStyle.flat(OnlineStyle.WINDOW_BG, 6, Color(OnlineStyle.ACCENT.r, OnlineStyle.ACCENT.g, OnlineStyle.ACCENT.b, 0.45), 1, 14, 10)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	add_stylebox_override("panel", sb)

func _ready():
	var in_map: bool = Rhythia.in_map
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_constant_override("separation", 10)
	v.add_child(top)
	var pic: Control = S.initial(String(inv.from_name))
	pic.rect_min_size = Vector2(34, 34)
	top.add_child(pic)
	var texts := VBoxContainer.new()
	texts.add_constant_override("separation", 0)
	texts.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(texts)
	texts.add_child(S.label("LOBBY INVITE", S.f_small, OnlineStyle.PINK))
	var who: Label = S.label("%s invited you" % String(inv.from_name), S.f_bold, OnlineStyle.TEXT)
	who.clip_text = true
	texts.add_child(who)
	var n := int(inv.lobby_size)
	var info := "%d player%s" % [n, "" if n == 1 else "s"]
	if String(inv.song_name) != "":
		info = String(inv.song_name) + "  ·  " + info
	var il: Label = S.label(info, S.f_small, OnlineStyle.DIM)
	il.clip_text = true
	texts.add_child(il)
	if in_map:
		v.add_child(S.label("Join it from the Online tab after this song.", S.f_small, OnlineStyle.DIM, true))
	else:
		var row := HBoxContainer.new()
		row.add_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGN_END
		v.add_child(row)
		var later := Button.new()
		later.text = "Later"
		S.button(later, false, true)
		later.connect("pressed", self, "close")
		row.add_child(later)
		var join := Button.new()
		join.text = "Join"
		S.button(join, true, true)
		join.connect("pressed", self, "_join")
		row.add_child(join)
	rect_min_size = Vector2(300, 0)
	get_viewport().connect("size_changed", self, "_place")
	_place()
	modulate.a = 0.0

func _place():
	var vp := get_viewport_rect().size
	rect_size = get_combined_minimum_size()
	# above the round Spectate button in the corner
	rect_position = Vector2(vp.x - rect_size.x - 16, vp.y - rect_size.y - 70)

func _process(delta):
	_t += delta
	var a := 1.0
	if _t < 0.2:
		a = _t / 0.2
	elif _t > SHOW_SEC - 0.5:
		a = max(0.0, (SHOW_SEC - _t) / 0.5)
	# (the mouse on it keeps it there)
	if get_global_rect().has_point(get_global_mouse_position()) and _t > 0.2:
		_t = min(_t, SHOW_SEC - 2.0)
		a = 1.0
	modulate.a = a
	if _t >= SHOW_SEC:
		close()

func _join():
	var lm = get_node_or_null("/root/LobbyManager")
	if lm != null:
		lm.accept_invite(String(inv.code))
	close()

func close():
	queue_free()
