extends Node


var thread
var thread_started: bool = false
var mutex
var semaphore
var exit_thread = false

var time_max = 100

var queue = []
var pending = {}

func _lock(_caller):
	mutex.lock()


func _unlock(_caller):
	mutex.unlock()


func _post(_caller):
	semaphore.post()


func _wait(_caller):
	semaphore.wait()


func queue_resource(path, p_in_front = false, quiet = false):
	if Input.is_key_pressed(KEY_CONTROL) and Input.is_key_pressed(KEY_P): return ERR_SKIP
	_lock("queue_resource")
	if path in pending:
		_unlock("queue_resource")
		return OK
	elif ResourceLoader.has_cached(path):
		var res = ResourceLoader.load(path)
		pending[path] = res
		_unlock("queue_resource")
		return OK
	else:
		var res = ResourceLoader.load_interactive(path)
		if not res:
			_unlock("queue_resource") # still locked here: the loader thread would wait on it forever
			return FAILED
		res.set_meta("path", path)
		res.set_meta("quiet", quiet)
		if not quiet:
			Rhythia.trail("loading %s" % path)
		if p_in_front:
			queue.insert(0, res)
		else:
			queue.push_back(res)
		pending[path] = res
		if not _main_thread():
			_post("queue_resource")
		_unlock("queue_resource")
		return OK


# VR (where loading is on the main thread): the scenes inside `path`, and the
# ones inside those, innermost first, each queued by itself ahead of `path`.
# A scene is read one file per step, but a scene inside it counted as a single
# file: the settings page inside the menu was one long step, a freeze in the
# middle of the loading screen. Queued by itself it is read in steps too, and
# the outer scene then finds it already there.
# -> what was queued: give it to forget() once `path` has been taken.
func queue_nested(path: String) -> Array:
	var found := []
	_nested_of(path, {}, found)
	var queued := []
	for p in found:
		if not ResourceLoader.has_cached(p) and queue_resource(p, false, true) == OK:
			queued.append(p)
	return queued

func _nested_of(path: String, seen: Dictionary, out: Array):
	seen[path] = true
	for d in ResourceLoader.get_dependencies(path):
		var dp: String = String(d).split("::")[0]
		if seen.has(dp) or not dp.begins_with("res://"):
			continue
		if dp.get_extension().to_lower() in ["tscn", "scn"]:
			_nested_of(dp, seen, out)
			out.append(dp)

func forget(paths: Array):
	for p in paths:
		cancel_resource(p)

func cancel_resource(path):
	_lock("cancel_resource")
	if path in pending:
		if pending[path] is ResourceInteractiveLoader:
			queue.erase(pending[path])
		pending.erase(path)
	_unlock("cancel_resource")


func get_progress(path):
	_lock("get_progress")
	var ret = -1
	if path in pending:
		if pending[path] is ResourceInteractiveLoader:
			ret = float(pending[path].get_stage()) / float(pending[path].get_stage_count())
		else:
			ret = 1.0
	_unlock("get_progress")
	return ret


func is_ready(path):
	var ret
	_lock("is_ready")
	if path in pending:
		ret = not (pending[path] is ResourceInteractiveLoader)
	else:
		ret = false
	_unlock("is_ready")
	return ret


func _wait_for_resource(res, path):
	_unlock("wait_for_resource")
	while true:
		VisualServer. sync ()
		OS.delay_usec(16000)
		_lock("wait_for_resource")
		if queue.size() == 0 or queue[0] != res:
			return pending[path]
		_unlock("wait_for_resource")


func get_resource(path):
	_lock("get_resource")
	if path in pending:
		if pending[path] is ResourceInteractiveLoader:
			var res = pending[path]
			if res != queue[0]:
				var pos = queue.find(res)
				queue.remove(pos)
				queue.insert(0, res)

			if _main_thread():
				# (nobody else loads it then: finished here, as loading on the
				# main thread did before it was spread over frames)
				_unlock("get_resource_now")
				while pending.get(path) is ResourceInteractiveLoader:
					thread_process(false)
				_lock("get_resource_now")
				res = pending.get(path)
			else:
				res = _wait_for_resource(res, path)
			pending.erase(path)
			_unlock("return")
			return res
		else:
			var res = pending[path]
			pending.erase(path)
			_unlock("return")
			return res
	else:
		_unlock("return")
		return ResourceLoader.load(path)


# budget_usec > 0: stop after that long (the rest goes on next frame)
func thread_process(wait_for_signal: bool = true, budget_usec: int = 0):
	var began := OS.get_ticks_usec()
	if wait_for_signal:
		_wait("thread_process")
		if _main_thread():
			return # (VR started meanwhile: the main thread loads now)

	_lock("process")
	while queue.size() > 0:
		var res = queue[0]
		_unlock("process_poll")
		var ret = OK
		if not Input.is_key_pressed(KEY_P): ret = res.poll()
		_lock("process_check_queue")

		if ret == ERR_FILE_EOF or ret != OK:
			var path = res.get_meta("path")
			if path in pending:
				if ret == ERR_FILE_EOF:
					pending[res.get_meta("path")] = res.get_resource()
					if not res.get_meta("quiet"):
						Rhythia.trail("loaded %s" % path)
				else: pending[res.get_meta("path")] = false


			queue.erase(res)
		if budget_usec > 0 and OS.get_ticks_usec() - began >= budget_usec:
			break
	_unlock("process")


func thread_func(_u):
	while true:
		mutex.lock()
		var should_exit = exit_thread
		mutex.unlock()

		if should_exit:
			break
		thread_process()


func start():
	mutex = Mutex.new()
	semaphore = Semaphore.new()
	thread = Thread.new()
	# the web build has no threads: _process() does the loading then. Phones
	# load on the main thread too: loading scenes on a second thread while the
	# game runs is a known source of random crashes in Godot 3 on mobile.
	var phone := OS.has_feature("mobile") or OS.has_feature("iOS") or OS.has_feature("Android")
	thread_started = not phone and OS.can_use_threads() and thread.start(self, "thread_func", 0) == OK

# In VR everything loads on the main thread, like on phones and the Meta Quest:
# loading scenes on a second thread while the headset is drawing is a known
# source of crashes in Godot 3 (PC VR crashed when a song started).
func _main_thread() -> bool:
	return not thread_started or (Rhythia != null and Rhythia.vr)

# Loading on the main thread used to do the whole queue in one frame: the menu
# and the song scene each froze the picture for as long as they took to read
# (most of a second on a Quest 3, longer on a Quest 2), loading panel and all.
# In a headset a frozen picture is what Meta's store review calls unresponsive
# (VRC.Quest.Performance.3). Now a little is read every frame, so the loading
# screen keeps moving: a headset frame's worth in VR, more on a phone (whose
# loading screen is fine at 30 pictures a second, and it costs less time).
const BUDGET_VR_USEC := 9000
const BUDGET_PHONE_USEC := 24000
func _process(_delta):
	if _main_thread():
		thread_process(false, BUDGET_VR_USEC if (Rhythia != null and Rhythia.vr) else BUDGET_PHONE_USEC)


func _exit_tree():
	if not thread_started or not thread.is_active():
		return
	mutex.lock()
	exit_thread = true
	mutex.unlock()


	semaphore.post()


	thread.wait_to_finish()

func _ready(): start()
