extends SpinBox

func upd():
	Rhythia.note_opacity = clamp(value / 100,0,1)

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if (value / 100) != Rhythia.note_opacity: upd()

func _ready():
	value = Rhythia.note_opacity * 100
	connect("changed",self,"upd")
