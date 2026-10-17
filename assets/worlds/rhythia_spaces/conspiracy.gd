extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Conspiracy": a dim green room. Walls of question marks scroll
# upward on both sides, an all-seeing-eye pyramid and floating "?" icons bob
# up and down, and cryptic messages slide along the floor toward the player.

const SCROLLING_TEXT_LOOP_END := 46.0
const TEXT_SPACING := 11.5
const MESSAGES := ["WAKE UP", "THEY ARE WATCHING", "IT'S ALL CONNECTED", "THE NOTES KNOW"]
const GREEN := Color(0.25, 1.0, 0.45)

var icons: Spatial
var icons_start: Vector3
var scrolling_text: Spatial
var scrolling_text_start: Vector3
var qm_left: Label3D
var qm_right: Label3D
var qm_line_h := 1.0
var qm_off := 0.0
var eye_mat: SpatialMaterial

func _build():
	env.background_color = Color(0.004, 0.018, 0.008)

	# --- ScrollingQuestionMarks (Left / Right walls) ---
	var qfont := dynamic_font(64)
	var line := ""
	for i in range(18):
		line += "?    "
	var txt := ""
	for i in range(16):
		txt += ("  " if i % 2 == 1 else "") + line + "\n"
	var qms := Spatial.new()
	qms.name = "ScrollingQuestionMarks"
	add_child(qms)
	qm_left = _label(qms, txt, qfont, 0.05, Color(GREEN.r, GREEN.g, GREEN.b, 0.15))
	qm_left.name = "Left"
	qm_left.transform = Transform(Basis(Vector3(0, 1, 0), deg2rad(90)), Vector3(-9, 0, -40))
	qm_right = _label(qms, txt, qfont, 0.05, Color(GREEN.r, GREEN.g, GREEN.b, 0.15))
	qm_right.name = "Right"
	qm_right.transform = Transform(Basis(Vector3(0, 1, 0), deg2rad(-90)), Vector3(9, 0, -40))
	qm_line_h = qfont.get_height() * 0.05 * 2.0 # two lines = one full period (rows are staggered)

	# --- Icons (bobbing) ---
	icons = Spatial.new()
	icons.name = "Icons"
	icons.translation = Vector3(0, 0, 0)
	add_child(icons)
	icons_start = icons.translation
	eye_mat = make_unshaded(GREEN, _eye_texture(256), true, 0.0)
	add_quad(icons, Vector2(16, 16), eye_mat, Vector3(0, 6.5, -48))
	var big_q := dynamic_font(128)
	for p in [Vector3(-14, 3, -45), Vector3(14, 1, -42), Vector3(-6, -7, -55), Vector3(8, 11, -60)]:
		var l = _label(icons, "?", big_q, 0.06, Color(GREEN.r, GREEN.g, GREEN.b, 0.55))
		l.translation = p
		l.rotation_degrees.z = rand_range(-20, 20)

	# --- ScrollingText (floor) ---
	scrolling_text = Spatial.new()
	scrolling_text.name = "ScrollingText"
	scrolling_text.translation = Vector3(0, -6.0, -24)
	add_child(scrolling_text)
	scrolling_text_start = scrolling_text.translation
	var tfont := dynamic_font(96)
	for i in range(8):
		var l = _label(scrolling_text, MESSAGES[i % MESSAGES.size()], tfont, 0.03, Color(GREEN.r, GREEN.g, GREEN.b, 0.35))
		l.transform = Transform(Basis(Vector3(1, 0, 0), deg2rad(-90)), Vector3(0, 0, -TEXT_SPACING * i))

func _label(parent: Node, text: String, font: Font, px: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.pixel_size = px
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0)
	l.double_sided = true
	l.shaded = false
	l.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	return l

func _eye_texture(size: int) -> ImageTexture:
	var img := Image.new()
	img.create(size, size, false, Image.FORMAT_RGBA8)
	img.lock()
	var verts = [Vector2(0, -0.86), Vector2(0.92, 0.72), Vector2(-0.92, 0.72)]
	var aa = 2.0 / size
	for y in range(size):
		var fy = (y + 0.5) / size * 2.0 - 1.0
		for x in range(size / 2):
			var fx = (x + 0.5) / size * 2.0 - 1.0
			var p = Vector2(fx, fy)
			# convex polygon distance (max of edge plane distances)
			var d = -10.0
			for i in range(3):
				var a: Vector2 = verts[i]
				var b: Vector2 = verts[(i + 1) % 3]
				var e = (b - a).normalized()
				var n = Vector2(e.y, -e.x)
				d = max(d, (p - a).dot(n))
			var al = 1.0 - _smooth(0.022 - aa, 0.022 + aa, abs(d + 0.03))
			# capstone line
			if d < -0.03 and abs(fy + 0.2) < 0.02:
				al = max(al, 1.0)
			# eye
			var ex = fx / 0.36
			var ey = (fy - 0.26) / 0.15
			var ed = sqrt(ex * ex + ey * ey)
			al = max(al, 1.0 - _smooth(0.07 - aa * 4.0, 0.07 + aa * 4.0, abs(ed - 1.0)))
			var pd = Vector2(fx, fy - 0.26).length()
			al = max(al, 1.0 - _smooth(0.085, 0.085 + aa, pd))
			# soft glow inside
			if d < 0.0:
				al = max(al, 0.08)
			# rays from the capstone
			if d > 0.0 and fy < 0.72:
				var ang = atan2(fy + 0.6, fx)
				var ray = abs(sin(ang * 9.0))
				al = max(al, (1.0 - _smooth(0.0, 0.08, 1.0 - ray)) * 0.25 * (1.0 - _smooth(0.0, 0.6, d)))
			var c = Color(1, 1, 1, clamp(al, 0.0, 1.0))
			img.set_pixel(x, y, c)
			img.set_pixel(size - 1 - x, y, c)
	img.unlock()
	return image_to_texture(img, false)

func _tick(delta):
	scrolling_text.visible = space_effects
	if not space_effects:
		return
	qm_off = fmod(qm_off + delta * 0.6, qm_line_h)
	qm_left.translation.y = qm_off
	qm_right.translation.y = qm_off
	icons.translation = icons_start + Vector3.UP * sin(time)
	if scrolling_text.translation.z < scrolling_text_start.z + SCROLLING_TEXT_LOOP_END:
		scrolling_text.translation += Vector3.BACK * delta * 2.0
	else:
		scrolling_text.translation = scrolling_text_start
	eye_mat.albedo_color = GREEN.linear_interpolate(note_hit_color, 0.25)
