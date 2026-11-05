extends SpinBox

func upd():
	Rhythia.parallax = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.parallax: upd()
	
func _ready():
	value = Rhythia.parallax
	connect("changed",self,"upd")
