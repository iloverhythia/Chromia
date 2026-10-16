tool
extends EditorPlugin

func _enter_tree():
	add_autoload_singleton("Discord", "res://scripts/discord/DiscordBridge.gd")

func disable_plugin():
	remove_autoload_singleton("Discord")
