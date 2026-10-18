extends VBoxContainer

# Map folders listed as filters in the Filters column, under "stars".
# Ticking a folder shows only its maps (one folder at a time, like the
# Map Folders panel); unticking shows all maps again.

const MapFolders = preload("res://scripts/MapFolders.gd")

var store
var template: CheckBox

func setup(like: CheckBox):
	template = like
	add_constant_override("separation", like.get_parent().get_constant("separation"))
	store = MapFolders.get_store()
	store.connect("changed", self, "_rebuild")
	_rebuild()

func _rebuild():
	for c in get_children():
		c.queue_free()
	visible = store.folders.size() > 0
	for i in range(store.folders.size()):
		var fd = store.folders[i]
		var cb: CheckBox = template.duplicate(0)
		cb.text = fd.name
		cb.clip_text = true
		cb.hint_tooltip = "only show maps in \"%s\"" % fd.name
		cb.pressed = store.active == i
		for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed", "font_color_focus"]:
			cb.add_color_override(k, fd.color)
		cb.connect("toggled", self, "_on_toggled", [i])
		add_child(cb)

func _on_toggled(on: bool, i: int):
	if on:
		store.set_active(i)
	elif store.active == i:
		store.set_active(-1)

# The folder store outlives the menu, so stop listening when the menu goes.
func _exit_tree():
	if store != null and store.is_connected("changed", self, "_rebuild"):
		store.disconnect("changed", self, "_rebuild")
