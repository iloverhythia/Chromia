extends Control

export(String) var target_bus

var updating:bool = false

func update_db(db:float):
	updating = true
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(target_bus),db)
	$percent.value = db2linear(db) * 100
	$db.value = db
	updating = false

func update_from_percent(_v=null):
	if !updating:
		print("updating from percent")
		update_db(linear2db($percent.value / 100))

func update_from_db(_v=null):
	if !updating:
		print("updating from db")
		update_db($db.value)

func _ready():
	update_db(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(target_bus)))
	$percent.connect("value_changed",self,"update_from_percent")
	$db.connect("value_changed",self,"update_from_db")
	if target_bus == "Music":
		call_deferred("_add_lyric_row")

# "Menu Music Lyrics", under Music Volume: 100% = normal, 0% = instrumental
# (scripts/ui/menu/MenuVocals.gd).
func _add_lyric_row():
	var parent = get_parent()
	if parent == null or parent.has_node("MenuLyrics"):
		return
	var row := HBoxContainer.new()
	row.name = "MenuLyrics"
	var box := SpinBox.new()
	box.rect_min_size = $percent.rect_min_size
	box.theme = $percent.theme
	box.min_value = 0
	box.max_value = 100
	box.step = 1
	box.suffix = "%"
	box.value = round(Rhythia.menu_lyric_volume * 100)
	box.hint_tooltip = "How loud the singing is in the menu music. 0% turns it into an instrumental (works best on songs mixed in stereo)."
	box.connect("value_changed", self, "_on_lyrics_changed")
	row.add_child(box)
	var spacer := Control.new()
	spacer.rect_min_size = Vector2($db.rect_min_size.x, 0)
	row.add_child(spacer)
	var label: Label = $Label.duplicate()
	label.text = "Menu Music Lyrics"
	row.add_child(label)
	parent.add_child(row)
	parent.move_child(row, get_index() + 1)

func _on_lyrics_changed(v: float):
	Rhythia.menu_lyric_volume = clamp(v / 100.0, 0.0, 1.0)
	preload("res://scripts/ui/menu/MenuVocals.gd").apply(Rhythia.menu_lyric_volume)
	Rhythia.save_settings()
