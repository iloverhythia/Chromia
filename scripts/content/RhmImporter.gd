extends Node
class_name RhmImporter

const TMP_ZIP := "user://tmp_rhm_import.zip"
const TMP_DIR := "user://tmp_rhm_import"
const TMP_AUDIO := "user://tmp_rhm_import_audio.mp3"

func _real_path(user_path: String) -> String:
	return user_path.replace("user://", OS.get_user_data_dir() + "/")

func _extract_zip(zip_path: String, dest_dir: String) -> bool:
	var dir := Directory.new()
	dir.make_dir_recursive(dest_dir)
	var output := []
	var exit_code := OS.execute("tar.exe", ["-xf", zip_path, "-C", dest_dir], true, output, true)
	return exit_code == 0

func _remove_dir_recursive(path: String):
	var dir := Directory.new()
	if dir.open(path) != OK:
		return
	dir.list_dir_begin(true, true)
	var f := dir.get_next()
	while f != "":
		var full := path.plus_file(f)
		if dir.current_is_dir():
			_remove_dir_recursive(full)
		else:
			dir.remove(full)
		f = dir.get_next()
	dir.list_dir_end()
	dir.remove(path)

func _cleanup():
	var dir := Directory.new()
	dir.remove(Globals.p(TMP_ZIP))
	dir.remove(Globals.p(TMP_AUDIO))
	_remove_dir_recursive(Globals.p(TMP_DIR))

func _slugify(s: String) -> String:
	var out := ""
	var lower = s.to_lower()
	for i in range(lower.length()):
		var c = lower[i]
		if "0123456789abcdefghijklmnopqrstuvwxyz".find(c) != -1:
			out += c
		elif out != "" and out[out.length() - 1] != "_":
			out += "_"
	return out.trim_suffix("_")

func _is_valid_song_id(txt: String) -> bool:
	return not (
		txt.length() == 0 or
		txt.begins_with("_") or
		not (("n" + txt).replace("-", "")).is_valid_identifier()
	)

func _find_cover_file(root: String) -> String:
	var dir := Directory.new()
	if dir.open(root) != OK:
		return ""
	dir.list_dir_begin(true, true)
	var f := dir.get_next()
	var found := ""
	while f != "":
		if not dir.current_is_dir() and f.get_basename().to_lower() == "cover":
			found = root.plus_file(f)
			break
		f = dir.get_next()
	dir.list_dir_end()
	return found

func import_rhm(path: String) -> Dictionary:

	yield(get_tree(), "idle_frame")

	var result := {"song": null, "error": ""}
	var dir := Directory.new()

	if dir.copy(path, Globals.p(TMP_ZIP)) != OK:
		result.error = "Couldn't read the selected file."
		return result

	if not _extract_zip(_real_path(TMP_ZIP), _real_path(TMP_DIR)):
		result.error = "Couldn't extract the archive — is it really a .rhm (zip) file?"
		_cleanup()
		return result

	var root := Globals.p(TMP_DIR)

	var map_file := File.new()
	if map_file.open(root.plus_file("map"), File.READ) != OK:
		result.error = "No 'map' found inside — is this really a .rhm file?"
		_cleanup()
		return result
	var map_text := map_file.get_as_text()
	map_file.close()

	var parsed = JSON.parse(map_text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		result.error = "'map' inside the archive isn't valid JSON."
		_cleanup()
		return result
	var data: Dictionary = parsed.result

	var rhm_notes = data.get("Notes", [])
	if typeof(rhm_notes) != TYPE_ARRAY or rhm_notes.size() == 0:
		result.error = "That map has no notes."
		_cleanup()
		return result

	var song_name := String(data.get("SongName", data.get("Title", "Unknown")))
	var mappers = data.get("Mappers", [])
	var creator := PoolStringArray(mappers).join(", ") if typeof(mappers) == TYPE_ARRAY and mappers.size() > 0 else "Unknown"

	var legacy_id := _slugify(String(data.get("LegacyId", "")))
	var id: String
	if legacy_id != "" and _is_valid_song_id(legacy_id):
		id = legacy_id
	else:
		var basis = "%s|%s|%d|%s" % [song_name, creator, rhm_notes.size(), String(data.get("Duration", 0))]
		id = "rhm_" + basis.sha256_text().substr(0, 24)

	var notes := []
	for n in rhm_notes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		notes.append([float(n.get("X", 0)), float(n.get("Y", 0)), float(n.get("Time", 0))])
	notes.sort_custom(self, "_sort_by_ms")

	var audio_file := File.new()
	if audio_file.open(root.plus_file("audio"), File.READ) != OK:
		result.error = "'audio' inside the archive couldn't be read."
		_cleanup()
		return result
	var audio_bytes: PoolByteArray = audio_file.get_buffer(audio_file.get_len())
	audio_file.close()
	var audio_out := File.new()
	if audio_out.open(Globals.p(TMP_AUDIO), File.WRITE) != OK:
		result.error = "Couldn't stage the audio for conversion."
		_cleanup()
		return result
	audio_out.store_buffer(audio_bytes)
	audio_out.close()

	var cover_texture: Texture = null
	var cover_path := _find_cover_file(root)
	if cover_path != "":
		var cover_file := File.new()
		if cover_file.open(cover_path, File.READ) == OK:
			var cover_bytes: PoolByteArray = cover_file.get_buffer(cover_file.get_len())
			cover_file.close()
			cover_texture = Globals.imageLoader.load_buffer(cover_bytes)

	var song := Song.new(id, song_name, creator)
	song.songType = Globals.MAP_RAW
	song.musicFile = TMP_AUDIO
	song.notes = notes
	song.note_count = notes.size()
	song.last_ms = notes[notes.size() - 1][2]

	song.difficulty = clamp(int(round(float(data.get("Difficulty", 0)))), 0, 4)
	song.rating = int(round(float(data.get("StarRating", 0))))
	var diff_name = data.get("CustomDifficultyName", "")
	if diff_name != "":
		song.custom_data = {"difficulty_name": diff_name}
	if cover_texture != null:
		song.cover = cover_texture
		song.has_cover = true

	var convert_result = song.convert_to_sspm()
	_cleanup()

	if convert_result != "Converted!" and convert_result != "File already exists!":
		result.error = "Conversion failed: %s" % String(convert_result)
		return result

	Rhythia.registry_song.check_and_remove_id(song.id)
	var registered_song = Rhythia.registry_song.add_sspm_map("user://maps/%s.sspm" % song.id)
	if registered_song == null:
		result.error = "Converted but couldn't be added to your map list."
		return result
	result.song = registered_song
	return result

func _sort_by_ms(a, b):
	return a[2] < b[2]
