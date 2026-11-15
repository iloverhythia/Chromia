extends Reference

# A few lines of text on a panel in front of you in the headset, for screens
# that otherwise only exist on the computer's flat window (the loading screen
# of Reload Content / a profile switch, the error screens): in the headset
# those were simply black.
static func make(host: Node, text: String) -> Label:
	var vp := Viewport.new()
	vp.size = Vector2(900, 220)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_v_flip = true
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	host.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.055, 0.08, 1)
	bg.rect_size = vp.size
	vp.add_child(bg)
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = 40
	f.use_filter = true
	var label := Label.new()
	label.add_font_override("font", f)
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.autowrap = true
	label.rect_size = vp.size
	label.text = text
	vp.add_child(label)
	var q := QuadMesh.new()
	q.size = Vector2(1.8, 1.8 * vp.size.y / vp.size.x)
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_albedo_tex_force_srgb = true
	var tex: ViewportTexture = vp.get_texture()
	tex.flags = Texture.FLAG_FILTER
	m.albedo_texture = tex
	q.material = m
	var mi := MeshInstance.new()
	mi.mesh = q
	host.add_child(mi)
	place(mi, host.get_viewport().get_camera())
	return label

const DISTANCE := 2.4

# in front of where you're looking, level
static func place(mi: Spatial, cam):
	var t := Transform()
	if cam:
		var g: Transform = cam.global_transform
		var fwd: Vector3 = -g.basis.z
		fwd.y = 0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
		t.origin = g.origin + fwd * DISTANCE
		t.basis = Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)) # (the quad's front, turned to you)
	else:
		t.origin = Vector3(0, 1.6, -DISTANCE)
	mi.global_transform = t

# How far the panel is from straight ahead of you (degrees, left / right
# only), and how far its distance is from where place() puts it.
static func off_by(mi: Spatial, cam) -> Array:
	if cam == null:
		return [0.0, 0.0]
	var g: Transform = cam.global_transform
	var to: Vector3 = mi.global_transform.origin - g.origin
	var flat := Vector2(to.x, to.z)
	var fwd := Vector2(-g.basis.z.x, -g.basis.z.z)
	var ang := 0.0
	if flat.length() > 0.01 and fwd.length() > 0.01:
		ang = abs(rad2deg(fwd.angle_to(flat)))
	return [ang, abs(flat.length() - DISTANCE) + abs(to.y)]

# The loading screen in the headset (init.gd): a big "Loading" or "Updating",
# three dots that keep moving, and under them what is being loaded.
# -> {title, detail: Label, dots: Array of Control, mesh: MeshInstance}
static func make_loading(host: Node) -> Dictionary:
	var vp := Viewport.new()
	vp.size = Vector2(1000, 440)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_v_flip = true
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	host.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.055, 0.08, 1)
	bg.rect_size = vp.size
	vp.add_child(bg)
	var edge := ReferenceRect.new()
	edge.border_color = Color(1, 0.705882, 0.945098, 0.55)
	edge.border_width = 3.0
	edge.editor_only = false
	edge.rect_size = vp.size
	vp.add_child(edge)
	var data = load("res://assets/font/Lato/Lato-Bold.ttf")
	var big := DynamicFont.new()
	big.font_data = data
	big.size = 92
	big.use_filter = true
	var small := DynamicFont.new()
	small.font_data = data
	small.size = 34
	small.use_filter = true
	var title := Label.new()
	title.add_font_override("font", big)
	title.add_color_override("font_color", Color(1, 0.86, 0.98))
	title.align = Label.ALIGN_CENTER
	title.valign = Label.VALIGN_CENTER
	title.rect_position = Vector2(0, 34)
	title.rect_size = Vector2(vp.size.x, 130)
	title.text = "Loading"
	vp.add_child(title)
	var dots := []
	for i in range(3):
		var d := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 0.705882, 0.945098)
		sb.set_corner_radius_all(11)
		d.add_stylebox_override("panel", sb)
		d.rect_size = Vector2(22, 22)
		d.rect_position = Vector2(vp.size.x * 0.5 - 11 + (i - 1) * 46, 184)
		vp.add_child(d)
		dots.append(d)
	var detail := Label.new()
	detail.add_font_override("font", small)
	detail.add_color_override("font_color", Color(0.82, 0.8, 0.88))
	detail.align = Label.ALIGN_CENTER
	detail.valign = Label.VALIGN_CENTER
	detail.autowrap = true
	detail.clip_text = true
	detail.rect_position = Vector2(30, 226)
	detail.rect_size = Vector2(vp.size.x - 60, 190)
	vp.add_child(detail)
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2 * vp.size.y / vp.size.x)
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_albedo_tex_force_srgb = true
	var tex: ViewportTexture = vp.get_texture()
	tex.flags = Texture.FLAG_FILTER
	m.albedo_texture = tex
	q.material = m
	var mi := MeshInstance.new()
	mi.mesh = q
	host.add_child(mi)
	place(mi, host.get_viewport().get_camera())
	return {title = title, detail = detail, dots = dots, mesh = mi}

# An error screen (scenes/errors) while VR runs: its text in the headset, and
# for a menu or song that didn't load, back to the menu after a moment (twice
# at most in a row, so a menu that can't load doesn't go round for ever).
static func error_screen(host: Node, text: String, retry: bool = true):
	if not Rhythia.vr:
		return
	Rhythia.trail("error screen in VR: " + text.replace("\n", " | "))
	var tries: int = int(Engine.get_meta("vr_error_retries")) if Engine.has_meta("vr_error_retries") else 0
	var again: bool = retry and tries < 2
	make(host, text.split("\n")[0].replace("--", "").strip_edges().capitalize() + ("\nGoing back to the menu..." if again else "\nPlease restart the game."))
	if again:
		Engine.set_meta("vr_error_retries", tries + 1)
		host.get_tree().create_timer(4.0).connect("timeout", Rhythia, "vr_back_to_menu")
