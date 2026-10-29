extends Control

signal closed

# Secret: click the Chromia icon next to the version text to open this.
# The Chromia Upgrade Tree: a never-ending upgrade tree paid for with chrome
# coins, which only exist in here and only grow while this screen is open.
#
# Prestige: 100 layers (Polish, Shine, Gleam ... Omega, Chromia). Resetting a
# layer gives its points and starts everything below it over: the tree, your
# coins and every lower layer. Points multiply your coin gain and the gains
# of the layers below. Each layer also has its own perk, unlocked for good the
# first time you reach it (the higher the layer, the stronger it is).
#
# Endless numbers: every amount (coins, prices, rates, points) is kept as its
# number of digits, log10 of it, so it can grow forever. Plain numbers stop
# at about 1e308 and then turned into "inf" / "nan" (and a save that could no
# longer be read). LZERO stands for 0.
#
# Progress is saved to user://furry_tree.json (the old name, so trees from
# before carry over).

const SAVE_PATH = "user://furry_tree.json"
const NODE_SIZE = Vector2(170, 52)
const MIN_GAP = 195.0
const LZERO := -1.0e18

const ADJ = ["Chrome", "Polished", "Neon", "Prismatic", "Mirrored", "Gleaming", "Holo", "Iridescent",
	"Radiant", "Glossy", "Liquid", "Cosmic", "Electric", "Shimmering", "Crystal", "Molten",
	"Silver", "Platinum", "Hyper", "Mega", "Sparkly", "Stellar", "Lucid", "Vivid"]
const NOUN = ["Note", "Beat", "Combo", "Grid", "Cursor", "Hit", "Rhythm", "Pulse", "Chord",
	"Tempo", "Drop", "Streak", "Spark", "Prism", "Lens", "Orb", "Core", "Wave", "Echo",
	"Glint", "Shard", "Mirror", "Coil", "Circuit"]
const SUFFIX = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

# --- Prestige layers --------------------------------------------------------
const LAYERS = [
	"Polish", "Shine", "Gleam", "Glint", "Sparkle", "Luster", "Sheen", "Glow", "Radiance", "Mirror",
	"Reflection", "Refraction", "Prism", "Spectrum", "Rainbow", "Hologram", "Neon", "Laser", "Plasma", "Aurora",
	"Starlight", "Moonbeam", "Sunburst", "Comet", "Meteor", "Nebula", "Pulsar", "Quasar", "Supernova", "Galaxy",
	"Cosmos", "Chroma", "Chrome", "Platinum", "Titanium", "Iridium", "Palladium", "Rhodium", "Osmium", "Mercury",
	"Quicksilver", "Crystal", "Diamond", "Sapphire", "Emerald", "Ruby", "Amethyst", "Opal", "Topaz", "Obsidian",
	"Beat", "Rhythm", "Tempo", "Groove", "Melody", "Harmony", "Chorus", "Echo", "Reverb", "Resonance",
	"Combo", "Streak", "Flow", "Overdrive", "Hyperspeed", "Warp", "Momentum", "Velocity", "Inertia", "Gravity",
	"Orbit", "Eclipse", "Zenith", "Apex", "Summit", "Pinnacle", "Ascension", "Transcendence", "Infinity", "Eternity",
	"Singularity", "Event Horizon", "Void", "Abyss", "Paradox", "Dimension", "Multiverse", "Omniverse", "Genesis", "Origin",
	"Myth", "Legend", "Saga", "Epic", "Divine", "Celestial", "Ethereal", "Absolute", "Omega", "Chromia",
]
# what each layer's perk is (layer 1 gets the first, layer 11 the first
# again but stronger, and so on)
const PERKS = ["rate", "click", "cheap", "start", "auto", "boost_prev", "branch", "keep", "power", "gains"]
const FIRST_REQ_L := 6.0 # 1e6 chrome coins in a run for the first Polish point

var coins_l: float = LZERO
var total_l: float = LZERO
var run_l: float = LZERO # chrome coins earned since the last prestige
var nodes: Array = []   # each: {id, parent, depth, x, y, name, kind, lv (log value) or value, lc (log cost), bought, children}
var seed_base: int = 0
var layers: Array = []  # per layer: {p: points, b: best, r: gathered since a higher reset (all log10), n: resets}

var _world: Control
var _coin_label: Label
var _rate_label: Label
var _info_label: Label
var _pet_btn: TextureButton
var _buttons: Dictionary = {}
var _rate_l: float = 0.0
var _pet_l: float = 0.0
var _cheap_l: float = 0.0
var _dragging := false
var _drag_moved := 0.0
var _zoom := 1.0
var _save_t := 0.0
var _ui_t := 0.0
var _hover_id := -1
var _bought_count := 0

# from the prestige layers (_recalc), all log10
var _coin_mult_l := 0.0
var _click_mult_l := 0.0
var _node_mult_l := 0.0
var _start_l := LZERO
var _keep_frac := 0.0
var _auto_every := 0.0 # seconds between auto-buys, 0 = off
var _extra_branches := 0
var _gain_mult_l := [] # per layer
var _auto_t := 0.0

var _sb_bought: StyleBoxFlat
var _sb_ready: StyleBoxFlat
var _sb_locked: StyleBoxFlat
var _sb_bought_hover: StyleBoxFlat
var _sb_ready_hover: StyleBoxFlat
const LILAC = Color(0.764706, 0.65098, 0.8)
const LILAC_HOVER = Color(0.913725, 0.74902, 0.94902)
const PINK = Color(1, 0.756863, 0.960784)
const CHROME = Color(0.85, 0.9, 1.0)
const DARK_TEXT = Color(0.1, 0.07, 0.12)
var _font_small: DynamicFont
var _font_big: DynamicFont
var _font_tiny: DynamicFont

# --- Endless numbers (log10) ----------------------------------------------------
static func lg(x: float) -> float:
	if is_nan(x) or x <= 0.0:
		return LZERO
	if is_inf(x):
		return 308.0
	return log(x) / log(10.0)

static func is_zero(a: float) -> bool:
	return a <= LZERO * 0.5

# a + b
static func ladd(a: float, b: float) -> float:
	if is_zero(a):
		return b
	if is_zero(b):
		return a
	var hi: float = max(a, b)
	var d: float = min(a, b) - hi
	if d < -17.0:
		return hi
	return hi + log(1.0 + pow(10.0, d)) / log(10.0)

# a - b (0 if b >= a)
static func lsub(a: float, b: float) -> float:
	if is_zero(b):
		return a
	var d: float = b - a
	if d >= -1e-12:
		return LZERO
	if d < -17.0:
		return a
	return a + log(1.0 - pow(10.0, d)) / log(10.0)

# 1 + a
static func l1p(a: float) -> float:
	return ladd(0.0, a)

# back to a plain number (only for small ones)
static func lval(a: float) -> float:
	return 0.0 if is_zero(a) else pow(10.0, min(a, 300.0))

# 1.23K, 4.56Dc, then 7.89e1234, then e1.23e45 ...
static func fmtl(a: float) -> String:
	if is_zero(a):
		return "0"
	if a < 2.0:
		return str(stepify(pow(10.0, a), 0.1))
	if a < 3.0:
		return str(int(round(pow(10.0, a))))
	var e := floor(a + 1e-9)
	if e < SUFFIX.size() * 3:
		var g := int(e / 3)
		return "%.2f%s" % [pow(10.0, a - g * 3), SUFFIX[g]]
	if a < 1e15:
		return "%.2fe%d" % [pow(10.0, a - e), int(e)]
	# more digits than can be written out: how many digits, in e-notation
	var de := floor(lg(a))
	return "e%.2fe%d" % [a / pow(10.0, de), int(de)]

static func fmt(v: float) -> String:
	return fmtl(lg(v))

func _font(size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = size
	return f

func _sb(bg: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	return s

func _ready():
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	_font_small = _font(14)
	_font_big = _font(30)
	_font_tiny = _font(12)
	# Same colors as the menu's buttons (uitheme.tres).
	_sb_bought = _sb(LILAC, LILAC, 0)
	_sb_bought_hover = _sb(LILAC_HOVER, LILAC_HOVER, 0)
	_sb_ready = _sb(Color(0.317647, 0.227451, 0.345098), LILAC)
	_sb_ready_hover = _sb(Color(0.4, 0.3, 0.44), LILAC_HOVER)
	_sb_locked = _sb(Color(0.1, 0.08, 0.12), Color(1, 1, 1, 0.12), 1)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.03, 0.98)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	_world = Control.new()
	_world.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_world)

	var top := ColorRect.new()
	top.color = Color(0, 0, 0, 0.94)
	top.anchor_right = 1.0
	top.rect_min_size = Vector2(0, 68)
	top.mouse_filter = MOUSE_FILTER_STOP
	add_child(top)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.18)
	line.anchor_right = 1.0
	line.margin_left = 24
	line.margin_right = -24
	line.margin_top = 68
	line.margin_bottom = 69
	line.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(line)

	var title := Label.new()
	title.text = "Chromia Upgrade Tree"
	title.add_font_override("font", _font(28))
	title.add_color_override("font_color", PINK)
	title.rect_position = Vector2(24, 16)
	add_child(title)

	_coin_label = Label.new()
	_coin_label.add_font_override("font", _font(24))
	_coin_label.add_color_override("font_color", CHROME)
	_coin_label.anchor_left = 0.5
	_coin_label.anchor_right = 0.5
	_coin_label.margin_left = -250
	_coin_label.margin_right = 250
	_coin_label.margin_top = 8
	_coin_label.align = Label.ALIGN_CENTER
	add_child(_coin_label)

	_rate_label = Label.new()
	_rate_label.add_font_override("font", _font(14))
	_rate_label.add_color_override("font_color", LILAC)
	_rate_label.anchor_left = 0.5
	_rate_label.anchor_right = 0.5
	_rate_label.margin_left = -300
	_rate_label.margin_right = 300
	_rate_label.margin_top = 38
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

	_prestige_btn = Button.new()
	_prestige_btn.text = "Prestige"
	_prestige_btn.theme = preload("res://uitheme.tres")
	_prestige_btn.anchor_left = 1.0
	_prestige_btn.anchor_right = 1.0
	_prestige_btn.margin_left = -330
	_prestige_btn.margin_right = -230
	_prestige_btn.margin_top = 16
	_prestige_btn.margin_bottom = 52
	_prestige_btn.connect("pressed", self, "_toggle_prestige")
	add_child(_prestige_btn)

	var bottom := ColorRect.new()
	bottom.color = Color(0, 0, 0, 0.94)
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.margin_top = -100
	bottom.mouse_filter = MOUSE_FILTER_STOP
	add_child(bottom)
	var bline := ColorRect.new()
	bline.color = Color(1, 1, 1, 0.18)
	bline.anchor_top = 1.0
	bline.anchor_bottom = 1.0
	bline.anchor_right = 1.0
	bline.margin_left = 24
	bline.margin_right = -24
	bline.margin_top = -100
	bline.margin_bottom = -99
	bline.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bline)

	_pet_btn = TextureButton.new()
	_pet_btn.texture_normal = preload("res://assets/images/branding/icon.png")
	_pet_btn.expand = true
	_pet_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_pet_btn.anchor_top = 1.0
	_pet_btn.anchor_bottom = 1.0
	_pet_btn.margin_left = 24
	_pet_btn.margin_right = 92
	_pet_btn.margin_top = -84
	_pet_btn.margin_bottom = -16
	_pet_btn.rect_pivot_offset = Vector2(34, 34)
	_pet_btn.hint_tooltip = "Click for chrome coins"
	_pet_btn.connect("pressed", self, "_pet_pressed")
	add_child(_pet_btn)

	_info_label = Label.new()
	_info_label.add_font_override("font", _font(15))
	_info_label.add_color_override("font_color", LILAC)
	_info_label.anchor_top = 1.0
	_info_label.anchor_bottom = 1.0
	_info_label.anchor_right = 1.0
	_info_label.margin_left = 112
	_info_label.margin_right = -24
	_info_label.margin_top = -90
	_info_label.margin_bottom = -16
	_info_label.text = "Click the Chromia logo for chrome coins. Click an upgrade to buy it. Drag to move, scroll to zoom. Prestige (top right) starts over for points that make everything faster."
	_info_label.valign = Label.VALIGN_BOTTOM
	_info_label.autowrap = true
	_info_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_info_label)

	_build_prestige_panel()
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
	emit_signal("closed") # the menu then deletes this screen entirely

# --- Tree generation ---------------------------------------------------------

func _rng_for(id: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(seed_base) + ":" + str(id))
	return r

static func _node_name(r: RandomNumberGenerator) -> String:
	return ADJ[r.randi() % ADJ.size()] + " " + NOUN[r.randi() % NOUN.size()]

func _new_node(parent_id: int, pos: Vector2) -> Dictionary:
	var id := nodes.size()
	var r := _rng_for(id)
	var depth := 0 if parent_id < 0 else int(nodes[parent_id].depth) + 1
	var n := {
		"id": id, "parent": parent_id, "depth": depth,
		"x": pos.x, "y": pos.y, "bought": false, "children": [],
	}
	if id == 0:
		n.name = "Chromia Origin"
		n.kind = "rate"
		n.lv = 0.0 # 1 coin / sec
		n.lc = 1.0 # 10 coins
	else:
		n.name = _node_name(r)
		var roll := r.randf()
		if roll < 0.22:
			n.kind = "mult"
			n.value = 1.08 + 0.015 * min(depth, 40)
		elif roll < 0.36:
			n.kind = "pet"
			n.lv = lg(2.0) + depth * lg(2.05) + lg(r.randf_range(0.8, 1.2))
		elif roll < 0.44:
			n.kind = "cheap"
			n.value = 0.96
		else:
			n.kind = "rate"
			n.lv = lg(1.2) + depth * lg(2.1) + lg(r.randf_range(0.8, 1.3))
		n.lc = lg(15.0) + depth * lg(2.45) + lg(r.randf_range(0.85, 1.25))
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

# Buying a node grows 2-3 new branches out of it (more with the Branch
# perks), so the tree never ends.
func _grow(id: int):
	var n = nodes[id]
	var r := _rng_for(id * 7919 + 13)
	var count = 3 if id == 0 else (2 if r.randf() < 0.65 else 3)
	count += _extra_branches
	var base_dir := Vector2.UP
	if n.parent >= 0:
		base_dir = (_pos(n) - _pos(nodes[n.parent])).normalized()
	var spread: float = 55.0 + 10.0 * _extra_branches
	for k in range(count):
		var ang: float
		if id == 0:
			ang = -PI / 2 + TAU * k / count
		else:
			ang = base_dir.angle() + deg2rad(lerp(-spread, spread, (k + 0.5) / count)) + r.randf_range(-0.15, 0.15)
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

func _new_tree():
	randomize()
	seed_base = randi()
	nodes = []
	_new_node(-1, Vector2.ZERO)

# --- Prestige ------------------------------------------------------------------

static func layer_count() -> int:
	return LAYERS.size()

func _layer(k: int) -> Dictionary: # k from 1
	return layers[k - 1]

static func _perk_kind(k: int) -> String:
	return PERKS[(k - 1) % PERKS.size()]

# how strong layer k's perk is ("start" is a log10 of coins)
static func _perk_value(k: int) -> float:
	var t := float(k)
	match _perk_kind(k):
		"rate": return 3.0 + t * 0.25
		"click": return 5.0 + t * 0.5
		"cheap": return min(0.1 + t * 0.003, 0.4) # (a share off)
		"start": return 2.0 + t * 0.6
		"auto": return max(2.5 / (1.0 + t / 15.0), 0.1) # seconds
		"boost_prev": return 2.0 + t * 0.1
		"branch": return 1.5 + t * 0.05
		"keep": return min(0.05 + t * 0.004, 0.9)
		"power": return 2.0 + t * 0.15
		"gains": return 1.5 + t * 0.03
	return 1.0

static func perk_text(k: int) -> String:
	var v := _perk_value(k)
	match _perk_kind(k):
		"rate": return "Chrome coins x%s" % _num(v)
		"click": return "Clicks give x%s" % _num(v)
		"cheap": return "Upgrades %d%% cheaper" % int(round(v * 100))
		"start": return "Every run starts with %s chrome coins" % fmtl(v)
		"auto": return "Buys the cheapest upgrade for you every %ss" % _num(v)
		"boost_prev": return "%s gains x%s" % [LAYERS[k - 2] if k >= 2 else "Polish", _num(v)]
		"branch": return "Upgrades grow one more branch (up to 3) and chrome coins x%s" % _num(v)
		"keep": return "Keep %d%% of your chrome coins when you prestige" % int(round(v * 100))
		"power": return "Coin and click upgrades x%s stronger" % _num(v)
		"gains": return "Every layer's prestige gains x%s" % _num(v)
	return ""

static func _num(v: float) -> String:
	return str(stepify(v, 0.01))

# what layer k needs (log10): chrome coins this run (layer 1), or points of
# the layer below gathered since layer k (or higher) last reset
static func _req_l(k: int) -> float:
	if k == 1:
		return FIRST_REQ_L
	return lg(4.0) + (k - 2) * lg(1.35)

func _source_l(k: int) -> float:
	return run_l if k == 1 else float(_layer(k - 1).r)

# points a reset of layer k gives (log10, LZERO if under 1)
func gain_l(k: int) -> float:
	var s := _source_l(k)
	var req := _req_l(k)
	if is_zero(s) or s < req:
		return LZERO
	var mult: float = _gain_mult_l[k - 1] if _gain_mult_l.size() >= k else 0.0
	var g: float = 0.5 * (s - req) + mult
	if g < 0.0:
		return LZERO
	if g < 15.0:
		g = lg(floor(pow(10.0, g) + 1e-6)) # whole points
	return g

func can_prestige(k: int) -> bool:
	return not is_zero(gain_l(k))

func _reached(k: int) -> bool:
	return not is_zero(float(_layer(k).b))

func _highest_reached() -> int:
	var h := 0
	for k in range(1, layer_count() + 1):
		if _reached(k):
			h = k
	return h

func prestige(k: int) -> bool:
	var g := gain_l(k)
	if is_zero(g):
		return false
	var L := _layer(k)
	L.p = ladd(float(L.p), g)
	L.b = max(float(L.b), float(L.p))
	L.r = ladd(float(L.r), g)
	L.n = int(L.n) + 1
	for j in range(1, k):
		_layer(j).p = LZERO
		_layer(j).r = LZERO
	# everything below starts over (with what the perks give back)
	_recalc() # (perks just unlocked count for the new run)
	var kept: float = coins_l + lg(_keep_frac) if _keep_frac > 0.0 else LZERO
	_new_tree()
	coins_l = max(_start_l, kept)
	run_l = LZERO
	_recalc()
	_rebuild_buttons()
	_recenter()
	_refresh_ui()
	_save()
	return true

# --- Economy -----------------------------------------------------------------

func _recalc():
	_ensure_layers()
	# the layers
	_coin_mult_l = 0.0
	_click_mult_l = 0.0
	_node_mult_l = 0.0
	_start_l = LZERO
	_keep_frac = 0.0
	_auto_every = 0.0
	_extra_branches = 0
	var cheap_perk := 1.0
	var gains_all_l := 0.0
	var boost := []
	for k in range(1, layer_count() + 1):
		boost.append(0.0)
	for k in range(1, layer_count() + 1):
		var L := _layer(k)
		var pts: float = float(L.p)
		if not is_zero(pts):
			_coin_mult_l += 0.5 * l1p(pts)
		if not _reached(k):
			continue
		var v := _perk_value(k)
		match _perk_kind(k):
			"rate":
				_coin_mult_l += lg(v)
			"click":
				_click_mult_l += lg(v)
			"cheap":
				cheap_perk *= 1.0 - v
			"start":
				_start_l = max(_start_l, v)
			"auto":
				_auto_every = v if _auto_every <= 0.0 else min(_auto_every, v)
			"boost_prev":
				if k >= 2:
					boost[k - 2] += lg(v)
			"branch":
				_extra_branches = min(_extra_branches + 1, 3)
				_coin_mult_l += lg(v)
			"keep":
				_keep_frac = max(_keep_frac, v)
			"power":
				_node_mult_l += lg(v)
			"gains":
				gains_all_l += lg(v)
	# each layer's gains: higher layers' points, the perks
	var per := []
	var above := 0.0
	for k in range(layer_count(), 0, -1):
		per.push_front(above + boost[k - 1] + gains_all_l)
		var pts: float = float(_layer(k).p)
		if not is_zero(pts):
			above += 0.35 * l1p(pts)
	_gain_mult_l = per
	# the tree
	var rate := 0.0 # (1 coin / sec to start with)
	var pet := 0.0
	var mult := 0.0
	var cheap := 0.0
	_bought_count = 0
	for n in nodes:
		if not n.bought: continue
		_bought_count += 1
		match n.kind:
			"rate": rate = ladd(rate, float(n.lv))
			"mult": mult += lg(float(n.value))
			"pet": pet = ladd(pet, float(n.lv))
			"cheap": cheap += lg(float(n.value))
	_rate_l = rate + _node_mult_l + mult + _coin_mult_l
	_pet_l = pet + _node_mult_l + mult + _click_mult_l + _coin_mult_l
	_cheap_l = max(cheap, lg(0.25)) + max(lg(cheap_perk), lg(0.02))

func _cost_l(n) -> float:
	return float(n.lc) + _cheap_l

func _affordable(n) -> bool:
	return coins_l >= _cost_l(n) - 1e-9

func _can_buy(n) -> bool:
	return not n.bought and (n.parent < 0 or nodes[n.parent].bought)

func _buy(id: int, quiet: bool = false):
	var n = nodes[id]
	if not _can_buy(n) or not _affordable(n):
		return
	coins_l = lsub(coins_l, _cost_l(n))
	n.bought = true
	_grow(id)
	_recalc()
	# Only the bought upgrade and its new branches change; a "cheaper" upgrade
	# changes every price, so then every button gets marked for a restyle.
	if n.kind == "cheap":
		for b in _buttons.values():
			b.set_meta("st", -1)
	if _buttons.has(id):
		_buttons[id].set_meta("st", -1)
	for c in n.children:
		if not _buttons.has(c):
			_make_button(nodes[c])
	_style_buttons()
	_update_links()
	_refresh_ui()
	if not quiet:
		_show_info(id)

# the Auto perks: the cheapest upgrade you can afford
func _auto_buy():
	var best := -1
	var best_cost := 0.0
	for n in nodes:
		if _can_buy(n) and _affordable(n):
			var c := _cost_l(n)
			if best < 0 or c < best_cost:
				best = n.id
				best_cost = c
	if best >= 0:
		_buy(best, true)

func _earn(v_l: float):
	coins_l = ladd(coins_l, v_l)
	total_l = ladd(total_l, v_l)
	run_l = ladd(run_l, v_l)

func _pet_pressed():
	_earn(_pet_l)
	_pet_btn.rect_scale = Vector2(0.88, 0.88)
	var t := create_tween()
	t.tween_property(_pet_btn, "rect_scale", Vector2.ONE, 0.15)
	_refresh_ui()

func _process(delta):
	if delta > 0.0:
		_earn(_rate_l + lg(delta))
	if _auto_every > 0.0:
		_auto_t += delta
		if _auto_t >= _auto_every:
			_auto_t = 0.0
			_auto_buy()
	_ui_t += delta
	if _ui_t >= 0.1:
		_ui_t = 0.0
		_refresh_ui()
	_save_t += delta
	if _save_t >= 10.0:
		_save_t = 0.0
		_save()
	if _confirm_layer > 0:
		_confirm_t -= delta
		if _confirm_t <= 0.0:
			_confirm_layer = -1

# --- Display -----------------------------------------------------------------

func _describe(n) -> String:
	match n.kind:
		"rate": return "+%s chrome coins/sec" % fmtl(float(n.lv) + _node_mult_l)
		"mult": return "x%.2f all chrome coin gains" % float(n.value)
		"pet": return "+%s chrome coins per click" % fmtl(float(n.lv) + _node_mult_l)
		"cheap": return "All upgrades %d%% cheaper" % int(round((1.0 - float(n.value)) * 100))
	return ""

func _rebuild_buttons():
	for b in _buttons.values():
		b.queue_free()
	_buttons.clear()
	_cells.clear()
	for n in nodes:
		if n.bought or _can_buy(n):
			_make_button(n)
	_style_buttons(true)
	_update_links()

func _make_button(n):
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
	nm.margin_top = 7
	nm.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(nm)
	var cost := Label.new()
	cost.name = "Cost"
	cost.align = Label.ALIGN_CENTER
	cost.anchor_right = 1.0
	cost.margin_top = 27
	cost.add_font_override("font", _font_tiny)
	cost.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(cost)
	b.connect("pressed", self, "_node_pressed", [n.id])
	b.connect("mouse_entered", self, "_show_info", [n.id])
	b.connect("mouse_exited", self, "_hide_info", [n.id])
	b.set_meta("st", -1)
	_world.add_child(b)
	_buttons[n.id] = b
	var cell := _cell_of(_pos(n))
	if not _cells.has(cell):
		_cells[cell] = []
	_cells[cell].append(n.id)

# Buttons are filed by area of the tree, so the on-screen check only looks
# at the areas that are actually on screen.
const CELL = 600.0
var _cells: Dictionary = {}
func _cell_of(p: Vector2) -> Vector2:
	return Vector2(floor(p.x / CELL), floor(p.y / CELL))

func _ids_on_screen() -> Array:
	var view: Rect2 = get_viewport_rect()
	var z: float = max(_zoom, 0.01)
	var a: Vector2 = (view.position - _world.rect_position) / z - NODE_SIZE
	var b: Vector2 = (view.end - _world.rect_position) / z + NODE_SIZE
	var ca := _cell_of(a)
	var cb := _cell_of(b)
	var out := []
	for cx in range(int(ca.x), int(cb.x) + 1):
		for cy in range(int(ca.y), int(cb.y) + 1):
			var k := Vector2(cx, cy)
			if _cells.has(k):
				out.append_array(_cells[k])
	return out

# Only upgrades on screen are checked, and a button is only restyled when it
# changes (bought, or becomes affordable / unaffordable). force=true restyles
# everything, for when the buttons were just made or prices changed.
func _style_buttons(force: bool = false):
	var ids = _buttons.keys() if force else _ids_on_screen()
	for id in ids:
		var n = nodes[id]
		var b: Button = _buttons[id]
		var ok: bool = _affordable(n)
		var state: int = 2 if n.bought else (1 if ok else 0)
		if not force and int(b.get_meta("st")) == state:
			continue
		b.set_meta("st", state)
		var sb: StyleBoxFlat
		var nm: Label = b.get_node("Name")
		var cost: Label = b.get_node("Cost")
		nm.text = n.name
		var hover: StyleBoxFlat
		if n.bought:
			sb = _sb_bought
			hover = _sb_bought_hover
			cost.text = _describe(n)
			nm.add_color_override("font_color", DARK_TEXT)
			cost.add_color_override("font_color", Color(0.25, 0.18, 0.28))
		else:
			sb = _sb_ready if ok else _sb_locked
			hover = _sb_ready_hover if ok else _sb_locked
			cost.text = "%s chrome coins" % fmtl(_cost_l(n))
			nm.add_color_override("font_color", Color(1, 1, 1) if ok else Color(1, 1, 1, 0.45))
			cost.add_color_override("font_color", PINK if ok else Color(1, 1, 1, 0.3))
		if b.get_stylebox("normal") != sb:
			b.add_stylebox_override("normal", sb)
			b.add_stylebox_override("focus", StyleBoxEmpty.new())
			b.add_stylebox_override("hover", hover)
			b.add_stylebox_override("pressed", hover)

# Links are drawn as batched thin lines (draw_multiline) on the world
# itself, doubled with a 1px offset so they read as ~2px. Thick or smoothed
# draw_line calls stop drawing once the tree gets big; batched thin lines don't.
var _owned_pts := PoolVector2Array()
var _other_pts := PoolVector2Array()
var _links_hooked := false

func _update_links():
	if not _links_hooked:
		_links_hooked = true
		_world.connect("draw", self, "_draw_links")
	_owned_pts = PoolVector2Array()
	_other_pts = PoolVector2Array()
	for n in nodes:
		if n.parent < 0 or not _buttons.has(n.id): continue
		var a := _pos(nodes[n.parent])
		var b := _pos(n)
		var pts: PoolVector2Array = _owned_pts if n.bought else _other_pts
		pts.append(a); pts.append(b)
		pts.append(a + Vector2.ONE); pts.append(b + Vector2.ONE)
		if n.bought: _owned_pts = pts
		else: _other_pts = pts
	_world.update()

func _draw_links():
	if _other_pts.size() > 0:
		_world.draw_multiline(_other_pts, Color(1, 1, 1, 0.14))
	if _owned_pts.size() > 0:
		_world.draw_multiline(_owned_pts, Color(LILAC.r, LILAC.g, LILAC.b, 0.8))

func _refresh_ui():
	_coin_label.text = "%s chrome coins" % fmtl(coins_l)
	var h := _highest_reached()
	var extra := ""
	if h > 0:
		extra = "    prestige x%s" % fmtl(_coin_mult_l)
	_rate_label.text = "+%s / sec    %s per click    %d upgrades%s" % [fmtl(_rate_l), fmtl(_pet_l), _bought_count, extra]
	# the Prestige button lights up when a reset is ready
	var ready := false
	for k in range(1, min(h + 1, layer_count()) + 1):
		if can_prestige(k):
			ready = true
			break
	_prestige_btn.text = "Prestige!" if ready else "Prestige"
	_prestige_btn.modulate = Color(1, 0.85, 1) if ready else Color(1, 1, 1)
	_style_buttons()
	if _hover_id >= 0:
		_show_info(_hover_id)
	if _panel.visible:
		_refresh_panel()

func _show_info(id: int):
	_hover_id = id
	var n = nodes[id]
	var state = "Owned" if n.bought else "Cost: %s chrome coins" % fmtl(_cost_l(n))
	_info_label.text = "%s  ·  tier %d\n%s\n%s" % [n.name, n.depth, _describe(n), state]

func _hide_info(id: int):
	if _hover_id == id:
		_hover_id = -1

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

# --- The prestige panel ------------------------------------------------------------
# A list of the layers you've reached and the next one. Each row: the layer,
# your points, its perk, and a button to reset for its points (pressed twice
# to be sure: it starts everything below over).

var _prestige_btn: Button
var _panel: Control
var _rows_box: VBoxContainer
var _rows := [] # [Label, Label, Button] per shown layer
var _panel_hint: Label
var _confirm_layer := -1
var _confirm_t := 0.0
var _shown_layers := 0

func _build_prestige_panel():
	_panel = Control.new()
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.margin_top = 70
	_panel.margin_bottom = -101
	_panel.visible = false
	_panel.mouse_filter = MOUSE_FILTER_STOP
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_panel.add_child(dim)
	var box := PanelContainer.new()
	var sb := _sb(Color(0.07, 0.05, 0.09, 0.98), Color(1, 1, 1, 0.18), 1)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	box.add_stylebox_override("panel", sb)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_bottom = 1.0
	box.margin_left = -470
	box.margin_right = 470
	box.margin_top = 16
	box.margin_bottom = -16
	_panel.add_child(box)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 10)
	box.add_child(v)
	var t := Label.new()
	t.text = "Prestige"
	t.add_font_override("font", _font(24))
	t.add_color_override("font_color", PINK)
	v.add_child(t)
	var d := Label.new()
	d.text = "Start over for points. Each layer resets the tree, your chrome coins and the layers below it. Points multiply your chrome coins and the layers below, and each layer's perk stays once you reach it."
	d.autowrap = true
	d.add_font_override("font", _font(14))
	d.add_color_override("font_color", LILAC)
	v.add_child(d)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	v.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows_box.add_constant_override("separation", 6)
	scroll.add_child(_rows_box)
	_panel_hint = Label.new()
	_panel_hint.add_font_override("font", _font(13))
	_panel_hint.add_color_override("font_color", Color(1, 1, 1, 0.45))
	v.add_child(_panel_hint)

func _toggle_prestige():
	_panel.visible = not _panel.visible
	_confirm_layer = -1
	if _panel.visible:
		_refresh_panel()

static func _layer_color(k: int, sat: float, alpha: float = 1.0) -> Color:
	var c := Color.from_hsv(fmod(k * 0.031, 1.0), sat, 1.0)
	c.a = alpha
	return c

# rows for the layers reached and the next one
func _rebuild_rows():
	var want: int = min(_highest_reached() + 1, layer_count())
	if want == _shown_layers and _rows.size() == want:
		return
	for c in _rows_box.get_children():
		c.queue_free()
	_rows = []
	_shown_layers = want
	for k in range(1, want + 1):
		var row := PanelContainer.new()
		var rsb := _sb(Color(0.11, 0.08, 0.13), _layer_color(k, 0.45, 0.55), 1)
		rsb.content_margin_left = 12
		rsb.content_margin_right = 12
		rsb.content_margin_top = 8
		rsb.content_margin_bottom = 8
		row.add_stylebox_override("panel", rsb)
		_rows_box.add_child(row)
		var h := HBoxContainer.new()
		h.add_constant_override("separation", 12)
		row.add_child(h)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(left)
		var name_l := Label.new()
		name_l.add_font_override("font", _font(17))
		name_l.add_color_override("font_color", _layer_color(k, 0.35))
		left.add_child(name_l)
		var info_l := Label.new()
		info_l.autowrap = true
		info_l.add_font_override("font", _font(13))
		info_l.add_color_override("font_color", LILAC)
		left.add_child(info_l)
		var b := Button.new()
		b.theme = preload("res://uitheme.tres")
		b.rect_min_size = Vector2(210, 44)
		b.size_flags_vertical = SIZE_SHRINK_CENTER
		b.connect("pressed", self, "_on_prestige_pressed", [k])
		h.add_child(b)
		_rows.append([name_l, info_l, b])

func _refresh_panel():
	_rebuild_rows()
	for i in range(_rows.size()):
		var k := i + 1
		var L := _layer(k)
		var r: Array = _rows[i]
		var reached := _reached(k)
		var pts: float = float(L.p)
		if reached:
			r[0].text = "%d. %s   %s points" % [k, LAYERS[k - 1], fmtl(pts)]
		else:
			r[0].text = "%d. %s   (not reached yet)" % [k, LAYERS[k - 1]]
		var src := "chrome coins this run" if k == 1 else "%s points since the last %s" % [LAYERS[k - 2], LAYERS[k - 1]]
		var bonus := ""
		if not is_zero(pts):
			bonus = "Points: chrome coins x%s, lower layers x%s.  " % [fmtl(0.5 * l1p(pts)), fmtl(0.35 * l1p(pts))]
		r[1].text = "%sPerk%s: %s\nNeeds %s %s (you have %s)" % [bonus, "" if reached else " (unlocks when reached)", perk_text(k), fmtl(_req_l(k)), src, fmtl(_source_l(k))]
		var g := gain_l(k)
		var b: Button = r[2]
		b.disabled = is_zero(g)
		if _confirm_layer == k:
			b.text = "Sure? Click again"
		else:
			b.text = ("Reset for +%s" % fmtl(g)) if not is_zero(g) else "Not enough yet"
	var left := layer_count() - _shown_layers
	_panel_hint.text = ("%d more layers to discover." % left) if left > 0 else "Every layer reached. You made it to Chromia!"

func _on_prestige_pressed(k: int):
	if not can_prestige(k):
		return
	if _confirm_layer != k:
		_confirm_layer = k
		_confirm_t = 3.0
		_refresh_panel()
		return
	_confirm_layer = -1
	if prestige(k):
		_info_label.text = "%s reset: you got its points, and the tree starts over." % LAYERS[k - 1]
	_refresh_panel()

# --- Pan & zoom --------------------------------------------------------------

func _input(ev):
	if not visible:
		return
	if ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		if _panel.visible:
			_toggle_prestige()
		else:
			close()
		get_tree().set_input_as_handled()
		return
	if _panel.visible:
		_dragging = false
		return # (the list scrolls with the wheel; the tree stays put)
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

func _ensure_layers():
	while layers.size() < layer_count():
		layers.append({"p": LZERO, "b": LZERO, "r": LZERO, "n": 0})

func _save():
	if nodes.empty(): return
	var f := File.new()
	if f.open(SAVE_PATH, File.WRITE) != OK: return
	f.store_string(to_json({"v": 2, "coins_l": coins_l, "total_l": total_l, "run_l": run_l, "seed": seed_base, "nodes": nodes, "layers": layers}))
	f.close()

# a log10 from the file: finite, or LZERO
static func _fl(v) -> float:
	var x := float(v) if (typeof(v) == TYPE_REAL or typeof(v) == TYPE_INT) else LZERO
	if is_nan(x) or is_inf(x):
		return LZERO
	return max(x, LZERO)

func _load():
	var f := File.new()
	layers = []
	if f.file_exists(SAVE_PATH) and f.open(SAVE_PATH, File.READ) == OK:
		var text := f.get_as_text()
		f.close()
		# saves from before could hold numbers that had gone past the limit
		# (inf / nan), which isn't JSON: read them as the biggest / no number
		var re := RegEx.new()
		re.compile("(?<=[:\\[,])\\s*-?(inf|nan)(?=\\s*[,}\\]])")
		var had_bad := re.search(text) != null
		if had_bad:
			text = re.sub(text, "1e308", true)
		var p := JSON.parse(text)
		if p.error == OK and p.result is Dictionary and p.result.get("nodes") is Array and not p.result.nodes.empty():
			var d: Dictionary = p.result
			var v2: bool = int(d.get("v", 1)) >= 2
			seed_base = int(d.get("seed", 0))
			nodes = d.nodes
			for n in nodes:
				n.id = int(n.id)
				n.parent = int(n.parent)
				n.depth = int(n.depth)
				var ch := []
				for c in n.children: ch.append(int(c))
				n.children = ch
				# names in the Chromia style (the same picks as when it grew)
				n.name = "Chromia Origin" if n.id == 0 else _node_name(_rng_for(n.id))
				if not n.has("lc"):
					# a save from before: plain numbers to digits
					n.lc = lg(float(n.get("cost", 10.0)))
					if n.kind == "rate" or n.kind == "pet":
						n.lv = lg(float(n.get("value", 1.0)))
					n.erase("cost")
					if n.kind == "rate" or n.kind == "pet":
						n.erase("value")
				else:
					n.lc = _fl(n.lc)
					if n.has("lv"):
						n.lv = _fl(n.lv)
			if v2:
				coins_l = _fl(d.get("coins_l", LZERO))
				total_l = _fl(d.get("total_l", LZERO))
				run_l = _fl(d.get("run_l", LZERO))
				var saved = d.get("layers")
				if saved is Array:
					for i in range(min(saved.size(), layer_count())):
						var s = saved[i]
						if not (s is Dictionary):
							break
						layers.append({"p": _fl(s.get("p", LZERO)), "b": _fl(s.get("b", LZERO)), "r": _fl(s.get("r", LZERO)), "n": int(max(0.0, _fl(s.get("n", 0))))})
			else:
				coins_l = lg(float(d.get("coins", 0)))
				total_l = lg(float(d.get("total", 0)))
				run_l = total_l
			_ensure_layers()
			if had_bad or is_zero(coins_l) and _bought_any():
				# the coins had gone past the limit: what this tree makes in 10 minutes
				_recalc()
				coins_l = max(coins_l, _rate_l + lg(600.0))
				total_l = max(total_l, coins_l)
				run_l = max(run_l, coins_l)
			return
	coins_l = LZERO
	total_l = LZERO
	run_l = LZERO
	_new_tree()
	_ensure_layers()

func _bought_any() -> bool:
	for n in nodes:
		if n.bought:
			return true
	return false

# Save if the menu goes away while the tree is still open.
func _exit_tree():
	if visible:
		_save()
