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
	primary_ray.force_raycast_update()
	primary_ray.update_beam()

# --- Recentering ---------------------------------------------------------------
# The game is laid out for your eyes at EYE_HEIGHT above the VR player (the menu
# screen in front of you, the grid straight ahead in songs). Recentering puts
# your head exactly there, facing the game, whatever your real height and
# wherever you stand or look.
#
# It happens by itself when the headset's view jumps all at once, which is what
# resetting the boundary / "Reset view" on a Meta Quest (or SteamVR's reset
# seated position) does, once at the start of VR, and on the recenter button.
const EYE_HEIGHT := 2.0          # game units (the fake VR head sits there too)
const JUMP_MOVE := 0.6           # game units in one frame (0.3 m at world scale 2)
const JUMP_TURN := deg2rad(35.0) # in one frame: no head turns that fast
const SETTLE_FRAMES := 8         # wait for the new pose to settle first

var _last_head = null # Transform
var _recenter_in := 45 # first recenter shortly after VR starts
var _ignore := 0

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
		if moved > JUMP_MOVE or abs(turned) > JUMP_TURN:
			Rhythia.trail("VR view jumped (moved %.2f, turned %d deg): recentering" % [moved, int(rad2deg(abs(turned)))])
			_recenter_in = SETTLE_FRAMES
	_last_head = t
	if _recenter_in > 0:
		_recenter_in -= 1
		if _recenter_in == 0:
			recenter_to_head()

func recenter_to_head():
	if Rhythia.fake_vr:
		return
	# head to the origin, facing forward (keeps the floor level / tilt)
	ARVRServer.center_on_hmd(ARVRServer.RESET_BUT_KEEP_TILT, false)
	origin.transform.origin = Vector3(0, EYE_HEIGHT, 0)
	_last_head = null
	_ignore = 3 # the recenter itself makes the pose jump
	_recenter_in = 0
	# the menu screen back in front of you
	if is_instance_valid(Rhythia.vr_menu) and Rhythia.vr_menu.has_meta("home"):
		Rhythia.vr_menu.transform = Rhythia.vr_menu.get_meta("home")
