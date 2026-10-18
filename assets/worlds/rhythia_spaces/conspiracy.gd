extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Conspiracy" (Conspiracy.cs + conspiracy.tscn), ported to Godot 3.
# Same planes, transforms and textures as the original: Illuminati / money /
# globe icons on both sides (bobbing up and down), two long "???" scrolls
# whose texture scrolls, and two strips of text sliding toward the camera
# along the floor. Effects stop (and the text strips hide) when SpaceEffects
# is off. GeometryInstance3D.transparency of the original is folded into the
# materials' albedo alpha (Godot 3 has no per-instance transparency).

const TEX_DIR := "res://assets/worlds/rhythia_spaces/conspiracy/"
const SCROLLING_TEXT_LOOP_END := 46.0

var icons: Spatial
var icons_start: Vector3
var scrolling_text: Spatial
var scrolling_text_start: Vector3
var qm_mat: SpatialMaterial

func _build():
	icons = $Icons
	icons_start = icons.translation
	scrolling_text = $ScrollingText
	scrolling_text_start = scrolling_text.translation
	qm_mat = $ScrollingQuestionMarks/Left.mesh.material

	$Icons/RIllu.mesh.material.albedo_texture = _tex("Illuminati.png", false)
	$Icons/RMoney.mesh.material.albedo_texture = _tex("Money.png", false)
	$Icons/RGlobe.mesh.material.albedo_texture = _tex("Globe.png", false)
	qm_mat.albedo_texture = _tex("Scroll.png", true)
	$ScrollingText/Top.mesh.material.albedo_texture = _tex("Front.png", true)
	$ScrollingText/Bottom.mesh.material.albedo_texture = _tex("back.png", true)
	scrolling_text.visible = space_effects

# Godot 4 samples albedo textures as sRGB with repeat + mipmaps; rebuild the
# imported texture with those flags regardless of how it was imported.
func _tex(file: String, repeat: bool) -> Texture:
	var t: Texture = load(TEX_DIR + file)
	if t == null:
		return null
	var img: Image = t.get_data()
	if img == null or img.is_empty():
		return t
	if img.is_compressed() and img.decompress() != OK:
		return t
	if not img.has_mipmaps():
		img.generate_mipmaps()
	var flags = Texture.FLAG_MIPMAPS | Texture.FLAG_FILTER | Texture.FLAG_ANISOTROPIC_FILTER | Texture.FLAG_CONVERT_TO_LINEAR
	if repeat:
		flags |= Texture.FLAG_REPEAT
	var it := ImageTexture.new()
	it.create_from_image(img, flags)
	return it

func _tick(delta):
	if not space_effects:
		return
	var o: Vector3 = qm_mat.uv1_offset
	o.y = fmod(o.y + delta / 10.0, 1.0)
	qm_mat.uv1_offset = o

	icons.translation = icons_start + Vector3.UP * sin(OS.get_ticks_msec() / 1000.0)

	if scrolling_text.translation.z < SCROLLING_TEXT_LOOP_END:
		scrolling_text.translation.z += delta * 2.0
	else:
		scrolling_text.translation = scrolling_text_start
