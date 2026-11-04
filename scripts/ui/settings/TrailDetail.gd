extends SpinBox

func upd():
	Rhythia.trail_detail = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.trail_detail: upd()

func _ready():
	value = Rhythia.trail_detail
	connect("changed",self,"upd")
