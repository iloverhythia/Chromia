extends Node

# The Settings button for StorageMove.gd (next to Open user folder, added by
# UserDir.gd): pick a folder, confirm, then a progress panel while the files
# are copied, with Cancel. Added as a child of its button.

const SM := "res://scripts/StorageMove.gd"

var _mover = null
var _layer: CanvasLayer = null
var _label: Label = null
var _cancel: Button = null

static func add_next_to(next_to: Control):
	if not load(SM).available() or next_to == null or next_to.get_parent() == null or next_to.get_parent().has_node("MoveMaps"):
		return
	var b := Button.new()
	b.name = "MoveMaps"
	b.text = "Move maps & replays..."
	b.hint_tooltip = "Move your maps, packs and replays to another folder or drive (for when the drive Chromia is on is running out of room).\nNow: %s" % load(SM).current_location()
	b.size_flags_horizontal = next_to.size_flags_horizontal
	b.size_flags_vertical = next_to.size_flags_vertical
	b.rect_min_size = next_to.rect_min_size
	next_to.get_parent().add_child(b)
	next_to.get_parent().move_child(b, next_to.get_index() + 1)
	var ui = load("res://scripts/StorageMoveUI.gd").new()
	b.add_child(ui)

func _ready():
	var b = get_parent()
	if b is Button:
		b.connect("pressed", self, "_pressed")

func _pressed():
	if _mover != null:
		return
	Globals.file_sel.raise()
	Globals.file_sel.open_folder(self, "picked", load(SM).current_location())

func picked(folder: String):
	if folder == "":
		return
	var to: String = folder.replace("\\", "/").trim_suffix("/")
	if to.get_file().to_lower() != "chromia":
		to = to.plus_file("Chromia") # (its own folder in what was picked)
	Globals.confirm_prompt.open(
		"Move your maps, packs and replays to\n%s ?\n\nThey're copied there and checked first, then the old copies are deleted to free the room. With lots of maps this takes a few minutes: keep the game open meanwhile." % to,
		"Move maps & replays",
		[{text = "Cancel"}, {text = "Move"}])
	var opt = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	if int(opt) != 1:
		return
	_show_panel()
	_mover = load(SM).start(get_tree(), to)

func _process(_dt):
	if _mover == null or not is_instance_valid(_mover):
		return
	var m = _mover
	if _label != null:
		_label.text = "Moving your maps and replays...\n\n%d / %d files\n%.1f / %.1f GB" % [
			m.files_done, m.files_total, float(m.bytes_done) / 1073741824.0, float(m.bytes_total) / 1073741824.0]
	if m.state == "copying":
		return
	var ok: bool = m.state == "done"
	Globals.notify(Globals.NOTIFY_SUCCEED if ok else Globals.NOTIFY_WARN, String(m.message), "Move maps & replays", 8.0)
	_hide_panel()
	_mover = null
	var b = get_parent()
	if b is Button:
		b.hint_tooltip = "Move your maps, packs and replays to another folder or drive (for when the drive Chromia is on is running out of room).\nNow: %s" % load(SM).current_location()
	# (the mover lets its thread finish, then goes)
	m.call_deferred("queue_free")

func _show_panel():
	_layer = CanvasLayer.new()
	_layer.layer = 110
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 0.88)
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_STOP # (nothing else while it moves)
	_layer.add_child(bg)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.margin_left = -260
	box.margin_right = 260
	box.margin_top = -90
	box.margin_bottom = 90
	box.alignment = BoxContainer.ALIGN_CENTER
	box.add_constant_override("separation", 16)
	bg.add_child(box)
	_label = Label.new()
	_label.align = Label.ALIGN_CENTER
	var font := DynamicFont.new()
	font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	font.size = 20
	_label.add_font_override("font", font)
	box.add_child(_label)
	_cancel = Button.new()
	_cancel.text = "Cancel"
	_cancel.rect_min_size = Vector2(140, 40)
	_cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel.connect("pressed", self, "_on_cancel")
	box.add_child(_cancel)
	get_tree().root.add_child(_layer)

func _on_cancel():
	if _mover != null and is_instance_valid(_mover):
		_mover.cancel()
		_cancel.disabled = true
		_cancel.text = "Stopping..."

func _hide_panel():
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_label = null
	_cancel = null
