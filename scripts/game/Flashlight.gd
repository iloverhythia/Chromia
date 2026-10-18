extends CanvasLayer
# Flashlight mod: everything is black except a soft circle around the cursor.
# Added by Game.gd when Rhythia.mod_flashlight is on. Hidden while paused or
# giving up, so the pause / give-up screens stay readable.

const RADIUS := 0.95     # circle radius, in grid units (the grid is 3 wide)
const SOFTNESS := 0.45  # width of the soft edge, as a fraction of the radius

const SHADER := """
shader_type canvas_item;
uniform vec2 center;
uniform vec2 size;
uniform float radius;
uniform float softness;
void fragment() {
	float d = length(UV * size - center);
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(radius, radius + softness, d));
}
"""

var rect: ColorRect
var mat: ShaderMaterial
var cursor: Spatial
var spawn: Node

func setup(cursor_node: Spatial, spawn_node: Node):
	cursor = cursor_node
	spawn = spawn_node

func _ready():
	layer = 1
	rect = ColorRect.new()
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	add_child(rect)

func _process(_delta):
	var cam := get_viewport().get_camera()
	if cam == null or cursor == null or not is_instance_valid(cursor):
		return
	var paused: bool = spawn != null and is_instance_valid(spawn) and float(spawn.get("pause_state")) != 0.0
	var giving_up: bool = Input.is_action_pressed("give_up")
	rect.visible = not (paused or giving_up)
	if not rect.visible:
		return
	var p: Vector3 = cursor.global_transform.origin
	if cam.is_position_behind(p):
		return
	var c := cam.unproject_position(p)
	# Radius on screen: project a point RADIUS grid units to the side.
	# (grid units are the note area's own units, so use its x axis and scale)
	var axis: Vector3 = spawn.global_transform.basis.x if spawn is Spatial else Vector3.RIGHT
	var side := cam.unproject_position(p + axis * RADIUS)
	var r: float = max(c.distance_to(side), 8.0)
	mat.set_shader_param("center", c)
	mat.set_shader_param("size", rect.rect_size)
	mat.set_shader_param("radius", r)
	mat.set_shader_param("softness", r * SOFTNESS)
