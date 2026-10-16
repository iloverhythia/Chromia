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
	primary_ray.force_raycast_update()
	primary_ray.update_beam()

func recenter_to_head():
	ARVRServer.center_on_hmd(ARVRServer.RESET_BUT_KEEP_TILT, true)
	var head_pos = head.global_transform.origin
	var yaw = head.global_transform.basis.get_euler().y
	var forward = Vector3(sin(yaw), 0, cos(yaw)) * -1
	Rhythia.vr_menu.global_transform.origin = head_pos + forward * 2.0
	Rhythia.vr_menu.global_transform.basis = Basis(Vector3.UP, yaw)
