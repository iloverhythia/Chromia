extends SpinBox

func upd():
	Rhythia.spawn_distance = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.spawn_distance: upd()

func _ready():
	connect("changed",self,"upd")
	value = Rhythia.spawn_distance
