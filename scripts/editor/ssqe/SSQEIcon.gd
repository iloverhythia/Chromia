extends Control
# Small drawn buttons of the map editor: the play / pause button under the
# grid's track (SSQE's GuiButtonPlayPause) and the speaker mute toggles above
# the volume sliders (GuiButtonToggle "MuteUnmute").

const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)

var ed
var kind := "play" # "play" or "mute"
var key := ""      # mute: the setting it toggles
var _hover := false

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	connect("mouse_entered", self, "_set_hover", [true])
	connect("mouse_exited", self, "_set_hover", [false])

func _set_hover(on: bool):
	_hover = on
	update()

func _gui_input(ev):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		if kind == "play":
			ed.toggle_play()
		else:
			ed.s[key] = not ed.s[key]
			ed.settings_changed()
		accept_event()

func _process(_d):
	update()

func _draw():
	var c := ACCENT if _hover else LILAC
	var sz := rect_size
	if kind == "play":
		var m: float = min(sz.x, sz.y) * 0.5
		var ctr := sz / 2
		if ed and ed.playing:
			var w := m * 0.28
			draw_rect(Rect2(ctr.x - m * 0.42, ctr.y - m * 0.5, w, m), c)
			draw_rect(Rect2(ctr.x + m * 0.42 - w, ctr.y - m * 0.5, w, m), c)
		else:
			var pts := PoolVector2Array([ctr + Vector2(-m * 0.38, -m * 0.5), ctr + Vector2(m * 0.5, 0), ctr + Vector2(-m * 0.38, m * 0.5)])
			draw_colored_polygon(pts, c)
		return
	# speaker
	var h := sz.y
	var body := PoolVector2Array([Vector2(h * 0.1, h * 0.35), Vector2(h * 0.3, h * 0.35), Vector2(h * 0.55, h * 0.12),
		Vector2(h * 0.55, h * 0.88), Vector2(h * 0.3, h * 0.65), Vector2(h * 0.1, h * 0.65)])
	draw_colored_polygon(body, c)
	var muted: bool = ed != null and bool(ed.s.get(key, false))
	if muted:
		draw_line(Vector2(h * 0.66, h * 0.3), Vector2(h * 0.96, h * 0.7), c, 1.5, true)
		draw_line(Vector2(h * 0.96, h * 0.3), Vector2(h * 0.66, h * 0.7), c, 1.5, true)
	else:
		draw_arc(Vector2(h * 0.55, h * 0.5), h * 0.22, -0.9, 0.9, 8, c, 1.5, true)
		draw_arc(Vector2(h * 0.55, h * 0.5), h * 0.38, -0.9, 0.9, 10, c, 1.5, true)
