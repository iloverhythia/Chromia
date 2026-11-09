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
	["neon", "Neon glow"],
	["tinted", "Tinted (panel text colour)"],
	["solid", "Solid dark"],
	["sharp", "Sharp corners"],
	["pill", "Pill"],
	["double", "Double border"],
	["sidebar", "Side stripe"],
	["minimal", "Thin outline"],
	["shadow", "Floating (shadow)"],
	["gradient", "Gradient"],
	["glow", "Soft glow"],
	["sunset", "Sunset"],
	["ocean", "Ocean"],
	["aurora", "Aurora (moving)"],
	["rainbow", "Rainbow border (moving)"],
	["hologram", "Hologram (moving)"],
	["brackets", "Corner brackets"],
	["stripes", "Stripes"],
	["dots", "Dots"],
	["scanlines", "CRT scanlines"],
	["carbon", "Carbon fibre"],
	["none", "No background"],
	["image", "Your own picture"],
]
# the looks drawn by assets/shaders/hud_panel.shader (its "mode")
const SHADER_MODES := {"gradient": 1, "sunset": 2, "ocean": 3, "rainbow": 4, "brackets": 5,
	"stripes": 6, "scanlines": 7, "dots": 8, "hologram": 9, "carbon": 10, "glow": 11, "aurora": 12}
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
				_restyle(bg, style, accent, tex, vp_name == "LeftVP")
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

static func _box(bg_col: Color, radius: int, border := 0, border_col := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.anti_aliasing = true
	sb.bg_color = bg_col
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.border_color = border_col
		sb.set_border_width_all(border)
	return sb

static func _panel(sb: StyleBox, inset := 0.0) -> Panel:
	var p := Panel.new()
	p.add_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_right = 1.0
	p.anchor_bottom = 1.0
	p.margin_left = inset
	p.margin_top = inset
	p.margin_right = -inset
	p.margin_bottom = -inset
	return p

static func _restyle(bg: ColorRect, style: String, accent: Color, tex: Texture, left := true):
	var col: Color = bg.color
	bg.color = Color(0, 0, 0, 0) # the look comes from what's put behind it
	var a := Color(accent.r, accent.g, accent.b, 1.0)
	var under: Control = null
	match style:
		"outlined":
			under = _panel(_box(col, 28, 6, a))
		"glass":
			under = _panel(_box(Color(col.r, col.g, col.b, col.a * 0.45), 22, 3, Color(1, 1, 1, 0.35)))
		"neon":
			var sb := _box(Color(0.015, 0.015, 0.03, 1.0), 18, 3, a) # (solid: the glow is drawn under it)
			sb.shadow_color = Color(a.r, a.g, a.b, 0.85)
			sb.shadow_size = 18
			under = _panel(sb, 22) # (room for the glow inside the panel)
		"tinted":
			under = _panel(_box(Color(a.r * 0.35, a.g * 0.35, a.b * 0.35, 0.7), 16, 2, Color(a.r, a.g, a.b, 0.6)))
		"solid":
			under = _panel(_box(Color(0.05, 0.05, 0.08, 0.95), 10))
		"sharp":
			under = _panel(_box(col, 0, 4, Color(1, 1, 1, 0.85)))
		"pill":
			under = _panel(_box(col, 150))
		"double":
			under = _panel(_box(col, 24, 4, a))
			under.add_child(_panel(_box(Color(0, 0, 0, 0), 14, 2, Color(1, 1, 1, 0.45)), 14))
		"sidebar":
			var sb := _box(col, 6)
			# (the stripe on the side that faces the grid)
			if left:
				sb.border_width_right = 12
			else:
				sb.border_width_left = 12
			sb.border_color = a
			under = _panel(sb)
		"minimal":
			under = _panel(_box(Color(0, 0, 0, 0.15), 6, 2, Color(1, 1, 1, 0.6)))
		"shadow":
			var sb := _box(col, 20)
			sb.shadow_color = Color(0, 0, 0, 0.8)
			sb.shadow_size = 26
			sb.shadow_offset = Vector2(0, 10)
			under = _panel(sb, 30)
		"image":
			if tex == null:
				bg.color = col # (no picture: as it was)
				return
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand = true
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.anchor_right = 1.0
			tr.anchor_bottom = 1.0
			under = tr
		"none":
			return
		_:
			if SHADER_MODES.has(style):
				var r := ColorRect.new()
				var m := ShaderMaterial.new()
				m.shader = load("res://assets/shaders/hud_panel.shader")
				m.set_shader_param("mode", float(SHADER_MODES[style]))
				m.set_shader_param("accent", a)
				m.set_shader_param("base", col)
				m.set_shader_param("size", bg.rect_size if bg.rect_size.x > 1 else Vector2(300, 900))
				r.material = m
				r.anchor_right = 1.0
				r.anchor_bottom = 1.0
				under = r
	if under == null:
		bg.color = col
		return
	under.name = "PanelStyle"
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.show_behind_parent = true
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
