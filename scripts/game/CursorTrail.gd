extends Spatial

signal cache_me

export(float) var offset = 0

var started:bool = false
var t:float = 0

onready var cursor = get_node("../Spawn/Cursor")
onready var cursormesh = get_node("../Spawn/Cursor/Mesh")

var last_origin = Vector3(-100,0,0)
var before
var can_reuse:bool = false
var transp_multi = 1

# Trail gradient (Rhythia.trail_gradient_enabled): colour looked up per frame from a
# small precomputed table, shared between all trail segments of the song.
const TrailGradient = preload("res://scripts/game/TrailGradient.gd")
var use_grad: bool = false
var grad_lut: PoolColorArray
var grad_max: int = 0
var base_alpha: float = 1.0
var grad_mat: SpatialMaterial

func _grad_apply(age: float, alpha: float):
	var c: Color = grad_lut[int(clamp(age, 0.0, 1.0) * grad_max)]
	grad_mat.albedo_color = Color(c.r, c.g, c.b, alpha * c.a)


func respawn(t_override=null,rot=0):
	if t_override:
		visible = true
		global_transform.origin = t_override
		$Mesh.rotation_degrees.x = rot
	else:
		var here: Vector3 = cursor.global_transform.origin - Vector3(0,0,0.001)
		visible = here != last_origin # nothing piles up where the cursor stands still
		last_origin = here
		global_transform.origin = here
		if Input.is_key_pressed(KEY_V):
			global_transform.origin = Vector3((offset*3)-1.5,(offset*3)-1.5,-0.2)
	
	var col: Color = cursormesh.get("material/0").albedo_color
	col.a *= Rhythia.trail_opacity
	base_alpha = col.a
	if use_grad:
		var gc: Color = grad_lut[0]
		col = Color(gc.r, gc.g, gc.b, col.a * gc.a)
	$Mesh.get("material/0").albedo_color = col
	$Mesh.rotation = cursormesh.rotation

func upd_dumb(delta):
	if !Rhythia.smart_trail:
		t += (delta/Rhythia.trail_time)
	var a = clamp((t - 0.2),0,1)
	if use_grad:
		_grad_apply(t, (a * 0.6 * transp_multi * Rhythia.trail_opacity) if Rhythia.trail_mode_opacity else base_alpha)
	elif Rhythia.trail_mode_opacity:
		$Mesh.get("material/0").albedo_color.a = a * 0.6 * transp_multi * Rhythia.trail_opacity
	if Rhythia.trail_mode_scale:
		$Mesh.scale = Vector3(a*Rhythia.cursor_scale,1,a*Rhythia.cursor_scale)
	if !Rhythia.smart_trail and t >= 1:
		t -= 1
		respawn()

func update(delta):
	t -= (delta/Rhythia.trail_time)
	var a = clamp((t),0,1)
	if use_grad:
		_grad_apply(1.0 - t, (a * 0.6 * transp_multi * Rhythia.trail_opacity) if Rhythia.trail_mode_opacity else base_alpha)
	elif Rhythia.trail_mode_opacity:
		$Mesh.get("material/0").albedo_color.a = a * 0.6 * transp_multi * Rhythia.trail_opacity
	if Rhythia.trail_mode_scale:
		$Mesh.scale = Vector3(a*Rhythia.cursor_scale,1,a*Rhythia.cursor_scale)
	if t <= 0:
		started = false
		visible = false
		emit_signal("cache_me")

func _process(delta):
	if started:
		if Rhythia.smart_trail: update(delta)
		else: upd_dumb(delta)

var init_done:bool = false
func init():
	if init_done: return
	init_done = true
	var mat:SpatialMaterial = $Mesh.get("material/0").duplicate()
	# Drawn over the grid like the cursor is (no depth test), just under it.
	# With the depth test, phones (less depth precision) hid the trail
	# behind the grid it sits on, and the grid frame was drawn over it.
	mat.flags_no_depth_test = true
	mat.render_priority = 98
	$Mesh.scale = Vector3(0,1,0)
	if not Rhythia.trail_mode_scale:
		$Mesh.scale = Vector3(Rhythia.cursor_scale,1,Rhythia.cursor_scale)
	$Mesh.set("material/0",mat)
	grad_mat = mat
	use_grad = Rhythia.trail_gradient_enabled
	if use_grad:
		# one table per song: stored on the shared parent (Game) so segments reuse it
		var p = get_parent()
		if p != null and p.has_meta("trail_grad_lut"):
			grad_lut = p.get_meta("trail_grad_lut")
		else:
			grad_lut = TrailGradient.build_lut(Rhythia.trail_gradient)
			if p != null: p.set_meta("trail_grad_lut", grad_lut)
		grad_max = grad_lut.size() - 1
		if grad_max < 0: use_grad = false

func start():
	init()
	t = -offset
	started = true


func start_smart(v:float,pos:Vector3,rot:float):
	init()
	started = true
	t = 1 - v
	respawn(pos,rot)
