extends SpinBox

func upd():
	Rhythia.ui_parallax = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.ui_parallax: upd()
	
func _ready():
	value = Rhythia.ui_parallax
	connect("changed",self,"upd")
