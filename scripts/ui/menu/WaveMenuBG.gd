extends ColorRect

# "Wave menu" (experimental setting): replaces the menu's dark background with
# an animated contour-line shader, and gives the menu's text black outlines so
# it stays readable on top of the lines.
#
# Settings > Menu Customizer (MenuStyle.gd) picks the pattern: the contour
# lines (wave_menu.shader) or grid, dots, waves, hexagons, stripes, stars or a
# plain colour (menu_patterns.shader), with your colours and speed. "Off" is
# the Wave menu setting off (the 3D background shows).

# Only light-coloured text gets an outline (black outlines on black button text
# would make it unreadable). Outlined copies of each font are made once and
# applied per control, so the original fonts are never changed.
var _outline_copies: Dictionary = {} # original DynamicFont -> outlined copy
var _changed: Dictionary = {}        # Control -> [property, original value]

const DEFAULT_COLORS = {
	"bg_color": Color(0.13, 0.025, 0.03, 1.0),
	"minor_color": Color(0.62, 0.16, 0.16, 0.75),
	"major_a": Color(1.0, 0.36, 0.45, 1.0),
	"major_b": Color(1.0, 0.42, 0.27, 1.0),
	"major_c": Color(1.0, 0.36, 0.45, 1.0),
	"major_d": Color(1.0, 0.42, 0.27, 1.0),
	"color_count": 2.0,
}

# Halloween (Seasonal.gd): pumpkin orange, purple and slime green
const HALLOWEEN_COLORS = {
	"bg_color": Color(0.06, 0.02, 0.09, 1.0),
	"minor_color": Color(0.34, 0.13, 0.42, 0.75),
	"major_a": Color(1.0, 0.52, 0.08, 1.0),
	"major_b": Color(0.68, 0.36, 1.0, 1.0),
	"major_c": Color(0.5, 0.92, 0.28, 1.0),
	"major_d": Color(1.0, 0.7, 0.2, 1.0),
	"color_count": 4.0,
}

# Christmas (Seasonal.gd): pine green night, holly red, gold and snow white
const CHRISTMAS_COLORS = {
	"bg_color": Color(0.02, 0.06, 0.05, 1.0),
	"minor_color": Color(0.1, 0.36, 0.2, 0.75),
	"major_a": Color(0.95, 0.18, 0.22, 1.0),
	"major_b": Color(1.0, 0.8, 0.3, 1.0),
	"major_c": Color(0.3, 0.88, 0.45, 1.0),
	"major_d": Color(0.92, 0.96, 1.0, 1.0),
	"color_count": 4.0,
}

# Wave colours: the default pink/orange, or (option) the selected colorset.
# In colorset mode the lines fade through every colour in the set over time.
const COLOR_STEP_SECONDS = 3.0
var _cs_colors: Array = []
var _cs_phase: float = 0.0

const MenuStyle = preload("res://scripts/ui/menu/MenuStyle.gd")
const PATTERN_IDS := {"grid": 0, "dots": 1, "waves": 2, "hex": 3, "stripes": 4, "stars": 5, "solid": 6}
var _pattern := ""
var _mat_contour: ShaderMaterial
var _mat_pattern: ShaderMaterial

# VR: the pattern is drawn into a half-size picture at most every other frame
# and shown stretched behind the menu, instead of over the whole menu screen
# (1920x1080 or more) every time the screen is redrawn: a full-screen shader
# that costs the Quest a lot, and made the menu smooth or laggy depending on
# how often it was being redrawn. The patterns are worked out from the
# picture's height, so they look the same.
var _cur_mat: ShaderMaterial
var _lr_vp: Viewport = null
var _lr_rect: ColorRect = null
var _lr_frame := 0

func _set_mat(m: ShaderMaterial):
	_cur_mat = m
	if _lr_rect != null:
		_lr_rect.material = m
		material = null
	else:
		material = m

func _make_lowres():
	_lr_vp = Viewport.new()
	_lr_vp.disable_3d = true
	_lr_vp.usage = Viewport.USAGE_2D
	_lr_vp.hdr = false
	_lr_vp.transparent_bg = false
	_lr_vp.render_target_v_flip = true
	_lr_vp.render_target_update_mode = Viewport.UPDATE_ONCE
	add_child(_lr_vp)
	_lr_rect = ColorRect.new()
	_lr_vp.add_child(_lr_rect)
	var tr := TextureRect.new()
	tr.name = "LowRes"
	tr.anchor_right = 1
	tr.anchor_bottom = 1
	tr.expand = true
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	var tex: ViewportTexture = _lr_vp.get_texture()
	tex.flags = Texture.FLAG_FILTER
	tr.texture = tex
	add_child(tr)
	_set_mat(_cur_mat)
	connect("resized", self, "_lowres_size")
	_lowres_size()

func _lowres_size():
	if _lr_vp == null:
		return
	var sz := (rect_size * 0.5).floor()
	sz = Vector2(max(sz.x, 16), max(sz.y, 16))
	_lr_vp.size = sz
	_lr_rect.rect_size = sz

# the material for the picked pattern
func _use_pattern():
	_pattern = MenuStyle.bg_pattern()
	if not PATTERN_IDS.has(_pattern):
		_pattern = "contour"
	if _pattern == "contour":
		_set_mat(_mat_contour)
		_mat_contour.set_shader_param("speed", 0.05 * MenuStyle.bg_speed())
	else:
		_set_mat(_mat_pattern)
		_mat_pattern.set_shader_param("pattern", PATTERN_IDS[_pattern])
		_mat_pattern.set_shader_param("speed", MenuStyle.bg_speed())

# the three colours (background, lines, accent) of a pattern other than contour
func _pattern_colors() -> Array:
	var mine := MenuStyle.bg_colors()
	if not mine.empty():
		return mine
	if Rhythia.wave_menu_colorset and Rhythia.selected_colorset != null and not Rhythia.selected_colorset.real_colors.empty():
		var cs: Array = Rhythia.selected_colorset.real_colors
		var a: Color = cs[0]
		var b: Color = cs[min(1, cs.size() - 1)]
		return [Color(a.r, a.g, a.b).darkened(0.88), Color(a.r, a.g, a.b).darkened(0.35), Color(b.r, b.g, b.b)]
	if preload("res://scripts/ui/menu/Seasonal.gd").halloween():
		return [Color(0.06, 0.02, 0.09), Color(0.42, 0.18, 0.55), Color(1.0, 0.52, 0.08)]
	if preload("res://scripts/ui/menu/Seasonal.gd").christmas():
		return [Color(0.02, 0.06, 0.05), Color(0.12, 0.42, 0.24), Color(0.95, 0.2, 0.24)]
	return MenuStyle.PATTERN_COLORS

func _apply_colors(_v = null):
	_use_pattern()
	var mat: ShaderMaterial = _cur_mat
	if mat == null: return
	_cs_colors = []
	if _pattern != "contour":
		var pc := _pattern_colors()
		mat.set_shader_param("c_bg", pc[0])
		mat.set_shader_param("c_line", pc[1])
		mat.set_shader_param("c_accent", pc[2])
		return
	for k in DEFAULT_COLORS.keys():
		mat.set_shader_param(k, DEFAULT_COLORS[k])
	# (your own colours: the background, the thin lines, the bright lines)
	var mine := MenuStyle.bg_colors()
	if not mine.empty():
		mat.set_shader_param("bg_color", mine[0])
		var minor: Color = mine[1]
		minor.a = 0.75
		mat.set_shader_param("minor_color", minor)
		for k in ["major_a", "major_c"]:
			mat.set_shader_param(k, mine[2])
		for k in ["major_b", "major_d"]:
			mat.set_shader_param(k, Color(mine[2]).linear_interpolate(Color(mine[1]).lightened(0.3), 0.5))
		return
	if not Rhythia.wave_menu_colorset and preload("res://scripts/ui/menu/Seasonal.gd").halloween():
		for k in HALLOWEEN_COLORS.keys():
			mat.set_shader_param(k, HALLOWEEN_COLORS[k])
		return
	if not Rhythia.wave_menu_colorset and preload("res://scripts/ui/menu/Seasonal.gd").christmas():
		for k in CHRISTMAS_COLORS.keys():
			mat.set_shader_param(k, CHRISTMAS_COLORS[k])
		return
	if not Rhythia.wave_menu_colorset or Rhythia.selected_colorset == null:
		return
	for c in Rhythia.selected_colorset.real_colors:
		_cs_colors.append(Color(c.r, c.g, c.b, 1.0))
	if _cs_colors.empty():
		return
	mat.set_shader_param("color_count", float(min(_cs_colors.size(), 4)))
	_update_cycle()

func _cs_color_at(pos: float) -> Color:
	var n := _cs_colors.size()
	var k := int(floor(pos))
	var f := pos - floor(pos)
	f = f * f * (3.0 - 2.0 * f) # ease between colours
	return _cs_colors[posmod(k, n)].linear_interpolate(_cs_colors[posmod(k + 1, n)], f)

func _update_cycle():
	var mat: ShaderMaterial = _cur_mat
	if mat == null or _cs_colors.empty():
		return
	var n := _cs_colors.size()
	# Spread the 4 line slots across the colorset, then slide them all along.
	var spread: float = max(1.0, float(n) / 4.0)
	var names = ["major_a", "major_b", "major_c", "major_d"]
	for i in range(4):
		mat.set_shader_param(names[i], _cs_color_at(_cs_phase + i * spread))
	var base: Color = _cs_color_at(_cs_phase)
	mat.set_shader_param("bg_color", base.darkened(0.88))
	var minor: Color = base.darkened(0.45)
	minor.a = 0.75
	mat.set_shader_param("minor_color", minor)

func _process(delta):
	if _lr_vp != null and visible:
		_lr_frame += 1
		if _lr_frame % 2 == 0:
			_lr_vp.render_target_update_mode = Viewport.UPDATE_ONCE
	if visible and _cs_colors.size() > 1:
		_cs_phase = fmod(_cs_phase + delta / COLOR_STEP_SECONDS, float(_cs_colors.size()))
		_update_cycle()

func _apply(_v = null):
	_apply_colors()
	visible = Rhythia.wave_menu
	if Rhythia.wave_menu:
		_add_outlines(get_parent())
	else:
		_remove_outlines()

func _outlined_copy(f: DynamicFont) -> DynamicFont:
	if _outline_copies.has(f):
		return _outline_copies[f]
	var c: DynamicFont = f.duplicate()
	c.outline_size = max(f.outline_size, 1 if f.size <= 18 else 2)
	c.outline_color = Color(0, 0, 0, 1)
	_outline_copies[f] = c
	return c

func _is_light(col: Color) -> bool:
	return col.a > 0.3 and (0.299 * col.r + 0.587 * col.g + 0.114 * col.b) > 0.45

func _add_outlines(n: Node):
	if n == self:
		return
	_outline_one(n)
	for c in n.get_children():
		_add_outlines(c)

func _outline_one(n: Node):
	if (n is Label or n is Button or n is RichTextLabel) and not _changed.has(n):
		var prop: String = "custom_fonts/normal_font" if n is RichTextLabel else "custom_fonts/font"
		var color_name: String = "default_color" if n is RichTextLabel else "font_color"
		var f = n.get_font("normal_font" if n is RichTextLabel else "font")
		if f is DynamicFont and f.outline_size == 0 and _is_light(n.get_color(color_name)):
			_changed[n] = [prop, n.get(prop)]
			n.set(prop, _outlined_copy(f))

func _remove_outlines():
	for n in _changed.keys():
		if is_instance_valid(n):
			n.set(_changed[n][0], _changed[n][1])
	_changed.clear()

# (Menu Customizer: the pattern or its colours changed)
func restyle():
	_apply_colors()

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	add_to_group("menu_style")
	_mat_contour = ShaderMaterial.new()
	_mat_contour.shader = load("res://assets/shaders/wave_menu.shader")
	_mat_pattern = ShaderMaterial.new()
	_mat_pattern.shader = load("res://assets/shaders/menu_patterns.shader")
	_set_mat(_mat_contour)
	if Rhythia.vr:
		_make_lowres()
	# the rest of the Menu Customizer's look (buttons, sidebar, tint)
	get_parent().call_deferred("add_child", MenuStyle.new())
	Rhythia.connect("wave_menu_changed", self, "_apply")
	Rhythia.connect("wave_menu_colorset_changed", self, "_apply_colors")
	Rhythia.connect("selected_colorset_changed", self, "_apply_colors")
	# Wait a frame so the map list and other menu parts exist before outlining.
	yield(get_tree(), "idle_frame")
	_apply()
	# Map buttons and popups appear later: outlined as they're added, a few
	# each frame. (Walking the whole menu every 3 seconds for them made a
	# small stutter every 3 seconds, worst on the Quest.)
	get_tree().connect("node_added", self, "_on_node_added")

var _new_nodes := []
func _on_node_added(n: Node):
	if not Rhythia.wave_menu or not (n is Label or n is Button or n is RichTextLabel):
		return
	if _new_nodes.empty():
		call_deferred("_outline_new")
	_new_nodes.append(n)

func _outline_new():
	var list := _new_nodes
	_new_nodes = []
	var parent = get_parent()
	for n in list:
		if is_instance_valid(n) and n.is_inside_tree() and parent != null and parent.is_a_parent_of(n):
			_outline_one(n)
	for n in _changed.keys():
		if not is_instance_valid(n):
			_changed.erase(n)

func _exit_tree():
	_remove_outlines()
