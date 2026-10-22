extends SpinBox

# A number setting for Sound Space Mode's health / progress bars
# (Rhythia.ss_health_y, ss_health_w, ss_progress_y, ss_progress_w).
export var target := ""

func _ready():
	value = float(Rhythia.get(target))
	connect("value_changed", self, "_on_value")

func _on_value(v: float):
	Rhythia.set(target, v)

func _process(_d):
	var cur := float(Rhythia.get(target))
	if not is_equal_approx(cur, value):
		value = cur
