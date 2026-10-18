extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Relic" (Relic.cs + relic.tscn), ported to Godot 3.
# - Structures: the original's flat 2x2 "pillars" (zero-depth boxes) with the
#   same transforms, a vertical white->transparent gradient (the original's
#   GradientTexture2D as seen through BoxMesh UVs) at 50% instance alpha.
#   Back/Group/Pillar uses a lit material in a scene without lights, so it
#   renders black; it is kept as a black gradient quad.
# - Squircles: three huge, nearly transparent RhythiaSquircle quads far below.
# - Particles Left/Right: 48 faint billboarded cube frames each, drifting and
#   spinning inside a 24-unit sphere (emitting only with SpaceEffects on).
#   The original "Aura" emitter has scale_min = scale_max = 0 (invisible), so
#   it is not recreated.

const SQUIRCLE_TEX := "res://assets/worlds/rhythia_spaces/relic/RhythiaSquircle.png"

func _build():
	var grad := _pillar_gradient()
	$Structures/Back/Group/Pillar.material_override.albedo_texture = grad
	$Structures/Back/Group/Pillar2.material_override.albedo_texture = grad

	var sq := _tex(SQUIRCLE_TEX)
	for n in $Squircles.get_children():
		n.mesh.material.albedo_texture = sq

	var mesh := _cube_mesh()
	var mat := SpatialMaterial.new()
	mat.flags_transparent = true
	mat.flags_unshaded = true
	mat.vertex_color_use_as_albedo = true
	# 0.0392 material alpha * (1 - 0.75 instance transparency)
	mat.albedo_color = Color(1, 1, 1, 0.0392157 * 0.25)
	mat.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	mat.distance_fade_mode = SpatialMaterial.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.0
	mat.distance_fade_max_distance = 10.0
	var ramp := Gradient.new()
	ramp.offsets = PoolRealArray([0.0, 0.503226, 1.0])
	ramp.colors = PoolColorArray([Color(0, 0, 0, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var pts := _sphere_points(24.0, 256)
	_add_cubes("Left", Vector3(-47.9036, 3.63416, -53.099064), mesh, mat, ramp, pts)
	_add_cubes("Right", Vector3(50.0899, 3.63416, -54.89727), mesh, mat, ramp, pts)

func _add_cubes(n: String, pos: Vector3, mesh: Mesh, mat: Material, ramp: Gradient, pts: PoolVector3Array):
	var p := CPUParticles.new()
	p.name = n
	p.translation = pos
	p.mesh = mesh
	p.material_override = mat
	p.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	p.amount = 48
	p.lifetime = 6.0
	p.randomness = 0.1
	p.lifetime_randomness = 0.05
	p.preprocess = 6.0
	p.emitting = space_effects
	p.emission_shape = CPUParticles.EMISSION_SHAPE_POINTS
	p.emission_points = pts
	p.direction = Vector3(1, 0.64, 0.385)
	p.spread = 180.0
	p.gravity = Vector3()
	p.initial_velocity = 1.0
	p.initial_velocity_random = 0.9
	p.angle = 360.0
	p.angle_random = 1.0
	p.angular_velocity = 10.0
	p.angular_velocity_random = 0.9
	p.color_ramp = ramp
	$Particles.add_child(p)

# Godot 4 ParticleProcessMaterial EMISSION_SHAPE_SPHERE emits inside the
# sphere volume (Godot 3's sphere shape is the surface), so use points.
func _sphere_points(r: float, n: int) -> PoolVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var out := PoolVector3Array()
	while out.size() < n:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if v.length_squared() <= 1.0:
			out.append(v * r)
	return out

# Cube frame + the inner 1.95 cube ("Transparent" surface), both drawn with the
# particle material like in the original (material_override).
func _cube_mesh() -> ArrayMesh:
	var am := ArrayMesh.new()
	var verts := PoolVector3Array()
	for i in range(0, FRAME_VERTS.size(), 3):
		verts.append(Vector3(FRAME_VERTS[i], FRAME_VERTS[i + 1], FRAME_VERTS[i + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = PoolIntArray(FRAME_INDICES)
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var cm := CubeMesh.new()
	cm.size = Vector3(1.95, 1.95, 1.95)
	var carr: Array = cm.get_mesh_arrays()
	var cv: PoolVector3Array = carr[Mesh.ARRAY_VERTEX]
	for i in range(cv.size()):
		cv[i] = cv[i] + Vector3(0, 0, -1)
	carr[Mesh.ARRAY_VERTEX] = cv
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, carr)
	return am

# The original pillars are BoxMesh(2, 2, 0) with a GradientTexture2D
# (black/transparent -> white/opaque, fill (0.53, 0.54) -> (0.525, 0)). BoxMesh
# maps a face to v in [0, 0.5], so along the pillar the gradient goes from 1
# at the top to ~0.07 at the bottom.
func _pillar_gradient() -> ImageTexture:
	var h := 64
	var img := Image.new()
	img.create(2, h, false, Image.FORMAT_RGBA8)
	img.lock()
	var from := Vector2(0.530303, 0.540404)
	var d := Vector2(0.5252525, 0.0) - from
	for y in range(h):
		var uv := Vector2(1.0 / 6.0, (y + 0.5) / h * 0.5)
		var t = clamp((uv - from).dot(d) / d.length_squared(), 0.0, 1.0)
		var c := Color(t, t, t, t)
		img.set_pixel(0, y, c)
		img.set_pixel(1, y, c)
	img.unlock()
	var tex := ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_CONVERT_TO_LINEAR)
	return tex

func _tex(path: String) -> Texture:
	var t: Texture = load(path)
	if t == null:
		return null
	var img: Image = t.get_data()
	if img == null or img.is_empty():
		return t
	if img.is_compressed() and img.decompress() != OK:
		return t
	if not img.has_mipmaps():
		img.generate_mipmaps()
	var it := ImageTexture.new()
	it.create_from_image(img, Texture.FLAG_MIPMAPS | Texture.FLAG_FILTER | Texture.FLAG_ANISOTROPIC_FILTER | Texture.FLAG_CONVERT_TO_LINEAR)
	return it

# Rhythia ArrayMesh_haq2w surface "Material": a 2-unit cube frame with 0.1 bars (144 verts).
const FRAME_VERTS := [-0.925, 1.025, -1.925, 0.925, 1.025, -1.925, -0.925, 0.925, -1.925, 0.925, 0.925, -1.925, 1.025, 0.925, -1.925, 1.025, -0.925, -1.925, 0.925, 0.925, -1.925, 0.925, -0.925, -1.925, 0.925, 0.925, 0.025, 0.925, -0.925, 0.025, 0.925, 0.925, -0.075, 0.925, -0.925, -0.075, 0.925, -1.025, -1.925, -0.925, -1.025, -1.925, 0.925, -0.925, -1.925, -0.925, -0.925, -1.925, -1.025, -0.925, -1.925, -1.025, 0.925, -1.925, -0.925, -0.925, -1.925, -0.925, 0.925, -1.925, 0.925, -0.925, -2.025, 0.925, 0.925, -2.025, 0.925, -0.925, -1.925, 0.925, 0.925, -1.925, -0.925, 0.925, 0.025, -0.925, -0.925, 0.025, -1.025, 1.025, 0.025, -1.025, -1.025, 0.025, 1.025, 1.025, 0.025, 0.925, -0.925, 0.025, 0.925, 0.925, 0.025, 1.025, -1.025, 0.025, -0.925, -0.925, -2.025, -0.925, 0.925, -2.025, -1.025, -1.025, -2.025, -1.025, 1.025, -2.025, 1.025, -1.025, -2.025, 0.925, 0.925, -2.025, 0.925, -0.925, -2.025, 1.025, 1.025, -2.025, -1.025, -0.925, -1.925, -1.025, -0.925, -0.075, -1.025, -1.025, -2.025, -1.025, -1.025, 0.025, -1.025, 1.025, -2.025, -1.025, 0.925, -0.075, -1.025, 0.925, -1.925, -1.025, 1.025, 0.025, 1.025, -0.925, -1.925, 1.025, 0.925, -1.925, 1.025, -1.025, -2.025, 1.025, 1.025, -2.025, 1.025, -1.025, 0.025, 1.025, 0.925, -0.075, 1.025, -0.925, -0.075, 1.025, 1.025, 0.025, -0.925, -1.025, -0.075, -0.925, -1.025, -1.925, -1.025, -1.025, 0.025, -1.025, -1.025, -2.025, 1.025, -1.025, 0.025, 0.925, -1.025, -1.925, 0.925, -1.025, -0.075, 1.025, -1.025, -2.025, -0.925, 1.025, -1.925, -0.925, 1.025, -0.075, -1.025, 1.025, -2.025, -1.025, 1.025, 0.025, 1.025, 1.025, -2.025, 0.925, 1.025, -0.075, 0.925, 1.025, -1.925, 1.025, 1.025, 0.025, 0.925, -0.925, 0.025, -0.925, -0.925, 0.025, 0.925, -0.925, -0.075, -0.925, -0.925, -0.075, 1.025, -0.925, -1.925, 1.025, -0.925, -0.075, 0.925, -0.925, -1.925, 0.925, -0.925, -0.075, 0.925, -1.025, -0.075, 0.925, -1.025, -1.925, 0.925, -0.925, -0.075, 0.925, -0.925, -1.925, -0.925, 0.925, 0.025, 0.925, 0.925, 0.025, -0.925, 0.925, -0.075, 0.925, 0.925, -0.075, 1.025, 0.925, -0.075, 1.025, 0.925, -1.925, 0.925, 0.925, -0.075, 0.925, 0.925, -1.925, 0.925, 1.025, -1.925, 0.925, 1.025, -0.075, 0.925, 0.925, -1.925, 0.925, 0.925, -0.075, -0.925, -0.925, 0.025, -0.925, 0.925, 0.025, -0.925, -0.925, -0.075, -0.925, 0.925, -0.075, 1.025, -0.925, -0.075, 1.025, 0.925, -0.075, 0.925, -0.925, -0.075, 0.925, 0.925, -0.075, -0.925, -1.025, -0.075, 0.925, -1.025, -0.075, -0.925, -0.925, -0.075, 0.925, -0.925, -0.075, -0.925, 0.925, -2.025, -0.925, -0.925, -2.025, -0.925, 0.925, -1.925, -0.925, -0.925, -1.925, -1.025, -0.925, -0.075, -1.025, -0.925, -1.925, -0.925, -0.925, -0.075, -0.925, -0.925, -1.925, 0.925, 1.025, -0.075, -0.925, 1.025, -0.075, 0.925, 0.925, -0.075, -0.925, 0.925, -0.075, -0.925, -0.925, -2.025, 0.925, -0.925, -2.025, -0.925, -0.925, -1.925, 0.925, -0.925, -1.925, -1.025, 0.925, -0.075, -1.025, -0.925, -0.075, -0.925, 0.925, -0.075, -0.925, -0.925, -0.075, -0.925, -1.025, -1.925, -0.925, -1.025, -0.075, -0.925, -0.925, -1.925, -0.925, -0.925, -0.075, 0.925, 0.925, -2.025, -0.925, 0.925, -2.025, 0.925, 0.925, -1.925, -0.925, 0.925, -1.925, -1.025, 0.925, -1.925, -1.025, 0.925, -0.075, -0.925, 0.925, -1.925, -0.925, 0.925, -0.075, -0.925, 1.025, -0.075, -0.925, 1.025, -1.925, -0.925, 0.925, -0.075, -0.925, 0.925, -1.925]
const FRAME_INDICES := [0, 1, 2, 2, 1, 3, 4, 5, 6, 6, 5, 7, 8, 9, 10, 10, 9, 11, 12, 13, 14, 14, 13, 15, 16, 17, 18, 18, 17, 19, 20, 21, 22, 22, 21, 23, 24, 25, 26, 26, 25, 27, 28, 24, 26, 25, 29, 27, 30, 24, 28, 27, 29, 31, 29, 30, 31, 31, 30, 28, 32, 33, 34, 34, 33, 35, 36, 32, 34, 33, 37, 35, 38, 32, 36, 35, 37, 39, 37, 38, 39, 39, 38, 36, 40, 41, 42, 42, 41, 43, 44, 40, 42, 41, 45, 43, 46, 40, 44, 43, 45, 47, 45, 46, 47, 47, 46, 44, 48, 49, 50, 50, 49, 51, 52, 48, 50, 49, 53, 51, 54, 48, 52, 51, 53, 55, 53, 54, 55, 55, 54, 52, 56, 57, 58, 58, 57, 59, 60, 56, 58, 57, 61, 59, 62, 56, 60, 59, 61, 63, 61, 62, 63, 63, 62, 60, 64, 65, 66, 66, 65, 67, 68, 64, 66, 65, 69, 67, 70, 64, 68, 67, 69, 71, 69, 70, 71, 71, 70, 68, 72, 73, 74, 74, 73, 75, 76, 77, 78, 78, 77, 79, 80, 81, 82, 82, 81, 83, 84, 85, 86, 86, 85, 87, 88, 89, 90, 90, 89, 91, 92, 93, 94, 94, 93, 95, 96, 97, 98, 98, 97, 99, 100, 101, 102, 102, 101, 103, 104, 105, 106, 106, 105, 107, 108, 109, 110, 110, 109, 111, 112, 113, 114, 114, 113, 115, 116, 117, 118, 118, 117, 119, 120, 121, 122, 122, 121, 123, 124, 125, 126, 126, 125, 127, 128, 129, 130, 130, 129, 131, 132, 133, 134, 134, 133, 135, 136, 137, 138, 138, 137, 139, 140, 141, 142, 142, 141, 143]
