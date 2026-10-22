extends Spatial
class_name VRPlayer

onready var origin: Spatial = $Origin
onready var head: Camera = $Origin/Head
onready var left_hand: Spatial = $Origin/LeftHand
onready var left_ray: RayCast = $Origin/LeftHand/Ray
onready var right_hand: Spatial = $Origin/RightHand
onready var right_ray: RayCast = $Origin/RightHand/Ray

var primary_ray: RayCast

func update_primary_ray():
	if Rhythia.vr_left_handed:
		primary_ray = left_ray
		left_ray.enabled = true
		right_ray.enabled = false
	else:
		primary_ray = right_ray
		left_ray.enabled = false
		right_ray.enabled = true

func _ready():
	origin.visible = false
	if Rhythia.fake_vr:
		origin = $FakeOrigin
		head = $FakeOrigin/Head
		left_hand = $FakeOrigin/LeftHand
		left_ray = $FakeOrigin/LeftHand/Ray
		right_hand = $FakeOrigin/RightHand
		right_ray = $FakeOrigin/RightHand/Ray
	origin.visible = true
	update_primary_ray()
	set_process(true)
	pause_mode = PAUSE_MODE_PROCESS

func _process(delta):
	if Input.is_action_just_pressed("vr_switch_hands"):
		Rhythia.vr_left_handed = not Rhythia.vr_left_handed
		update_primary_ray()
	if Input.is_action_just_pressed("vr_recenter"):
		recenter_to_head()
	_watch_for_reset()
	if not Rhythia.fake_vr:
		_place_eye()
	primary_ray.force_raycast_update()
	primary_ray.update_beam()

# --- Recentering ---------------------------------------------------------------
# Puts the game where you're looking: the menu screen (or the grid in a song)
# straight ahead of the way you face, and lower or higher by how far down or up
# you look, whatever your real height or where you stand.
#
# It happens when the headset's view jumps all at once (resetting the boundary
# / "Reset view" on a Meta Quest, SteamVR's reset), once when VR starts, and
# on the recenter button (A / X).
const EYE_HEIGHT := 2.0          # game units (the fake VR head sits there too)
const JUMP_MOVE := 0.25          # game units in one frame (12 cm at world scale 2)
const JUMP_TURN := deg2rad(15.0) # in one frame (heads don't turn that fast)
const SETTLE_FRAMES := 8         # wait for the new pose to settle first
const MAX_LOOK_DOWN := deg2rad(60.0)
const MAX_LOOK_UP := deg2rad(40.0)

var _last_head = null # Transform
var _recenter_in := 45 # first recenter shortly after VR starts
var _ignore := 0
var _pitch := 0.0 # how far down (-) / up (+) you looked at the last recenter

# Eye height so the content sits along your gaze: looking down puts it lower
# in front of you, looking up higher. Kept when the scene changes (menu <->
# song), so each gets placed the same way.
func _place_eye():
	# the menu screen tilts back to face you when you look down at it
	if is_instance_valid(Rhythia.vr_menu) and Rhythia.vr_menu.has_meta("home"):
		var home: Transform = Rhythia.vr_menu.get_meta("home")
		var want := Transform(home.basis.rotated(Vector3.RIGHT, _pitch), home.origin)
		if not Rhythia.vr_menu.transform.is_equal_approx(want):
			Rhythia.vr_menu.transform = want
	var c: Vector3 = to_local(_content_point())
	var dist: float = max(Vector2(c.x, c.z).length(), 0.5)
	var eye: float = c.y - dist * tan(_pitch)
	if is_nan(eye) or is_inf(eye):
		eye = EYE_HEIGHT
	if abs(origin.transform.origin.y - eye) > 0.001 or origin.transform.origin.x != 0 or origin.transform.origin.z != 0:
		origin.transform.origin = Vector3(0, eye, 0)

func _watch_for_reset():
	if Rhythia.fake_vr:
		return
	var t: Transform = head.transform
	if t.origin == Vector3.ZERO and t.basis == Basis():
		return # no pose from the headset yet
	if _ignore > 0:
		_ignore -= 1
	elif _last_head != null:
		var moved: float = t.origin.distance_to(_last_head.origin)
		var f0: Vector3 = -_last_head.basis.z
		var f1: Vector3 = -t.basis.z
		var turned: float = Vector2(f0.x, f0.z).angle_to(Vector2(f1.x, f1.z)) if Vector2(f0.x, f0.z).length() > 0.1 and Vector2(f1.x, f1.z).length() > 0.1 else 0.0
		if (moved > JUMP_MOVE or abs(turned) > JUMP_TURN) and _recenter_in == 0:
			Rhythia.trail("VR view jumped (moved %.2f, turned %d deg): recentering" % [moved, int(rad2deg(abs(turned)))])
			_recenter_in = SETTLE_FRAMES
	_last_head = t
	if _recenter_in > 0:
		_recenter_in -= 1
		if _recenter_in == 0:
			recenter_to_head()

# Where the game's content is (menu screen or grid centre), in world space.
func _content_point() -> Vector3:
	if is_instance_valid(Rhythia.vr_menu) and Rhythia.vr_menu.is_inside_tree() and Rhythia.vr_menu.has_meta("home"):
		var home: Transform = Rhythia.vr_menu.get_meta("home")
		return Rhythia.vr_menu.get_parent().global_transform.xform(home.origin)
	return Vector3.ZERO # songs: the grid is around the world's centre

func recenter_to_head():
	if Rhythia.fake_vr:
		return
	# how far up / down you look (before the reset straightens it out)
	var fwd: Vector3 = -head.global_transform.basis.z.normalized()
	var pitch: float = clamp(asin(clamp(fwd.y, -1.0, 1.0)), -MAX_LOOK_DOWN, MAX_LOOK_UP)
	# head to the origin, facing forward (keeps the floor level / tilt)
	ARVRServer.center_on_hmd(ARVRServer.RESET_BUT_KEEP_TILT, false)
	_pitch = pitch
	_place_eye()
	Rhythia.trail("VR recentered (looking %d deg %s)" % [int(abs(rad2deg(pitch))), "down" if pitch < 0 else "up"])
	_last_head = null
	_ignore = 3 # the recenter itself makes the pose jump
	_recenter_in = 0
