extends Node

func _ready():
	set_script(load("res://addons/discord_game_sdk/discord.gd"))
	call_deferred("_ready")
