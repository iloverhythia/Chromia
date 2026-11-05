extends SpinBox

# Your hit window. The box shows the setting and changes it when you do (it
# used to write its number back every frame, which undid other changes, like
# multiplayer's 55 / 58 ms rule in LobbyManager.gd).

var _showing := false

func upd(_v = null):
	if _showing:
		return
	Rhythia.hitwindow_ms = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box keeps yours)
	if value != Rhythia.hitwindow_ms:
		_showing = true
		value = Rhythia.hitwindow_ms
		_showing = false

func _ready():
	value = Rhythia.hitwindow_ms
	connect("value_changed", self, "upd")
