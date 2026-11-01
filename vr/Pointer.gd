extends RayCast

# The pointer beam. It ends where the ray hits, or (in songs with an aim
# sensitivity other than 1, NoteManager.do_vr_cursor) bends to end on the
# cursor, set each frame with set_target.
#
# With the pointer locked to the grid (Settings > VR > Pointer) there are two
# beams, like Roblox Rhythia's VR: the normal one goes to the cursor and stays
# on the grid, and a thin one shows where the controller really points, past
# the grid's edges too.

const FREE_COLOR := Color(0.03, 0.17, 0.55) # the thin beam
const FREE_WIDTH := 0.3 # of the normal beam's thickness

var _target = null
var _target_frame := -10
var _show_free := false
var _free: MeshInstance = null
var _beam_base = null # the beam's own rotation (a cylinder along -Z)
var start_gap := 0.0 # the beam starts this far along the ray (in front of a big hand)

func set_target(p, show_free := false):
	_target = p
	_show_free = show_free and p != null
	_target_frame = Engine.get_frames_drawn()

func update_beam():
	var beam: MeshInstance = $Beam
	if _beam_base == null:
		_beam_base = beam.transform.basis
	_style(beam)
	var targeted: bool = _target != null and Engine.get_frames_drawn() - _target_frame <= 2
	_update_free(targeted and _show_free and beam.visible)
	if targeted:
		var local: Vector3 = to_local(_target)
		var dist: float = local.length()
		if dist > 0.01:
			var a := Vector3(0, 0, -1)
			var b: Vector3 = local / dist
			var axis: Vector3 = a.cross(b)
			var r := Basis()
			if axis.length() > 0.00001:
				r = Basis(axis.normalized(), a.angle_to(b))
			var g: float = min(start_gap, dist * 0.5)
			beam.mesh.height = dist - g
			beam.transform = Transform(r * _beam_base, r.xform(Vector3(0, 0, -(dist + g) / 2.0)))
			return
	var dist: float = _ray_length()
	var g: float = min(start_gap, dist * 0.5)
	beam.mesh.height = dist - g
	beam.transform = Transform(_beam_base, Vector3(0, 0, -(dist + g) / 2.0))

func _ray_length() -> float:
	if is_colliding():
		return (get_collision_point() - global_transform.origin).length()
	return -cast_to.z

# the thin beam: straight along the ray, where the controller points
func _update_free(on: bool):
	if not on:
		if _free != null:
			_free.visible = false
		return
	if _free == null:
		_free = MeshInstance.new()
		var m := CylinderMesh.new()
		m.radial_segments = 8
		m.rings = 1
		_free.mesh = m
		var mat := SpatialMaterial.new()
		mat.flags_unshaded = true
		mat.albedo_color = FREE_COLOR
		_free.material_override = mat
		_free.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		add_child(_free)
	var m: CylinderMesh = _free.mesh
	var w: float = Rhythia.vr_beam_width * FREE_WIDTH
	m.top_radius = 0.003 * w
	m.bottom_radius = 0.01 * w
	var dist: float = _ray_length()
	var g: float = min(start_gap, dist * 0.5)
	m.height = dist - g
	_free.transform = Transform(_beam_base, Vector3(0, 0, -(dist + g) / 2.0))
	_free.visible = true

# Settings > VR > Pointer: thickness, colour or rainbow (both hands share the
# beam's mesh and material)
var _width_done := -1.0
func _style(beam: MeshInstance):
	var w: float = Rhythia.vr_beam_width
	if w != _width_done and beam.mesh is CylinderMesh:
		beam.mesh.top_radius = 0.003 * w
		beam.mesh.bottom_radius = 0.01 * w
		_width_done = w
	var mat = beam.get_surface_material(0)
	if mat is SpatialMaterial:
		var c: Color = Rhythia.vr_beam_color
		if Rhythia.vr_beam_rainbow:
			var a: float = c.a
			c = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.65, 1)
			c.a = a
		if mat.albedo_color != c:
			mat.albedo_color = c

func _process(_delta):
	var hidden: bool = bool(Rhythia.get("vr_hide_beam")) # (Settings > VR > Pointer)
	$Beam.visible = enabled and not hidden
	if _free != null and (not enabled or hidden):
		_free.visible = false
