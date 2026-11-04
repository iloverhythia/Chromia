extends SpinBox

func upd():
	Rhythia.fov = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.fov: upd()
	
func _ready():
	value = Rhythia.fov
	connect("changed",self,"upd")
