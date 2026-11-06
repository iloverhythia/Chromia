extends MultiMeshInstance

# The cursor's smart trail, drawn as one MultiMesh: every piece of the trail
# is an instance of the trail mesh with its own place, turn, colour and size,
# set here each frame. It used to be one node (with its own material) per
# piece, made as the cursor moved: up to 120 new ones in a frame, hundreds
# alive at once. That stuttered on PC and crashed the game in VR (Quest).
# Looks the same as before (CursorTrail.gd start_smart / update): each piece
# fades and / or shrinks over Trail Time, with the trail gradient if it's on.

const MAX_PIECES := 4096 # (a high Trail Detail with fast phone swipes filled 1024)
const TrailGradient = preload("res://scripts/game/TrailGradient.gd")

var _pos := [] # Vector3, local to this node
var _rot := [] # Vector3 (the cursor mesh's rotation when the piece was made)
var _col := [] # Color (the cursor's colour then, alpha x Trail Opacity)
var _t := [] # 1 -> 0 over Trail Time
var _head := 0 # the oldest piece
var _count := 0
var _lut: PoolColorArray
var _grad := false
var _grad_max := 0

static func make(trail_base: Spatial) -> MultiMeshInstance:
	var mi: MeshInstance = trail_base.get_node("Mesh")
	var tm = load("res://scripts/game/TrailMulti.gd").new()
	tm.name = "TrailMulti"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_FLOAT
	mm.mesh = mi.mesh
	mm.instance_count = MAX_PIECES
	mm.visible_instance_count = 0
	tm.multimesh = mm
	tm.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	# one material: drawn over the grid like the cursor (no depth test), just
	# under it, coloured per piece
	var src = mi.get("material/0")
	var mat: SpatialMaterial = src.duplicate() if src is SpatialMaterial else SpatialMaterial.new()
	mat.flags_no_depth_test = true
	mat.render_priority = 98
	mat.flags_transparent = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	tm.material_override = mat
	tm._grad = bool(Rhythia.trail_gradient_enabled)
	if tm._grad:
		tm._lut = TrailGradient.build_lut(Rhythia.trail_gradient)
		tm._grad_max = tm._lut.size() - 1
		tm._grad = tm._grad_max >= 0
	for i in MAX_PIECES:
		tm._pos.append(Vector3())
		tm._rot.append(Vector3())
		tm._col.append(Color())
		tm._t.append(0.0)
	return tm

# a new piece at a global position (t0: how far into its life it starts, 0..1)
func add(global_pos: Vector3, rot: Vector3, col: Color, t0: float):
	if not is_inside_tree():
		return
	var i: int
	if _count < MAX_PIECES:
		i = (_head + _count) % MAX_PIECES
		_count += 1
	else:
		i = _head # (full: the oldest goes)
		_head = (_head + 1) % MAX_PIECES
	_pos[i] = to_local(global_pos)
	_rot[i] = rot
	_col[i] = col
	_t[i] = 1.0 - t0

func live() -> int:
	return _count

func _process(delta: float):
	var tt: float = max(0.001, float(Rhythia.trail_time))
	var dt: float = delta / tt
	# the old ones are gone first
	while _count > 0 and _t[_head] - dt <= 0.0:
		_head = (_head + 1) % MAX_PIECES
		_count -= 1
	var mm := multimesh
	var cs: float = float(Rhythia.cursor_scale)
	var mode_op: bool = Rhythia.trail_mode_opacity
	var mode_sc: bool = Rhythia.trail_mode_scale
	var op: float = float(Rhythia.trail_opacity)
	for k in _count:
		var i: int = (_head + k) % MAX_PIECES
		var t: float = _t[i] - dt
		_t[i] = t
		var a: float = clamp(t, 0.0, 1.0)
		var c: Color = _col[i]
		var alpha: float = (a * 0.6 * op) if mode_op else c.a
		if _grad:
			var g: Color = _lut[int(clamp(1.0 - t, 0.0, 1.0) * _grad_max)]
			c = Color(g.r, g.g, g.b, alpha * g.a)
		else:
			c = Color(c.r, c.g, c.b, alpha)
		var s: float = (a * cs) if mode_sc else cs
		var b := Basis(_rot[i]) * Basis().scaled(Vector3(s, 1, s))
		mm.set_instance_transform(k, Transform(b, _pos[i]))
		mm.set_instance_color(k, c)
	mm.visible_instance_count = _count
