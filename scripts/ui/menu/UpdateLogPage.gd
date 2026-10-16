extends Control

func _ready():
	$Scroll/V/L.text = Rhythia.get_update_log_text()
