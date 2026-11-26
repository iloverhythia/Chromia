extends SpinBox

# Settings > World & Cursor > Cursor: how see-through your co-op partner's
# cursor is on your screen (NoteManager's co-op part; only yours: they see
# theirs as they set it). 0 hides it. Put next to Cursor Scale by CursorScale.gd.

func upd(_v = null):
	Rhythia.partner_cursor_opacity = clamp(value / 100.0, 0.0, 1.0)

func _ready():
	min_value = 0
	max_value = 100
	step = 5
	suffix = "%"
	allow_greater = false
	value = round(Rhythia.partner_cursor_opacity * 100.0)
	connect("value_changed", self, "upd")

# made from the Cursor Scale row (CursorScale.gd): the same look, its own setting
static func add_next_to(row: Control):
	var parent = row.get_parent() if row != null else null
	if parent == null or parent.has_node("PartnerCursorOpacity"):
		return
	var copy: Control = row.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_USE_INSTANCING) # (not its script)
	copy.name = "PartnerCursorOpacity"
	var tip := "[def. 80%] how see-through your co-op partner's cursor is on your screen (0% hides it)"
	copy.hint_tooltip = tip
	var box = copy.get_node_or_null("CursorScale")
	if box is SpinBox:
		box.name = "PartnerCursorOpacity"
		box.hint_tooltip = tip
		box.set_script(load("res://scripts/ui/settings/PartnerCursorOpacity.gd"))
	var label = copy.get_node_or_null("Label")
	if label is Label:
		label.text = "Co-op Partner Cursor"
	parent.add_child(copy)
	parent.move_child(copy, row.get_index() + 1)
