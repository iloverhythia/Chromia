extends SpinBox

# Settings > Notes: when Half Ghost starts fading a note out, in ms before you
# hit it (Rhythia.half_ghost_ms; NoteManager: the fade ends at a quarter of
# it). The same time at any approach rate. Put under Half Ghost Strength by
# HalfGhostStrength.gd.

func upd(_v = null):
	Rhythia.half_ghost_ms = clamp(value, 20.0, 2000.0)

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if not is_equal_approx(value, Rhythia.half_ghost_ms): upd()

func _ready():
	min_value = 20
	max_value = 2000
	step = 10
	suffix = "ms"
	allow_greater = false
	value = Rhythia.half_ghost_ms
	connect("value_changed", self, "upd")

# made from the Half Ghost Strength row: the same look, its own setting
static func add_next_to(row: Control):
	var parent = row.get_parent() if row != null else null
	if parent == null or parent.has_node("HalfGhostTime"):
		return
	var copy: Control = row.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_USE_INSTANCING) # (not its script)
	copy.name = "HalfGhostTime"
	var tip := "[def. 240 ms] how long before you hit a note Half Ghost starts fading it out (it's faded fully at a quarter of that)"
	copy.hint_tooltip = tip
	var box = copy.get_node_or_null("Strength")
	if box is SpinBox:
		box.name = "Time"
		box.hint_tooltip = tip
		box.set_script(load("res://scripts/ui/settings/HalfGhostTime.gd"))
	var label = copy.get_node_or_null("Label")
	if label is Label:
		label.text = "Half Ghost Start"
	parent.add_child(copy)
	parent.move_child(copy, row.get_index() + 1)
