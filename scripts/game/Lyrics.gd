extends Label3D

# A map's lyrics in a song (Chromia maps, .chrm: ChromiaMap.gd), shown as in
# Novastra: one line of white text inside the grid near its bottom edge, in
# the grid's own space (it turns and moves with the grid, in VR too). The line
# is built from the lyrics up to the song's time by Nova's rules
# (ChromiaMap.lyric_at): words add on, "-" in front starts a new line, "-" at
# the end joins the next one as a syllable, Fade In / Fade Out over a second.

const CM = preload("res://scripts/content/ChromiaMap.gd")
const FONT_PATH := "res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"
const GRID := 3.04 # (the grid's width, song.tscn's Outer)

var lyrics := []
var spawn: Spatial = null
var _shown := ""
var _alpha := -1.0

# added by the note spawner when the song's map has lyrics
static func attach(spawn_node: Spatial):
	var song = Rhythia.selected_song
	if song == null or spawn_node == null:
		return
	var list: Array = CM.lyrics_of(CM.read_song(song))
	if list.empty():
		return
	var l = load("res://scripts/game/Lyrics.gd").new()
	l.name = "Lyrics"
	l.lyrics = list
	l.spawn = spawn_node
	spawn_node.add_child(l)

func _ready():
	var f := DynamicFont.new()
	f.font_data = load(FONT_PATH)
	f.size = 48
	f.use_filter = true
	f.outline_size = 3
	f.outline_color = Color(0, 0, 0)
	font = f
	pixel_size = 0.0028
	# (the middle of the grid is (1, -1) in the spawner's space; near its bottom edge)
	translation = Vector3(1.0, -1.0 - GRID * 0.37, 0.02)
	horizontal_alignment = ALIGN_CENTER
	vertical_alignment = VALIGN_CENTER
	autowrap = true
	width = GRID * 0.92 / pixel_size
	outline_modulate = Color(0, 0, 0, 0.55)
	modulate = Color(1, 1, 1, 0)
	text = ""
	# every letter the lyrics use is made now, while the song loads, not the
	# first time it shows (a new letter is a small stall)
	var chars := {}
	for l in lyrics:
		for c in String(l[1]):
			chars[c] = true
	if not chars.empty():
		f.get_string_size(PoolStringArray(chars.keys()).join(""))

func _process(_delta):
	if spawn == null or not is_instance_valid(spawn):
		return
	var ms: float = float(spawn.get("ms"))
	var r: Array = CM.lyric_at(lyrics, ms)
	var t: String = r[0]
	var a: float = r[1] if t.strip_edges() != "" else 0.0
	if t != _shown:
		_shown = t
		text = t
	if abs(a - _alpha) > 0.004:
		_alpha = a
		modulate = Color(1, 1, 1, a)
		outline_modulate = Color(0, 0, 0, 0.55 * a)
