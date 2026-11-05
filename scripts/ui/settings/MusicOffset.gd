extends SpinBox

func upd():
	Rhythia.music_offset = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.music_offset: upd()

func _ready():
	connect("changed",self,"upd")
	value = Rhythia.music_offset
