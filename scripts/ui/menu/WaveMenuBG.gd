extends ColorRect

# "Wave menu" (experimental setting): replaces the menu's dark background with
# an animated contour-line shader, and gives the menu's text black outlines so
# it stays readable on top of the lines.

# Only light-coloured text gets an outline (black outlines on black button text
# would make it unreadable). Outlined copies of each font are made once and
# applied per control, so the original fonts are never changed.
var _outline_copies: Dictionary = {} # original DynamicFont -> outlined copy
var _changed: Dictionary = {}        # Control -> [property, original value]

func _apply(_v = null):
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
