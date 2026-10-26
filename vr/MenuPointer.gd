extends Area

# The VR menu screen: the normal menu drawn into Viewport and shown on a big
# curved screen around you (or a flat one), pointed at with the controller.
# Size, distance and curve are in Settings > VR (Rhythia.vr_menu_size /
# vr_menu_distance / vr_menu_curve); rebuild() applies them.
#
# The menu is laid out like a 1600x900 window (sized by Settings > VR > Text
# and buttons: smaller text = a bigger layout, so more fits), but drawn at
# 1920x1080 or more so its text stays sharp on the big screen. last_screen_pos
# is in the layout's pixels (Rhythia.menu_mouse uses it), and so are the events
# sent to the viewport: Viewport.input() takes them as they are (only events
# coming through a ViewportContainer get scaled), so sending drawn pixels put
# every click further right and lower than the pointer.
#
# The icon in the screen's bottom right corner (MenuResize.gd) resizes it: drag
# it to make the screen bigger or smaller, tap it for the size buttons.

onready var viewport: Viewport = get_node("Viewport")
export(Vector2) var size

var last_screen_pos: Vector2 = Vector2(0, 0)
var active: bool = false

const BASE_LAYOUT := Vector2(1600, 900) # at 100 % text size
const MIN_RENDER := Vector2(1920, 1080)
var LAYOUT := BASE_LAYOUT
const UNITS_PER_M := 2.0 # the VR world scale
const SEGMENTS := 48
var _radius := 2.86   # game units; the curve's centre is where you stand
var _arc := 1.0       # radians the curved screen spans
var _curved := true
var _scroll_left := 0.0
var _scroll_carry := 0.0
var _scroll_target = null
var _scroll_target_ms := 0
var _resize = null # [start width, start pointer width, start time] while dragging the corner icon
var _resize_moved := false
var _resize_icon = null

# Lays the menu out for the text size setting (and draws it at least 1920x1080).
func apply_layout():
	var pct: float = clamp(float(Rhythia.get("vr_menu_ui")), 60.0, 140.0)
	var lay := (BASE_LAYOUT * 100.0 / pct).round()
	var render := Vector2(max(lay.x, MIN_RENDER.x), max(lay.y, MIN_RENDER.y))
	if lay == LAYOUT and viewport.size == render:
		return
	LAYOUT = lay
	viewport.size = render
	viewport.set_size_override(true, LAYOUT)
	viewport.size_override_stretch = true
	last_screen_pos = LAYOUT / 2

func _px(p: Vector2) -> Vector2:
	return p # events go in layout pixels (see the top)

# Builds the screen for the settings: its shape, what the pointer hits, and how
# far in front of you it is.
func rebuild():
	apply_layout()
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

# Thumbstick up / down (either hand) scrolls whatever the pointer is on: the
# settings pages and other scrolling boxes are moved directly (a mouse wheel
# over a number box or slider would change its value instead), anything else
# (the map list) gets mouse wheel steps.
func _scroll(delta: float):
	var y := 0.0
	for hand in [Rhythia.vr_player.left_hand, Rhythia.vr_player.right_hand]:
		if hand != null and hand.has_method("get_joystick_axis"):
			var v: float = hand.get_joystick_axis(1)
			if abs(v) > abs(y):
				y = v
	scroll_by(y, delta)

func scroll_by(y: float, delta: float):
	if abs(y) < 0.25:
		_scroll_left = 0.0
		_scroll_carry = 0.0
		_scroll_target = null
		return
	var t: float = (abs(y) - 0.25) / 0.75
	var now := OS.get_ticks_msec()
	if _scroll_target == null or not is_instance_valid(_scroll_target) or now - _scroll_target_ms > 300:
		_scroll_target = _scroll_box_at(last_screen_pos)
		_scroll_target_ms = now
	if _scroll_target != null and is_instance_valid(_scroll_target):
		# about 1 to 5 screens a second, faster the further you push
		_scroll_carry += delta * lerp(250.0, 1400.0, t * t) * (LAYOUT.y / 720.0) * (-1.0 if y > 0 else 1.0)
		var step := int(_scroll_carry)
		if step != 0:
			_scroll_carry -= step
			_scroll_target.scroll_vertical += step
		return
	# a wheel step about 12 times a second at full tilt, sooner the further you push
	_scroll_left -= delta * lerp(3.0, 12.0, t)
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

# The innermost (topmost) scroll box under a point of the menu (layout pixels)
# that has something to scroll.
func _scroll_box_at(p: Vector2):
	var found = [null]
	_find_scroll(viewport, p, found)
	return found[0]

func _find_scroll(n: Node, p: Vector2, found: Array):
	if n is CanvasItem and not n.visible:
		return
	if n is ScrollContainer and n.get_global_rect().has_point(p):
		var bar: VScrollBar = n.get_v_scrollbar()
		if n.scroll_vertical_enabled and bar.max_value - bar.page > 1.0:
			found[0] = n
	for c in n.get_children():
		if c is Viewport:
			continue
		_find_scroll(c, p, found)

# --- Resizing from the corner icon -------------------------------------------

# Where the pointer ray meets the screen's (endless) surface, as the width the
# screen would need for its bottom right corner to be there.
func _pointer_width():
	var ray: RayCast = Rhythia.vr_player.primary_ray
	var from: Vector3 = global_transform.xform_inv(ray.global_transform.origin)
	var dir: Vector3 = (global_transform.basis.inverse() * ray.global_transform.basis.xform(ray.cast_to)).normalized()
	var hit = null
	if _curved:
		# cylinder around (0, y, radius), the screen's curve
		var o := Vector2(from.x, from.z - _radius)
		var d := Vector2(dir.x, dir.z)
		var a: float = d.dot(d)
		var b: float = 2.0 * o.dot(d)
		var c: float = o.dot(o) - _radius * _radius
		var disc: float = b * b - 4.0 * a * c
		if a < 1e-6 or disc < 0.0:
			return null
		var tt: float = (-b - sqrt(disc)) / (2.0 * a)
		if tt < 0.0:
			tt = (-b + sqrt(disc)) / (2.0 * a)
		if tt < 0.0:
			return null
		hit = from + dir * tt
		var ang: float = atan2(hit.x, _radius - hit.z)
		var wx: float = 2.0 * abs(ang) * _radius
		var wy: float = 2.0 * abs(hit.y) * LAYOUT.x / LAYOUT.y
		return (wx + wy) / 2.0
	if abs(dir.z) < 1e-6:
		return null
	var tf: float = -from.z / dir.z
	if tf < 0.0:
		return null
	hit = from + dir * tf
	return (2.0 * abs(hit.x) + 2.0 * abs(hit.y) * LAYOUT.x / LAYOUT.y) / 2.0

func begin_resize(icon):
	_resize_icon = icon
	var pw = _pointer_width()
	if pw == null or pw < 0.01:
		return
	_resize = [size.x, pw, OS.get_ticks_msec()]
	_resize_moved = false

func _drag_resize():
	if _resize == null:
		return
	var held: bool = Input.is_action_pressed("vr_click") or Input.is_mouse_button_pressed(BUTTON_LEFT)
	if not held:
		var tapped: bool = not _resize_moved and OS.get_ticks_msec() - int(_resize[2]) < 600
		_resize = null
		if _resize_moved:
			Rhythia.save_settings()
		elif tapped and is_instance_valid(_resize_icon):
			_resize_icon.toggle_panel()
		return
	var pw = _pointer_width()
	if pw == null:
		return
	var w: float = float(_resize[0]) * pw / float(_resize[1])
	var deg: float
	if _curved:
		deg = rad2deg(w / _radius)
	else:
		deg = rad2deg(2.0 * atan(w / (2.0 * _radius)))
	deg = clamp(deg, 40.0, 160.0)
	if abs(deg - float(Rhythia.vr_menu_size)) >= 0.5:
		if abs(deg - float(Rhythia.vr_menu_size)) >= 1.5:
			_resize_moved = true
		if _resize_moved:
			Rhythia.vr_menu_size = deg
			rebuild()

func _input(event: InputEvent):
	# a release always reaches the menu (also when the pointer left the screen
	# while dragging), or what was held would stay pressed
	var release: bool = (event is InputEventMouseButton or event is InputEventJoypadButton) and not event.is_pressed()
	if active or release:
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
	_drag_resize()
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
	# laid out like a window, drawn sharper
	LAYOUT = Vector2.ZERO
	rebuild()
	var icon = load("res://vr/MenuResize.gd").new()
	icon.name = "MenuResize"
	icon.screen = self
	viewport.add_child(icon)
	# on top of the menu, under the boxes and keyboard moved here later
	viewport.move_child(icon, viewport.get_node("Menu").get_index() + 1)
	var img = Globals.imageLoader.load_if_exists("user://cursor")
	if img: $Pointer.mesh.material.albedo_texture = img

	var img2 = Globals.imageLoader.load_if_exists("user://trail")
	if img2: $PointerTrail.draw_pass_1.material.albedo_texture = img2
	elif img: $PointerTrail.draw_pass_1.material.albedo_texture = img
