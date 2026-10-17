extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Tri Tunnel": a long triangular wireframe tunnel sliding toward the
# player (approach rate / 6), tinted by the last hit note colour.

const RADIUS := 7.0
const LENGTH := 160.0
const SEG := 4.0
var tunnel: Spatial
var tunnel_mat: SpatialMaterial
var base_z := -70.0

func _build():
	env.background_color = Color(0.008, 0.006, 0.014)
	tunnel_mat = make_unshaded(note_hit_color, tile_texture(128, 0.03, 0.0, 0.08), true, 90.0)
	tunnel_mat.uv1_scale = Vector3(2.0, LENGTH / SEG, 1.0)
	tunnel = Spatial.new()
	tunnel.name = "Tunnel"
	tunnel.translation = Vector3(0, 0.6, base_z)
	add_child(tunnel)
	var pts := []
	for i in range(3):
		var a = deg2rad(90.0 + 120.0 * i)
		pts.append(Vector3(cos(a), sin(a), 0) * RADIUS)
	for i in range(3):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % 3]
		var x = (b - a).normalized()
		var z = Vector3(0, 0, 1)
		var y = z.cross(x)
		var pm := PlaneMesh.new()
		pm.size = Vector2((b - a).length(), LENGTH)
		var mi := MeshInstance.new()
		mi.mesh = pm
		mi.material_override = tunnel_mat
		mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform(Basis(x, y, z), (a + b) * 0.5)
		tunnel.add_child(mi)

func _tick(_delta):
	if space_effects:
		tunnel.translation.z = base_z + fmod(time * approach_rate / 6.0, SEG)
	tunnel_mat.albedo_color = note_hit_color
