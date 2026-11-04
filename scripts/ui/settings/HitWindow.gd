extends SpinBox

func upd():
	Rhythia.hitwindow_ms = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.hitwindow_ms: upd()
	
func _ready():
	value = Rhythia.hitwindow_ms
	connect("changed",self,"upd")
