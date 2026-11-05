extends Reference
# Settings > Background Editor > HUD panels: how the two side panels of the
# song HUD look (a few built-in styles, Sound Space's, or your own picture)
# and how big they are. HUD.gd calls apply() once the HUD is built.
#
# "Sound Space" is the Sound Space HUD (SoundSpaceMode.gd, the ss_hud
# setting): picking it turns that on, picking another turns it off. Your own
# picture is user://hud_panel.png (or .jpg); spectators see the default look
# instead of it.

# id, name shown
const STYLES := [
	["chromia", "Chromia (default)"],
	["soundspace", "Sound Space"],
	["outlined", "Outlined"],
	["glass", "Glass"],
	["none", "No background"],
	["image", "Your own picture"],
]
const IMAGE_BASE := "user://hud_panel"
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp"]
const PANELS := ["LeftVP", "RightVP"]

static func ids() -> Array:
	var out := []
	for st in STYLES:
		out.append(st[0])
	return out

static func current() -> String:
	if bool(Rhythia.get("ss_hud")):
		return "soundspace"
	var id := String(Rhythia.get("hud_panel_style"))
	return id if id in ids() else "chromia"

static func set_style(id: String):
	Rhythia.ss_hud = id == "soundspace"
	Rhythia.hud_panel_style = "chromia" if id == "soundspace" else id

static func image_file() -> String:
	for ext in IMAGE_EXTS:
		var p: String = Globals.p("%s.%s" % [IMAGE_BASE, ext])
		if File.new().file_exists(p):
			return p
	return ""

static func size_scale() -> float:
	var v = Rhythia.get("hud_panel_size")
	return clamp(float(v) / 100.0, 0.5, 2.0) if v != null else 1.0

static func apply(hud: Node):
	if hud == null:
		return
	var style := current()
	if style != "chromia" and style != "soundspace":
		var accent: Color = Rhythia.get("panel_text") if Rhythia.get("panel_text") is Color else Color(1, 0.76, 0.96)
		var tex: Texture = _image() if style == "image" else null
		for vp_name in PANELS:
			var bg = hud.get_node_or_null(vp_name + "/Control")
			if bg is ColorRect:
				_restyle(bg, style, accent, tex)
	_resize(hud)
	_place(hud)
	_brighten(hud)

# Settings > Background Editor > HUD panels: where the parts are, as moves
# from where the song puts them (in grid units: the grid is 3 wide)
static func offsets() -> Dictionary:
	return {
		"x": clamp(float(Rhythia.get("hud_panel_x")), -3.0, 3.0), # side panels: farther from the grid (+) or closer (-)
		"y": clamp(float(Rhythia.get("hud_panel_y")), -3.0, 3.0), # side panels: up (+) or down (-)
		"bars": clamp(float(Rhythia.get("hud_bars_y")), -3.0, 3.0), # timer up and health bar down (+), or in (-)
	}

# a part of the HUD, also when it was moved onto the grid (attach to grid)
static func _part(hud: Node, n: String) -> Node:
	var c = hud.get_node_or_null(n)
	if c != null:
		return c
	var p = hud.get_parent()
	for i in 2:
		if p == null:
			break
		var g = p.get_node_or_null("Spawn/" + n)
		if g != null:
			return g
		p = p.get_parent()
	return null

static func _place(hud: Node):
	var o := offsets()
	var l = hud.get_node_or_null("LeftHud")
	var r = hud.get_node_or_null("RightHud")
	if l is Spatial:
		l.transform.origin += Vector3(-o.x, o.y, 0)
	if r is Spatial:
		r.transform.origin += Vector3(o.x, o.y, 0)
	var t = _part(hud, "TimerHud")
	if t is Spatial:
		t.transform.origin.y += o.bars
	var e = _part(hud, "EnergyHud")
	if e is Spatial:
		e.transform.origin.y -= o.bars

# HUD brightness: every part's picture made darker or brighter
static func brightness() -> float:
	var v = Rhythia.get("hud_brightness")
	return clamp(float(v) / 100.0, 0.1, 2.0) if v != null else 1.0

static func _brighten(hud: Node):
	var b := brightness()
	if abs(b - 1.0) < 0.001:
		return
	for c in hud.get_children():
		if c is Viewport:
			for k in c.get_children():
				if k is CanvasItem:
					k.modulate = Color(b, b, b, k.modulate.a)

static func _restyle(bg: ColorRect, style: String, accent: Color, tex: Texture):
	var col: Color = bg.color
	bg.color = Color(0, 0, 0, 0) # the look comes from what's put behind it
	var under: Control = null
	match style:
		"outlined", "glass":
			var p := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.anti_aliasing = true
			if style == "outlined":
				sb.bg_color = col
				sb.border_color = Color(accent.r, accent.g, accent.b, 1.0)
				sb.set_border_width_all(6)
				sb.set_corner_radius_all(28)
			else:
				sb.bg_color = Color(col.r, col.g, col.b, col.a * 0.45)
				sb.border_color = Color(1, 1, 1, 0.35)
				sb.set_border_width_all(3)
				sb.set_corner_radius_all(22)
			p.add_stylebox_override("panel", sb)
			under = p
		"image":
			if tex == null:
				bg.color = col # (no picture: as it was)
				return
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand = true
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			under = tr
		"none":
			return
	if under == null:
		return
	under.name = "PanelStyle"
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.show_behind_parent = true
	under.anchor_right = 1.0
	under.anchor_bottom = 1.0
	bg.add_child(under)
	bg.move_child(under, 0)

static func _image() -> Texture:
	var p := image_file()
	if p == "":
		return null
	var img := Image.new()
	if img.load(p) != OK or img.is_empty():
		return null
	var t := ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER)
	return t

# bigger or smaller, growing outwards (away from the grid)
static func _resize(hud: Node):
	var s := size_scale()
	if abs(s - 1.0) < 0.001:
		return
	for pair in [["LeftHud", -1.0], ["RightHud", 1.0]]:
		var n = hud.get_node_or_null(pair[0])
		if not (n is Spatial):
			continue
		var w: float = 0.0
		if n is VisualInstance:
			w = n.get_aabb().size.x * n.scale.x
		n.scale *= s
		n.transform.origin.x += float(pair[1]) * w * (s - 1.0) / 2.0
