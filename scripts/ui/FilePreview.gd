extends PanelContainer
# Preview pane for the in-game file browser (FileSelector): click a file to see
# it. Images (incl. GIFs) are shown, WebM / Ogg videos play muted, audio files
# get a play button; anything else shows its name and size.
# FilePreview.attach(dialog) puts the pane to the right of the dialog's file list.

const LILAC = Color(0.764706, 0.65098, 0.8)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)
const IMAGE_EXT = ["png", "jpg", "jpeg", "webp", "bmp", "tga", "gif"]
const VIDEO_EXT = ["webm", "ogv"]
const AUDIO_EXT = ["mp3", "ogg", "wav"]
const MAX_PREVIEW_BYTES = 60 * 1024 * 1024 # don't stall on huge files

var dialog: FileDialog
var tree: Tree
var pic: TextureRect
var video: VideoPlayer
var name_label: Label
var info_label: Label
var play_btn: Button
var player: AudioStreamPlayer
var _path := ""

static func attach(dlg: FileDialog):
	if dlg == null or dlg.has_meta("file_preview"):
		return
	var t = _find_tree(dlg.get_vbox())
	if t == null:
		return
	var parent: Control = t.get_parent()
	var idx: int = t.get_index()
	var row = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_constant_override("separation", 8)
	parent.add_child(row)
	parent.move_child(row, idx)
	parent.remove_child(t)
	row.add_child(t)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pane = load("res://scripts/ui/FilePreview.gd").new()
	row.add_child(pane)
	pane.setup(dlg, t)
	dlg.set_meta("file_preview", pane)

static func _find_tree(n: Node):
	for c in n.get_children():
		if c is Tree:
			return c
		var r = _find_tree(c)
		if r != null:
			return r
	return null

func setup(dlg: FileDialog, t: Tree):
	dialog = dlg
	tree = t
	rect_min_size = Vector2(300, 0)
	size_flags_vertical = SIZE_EXPAND_FILL
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.065, 0.09, 0.9)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_stylebox_override("panel", sb)

	var v = VBoxContainer.new()
	v.add_constant_override("separation", 8)
	add_child(v)
	var box = Control.new() # the picture / video area
	box.rect_min_size = Vector2(280, 220)
	box.size_flags_vertical = SIZE_EXPAND_FILL
	box.rect_clip_content = true
	v.add_child(box)
	pic = TextureRect.new()
	pic.anchor_right = 1
	pic.anchor_bottom = 1
	pic.expand = true
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(pic)
	video = VideoPlayer.new()
	video.anchor_right = 1
	video.anchor_bottom = 1
	video.expand = true
	video.volume_db = -80
	video.visible = false
	video.connect("finished", self, "_on_video_finished")
	box.add_child(video)

	name_label = Label.new()
	name_label.autowrap = true
	name_label.add_color_override("font_color", TEXT)
	v.add_child(name_label)
	info_label = Label.new()
	info_label.autowrap = true
	info_label.add_color_override("font_color", DIM)
	v.add_child(info_label)
	play_btn = Button.new()
	play_btn.text = "▶  Play"
	play_btn.theme = load("res://uitheme.tres")
	play_btn.rect_min_size = Vector2(0, 32)
	play_btn.visible = false
	play_btn.focus_mode = FOCUS_NONE
	play_btn.connect("pressed", self, "_toggle_audio")
	v.add_child(play_btn)
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	player.connect("finished", self, "_on_audio_finished")
	add_child(player)

	tree.connect("item_selected", self, "_on_selected")
	tree.connect("multi_selected", self, "_on_multi_selected")
	dialog.connect("dir_selected", self, "_clear_if_dir")
	dialog.connect("popup_hide", self, "_clear")
	dialog.connect("about_to_show", self, "_clear")
	_clear()

func _on_multi_selected(item: TreeItem, _col: int, selected: bool):
	if selected:
		_show_item(item)

func _on_selected():
	_show_item(tree.get_selected())

func _show_item(item: TreeItem):
	if item == null:
		return
	var path: String = dialog.current_dir.plus_file(item.get_text(0))
	var f = File.new()
	if not f.file_exists(path):
		_clear() # a folder
		return
	if path == _path:
		return
	_show(path)

func _clear_if_dir(_d = ""):
	_clear()

func _clear():
	_path = ""
	_stop_media()
	pic.texture = null
	name_label.text = "Click a file to preview it"
	info_label.text = ""
	play_btn.visible = false

func _stop_media():
	if player.playing:
		player.stop()
	player.stream = null
	if video.is_playing():
		video.stop()
	video.stream = null
	video.visible = false
	play_btn.text = "▶  Play"

static func _fmt_size(n: int) -> String:
	if n >= 1048576:
		return "%.1f MB" % (n / 1048576.0)
	if n >= 1024:
		return "%d KB" % int(n / 1024)
	return "%d bytes" % n

func _show(path: String):
	_clear()
	_path = path
	var ext := path.get_extension().to_lower()
	var size := 0
	var f = File.new()
	if f.open(path, File.READ) == OK:
		size = int(f.get_len())
		f.close()
	name_label.text = path.get_file()
	info_label.text = _fmt_size(size)
	if size > MAX_PREVIEW_BYTES and not ext in AUDIO_EXT:
		info_label.text += " · too big to preview"
		return
	if ext in IMAGE_EXT:
		var tex = Globals.imageLoader.load_file(path)
		if tex is Texture:
			pic.texture = tex
			info_label.text = "%d × %d · %s" % [tex.get_width(), tex.get_height(), _fmt_size(size)]
		else:
			info_label.text += " · can't read this image"
	elif ext in VIDEO_EXT:
		var s: VideoStream = Globals.new_video_stream(path)
		if s != null:
			s.set_file(path)
			video.stream = s
			video.visible = true
			video.play()
			info_label.text += " · video"
		else:
			info_label.text += " · this device can't play .%s videos" % ext
	elif ext in AUDIO_EXT:
		play_btn.visible = true
		info_label.text += " · audio"

func _toggle_audio():
	if player.playing:
		player.stop()
		play_btn.text = "▶  Play"
		return
	if player.stream == null:
		var s = Globals.audioLoader.load_file(_path)
		if not (s is AudioStream):
			info_label.text = "Can't play this file"
			return
		player.stream = s
	player.play()
	play_btn.text = "■  Stop"

func _on_audio_finished():
	play_btn.text = "▶  Play"

func _on_video_finished():
	if video.visible and video.stream != null:
		video.play() # loop
