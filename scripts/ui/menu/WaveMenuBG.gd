extends ColorRect

# "Wave menu" (experimental setting): replaces the menu's dark background with
# an animated contour-line shader.

func _apply(_v = null):
	visible = Rhythia.wave_menu

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	show_behind_parent = false
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/wave_menu.shader")
	material = mat
	_apply()
	Rhythia.connect("wave_menu_changed", self, "_apply")
