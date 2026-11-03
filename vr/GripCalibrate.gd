extends Spatial

# Settings > VR > Controller grip > Calibrate: sets the grip angle from how you
# really hold the controller. A dot shows in front of you (the menu screen and
# the beams are hidden, so you aim the way you would without seeing a beam);
# you point at it like you normally do and hold the trigger for a moment.
# The grip's tilt and turn then become the angle between where the controller
# points by itself and where your hand pointed (averaged over the hold), so the
# beam goes where you aim. Roll and the position offset stay as they are.
# Works with either hand (the left one is stored as the right one's mirror,
# like the sliders). B / Y or 30 seconds without a hold: cancelled.

signal finished(applied)

const HOLD_S := 1.2
const MAX_SPREAD_DEG := 7.0 # moved more than this during the hold: again
const GIVE_UP_S := 30.0
const DIST_M := 1.6

var player # VRPlayer
var _target: Spatial
var _label: Label3D
var _held := 0.0
var _hand := -1 # 0 left, 1 right
var _sum := Vector3.ZERO
var _samples := []
var _age := 0.0
var _hidden := [] # [node, was visible]
var _rays_enabled := []
var _done := false

static func start(vr_player) -> Node:
	var c = load("res://vr/GripCalibrate.gd").new()
	c.name = "GripCalibrate"
	c.player = vr_player
	vr_player.add_child(c)
	return c

# the tilt / turn (degrees, as the sliders store them) that makes a ray with
# `base` on a controller at `ctrl` point at `target`; roll is `roll`
static func solve(ctrl: Transform, base: Transform, target: Vector3, left: bool, roll: float, off: Vector3 = Vector3.ZERO) -> Vector3:
	var v := local_dir(ctrl, base, target, off)
	return angles(v, left, roll)

# the grip's position offset on that hand, as VRPlayer._apply_grip puts it
static func hand_offset(left: bool) -> Vector3:
	var p: Vector3 = Rhythia.vr_grip_pos * 0.02
	return Vector3(-p.x if left else p.x, p.y, p.z)

static func local_dir(ctrl: Transform, base: Transform, target: Vector3, off: Vector3 = Vector3.ZERO) -> Vector3:
	var origin: Vector3 = ctrl.xform(base.origin + off)
	var d: Vector3 = (target - origin).normalized()
	var b: Basis = ctrl.basis.orthonormalized()
	var v: Vector3 = b.xform_inv(d)
	return base.basis.orthonormalized().xform_inv(v).normalized()

static func angles(v: Vector3, left: bool, roll: float) -> Vector3:
	var pitch: float = rad2deg(asin(clamp(v.y, -1.0, 1.0)))
	var yaw: float = rad2deg(atan2(-v.x, -v.z))
	if left:
		yaw = -yaw # (the left hand is the right hand's mirror image)
	return Vector3(clamp(pitch, -90.0, 90.0), clamp(yaw, -60.0, 60.0), roll)

func _ready():
	var head: Camera = player.head
	var fwd: Vector3 = -head.global_transform.basis.z
	fwd.y = 0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var u: float = player.UNITS_PER_M
	# the dot: at eye height in front of you
	_target = Spatial.new()
	player.add_child(_target)
	_target.global_transform.origin = head.global_transform.origin + fwd * DIST_M * u
	var m := MeshInstance.new()
	var s := SphereMesh.new()
	s.radius = 0.035 * u
	s.height = 0.07 * u
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.flags_no_depth_test = true
	mat.albedo_color = Color(1, 0.76, 0.96)
	s.material = mat
	m.mesh = s
	_target.add_child(m)
	var ring := MeshInstance.new()
	var t := CylinderMesh.new()
	t.top_radius = 0.08 * u
	t.bottom_radius = 0.08 * u
	t.height = 0.002 * u
	var rmat := SpatialMaterial.new()
	rmat.flags_unshaded = true
	rmat.flags_transparent = true
	rmat.albedo_color = Color(1, 0.76, 0.96, 0.25)
	t.material = rmat
	ring.mesh = t
	ring.rotation_degrees = Vector3(90, 0, 0)
	_target.add_child(ring)
	_target.look_at(head.global_transform.origin, Vector3.UP)
	_label = Label3D.new()
	_label.pixel_size = 0.0025 * u
	_label.font = DynamicFont.new()
	_label.font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	_label.font.size = 44
	_label.modulate = Color(1, 0.94, 1)
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.no_depth_test = true
	_label.autowrap = true
	_label.width = 900
	_label.transform.origin = Vector3(0, -0.22 * u, 0)
	_label.rotation_degrees = Vector3(0, 180, 0) # (faces you: the target looks at you)
	_target.add_child(_label)
	_say("Hold the controller the way you normally play and point it at the dot.\nThen hold the trigger still for a second.\n(B / Y: cancel)")
	# nothing else in the way: the menu screen and the beams go while you aim
	if is_instance_valid(Rhythia.vr_menu):
		_hide(Rhythia.vr_menu)
	for ray in [player.left_ray, player.right_ray]:
		_hide(ray)
		_rays_enabled.append([ray, ray.enabled])
		ray.enabled = false # (no clicks on the hidden menu)

func _hide(n: Spatial):
	_hidden.append([n, n.visible])
	n.visible = false

func _say(text: String):
	_label.text = text

func _trigger(hand) -> bool:
	if Rhythia.fake_vr and hand == player.right_hand:
		return Input.is_mouse_button_pressed(BUTTON_LEFT) # (the desktop stand-in for VR)
	if not (hand is ARVRController):
		return false
	for b in Rhythia.vr_bind("vr_click") + [JOY_VR_TRIGGER]:
		if hand.is_button_pressed(int(b)):
			return true
	return false

func _cancel_pressed() -> bool:
	for hand in [player.left_hand, player.right_hand]:
		if hand is ARVRController and hand.is_button_pressed(JOY_OCULUS_BY): # (B / Y)
			return true
	return Input.is_key_pressed(KEY_ESCAPE)

func _process(delta: float):
	if _done:
		return
	_age += delta
	if _cancel_pressed() or (_age > GIVE_UP_S and _held == 0.0):
		_finish(false, "Calibration cancelled")
		return
	var hands := [player.left_hand, player.right_hand]
	var which := -1
	if _hand != -1 and _trigger(hands[_hand]):
		which = _hand
	else:
		for i in 2:
			if _trigger(hands[i]):
				which = i
				break
	if which == -1:
		if _held > 0.0:
			_say("Keep the trigger held until it's done. Try again:\npoint at the dot and hold the trigger.")
		_reset_hold()
		return
	if which != _hand:
		_reset_hold()
		_hand = which
	_held += delta
	var ray: Spatial = player.left_ray if which == 0 else player.right_ray
	var base: Transform = player._ray_base[which]
	var v := local_dir(hands[which].global_transform, base, _target.global_transform.origin, hand_offset(which == 0))
	_sum += v
	_samples.append(v)
	var n := int(clamp(_held / HOLD_S, 0.0, 1.0) * 10.0)
	_say("Hold still...  " + "|".repeat(n) + ".".repeat(10 - n))
	if _held >= HOLD_S:
		var avg := _sum.normalized()
		var spread := 0.0
		for s in _samples:
			spread = max(spread, rad2deg(s.angle_to(avg)))
		if spread > MAX_SPREAD_DEG:
			_say("You moved a little. Point at the dot and hold the trigger still.")
			_reset_hold()
			return
		var r: Vector3 = angles(avg, which == 0, Rhythia.vr_grip_rot.z)
		Rhythia.vr_grip_rot = r
		Rhythia.save_settings()
		Rhythia.trail("VR grip calibrated (%s hand): tilt %d, turn %d" % ["left" if which == 0 else "right", int(round(r.x)), int(round(r.y))])
		_finish(true, "Done: tilt %+d°, turn %+d°" % [int(round(r.x)), int(round(r.y))])

func _reset_hold():
	_held = 0.0
	_sum = Vector3.ZERO
	_samples.clear()

func _finish(applied: bool, text: String):
	_done = true
	_say(text)
	for e in _rays_enabled:
		e[0].enabled = e[1]
	yield(get_tree().create_timer(1.2), "timeout")
	for e in _hidden:
		if is_instance_valid(e[0]):
			e[0].visible = e[1]
	if is_instance_valid(_target):
		_target.queue_free()
	emit_signal("finished", applied)
	queue_free()
