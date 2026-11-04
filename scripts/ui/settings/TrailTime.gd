extends SpinBox

func upd():
	Rhythia.trail_time = float(str(value))

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if float(str(value)) != float(str(Rhythia.trail_time)): upd()

func _ready():
	value = float(str(Rhythia.trail_time))
	connect("changed",self,"upd")
