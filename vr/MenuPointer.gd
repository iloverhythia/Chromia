extends Area

# The VR menu screen: the normal menu drawn into Viewport and shown on a big
# curved screen around you (or a flat one), pointed at with the controller.
# Size, distance and curve are in Settings > VR (Rhythia.vr_menu_size /
# vr_menu_distance / vr_menu_curve); rebuild() applies them.
#
# The menu is laid out at 1280x720 like the window, but drawn at 1920x1080 so
# its text stays sharp on the big screen. last_screen_pos is in the layout's
# pixels (Rhythia.menu_mouse uses it); events go to the viewport in its real
# pixels (it scales them back).

onready var viewport: Viewport = get_node("Viewport")
export(Vector2) var size

var last_screen_pos: Vector2 = Vector2(0, 0)
var active: bool = false

const LAYOUT := Vector2(1280, 720)
const RENDER := Vector2(1920, 1080)
const UNITS_PER_M := 2.0 # the VR world scale
const SEGMENTS := 48
var _radius := 2.86   # game units; the curve's centre is where you stand
var _arc := 1.0       # radians the curved screen spans
var _curved := true
var _scroll_left := 0.0

func _px(p: Vector2) -> Vector2:
	return p * (viewport.size / LAYOUT)

# Builds the screen for the settings: its shape, what the pointer hits, and how
# far in front of you it is.
func rebuild():
	var dist: float = clamp(float(Rhythia.get("vr_menu_distance")), 0.8, 4.0) * UNITS_PER_M
	var deg: float = clamp(float(Rhythia.get("vr_menu_size")), 40.0, 160.0)
	_curved = bool(Rhythia.get("vr_menu_curve"))
	_radius = dist
	var w: float
	if _curved:
		_arc = deg2rad(deg)
		w = _radius * _arc
	else:
		w = 2.0 * dist * tan(deg2rad(min(deg, 130.0)) / 2.0)
	var h: float = w * LAYOUT.y / LAYOUT.x
	size = Vector2(w, h)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = SEGMENTS if _curved else 1
	for i in range(n):
		var u0: float = float(i) / n
		var u1: float = float(i + 1) / n
		var a := _edge(u0, w)
		var b := _edge(u1, w)
		var tl := Vector3(a.x, h / 2.0, a.y)
		var bl := Vector3(a.x, -h / 2.0, a.y)
		var tr := Vector3(b.x, h / 2.0, b.y)
		var br := Vector3(b.x, -h / 2.0, b.y)
		for v in [[tl, Vector2(u0, 0)], [tr, Vector2(u1, 0)], [br, Vector2(u1, 1)], [tl, Vector2(u0, 0)], [br, Vector2(u1, 1)], [bl, Vector2(u0, 1)]]:
			st.add_uv(v[1])
			st.add_normal(Vector3(0, 0, 1))
			st.add_vertex(v[0])
	var mesh: ArrayMesh = st.commit()
	var mat = $Screen.get_active_material(0)
	if mat is SpatialMaterial:
		mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	$Screen.mesh = mesh
	var shape := ConcavePolygonShape.new()
	shape.set_faces(mesh.get_faces())
	$CollisionShape.shape = shape
	$CollisionShape.transform = Transform()
	var t := transform
	t.origin.z = -dist
	transform = t
	if has_meta("home"):
		var home: Transform = get_meta("home")
		home.origin.z = -dist
		set_meta("home", home)

# x and z of the screen's edge at u (0 left .. 1 right); the screen's centre is
# at the origin, the curve's centre at z = radius.
func _edge(u: float, w: float) -> Vector2:
	if not _curved:
		return Vector2((u - 0.5) * w, 0.0)
	var a: float = (u - 0.5) * _arc
	return Vector2(_radius * sin(a), _radius * (1.0 - cos(a)))

# Where on the menu (0..1) a point on the screen is, and the angle there.
func _uv(lp: Vector3) -> Vector3:
	var u: float
	var ang := 0.0
	if _curved:
		ang = atan2(lp.x, _radius - lp.z)
		u = ang / _arc + 0.5
	else:
		u = lp.x / size.x + 0.5
	var v: float = 0.5 - lp.y / size.y
	return Vector3(clamp(u, 0, 1), clamp(v, 0, 1), ang)

# Thumbstick up / down scrolls whatever the pointer is on (map list, settings).
func _scroll(delta: float):
	var hand = Rhythia.vr_player.left_hand if Rhythia.vr_left_handed else Rhythia.vr_player.right_hand
	if hand == null or not hand.has_method("get_joystick_axis"):
		return
	scroll_by(hand.get_joystick_axis(1), delta)

func scroll_by(y: float, delta: float):
	if abs(y) < 0.25:
		_scroll_left = 0.0
		return
	# a wheel step about 12 times a second at full tilt, sooner the further you push
	_scroll_left -= delta * lerp(3.0, 12.0, (abs(y) - 0.25) / 0.75)
	if _scroll_left > 0.0:
		return
	_scroll_left = 1.0
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = _px(last_screen_pos)
		ev.global_position = ev.position
		ev.button_index = BUTTON_WHEEL_UP if y > 0 else BUTTON_WHEEL_DOWN
		ev.pressed = pressed
		ev.factor = 1.0
		viewport.input(ev)

func _input(event: InputEvent):
	if active:
		if event is InputEventKey:
			viewport.input(event)
		elif event is InputEventMouseButton:
			var e: InputEventMouseButton = event as InputEventMouseButton
			if e.pressed:
				Rhythia.trail("VR click at %s" % last_screen_pos)
			var ev: InputEventMouseButton = InputEventMouseButton.new()
			ev.position = _px(last_screen_pos)
			ev.button_index = e.button_index
			ev.button_mask = e.button_mask
			ev.pressed = e.is_pressed()
			viewport.input(ev)
		elif event is InputEventJoypadButton and (event as InputEventJoypadButton):
			var e: InputEventJoypadButton = event
			if Rhythia.vr_bind("vr_click").has(e.button_index):
				if e.pressed:
					Rhythia.trail("VR trigger at %s" % last_screen_pos)
				var ev: InputEventMouseButton = InputEventMouseButton.new()
				ev.position = _px(last_screen_pos)
				ev.button_index = BUTTON_LEFT
				ev.button_mask = BUTTON_MASK_LEFT
				ev.pressed = event.is_pressed()
				viewport.input(ev)

func _process(delta):
	active = (Rhythia.vr_player.primary_ray.is_colliding() and (Rhythia.vr_player.primary_ray.get_collider() == self))
	if active:

		var p = Rhythia.vr_player.primary_ray.get_collision_point()

		var lp3 = global_transform.xform_inv(p)
		var uv := _uv(lp3)
		var screen_pos = Vector2(round(uv.x * LAYOUT.x), round(uv.y * LAYOUT.y))
		if screen_pos != last_screen_pos:
			var ev: InputEventMouseMotion = InputEventMouseMotion.new()
			var relative = _px(screen_pos - last_screen_pos)
			ev.relative = relative
			ev.speed = relative / delta
			ev.pressure = Input.get_action_raw_strength("vr_click")
			ev.position = _px(screen_pos)
			ev.global_position = ev.position

			viewport.input(ev)
			last_screen_pos = screen_pos
		_scroll(delta)

		# the dot lies on the screen, facing you, just in front of it
		var face: Basis = global_transform.basis * Basis(Vector3.UP, -uv.z)
		$Pointer.global_transform = Transform(face.orthonormalized(), p + face.z.normalized() * 0.004)
		$PointerTrail.global_transform = $Pointer.global_transform
		$Pointer.visible = true
		$PointerTrail.emitting = Rhythia.cursor_trail
		$Pointer.scale = Vector3(Rhythia.cursor_scale, Rhythia.cursor_scale, Rhythia.cursor_scale) * 0.5
		var sc: CurveTexture = $PointerTrail.process_material.scale_curve
		sc.curve.set_point_value(0, Rhythia.cursor_scale * 0.5)

		var target_detail = Rhythia.trail_detail * (1 + float(Rhythia.smart_trail))
		if $PointerTrail.amount != target_detail or $PointerTrail.lifetime != Rhythia.trail_time:
			$PointerTrail.amount = target_detail
			$PointerTrail.lifetime = Rhythia.trail_time

		if Rhythia.cursor_color_type == Globals.CURSOR_RAINBOW:
			$Pointer.mesh.material.albedo_color = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.65, 1)
			$PointerTrail.draw_pass_1.material.albedo_color = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.65, 1)
		else:
			$Pointer.mesh.material.albedo_color = Rhythia.cursor_color
			$PointerTrail.draw_pass_1.material.albedo_color = Rhythia.cursor_color
	else:
		$Pointer.visible = false
		$PointerTrail.emitting = false

func _ready():
	# the menu screen keeps its own "input handled" state: with the main
	# window's, a click or pointer move was dropped whenever something on the
	# window had used the last event
	viewport.handle_input_locally = true
	# laid out like the window, drawn sharper
	viewport.size = RENDER
	viewport.set_size_override(true, LAYOUT)
	viewport.size_override_stretch = true
	rebuild()
	var img = Globals.imageLoader.load_if_exists("user://cursor")
	if img: $Pointer.mesh.material.albedo_texture = img

	var img2 = Globals.imageLoader.load_if_exists("user://trail")
	if img2: $PointerTrail.draw_pass_1.material.albedo_texture = img2
	elif img: $PointerTrail.draw_pass_1.material.albedo_texture = img
	get_node("Viewport/Menu/Main/Maps/Filters").visible = false
