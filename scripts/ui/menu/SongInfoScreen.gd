extends Control

func comma_sep(number):
	var string = str(number)
	var mod = string.length() % 3
	var res = ""

	for i in range(0, string.length()):
		if i != 0 and i % 3 == mod:
			res += ","
		res += string[i]

	return res

func get_time_ms(ms: float):
	var s = max(floor(ms / 1000), 0)
	var m = floor(s / 60)
	var rs = fmod(s, 60)
	return "%d:%02d" % [m, rs]

onready var difficulty_btns: Array = [
	$RS/H1/ButtonDisp/NODIF,
	$RS/H1/ButtonDisp/EASY,
	$RS/H1/ButtonDisp/MEDIUM,
	$RS/H1/ButtonDisp/HARD,
	$RS/H1/ButtonDisp/LOGIC,
	$RS/H1/ButtonDisp/TASUKETE
]

var _rank_song_id: String = ""
var _rank_is_ranked: bool = false
var _rank_base_xp: int = 0

var _my_stats_song_id: String = ""
var _my_stats_has_passed: bool = false
var _my_stats_best_xp: int = 0
var _my_stats_best_sp: int = 0

func _rebuild_data_label(map: Song):
	$RS/H1/Info/Data/Data.text = "%s - %s notes" % [get_time_ms(map.last_ms), comma_sep(map.note_count)]
	if _rank_is_ranked and _rank_song_id == map.id:
		var effective = int(round(_rank_base_xp * Rhythia.current_xp_speed_multiplier()))
		var txt = "XP: %d" % effective
		if _my_stats_song_id == map.id and _my_stats_has_passed:
			txt += "\nPB: %d XP / %d SP" % [_my_stats_best_xp, _my_stats_best_sp]
		$RS/H1/Info/XP.text = txt
		$RS/H1/Info/XP.visible = true
	else:
		$RS/H1/Info/XP.visible = false

func _on_map_rank_info_received(song_id: String, ranked: bool, xp: int, _content_hash: String):
	_rank_song_id = song_id
	_rank_is_ranked = ranked
	_rank_base_xp = xp
	if Rhythia.selected_song != null and Rhythia.selected_song.id == song_id:
		_rebuild_data_label(Rhythia.selected_song)

func _on_my_map_stats_received(song_id: String, has_passed: bool, best_xp: int, best_sp: int):
	_my_stats_song_id = song_id
	_my_stats_has_passed = has_passed
	_my_stats_best_xp = best_xp
	_my_stats_best_sp = best_sp
	if Rhythia.selected_song != null and Rhythia.selected_song.id == song_id:
		_rebuild_data_label(Rhythia.selected_song)

func update(_s = null):
	if not Rhythia.selected_song: return
	$RS.visible = true
	var map: Song = Rhythia.selected_song

	$RS.visible = (map.id != "!DELETED")
	$RS/H2/EndInfo.visible = true
	$RS/H1/Info/Control/Actions.visible = true

	$RS/H1/Info/Id/Id.text = map.id
	$RS/H1/Info/Name/Name.text = map.name
	$RS/H1/Info/SongName/SongName.text = map.song

	$RS/H1/Info/Mapper/Mapper.text = map.creator
	$RS/HMid/Difficulty.text = map.custom_data.get("difficulty_name",
		Globals.difficulty_names.get(map.difficulty, "INVALID DIFFICULTY ID")
	)
	$RS/HMid/Difficulty.modulate = Globals.difficulty_colors.get(map.difficulty, Color("#ffffff"))
	if map.id != _rank_song_id:
		_rank_is_ranked = false
		var lobby_manager = get_node_or_null("/root/LobbyManager")
		if lobby_manager != null:
			lobby_manager.get_map_rank(map.id)
	if map.id != _my_stats_song_id:
		_my_stats_has_passed = false
		var lobby_manager2 = get_node_or_null("/root/LobbyManager")
		if lobby_manager2 != null:
			lobby_manager2.get_my_map_stats(map.id)
	_rebuild_data_label(map)

	$RS/HMid/Difficulty.visible = true

	$RS/H1/Info/Mapper.visible = not Rhythia.single_map_mode_txt
	$RS/H1/Info/Id.visible = not Rhythia.single_map_mode_txt
	$RS/H1/Info/SMM.visible = Rhythia.single_map_mode



	var txt = ""
	if Rhythia.note_hitbox_size == 1.14: txt += tr("Default hitboxes, ")
	else: txt += tr("Hitboxes: %s, ") % Rhythia.note_hitbox_size
	if Rhythia.hitwindow_ms == 55: txt += tr("default hitwindow")
	elif Rhythia.hitwindow_ms == 300: txt += "Brrecken Judgement"
	else: txt += tr("hitwindow: %s ms") % Rhythia.hitwindow_ms
	$RS/HMid/Hitboxes.text = txt

	if map.creator == "DyamoDash":
		$RS/H1/Info/Mapper/Mapper.text = map.creator + " ♡"


	for i in range(difficulty_btns.size()):
		var n: Panel = difficulty_btns[i]
		n.visible = (map.difficulty == i - 1)
		n.get_node("F").visible = Rhythia.is_favorite(map.id)
		if map.has_cover:
			n.get_node("Name").visible = false
			n.get_node("Cover").visible = true
			n.get_node("Cover").texture = map.cover
		else:
			n.get_node("Cover").visible = false
			n.get_node("Name").visible = true
			n.get_node("Name").text = map.name

	if map.warning != "":
		$RS/H1/Info/Warning.visible = true
		$RS/H1/Info/Warning.text = map.warning
		if map.is_broken:
			$RS/H1/Info/Warning.set("custom_colors/font_color", Color(1, 0, 0))
		else:
			$RS/H1/Info/Warning/Warning.set("custom_colors/font_color", Color(1, 1, 0))
	else: $RS/H1/Info/Warning.visible = false
	$RS/H1/Info/Run.disabled = false
	$RS/H1/Info/Control/Actions.disabled = false
	$RS/H1/Info/Control/PreviewMusic.disabled = false

	$Actions/Convert.disabled = (
		$Actions/Convert.debounce or
		Rhythia.selected_song.is_broken or
		Rhythia.selected_song.is_builtin or
		Rhythia.selected_song.converted or
		Rhythia.selected_song.songType == Globals.MAP_SSPM2 or
		Rhythia.selected_song.is_online
	)

	$Actions/Convert.visible = (
		not Rhythia.selected_song.is_builtin and
		not Rhythia.selected_song.is_online and
		Rhythia.selected_song.songType != Globals.MAP_SSPM2
	)

	$Actions/Difficulty.visible = (
		not Rhythia.selected_song.is_builtin and
		not Rhythia.selected_song.is_online and (
			Rhythia.selected_song.songType == Globals.MAP_SSPM or
			Rhythia.selected_song.songType == Globals.MAP_SSPM2
		)
	)

	if Rhythia.selected_song.songType == Globals.MAP_SSPM:
		$Actions/Convert.text = "Upgrade map to SSPM v2"
	else:
		$Actions/Convert.text = "Convert map to .sspm"


	if is_inside_tree():
		yield(get_tree(), "idle_frame")
		yield(get_tree(), "idle_frame")

func return_to_song_select():
	get_viewport().get_node("Menu/Sidebar").press(0, false)

func _ready():
	Rhythia.connect("selected_song_changed", self, "update")
	Rhythia.connect("mods_changed", self, "update")
	Rhythia.connect("favorite_songs_changed", self, "update")
	var lobby_manager = get_node_or_null("/root/LobbyManager")
	if lobby_manager != null:
		lobby_manager.connect("map_rank_info_received", self, "_on_map_rank_info_received")
		lobby_manager.connect("my_map_stats_received", self, "_on_my_map_stats_received")

	if Rhythia.selected_song: update()
	else:
		$RS.visible = false
		$RS/H2/EndInfo.visible = false
		$RS/H1/Info/Run.disabled = true
		$RS/H1/Info/Control/Actions.disabled = true
		$RS/H1/Info/Control/PreviewMusic.disabled = true
