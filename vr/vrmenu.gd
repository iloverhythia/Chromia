extends Spatial

func _ready():
	Rhythia.vr_menu = $PointerScreen # VRPlayer.recenter_to_head puts it back in front of you
	$PointerScreen.set_meta("home", $PointerScreen.transform)
