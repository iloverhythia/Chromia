extends Control

# A quick tap can press and release in the same frame, which the game would
# never see as a press, so a release always waits for the next frame.
var _pressed_frame := {}

func _press(action: String):
	_pressed_frame[action] = Engine.get_idle_frames()
	Input.action_press(action)

func _release(action: String):
	while Engine.get_idle_frames() <= int(_pressed_frame.get(action, -1)) + 1:
		yield(get_tree(), "idle_frame")
	Input.action_release(action)

func _on_Pause_pressed():
	_press("pause")

func _on_Pause_released():
	_release("pause")

func _on_GiveUp_pressed():
	_press("give_up")

func _on_GiveUp_released():
	_release("give_up")

func _ready():
	var tween: Tween = Tween.new()
	add_child(tween)

	$Pause/Button.visible = Rhythia.device("mobile")
	$GiveUp/Button.visible = Rhythia.device("mobile")

	if Rhythia.mirror_buttons:
		$Pause/Button.position.x = OS.get_window_safe_area().size.x - 150
		$GiveUp/Button.position.x = OS.get_window_safe_area().size.x - 150

	tween.interpolate_property($Pause, "modulate", Color(1, 1, 1, 0.5), Color(1, 1, 1, 0), 1, Tween.TRANS_QUAD, Tween.EASE_IN_OUT, 1)
	tween.start()
	tween.interpolate_property($GiveUp, "modulate", Color(1, 1, 1, 0.5), Color(1, 1, 1, 0), 1, Tween.TRANS_QUAD, Tween.EASE_IN_OUT, 1)
	tween.start()
