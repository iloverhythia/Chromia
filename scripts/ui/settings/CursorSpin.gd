extends SpinBox

func upd():
	Rhythia.cursor_spin = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.cursor_spin: upd()

func _ready():
	value = Rhythia.cursor_spin
	connect("changed",self,"upd")
