extends Control

# Seasonal themes (Settings > Replays & Misc > Seasonal Themes, on by default),
# by your computer's clock. menu2.gd adds this; it removes itself when the
# season is over (or the setting is turned off).
#   Halloween (31 October): the Wave Menu turns orange / purple / green
#     (WaveMenuBG.gd) and bats and embers drift over the menu.
#   Christmas (1 to 26 December): the Wave Menu turns red / green / gold,
#     snow falls over the menu and a string of lights twinkles along the top.
# To see one on another day, start the game with --season=christmas (or
# --season=halloween).

const ORANGE := Color(1.0, 0.55, 0.12)
const BAT := Color(0.05, 0.02, 0.07, 0.9)
const BATS := 7
const EMBERS := 36
const FLAKES := 90
const BULBS := [Color(1.0, 0.22, 0.22), Color(0.25, 0.9, 0.35), Color(1.0, 0.8, 0.25), Color(0.35, 0.6, 1.0), Color(1.0, 0.45, 0.85)]

# "halloween", "christmas" or ""
static func season() -> String:
	if not Rhythia.get("seasonal_themes"):
		return ""
	for a in OS.get_cmdline_args():
		if String(a).begins_with("--season="):
			return String(a).trim_prefix("--season=").to_lower()
	var d := OS.get_date()
	if int(d.month) == 10 and int(d.day) == 31:
		return "halloween"
	if int(d.month) == 12 and int(d.day) <= 26:
		return "christmas"
	return ""

static func halloween() -> bool:
	return season() == "halloween"

static func christmas() -> bool:
	return season() == "christmas"

static func install(menu: Node):
	if menu == null or menu.has_node("Seasonal") or not (halloween() or christmas()):
		return
	var s = load("res://scripts/ui/menu/Seasonal.gd").new()
	s.name = "Seasonal"
	menu.add_child(s)

var _season := ""
var _bats := []    # [pos, velocity, size, flap phase]
var _embers := []  # [pos, speed, size, sway phase, life]
var _flakes := []  # [pos, fall speed, size, sway phase, star shaped]
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_WIDE)
	_rng.randomize()
	_season = season()
	if _season == "halloween":
		for i in range(BATS):
			_bats.append(_new_bat(true))
		for i in range(EMBERS):
			_embers.append(_new_ember(true))
	else:
		for i in range(FLAKES):
			_flakes.append(_new_flake(true))
	Rhythia.connect("wave_menu_changed", self, "_on_setting")

func _on_setting(_v = null):
	if season() != _season:
		queue_free()

func _new_flake(anywhere: bool) -> Array:
	var sz: Vector2 = get_viewport_rect().size
	var y: float = _rng.randf_range(-10, sz.y) if anywhere else -10.0
	var big := _rng.randf() < 0.12
	var s: float = _rng.randf_range(4.0, 7.0) if big else _rng.randf_range(1.0, 2.8)
	# (bigger flakes are nearer: they fall faster)
	return [Vector2(_rng.randf_range(-20, sz.x + 20), y), _rng.randf_range(18, 32) + s * 9.0, s, _rng.randf() * TAU, big]

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
	for i in range(_flakes.size()):
		var f: Array = _flakes[i]
		f[0] += Vector2(sin(_t * 0.6 + f[3]) * 14.0 + 6.0, f[1]) * delta
		f[3] += delta * 0.4
		if f[0].y > sz.y + 12:
			_flakes[i] = _new_flake(false)
	update()

func _draw():
	if _season == "christmas":
		_draw_christmas()
		return
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

# --- Christmas -------------------------------------------------------------------
func _draw_christmas():
	var sz: Vector2 = get_viewport_rect().size
	for f in _flakes:
		var a: float = 0.85 if f[4] else 0.55
		if f[4]:
			_draw_flake(f[0], f[2], f[3], Color(1, 1, 1, a))
		else:
			draw_circle(f[0], f[2], Color(1, 1, 1, a))
	_draw_lights(sz)

# a six-armed snowflake, turning slowly
func _draw_flake(p: Vector2, s: float, turn: float, c: Color):
	draw_circle(p, s * 1.6, Color(1, 1, 1, c.a * 0.08))
	for k in range(6):
		var d := Vector2(0, -1).rotated(turn + k * TAU / 6.0)
		var tip := p + d * s
		draw_line(p, tip, c, 1.2, true)
		var mid := p + d * s * 0.55
		draw_line(mid, mid + d.rotated(0.75) * s * 0.35, c, 1.0, true)
		draw_line(mid, mid + d.rotated(-0.75) * s * 0.35, c, 1.0, true)

# a string of lights along the top: the wire sags between hooks, each bulb
# twinkles on its own
func _draw_lights(sz: Vector2):
	var spacing := 54.0
	var hooks := int(ceil(sz.x / (spacing * 4))) + 1
	var span: float = sz.x / float(hooks - 1) if hooks > 1 else sz.x
	var sag := 16.0
	var top := 6.0
	var wire := PoolVector2Array()
	var steps := int(sz.x / 8.0) + 1
	for i in range(steps + 1):
		var x := float(i) / steps * sz.x
		var u := fmod(x, span) / span
		wire.append(Vector2(x, top + sag * 4.0 * u * (1.0 - u)))
	draw_polyline(wire, Color(0.08, 0.16, 0.08, 0.95), 2.0, true)
	var n := int(sz.x / spacing) + 1
	for i in range(n):
		var x := (i + 0.5) * spacing
		if x > sz.x:
			break
		var u := fmod(x, span) / span
		var at := Vector2(x, top + sag * 4.0 * u * (1.0 - u))
		var c: Color = BULBS[i % BULBS.size()]
		var tw: float = 0.55 + 0.45 * sin(_t * (1.3 + fmod(i * 0.37, 1.1)) + i * 1.9)
		var bulb := at + Vector2(0, 9)
		draw_rect(Rect2(at + Vector2(-2.5, 1), Vector2(5, 4)), Color(0.15, 0.2, 0.15))
		draw_circle(bulb, 13.0, Color(c.r, c.g, c.b, 0.12 * tw))
		draw_circle(bulb, 7.5, Color(c.r, c.g, c.b, 0.22 * tw))
		draw_circle(bulb, 4.5, c.darkened(0.5 * (1.0 - tw)))
		draw_circle(bulb + Vector2(-1.3, -1.5), 1.3, Color(1, 1, 1, 0.55 * tw))
