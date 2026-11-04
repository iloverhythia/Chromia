extends SpinBox

func upd():
	Rhythia.glow = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.glow: upd()

func _ready():
	value = Rhythia.glow
	connect("changed",self,"upd")
