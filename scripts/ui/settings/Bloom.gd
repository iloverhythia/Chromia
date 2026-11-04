extends SpinBox

func upd():
	Rhythia.bloom = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.bloom: upd()

func _ready():
	value = Rhythia.bloom
	connect("changed",self,"upd")
