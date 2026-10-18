extends Control

# Secret: click the Furria icon next to the version text to open this.
# A never-ending upgrade tree. Furcoins only exist in here, and only grow
# while this screen is open. Progress is saved to user://furry_tree.json.

const SAVE_PATH = "user://furry_tree.json"
const NODE_SIZE = Vector2(170, 62)
const MIN_GAP = 195.0

const ADJ = ["Fluffy", "Soft", "Silky", "Bushy", "Glossy", "Cozy", "Wiggly", "Bouncy",
	"Majestic", "Shiny", "Velvet", "Cosmic", "Royal", "Floofy", "Snuggly", "Fuzzy",
	"Golden", "Ancient", "Hyper", "Mega", "Sparkly", "Toasty", "Feral", "Sleepy"]
const NOUN = ["Tail", "Ears", "Paws", "Whiskers", "Fur", "Snoot", "Beans", "Mane",
	"Fangs", "Collar", "Plush", "Fursuit", "Howl", "Purr", "Boop", "Scritch", "Den",
	"Pack", "Treat", "Brush", "Blep", "Zoomies", "Belly Rub", "Headpat"]
const SUFFIX = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

var coins: float = 0.0
var total_earned: float = 0.0
var nodes: Array = []   # each: {id, parent, depth, pos, name, kind, value, cost, bought, children}
var seed_base: int = 0

var _world: Control
var _coin_label: Label
var _rate_label: Label
var _info_label: Label
var _pet_btn: TextureButton
var _buttons: Dictionary = {}
var _rate: float = 1.0
var _pet: float = 1.0
var _cheap: float = 1.0
var _dragging := false
var _drag_moved := 0.0
var _zoom := 1.0
var _save_t := 0.0
var _ui_t := 0.0
var _hover_id := -1

var _sb_bought: StyleBoxFlat
var _sb_ready: StyleBoxFlat
var _sb_locked: StyleBoxFlat
var _font_small: DynamicFont
var _font_big: DynamicFont

func _font(size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = size
	return f

func _sb(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(12)
	return s

func _ready():
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	_font_small = _font(14)
	_font_big = _font(30)
	_sb_bought = _sb(Color(0.55, 0.2, 0.45), Color(1, 0.6, 0.9))
	_sb_ready = _sb(Color(0.1, 0.2, 0.12), Color(0.4, 1, 0.5))
	_sb_locked = _sb(Color(0.1, 0.1, 0.13), Color(0.4, 0.4, 0.45))

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.07, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	_world = Control.new()
	_world.mouse_filter = MOUSE_FILTER_IGNORE
	_world.connect("draw", self, "_draw_links")
	add_child(_world)

	var top := ColorRect.new()
	top.color = Color(0, 0, 0, 0.6)
	top.anchor_right = 1.0
	top.rect_min_size = Vector2(0, 70)
	top.mouse_filter = MOUSE_FILTER_STOP
	add_child(top)

	var title := Label.new()
	title.text = "Furry Upgrade Tree"
	title.add_font_override("font", _font_big)
	title.add_color_override("font_color", Color(1, 0.7, 0.93))
	title.rect_position = Vector2(20, 14)
	add_child(title)

	_coin_label = Label.new()
	_coin_label.add_font_override("font", _font(26))
	_coin_label.add_color_override("font_color", Color(1, 0.85, 0.35))
	_coin_label.anchor_left = 0.5
	_coin_label.anchor_right = 0.5
	_coin_label.margin_left = -250
	_coin_label.margin_right = 250
	_coin_label.margin_top = 6
	_coin_label.align = Label.ALIGN_CENTER
	add_child(_coin_label)

	_rate_label = Label.new()
	_rate_label.add_font_override("font", _font(16))
	_rate_label.add_color_override("font_color", Color(0.85, 0.85, 0.9))
	_rate_label.anchor_left = 0.5
	_rate_label.anchor_right = 0.5
	_rate_label.margin_left = -250
	_rate_label.margin_right = 250
	_rate_label.margin_top = 40
	_rate_label.align = Label.ALIGN_CENTER
	add_child(_rate_label)

	var close := Button.new()
	close.text = "Close"
	close.theme = preload("res://uitheme.tres")
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.margin_left = -110
	close.margin_right = -16
	close.margin_top = 16
	close.margin_bottom = 52
	close.connect("pressed", self, "close")
	add_child(close)

	var center := Button.new()
	center.text = "Recenter"
	center.theme = preload("res://uitheme.tres")
	center.anchor_left = 1.0
	center.anchor_right = 1.0
	center.margin_left = -220
	center.margin_right = -120
	center.margin_top = 16
	center.margin_bottom = 52
	center.connect("pressed", self, "_recenter")
	add_child(center)

	var bottom := ColorRect.new()
	bottom.color = Color(0, 0, 0, 0.6)
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.margin_top = -165
	bottom.mouse_filter = MOUSE_FILTER_STOP
	add_child(bottom)

	_pet_btn = TextureButton.new()
	_pet_btn.texture_normal = preload("res://assets/images/branding/icon.png")
	_pet_btn.expand = true
	_pet_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_pet_btn.anchor_top = 1.0
	_pet_btn.anchor_bottom = 1.0
	_pet_btn.margin_left = 24
	_pet_btn.margin_right = 144
	_pet_btn.margin_top = -150
	_pet_btn.margin_bottom = -30
	_pet_btn.rect_pivot_offset = Vector2(60, 60)
	_pet_btn.hint_tooltip = "Pet the furry"
	_pet_btn.connect("pressed", self, "_pet_pressed")
	add_child(_pet_btn)

	var pet_hint := Label.new()
	pet_hint.text = "pet me"
	pet_hint.add_font_override("font", _font_small)
	pet_hint.add_color_override("font_color", Color(1, 0.7, 0.93))
	pet_hint.anchor_top = 1.0
	pet_hint.anchor_bottom = 1.0
	pet_hint.margin_left = 24
	pet_hint.margin_right = 144
	pet_hint.margin_top = -28
	pet_hint.align = Label.ALIGN_CENTER
	add_child(pet_hint)

	_info_label = Label.new()
	_info_label.add_font_override("font", _font(18))
	_info_label.add_color_override("font_color", Color(0.95, 0.95, 1))
	_info_label.anchor_top = 1.0
	_info_label.anchor_bottom = 1.0
	_info_label.anchor_right = 1.0
	_info_label.margin_left = 170
	_info_label.margin_right = -20
	_info_label.margin_top = -90
	_info_label.margin_bottom = -20
	_info_label.valign = Label.VALIGN_BOTTOM
	_info_label.autowrap = true
	_info_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_info_label)

	set_process(false)

func open():
	if nodes.empty():
		_load()
	visible = true
	set_process(true)
	_recalc()
	_rebuild_buttons()
	_recenter()
	_refresh_ui()

func close():
	_save()
	visible = false
	set_process(false)

# --- Tree generation ---------------------------------------------------------

func _rng_for(id: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(seed_base) + ":" + str(id))
	return r

func _new_node(parent_id: int, pos: Vector2) -> Dictionary:
	var id := nodes.size()
	var r := _rng_for(id)
	var depth := 0 if parent_id < 0 else int(nodes[parent_id].depth) + 1
	var n := {
		"id": id, "parent": parent_id, "depth": depth,
		"x": pos.x, "y": pos.y, "bought": false, "children": [],
	}
	if id == 0:
		n.name = "Furry Origin"
		n.kind = "rate"
		n.value = 1.0
		n.cost = 10.0
	else:
		n.name = ADJ[r.randi() % ADJ.size()] + " " + NOUN[r.randi() % NOUN.size()]
		var roll := r.randf()
		if roll < 0.22:
			n.kind = "mult"
			n.value = 1.08 + 0.015 * min(depth, 40)
		elif roll < 0.36:
			n.kind = "pet"
			n.value = 2.0 * pow(2.05, depth) * r.randf_range(0.8, 1.2)
		elif roll < 0.44:
			n.kind = "cheap"
			n.value = 0.96
		else:
			n.kind = "rate"
			n.value = 1.2 * pow(2.1, depth) * r.randf_range(0.8, 1.3)
		n.cost = 15.0 * pow(2.45, depth) * r.randf_range(0.85, 1.25)
	nodes.append(n)
	if parent_id >= 0:
		nodes[parent_id].children.append(id)
	return n

func _pos(n) -> Vector2:
	return Vector2(n.x, n.y)

func _free_spot(p: Vector2) -> bool:
	for n in nodes:
		if _pos(n).distance_to(p) < MIN_GAP:
			return false
	return true

# Buying a node grows 2-3 new branches out of it, so the tree never ends.
func _grow(id: int):
	var n = nodes[id]
	var r := _rng_for(id * 7919 + 13)
	var count = 3 if id == 0 else (2 if r.randf() < 0.65 else 3)
	var base_dir := Vector2.UP
	if n.parent >= 0:
		base_dir = (_pos(n) - _pos(nodes[n.parent])).normalized()
	for k in range(count):
		var ang: float
		if id == 0:
			ang = -PI / 2 + TAU * k / count
		else:
			ang = base_dir.angle() + deg2rad(lerp(-55.0, 55.0, (k + 0.5) / count)) + r.randf_range(-0.15, 0.15)
		var placed := false
		var dist := 200.0
		while not placed and dist < 2000.0:
			for off in [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9]:
				var p := _pos(n) + Vector2(cos(ang + off), sin(ang + off)) * dist
				if _free_spot(p):
					_new_node(id, p)
					placed = true
					break
			dist += 60.0

# --- Economy -----------------------------------------------------------------

func _recalc():
	var rate := 1.0
	var mult := 1.0
	var pet := 1.0
	var cheap := 1.0
	for n in nodes:
		if not n.bought: continue
		match n.kind:
			"rate": rate += n.value
			"mult": mult *= n.value
			"pet": pet += n.value
			"cheap": cheap *= n.value
	_rate = rate * mult
	_pet = pet * mult
	_cheap = max(cheap, 0.25)

func _cost(n) -> float:
	return n.cost * _cheap

func _can_buy(n) -> bool:
	return not n.bought and (n.parent < 0 or nodes[n.parent].bought)

func _buy(id: int):
	var n = nodes[id]
	if not _can_buy(n) or coins < _cost(n):
		return
	coins -= _cost(n)
	n.bought = true
	_grow(id)
	_recalc()
	_rebuild_buttons()
	_refresh_ui()
	_show_info(id)

func _pet_pressed():
	coins += _pet
	total_earned += _pet
	_pet_btn.rect_scale = Vector2(0.88, 0.88)
	var t := create_tween()
	t.tween_property(_pet_btn, "rect_scale", Vector2.ONE, 0.15)
	_refresh_ui()

func _process(delta):
	coins += _rate * delta
	total_earned += _rate * delta
	_ui_t += delta
	if _ui_t >= 0.1:
		_ui_t = 0.0
		_refresh_ui()
	_save_t += delta
	if _save_t >= 10.0:
		_save_t = 0.0
		_save()

# --- Display -----------------------------------------------------------------

static func fmt(v: float) -> String:
	if v < 1000.0:
		return str(stepify(v, 0.1)) if v < 100.0 else str(int(v))
	var i := 0
	while v >= 1000.0 and i < SUFFIX.size() - 1:
		v /= 1000.0
		i += 1
	if v >= 1000.0:
		return "%.2fe%d" % [v / pow(10, floor(log(v) / log(10))), int(floor(log(v) / log(10))) + i * 3]
	return "%.2f%s" % [v, SUFFIX[i]]

func _describe(n) -> String:
	match n.kind:
		"rate": return "+%s furcoins/sec" % fmt(n.value)
		"mult": return "x%.2f all furcoin gains" % n.value
		"pet": return "+%s furcoins per pet" % fmt(n.value)
		"cheap": return "All upgrades %d%% cheaper" % int(round((1.0 - n.value) * 100))
	return ""

func _rebuild_buttons():
	for b in _buttons.values():
		b.queue_free()
	_buttons.clear()
	for n in nodes:
		if not n.bought and not _can_buy(n):
			continue
		var b := Button.new()
		b.rect_size = NODE_SIZE
		b.rect_position = _pos(n) - NODE_SIZE / 2
		var nm := Label.new()
		nm.name = "Name"
		nm.add_font_override("font", _font_small)
		nm.align = Label.ALIGN_CENTER
		nm.clip_text = true
		nm.anchor_right = 1.0
		nm.margin_left = 6
		nm.margin_right = -6
		nm.margin_top = 8
		nm.mouse_filter = MOUSE_FILTER_IGNORE
		b.add_child(nm)
		var cost := Label.new()
		cost.name = "Cost"
		cost.add_font_override("font", _font_small)
		cost.align = Label.ALIGN_CENTER
		cost.anchor_right = 1.0
		cost.margin_top = 32
		cost.mouse_filter = MOUSE_FILTER_IGNORE
		b.add_child(cost)
		b.connect("pressed", self, "_node_pressed", [n.id])
		b.connect("mouse_entered", self, "_show_info", [n.id])
		b.connect("mouse_exited", self, "_hide_info", [n.id])
		_world.add_child(b)
		_buttons[n.id] = b
	_style_buttons()
	_world.update()

func _style_buttons():
	for id in _buttons:
		var n = nodes[id]
		var b: Button = _buttons[id]
		var sb: StyleBoxFlat
		var nm: Label = b.get_node("Name")
		var cost: Label = b.get_node("Cost")
		nm.text = n.name
		if n.bought:
			sb = _sb_bought
			cost.text = _describe(n)
			cost.add_color_override("font_color", Color(1, 0.8, 0.95))
		else:
			var ok: bool = coins >= _cost(n)
			sb = _sb_ready if ok else _sb_locked
			cost.text = "%s furcoins" % fmt(_cost(n))
			cost.add_color_override("font_color", Color(1, 0.85, 0.35) if ok else Color(0.55, 0.55, 0.6))
		nm.add_color_override("font_color", Color(1, 1, 1) if n.bought or coins >= _cost(n) else Color(0.65, 0.65, 0.7))
		if b.get_stylebox("normal") != sb:
			for st in ["normal", "hover", "pressed", "focus"]:
				b.add_stylebox_override(st, sb)

func _draw_links():
	for n in nodes:
		if n.parent < 0: continue
		if not _buttons.has(n.id): continue
		var col = Color(1, 0.6, 0.9, 0.9) if n.bought else Color(0.6, 0.6, 0.7, 0.5)
		_world.draw_line(_pos(nodes[n.parent]), _pos(n), col, 4.0, true)

func _refresh_ui():
	_coin_label.text = "%s furcoins" % fmt(coins)
	var bought := 0
	for n in nodes:
		if n.bought: bought += 1
	_rate_label.text = "+%s/sec   •   %s per pet   •   %d upgrades" % [fmt(_rate), fmt(_pet), bought]
	_style_buttons()
	if _hover_id >= 0:
		_show_info(_hover_id)

func _show_info(id: int):
	_hover_id = id
	var n = nodes[id]
	var state = "Owned" if n.bought else "Cost: %s furcoins" % fmt(_cost(n))
	_info_label.text = "%s  (tier %d)\n%s\n%s" % [n.name, n.depth, _describe(n), state]

func _hide_info(id: int):
	if _hover_id == id:
		_hover_id = -1
		_info_label.text = ""

func _node_pressed(id: int):
	if _drag_moved > 8.0:
		return
	_buy(id)

func _recenter():
	_zoom = 1.0
	_world.rect_scale = Vector2.ONE
	var target := Vector2.ZERO
	var count := 0
	for n in nodes:
		if _buttons.has(n.id) and not n.bought:
			target += _pos(n)
			count += 1
	if count > 0:
		target /= count
	_world.rect_position = rect_size / 2 - target

# --- Pan & zoom --------------------------------------------------------------

func _input(ev):
	if not visible:
		return
	if ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()
		return
	if ev is InputEventMouseButton:
		if ev.button_index == BUTTON_LEFT:
			if ev.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
		elif ev.pressed and (ev.button_index == BUTTON_WHEEL_UP or ev.button_index == BUTTON_WHEEL_DOWN):
			var old = _zoom
			_zoom = clamp(_zoom * (1.1 if ev.button_index == BUTTON_WHEEL_UP else 1 / 1.1), 0.2, 2.5)
			var m: Vector2 = ev.position
			_world.rect_position = m - (m - _world.rect_position) * (_zoom / old)
			_world.rect_scale = Vector2(_zoom, _zoom)
			get_tree().set_input_as_handled()
	elif ev is InputEventMouseMotion and _dragging:
		_drag_moved += ev.relative.length()
		_world.rect_position += ev.relative

# --- Save / load -------------------------------------------------------------

func _save():
	if nodes.empty(): return
	var f := File.new()
	if f.open(SAVE_PATH, File.WRITE) != OK: return
	f.store_string(to_json({"coins": coins, "total": total_earned, "seed": seed_base, "nodes": nodes}))
	f.close()

func _load():
	var f := File.new()
	if f.file_exists(SAVE_PATH) and f.open(SAVE_PATH, File.READ) == OK:
		var p := JSON.parse(f.get_as_text())
		f.close()
		if p.error == OK and p.result is Dictionary and p.result.get("nodes") is Array and not p.result.nodes.empty():
			coins = float(p.result.get("coins", 0))
			total_earned = float(p.result.get("total", 0))
			seed_base = int(p.result.get("seed", 0))
			nodes = p.result.nodes
			for n in nodes:
				n.id = int(n.id)
				n.parent = int(n.parent)
				n.depth = int(n.depth)
				var ch := []
				for c in n.children: ch.append(int(c))
				n.children = ch
			return
	randomize()
	seed_base = randi()
	coins = 0.0
	nodes = []
	_new_node(-1, Vector2.ZERO)
