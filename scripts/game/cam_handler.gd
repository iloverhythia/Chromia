extends Spatial

var state = (Rhythia.replaying and Rhythia.alt_cam)
var _c_held := false

func _spectating() -> bool:
	var hud = get_node_or_null("HUD")
	if hud == null:
		hud = find_node("HUD", true, false)
	return hud != null and bool(hud.get("spectating"))
var debug: bool = OS.has_feature("debug")

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	PhysicsServer.set_active(not Rhythia.visual_mode and (Rhythia.spin_now() or Rhythia.vr))


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


	# your avatar (Settings > Player Avatar); the player's own while you watch
	# them with their settings (SpectateSettings sends it)
	load("res://scripts/avatar/AvatarLook.gd").apply($Game/Avatar, Rhythia.get("avatar"))
	if Rhythia.is_lacunella_enabled():
		$Game/Avatar/Head/Accessories/CubellaHair.visible = true


	# background brightness (Settings > Background Editor)
	var veil = load("res://scripts/game/BgVeil.gd")
	veil.add_to($Camera)
	veil.add_to($AltCam)
	if Rhythia.vr and Rhythia.vr_player != null and "head" in Rhythia.vr_player:
		veil.add_to(Rhythia.vr_player.head)

	if Rhythia.vhs_shader:
		$Camera/VHS.visible = true
		$AltCam/VHS.visible = true
	else:
		$Camera/VHS.visible = false
		$AltCam/VHS.visible = false

# 3rd person (the alternate camera, your avatar playing): 3 while you watch a
# replay or spectate someone (not in VR: there the HUD moves you instead)
func set_third_person(on: bool, look = null):
	if Rhythia.vr:
		return
	state = on
	$Camera.current = not on
	$AltCam.current = on
	$AltCam.set_enabled(on)
	$Game/Avatar.visible = on
	if on:
		$Game/Avatar/Animations.play("Idle")
		$Game/Avatar/Head/Blinking.play("Blink")
		if look != null:
			load("res://scripts/avatar/AvatarLook.gd").apply($Game/Avatar, look)

func _process(delta):
	if Input.is_action_just_pressed("debug_freecam_toggle") and debug:
		state = not state
		_ready()
	if not Rhythia.vr and Input.is_key_pressed(KEY_3) and not _c_held and Rhythia.replaying and not _spectating(): # (spectating: HUD.gd)
		set_third_person(not state)
	_c_held = Input.is_key_pressed(KEY_3)
	if Input.is_action_just_pressed("retry"):
		var lobby_manager = get_node_or_null("/root/LobbyManager")
		if lobby_manager == null or not lobby_manager.lobby_active:
			get_tree().paused = false
			Rhythia.set_meta("quick_retry", true) # (Game.gd: fades in quickly)
			get_tree().reload_current_scene()

func _exit_tree():
	# (the VR headset's camera stays when the song ends: its veil goes)
	if Rhythia.vr and Rhythia.vr_player != null and "head" in Rhythia.vr_player:
		load("res://scripts/game/BgVeil.gd").remove_from(Rhythia.vr_player.head)
	# (this is the last of the song's nodes to leave: after this line the
	# engine frees them, and the next scene's first line follows)
	Rhythia.trail("song scene: left")
