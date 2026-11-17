extends CanvasLayer
# Flashlight mod: everything is black except a soft circle around the cursor.
# Added by Game.gd when Flashlight or True Flashlight is on.
#
# The circle is the same size on the screen whatever FOV you play with: what
# it had at the default FOV of 70 (SCREEN_SHARE of the screen's height). It
# used to be a set piece of the grid, so it shrank and grew with the FOV. It
# never lights more of the grid than it did, though: at a high FOV the grid
# is small on the screen and a circle of that size would light all of it,
# which is no Flashlight, so there it follows the grid as before.
#
# True Flashlight: the circle closes in as the combo grows, 1.2 times
# narrower every 100 combo up to TRUE_STEPS times; a miss opens it again.
#
# The darkness used to lift while the give up key (R) was held, so a tap of
# it showed every note. It stays now. It still lifts while the song is
# paused, so the pause screen can be read, but the notes are hidden then
# (NoteManager.set_notes_hidden), and it is back for the countdown after it.

const RADIUS := 0.95     # the most the circle lights, in grid units (the grid is 3 wide)
const SCREEN_SHARE := 0.1809 # the circle's radius as a share of the screen's height (RADIUS at FOV 70)
const SOFTNESS := 0.45  # width of the soft edge, as a fraction of the radius
const TRUE_AMP := 1.2    # True Flashlight: how much narrower per step
const TRUE_EVERY := 100  # combo per step
const TRUE_STEPS := 5
const GLIDE := 5.0       # how fast the circle takes a new size (per second)

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
var _amp := 1.0 # True Flashlight: how much narrower right now

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

# True Flashlight: 1.2 at 100 combo, 1.44 at 200 ... up to TRUE_STEPS steps
static func true_amp(combo: int) -> float:
	return pow(TRUE_AMP, clamp(combo / TRUE_EVERY, 0, TRUE_STEPS))

# the circle's radius in pixels: `grid_px` is RADIUS grid units on the screen
static func radius_px(grid_px: float, screen_h: float, amp: float) -> float:
	return max(min(screen_h * SCREEN_SHARE, grid_px) / max(amp, 1.0), 8.0)

func _exit_tree():
	if spawn != null and is_instance_valid(spawn) and spawn.has_method("set_notes_hidden"):
		spawn.set_notes_hidden(false)

func _process(delta):
	var cam := get_viewport().get_camera()
	if cam == null or cursor == null or not is_instance_valid(cursor):
		return
	# (-1: paused; above 0: the countdown back in, with the darkness on)
	var paused: bool = spawn != null and is_instance_valid(spawn) and float(spawn.get("pause_state")) == -1.0
	rect.visible = not paused
	if spawn != null and is_instance_valid(spawn) and spawn.has_method("set_notes_hidden"):
		spawn.set_notes_hidden(paused)
	if paused:
		return
	var p: Vector3 = cursor.global_transform.origin
	if cam.is_position_behind(p):
		return
	var c := cam.unproject_position(p)
	# RADIUS grid units on the screen: project a point that far to the side.
	# (grid units are the note area's own units, so use its x axis and scale)
	var axis: Vector3 = spawn.global_transform.basis.x if spawn is Spatial else Vector3.RIGHT
	var side := cam.unproject_position(p + axis * RADIUS)
	var want := 1.0
	if Rhythia.mod_true_flashlight:
		var game = get_parent()
		want = true_amp(int(game.get("combo")) if game != null and game.get("combo") != null else 0)
	_amp += (want - _amp) * min(delta * GLIDE, 1.0)
	var r: float = radius_px(c.distance_to(side), rect.rect_size.y, _amp)
	mat.set_shader_param("center", c)
	mat.set_shader_param("size", rect.rect_size)
	mat.set_shader_param("radius", r)
	mat.set_shader_param("softness", r * SOFTNESS)
