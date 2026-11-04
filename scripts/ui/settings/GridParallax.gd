extends SpinBox

func upd():
	Rhythia.grid_parallax = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.grid_parallax: upd()
	
func _ready():
	value = Rhythia.grid_parallax
	connect("changed",self,"upd")
