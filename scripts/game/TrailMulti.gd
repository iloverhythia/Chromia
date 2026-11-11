extends MultiMeshInstance

# The cursor's smart trail, drawn as one MultiMesh: every piece of the trail
# is an instance of the trail mesh with its own place, turn, colour and size,
# set here each frame. It used to be one node (with its own material) per
# piece, made as the cursor moved: up to 120 new ones in a frame, hundreds
# alive at once. That stuttered on PC and crashed the game in VR (Quest).
# Looks the same as before (CursorTrail.gd start_smart / update): each piece
# fades and / or shrinks over Trail Time, with the trail gradient if it's on.
#
# On phones the per-piece work each frame was the cost (hundreds to thousands
# of pieces aged, sized and coloured one by one in script, 60 to 120 times a
# second), and with the trail on the cursor felt laggy. With the GLES3
# renderer the pieces now age on the graphics card: a piece is written once,
# when it's made (its place, turn, colour and the moment it was made), and a
# small shader works out its fade, size and gradient colour from the clock.
# A frame costs the new pieces only. The classic trail (Smart Trail off) is
# drawn this way too: its N pieces are N slots of the same MultiMesh instead
# of N nodes with a script and a material each. GLES2 keeps the old ways.

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

# --- on the graphics card (GLES3) ---
var gpu := false
var classic := false # the classic trail's slots (stamp()), not the smart trail's stream (add())
var _now := 0.0 # the pieces' clock, seconds
var _next := 0 # smart: the slot the next piece takes
var _high := 0 # smart: slots in use
var _last_add := -1000.0
var _mat: ShaderMaterial = null
var _shown := -1

# (%s: how the pieces write depth. As the trail's material always did on
# computers; never on a headset or a phone, where that second pass over every
# piece, for each eye, is work with nothing to show for it: the trail is
# drawn over everything, without a depth test.)
const SHADER := """shader_type spatial;
render_mode blend_mix, %s, cull_back, unshaded, depth_test_disable, shadows_disabled, ambient_light_disabled;
uniform sampler2D tex : hint_albedo;
uniform sampler2D grad;
uniform float now = 0.0;
uniform float life = 0.15;
uniform float fade = 1.0;
uniform float shrink = 1.0;
uniform float opacity = 1.0;
uniform float grow = 0.0;
uniform float use_grad = 0.0;
uniform float srgb_in = 0.0;
varying vec4 tint;
void vertex() {
	// how far through its life this piece is
	float x = (now - INSTANCE_CUSTOM.x) / life;
	if (x < 0.0 || x >= 1.0) {
		VERTEX = vec3(0.0);
		tint = vec4(0.0);
	} else {
		// smart: fades / shrinks away; classic: comes in, then is moved on
		float a = clamp(mix(1.0 - x, x - 0.2, grow), 0.0, 1.0);
		float s = mix(1.0, a, shrink);
		VERTEX.x *= s;
		VERTEX.z *= s;
		vec4 c = COLOR;
		float alpha = mix(c.a, a * 0.6 * opacity, fade);
		if (use_grad > 0.5) {
			vec4 g = textureLod(grad, vec2(clamp(x, 0.0, 0.999), 0.5), 0.0);
			c.rgb = g.rgb;
			alpha *= g.a;
		}
		if (srgb_in > 0.5) {
			c.rgb = mix(pow((c.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c.rgb * (1.0 / 12.92), lessThan(c.rgb, vec3(0.04045)));
		}
		tint = vec4(c.rgb, alpha);
	}
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * tint.rgb;
	ALPHA = t.a * tint.a;
}
"""

# slots: the classic trail's number of pieces (0: the smart trail)
static func make(trail_base: Spatial, slots: int = 0, in_script: bool = false) -> MultiMeshInstance:
	var mi: MeshInstance = trail_base.get_node("Mesh")
	var tm = load("res://scripts/game/TrailMulti.gd").new()
	tm.name = "TrailMulti"
	# (in_script: the old way on purpose, to compare the two)
	tm.gpu = OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES3 and not in_script
	tm.classic = slots > 0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_FLOAT
	if tm.gpu:
		mm.custom_data_format = MultiMesh.CUSTOM_DATA_FLOAT
	mm.mesh = mi.mesh
	if tm.gpu and light():
		tm._cap = 2048
	mm.instance_count = min(slots, MAX_PIECES) if slots > 0 else (tm._cap if tm.gpu else MAX_PIECES)
	mm.visible_instance_count = 0
	tm.multimesh = mm
	tm.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var src = mi.get("material/0")
	tm._grad = bool(Rhythia.trail_gradient_enabled)
	if tm._grad:
		tm._lut = TrailGradient.build_lut(Rhythia.trail_gradient)
		tm._grad_max = tm._lut.size() - 1
		tm._grad = tm._grad_max >= 0
	if tm.gpu:
		tm._make_gpu(src)
		return tm
	# one material: drawn over the grid like the cursor (no depth test), just
	# under it, coloured per piece
	var mat: SpatialMaterial = src.duplicate() if src is SpatialMaterial else SpatialMaterial.new()
	mat.flags_no_depth_test = true
	mat.render_priority = 98
	mat.flags_transparent = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	tm.material_override = mat
	for i in MAX_PIECES:
		tm._pos.append(Vector3())
		tm._rot.append(Vector3())
		tm._col.append(Color())
		tm._t.append(0.0)
	return tm

# a headset or a phone: less to upload and draw (see _cap and the shader)
static func light() -> bool:
	return bool(Rhythia.vr) or Rhythia.device("mobile")

var _cap := MAX_PIECES # smart: slots in the ring (2048 on a headset or a phone: the whole list goes to the graphics card every frame a piece is made)

func _make_gpu(src):
	# One Shader for every song of the session. A new one each song was
	# compiled again each time, on the first piece drawn: a stall at the start
	# of every song, worst on a headset.
	var key: String = "trail_shader_light" if light() else "trail_shader"
	var sh: Shader = Engine.get_meta(key) if Engine.has_meta(key) else null
	if sh == null:
		sh = Shader.new()
		sh.code = SHADER % ("depth_draw_never" if light() else "depth_draw_alpha_prepass")
		Engine.set_meta(key, sh)
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = 98
	if src is SpatialMaterial and src.albedo_texture != null:
		_mat.set_shader_param("tex", src.albedo_texture)
	else:
		var white := Image.new()
		white.create(2, 2, false, Image.FORMAT_RGBA8)
		white.fill(Color(1, 1, 1, 1))
		var wt := ImageTexture.new()
		wt.create_from_image(white, 0)
		_mat.set_shader_param("tex", wt)
	if _grad:
		# the gradient's table as a strip of pixels, read by age
		var img := Image.new()
		img.create(_lut.size(), 1, false, Image.FORMAT_RGBAF)
		img.lock()
		for i in _lut.size():
			img.set_pixel(i, 0, _lut[i])
		img.unlock()
		var gt := ImageTexture.new()
		gt.create_from_image(img, 0) # (no filter: the same steps as the table)
		_mat.set_shader_param("grad", gt)
	_mat.set_shader_param("use_grad", 1.0 if _grad else 0.0)
	_mat.set_shader_param("grow", 1.0 if classic else 0.0)
	# (the pieces' colours are the cursor's colour, an sRGB colour like any
	# colour picked on screen: read as one, the trail is the cursor's own
	# colour. Used as they were, the smart trail came out paler than the
	# cursor: a pink cursor had a whitish trail.)
	_mat.set_shader_param("srgb_in", 1.0)
	material_override = _mat
	# (pieces are anywhere on the grid: no working out their bounds every frame)
	set_custom_aabb(AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80)))
	if classic:
		for i in multimesh.instance_count:
			multimesh.set_instance_custom_data(i, Color(-1000000.0, 0, 0, 0))
		multimesh.visible_instance_count = multimesh.instance_count

# The classic trail: slot i is put down again (where the cursor was `born_ago`
# seconds before this frame is drawn; show = false leaves it out, as when the
# cursor hasn't moved since this slot's last place).
func stamp(i: int, global_pos: Vector3, rot: Vector3, col: Color, born_ago: float, show: bool):
	if not is_inside_tree() or i < 0 or i >= multimesh.instance_count:
		return
	if not show:
		multimesh.set_instance_custom_data(i, Color(-1000000.0, 0, 0, 0))
		return
	var cs: float = float(Rhythia.cursor_scale)
	multimesh.set_instance_transform(i, Transform(Basis(rot) * Basis().scaled(Vector3(cs, 1, cs)), to_local(global_pos)))
	multimesh.set_instance_color(i, col)
	multimesh.set_instance_custom_data(i, Color(_now + _frame_ahead - born_ago, 0, 0, 0))

# (the clock moves on by this much before the pieces put down now are drawn)
var _frame_ahead := 0.0
func begin_frame(delta: float):
	_frame_ahead = delta

# a new piece at a global position (t0: how far into its life it starts, 0..1)
func add(global_pos: Vector3, rot: Vector3, col: Color, t0: float):
	if not is_inside_tree():
		return
	if gpu:
		var j := _next
		_next = (_next + 1) % _cap
		if j + 1 > _high:
			_high = j + 1
		var cs: float = float(Rhythia.cursor_scale)
		var tt: float = max(0.001, float(Rhythia.trail_time))
		multimesh.set_instance_transform(j, Transform(Basis(rot) * Basis().scaled(Vector3(cs, 1, cs)), to_local(global_pos)))
		multimesh.set_instance_color(j, col)
		multimesh.set_instance_custom_data(j, Color(_now - t0 * tt, 0, 0, 0))
		_last_add = _now
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
	return _high if gpu else _count

func _process(delta: float):
	var tt: float = max(0.001, float(Rhythia.trail_time))
	if gpu:
		_now += delta
		_frame_ahead = 0.0
		_mat.set_shader_param("now", _now)
		_mat.set_shader_param("life", tt)
		_mat.set_shader_param("fade", 1.0 if Rhythia.trail_mode_opacity else 0.0)
		_mat.set_shader_param("shrink", 1.0 if Rhythia.trail_mode_scale else 0.0)
		_mat.set_shader_param("opacity", float(Rhythia.trail_opacity))
		if not classic:
			# (nothing left of the last movement: the next one starts at the first slot,
			# so only what's in use is drawn)
			if _high > 0 and _now - _last_add > tt + 0.05:
				_next = 0
				_high = 0
			if _shown != _high:
				_shown = _high
				multimesh.visible_instance_count = _high
		return
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
