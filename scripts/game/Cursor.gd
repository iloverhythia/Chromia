extends Spatial

var rpos: Vector2 = Vector2(transform.origin.x, -transform.origin.y)

enum {
	C_MOUSE = 0
	C_JOYSTICK = 1
}

var sh: Vector2 = Vector2(-0.5, -0.5)
var edgec: float = 0.13125
var edger: float = 0.13125 - max(0, Rhythia.get("edge_drift"))
var _face_spin_deg: float = 0.0
var _face_accum: Vector2 = Vector2.ZERO
var face: Vector2 # (Legacy Mouse Movement: the last movement, as the first version kept it)
var _legacy: bool = bool(Rhythia.get("legacy_mouse")) and not Rhythia.device("mobile")

var move_mode: int = C_MOUSE
var can_switch_move_modes: bool = true

func drift_cursor(rx, ry, cx, cy):
	if Rhythia.enable_drift_cursor:
		if cx != rx or cy != ry:
			$Mesh2.visible = true
			$Mesh2.transform.origin.x = rx - cx
			$Mesh2.transform.origin.y = -(ry - cy)
		else: $Mesh2.visible = false

func move_cursor(mdel: Vector2):
	var rx = rpos.x
	var ry = rpos.y
	rx += mdel.x
	ry += mdel.y

	if Rhythia.hr_on():
		var hard_cock = edger - Rhythia.hr_reach()
		rx = clamp(rx, (0 + sh.x + hard_cock), (3 + sh.x - hard_cock))
		ry = clamp(ry, (0 + sh.y + hard_cock), (3 + sh.y - hard_cock))
	else:
		rx = clamp(rx, (0 + sh.x + edger), (3 + sh.x - edger))
		ry = clamp(ry, (0 + sh.y + edger), (3 + sh.y - edger))

	rpos.x = rx
	rpos.y = ry

	var cx = rx
	var cy = ry

	if Rhythia.hr_on():
		var hard_cock = edgec - Rhythia.hr_reach()


		cx = clamp(cx, (0 + sh.x + hard_cock), (3 + sh.x - hard_cock))
		cy = clamp(cy, (0 + sh.y + hard_cock), (3 + sh.y - hard_cock))
	else:
		cx = clamp(cx, (0 + sh.x + edgec), (3 + sh.x - edgec))
		cy = clamp(cy, (0 + sh.y + edgec), (3 + sh.y - edgec))

	transform.origin.x = cx
	transform.origin.y = -cy

	drift_cursor(rx, ry, cx, cy)

func move_cursor_abs(mdel: Vector2):
	var rx = mdel.x
	var ry = mdel.y

	# (a replay's positions were already kept in by the player's own edge drift
	# when they played: clamped again with the viewer's, a player with edge
	# drift had their cursor squashed onto the grid's edge)
	if Rhythia.replaying:
		pass
	elif Rhythia.hr_on():
		var hard_cock = edger - Rhythia.hr_reach()
		rx = clamp(rx, (0 + sh.x + hard_cock), (3 + sh.x - hard_cock))
		ry = clamp(ry, (0 + sh.y + hard_cock), (3 + sh.y - hard_cock))
	else:
		rx = clamp(rx, (0 + sh.x + edger), (3 + sh.x - edger))
		ry = clamp(ry, (0 + sh.y + edger), (3 + sh.y - edger))

	rpos.x = rx
	rpos.y = ry

	var cx = rx
	var cy = ry

	if Rhythia.hr_on():
		var hard_cock = edgec - Rhythia.hr_reach()
		cx = clamp(cx, (0 + sh.x + hard_cock), (3 + sh.x - hard_cock))
		cy = clamp(cy, (0 + sh.y + hard_cock), (3 + sh.y - hard_cock))
	else:
		cx = clamp(cx, (0 + sh.x + edgec), (3 + sh.x - edgec))
		cy = clamp(cy, (0 + sh.y + edgec), (3 + sh.y - edgec))

	transform.origin.x = cx
	transform.origin.y = -cy

	drift_cursor(rx, ry, cx, cy)


onready var absCamera = get_node("../../../AbsCamera")

# Touch prediction (phones, Settings > No Touch Delay; TouchPredictor.gd):
# what's on screen is behind your finger, and touch samples don't line up with
# drawn frames, so every drawn frame the cursor is put where the finger has got
# to since the last sample, plus the chosen lead. When the finger stops it
# eases onto the real spot. Works for the absolute cursor (the finger's place)
# and the relative one (the finger's movement).
var _pred := false
var _tp = null # TouchPredictor
var _rel_px := Vector2.ZERO # relative mode: the finger's movements added up, px
var _rel_true := Vector2.ZERO # relative mode: the cursor without the lead
var _rel_shown := Vector2.ZERO # ...and where it was put with it
var _rel_has := false

func _predict_input(p: Vector2):
	_tp.add(p, OS.get_ticks_usec())

func _predict_offset() -> Vector2:
	if not _pred:
		return Vector2.ZERO
	var cap: float = get_viewport().get_visible_rect().size.y * 0.04 # (the lead is never far off)
	return _tp.offset(OS.get_ticks_usec(), Rhythia.mobile_predict_ms / 1000.0, cap)

func _predicted_mouse() -> Vector2:
	return get_viewport().get_mouse_position() + _predict_offset()

# relative mode, one finger movement: the cursor moves from where it really is
# (not from where the lead drew it)
func _move_rel_predicted(mdel: Vector2, rel_px: Vector2):
	if _rel_has and rpos == _rel_shown:
		rpos = _rel_true
	move_cursor(mdel)
	_rel_true = rpos
	_rel_shown = rpos
	_rel_has = true
	_rel_px += rel_px
	_predict_input(_rel_px)

func get_absolute_position():
	absCamera.fov = Rhythia.get("fov")
	var pos = absCamera.project_position(_predicted_mouse(), 3.75) * Rhythia.absolute_scale
	return Vector2(pos.x, -pos.y) + Vector2(1, 1)

func _input(event: InputEvent):
	if not Rhythia.replaying and not Rhythia.vr:
		# A controller only takes over when it's allowed (Settings > Disable
		# Controller off) and a stick is really pushed: a plugged-in pad's
		# resting drift or a trigger used to switch to it at the song start,
		# which put the cursor in the middle and kept the mouse from moving it.
		if Rhythia.ignore_controller_detection:
			move_mode = C_MOUSE
		elif can_switch_move_modes:
			if event is InputEventJoypadMotion and event.axis <= JOY_AXIS_3 and abs(event.axis_value) > 0.5:
				move_mode = C_JOYSTICK
			elif event is InputEventMouseMotion:
				move_mode = C_MOUSE
		elif move_mode == C_JOYSTICK and event is InputEventMouseMotion and event.relative.length() > 2.0:
			move_mode = C_MOUSE # (the mouse moved: it's the mouse after all)

		if move_mode == C_JOYSTICK:
			var v_strength = (Input.get_action_strength("joy_up") + (Input.get_action_strength("joy_down") * -1)) * -1
			var h_strength = (Input.get_action_strength("joy_right") + (Input.get_action_strength("joy_left") * -1)) * 1
			var relative = Vector2(h_strength * 1.5, v_strength * 1.5)
			var off = Vector2(1, 1)
			if Rhythia.invert_mouse:
				move_cursor_abs((relative + off) * -1)
			else:
				move_cursor_abs(relative + off)
		elif not Rhythia.spin_now() and move_mode == C_MOUSE and _legacy:
			# Experimental Legacy Mouse Movement: the first version's mouse code,
			# line for line (its render scale was always 1)
			visible = true
			if (event is InputEventMouseMotion):
				face = event.relative
				if Rhythia.invert_mouse:
					if Rhythia.absolute_mode:
						move_cursor_abs(get_absolute_position() * -1)
					else:
						move_cursor((event.relative * 0.018 * Rhythia.sensitivity) * -1)
				else:
					if Rhythia.absolute_mode:
						move_cursor_abs(get_absolute_position())
					else:
						move_cursor(event.relative * 0.018 * Rhythia.sensitivity)
		elif not Rhythia.spin_now() and move_mode == C_MOUSE:
			visible = true
			if (event is InputEventMouseMotion):
				_face_accum += event.relative
				if _pred and Rhythia.absolute_mode:
					_predict_input(event.position)
				if _pred and not Rhythia.absolute_mode:
					_move_rel_predicted(event.relative * 0.018 * Rhythia.sensitivity * (-1 if Rhythia.invert_mouse else 1), event.relative)
				elif Rhythia.invert_mouse:
					if Rhythia.absolute_mode:
						move_cursor_abs(get_absolute_position() * -1)
					else:
						move_cursor((event.relative * 0.018 * Rhythia.sensitivity) * -1)
				else:
					if Rhythia.absolute_mode:
						move_cursor_abs(get_absolute_position())
					else:
						move_cursor(event.relative * 0.018 * Rhythia.sensitivity)

		# (touches are shown by scripts/ui/TouchIndicator.gd now)

var frame: int = Engine.get_frames_drawn()
var trail_cache: Array = []

var prev_pos
var prev_rot
var trail_started = false
var _trail_gap := 0.0 # (seconds since the trail last got new pieces)
var _trail_before = null # (the point before the last one: the trail's curve)

var ct: float = 0
var segt: float = 0
var segl: float = 0.01

var total_trail_segments = 0
var _trail_mm = null # the smart trail (TrailMulti.gd)

onready var trail_base = get_node("../../CursorTrail")

const MAX_CACHED_TRAIL_SEGMENTS = 200
func cache_trail(part: Spatial):
	if trail_cache.has(part):
		return
	if trail_cache.size() >= MAX_CACHED_TRAIL_SEGMENTS:
		total_trail_segments -= 1
		part.queue_free()
		return
	trail_cache.append(part)

func recolor(col: Color):
	$Mesh.get("material/0").albedo_color = Color(col.r, col.g, col.b, col.a)

var mt = 0
func check_debug_mouse_toggle():
	if Input.is_action_just_pressed("debug_enable_mouse"):
		mt = mt + 1
		if mt == 1:
			Input.set_custom_mouse_cursor(null)
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if mt == 2:
			Input.set_custom_mouse_cursor(load("res://assets/images/ui/blank.png"))
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
			if Rhythia.absolute_mode:
				Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			mt = 0

func _process(delta):
	# touch prediction: re-place the cursor every drawn frame so it keeps gliding
	# between touch samples and settles on the real spot when your finger stops
	# (get_absolute_position() leads while moving and snaps back once it pauses).
	if _pred and not Rhythia.replaying and move_mode == C_MOUSE and not Rhythia.spin_now():
		if Rhythia.absolute_mode:
			move_cursor_abs(get_absolute_position() * (-1 if Rhythia.invert_mouse else 1))
		elif _rel_has and rpos == _rel_shown:
			var off: Vector2 = _predict_offset() * 0.018 * Rhythia.sensitivity * (-1 if Rhythia.invert_mouse else 1)
			move_cursor_abs(_rel_true + off)
			_rel_shown = rpos
	check_debug_mouse_toggle()
	frame = Engine.get_frames_drawn()
	if Rhythia.cursor_spin != 0 and not Rhythia.cursor_face_velocity:
		$Mesh.rotate_z(deg2rad(-delta * Rhythia.cursor_spin))
		$Mesh2.rotate_z(deg2rad(-delta * Rhythia.cursor_spin))
	if Rhythia.cursor_face_velocity and _legacy:
		# (the first version's turn towards where the cursor last moved)
		$Mesh.rotation_degrees.x += ((rad2deg(face.angle()) + 180) - $Mesh.rotation_degrees.x) * 0.025
	elif Rhythia.cursor_face_velocity:
		var frame_face = _face_accum
		_face_accum = Vector2.ZERO
		if frame_face.length() > 0.05:
			var turn_speed = clamp(frame_face.length() * 0.012, 0.05, 1.0)
			var target_deg = rad2deg(Vector2(frame_face.x, -frame_face.y).angle()) - 90
			var delta_deg = wrapf(target_deg - _face_spin_deg, -180, 180) * turn_speed
			_face_spin_deg = wrapf(_face_spin_deg + delta_deg, -180, 180)
			$Mesh.rotate_z(deg2rad(delta_deg))
	if Rhythia.cursor_color_type == Globals.CURSOR_RAINBOW:
		$Mesh.get("material/0").albedo_color = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.65, 1)
	if Input.is_key_pressed(KEY_C):
		ct = fmod(ct + delta, 3)
		global_transform.origin = Vector3(ct - 1.5, sin(ct * 4), global_transform.origin.z)

	if Rhythia.replaying:
		var p
		if Rhythia.replay.sv == 1 or Rhythia.replay.autoplayer: p = Rhythia.replay.get_cursor_position(get_parent().ms)
		else: p = Rhythia.replay.get_cursor_position(get_parent().rms)
		var before: Vector2 = rpos
		if Rhythia.replay.sv < 3:
			transform.origin.x = p.x
			transform.origin.y = p.y
		else:
			move_cursor_abs(Vector2(p.x, p.y))
			# Face movement: the replay's own movement turns the cursor (there's no
			# mouse input to do it), as the mouse's would (grid units / 0.018 at
			# sensitivity 1, as move_cursor turns them into the cursor's movement)
			if Rhythia.cursor_face_velocity:
				var moved: Vector2 = rpos - before
				if moved.length() < 1.0: # (not a jump: a skip or a seek)
					_face_accum += moved / 0.018

	if Rhythia.show_cursor and Rhythia.cursor_trail and Rhythia.smart_trail and trail_started:
		var start_p = global_transform.origin
		var end_p = prev_pos
		var start_r = $Mesh.rotation_degrees.x
		var end_r = prev_rot
		var p_diff = (start_p - end_p).length()
		var r_diff = PI * Rhythia.cursor_scale * abs(start_r - end_r) / 360
		var diff = p_diff
		if r_diff > p_diff: diff = r_diff
		# the time this stretch took: on phones the touch moves the cursor less
		# often than frames are drawn (60 touches a second at 120 FPS), so a
		# frame without a move adds its time to the next stretch
		_trail_gap += delta
		if diff <= 0.00001:
			if _trail_gap > 0.1:
				_trail_gap = delta # (standing still: the next move starts afresh)
		else:
			# (a headset or a phone: no more pieces than can be told apart, about
			# eight across the cursor's width. More only overlap, and every piece
			# is drawn over the others, for each eye.)
			var detail: float = float(Rhythia.trail_detail)
			var most: int = 240
			if _light_trail:
				detail = min(detail, 30.0 / max(float(Rhythia.cursor_scale), 0.25))
				most = 96
			var amt = min(ceil(detail * diff), most)
			# (all the pieces are one MultiMesh: TrailMulti.gd)
			if _trail_mm != null and is_instance_valid(_trail_mm):
				var col: Color = $Mesh.get("material/0").albedo_color
				col.a *= Rhythia.trail_opacity
				var rot_now: Vector3 = $Mesh.rotation
				var tt: float = max(0.001, float(Rhythia.trail_time))
				# a curve through the last points, not straight lines with corners
				# (Catmull-Rom: the point before, and the move continuing ahead)
				var p0: Vector3 = _trail_before if _trail_before != null else end_p
				var p3: Vector3 = start_p + (start_p - end_p)
				var curve: bool = _trail_before != null and p_diff > 0.0001
				for i in range(amt):
					var v = float(i) / float(amt)
					var pos: Vector3
					if curve:
						pos = start_p.cubic_interpolate(end_p, p3, p0, v)
					else:
						pos = lerp(start_p, end_p, v)
					# (its age as a part of Trail Time: older towards the last point)
					_trail_mm.add(pos, rot_now, col, clamp(v * _trail_gap / tt, 0.0, 1.0))
			_trail_before = end_p
			_trail_gap = 0.0
			if $L.visible:
				$L.text = "amount this frame: %s\nalive: %s" % [amt, _trail_mm.live() if _trail_mm != null else 0]
		prev_pos = global_transform.origin
		prev_rot = $Mesh.rotation_degrees.x
	if _trail_cl != null and is_instance_valid(_trail_cl) and _trail_cl.is_inside_tree():
		_classic_stamps(delta)
	_tr_prev = _tr_now
	_tr_now = global_transform.origin
	_tr_dt = delta
	_tr_frame = Engine.get_frames_drawn()

# The classic trail on the graphics card: piece k is put down again once every
# Trail Time, each a little after the one before (as CursorTrail.gd's nodes
# did: the same moments, the same places between two frames, left out when
# the cursor hasn't moved since that piece's last place).
var _light_trail: bool = bool(Rhythia.vr) or Rhythia.device("mobile")
var _trail_cl = null
var _cl_n := 0
var _cl_T := 0.0 # time, in Trail Times
var _cl_last := []
func _classic_stamps(delta: float):
	var tt: float = max(0.001, float(Rhythia.trail_time))
	var t0: float = _cl_T
	var t1: float = t0 + delta / tt
	_cl_T = t1
	_trail_cl.begin_frame(delta)
	var here: Vector3 = global_transform.origin
	var before: Vector3 = _tr_now # (where the cursor was a frame ago)
	var jumped: bool = (here - before).length() > 2.5
	var col = null
	var rot: Vector3 = $Mesh.rotation
	var step: float = 1.0 / float(_cl_n - 1)
	for k in range(_cl_n):
		var off: float = k * step
		var c1: float = floor(t1 - off)
		if c1 < 1.0 or c1 <= floor(t0 - off):
			continue
		var late: float = (t1 - off - c1) * tt # (seconds since this piece was due)
		var p: Vector3 = here
		if not jumped and late > 0.0:
			p = here.linear_interpolate(before, clamp(late / max(delta, 0.0005), 0.0, 1.0))
		p -= Vector3(0, 0, 0.001)
		var show: bool = p != _cl_last[k]
		_cl_last[k] = p
		if col == null:
			col = $Mesh.get("material/0").albedo_color
			col.a *= Rhythia.trail_opacity
		_trail_cl.stamp(k, p, rot, col, late, show)

# The classic trail (CursorTrail.gd) puts a piece down every so often. The
# moment a piece is due falls between two drawn frames: this is where the
# cursor was `late` seconds ago, on the line from its last frame's place to
# this frame's, so pieces are spread evenly along the path at any frame rate
# (at 60 FPS they used to bunch up on the frames' own spots).
var _tr_now := Vector3.ZERO
var _tr_prev := Vector3.ZERO
var _tr_dt := 0.016
var _tr_frame := -1
func trail_point(late: float) -> Vector3:
	var now_p: Vector3 = global_transform.origin
	# (asked before this frame's _process here: the last one kept is last frame's)
	var prev_p: Vector3 = _tr_prev if _tr_frame == Engine.get_frames_drawn() else _tr_now
	if late <= 0.0 or (now_p - prev_p).length() > 2.5:
		return now_p # (a jump, like the start of a song: no line across the grid)
	return now_p.linear_interpolate(prev_p, clamp(late / max(_tr_dt, 0.0005), 0.0, 1.0))

func _ready():
	_tr_now = global_transform.origin
	_tr_prev = _tr_now
	if not Rhythia.show_cursor: visible = false
	_pred = Rhythia.device("mobile") and bool(Rhythia.get("mobile_no_delay")) and not Rhythia.replaying and not Rhythia.vr
	if _pred and bool(Rhythia.get("mobile_old_cursor")):
		# Settings > Old Cursor Movement: the prediction as it was (and, as then,
		# only for the absolute cursor)
		_pred = Rhythia.absolute_mode
		if _pred:
			_tp = load("res://scripts/game/TouchPredictorOld.gd").new()
	elif _pred:
		_tp = load("res://scripts/game/TouchPredictor.gd").new()
	if _legacy and not Rhythia.replaying:
		Input.use_accumulated_input = true # (as it was then)

	if not Rhythia.replaying:
		if not Rhythia.absolute_mode:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
			Input.set_custom_mouse_cursor(load("res://assets/images/ui/blank.png"))
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	var mat: SpatialMaterial = $Mesh.get("material/0")
	$Mesh.scale = Vector3(Rhythia.cursor_scale, Rhythia.cursor_scale, Rhythia.cursor_scale)
	$Mesh2.scale = Vector3(Rhythia.cursor_scale, Rhythia.cursor_scale, Rhythia.cursor_scale)
	var img = Globals.imageLoader.load_if_exists("user://cursor")
	if img:
		mat.albedo_color = Color(1, 1, 1)
		mat.albedo_texture = img

	mat = get_node("../../CursorTrail/Mesh").get("material/0")
	var img2 = Globals.imageLoader.load_if_exists("user://trail")
	if img2: mat.albedo_texture = img2
	elif img: mat.albedo_texture = img

	img = Globals.imageLoader.load_if_exists("user://touch")
	if img: $VisualPos/T.texture = img

	$L.visible = ProjectSettings.get_setting("application/config/show_trail_debug")

	prev_pos = global_transform.origin
	prev_rot = $Mesh.rotation_degrees.x

	if Rhythia.cursor_color_type == Globals.CURSOR_NOTE_COLOR:
		recolor(Rhythia.selected_colorset.colors[-1])
		get_parent().connect("hit", self, "recolor")
	elif Rhythia.cursor_color_type == Globals.CURSOR_CUSTOM_COLOR:
		recolor(Rhythia.cursor_color)

	if Rhythia.get("cursor_glow"):
		load("res://scripts/game/CursorGlow.gd").add_to(self, get_parent())

	if Rhythia.cursor_trail:
		if Rhythia.smart_trail:
			# one MultiMesh for the whole trail (TrailMulti.gd), next to the old pieces' place
			_trail_mm = load("res://scripts/game/TrailMulti.gd").make(trail_base)
			get_node("../..").call_deferred("add_child", _trail_mm)
		elif OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES3 and int(Rhythia.trail_detail) >= 2:
			# the classic trail's pieces as slots of one MultiMesh, aged on the
			# graphics card (TrailMulti.gd): no node, script and material per piece
			_cl_n = int(min(int(Rhythia.trail_detail), 256 if _light_trail else 4096))
			_trail_cl = load("res://scripts/game/TrailMulti.gd").make(trail_base, _cl_n)
			get_node("../..").call_deferred("add_child", _trail_cl)
			for _i in range(_cl_n):
				_cl_last.append(Vector3(-100, 0, 0))
		else:
			for i in range(Rhythia.trail_detail):
				var trail: Spatial = trail_base
				if i != 0:
					trail = trail.duplicate()
					get_node("../..").call_deferred("add_child", trail)
				trail.offset = (i) / float(Rhythia.trail_detail - 1)
				trail.start()
	trail_started = true
func _exit_tree():
	for n in trail_cache:
		n.queue_free()
