extends HBoxContainer
# "Custom BG Color" row under "Custom World BG" (World & Cursor tab): the
# Custom Background world shows this color when there's no image, and tints the
# image with it when there is one (white = unchanged).

static func attach(tab_container) -> void:
	if tab_container == null:
		return
	var anchor = tab_container.get_node_or_null("World & Cursor/World/Group/H/CustomBg")
	if anchor == null or anchor.get_parent().has_node("CustomBgColor"):
		return
	var row = load("res://scripts/ui/settings/CustomBgColor.gd").new()
	row.name = "CustomBgColor"
	var parent = anchor.get_parent()
	parent.add_child(row)
	parent.move_child(row, anchor.get_index() + 1)

var picker: ColorPickerButton

func _ready():
	var ui_theme = load("res://uitheme.tres")
	add_constant_override("separation", 6)
	rect_min_size = Vector2(0, 32)
	picker = ColorPickerButton.new()
	picker.rect_min_size = Vector2(200, 32)
	picker.edit_alpha = false
	picker.color = Rhythia.custombg_color
	picker.hint_tooltip = "Background color of the \"Custom Background\" world.\nWith no image it's a solid color; with an image it tints it (white = no tint)."
	picker.connect("color_changed", self, "_on_color")
	picker.connect("popup_closed", self, "_on_closed")
	add_child(picker)
	var reset = Button.new()
	reset.text = "Reset"
	reset.theme = ui_theme
	reset.rect_min_size = Vector2(60, 32)
	reset.focus_mode = Control.FOCUS_NONE
	reset.connect("pressed", self, "_on_reset")
	add_child(reset)
	var l = Label.new()
	l.text = "Custom BG Color"
	l.theme = ui_theme
	var src = get_parent().get_node_or_null("CustomBg/CustomBg/Label")
	if src != null:
		var f = src.get("custom_fonts/font")
		if f: l.add_font_override("font", f)
	l.add_color_override("font_color", Color(0.898039, 0.94902, 1, 1))
	l.valign = Label.VALIGN_CENTER
	add_child(l)

func _on_color(c: Color):
	Rhythia.custombg_color = c

func _on_closed():
	Rhythia.save_settings()

func _on_reset():
	Rhythia.custombg_color = Color(1, 1, 1)
	picker.color = Rhythia.custombg_color
	Rhythia.save_settings()
