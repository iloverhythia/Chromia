extends HSlider

func value_changed(value):
	Rhythia.mod_360_speed = value
	upd_label()

func on_map_selected(_map):
	pass

func _ready():
	connect("value_changed", self, "value_changed")
	$SpeedTextBox.connect("text_entered", self, "speed_text_entered")
	Rhythia.connect("selected_song_changed", self, "on_map_selected")

	min_value = -5
	max_value = 5
	step = 0.01

	value = Rhythia.mod_360_speed

	upd_label()

func speed_text_entered(new_text):
	var speed = float(new_text)
	self.value = clamp(speed, min_value, max_value)

func upd_label():
	$SpeedTextBox.text = str(value)
