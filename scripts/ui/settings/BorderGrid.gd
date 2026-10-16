extends GridContainer

var cards := {}

func _ready():
	set("custom_constants/vseparation", 10)
	set("custom_constants/hseparation", 10)
	_rebuild()
	Rhythia.connect("selected_border_changed", self, "_upd")
	Rhythia.connect("borders_changed", self, "_rebuild")

func _rebuild():
	for entry in cards.values():
		entry.card.queue_free()
	cards.clear()
	var ui_theme = load("res://uitheme.tres")
	for b in Rhythia.registry_border.items:
		var border: Border = b
		var card := PanelContainer.new()
		card.rect_min_size = Vector2(120, 140)

		var v := VBoxContainer.new()
		v.add_constant_override("separation", 6)
		card.add_child(v)

		var preview := TextureRect.new()
		preview.rect_min_size = Vector2(0, 80)
		preview.expand = true
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var tex = null
		if border.path != "":
			tex = Globals.imageLoader.load_if_exists(border.path)
		if tex == null:
			tex = load("res://assets/images/grid_outer.png")
		preview.texture = tex
		v.add_child(preview)

		var name_label := Label.new()
		name_label.text = border.name
		name_label.theme = ui_theme
		name_label.align = Label.ALIGN_CENTER
		name_label.clip_text = true
		name_label.hint_tooltip = border.name + ("\nby " + border.creator if border.creator != "" else "")
		v.add_child(name_label)

		var select_btn := Button.new()
		select_btn.text = "Select"
		select_btn.theme = ui_theme
		select_btn.connect("pressed", Rhythia, "select_border", [border])
		v.add_child(select_btn)

		cards[border.id] = {"card": card, "btn": select_btn}
		call_deferred("add_child", card)
	_upd()

func _upd(_b = null):
	for id in cards.keys():
		var is_sel = Rhythia.selected_border != null and Rhythia.selected_border.id == id
		cards[id].btn.disabled = is_sel
		cards[id].btn.text = "Selected" if is_sel else "Select"
