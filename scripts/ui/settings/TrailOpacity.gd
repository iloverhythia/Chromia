extends SpinBox

# Shown as a percentage; stored as 0.0-1.0 in Rhythia.trail_opacity.
func upd():
	Rhythia.trail_opacity = clamp(value / 100.0, 0.0, 1.0)

func _process(_d):
	if not is_equal_approx(value / 100.0, Rhythia.trail_opacity): upd()

func _ready():
	value = Rhythia.trail_opacity * 100.0
	connect("changed", self, "upd")
