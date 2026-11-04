extends SpinBox

func upd():
	Rhythia.approach_rate = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.approach_rate: upd()

func _ready():
	value = Rhythia.approach_rate
	connect("changed",self,"upd")
