extends Node
# PerfLog.gd's other end: runs last in every frame (and every physics step),
# so the logger knows how long the game's own scripts and physics took.
var log_node = null

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	process_priority = 100000

func _process(_d):
	log_node._end_us = OS.get_ticks_usec()

func _physics_process(_d):
	log_node._physics_end()
