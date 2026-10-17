extends MenuButton

var presets = [
	{ name = "Normal", additive = false, exponential = false, instant = false },
	{ name = "Additive", additive = true, exponential = false, instant = false },
	{ name = "Exponential", additive = false, exponential = true, instant = false },
	# Kicks the FOV on hit, then snaps straight back to your FOV setting.
	{ name = "Instant", additive = false, exponential = false, instant = true },
]

func on_pressed(i):
	var preset = presets[i]
	Rhythia.hit_fov_additive = preset.additive
	Rhythia.hit_fov_exponential = preset.exponential
	Rhythia.hit_fov_instant = preset.instant
	$Desc.text = "Mode: " + preset.name

func _ready():
	for i in range(presets.size()):
		get_popup().add_item(presets[i].name,i)
	get_popup().connect("id_pressed",self,"on_pressed")

	if Rhythia.hit_fov_instant:
		$Desc.text = "Mode: Instant"
	elif not Rhythia.hit_fov_additive and not Rhythia.hit_fov_exponential:
		$Desc.text = "Mode: Normal"
	elif Rhythia.hit_fov_additive and not Rhythia.hit_fov_exponential:
		$Desc.text = "Mode: Additive"
	elif not Rhythia.hit_fov_additive and Rhythia.hit_fov_exponential:
		$Desc.text = "Mode: Exponential"
	else:
		$Desc.text = "Mode: ?"
