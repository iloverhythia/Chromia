extends Node

func _ready():
	if OS.has_feature("HTML5"):
		return
	set_script(load("res://addons/discord_game_sdk/discord.gd"))
	call_deferred("_ready")
