extends Spatial

func _ready():
	Rhythia.vr_menu = $PointerScreen # VRPlayer.recenter_to_head moves it in front of you
