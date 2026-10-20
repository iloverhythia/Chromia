extends Spatial
# Stand-in "Game" node for background worlds in the map editor's game view:
# worlds connect to Game's "hit" signal to flash on note hits.

signal hit(col)

func emit_hit(col: Color):
	emit_signal("hit", col)
