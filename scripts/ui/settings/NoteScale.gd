extends SpinBox

func upd():
	Rhythia.note_size = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.note_size: upd()

func _ready():
	value = Rhythia.note_size
	connect("changed",self,"upd")
