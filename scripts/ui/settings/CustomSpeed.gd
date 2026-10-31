extends SpinBox

# The custom speed box. What you type sets the speed; a speed set from
# elsewhere (a lobby host's mods, the player you spectate, a settings profile)
# shows up here. Before, the box pushed its own number back every frame, so
# spectating someone at 93% while yours said 300 snapped the speed back to 300.

var _shown: float = 0.0 # the speed (x100) the box last showed or set

func upd():
	_shown = value
	Rhythia.custom_speed = value / 100

func _process(_d):
	if not is_equal_approx(value, _shown):
		upd() # you changed the box
	elif not is_equal_approx(Rhythia.custom_speed * 100, value):
		value = Rhythia.custom_speed * 100 # the speed changed elsewhere: show it
		_shown = value # (what the box shows, rounded: so it isn't taken as your edit)

func _ready():
	value = Rhythia.custom_speed * 100
	_shown = value
	connect("changed", self, "upd")
	get_line_edit().connect("text_entered", self, "_on_line_edit_text_entered")

func _on_line_edit_text_entered(_new_text):
	get_line_edit().release_focus()
