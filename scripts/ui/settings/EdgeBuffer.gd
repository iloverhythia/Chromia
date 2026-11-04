extends SpinBox

func upd():
	Rhythia.edge_drift = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.edge_drift: upd()

func _ready():
	value = Rhythia.edge_drift
	connect("changed",self,"upd")
