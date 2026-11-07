extends Spatial

# Settings > VR > Controller grip > Calibrate: sets the grip angle from how you
# really play. The song grid shows in front of you, where it is in a song
# (Settings > VR > grid distance). Notes light up one at a time (the middle,
# then the four corners): move your hand to each one the way you would in a
# song, without aiming carefully, and pull the trigger. The grip's tilt and
# turn are then fitted to all five (where the controller pointed by itself
# against where the notes were), so the beam follows your natural hand.
# After that a cursor follows your hand on the grid with the new angle, live:
# trigger keeps it, B / Y starts over. Roll and the position offset stay as
# they are. Either hand works (the left one is stored as the right one's
# mirror, like the sliders). Esc, or 40 seconds without a note: cancelled.

signal finished(applied)

const GIVE_UP_S := 40.0
const TARGETS := [Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)] # (grid squares from the middle)
const HOLD_FRAMES := 6 # (frames averaged for each note)

var player # VRPlayer
var _root: Spatial # the grid, its notes and the cursor
var _center := Vector3()
var _right := Vector3()
var _up := Vector3()
var _k := 1.0 # (Settings > VR > Grid size)
var _normal := Vector3()
var _note: MeshInstance
var _cursor: MeshInstance
var _label: Label3D
var _step := 0 # which note, TARGETS.size(): checking the result
var _hand := -1 # 0 left, 1 right
var _samples := [] # local directions, one per note
var _grab := [] # this note's frames
var _was_down := [false, false]
var _was_cancel := false
var _age := 0.0
var _hidden := [] # [node, was visible]
var _rays_enabled := []
var _old_rot := Vector3()
var _done := false

static func start(vr_player) -> Node:
	var c = load("res://vr/GripCalibrate.gd").new()
	c.name = "GripCalibrate"
	c.player = vr_player
	vr_player.add_child(c)
	return c

# the grip's position offset on that hand, as VRPlayer._apply_grip puts it
static func hand_offset(left: bool) -> Vector3:
	var p: Vector3 = Rhythia.vr_grip_pos * 0.02
	return Vector3(-p.x if left else p.x, p.y, p.z)

# where `target` is, seen from the ray's base on a controller at `ctrl`
static func local_dir(ctrl: Transform, base: Transform, target: Vector3, off: Vector3 = Vector3.ZERO) -> Vector3:
	var origin: Vector3 = ctrl.xform(base.origin + off)
	var d: Vector3 = (target - origin).normalized()
	var b: Basis = ctrl.basis.orthonormalized()
	var v: Vector3 = b.xform_inv(d)
	return base.basis.orthonormalized().xform_inv(v).normalized()

# the tilt / turn (degrees, as the sliders store them) for a ray pointing at `v`
static func angles(v: Vector3, left: bool, roll: float) -> Vector3:
	var pitch: float = rad2deg(asin(clamp(v.y, -1.0, 1.0)))
	var yaw: float = rad2deg(atan2(-v.x, -v.z))
	if left:
		yaw = -yaw # (the left hand is the right hand's mirror image)
	return Vector3(clamp(pitch, -90.0, 90.0), clamp(yaw, -60.0, 60.0), roll)

func _ready():
	_old_rot = Rhythia.vr_grip_rot
	var head: Camera = player.head
	var fwd: Vector3 = -head.global_transform.basis.z
	fwd.y = 0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var u: float = player.UNITS_PER_M
	# where the grid is in a song: the grid distance ahead, 2.5 units over the floor
	var floor_y: float = player.left_hand.get_parent().global_transform.origin.y
	_center = head.global_transform.origin + fwd * Rhythia.vr_grid_distance * u
	_center.y = floor_y + 2.5
	_normal = -fwd
	_up = Vector3.UP
	_right = _up.cross(_normal).normalized()
	_root = Spatial.new()
	player.add_child(_root)
	# (Settings > VR > Grid size: the grid as big as in songs)
	_k = clamp(float(Rhythia.vr_grid_size), 0.5, 2.0)
	_root.global_transform = Transform(Basis(_right * _k, _up * _k, _normal * _k), _center)
	_root.add_child(_grid_mesh())
	_note = _square(0.86, Color(1, 0.76, 0.96), 0.09)
	_root.add_child(_note)
	_cursor = MeshInstance.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.material = _mat(Color(1, 1, 1))
	_cursor.mesh = s
	_cursor.visible = false
	_root.add_child(_cursor)
	_label = Label3D.new()
	_label.pixel_size = 0.004
	_label.font = DynamicFont.new()
	_label.font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	_label.font.size = 44
	_label.modulate = Color(1, 0.94, 1)
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.no_depth_test = true
	_label.autowrap = true
	_label.width = 1100
	_label.transform.origin = Vector3(0, -2.2, 0)
	_root.add_child(_label)
	# nothing else in the way: the menu screen and the beams go while you play
	if is_instance_valid(Rhythia.vr_menu):
		_hide(Rhythia.vr_menu)
	for ray in [player.left_ray, player.right_ray]:
		_hide(ray)
		_rays_enabled.append([ray, ray.enabled])
		ray.enabled = false # (no clicks on the hidden menu)
	_show_step()

func _mat(c: Color) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_no_depth_test = true
	m.flags_transparent = c.a < 1.0
	m.albedo_color = c
	return m

# the 3x3 grid, its squares 1 unit wide like in a song
func _grid_mesh() -> MeshInstance:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in range(4):
		var k: float = -1.5 + i
		for p in [Vector3(k, -1.5, 0), Vector3(k, 1.5, 0), Vector3(-1.5, k, 0), Vector3(1.5, k, 0)]:
			st.add_vertex(p)
	var mi := MeshInstance.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1, 0.55))
	return mi

# a note: a square outline
func _square(size: float, c: Color, w: float) -> MeshInstance:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size / 2.0
	var i := h - w
	var quads := [
		[Vector3(-h, h, 0), Vector3(h, h, 0), Vector3(h, i, 0), Vector3(-h, i, 0)],
		[Vector3(-h, -i, 0), Vector3(h, -i, 0), Vector3(h, -h, 0), Vector3(-h, -h, 0)],
		[Vector3(-h, i, 0), Vector3(-i, i, 0), Vector3(-i, -i, 0), Vector3(-h, -i, 0)],
		[Vector3(i, i, 0), Vector3(h, i, 0), Vector3(h, -i, 0), Vector3(i, -i, 0)],
	]
	for q in quads:
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[idx])
	var mi := MeshInstance.new()
	mi.mesh = st.commit()
	var m := _mat(c)
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	mi.material_override = m
	return mi

func _hide(n: Spatial):
	_hidden.append([n, n.visible])
	n.visible = false

func _say(text: String):
	_label.text = text

func _show_step():
	if _step < TARGETS.size():
		_note.visible = true
		_note.transform.origin = Vector3(TARGETS[_step].x, TARGETS[_step].y, 0.01)
		_cursor.visible = false
		_say("Move your hand to the note the way you would in a song (no need to aim) and pull the trigger.   %d / %d\n(Esc: cancel)" % [_step + 1, TARGETS.size()])
	else:
		_note.visible = false
		_cursor.visible = true
		_say("Move your hand around: the dot follows it with the new grip.\nTrigger: keep it.   B / Y: start over.")

func _trigger(hand) -> bool:
	if Rhythia.fake_vr and hand == player.right_hand:
		return Input.is_mouse_button_pressed(BUTTON_LEFT) # (the desktop stand-in for VR)
	if not (hand is ARVRController):
		return false
	for b in Rhythia.vr_bind("vr_click") + [JOY_VR_TRIGGER]:
		if hand.is_button_pressed(int(b)):
			return true
	return false

func _by_pressed() -> bool:
	for hand in [player.left_hand, player.right_hand]:
		if hand is ARVRController and hand.is_button_pressed(JOY_OCULUS_BY): # (B / Y)
			return true
	return false

# a grid point (in squares from the middle) in the world
func _grid_point(p: Vector2) -> Vector3:
	return _center + (_right * p.x + _up * p.y) * _k

func _process(delta: float):
	if _done:
		return
	_age += delta
	if Input.is_key_pressed(KEY_ESCAPE) or (_age > GIVE_UP_S and _step < TARGETS.size()):
		_finish(false, "Calibration cancelled")
		return
	var hands := [player.left_hand, player.right_hand]
	var pressed := [false, false]
	for i in 2:
		var down: bool = _trigger(hands[i])
		pressed[i] = down and not _was_down[i]
		_was_down[i] = down
	var by := _by_pressed()
	var by_edge := by and not _was_cancel
	_was_cancel = by
	if _step >= TARGETS.size():
		_live(hands)
		if by_edge:
			Rhythia.vr_grip_rot = _old_rot
			_restart()
		elif pressed[_hand]:
			Rhythia.save_settings()
			var r: Vector3 = Rhythia.vr_grip_rot
			Rhythia.trail("VR grip calibrated on the grid (%s hand): tilt %d, turn %d" % ["left" if _hand == 0 else "right", int(round(r.x)), int(round(r.y))])
			_finish(true, "Done: tilt %+d°, turn %+d°" % [int(round(r.x)), int(round(r.y))])
		return
	if by_edge and _step > 0:
		_restart()
		return
	# a note: the hand that pulls the trigger, a few frames averaged
	if _grab.empty():
		for i in 2:
			if pressed[i] and (_hand == -1 or _hand == i):
				_hand = i
				_grab.append(_dir_now(hands[i], i))
				break
		return
	_grab.append(_dir_now(hands[_hand], _hand))
	if _grab.size() >= HOLD_FRAMES:
		var sum := Vector3.ZERO
		for v in _grab:
			sum += v
		_samples.append(sum.normalized())
		_grab.clear()
		_step += 1
		age_reset()
		if _step >= TARGETS.size():
			_fit()
		_show_step()

func age_reset():
	_age = 0.0

func _dir_now(hand: Spatial, i: int) -> Vector3:
	var base: Transform = player._ray_base[i]
	return local_dir(hand.global_transform, base, _grid_point(TARGETS[_step]), hand_offset(i == 0))

# one grip for all the notes: the average of where the notes were, seen from
# the controller (a note far off the rest, a slip, counts less)
func _fit():
	var avg := Vector3.ZERO
	for v in _samples:
		avg += v
	avg = avg.normalized()
	var w_sum := Vector3.ZERO
	for v in _samples:
		var off: float = rad2deg(v.angle_to(avg))
		w_sum += v * (1.0 / (1.0 + off / 10.0))
	avg = w_sum.normalized()
	Rhythia.vr_grip_rot = angles(avg, _hand == 0, Rhythia.vr_grip_rot.z) # (VRPlayer puts it on the beams)

# the dot: where the beam meets the grid, with the grip as it is now
func _live(hands: Array):
	var ray: RayCast = player.left_ray if _hand == 0 else player.right_ray
	var from: Vector3 = ray.global_transform.origin
	var dir: Vector3 = ray.global_transform.basis.xform(ray.cast_to).normalized()
	var den: float = dir.dot(_normal)
	if abs(den) < 1e-4:
		_cursor.visible = false
		return
	var t: float = (_center - from).dot(_normal) / den
	if t < 0.0:
		_cursor.visible = false
		return
	var hit: Vector3 = from + dir * t
	var local: Vector3 = _root.global_transform.affine_inverse().xform(hit)
	_cursor.visible = true
	_cursor.transform.origin = Vector3(clamp(local.x, -1.8, 1.8), clamp(local.y, -1.8, 1.8), 0.02)

func _restart():
	_step = 0
	_samples.clear()
	_grab.clear()
	_hand = -1
	_age = 0.0
	_show_step()

func _finish(applied: bool, text: String):
	_done = true
	if not applied:
		Rhythia.vr_grip_rot = _old_rot
	_say(text)
	for e in _rays_enabled:
		e[0].enabled = e[1]
	yield(get_tree().create_timer(1.2), "timeout")
	for e in _hidden:
		if is_instance_valid(e[0]):
			e[0].visible = e[1]
	if is_instance_valid(_root):
		_root.queue_free()
	emit_signal("finished", applied)
	queue_free()
