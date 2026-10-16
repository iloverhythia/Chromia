extends Spatial

var state = (Rhythia.replaying and Rhythia.alt_cam)
var debug: bool = OS.has_feature("debug")

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	PhysicsServer.set_active(not Rhythia.visual_mode and (Rhythia.get("cam_unlock") or Rhythia.vr))


	if state:
		$Camera.current = false
		$AltCam.current = true
		$AltCam.set_enabled(true)
		$Game/Avatar.visible = true
		$Game/Avatar/Animations.play("Idle")
		$Game/Avatar/Head/Blinking.play("Blink")
	else:
		$AltCam.set_enabled(false)
		$Game/Avatar.visible = false
		$Camera.current = true
		$AltCam.current = false


	if Rhythia.is_lacunella_enabled():
		$Game/Avatar/Head/Accessories/CubellaHair.visible = true


	if Rhythia.vhs_shader:
		$Camera/VHS.visible = true
		$AltCam/VHS.visible = true
	else:
		$Camera/VHS.visible = false
		$AltCam/VHS.visible = false

func _process(delta):
	if Input.is_action_just_pressed("debug_freecam_toggle") and debug:
		state = not state
		_ready()
	if Input.is_action_just_pressed("retry"):
		var lobby_manager = get_node_or_null("/root/LobbyManager")
		if lobby_manager == null or not lobby_manager.lobby_active:
			get_tree().paused = false
			get_tree().reload_current_scene()
