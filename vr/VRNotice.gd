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
	# in front of where you're looking, level
	var cam = host.get_viewport().get_camera()
	var t := Transform()
	if cam:
		var g: Transform = cam.global_transform
		var fwd: Vector3 = -g.basis.z
		fwd.y = 0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
		t.origin = g.origin + fwd * 2.4
		t.basis = Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)) # (the quad's front, turned to you)
	else:
		t.origin = Vector3(0, 1.6, -2.4)
	mi.global_transform = t
	return label

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
