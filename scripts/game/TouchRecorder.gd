extends Node

# Records the fingers on the screen into the replay being recorded
# (Replay.store_touch), so the touch indicator can show them when the replay
# is watched (scripts/ui/TouchIndicator.gd). Added to the note spawner by
# NoteManager while recording.

const MOVE_EVERY_MS := 8 # at most one move per finger this often (phones send many)

var nm: Node
var _last_move := {} # finger -> rms of its last saved move

static func attach(note_manager: Node):
	if Rhythia.replaying or not Rhythia.record_replays or Rhythia.replay == null:
		return
	var r = load("res://scripts/game/TouchRecorder.gd").new()
	r.name = "TouchRecorder"
	r.nm = note_manager
	r.pause_mode = Node.PAUSE_MODE_PROCESS # fingers lifted while paused still count
	note_manager.add_child(r)

func _input(event):
	if nm == null or not is_instance_valid(nm) or Rhythia.replay == null or not Rhythia.replay.recording:
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var ms: float = nm.rms
	var screen: Vector2 = get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var kind: int = Rhythia.replay.TOUCH_DOWN if event.pressed else Rhythia.replay.TOUCH_UP
		Rhythia.replay.store_touch(ms, kind, event.index, event.position, screen)
		_last_move.erase(event.index)
	else:
		var last = _last_move.get(event.index)
		if last != null and ms - float(last) < MOVE_EVERY_MS:
			return
		_last_move[event.index] = ms
		Rhythia.replay.store_touch(ms, Rhythia.replay.TOUCH_MOVE, event.index, event.position, screen)
