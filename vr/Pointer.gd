extends RayCast

# The pointer beam. It ends where the ray hits, or (in songs with an aim
# sensitivity other than 1, NoteManager.do_vr_cursor) bends to end on the
# cursor, set each frame with set_target.

var _target = null
var _target_frame := -10
var _beam_base = null # the beam's own rotation (a cylinder along -Z)
var start_gap := 0.0 # the beam starts this far along the ray (in front of a big hand)

func set_target(p):
	_target = p
	_target_frame = Engine.get_frames_drawn()

func update_beam():
	var beam: MeshInstance = $Beam
	if _beam_base == null:
		_beam_base = beam.transform.basis
	_style(beam)
	if _target != null and Engine.get_frames_drawn() - _target_frame <= 2:
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
	var dist = -cast_to.z
	if is_colliding():
		dist = (get_collision_point() - global_transform.origin).length()
	var g: float = min(start_gap, dist * 0.5)
	beam.mesh.height = dist - g
	beam.transform = Transform(_beam_base, Vector3(0, 0, -(dist + g) / 2.0))

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
	$Beam.visible = enabled
