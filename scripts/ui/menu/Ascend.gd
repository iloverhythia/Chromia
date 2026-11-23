extends Control

# A secret. Typing ASCEND in Inventory & Misc > Codes opens this: a burst of
# light that grows over the whole screen and shrinks again, and behind it a
# small top-down pixel world in Chromia's colours. You are a little pixel
# figure (WASD or the arrow keys), something types unsettling lines along the
# bottom, and there is a hall with four doors. Behind each door is a room with
# a puzzle:
#
#   north  the grid       the nine plates light up in an order: walk it
#   east   the blocks     push the three note blocks into their sockets
#   west   the spectrum   wake the six crystals in the order of the logo
#   south  the dark       cross a floor you can only see around yourself
#
# With all four solved the altar in the hall wakes: step on it and the server
# gives the Ascension card and its frame (savia_web src/cards.js ascended();
# LobbyManager's "card_code" answer shows the unlock notice).
#
# Everything is drawn here with rectangles into a 320 x 180 picture that is
# shown enlarged without smoothing; there are no picture files. It only
# exists while it is open. Solved rooms are remembered (user://ascend.json).

const W := 320
const H := 180
const T := 16 # a tile
const COLS := 20
const ROWS := 11
const SAVE := "user://ascend.json"
const SPEED := 62.0

# the logo's colours, sky to leaf (the spectrum room's order)
const SPECTRUM := [Color("8ec9ff"), Color("9b9cff"), Color("d480e6"), Color("f586b2"), Color("f6c07a"), Color("a4f07c")]
const C_FLOOR := Color("15111d")
const C_FLOOR_LINE := Color("211a2d")
const C_WALL := Color("382c4b")
const C_WALL_HI := Color("5d4a7c")
const C_WALL_LO := Color("241b33")
const C_LILAC := Color("c3a6cc")
const C_PINK := Color("ffc1f5")
const C_GOLD := Color("ffe08a")

const HUB := 0
const R_GRID := 1
const R_BLOCKS := 2
const R_SPECTRUM := 3
const R_DARK := 4

var room := HUB
var solved := [false, false, false, false]
var pos := Vector2(9.5 * T, 7.5 * T) # the figure's feet, in pixels of the small picture
var facing := 1
var walk_t := 0.0
var moving := false
var time := 0.0
var frozen := 0.0 # seconds the figure can't move (a fall, a wrong step)
var flash := 0.0 # a red (wrong) or white (right) flash over the room
var flash_col := Color(1, 1, 1)
var maps := {} # room -> Array of PoolByteArray-like strings
var _closing := false

# the grid
var seq := []
var seq_show := -1 # which step is lit while it is shown (-1: not showing)
var seq_t := 0.0
var seq_at := 0 # how far the player has got
var plate_lit := -1
var plate_lit_t := 0.0
var last_plate := -1
# the blocks
const BLOCKS_START := [Vector2(5, 3), Vector2(8, 5), Vector2(5, 7)]
const SOCKETS := [Vector2(15, 2), Vector2(15, 5), Vector2(15, 8)]
var blocks := []
var push_t := 0.0
var push_dir := Vector2.ZERO
# the spectrum
const CRYSTALS := [[Vector2(4, 3), 3], [Vector2(9, 7), 0], [Vector2(14, 3), 5], [Vector2(6, 8), 1], [Vector2(13, 8), 4], [Vector2(3, 6), 2]]
var woken := 0
var bump_wait := 0.0
# the dark
var dark_safe := {} # Vector2 tile -> true

# what is on screen
var _vp: Viewport
var _world: Node2D
var _view: TextureRect
var _burst: ColorRect
var _burst_r := 0.0
var _phase := "in" # in, hold, out, play, end_in, end_wait, end_out
var _phase_t := 0.0
var _dlg_band: ColorRect
var _dlg: Label
var _hint: Label
var _lines := [] # waiting to be typed
var _line := ""
var _typed := 0.0
var _line_hold := 0.0
var _pad := Vector2.ZERO # the on-screen arrows (touch, VR)
var _esc_at := -100.0
var _answer_wait := 0.0

static func is_word(code: String) -> bool:
	return code.strip_edges().to_upper() == "ASCEND"

static func open_on(from: Node):
	for old in from.get_tree().get_nodes_in_group("ascend"):
		return old
	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.name = "AscendLayer"
	from.get_viewport().add_child(layer)
	var a = load("res://scripts/ui/menu/Ascend.gd").new()
	a.name = "Ascend"
	a.add_to_group("ascend")
	layer.add_child(a)
	return a

# --- the rooms ---------------------------------------------------------------------

func _make_maps():
	maps[HUB] = [
		"#########N##########",
		"#..................#",
		"#...#..........#...#",
		"#..................#",
		"#..................#",
		"W........A.........E",
		"#..................#",
		"#..................#",
		"#...#..........#...#",
		"#..................#",
		"#########S##########"]
	maps[R_GRID] = [
		"####################",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..T...............#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#########X##########"]
	maps[R_BLOCKS] = [
		"####################",
		"#..........#.......#",
		"#..........#.......#",
		"#..........#.......#",
		"#..................#",
		"X..................#",
		"#..................#",
		"#..........#.......#",
		"#.R........#.......#",
		"#..........#.......#",
		"####################"]
	maps[R_SPECTRUM] = [
		"####################",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................X",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"####################"]
	maps[R_DARK] = [
		"#########X##########",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"####################"]
	# the dark's safe floor: a path with a few dead ends
	dark_safe = {}
	for seg in [[9, 1, 9, 3], [4, 3, 9, 3], [4, 3, 4, 6], [4, 6, 12, 6], [12, 4, 12, 6], [12, 4, 16, 4], [16, 4, 16, 8],
			[2, 3, 4, 3], [2, 3, 2, 8], [7, 6, 7, 9], [12, 1, 12, 4], [9, 6, 9, 8], [16, 2, 18, 2], [16, 2, 16, 4]]:
		for x in range(min(seg[0], seg[2]), max(seg[0], seg[2]) + 1):
			for y in range(min(seg[1], seg[3]), max(seg[1], seg[3]) + 1):
				dark_safe[Vector2(x, y)] = true

const DARK_GOAL := Vector2(16, 8)
const PLATE_XS := [8, 10, 12]
const PLATE_YS := [3, 5, 7]

func tile_at(c: int, r: int) -> String:
	if c < 0 or r < 0 or c >= COLS or r >= ROWS:
		return "#"
	return maps[room][r][c]

func _block_on(t: Vector2) -> int:
	if room != R_BLOCKS:
		return -1
	for i in range(blocks.size()):
		if blocks[i] == t:
			return i
	return -1

func _crystal_on(t: Vector2) -> int:
	if room != R_SPECTRUM:
		return -1
	for i in range(CRYSTALS.size()):
		if CRYSTALS[i][0] == t:
			return i
	return -1

func solid(c: int, r: int) -> bool:
	var ch := tile_at(c, r)
	if ch == "#" or ch == "T":
		return true
	if _block_on(Vector2(c, r)) >= 0 or _crystal_on(Vector2(c, r)) >= 0:
		return true
	return false

# --- starting up -------------------------------------------------------------------

func _ready():
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP
	pause_mode = PAUSE_MODE_PROCESS
	_make_maps()
	_load()
	_reset_blocks()

	var back := ColorRect.new()
	back.name = "Back"
	back.color = Color(0, 0, 0, 1)
	back.anchor_right = 1.0
	back.anchor_bottom = 1.0
	back.mouse_filter = MOUSE_FILTER_IGNORE
	back.visible = false
	add_child(back)

	_vp = Viewport.new()
	_vp.size = Vector2(W, H)
	_vp.usage = Viewport.USAGE_2D
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_v_flip = true
	_vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	add_child(_vp)
	_world = PixelWorld.new()
	_world.host = self
	_vp.add_child(_world)

	_view = TextureRect.new()
	_view.name = "View"
	_view.expand = true
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = MOUSE_FILTER_IGNORE
	_view.visible = false
	add_child(_view)
	var tex := _vp.get_texture()
	tex.flags = 0 # (no smoothing: square pixels)
	_view.texture = tex

	# the lines typed along the bottom
	_dlg_band = ColorRect.new()
	_dlg_band.name = "DialogBand"
	_dlg_band.mouse_filter = MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment() { COLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.0, 0.35, UV.y) * 0.72); }"
	sm.shader = sh
	_dlg_band.material = sm
	_dlg_band.visible = false
	add_child(_dlg_band)
	_dlg = Label.new()
	_dlg.name = "Dialog"
	_dlg.mouse_filter = MOUSE_FILTER_IGNORE
	_dlg.valign = Label.VALIGN_CENTER
	_dlg.add_color_override("font_color", Color(0.93, 0.9, 0.98))
	add_child(_dlg)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.mouse_filter = MOUSE_FILTER_IGNORE
	_hint.text = "WASD to walk   Esc to leave"
	_hint.add_color_override("font_color", Color(0.8, 0.76, 0.9, 0.7))
	_hint.visible = false
	add_child(_hint)
	if Rhythia.vr or Rhythia.device("mobile"):
		_add_pad()

	# the light
	_burst = ColorRect.new()
	_burst.name = "Burst"
	_burst.anchor_right = 1.0
	_burst.anchor_bottom = 1.0
	_burst.mouse_filter = MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	var bs := Shader.new()
	bs.code = BURST_SHADER
	bm.shader = bs
	_burst.material = bm
	add_child(_burst)

	connect("resized", self, "_layout")
	_layout()
	var lm = get_node_or_null("/root/LobbyManager")
	if lm != null:
		if lm.has_signal("code_result"):
			lm.connect("code_result", self, "_on_answer")
		if lm.has_method("_ensure_connected_then_send"):
			lm._ensure_connected_then_send({"type": "ascend_start", "client_id": Rhythia.cid})
	Rhythia.trail("the word was typed")

const BURST_SHADER := """
shader_type canvas_item;
uniform float r = 0.0;
uniform float t = 0.0;
uniform float aspect = 1.78;
void fragment() {
	vec2 p = (UV - vec2(0.5, 0.56)) * vec2(aspect, 1.0);
	float d = length(p);
	float a = atan(p.y, p.x);
	float rays = pow(abs(sin(a * 6.0 + t * 0.9)) * abs(sin(a * 2.5 - t * 0.6)) + 0.25 * abs(sin(a * 17.0 + t * 1.7)), 1.6);
	float core = smoothstep(r * 0.42, 0.0, d);
	float glow = smoothstep(r * 1.05, 0.0, d);
	float ray = rays * smoothstep(r * 1.9, r * 0.1, d);
	float grain = fract(sin(dot(floor(UV * vec2(aspect, 1.0) * 220.0) + floor(t * 24.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 col = mix(vec3(1.0, 0.72, 0.12), vec3(1.0, 0.97, 0.78), clamp(core * 1.4 + glow * 0.3, 0.0, 1.0));
	float al = clamp(glow * 0.85 + ray * 0.9 + core * 1.2, 0.0, 1.0);
	al *= step(0.001, r);
	al = clamp(al + (grain - 0.5) * 0.12 * al, 0.0, 1.0);
	// (at its biggest it is the whole screen: what is behind it is changed then)
	float cover = smoothstep(2.0, 2.8, r);
	al = max(al, cover);
	col = mix(col + core * 0.6, vec3(1.0, 0.98, 0.88), cover);
	COLOR = vec4(col, al);
}
"""

func _layout():
	var s := rect_size
	if s.x <= 0 or s.y <= 0:
		return
	var k: float = min(s.x / W, s.y / H)
	var vs := Vector2(W, H) * k
	_view.rect_size = vs
	_view.rect_position = ((s - vs) / 2.0).floor()
	var px: float = max(1.0, k)
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/VT323/VT323-Regular.ttf") if ResourceLoader.exists("res://assets/font/VT323/VT323-Regular.ttf") else load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = int(clamp(round(11.0 * px), 14, 72))
	_dlg.add_font_override("font", f)
	var band_h: float = 44.0 * px
	_dlg_band.rect_position = Vector2(_view.rect_position.x, _view.rect_position.y + vs.y - band_h)
	_dlg_band.rect_size = Vector2(vs.x, band_h)
	_dlg.rect_position = _dlg_band.rect_position + Vector2(8.0 * px, band_h * 0.38)
	_dlg.rect_size = Vector2(vs.x - 16.0 * px, band_h * 0.62)
	var hf := DynamicFont.new()
	hf.font_data = f.font_data
	hf.size = int(clamp(round(7.0 * px), 12, 40))
	_hint.add_font_override("font", hf)
	_hint.rect_position = _view.rect_position + Vector2(6.0 * px, 4.0 * px)
	(_burst.material as ShaderMaterial).set_shader_param("aspect", s.x / s.y)
	if has_node("Pad"):
		var pad: Control = get_node("Pad")
		var u: float = 26.0 * px
		pad.rect_position = Vector2(_view.rect_position.x + 10.0 * px, _view.rect_position.y + vs.y - band_h - u * 3.2)
		var places := {"u": Vector2(1, 0), "l": Vector2(0, 1), "r": Vector2(2, 1), "d": Vector2(1, 2)}
		for n in places:
			var b: Button = pad.get_node(n)
			b.rect_position = places[n] * u
			b.rect_size = Vector2(u, u) * 0.94

# arrows for a finger or a VR pointer (held down to walk), and a way out
func _add_pad():
	var pad := Control.new()
	pad.name = "Pad"
	pad.visible = false
	add_child(pad)
	for d in [["u", "^", Vector2(0, -1)], ["l", "<", Vector2(-1, 0)], ["r", ">", Vector2(1, 0)], ["d", "v", Vector2(0, 1)]]:
		var b := Button.new()
		b.name = d[0]
		b.text = d[1]
		b.focus_mode = FOCUS_NONE
		b.modulate = Color(1, 1, 1, 0.55)
		b.connect("button_down", self, "_pad_set", [d[2], true])
		b.connect("button_up", self, "_pad_set", [d[2], false])
		pad.add_child(b)
	var out := Button.new()
	out.name = "Leave"
	out.text = "Leave"
	out.focus_mode = FOCUS_NONE
	out.modulate = Color(1, 1, 1, 0.55)
	out.rect_position = Vector2(0, -44)
	out.connect("pressed", self, "_leave")
	pad.add_child(out)
	_hint.text = "Hold the arrows to walk"

func _pad_set(d: Vector2, on: bool):
	if on:
		_pad = d
	elif _pad == d:
		_pad = Vector2.ZERO

# --- remembered --------------------------------------------------------------------

func _load():
	var f := File.new()
	if f.file_exists(SAVE) and f.open(SAVE, File.READ) == OK:
		var p = JSON.parse(f.get_as_text())
		f.close()
		if p.error == OK and p.result is Dictionary and p.result.get("solved") is Array:
			for i in range(min(4, p.result.solved.size())):
				solved[i] = bool(p.result.solved[i])

func _save():
	var f := File.new()
	if f.open(SAVE, File.WRITE) == OK:
		f.store_string(JSON.print({"solved": solved}))
		f.close()

# --- the lines ---------------------------------------------------------------------

func say(lines):
	if lines is String:
		lines = [lines]
	for l in lines:
		_lines.append(String(l))

func _say_now(lines):
	_lines.clear()
	_line = ""
	say(lines)

func _dialog_tick(delta: float):
	if _line == "":
		if _lines.empty():
			return
		_line = _lines.pop_front()
		_typed = 0.0
		_line_hold = 0.0
	if _typed < _line.length():
		_typed = min(_typed + delta * 22.0, float(_line.length()))
		_dlg.text = _line.substr(0, int(_typed))
	else:
		_line_hold += delta
		if _line_hold > (1.6 + _line.length() * 0.045 if not _lines.empty() else 4.5):
			_line = ""
			if _lines.empty():
				_dlg.text = ""

const ENTER := {
	HUB: ["you typed the word.", "nobody types the word.", "four doors. the game forgot what it put behind them."],
	R_GRID: ["nine plates. you know this shape.", "it will show you an order. it only shows the patient.", "touch the terminal when you want to see it again."],
	R_BLOCKS: ["these are the notes you missed.", "they have been waiting to be put somewhere.", "the pale plate in the corner undoes what you did."],
	R_SPECTRUM: ["six of them. asleep.", "the mark on the wall remembers the order. sky first. leaf last."],
	R_DARK: ["there is a floor. most of it is not there.", "the light is only as big as you are."],
}
const SOLVED_LINE := ["the grid goes quiet. it is satisfied.", "every note has a place now. even those.", "awake. all six. they are looking at you.", "you crossed it. something else did not."]

# --- every frame -------------------------------------------------------------------

func _process(delta: float):
	time += delta
	_phase_t += delta
	var bm: ShaderMaterial = _burst.material
	bm.set_shader_param("t", time)
	match _phase:
		"in":
			_burst_r = 2.9 * pow(clamp(_phase_t / 1.5, 0.0, 1.0), 2.2)
			if _phase_t >= 1.5:
				_set_phase("hold")
				get_node("Back").visible = true
				_view.visible = true
				_dlg_band.visible = true
				_hint.visible = true
				if has_node("Pad"):
					get_node("Pad").visible = true
		"hold":
			_burst_r = 2.9
			if _phase_t >= 0.45:
				_set_phase("out")
		"out":
			_burst_r = 2.9 * pow(1.0 - clamp(_phase_t / 1.9, 0.0, 1.0), 1.8)
			if _phase_t >= 1.9:
				_burst_r = 0.0
				_set_phase("play")
				_enter_lines()
		"end_in":
			_burst_r = 2.9 * pow(clamp(_phase_t / 1.6, 0.0, 1.0), 2.0)
			if _phase_t >= 1.6:
				_set_phase("end_wait")
				_answer_wait = 0.0
				var lm = get_node_or_null("/root/LobbyManager")
				if lm != null and lm.has_method("_ensure_connected_then_send"):
					lm._ensure_connected_then_send({"type": "ascend_complete", "client_id": Rhythia.cid})
		"end_wait":
			_burst_r = 2.9
			_answer_wait += delta
			if _answer_wait > 8.0:
				# (no answer: an older server, or no connection)
				_back_from_end(["nothing answered.", "it is kept. come back and stand here again."])
		"end_out":
			_burst_r = 2.9 * pow(1.0 - clamp(_phase_t / 1.6, 0.0, 1.0), 1.8)
			if _phase_t >= 1.6:
				_burst_r = 0.0
				if _closing:
					_close()
				else:
					_set_phase("play")
	bm.set_shader_param("r", _burst_r)
	if _hint.visible and time > 9.0:
		_hint.modulate.a = max(0.0, _hint.modulate.a - delta * 0.6)
	_dialog_tick(delta)
	# (the dark band is only there while something is being said)
	_dlg_band.modulate.a = clamp(_dlg_band.modulate.a + (delta * 3.0 if _dlg.text != "" else -delta * 1.5), 0.0, 1.0)
	if _phase == "play":
		_play_tick(delta)
	flash = max(0.0, flash - delta * 2.5)
	_world.update()

func _set_phase(p: String):
	_phase = p
	_phase_t = 0.0

func _enter_lines():
	_say_now(ENTER[room] if not (room != HUB and solved[room - 1]) else ["this one is finished. it has nothing left to say."])
	if room == HUB and solved == [true, true, true, true]:
		_say_now(["all four are quiet.", "the middle of the hall is awake. stand on it."])

func _input_dir() -> Vector2:
	var d := _pad
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): d.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): d.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): d.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): d.y += 1
	return Vector2(sign(d.x), sign(d.y))

# the figure is a box 8 wide and 6 high around its feet
func _hits(p: Vector2) -> bool:
	for off in [Vector2(-4, -5), Vector2(3, -5), Vector2(-4, 0), Vector2(3, 0)]:
		var q: Vector2 = p + off
		if solid(int(floor(q.x / T)), int(floor(q.y / T))):
			return true
	return false

func _play_tick(delta: float):
	frozen = max(0.0, frozen - delta)
	bump_wait = max(0.0, bump_wait - delta)
	plate_lit_t = max(0.0, plate_lit_t - delta)
	if seq_show >= 0:
		# the order being shown, one plate at a time
		seq_t += delta
		if seq_t > 0.62:
			seq_t = 0.0
			seq_show += 1
			if seq_show >= seq.size():
				seq_show = -1
				say(["now you."])
	var d := _input_dir() if frozen <= 0.0 else Vector2.ZERO
	moving = d != Vector2.ZERO
	if d.x != 0:
		facing = int(d.x)
	if moving:
		walk_t += delta
		var step: Vector2 = d.normalized() * SPEED * delta
		var blocked := Vector2.ZERO
		if step.x != 0:
			if _hits(pos + Vector2(step.x, 0)):
				blocked.x = sign(step.x)
			else:
				pos.x += step.x
		if step.y != 0:
			if _hits(pos + Vector2(0, step.y)):
				blocked.y = sign(step.y)
			else:
				pos.y += step.y
		_bumped(blocked, delta)
	else:
		push_t = 0.0
	var here := Vector2(floor(pos.x / T), floor((pos.y - 2) / T))
	_stepped(here, delta)

# walking into something
func _bumped(dir: Vector2, delta: float):
	if dir == Vector2.ZERO or (dir.x != 0 and dir.y != 0):
		push_t = 0.0
		return
	var feet := Vector2(floor(pos.x / T), floor((pos.y - 2) / T))
	var at: Vector2 = feet + dir
	if tile_at(int(at.x), int(at.y)) == "T" and room == R_GRID and bump_wait <= 0.0:
		bump_wait = 1.0
		_show_sequence()
		return
	var ci := _crystal_on(at)
	if ci >= 0 and bump_wait <= 0.0:
		bump_wait = 0.5
		_touch_crystal(ci)
		return
	var bi := _block_on(at)
	if bi >= 0:
		# (leaning on it for a moment, lined up with it, moves it one tile)
		if dir != push_dir:
			push_dir = dir
			push_t = 0.0
		push_t += delta
		var lined: bool = abs((pos.x if dir.y != 0 else pos.y - 3) - ((at.x if dir.y != 0 else at.y) * T + T / 2.0)) < 6.0
		if push_t > 0.16 and lined:
			push_t = 0.0
			var to: Vector2 = at + dir
			if not solid(int(to.x), int(to.y)) and tile_at(int(to.x), int(to.y)) == ".":
				blocks[bi] = to
				_check_blocks()

func _goto(r: int, tile: Vector2):
	room = r
	pos = Vector2((tile.x + 0.5) * T, (tile.y + 0.8) * T)
	frozen = 0.25
	seq_show = -1
	seq_at = 0
	last_plate = -1
	woken = 0 if not solved[R_SPECTRUM - 1] else 6
	if r == R_BLOCKS and not solved[R_BLOCKS - 1]:
		_reset_blocks()
	if r == R_GRID and not solved[R_GRID - 1]:
		_new_sequence()
	_enter_lines()

# standing on something
func _stepped(here: Vector2, _delta: float):
	var ch := tile_at(int(here.x), int(here.y))
	if room == HUB:
		match ch:
			"N": _goto(R_GRID, Vector2(9, 9))
			"E": _goto(R_BLOCKS, Vector2(1, 5))
			"W": _goto(R_SPECTRUM, Vector2(18, 5))
			"S": _goto(R_DARK, Vector2(9, 1))
			"A":
				if solved == [true, true, true, true] and _phase == "play":
					_say_now(["ascend."])
					_set_phase("end_in")
		return
	if ch == "X":
		var back := {R_GRID: Vector2(9, 1), R_BLOCKS: Vector2(18, 5), R_SPECTRUM: Vector2(1, 5), R_DARK: Vector2(9, 9)}
		_goto(HUB, back[room])
		return
	match room:
		R_GRID:
			var p := -1
			var ix: int = PLATE_XS.find(int(here.x))
			var iy: int = PLATE_YS.find(int(here.y))
			if ix >= 0 and iy >= 0:
				p = iy * 3 + ix
			if p != last_plate:
				last_plate = p
				if p >= 0 and seq_show < 0 and not solved[0] and not seq.empty():
					_plate(p)
		R_BLOCKS:
			if ch == "R" and not solved[1] and blocks != BLOCKS_START:
				_reset_blocks()
				_say_now(["undone."])
		R_DARK:
			if solved[3]:
				return
			if here == DARK_GOAL:
				_solve(R_DARK)
			elif not dark_safe.has(here) and ch == "." and frozen <= 0.0:
				flash = 1.0
				flash_col = Color(0.6, 0.1, 0.2)
				frozen = 0.7
				pos = Vector2(9.5 * T, 1.8 * T)
				_say_now([["the dark keeps what steps into it.", "not there.", "again.", "it was never there."][randi() % 4]])

func _solve(r: int):
	if solved[r - 1]:
		return
	solved[r - 1] = true
	_save()
	flash = 1.0
	flash_col = Color(1, 0.95, 0.7)
	_say_now([SOLVED_LINE[r - 1], "go back."])
	Rhythia.trail("a room is quiet (%d)" % r)

# --- the grid ----------------------------------------------------------------------

func _new_sequence():
	seq = []
	var last := -1
	for _i in range(5):
		var p := randi() % 9
		while p == last:
			p = randi() % 9
		seq.append(p)
		last = p
	seq_at = 0
	seq_show = -1

func _show_sequence():
	if solved[0]:
		return
	if seq.empty():
		_new_sequence()
	seq_show = 0
	seq_t = -0.6
	seq_at = 0
	_say_now(["watch."])

func _plate(p: int):
	plate_lit = p
	plate_lit_t = 0.35
	if p == seq[seq_at]:
		seq_at += 1
		if seq_at >= seq.size():
			_solve(R_GRID)
	else:
		seq_at = 0
		flash = 1.0
		flash_col = Color(0.6, 0.1, 0.2)
		_say_now([["no.", "that is not the order.", "it noticed."][randi() % 3], "from the beginning."])

# --- the blocks --------------------------------------------------------------------

func _reset_blocks():
	blocks = BLOCKS_START.duplicate()

func _check_blocks():
	for s in SOCKETS:
		if not blocks.has(s):
			return
	_solve(R_BLOCKS)

# --- the spectrum ------------------------------------------------------------------

func _touch_crystal(i: int):
	if solved[2]:
		return
	var colour: int = CRYSTALS[i][1]
	if colour < woken:
		return # (awake already)
	if colour == woken:
		woken += 1
		if woken >= 6:
			_solve(R_SPECTRUM)
		else:
			_say_now([["it opens one eye.", "yes.", "that one was waiting.", "the next is colder.", "almost."][min(woken - 1, 4)]])
	else:
		woken = 0
		flash = 1.0
		flash_col = Color(0.6, 0.1, 0.2)
		_say_now(["wrong. they all close again.", "sky first. leaf last."])

# --- the end -----------------------------------------------------------------------

func _on_answer(ok: bool, _text: String, cards: Array):
	if _phase != "end_wait":
		return
	if ok:
		var got := false
		for c in cards:
			if c is Dictionary and String(c.get("id", "")) == "ascension":
				got = true
		if got:
			# (the light shrinks back onto the menu, not onto the hall)
			_closing = true
			for n in ["Back", "View", "DialogBand", "Dialog", "Hint", "Pad"]:
				if has_node(n):
					get_node(n).visible = false
			Rhythia.trail("ascended")
			_set_phase("end_out")
			return
	_back_from_end(["not yet.", "stay a little longer. then stand here again."])

func _back_from_end(lines: Array):
	pos = Vector2(9.5 * T, 7.5 * T)
	_say_now(lines)
	_set_phase("end_out")

func _leave():
	if _phase == "play":
		_close()

func _close():
	var layer = get_parent()
	remove_from_group("ascend")
	if layer is CanvasLayer:
		layer.queue_free()
	else:
		queue_free()

# keys stay here: the menu behind (its search box takes any letter) gets none
func _input(ev):
	if ev is InputEventKey:
		if ev.pressed and not ev.echo and ev.scancode == KEY_ESCAPE and _phase == "play":
			if time - _esc_at < 3.0:
				_close()
			else:
				_esc_at = time
				_say_now(["leave? press esc again. what you finished stays finished."])
		get_tree().set_input_as_handled()
	elif ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
		pass

# --- drawing -----------------------------------------------------------------------

class PixelWorld extends Node2D:
	var host

	func _px(x: float, y: float, w: float, h: float, c: Color):
		draw_rect(Rect2(x, y, w, h), c)

	# a hollow square, the shape of a note and of the logo
	func _ring(x: float, y: float, s: float, w: float, c: Color):
		_px(x, y, s, w, c)
		_px(x, y + s - w, s, w, c)
		_px(x, y + w, w, s - w * 2, c)
		_px(x + s - w, y + w, w, s - w * 2, c)

	func _draw():
		var h = host
		var room: int = h.room
		var t: float = h.time
		_px(0, 0, h.W, h.H, Color(0.03, 0.02, 0.05))
		for r in range(h.ROWS):
			for c in range(h.COLS):
				_tile(c, r, h.maps[room][r][c], room, t)
		match room:
			h.HUB: _hub(t)
			h.R_GRID: _grid_room(t)
			h.R_BLOCKS: _blocks_room(t)
			h.R_SPECTRUM: _spectrum_room(t)
		_figure(t)
		if room == h.R_DARK and not h.solved[3]:
			_darkness()
		if h.flash > 0.0:
			_px(0, 0, h.W, h.H, Color(h.flash_col.r, h.flash_col.g, h.flash_col.b, h.flash * 0.45))

	func _tile(c: int, r: int, ch: String, room: int, t: float):
		var h = host
		var x: float = c * h.T
		var y: float = r * h.T
		if ch == "#":
			_px(x, y, 16, 16, h.C_WALL)
			_px(x, y, 16, 2, h.C_WALL_HI)
			_px(x, y + 14, 16, 2, h.C_WALL_LO)
			_px(x + 15, y, 1, 16, h.C_WALL_LO)
			# (little note squares set into the wall)
			if (c + r) % 2 == 0:
				_ring(x + 5, y + 5, 6, 1, h.C_WALL_HI)
			return
		var floor_c: Color = h.C_FLOOR
		if room == h.R_DARK and not h.solved[3] and ch == "." and not h.dark_safe.has(Vector2(c, r)):
			# the floor that isn't there
			_px(x, y, 16, 16, Color(0.02, 0.012, 0.035))
			if (c * 7 + r * 13) % 5 == 0:
				_px(x + 6, y + 9, 2, 1, Color(0.09, 0.06, 0.13))
			return
		_px(x, y, 16, 16, floor_c)
		_px(x, y, 16, 1, h.C_FLOOR_LINE)
		_px(x, y, 1, 16, h.C_FLOOR_LINE)
		if (c * 5 + r * 3) % 11 == 0:
			_px(x + 7, y + 8, 2, 2, h.C_FLOOR_LINE)
		match ch:
			"N", "E", "S", "W", "X":
				var which: int = {"N": 0, "E": 1, "W": 2, "S": 3}.get(ch, -1)
				var done: bool = which >= 0 and h.solved[which]
				var glow: float = 0.55 + 0.25 * sin(t * 2.4 + c)
				var col: Color = h.C_GOLD if done else (h.C_LILAC if ch != "X" else h.C_PINK)
				_px(x, y, 16, 16, Color(col.r, col.g, col.b, 0.16 + 0.1 * glow))
				_ring(x + 2, y + 2, 12, 2, Color(col.r, col.g, col.b, glow))
			"T":
				_px(x + 3, y + 9, 10, 6, h.C_WALL_LO)
				_px(x + 2, y + 1, 12, 9, h.C_WALL)
				_px(x + 3, y + 2, 10, 7, Color(0.1, 0.5, 0.6) if fmod(t, 1.2) < 0.9 else Color(0.2, 0.75, 0.85))
				_ring(x + 6, y + 3, 4, 1, Color(0.8, 1, 1))
			"R":
				_px(x + 2, y + 2, 12, 12, Color(0.75, 0.72, 0.85, 0.2))
				_ring(x + 2, y + 2, 12, 1, Color(0.85, 0.82, 0.95, 0.7))
			"A":
				var all: bool = h.solved == [true, true, true, true]
				var a: float = (0.6 + 0.4 * sin(t * 3.0)) if all else 0.25
				_px(x - 2, y - 2, 20, 20, Color(h.C_GOLD.r, h.C_GOLD.g, h.C_GOLD.b, 0.18 * a))
				_ring(x, y, 16, 2, Color(h.C_GOLD.r, h.C_GOLD.g, h.C_GOLD.b, a))
				_ring(x + 5, y + 5, 6, 2, Color(1, 1, 0.9, a))

	func _hub(t: float):
		var h = host
		# four marks round the altar, one per room
		var marks = [Vector2(9, 4), Vector2(10, 5), Vector2(8, 5), Vector2(9, 6)]
		for i in range(4):
			var m: Vector2 = marks[i] * h.T
			var on: bool = h.solved[i]
			var col: Color = h.C_GOLD if on else Color(0.3, 0.25, 0.4)
			_ring(m.x + 5, m.y + 5, 6, 1 if not on else 2, Color(col.r, col.g, col.b, 0.9 if on else 0.6))

	func _grid_room(t: float):
		var h = host
		for iy in range(3):
			for ix in range(3):
				var p: int = iy * 3 + ix
				var x: float = h.PLATE_XS[ix] * h.T
				var y: float = h.PLATE_YS[iy] * h.T
				var col: Color = h.SPECTRUM[(p * 2 + 1) % 6]
				var lit: bool = (h.seq_show >= 0 and h.seq_show < h.seq.size() and h.seq[h.seq_show] == p and h.seq_t > 0.0 and h.seq_t < 0.45) or (h.plate_lit == p and h.plate_lit_t > 0.0) or h.solved[0]
				_px(x + 1, y + 1, 14, 14, Color(col.r, col.g, col.b, 0.85 if lit else 0.1))
				_ring(x + 1, y + 1, 14, 1, Color(col.r, col.g, col.b, 1.0 if lit else 0.5))
		# how far you have got
		for i in range(h.seq.size()):
			_px(8 * h.T + i * 8, 9 * h.T + 4, 5, 3, h.C_PINK if (i < h.seq_at or h.solved[0]) else Color(0.3, 0.25, 0.4))

	func _blocks_room(t: float):
		var h = host
		for s in h.SOCKETS:
			var x: float = s.x * h.T
			var y: float = s.y * h.T
			for k in range(0, 12, 4):
				_px(x + 2 + k, y + 2, 2, 1, h.C_PINK)
				_px(x + 2 + k, y + 13, 2, 1, h.C_PINK)
				_px(x + 2, y + 2 + k, 1, 2, h.C_PINK)
				_px(x + 13, y + 2 + k, 1, 2, h.C_PINK)
		for i in range(h.blocks.size()):
			var b: Vector2 = h.blocks[i]
			var x: float = b.x * h.T
			var y: float = b.y * h.T
			var col: Color = h.SPECTRUM[[0, 3, 5][i]]
			var home: bool = h.SOCKETS.has(b)
			_px(x + 2, y + 2, 12, 12, Color(col.r, col.g, col.b, 0.35 if home else 0.12))
			_ring(x + 2, y + 2, 12, 3, col)
			if home:
				_px(x + 7, y + 7, 2, 2, Color(1, 1, 1))

	func _spectrum_room(t: float):
		var h = host
		# the mark on the wall: the logo's ring, sky at the top right round to leaf
		var cx = 9 * h.T + 8
		var order = [Vector2(1, -1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1)]
		for i in range(8):
			var col: Color = h.SPECTRUM[int(min(5, i * 6 / 8))]
			_px(cx - 2 + order[i].x * 5, 8 - 2 + order[i].y * 5, 5, 5, col)
		for i in range(h.CRYSTALS.size()):
			var cr = h.CRYSTALS[i]
			var x: float = cr[0].x * h.T
			var y: float = cr[0].y * h.T
			var col: Color = h.SPECTRUM[cr[1]]
			var awake: bool = cr[1] < h.woken or h.solved[2]
			var bob: float = round(sin(t * 2.0 + i) * 1.0) if awake else 0.0
			_px(x + 4, y + 13, 8, 2, Color(0, 0, 0, 0.5))
			var a: float = 1.0 if awake else 0.38
			_px(x + 6, y + 2 + bob, 4, 10, Color(col.r, col.g, col.b, a))
			_px(x + 4, y + 5 + bob, 8, 4, Color(col.r, col.g, col.b, a))
			_px(x + 7, y + 4 + bob, 1, 3, Color(1, 1, 1, 0.9 if awake else 0.25))
			if awake:
				_ring(x + 1, y + bob, 14, 1, Color(col.r, col.g, col.b, 0.35 + 0.25 * sin(t * 4.0 + i)))

	# the pixel figure: a hollow square for a head (a note), a small body, two feet
	func _figure(t: float):
		var h = host
		var x: float = round(h.pos.x)
		var y: float = round(h.pos.y)
		var step: int = int(h.walk_t * 8.0) % 2 if h.moving else 0
		var bob: float = 0.0 if not h.moving else float(step)
		_px(x - 4, y, 8, 2, Color(0, 0, 0, 0.45))
		# feet
		_px(x - 3, y - 2 - (1 if step == 1 else 0), 2, 2, h.C_LILAC)
		_px(x + 1, y - 2 - (0 if step == 1 else (1 if h.moving else 0)), 2, 2, h.C_LILAC)
		# body
		_px(x - 3, y - 7 + bob, 6, 5, Color("6e5a8f"))
		_px(x - 3, y - 7 + bob, 6, 1, Color("8a73b0"))
		# head
		var hy: float = y - 15 + bob
		_px(x - 4, hy, 8, 8, Color("1d1628"))
		_ring(x - 4, hy, 8, 2, h.C_PINK)
		_px(x - 4, hy, 8, 1, Color("ffe3fb"))
		var ex: float = x - 1 + h.facing
		_px(ex - 1, hy + 3, 1, 2, Color(1, 1, 1))
		_px(ex + 1, hy + 3, 1, 2, Color(1, 1, 1))

	# only what is near you is there to see
	func _darkness():
		var h = host
		var p: Vector2 = h.pos + Vector2(0, -6)
		var rad: float = 30.0 + sin(h.time * 3.0) * 1.5
		for ty in range(0, h.H, 4):
			for tx in range(0, h.W, 4):
				var d: float = Vector2(tx + 2, ty + 2).distance_to(p)
				if d > rad:
					_px(tx, ty, 4, 4, Color(0, 0, 0, 1.0 if d > rad + 10.0 else 0.72))
		# the way out and the end glow faintly through it
		var g: Vector2 = h.DARK_GOAL * h.T
		_ring(g.x + 4, g.y + 4, 8, 2, Color(h.C_GOLD.r, h.C_GOLD.g, h.C_GOLD.b, 0.35 + 0.3 * sin(h.time * 3.0)))
