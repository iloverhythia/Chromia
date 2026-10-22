extends Reference

# Sound Space Mode's menu sounds, taken from a recording of Sound Space:
# tick (an item showing up / hovering), select (picking something) and
# swoosh (turning to another screen or page).

const SOUNDS := {
	"tick": "res://assets/soundspace/ui_tick.wav",
	"select": "res://assets/soundspace/ui_select.wav",
	"swoosh": "res://assets/soundspace/ui_swoosh.wav",
}
const VOLUME := {"tick": -14.0, "select": -9.0, "swoosh": -11.0}

static func play(from: Node, name: String, pitch: float = 1.0):
	if from == null or not from.is_inside_tree() or not SOUNDS.has(name):
		return
	var root: Node = from.get_tree().root
	var p = root.get_node_or_null("SSSfx_" + name)
	if p == null:
		p = AudioStreamPlayer.new()
		p.name = "SSSfx_" + name
		p.stream = load(SOUNDS[name])
		p.volume_db = VOLUME[name]
		p.pause_mode = Node.PAUSE_MODE_PROCESS
		root.add_child(p)
	p.pitch_scale = pitch
	p.play()
