extends SpinBox

func upd():
	if value < 15 and value != 0:
		value = 15
	Engine.target_fps = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Engine.target_fps: upd()
	
func _ready():
	value = Engine.target_fps
	connect("changed",self,"upd")
