extends PanelContainer

# Your profile > Cards: the card your player card shows in the Spectate grid
# (its background and border) and as the border of your website profile.
# Everyone has Default; locked cards show greyed out with no hint of how to get
# them. A secret code (from somewhere...) can unlock a card. The server keeps
# which cards you have (LobbyManager get_cards / set_card / redeem_card_code).

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")

var S
var lm
var _grid: GridContainer
var _msg: Label
var _code: LineEdit
var _chosen := "default"

static func open_on(parent: Node):
	var old = parent.get_tree().root.find_node("CardsMenu", true, false)
	if old != null:
		old.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 110
	layer.name = "CardsMenuLayer"
	parent.get_tree().root.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	layer.add_child(dim)
	var m = load("res://scripts/ui/CardsMenu.gd").new()
	m.name = "CardsMenu"
	layer.add_child(m)
	dim.connect("gui_input", m, "_on_dim")
	return m

func _init():
	S = OnlineStyle.new()
	add_stylebox_override("panel", OnlineStyle.flat(OnlineStyle.WINDOW_BG, 6, Color(1, 1, 1, 0.1), 1, 22, 18))
	rect_min_size = Vector2(560, 0)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t: Label = S.heading("Cards")
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "Close"
	S.button(x)
	x.connect("pressed", self, "close")
	head.add_child(x)
	v.add_child(S.label("The colours of your card in the Spectate grid, and the border of your website profile. Some cards are unlocked by what you do; how is a secret.", S.f_small, OnlineStyle.DIM, true))
	v.add_child(S.rule())
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_constant_override("hseparation", 10)
	_grid.add_constant_override("vseparation", 10)
	v.add_child(_grid)
	_msg = S.label("Loading your cards...", S.f_small, OnlineStyle.DIM)
	v.add_child(_msg)
	v.add_child(S.rule())
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 8)
	v.add_child(row)
	_code = LineEdit.new()
	_code.placeholder_text = "Secret code"
	_code.size_flags_horizontal = SIZE_EXPAND_FILL
	S.field(_code)
	_code.connect("text_entered", self, "_redeem")
	row.add_child(_code)
	var go := Button.new()
	go.text = "Use code"
	S.button(go, true)
	go.connect("pressed", self, "_redeem")
	row.add_child(go)

func _ready():
	lm = get_node_or_null("/root/LobbyManager")
	if lm != null:
		lm.connect("cards_received", self, "_on_cards")
		lm.connect("card_message", self, "_on_message")
		lm.get_cards()
	get_viewport().connect("size_changed", self, "_place")
	call_deferred("_place")

func _place():
	var vp := get_viewport_rect().size
	rect_size = get_combined_minimum_size()
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

func _on_cards(cards: Array, chosen: String):
	_chosen = chosen
	for c in _grid.get_children():
		c.queue_free()
	var locked := 0
	for c in cards:
		if c is Dictionary:
			_grid.add_child(_card(c))
			if not bool(c.get("unlocked", false)):
				locked += 1
	_msg.text = ("%d locked: keep playing (and looking) to find them." % locked) if locked > 0 else "You have every card!"
	call_deferred("_place")

func _card(c: Dictionary) -> Control:
	var id := String(c.get("id", ""))
	var have := bool(c.get("unlocked", false))
	var bg := Color(String(c.get("bg", "#13111a"))) if String(c.get("bg", "")).is_valid_html_color() else OnlineStyle.CARD_BG
	var border := Color(String(c.get("border", "#2b2734"))) if String(c.get("border", "")).is_valid_html_color() else Color(1, 1, 1, 0.1)
	var b := Button.new()
	b.rect_min_size = Vector2(160, 92)
	b.focus_mode = FOCUS_NONE
	b.toggle_mode = false
	var picked := id == _chosen
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb = OnlineStyle.flat(bg.lightened(0.06) if st == "hover" else bg, 6, OnlineStyle.TEXT if picked else border, 3 if picked else 2)
		b.add_stylebox_override(st, sb)
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND if have else CURSOR_ARROW
	b.disabled = not have
	b.hint_tooltip = ("Showing" if picked else "Use this card") if have else "Locked"
	var v := VBoxContainer.new()
	v.anchor_right = 1
	v.anchor_bottom = 1
	v.alignment = BoxContainer.ALIGN_CENTER
	v.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(v)
	var nm: Label = S.label(String(c.get("name", "Card")), S.f_bold, OnlineStyle.TEXT)
	nm.align = Label.ALIGN_CENTER
	nm.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(nm)
	var sub: Label = S.label("Showing" if picked else ("" if have else "Locked"), S.f_small, OnlineStyle.DIM)
	sub.align = Label.ALIGN_CENTER
	sub.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(sub)
	if not have:
		b.modulate = Color(1, 1, 1, 0.45)
	b.connect("pressed", self, "_pick", [id])
	return b

func _pick(id: String):
	if lm != null:
		_msg.text = "Saving..."
		lm.set_card(id)

func _redeem(_t = null):
	var code := _code.text.strip_edges()
	if code == "" or lm == null:
		return
	_msg.text = "Checking the code..."
	lm.redeem_card_code(code)
	_code.text = ""

func _on_message(text: String, refresh: bool):
	_msg.text = text
	if refresh and lm != null:
		lm.get_cards()
