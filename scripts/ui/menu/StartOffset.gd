extends HSlider

var _push_timer: float = 0.0

func _get_lobby_manager():
	return get_node_or_null("/root/LobbyManager")

func get_seconds_from_ms(ms: float):
	return max(floor(ms / 1000), 0)

func value_changed(value):
	Rhythia.start_offset = value * 1000
	call_deferred("upd_label")
	_push_timer = 0.15

var _last_song_id: String = ""

func on_map_selected(_map):
	if Rhythia.selected_song == null:
		return
	var song_id = String(Rhythia.selected_song.id)
	if song_id == _last_song_id:
		return
	_last_song_id = song_id
	self.max_value = get_seconds_from_ms(Rhythia.selected_song.last_ms)
	self.value = 0

func _ready():
	connect("value_changed", self, "value_changed")
	$TimeTextBox.connect("text_entered", self, "time_text_entered")
	Rhythia.connect("selected_song_changed", self, "on_map_selected")
	if (Rhythia.selected_song != null):
		on_map_selected(null)
		self.value = Rhythia.start_offset / 1000

func time_text_entered(new_text):
	var time = new_text.split(":", false, 1)
	var total_seconds: int
	if time.size() == 2: total_seconds = int(time[0]) * 60 + int(time[1])
	else: total_seconds = int(time[0])
	self.value = total_seconds
	$TimeTextBox.release_focus()

func upd_label():
	var total_seconds = int(self.value)
	var minutes = floor(total_seconds / 60)
	var seconds = total_seconds % 60
	var SongPreview = $"/root/Menu/Main/Maps/Results/Results/RS/H1/Info/Control/PreviewMusic/Song"
	if SongPreview.playing != null and SongPreview.playing:
		SongPreview.seek(total_seconds)
	$TimeTextBox.text = "%d:%02d" % [minutes, seconds]

func _process(delta):
	if _push_timer > 0:
		_push_timer -= delta
		if _push_timer <= 0:
			var lobby_manager = _get_lobby_manager()
			if lobby_manager != null and lobby_manager.lobby_active and lobby_manager.is_host:
				lobby_manager.push_current_mods()
