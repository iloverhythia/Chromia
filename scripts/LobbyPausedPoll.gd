extends Node
# LobbyManager's connection, polled while the game is paused (LobbyManager
# itself stops then): pings answered and messages in, so nothing drops

func _process(_delta):
	if get_tree().paused:
		get_parent().poll_while_paused()
