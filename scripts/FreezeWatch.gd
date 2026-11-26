extends Node

# The freeze recorder.
#
# A crash report is the game's last steps (the trail, Savia.gd). A game that
# FREEZES (the window stops answering until it is closed: report 472, in the
# menu, a second after a map was picked) leaves nothing to go on: whatever it
# is stuck in writes no more lines, so the report ends on the last ordinary
# thing and says nothing of the freeze.
#
# This is a thread of its own that looks, four times a second, at when the
# game's main loop last went round (_process below). When that is AFTER_MS
# ago it writes to the trail, from its own thread:
#  - how long ago, and where (menu / map);
#  - the last step the main thread said it was starting (Rhythia.doing: the
#    few places that read files, wait for another thread or take a lock);
#  - which background jobs were running;
#  - whether the sound system still answers, and whether the graphics thread
#    does. Each is asked on this thread with a line before and a line after:
#    a "asking..." with no answer under it is the one that is stuck (a sound
#    device or a graphics driver that hangs takes the whole game with it).
# And a line when the game moves again, with how long it stood still: a long
# load is told apart from a freeze that way.
#
# It costs a wake-up every 250 ms and one number written per frame.

const AFTER_MS := 4000

var _thread: Thread = null
var _quit := false
var _tick := 0          # when the main loop last went round (ms)
var _held := false      # the app is in the background: standing still is normal
var _main_id := 0
var _mutex := Mutex.new()
var _doing := ""        # the step the main thread is in ("" none)
var _last := ""         # the last step it named
var _doing_at := 0
var _probe: ImageTexture = null # (a 1 x 1 picture: asking its width is a question only the graphics thread answers)

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	_main_id = OS.get_thread_caller_id()
	_tick = OS.get_ticks_msec()
	if OS.has_feature("JavaScript") or not OS.can_use_threads():
		set_process(false)
		return
	var im := Image.new()
	im.create(1, 1, false, Image.FORMAT_RGB8)
	_probe = ImageTexture.new()
	_probe.create_from_image(im, 0)
	_thread = Thread.new()
	if _thread.start(self, "_watch", null, Thread.PRIORITY_LOW) != OK:
		_thread = null
		set_process(false)

func _process(_d):
	_tick = OS.get_ticks_msec()

# the main thread: "this is what I'm starting" ("" = done). Other threads' calls are left out.
func doing(what: String):
	if _thread == null or OS.get_thread_caller_id() != _main_id:
		return
	_mutex.lock()
	_doing = what
	if what != "":
		_last = what
	_doing_at = OS.get_ticks_msec()
	_mutex.unlock()

# the app went to the background / came back (phones, headsets: nothing runs there)
func hold(on: bool):
	_held = on
	_tick = OS.get_ticks_msec()

func stop():
	_quit = true
	if _thread == null:
		return
	# (a watcher stuck asking a hung sound or graphics system is left behind)
	var deadline := OS.get_ticks_msec() + 800
	while _thread.is_alive() and OS.get_ticks_msec() < deadline:
		OS.delay_msec(10)
	if not _thread.is_alive():
		_thread.wait_to_finish()
	_thread = null

func _exit_tree():
	stop()

func _watch(_u):
	var last_wake := OS.get_ticks_msec()
	var since := 0 # the tick it stopped at (0: it's running)
	var skip_until := 0
	var next_note := 0
	while not _quit:
		OS.delay_msec(250)
		var now := OS.get_ticks_msec()
		# (this thread stood still as well: the whole game was put to sleep,
		# a laptop's lid or a headset taken off)
		if now - last_wake > 1500:
			skip_until = now + AFTER_MS
		last_wake = now
		var tick := _tick
		if _held or _quit or now < skip_until:
			since = 0
			continue
		if since == 0:
			if now - tick >= AFTER_MS:
				since = tick
				next_note = AFTER_MS * 4
				_report(now - tick)
		elif tick != since:
			Rhythia.trail("moving again: it stood still for %.1f s" % ((tick - since) / 1000.0))
			since = 0
		elif now - since >= next_note:
			Rhythia.trail("still not responding after %d s" % ((now - since) / 1000))
			next_note *= 4

func _report(ms: int):
	_mutex.lock()
	var d := _doing
	var l := _last
	var at := _doing_at
	_mutex.unlock()
	var step := "no step named"
	var ago: float = max(0.0, (OS.get_ticks_msec() - ms - at) / 1000.0)
	if d != "":
		step = "in the middle of: %s (started %.1f s before it stopped)" % [d, ago]
	elif l != "":
		step = "last step, finished %.1f s before it stopped: %s" % [ago, l]
	Rhythia.trail("NOT RESPONDING for %.1f s, %s; %s; background jobs: %s" % [ms / 1000.0, Rhythia._alive_what(), step, Rhythia.background_jobs()])
	Rhythia.trail("freeze check: asking the sound system...")
	AudioServer.lock()
	AudioServer.unlock()
	Rhythia.trail("freeze check: the sound system answers")
	# (only where graphics run on a thread of their own, computers: elsewhere
	# they answer on the main thread, the one that is stuck)
	if int(ProjectSettings.get_setting("rendering/threads/thread_model")) == 2:
		Rhythia.trail("freeze check: asking the graphics thread...")
		VisualServer.texture_get_width(_probe.get_rid())
		Rhythia.trail("freeze check: the graphics thread answers (the game's own code is what's stuck)")
