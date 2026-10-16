extends CanvasLayer

onready var play_button: Button = $Panel/Row/PlayButton
onready var scrub_slider: HSlider = $Panel/Row/ScrubSlider
onready var speed_slider: HSlider = $Panel/Row/SpeedBox/SpeedSlider
onready var speed_label: Label = $Panel/Row/SpeedBox/SpeedLabel
onready var logo_button: TextureButton = $LogoButton

var Spawn: NoteManager
var _dragging_scrub: bool = false
var _resume_after_scrub: bool = false
var _syncing_slider: bool = false
var _giveup_hold_t: float = 0.0
var _collapsed: bool = false

var _scrub_bar: Dictionary
var _speed_bar: Dictionary

func setup(spawn: NoteManager):
	Spawn = spawn
	scrub_slider.max_value = max(Rhythia.replay.end_ms, 1)

func _make_circle_texture(diameter: int, color: Color) -> ImageTexture:
	var img := Image.new()
	img.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.lock()
	var r := diameter / 2.0
	var center := Vector2(r, r)
	for y in range(diameter):
		for x in range(diameter):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= r:
				img.set_pixel(x, y, color)
	img.unlock()
	var tex := ImageTexture.new()
	tex.create_from_image(img, 0)
	return tex

func _make_blank_texture() -> ImageTexture:
	var img := Image.new()
	img.create(1, 1, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.new()
	tex.create_from_image(img, 0)
	return tex

func _make_bar_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	return sb

func _wrap_slider_with_bar(slider: HSlider, track_color: Color, fill_color: Color, handle_tex: Texture, blank_tex: Texture) -> Dictionary:
	var parent := slider.get_parent()
	var idx := slider.get_index()
	parent.remove_child(slider)

	var wrapper := Control.new()
	wrapper.size_flags_horizontal = slider.size_flags_horizontal
	wrapper.size_flags_vertical = slider.size_flags_vertical
	wrapper.rect_min_size = slider.rect_min_size
	parent.add_child(wrapper)
	parent.move_child(wrapper, idx)

	var track := Panel.new()
	track.anchor_right = 1.0
	track.anchor_top = 0.5
	track.anchor_bottom = 0.5
	track.margin_top = -5
	track.margin_bottom = 5
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_stylebox_override("panel", _make_bar_style(track_color))
	wrapper.add_child(track)

	var fill := Panel.new()
	fill.anchor_top = 0.5
	fill.anchor_bottom = 0.5
	fill.margin_top = -5
	fill.margin_bottom = 5
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.add_stylebox_override("panel", _make_bar_style(fill_color))
	wrapper.add_child(fill)

	wrapper.add_child(slider)
	slider.anchor_right = 1.0
	slider.anchor_bottom = 1.0
	slider.margin_left = 0
	slider.margin_top = 0
	slider.margin_right = 0
	slider.margin_bottom = 0
	for icon_name in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_icon_override(icon_name, blank_tex)

	var handle := TextureRect.new()
	handle.texture = handle_tex
	handle.rect_size = handle_tex.get_size()
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(handle)

	return {"track": track, "fill": fill, "handle": handle}

func _update_progress_bar(slider: HSlider, bar: Dictionary):
	var track: Panel = bar.track
	var fill: Panel = bar.fill
	var handle: TextureRect = bar.handle
	var ratio := 0.0
	if slider.max_value > slider.min_value:
		ratio = (slider.value - slider.min_value) / (slider.max_value - slider.min_value)
	ratio = clamp(ratio, 0.0, 1.0)
	fill.rect_position = track.rect_position
	fill.rect_size = Vector2(track.rect_size.x * ratio, track.rect_size.y)
	var track_center_y = track.rect_position.y + track.rect_size.y / 2.0
	handle.rect_position = Vector2(
		track.rect_position.x + track.rect_size.x * ratio - handle.rect_size.x / 2.0,
		track_center_y - handle.rect_size.y / 2.0
	)

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	$Panel.pause_mode = PAUSE_MODE_PROCESS
	logo_button.pause_mode = PAUSE_MODE_PROCESS

	var grabber_tex = _make_circle_texture(16, Color(1, 1, 1, 1))
	var blank_tex = _make_blank_texture()

	var track_color := Color(0.560784, 0.592157, 0.639216, 1)
	var fill_color := Color(0.286275, 0.482353, 0.980392, 1)
	_scrub_bar = _wrap_slider_with_bar(scrub_slider, track_color, fill_color, grabber_tex, blank_tex)
	_speed_bar = _wrap_slider_with_bar(speed_slider, track_color, fill_color, grabber_tex, blank_tex)

	play_button.connect("pressed", self, "_on_play_pressed")
	scrub_slider.connect("drag_started", self, "_on_scrub_drag_started")
	scrub_slider.connect("drag_ended", self, "_on_scrub_drag_ended")
	scrub_slider.connect("value_changed", self, "_on_scrub_value_changed")
	speed_slider.connect("value_changed", self, "_on_speed_value_changed")
	speed_label.text = "%.2fx" % speed_slider.value
	logo_button.connect("pressed", self, "_set_collapsed", [false])

func _set_collapsed(value: bool):
	_collapsed = value
	$Panel.visible = not _collapsed
	logo_button.visible = _collapsed

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_F1:
		_set_collapsed(not _collapsed)
		get_tree().set_input_as_handled()

func _on_play_pressed():
	Spawn.set_viewer_paused(not Spawn.viewer_paused)
	play_button.text = "Play" if Spawn.viewer_paused else "Pause"

func _on_scrub_drag_started():
	_dragging_scrub = true
	_resume_after_scrub = not Spawn.viewer_paused

func _on_scrub_drag_ended(_value_changed: bool):
	_dragging_scrub = false
	if _resume_after_scrub:
		Spawn.set_viewer_paused(false)
	play_button.text = "Play" if Spawn.viewer_paused else "Pause"

func _on_scrub_value_changed(value: float):
	if _syncing_slider: return
	Spawn.set_viewer_paused(true)
	play_button.text = "Play"
	Spawn.seek_to_rms(value)

func _on_speed_value_changed(value: float):
	Spawn.set_replay_view_speed(value)
	speed_label.text = "%.2fx" % value

func _process(delta):
	_update_progress_bar(scrub_slider, _scrub_bar)
	_update_progress_bar(speed_slider, _speed_bar)
	if Spawn == null: return
	if not _dragging_scrub:
		_syncing_slider = true
		scrub_slider.value = Spawn.rms
		_syncing_slider = false
	play_button.text = "Play" if Spawn.viewer_paused else "Pause"

	if get_tree().paused:
		if Input.is_action_pressed("give_up"):
			_giveup_hold_t += delta / 0.6
			if _giveup_hold_t >= 1.0:
				Spawn.get_parent().end(Globals.END_GIVEUP)
		else:
			_giveup_hold_t = 0.0
