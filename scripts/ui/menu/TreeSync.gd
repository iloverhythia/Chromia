extends Node

# The Chromia Upgrade Tree on all your devices (signed in to the same
# account): the server keeps the tree that has got furthest (savia_web
# src/treesync.js). Opening the tree asks how far the kept one is; if it's
# ahead of this device's, it comes down and replaces this one (yours is kept
# as furry_tree.before_sync.json). Closing the tree sends this device's when
# it's ahead. How far: [highest layer reached, its best points, all chrome
# coins ever, features found], compared in that order
# (ChromiaUpgradeTree.progress_score).

const URL := "https://savia.nysr.host/savia-tree"
const BACKUP := "user://furry_tree.before_sync.json"

var server_score = null # the kept tree's, once asked (null: not known)
var _tree: WeakRef = null
var _thread: Thread = null

static func get_sync() -> Node:
	var n = Rhythia.get_node_or_null("TreeSync")
	if n == null:
		n = load("res://scripts/ui/menu/TreeSync.gd").new()
		n.name = "TreeSync"
		Rhythia.add_child(n)
	return n

static func ahead(a, b) -> bool:
	if not (a is Array) or a.size() < 4:
		return false
	if not (b is Array) or b.size() < 4:
		return true
	for i in 4:
		var eps := 1e-6 if i == 1 or i == 2 else 0.0
		if float(a[i]) > float(b[i]) + eps:
			return true
		if float(a[i]) < float(b[i]) - eps:
			return false
	return false

func _cid() -> String:
	return String(Rhythia.cid) if Rhythia.get("cid") != null else ""

func _online() -> bool:
	return _cid() != "" and ProjectSettings.get_setting("application/networking/enabled") and not OS.has_feature("JavaScript")

# --- opening: take the kept tree if it's further along -------------------------
func check(tree: Node):
	if not _online():
		return
	_tree = weakref(tree)
	var r := HTTPRequest.new()
	r.timeout = 15
	add_child(r)
	r.connect("request_completed", self, "_on_score", [r, _cid()])
	if r.request("%s/score?client_id=%s" % [URL, _cid().http_escape()]) != OK:
		r.queue_free()

func _on_score(result, code, _h, body: PoolByteArray, r: HTTPRequest, cid: String):
	r.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or cid != _cid():
		return
	var p := JSON.parse(body.get_string_from_utf8())
	if p.error != OK or not (p.result is Dictionary):
		return
	server_score = p.result.get("score")
	var tree = _tree.get_ref() if _tree != null else null
	if tree == null or not is_instance_valid(tree) or not tree.has_method("progress_score"):
		return
	if not ahead(server_score, tree.progress_score()):
		return
	var g := HTTPRequest.new()
	g.timeout = 120
	g.use_threads = OS.can_use_threads()
	add_child(g)
	g.connect("request_completed", self, "_on_tree", [g, cid])
	if g.request("%s?client_id=%s" % [URL, cid.http_escape()]) != OK:
		g.queue_free()

func _on_tree(result, code, _h, body: PoolByteArray, r: HTTPRequest, cid: String):
	r.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.size() < 18 or cid != _cid():
		return
	var raw: PoolByteArray = body.decompress_dynamic(256 * 1024 * 1024, File.COMPRESSION_GZIP)
	var p := JSON.parse(raw.get_string_from_utf8())
	if p.error != OK or not (p.result is Dictionary) or not (p.result.get("nodes") is Array):
		Rhythia.trail("tree sync: the kept tree couldn't be read")
		return
	var tree = _tree.get_ref() if _tree != null else null
	if tree == null or not is_instance_valid(tree):
		return
	var path: String = tree.SAVE_PATH
	var d := Directory.new()
	if d.file_exists(path):
		d.remove(BACKUP)
		d.copy(path, BACKUP)
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		return
	f.store_buffer(raw)
	f.close()
	Rhythia.trail("tree sync: took the tree from another device %s" % str(server_score))
	tree.reload_from_save("Your tree from your other device is further along, so it's here now (this device's is kept as furry_tree.before_sync.json).")

# --- closing: send this device's if it's further along ---------------------------
func upload(score: Array, save_path: String):
	if not _online() or (server_score != null and not ahead(score, server_score)):
		return
	if _thread != null:
		return # (one at a time)
	var f := File.new()
	if f.open(save_path, File.READ) != OK:
		return
	var raw := f.get_buffer(f.get_len())
	f.close()
	# (gzipped on a thread: a big tree takes a moment)
	if OS.can_use_threads():
		_thread = Thread.new()
		if _thread.start(self, "_pack", [raw, score, _cid()]) == OK:
			return
		_thread = null
	_send([raw.compress(File.COMPRESSION_GZIP), score, _cid()])

func _pack(job: Array):
	call_deferred("_packed", [job[0].compress(File.COMPRESSION_GZIP), job[1], job[2]])

func _packed(job: Array):
	if _thread != null and _thread.is_active():
		_thread.wait_to_finish()
	_thread = null
	_send(job)

func _send(job: Array):
	var score: Array = job[1]
	var r := HTTPRequest.new()
	r.timeout = 120
	r.use_threads = OS.can_use_threads()
	add_child(r)
	r.connect("request_completed", self, "_on_sent", [r, score])
	var q := "%s?client_id=%s&score=%s" % [URL, String(job[2]).http_escape(), PoolStringArray([str(int(score[0])), str(float(score[1])), str(float(score[2])), str(int(score[3]))]).join(",")]
	if r.request_raw(q, PoolStringArray(["Content-Type: application/gzip"]), true, HTTPClient.METHOD_POST, job[0]) != OK:
		r.queue_free()

func _on_sent(result, code, _h, body: PoolByteArray, r: HTTPRequest, score: Array):
	r.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var p := JSON.parse(body.get_string_from_utf8())
	if p.error == OK and p.result is Dictionary and p.result.get("score") is Array:
		server_score = p.result.score
		if bool(p.result.get("kept", false)):
			Rhythia.trail("tree sync: sent this tree %s" % str(score))

func _exit_tree():
	if _thread != null and _thread.is_active():
		_thread.wait_to_finish()
