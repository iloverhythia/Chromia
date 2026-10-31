extends Control

# Seasonal themes (Settings > Replays & Misc > Seasonal Themes, on by default).
# Halloween (31 October, by your computer's clock): the Wave Menu turns
# orange / purple / green (WaveMenuBG.gd) and bats and embers drift over the
# menu (this). menu2.gd adds it; it removes itself on any other day.

const ORANGE := Color(1.0, 0.55, 0.12)
const BAT := Color(0.05, 0.02, 0.07, 0.9)
const BATS := 7
const EMBERS := 36

static func halloween() -> bool:
	if not Rhythia.get("seasonal_themes"):
		return false
	var d := OS.get_date()
	return int(d.month) == 10 and int(d.day) == 31

static func install(menu: Node):
	if menu == null or menu.has_node("Seasonal") or not halloween():
		return
	var s = load("res://scripts/ui/menu/Seasonal.gd").new()
	s.name = "Seasonal"
	menu.add_child(s)

var _bats := []    # [pos, velocity, size, flap phase]
var _embers := []  # [pos, speed, size, sway phase, life]
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_WIDE)
	_rng.randomize()
	for i in range(BATS):
		_bats.append(_new_bat(true))
	for i in range(EMBERS):
		_embers.append(_new_ember(true))
	Rhythia.connect("wave_menu_changed", self, "_on_setting")

func _on_setting(_v = null):
	if not halloween():
		queue_free()

func _new_bat(anywhere: bool) -> Array:
	var sz: Vector2 = get_viewport_rect().size
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	var x: float = _rng.randf_range(0, sz.x) if anywhere else (-60.0 if dir > 0 else sz.x + 60.0)
	var y: float = _rng.randf_range(sz.y * 0.05, sz.y * 0.55)
	var v := Vector2(dir * _rng.randf_range(40, 95), _rng.randf_range(-8, 8))
	return [Vector2(x, y), v, _rng.randf_range(9, 20), _rng.randf() * TAU]

func _new_ember(anywhere: bool) -> Array:
	var sz: Vector2 = get_viewport_rect().size
	var y: float = _rng.randf_range(sz.y * 0.4, sz.y) if anywhere else sz.y + 8.0
	return [Vector2(_rng.randf_range(0, sz.x), y), _rng.randf_range(14, 40), _rng.randf_range(1.2, 3.2), _rng.randf() * TAU, 0.0]

func _process(delta):
	if not is_visible_in_tree():
		return
	_t += delta
	var sz: Vector2 = get_viewport_rect().size
	for i in range(_bats.size()):
		var b: Array = _bats[i]
		b[0] += b[1] * delta + Vector2(0, sin(_t * 1.7 + b[3]) * 10.0 * delta)
		b[3] += delta * 9.0
		if b[0].x < -80 or b[0].x > sz.x + 80:
			_bats[i] = _new_bat(false)
	for i in range(_embers.size()):
		var e: Array = _embers[i]
		e[4] += delta
		e[0] += Vector2(sin(_t * 0.8 + e[3]) * 8.0, -e[1]) * delta
		if e[0].y < sz.y * 0.25:
			_embers[i] = _new_ember(false)
	update()

func _draw():
	var sz: Vector2 = get_viewport_rect().size
	for e in _embers:
		# fade in at the bottom, out as they rise
		var a: float = clamp(e[4] * 0.8, 0.0, 1.0) * clamp((e[0].y - sz.y * 0.25) / (sz.y * 0.4), 0.0, 1.0)
		draw_circle(e[0], e[2] * 2.4, Color(ORANGE.r, ORANGE.g * 0.8, ORANGE.b, 0.08 * a))
		draw_circle(e[0], e[2], Color(1.0, 0.7, 0.3, 0.55 * a))
	for b in _bats:
		_draw_bat(b[0], b[2], sin(b[3]), b[1].x < 0)

# a bat: body and two wings with scalloped edges, flapping (f -1..1)
func _draw_bat(p: Vector2, s: float, f: float, left: bool):
	var lift := f * 0.55
	for side in [-1.0, 1.0]:
		var pts := PoolVector2Array()
		pts.append(p + Vector2(side * 0.15, -0.1) * s)
		pts.append(p + Vector2(side * 0.9, -0.55 - lift) * s)
		pts.append(p + Vector2(side * 1.6, -0.25 - lift * 1.4) * s)
		pts.append(p + Vector2(side * 1.25, 0.15 - lift * 0.8) * s)
		pts.append(p + Vector2(side * 0.95, 0.0 - lift * 0.5) * s)
		pts.append(p + Vector2(side * 0.7, 0.3 - lift * 0.4) * s)
		pts.append(p + Vector2(side * 0.45, 0.1 - lift * 0.2) * s)
		pts.append(p + Vector2(side * 0.15, 0.3) * s)
		if side < 0:
			pts.invert()
		draw_colored_polygon(pts, BAT)
	draw_circle(p + Vector2(0, 0.05) * s, 0.28 * s, BAT)
	draw_circle(p + Vector2(0, -0.28) * s, 0.2 * s, BAT)
	# ears
	draw_colored_polygon(PoolVector2Array([p + Vector2(-0.18, -0.35) * s, p + Vector2(-0.12, -0.62) * s, p + Vector2(-0.02, -0.4) * s]), BAT)
	draw_colored_polygon(PoolVector2Array([p + Vector2(0.18, -0.35) * s, p + Vector2(0.12, -0.62) * s, p + Vector2(0.02, -0.4) * s]), BAT)
	# eyes, orange
	var eye := 0.05 * s
	draw_circle(p + Vector2(-0.08 if not left else -0.1, -0.3) * s, max(1.0, eye), ORANGE)
	draw_circle(p + Vector2(0.08 if not left else 0.06, -0.3) * s, max(1.0, eye), ORANGE)
