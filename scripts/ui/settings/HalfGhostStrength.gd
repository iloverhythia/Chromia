extends SpinBox

# Shown as a percentage; stored as 0.1-1.0 in Rhythia.half_ghost_strength.
func upd():
	Rhythia.half_ghost_strength = clamp(value / 100.0, 0.1, 1.0)

func _process(_d):
	if not is_equal_approx(value / 100.0, Rhythia.half_ghost_strength): upd()

func _ready():
	value = Rhythia.half_ghost_strength * 100.0
	connect("changed", self, "upd")
