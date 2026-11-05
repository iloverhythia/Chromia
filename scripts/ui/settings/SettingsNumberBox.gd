extends SpinBox

export(String) var target

func upd():
	Rhythia.set(target,value)

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.get(target): upd()
	
func _ready():
	value = Rhythia.get(target)
	connect("changed",self,"upd")
