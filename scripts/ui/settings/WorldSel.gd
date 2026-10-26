extends MenuButton
# Background setting. Pressing it opens WorldPicker.gd: a scrollable grid with
# every background that fits the screen. (The old dropdown list ran off the
# bottom of the screen once there were more backgrounds than fit, e.g. on phones.)

var worlds:Array = []
var _picker = null

func on_world_selected(selected_world:BackgroundWorld):
	if selected_world != null:
		text = selected_world.name

func _ready():
	worlds = Rhythia.registry_world.get_items()
	Rhythia.connect("selected_space_changed",self,"on_world_selected")
	# the built-in dropdown stays empty; it is closed as soon as it opens
	var pop = get_popup()
	pop.modulate = Color(1, 1, 1, 0)
	pop.connect("about_to_show", self, "_open_picker")
	on_world_selected(Rhythia.selected_space)

func _open_picker():
	get_popup().call_deferred("hide")
	if _picker != null and is_instance_valid(_picker):
		return
	_picker = preload("res://scripts/ui/settings/WorldPicker.gd").new()
	_picker.worlds = worlds
	_picker.selected = Rhythia.selected_space
	_picker.connect("picked", self, "_on_picked")
	# same viewport as the button (the VR menu draws the settings in its own one)
	get_viewport().add_child(_picker)

func _on_picked(w):
	Rhythia.select_world(w)
