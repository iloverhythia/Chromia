extends SpinBox

func upd():
	Rhythia.absolute_scale = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.absolute_scale: upd()
	
func _ready():
	value = Rhythia.absolute_scale
	connect("changed",self,"upd")
