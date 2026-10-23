extends CanvasLayer

# Phones/tablets: a marker under each finger touching the screen (menus and
# songs). Everything about it is set in Settings > Gameplay > Touch Indicator
# > Customize (scripts/ui/TouchIndicatorEditor.gd) and kept in
# Rhythia.touch_style. A picture saved as "touch" in the user folder can
# replace the shape.
#
# Watching a replay that has fingers recorded (scripts/game/TouchRecorder.gd,
# Replay.touches) shows those instead of your own, on computers too.

const DEFAULTS := {
	"shape": "ring",          # one of SHAPES
	"size": 46.0,             # diameter, layout pixels
	"thickness": 3.0,         # outline width
	"color": "ffffdbf7",      # outline (Godot html, aarrggbb)
	"fill": "1fffffff",       # inside
	"opacity": 1.0,
	"fade": 0.18,             # seconds to fade after lifting
	"grow": true,             # grows a little while fading
	"pop": false,             # pops in when touching
	"ripple": false,          # a ring spreads out on each tap
	"ripple_size": 1.7,       # how far it spreads (x size)
	"trail": false,           # a line behind a moving finger
	"trail_time": 0.25,       # seconds of trail
	"trail_width": 0.45,      # x size
	"rainbow": false,         # colours cycle
	"rainbow_speed": 0.5,
	"in_menus": true,
	"in_songs": true,
}
const SHAPES := ["ring", "circle", "dot", "ring_dot", "square", "diamond", "cross", "image"]
const SHAPE_NAMES := ["Ring", "Filled circle", "Dot", "Ring with dot", "Square", "Diamond", "Crosshair", "Custom picture"]

const PRESETS := {
	"Default": {},
	"Minimal": {"shape": "dot", "size": 18.0, "fill": "c8ffffff", "fade": 0.1, "grow": false},
	"Neon": {"shape": "ring", "size": 56.0, "thickness": 5.0, "color": "ff7df9ff", "fill": "00000000", "ripple": true, "trail": true, "trail_time": 0.3},
	"Rainbow": {"shape": "ring_dot", "size": 50.0, "thickness": 4.0, "rainbow": true, "trail": true, "pop": true},
	"Crosshair": {"shape": "cross", "size": 40.0, "thickness": 2.0, "color": "ffffffff", "fill": "00000000", "grow": false},
	"Ghost": {"shape": "circle", "size": 70.0, "fill": "33c3a6cc", "color": "00ffffff", "opacity": 0.8, "fade": 0.4},
}

var _touches := {}        # finger -> {pos, alpha, down, t0, trail:[[pos, t]]}
var _ripples := []        # [{pos, t, hue}]
var _canvas: Control
var _custom: Texture = null
var _time := 0.0
var _st := {}             # style() for this frame (it's read a lot)
var replay_only := false  # made just to show a replay's fingers (computers): ignores your own touches
var _rp_i := 0            # next Replay.touches entry to show
var _rp_last := -1e12     # replay time shown last frame
var _rp_on := false
var _spawn = null         # the replay's note spawner (its rms is the replay clock)
const TRAIL_MAX := 48     # trail points kept per finger
const TRAIL_STEP := 3.0   # px a finger has to move for a new trail point

static func style() -> Dictionary:
	var s := DEFAULTS.duplicate()
	var user = Rhythia.touch_style
	if user is Dictionary:
		for k in user:
			if s.has(k):
				s[k] = user[k]
	return s

# NoteManager: a replay with fingers is starting; make sure something shows them.
static func for_replay():
	if not Rhythia.replaying or Rhythia.replay == null or Rhythia.replay.get("touches") == null or Rhythia.replay.touches.empty():
		return
	if Rhythia.has_node("TouchIndicator"):
		return
	var t = load("res://scripts/ui/TouchIndicator.gd").new()
	t.name = "TouchIndicator"
	t.replay_only = true
	Rhythia.call_deferred("add_child", t)

static func color_of(v, fallback: Color) -> Color:
	if typeof(v) == TYPE_STRING and String(v).is_valid_html_color():
		return Color(v)
	return fallback

func _ready():
	layer = 128 # above everything, notifications included
	pause_mode = PAUSE_MODE_PROCESS
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.anchor_right = 1.0
	_canvas.anchor_bottom = 1.0
	_canvas.connect("draw", self, "_draw_touches")
	add_child(_canvas)
	reload_picture()

func reload_picture():
	_custom = Globals.imageLoader.load_if_exists("user://touch")
	if _custom == Globals.imageLoader.error_texture or _custom == Globals.imageLoader.invalid_texture:
		_custom = null

func _shown(st: Dictionary) -> bool:
	if not Rhythia.show_touch_indicator:
		return false
	return bool(st.in_songs) if Rhythia.in_map else bool(st.in_menus)

func _input(event):
	if _st.empty():
		_st = style()
	var st: Dictionary = _st
	if not _shown(st):
		if not _touches.empty() or not _ripples.empty():
			_touches.clear()
			_ripples.clear()
			_canvas.update()
		return
	if replay_only or _replay_active():
		return # showing a replay's fingers
	if event is InputEventScreenTouch:
		if event.pressed:
			_down(event.index, event.position, st, true)
		else:
			_up(event.index, event.position)
	elif event is InputEventScreenDrag:
		_move(event.index, event.position, st, true)

func _down(finger: int, pos: Vector2, st: Dictionary, effects: bool):
	_touches[finger] = {pos = pos, alpha = 1.0, down = true, t0 = _time, trail = [[pos, _time]] if effects else []}
	if effects and st.ripple:
		_ripples.append({pos = pos, t = _time, hue = _hue(finger, st)})

func _up(finger: int, pos: Vector2):
	if _touches.has(finger):
		_touches[finger].pos = pos
		_touches[finger].down = false

func _move(finger: int, pos: Vector2, st: Dictionary, effects: bool):
	if not _touches.has(finger):
		_touches[finger] = {pos = pos, alpha = 1.0, down = true, t0 = _time, trail = []}
	var t: Dictionary = _touches[finger]
	t.pos = pos
	if effects and st.trail:
		# a point only when the finger really moved (phones send many
		# drag events per frame), and not too many of them
		if t.trail.empty() or pos.distance_to(t.trail[-1][0]) >= TRAIL_STEP:
			t.trail.append([pos, _time])
			if t.trail.size() > TRAIL_MAX:
				t.trail.pop_front()

# --- Replays -------------------------------------------------------------------

func _replay_active() -> bool:
	if not Rhythia.replaying or not Rhythia.in_map or Rhythia.replay == null:
		return false
	var list = Rhythia.replay.get("touches")
	return list != null and not list.empty()

func _replay_clock():
	if _spawn != null and is_instance_valid(_spawn) and _spawn.is_inside_tree():
		return _spawn
	_spawn = null
	var cs = get_tree().current_scene
	if cs != null:
		_spawn = cs.find_node("Spawn", true, false)
		if _spawn != null and _spawn.get("rms") == null:
			_spawn = null
	return _spawn

# Where a recorded finger goes on this screen: the game keeps the height of
# the view, so positions scale with the height around the middle (the finger
# stays on the cursor on screens of another shape).
func _replay_pos(e: Array) -> Vector2:
	var rec: Vector2 = Rhythia.replay.touch_screen
	var now: Vector2 = get_viewport().get_visible_rect().size
	var p := Vector2(e[3], e[4])
	if rec.y <= 0:
		return p
	return now / 2.0 + (p - rec / 2.0) * (now.y / rec.y)

func _replay_apply(e: Array, st: Dictionary, effects: bool):
	var pos := _replay_pos(e)
	match int(e[1]):
		0: # down
			_down(int(e[2]), pos, st, effects)
		1: # move
			_move(int(e[2]), pos, st, effects)
		_: # up
			if effects:
				_up(int(e[2]), pos)
			else:
				_touches.erase(int(e[2]))

func _feed_replay(st: Dictionary):
	var sp = _replay_clock()
	if sp == null:
		return
	var ms: float = float(sp.rms)
	var list: Array = Rhythia.replay.touches
	if ms < _rp_last - 1.0 or ms > _rp_last + 400.0:
		# started, or jumped somewhere else in the replay: the fingers as they
		# were then, without trails or ripples for everything in between
		_touches.clear()
		_ripples.clear()
		_rp_i = 0
		while _rp_i < list.size() and float(list[_rp_i][0]) <= ms:
			_replay_apply(list[_rp_i], st, false)
			_rp_i += 1
	else:
		while _rp_i < list.size() and float(list[_rp_i][0]) <= ms:
			_replay_apply(list[_rp_i], st, true)
			_rp_i += 1
	_rp_last = ms

func _process(delta):
	_time += delta
	_st = style()
	var rp := _replay_active()
	if rp != _rp_on:
		# a replay started or ended: nothing carries over
		_rp_on = rp
		_rp_last = -1e12
		_touches.clear()
		_ripples.clear()
		_canvas.update()
	if rp and _shown(_st):
		_feed_replay(_st)
	if _touches.empty() and _ripples.empty():
		return
	var st: Dictionary = _st
	var gone := []
	for i in _touches:
		var t: Dictionary = _touches[i]
		if not t.down:
			t.alpha -= delta / max(float(st.fade), 0.01)
			if t.alpha <= 0.0:
				gone.append(i)
		# drop trail points older than the trail
		while t.trail.size() > 0 and _time - t.trail[0][1] > float(st.trail_time):
			t.trail.pop_front()
	for i in gone:
		_touches.erase(i)
	while _ripples.size() > 0 and _time - _ripples[0].t > 0.5:
		_ripples.pop_front()
	_canvas.update()

func _hue(index: int, st: Dictionary) -> float:
	return fmod(_time * float(st.rainbow_speed) + index * 0.17, 1.0)

func _draw_touches():
	var st: Dictionary = _st if not _st.empty() else style()
	for r in _ripples:
		draw_ripple(_canvas, r.pos, (_time - r.t) / 0.5, st, r.hue)
	for i in _touches:
		var t: Dictionary = _touches[i]
		var a: float = clamp(t.alpha, 0.0, 1.0)
		var hue := _hue(i, st)
		if st.trail and t.trail.size() > 1:
			draw_trail(_canvas, t.trail, _time, st, a, hue)
		draw_marker(_canvas, t.pos, a, st, marker_scale(st, _time - t.t0, a), hue, _custom)

# --- Drawing (also used by the preview in the editor) -----------------------

# `held`: seconds since the finger touched, `a`: 1 while held, fading to 0
static func marker_scale(st: Dictionary, held: float, a: float) -> float:
	var sc := 1.0
	if st.pop:
		sc *= lerp(0.55, 1.0, ease(clamp(held / 0.12, 0.0, 1.0), 0.4))
	if st.grow:
		sc *= 1.0 + (1.0 - a) * 0.35
	return sc

static func _tint(c: Color, st: Dictionary, hue: float, a: float) -> Color:
	if st.rainbow:
		var r := Color.from_hsv(hue, 0.55, 1.0)
		r.a = c.a
		c = r
	c.a *= clamp(float(st.opacity), 0.0, 1.0) * a
	return c

static func draw_marker(ci: CanvasItem, pos: Vector2, a: float, st: Dictionary, sc: float, hue: float, picture: Texture):
	var r: float = float(st.size) * 0.5 * sc
	var w: float = max(float(st.thickness), 0.5)
	var line := _tint(color_of(st.color, Color(1, 0.86, 0.97)), st, hue, a)
	var fill := _tint(color_of(st.fill, Color(1, 1, 1, 0.12)), st, hue, a)
	match String(st.shape):
		"image":
			if picture:
				ci.draw_texture_rect(picture, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2), false, Color(1, 1, 1, clamp(float(st.opacity), 0.0, 1.0) * a))
			else:
				ci.draw_arc(pos, r, 0, TAU, 40, line, w, true)
		"circle":
			ci.draw_circle(pos, r, fill)
			if line.a > 0.0:
				ci.draw_arc(pos, r, 0, TAU, 40, line, w, true)
		"dot":
			ci.draw_circle(pos, r, fill if fill.a > 0.0 else line)
		"ring_dot":
			ci.draw_circle(pos, r, fill)
			ci.draw_arc(pos, r, 0, TAU, 40, line, w, true)
			ci.draw_circle(pos, max(r * 0.18, w), line)
		"square":
			var rect := Rect2(pos - Vector2(r, r), Vector2(r, r) * 2)
			ci.draw_rect(rect, fill, true)
			if line.a > 0.0:
				ci.draw_rect(rect, line, false, w, true)
		"diamond":
			var pts := PoolVector2Array([pos + Vector2(0, -r), pos + Vector2(r, 0), pos + Vector2(0, r), pos + Vector2(-r, 0)])
			ci.draw_colored_polygon(pts, fill)
			if line.a > 0.0:
				pts.append(pts[0])
				ci.draw_polyline(pts, line, w, true)
		"cross":
			ci.draw_circle(pos, r, fill)
			var gap := r * 0.3
			ci.draw_line(pos + Vector2(-r, 0), pos + Vector2(-gap, 0), line, w, true)
			ci.draw_line(pos + Vector2(gap, 0), pos + Vector2(r, 0), line, w, true)
			ci.draw_line(pos + Vector2(0, -r), pos + Vector2(0, -gap), line, w, true)
			ci.draw_line(pos + Vector2(0, gap), pos + Vector2(0, r), line, w, true)
		_: # ring
			ci.draw_circle(pos, r, fill)
			ci.draw_arc(pos, r, 0, TAU, 40, line, w, true)

static func draw_ripple(ci: CanvasItem, pos: Vector2, k: float, st: Dictionary, hue: float):
	k = clamp(k, 0.0, 1.0)
	var r: float = float(st.size) * 0.5 * lerp(1.0, float(st.ripple_size), ease(k, 0.5))
	var c := _tint(color_of(st.color, Color(1, 0.86, 0.97)), st, hue, 1.0 - k)
	ci.draw_arc(pos, r, 0, TAU, 48, c, max(float(st.thickness) * (1.0 - k * 0.6), 0.5), true)

static func draw_trail(ci: CanvasItem, pts: Array, now: float, st: Dictionary, a: float, hue: float):
	var base := _tint(color_of(st.color, Color(1, 0.86, 0.97)), st, hue, a)
	var width: float = float(st.size) * float(st.trail_width)
	var life: float = max(float(st.trail_time), 0.01)
	var n := pts.size()
	if n < 2:
		return
	# A tapered ribbon in one continuous strip: each point gets a side
	# direction averaged from the segments around it, and neighbouring quads
	# share their edges (a few dozen quads, where it used to be hundreds of
	# overlapping circles).
	var side := []
	var wid := []
	var col := []
	for i in range(n):
		var p: Vector2 = pts[i][0]
		var a_dir := Vector2.ZERO
		if i > 0:
			a_dir += (p - pts[i - 1][0]).normalized()
		if i < n - 1:
			a_dir += (pts[i + 1][0] - p).normalized()
		if a_dir.length_squared() < 0.0001:
			a_dir = Vector2.RIGHT if side.empty() else Vector2(side[-1].y, -side[-1].x)
		a_dir = a_dir.normalized()
		side.append(Vector2(-a_dir.y, a_dir.x))
		var k: float = clamp(1.0 - (now - pts[i][1]) / life, 0.0, 1.0)
		wid.append(max(width * k * 0.5, 0.75))
		var c := base
		c.a *= k * 0.6
		col.append(c)
	for i in range(1, n):
		if col[i].a <= 0.0 and col[i - 1].a <= 0.0:
			continue
		var p0: Vector2 = pts[i - 1][0]
		var p1: Vector2 = pts[i][0]
		ci.draw_primitive(PoolVector2Array([p0 + side[i - 1] * wid[i - 1], p1 + side[i] * wid[i], p1 - side[i] * wid[i], p0 - side[i - 1] * wid[i - 1]]),
			PoolColorArray([col[i - 1], col[i], col[i], col[i - 1]]), PoolVector2Array())
	# round end at the finger
	if col[n - 1].a > 0.0:
		ci.draw_circle(pts[n - 1][0], wid[n - 1], col[n - 1])
