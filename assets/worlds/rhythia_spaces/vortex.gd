extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Vortex": a twisted tunnel of squircle outlines that slowly spins.
# The nearest squircle takes the latest hit colour and older hit colours are
# pushed back down the tunnel.

const COUNT := 14
var squircles: Spatial
var mats := []
var hit_colors := []

func _build():
	env.background_color = Color(0.005, 0.004, 0.01)
	var tex = shape_texture(256, 2, 0.03, 0.05)
	squircles = Spatial.new()
	squircles.name = "Squircles"
	squircles.translation = Vector3(0, 0, 0)
	add_child(squircles)
	var cols := []
	if Rhythia.selected_colorset != null:
		cols = Rhythia.selected_colorset.colors.duplicate()
	if cols.empty():
		cols = [Color(1, 1, 1)]
	cols.invert()
	for i in range(COUNT):
		var c: Color = cols[i % cols.size()]
		var m = make_unshaded(c, tex, true, 75.0)
		mats.append(m)
		hit_colors.append(c)
		var mi = add_quad(squircles, Vector2(10, 10), m, Vector3(0, 0, -3.0 - i * 4.5))
		mi.rotation_degrees.z = i * 6.0

func _on_hit(col: Color):
	for i in range(hit_colors.size() - 1, 0, -1):
		hit_colors[i] = hit_colors[i - 1]
	hit_colors[0] = col

func _tick(delta):
	if space_effects:
		squircles.rotation.z = -time / 8.0
	var w = min(1.0, delta * 6.0)
	for i in range(mats.size()):
		var m: SpatialMaterial = mats[i]
		m.albedo_color = m.albedo_color.linear_interpolate(hit_colors[i], w)
