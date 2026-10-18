extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Vortex" (Vortex.cs + vortex.tscn): six huge, very faint squircle
# outlines (squircle_blank.png) nested down the view axis, each turned 10 deg
# more than the previous one, slowly spinning. Squircle i fades toward the
# colour of the i-th most recent hit, so hit colours ripple down the tunnel.
#
# The original quads reach z = -580, past Furria's camera far plane (500), so
# the whole group is scaled by SCALE toward the camera (identical on screen,
# everything is unshaded); the shader undoes the scale for the fog distance.

const SQUIRCLE_TEX = preload("res://assets/worlds/rhythia_spaces/vortex/squircle_blank.png")
const SQUIRCLE_SHADER = preload("res://assets/worlds/rhythia_spaces/vortex/vortex_squircle.shader")
const CAM_Z := 3.5
const SCALE := 0.5
# [size, z rotation in degrees, z position, GeometryInstance3D.transparency]
const QUADS := [
	[600.0, 0.0, -180.0, 0.94],
	[500.0, 10.0, -260.0, 0.95],
	[400.0, 20.0, -340.0, 0.96],
	[300.0, 30.0, -420.0, 0.97],
	[200.0, 40.0, -500.0, 0.98],
	[125.0, 50.0, -580.0, 0.99],
]

var squircles: Spatial
var mats := []
var cols := []
var alphas := []
var last_hit_colors := []

func _build():
	var holder := Spatial.new()
	holder.name = "Holder"
	holder.translation = Vector3(0, 0, CAM_Z)
	holder.scale = Vector3(SCALE, SCALE, SCALE)
	add_child(holder)
	squircles = Spatial.new()
	squircles.name = "Squircles"
	squircles.translation = Vector3(0, 0, -CAM_Z)
	holder.add_child(squircles)

	# start as if the previous notes had been hit: reversed skin colours
	var note_colors := []
	if Rhythia.selected_colorset != null:
		note_colors = Rhythia.selected_colorset.colors.duplicate()
	if note_colors.empty():
		note_colors = [Color(1, 1, 1)]
	note_colors.invert()

	var quad := QuadMesh.new()
	for i in range(QUADS.size()):
		var q: Array = QUADS[i]
		var m := ShaderMaterial.new()
		m.shader = SQUIRCLE_SHADER
		m.set_shader_param("tex", SQUIRCLE_TEX)
		m.set_shader_param("dist_scale", 1.0 / SCALE)
		var a: float = 1.0 - q[3]
		m.set_shader_param("color", Color(1, 1, 1, a))
		mats.append(m)
		alphas.append(a)
		cols.append(Color(1, 1, 1))
		last_hit_colors.append(note_colors[i % note_colors.size()])
		var mi := MeshInstance.new()
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform(Basis(Vector3(0, 0, 1), deg2rad(q[1])).scaled(Vector3(q[0], q[0], 1.0)), Vector3(0, 0, q[2]))
		squircles.add_child(mi)

func _on_hit(col: Color):
	# a new colour is pushed onto the front, older ones move one squircle back
	if col == last_hit_colors[0]:
		return
	for i in range(last_hit_colors.size() - 1, 0, -1):
		last_hit_colors[i] = last_hit_colors[i - 1]
	last_hit_colors[0] = col

func _tick(delta):
	if space_effects:
		# Rotation = Forward * ticks / 8000
		squircles.rotation.z = -OS.get_ticks_msec() / 8000.0
	var w = min(1.0, delta * 6.0)
	for i in range(mats.size()):
		var c: Color = Color(1, 1, 1)
		if space_effects:
			c = cols[i].linear_interpolate(last_hit_colors[i], w)
		cols[i] = c
		mats[i].set_shader_param("color", Color(c.r, c.g, c.b, alphas[i]))
