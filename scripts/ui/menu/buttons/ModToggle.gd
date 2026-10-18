extends CheckBox
# A mod checkbox bound to a Rhythia bool property (set `prop` before adding it).

var prop: String = ""

func _ready():
	pressed = bool(Rhythia.get(prop))
	Rhythia.connect("mods_changed", self, "_upd")
	connect("toggled", self, "_on_toggled")

func _upd():
	var v := bool(Rhythia.get(prop))
	if pressed != v:
		pressed = v

func _on_toggled(on: bool):
	if bool(Rhythia.get(prop)) != on:
		Rhythia.set(prop, on)
