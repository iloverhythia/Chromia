extends GridContainer

export(String) var kind = "hit"

onready var base = $Card

var cards := {}
var _preview := AudioStreamPlayer.new()

func _registry() -> Registry:
	return Rhythia.registry_hit_sound if kind == "hit" else Rhythia.registry_miss_sound

func _selected():
	return Rhythia.selected_hit_sound if kind == "hit" else Rhythia.selected_miss_sound

func _ready():
	add_child(_preview)
	base.visible = false
	_rebuild()
	if kind == "hit":
		Rhythia.connect("hit_sounds_changed", self, "_rebuild")
		Rhythia.connect("selected_hit_sound_changed", self, "_upd")
	else:
		Rhythia.connect("miss_sounds_changed", self, "_rebuild")
		Rhythia.connect("selected_miss_sound_changed", self, "_upd")

func _rebuild(_a = null):
	for c in cards.values():
		c.queue_free()
	cards.clear()
	for snd in _registry().items:
		var card = base.duplicate()
		card.visible = true
		card.get_node("V/Name").text = snd.name
		card.get_node("V/Row1/Play").connect("pressed", self, "_on_play_pressed", [snd])
		card.get_node("V/Row1/Select").connect("pressed", self, "_on_select_pressed", [snd])
		if snd.id == "default":
			card.get_node("V/Row2").visible = false
		else:
			card.get_node("V/Row2/Rename").connect("pressed", self, "_on_rename_pressed", [snd])
			card.get_node("V/Row2/Delete").connect("pressed", self, "_on_delete_pressed", [snd])
		cards[snd.id] = card
		call_deferred("add_child", card)
	_upd()

func _upd(_a = null):
	var sel = _selected()
	for id in cards.keys():
		var select_btn = cards[id].get_node("V/Row1/Select")
		var is_sel = (sel != null and sel.id == id)
		select_btn.disabled = is_sel
		select_btn.text = "Selected" if is_sel else "Select"

func _on_play_pressed(snd):
	var is_hit = kind == "hit"
	var stream_path = snd.path
	if stream_path == "":
		stream_path = "user://hit" if is_hit else "user://miss"
	var default_stream = Rhythia.def_hit_snd if is_hit else Rhythia.def_miss_snd
	_preview.stream = Rhythia.get_stream_with_default(stream_path, default_stream)
	_preview.play()

func _on_select_pressed(snd):
	if kind == "hit":
		Rhythia.select_hit_sound(snd)
	else:
		Rhythia.select_miss_sound(snd)

func _on_rename_pressed(snd):
	Globals.string_prompt.open(
		"Rename this sound",
		"Rename Sound",
		snd.name,
		[{text = "OK"}, {text = "Cancel", wait = 0}]
	)
	var response = yield(Globals.string_prompt, "option_selected")
	Globals.string_prompt.close()
	if response == 0:
		var new_name = Globals.string_prompt.input.get_text().strip_edges()
		if new_name != "":
			Rhythia.rename_named_sound(kind, snd, new_name)

func _on_delete_pressed(snd):
	Globals.confirm_prompt.open(
		"Delete \"%s\"? This can't be undone." % snd.name,
		"Delete Sound",
		[{text = "Cancel"}, {text = "Delete", wait = 1}]
	)
	var response = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	if response == 1:
		Rhythia.delete_named_sound(kind, snd)
