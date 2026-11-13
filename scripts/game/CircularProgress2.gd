extends Control

onready var spin = $Spin
export(float) var percent = 0 setget _set_percent
export(Color) var fill_color = Color.white setget _set_fill
export(Color) var empty_color = Color("#6f6f6f") setget _set_empty

var ready:bool = false

# (spin.update(): a shader value announces nothing, and the HUD only redraws
# a panel when something on it says it changed, HUD.gd _hud_changed)
func _set_fill(v:Color):
	if ready and v == fill_color: return
	fill_color = v
	if ready:
		spin.material.set_shader_param("fill_color",fill_color)
		spin.update()

func _set_empty(v:Color):
	if ready and v == empty_color: return
	empty_color = v
	if ready:
		spin.material.set_shader_param("empty_color",empty_color)
		spin.update()

func _update_progress(value:float=percent):
	if ready:
		spin.material.set_shader_param("value",percent)
		spin.update()

func _set_percent(value:float):
	if ready and value == percent: return
	percent = value
	_update_progress()

func _ready():
	spin.material = spin.material.duplicate()
	spin.material.set_shader_param("fill_color",fill_color)
	spin.material.set_shader_param("empty_color",empty_color)
	spin.material.set_shader_param("value",percent)
	ready = true
