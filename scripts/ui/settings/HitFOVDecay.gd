extends SpinBox

func upd():
	Rhythia.hit_fov_decay = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.hit_fov_decay: upd()
	
func _ready():
	value = Rhythia.hit_fov_decay
	connect("changed",self,"upd")
