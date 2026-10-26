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
	_ray_base = [left_ray.transform, right_ray.transform]
	for h in [left_hand, right_hand]:
		var mi = h.get_node_or_null("Mesh")
		if mi:
			_hand_default.append([mi, mi.mesh, mi.transform, mi.get_surface_material(0)])
	apply_hand()
	# the headset's settings once VR is up and drawing (the plugin's foveation
	# works on the eye images, which exist only then)
	get_tree().create_timer(1.5).connect("timeout", self, "apply_xr_settings")
	get_tree().connect("node_added", self, "_on_node_added")
	update_primary_ray()
	set_process(true)
	pause_mode = PAUSE_MODE_PROCESS

func _process(delta):
	if Input.is_action_just_pressed("vr_switch_hands"):
		Rhythia.vr_left_handed = not Rhythia.vr_left_handed
		update_primary_ray()
	_hold_recenter(delta)
	_haptics_tick(delta)
	_watch_for_reset(delta)
	_apply_grip()
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
# when you hold the recenter button (A / X) for a second.
#
# Loading a song or the menu (failing, restarting) can stall the game for a
# moment, and your head moves on meanwhile: that is not a reset. So the jump
# check pauses while a scene changes and for slow frames.
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
const HOLD_TIME := 1.0 # seconds the recenter button has to be held
const SLOW_FRAME := 0.05 # seconds: a stall, not a reset
const SCENE_QUIET := 60 # frames after a scene change without the jump check
var _held := 0.0
var _hold_done := false
var _hold_label = null # Label3D in front of you while holding
var _scene_id := 0

func _hold_recenter(delta: float):
	if not Input.is_action_pressed("vr_recenter"):
		_held = 0.0
		_hold_done = false
		_show_hold("")
		return
	if _hold_done:
		return
	_held += delta
	if _held >= HOLD_TIME:
		_hold_done = true
		recenter_to_head()
		_show_hold("Recentered", 0.8)
	elif _held > 0.15:
		var n := int(_held / HOLD_TIME * 10.0)
		_show_hold("Hold to recenter  " + "|".repeat(n) + ".".repeat(10 - n))

func _show_hold(text: String, keep: float = 0.0):
	if Rhythia.fake_vr:
		return
	if _hold_label == null or not is_instance_valid(_hold_label):
		if text == "":
			return
		_hold_label = Label3D.new()
		_hold_label.pixel_size = 0.0025
		_hold_label.font = DynamicFont.new()
		_hold_label.font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
		_hold_label.font.size = 48
		_hold_label.modulate = Color(1, 0.86, 0.98)
		_hold_label.outline_modulate = Color(0, 0, 0, 0.8)
		_hold_label.no_depth_test = true
		_hold_label.fixed_size = false
		_hold_label.transform.origin = Vector3(0, -0.25, -1.6)
		head.add_child(_hold_label)
	if keep > 0.0:
		_hold_label.text = text
		_hold_label.visible = true
		get_tree().create_timer(keep).connect("timeout", self, "_hide_hold", [text])
		return
	if text == "" and _hold_label.text == "Recentered":
		return # the "Recentered" note stays a moment
	_hold_label.text = text
	_hold_label.visible = text != ""

func _hide_hold(text: String):
	if _hold_label != null and is_instance_valid(_hold_label) and _hold_label.text == text:
		_hold_label.text = ""
		_hold_label.visible = false

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

func _watch_for_reset(delta: float):
	if Rhythia.fake_vr:
		return
	var t: Transform = head.transform
	if t.origin == Vector3.ZERO and t.basis == Basis():
		return # no pose from the headset yet
	var sc = get_tree().current_scene
	var sid: int = sc.get_instance_id() if sc != null else 0
	if sid != _scene_id:
		_scene_id = sid
		_ignore = max(_ignore, SCENE_QUIET) # a song or the menu is loading
	if delta > SLOW_FRAME:
		_ignore = max(_ignore, 2) # a stall: the head kept moving meanwhile
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

# Controller grip (Settings > VR): the pointer's angle and offset on the hand.
# The left hand gets the mirror image of the right hand's setting.
var _ray_base := []
var _grip_applied = null
func _apply_grip():
	if _ray_base.size() != 2:
		return
	var key = [Rhythia.vr_grip_rot, Rhythia.vr_grip_pos]
	if key == _grip_applied:
		return
	_grip_applied = key
	var r: Vector3 = Rhythia.vr_grip_rot
	var p: Vector3 = Rhythia.vr_grip_pos * 0.02 # cm -> game units (world scale 2)
	for i in range(2):
		var left := i == 0
		var base: Transform = _ray_base[i]
		var rot := Vector3(deg2rad(r.x), deg2rad(-r.y if left else r.y), deg2rad(-r.z if left else r.z))
		var off := Vector3(-p.x if left else p.x, p.y, p.z)
		var ray: Spatial = left_ray if left else right_ray
		ray.transform = Transform(base.basis * Basis(rot), base.origin + off)

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

# --- Hands -------------------------------------------------------------------
# Settings > VR > Hands: "default" (the box), "paw" (PawHand.gd, built in) or
# "custom": vr_hand.obj (and its .mtl / textures) in the user folder, the right
# hand's model in metres with the controller at the origin, -Z forward (where
# the pointer goes), +Y up. The left hand gets the mirror image, or its own
# vr_hand_left.obj. Without an .mtl colour it takes the default hand look.
# The default hand is in docs/vr_hand (same layout) to start from.
var _hand_default := [] # [MeshInstance, mesh, transform, material] per hand
var _hand_shown := ""

func apply_hand():
	var want: String = Rhythia.vr_hand
	if want == _hand_shown:
		return
	var meshes = null # [left, right]
	if want == "paw":
		var right = load("res://vr/PawHand.gd").build()
		meshes = [_mirrored(right), right]
	elif want == "custom":
		meshes = _custom_hand_meshes()
		if meshes == null:
			want = "default"
	_hand_shown = want
	# the beam starts at the paw's toes (the ray itself is unchanged)
	for ray in [left_ray, right_ray]:
		if "start_gap" in ray:
			ray.start_gap = 0.0
			if want == "paw":
				ray.start_gap = max(0.0, ray.transform.origin.z + load("res://vr/PawHand.gd").TIP * UNITS_PER_M)
	for i in range(_hand_default.size()):
		var d: Array = _hand_default[i]
		var mi: MeshInstance = d[0]
		var outline = mi.get_node_or_null("Outline")
		var trail = mi.get_node_or_null("HandTrail")
		if meshes == null:
			mi.mesh = d[1]
			mi.transform = d[2]
			mi.set_surface_material(0, d[3])
			if outline:
				outline.visible = true
			if trail:
				trail.transform = Transform()
			continue
		var mesh: Mesh = meshes[i]
		mi.mesh = mesh
		mi.transform = Transform(Basis().scaled(Vector3(UNITS_PER_M, UNITS_PER_M, UNITS_PER_M)), Vector3.ZERO)
		for k in range(mesh.get_surface_count()):
			# its own material (paw, .mtl colour / texture), or the default hand look
			mi.set_surface_material(k, null if mesh.surface_get_material(k) != null else d[3])
		if outline:
			outline.visible = false
		if trail:
			trail.transform = Transform(Basis().scaled(Vector3(0.02, 0.02, 0.06)), Vector3.ZERO)
	Rhythia.trail("VR hands: " + want)

func _custom_hand_meshes():
	var right_path: String = Globals.p("user://vr_hand.obj")
	var f := File.new()
	if not f.file_exists(right_path):
		return null
	var ObjParse = load("res://scripts/content/resources/ObjParse.gd")
	var right = ObjParse.load_obj(right_path)
	if right == null or right.get_surface_count() == 0:
		Rhythia.trail("VR hand: couldn't read vr_hand.obj")
		return null
	var left = null
	var left_path: String = Globals.p("user://vr_hand_left.obj")
	if f.file_exists(left_path):
		left = ObjParse.load_obj(left_path)
	if left == null or left.get_surface_count() == 0:
		left = _mirrored(right)
	return [left, right]

# --- Graphics (Settings > VR > Graphics) --------------------------------------
# Meta Quest (OpenXR plugin): foveated rendering (the edges of each eye drawn
# at lower resolution, where the lenses blur them anyway) and the display
# refresh rate. Glow: a full-screen blur per eye, costly on the headset, so off
# there unless turned on.
func apply_xr_settings():
	var cfg = Rhythia.vr_xr_config
	if cfg == null:
		return
	# the plugin's set_foveation_level(level, dynamic) takes both: called
	# with one, native code reads a missing argument and the app crashed
	if cfg.has_method("set_foveation_level"):
		var lvl: int = int(clamp(Rhythia.vr_foveation, 0, 3))
		cfg.set_foveation_level(lvl, lvl > 0)
	if Rhythia.vr_refresh > 0.0 and cfg.has_method("set_refresh_rate"):
		var ok := true
		if cfg.has_method("get_available_refresh_rates"):
			ok = false
			for r in cfg.get_available_refresh_rates():
				if abs(float(r) - Rhythia.vr_refresh) < 0.5:
					ok = true
		if ok:
			cfg.set_refresh_rate(Rhythia.vr_refresh)
	Rhythia.trail("VR graphics: foveation %d, refresh %s" % [Rhythia.vr_foveation, str(Rhythia.vr_refresh) if Rhythia.vr_refresh > 0 else "default"])

static func refresh_rates() -> Array:
	var cfg = Rhythia.vr_xr_config
	if cfg != null and cfg.has_method("get_available_refresh_rates"):
		var out := []
		for r in cfg.get_available_refresh_rates():
			out.append(float(r))
		out.sort()
		return out
	return []

static func glow_on() -> bool:
	if Rhythia.vr_glow >= 0:
		return Rhythia.vr_glow == 1
	return not OS.has_feature("quest")

func _on_node_added(n: Node):
	if n is WorldEnvironment:
		call_deferred("_tune_env", n) # after its scene has set it up
	elif n is Viewport and n.name.ends_with("VP") and n.get_parent() != null and n.get_parent().name == "HUD":
		# the song HUD's panels are drawn into 2D-only viewports: no 3D pass
		# and no multisampling (4x on each, redrawn as the numbers change)
		n.disable_3d = true
		n.msaa = Viewport.MSAA_DISABLED
	elif n.name == "Game" and n.has_signal("hit") and not n.is_connected("hit", self, "_on_hit"):
		n.connect("hit", self, "_on_hit")
		n.connect("miss", self, "_on_miss")

func _tune_env(we):
	if not is_instance_valid(we) or we.environment == null:
		return
	var e: Environment = we.environment
	# the effects that cost the most per eye; glow only if wanted, and cheaper
	e.ssao_enabled = false
	e.ss_reflections_enabled = false
	e.dof_blur_far_enabled = false
	e.dof_blur_near_enabled = false
	if not glow_on():
		e.glow_enabled = false
	else:
		e.glow_high_quality = false
		e.glow_bicubic_upscale = false

# --- Haptics (Settings > VR > Haptics) ----------------------------------------
# A short buzz in the pointing hand on each hit, a stronger one on a miss.
var _rumble_left := 0.0
var _rumble_hand = null

func _on_hit(_col = null):
	_buzz(Rhythia.vr_haptics * 0.6, 0.035)

func _on_miss(_col = null):
	if Rhythia.vr_haptic_miss:
		_buzz(Rhythia.vr_haptics, 0.09)

func _buzz(strength: float, time: float):
	if strength <= 0.0 or Rhythia.fake_vr:
		return
	var hand = left_hand if Rhythia.vr_left_handed else right_hand
	if _rumble_hand != null and _rumble_hand != hand and is_instance_valid(_rumble_hand):
		_rumble_hand.rumble = 0.0
	_rumble_hand = hand
	if "rumble" in hand:
		hand.rumble = clamp(strength, 0.0, 1.0)
	_rumble_left = max(_rumble_left, time)

func _haptics_tick(delta: float):
	if _rumble_left <= 0.0:
		return
	_rumble_left -= delta
	if _rumble_left <= 0.0 and _rumble_hand != null and is_instance_valid(_rumble_hand) and "rumble" in _rumble_hand:
		_rumble_hand.rumble = 0.0

const UNITS_PER_M := 2.0

# The mirror image (left from right): x flipped, triangles turned back around.
static func _mirrored(m: Mesh) -> Mesh:
	var out := ArrayMesh.new()
	for i in range(m.get_surface_count()):
		var a: Array = m.surface_get_arrays(i)
		var v: PoolVector3Array = a[Mesh.ARRAY_VERTEX]
		for k in range(v.size()):
			v[k] = Vector3(-v[k].x, v[k].y, v[k].z)
		a[Mesh.ARRAY_VERTEX] = v
		if a[Mesh.ARRAY_NORMAL] != null:
			var n: PoolVector3Array = a[Mesh.ARRAY_NORMAL]
			for k in range(n.size()):
				n[k] = Vector3(-n[k].x, n[k].y, n[k].z)
			a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TANGENT] = null
		var idx = a[Mesh.ARRAY_INDEX]
		if idx == null or idx.size() == 0:
			idx = PoolIntArray()
			for k in range(v.size()):
				idx.append(k)
		for k in range(0, idx.size() - 2, 3):
			var t = idx[k + 1]
			idx[k + 1] = idx[k + 2]
			idx[k + 2] = t
		a[Mesh.ARRAY_INDEX] = idx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.surface_set_material(i, m.surface_get_material(i))
	return out
