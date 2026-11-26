extends SpinBox

func upd():
	Rhythia.cursor_scale = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if value != Rhythia.cursor_scale: upd()

func _ready():
	value = Rhythia.cursor_scale
	connect("changed",self,"upd")
	# (and the co-op partner's cursor opacity in the row under it)
	call_deferred("_add_partner_row")

func _add_partner_row():
	load("res://scripts/ui/settings/PartnerCursorOpacity.gd").add_next_to(get_parent())
