extends RayCast

# The pointer beam. It ends where the ray hits, or (in songs with an aim
# sensitivity other than 1, NoteManager.do_vr_cursor) bends to end on the
# cursor, set each frame with set_target.

var _target = null
var _target_frame := -10
var _beam_base = null # the beam's own rotation (a cylinder along -Z)

func set_target(p):
	_target = p
	_target_frame = Engine.get_frames_drawn()

func update_beam():
	var beam: MeshInstance = $Beam
	if _beam_base == null:
		_beam_base = beam.transform.basis
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
			beam.mesh.height = dist
			beam.transform = Transform(r * _beam_base, r.xform(Vector3(0, 0, -dist / 2.0)))
			return
	var dist = -cast_to.z
	if is_colliding():
		dist = (get_collision_point() - global_transform.origin).length()
	beam.mesh.height = dist
	beam.transform = Transform(_beam_base, Vector3(0, 0, -dist / 2.0))

func _process(_delta):
	$Beam.visible = enabled
