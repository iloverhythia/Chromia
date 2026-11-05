extends SpinBox

# Shown as a percentage; stored as 0.0-1.0 in Rhythia.trail_opacity.
func upd():
	Rhythia.trail_opacity = clamp(value / 100.0, 0.0, 1.0)

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if not is_equal_approx(value / 100.0, Rhythia.trail_opacity): upd()

func _ready():
	value = Rhythia.trail_opacity * 100.0
	connect("changed", self, "upd")
