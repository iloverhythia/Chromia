extends Node

# A song the engine can't decode (.m4a, FLAC, AAC, Opus: AudioConvert.gd) is
# converted once by the Chromia server, which takes a while (the song goes up,
# an Ogg comes back). That used to start when Play was pressed, so the first
# play of such a map sat on the loading screen for all of it.
#
# Now it starts when the map is selected in the menu: by the time Play is
# pressed it is usually done, and if not, the loading screen waits for the
# conversion that is already running instead of starting one.
#
# The song's bytes are read and looked at on a thread (a map's song is several
# MB: not on the menu's own time), one map at a time; a map selected meanwhile
# is looked at next.

var _thread: Thread = null
var _next = null # the song to look at after the one being read

static func selected(song):
	if song == null or OS.has_feature("JavaScript") or not OS.can_use_threads():
		return
	if bool(song.get("is_online")) or bool(song.get("is_builtin")):
		return
	var root: Node = Engine.get_main_loop().root
	var n = root.get_node_or_null("AudioPrefetch")
	if n == null:
		n = load("res://scripts/content/AudioPrefetch.gd").new()
		n.name = "AudioPrefetch"
		root.add_child(n)
	n._look(song)

func _look(song):
	if _thread != null:
		_next = song
		return
	_thread = Thread.new()
	if _thread.start(self, "_read", song) != OK:
		_thread = null

func _read(song):
	var buf = song.get_music_buffer()
	var AC = load("res://scripts/content/AudioConvert.gd")
	var need: bool = buf is PoolByteArray and buf.size() <= AC.MAX_BYTES and AC.needed(buf)
	call_deferred("_read_done", song, buf if need else null)

func _read_done(song, buf):
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if buf != null and Rhythia.selected_song == song:
		Rhythia.trail("song of %s is being converted ahead of playing it" % String(song.id))
		load("res://scripts/content/AudioConvert.gd").start(buf)
	if _next != null:
		var s = _next
		_next = null
		if s != song:
			_look(s)

func _exit_tree():
	if _thread != null and _thread.is_active():
		_thread.wait_to_finish()
	_thread = null
