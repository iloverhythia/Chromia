extends SpinBox

# Settings > Notes > Note Brightness (Rhythia.note_brightness): 100% is the
# colorset as it is, less is darker, more goes towards white. Made next to
# Note Opacity by NoteOpacity.gd.

func upd():
	Rhythia.note_brightness = clamp(value / 100.0, 0.1, 2.0)

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if not is_equal_approx(value / 100.0, Rhythia.note_brightness): upd()

func _ready():
	min_value = 10
	max_value = 200
	value = Rhythia.note_brightness * 100.0
	connect("changed", self, "upd")
