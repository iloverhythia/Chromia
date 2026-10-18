extends ColorRect

# "Wave menu" (experimental setting): replaces the menu's dark background with
# an animated contour-line shader, and gives the menu's text black outlines so
# it stays readable on top of the lines.

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

# Wave colours: the default pink/orange, or (option) the selected colorset.
# In colorset mode the lines fade through every colour in the set over time.
const COLOR_STEP_SECONDS = 3.0
var _cs_colors: Array = []
var _cs_phase: float = 0.0

func _apply_colors(_v = null):
	var mat: ShaderMaterial = material
	if mat == null: return
	for k in DEFAULT_COLORS.keys():
		mat.set_shader_param(k, DEFAULT_COLORS[k])
	_cs_colors = []
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
	var mat: ShaderMaterial = material
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
	if (n is Label or n is Button or n is RichTextLabel) and not _changed.has(n) and n.is_visible_in_tree():
		var prop: String = "custom_fonts/normal_font" if n is RichTextLabel else "custom_fonts/font"
		var color_name: String = "default_color" if n is RichTextLabel else "font_color"
		var f = n.get_font("normal_font" if n is RichTextLabel else "font")
		if f is DynamicFont and f.outline_size == 0 and _is_light(n.get_color(color_name)):
			_changed[n] = [prop, n.get(prop)]
			n.set(prop, _outlined_copy(f))
	for c in n.get_children():
		_add_outlines(c)

func _remove_outlines():
	for n in _changed.keys():
		if is_instance_valid(n):
			n.set(_changed[n][0], _changed[n][1])
	_changed.clear()

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/wave_menu.shader")
	material = mat
	Rhythia.connect("wave_menu_changed", self, "_apply")
	Rhythia.connect("wave_menu_colorset_changed", self, "_apply_colors")
	Rhythia.connect("selected_colorset_changed", self, "_apply_colors")
	# Wait a frame so the map list and other menu parts exist before outlining.
	yield(get_tree(), "idle_frame")
	_apply()
	# Map buttons and popups appear later; pick up any new fonts now and then.
	var t := Timer.new()
	t.wait_time = 3.0
	t.autostart = true
	t.connect("timeout", self, "_refresh")
	add_child(t)

func _refresh():
	if Rhythia.wave_menu:
		for n in _changed.keys():
			if not is_instance_valid(n): _changed.erase(n)
		_add_outlines(get_parent())

func _exit_tree():
	_remove_outlines()
