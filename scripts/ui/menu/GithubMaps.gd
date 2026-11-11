extends VBoxContainer
# Content Browser > Maps > "Maps from: GitHub". Paste a link to any GitHub
# repository (or to a folder, a file or the releases of one) and every .sspm
# and .rhm map found there is listed, ready to download into the game.
#
# The list comes from GitHub's public API (no account: about 60 lookups an
# hour per connection, a whole repository costs two), the files from
# raw.githubusercontent.com (or the release's own download link). Nothing
# goes through Chromia's server.

const GH_API := "https://api.github.com"
const GH_RAW := "https://raw.githubusercontent.com"
const GH_MEDIA := "https://media.githubusercontent.com/media" # (files kept with Git LFS)
const GH_WEB := "https://github.com"
const SAVE := "user://github_maps.json"
const DOWNLOAD_DIR := "user://content_downloads"
const PER_PAGE := 30
const MAX_RECENT := 6
const MAX_DOWNLOADS := 2
const HELP := "Paste a link to a GitHub repository, or to a folder, a release or a map file in one. Every .sspm and .rhm map found there is listed for you to download. These files come straight from GitHub, not from Chromia: download from people you trust."

var cb # the Content Browser (its fonts and looks)
var addr := {} # what was looked up last (parse_address)
var items := [] # every map found
var shown := [] # the ones the filter lets through
var page := 1

var box: LineEdit
var find_btn: Button
var recent_row: HFlowContainer
var info: Label
var tools: HBoxContainer
var filter: LineEdit
var all_btn: Button
var scroll: ScrollContainer
var grid: GridContainer
var pager: HBoxContainer
var page_label: Label
var prev_btn: Button
var next_btn: Button

var _q := 0 # the lookup going on (older answers are dropped)
var _waiting := 0 # answers still to come for it
var _found := []
var _truncated := false
var _held := {} # a cut-off list, kept while the folder alone is asked for
var _threads := []
var _save := {"recent": [], "got": {}}
var _btns := {} # item key -> its button on this page
var _state := {} # item key -> "wait" | "busy"
var _queue := []
var _active := 0
var _batch := {} # {ok, bad} while Download all runs

# ------------------------------------------------------------------ the link

static func is_map(path: String) -> bool:
	var low := path.to_lower()
	return low.ends_with(".sspm") or low.ends_with(".rhm")

static func _from(a: Array, i: int) -> Array:
	var out := []
	for j in range(i, a.size()):
		out.append(a[j])
	return out

static func _join(a: Array, from := 0, to := -1) -> String:
	var out := PoolStringArray()
	for j in range(from, a.size() if to < 0 else int(min(to, a.size()))):
		out.append(String(a[j]))
	return out.join("/")

static func _plain(s: String) -> bool:
	if s == "" or s == "." or s == "..":
		return false
	for ch in s:
		if not ((ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in ["-", "_", "."]):
			return false
	return true

# What a pasted link points at:
# {owner, repo, mode, rest, tag}, or {error}. mode is "repo" (all of it),
# "tree" (rest = branch then folder, as in the link: which part is the branch
# is found by asking), "file" (rest = branch and path of one map) or
# "releases" (tag = one release, or "" for all).
static func parse_address(text: String) -> Dictionary:
	var s := text.strip_edges()
	if s == "":
		return {"error": "Paste a GitHub link first, like github.com/name/maps."}
	if s.to_lower().begins_with("git@github.com:"):
		s = "github.com/" + s.substr(15)
	for p in ["https://", "http://", "git://", "ssh://git@"]:
		if s.to_lower().begins_with(p):
			s = s.substr(String(p).length())
			break
	if s.to_lower().begins_with("www."):
		s = s.substr(4)
	for cut in ["?", "#"]:
		var at := s.find(cut)
		if at != -1:
			s = s.left(at)
	var parts := []
	for p in s.split("/", false):
		var seg := String(p).percent_decode().strip_edges()
		if seg != "":
			parts.append(seg)
	var raw := false
	var nope := {"error": "That isn't a GitHub link. Paste one like github.com/name/maps."}
	if parts.size() > 0 and String(parts[0]).find(".") != -1:
		var host := String(parts[0]).to_lower()
		parts.remove(0)
		match host:
			"github.com":
				pass
			"raw.githubusercontent.com", "raw.github.com":
				raw = true
			"media.githubusercontent.com":
				raw = true
				if parts.size() > 0 and String(parts[0]) == "media":
					parts.remove(0)
			"api.github.com":
				if parts.size() > 0 and String(parts[0]) == "repos":
					parts.remove(0)
				while parts.size() > 2:
					parts.pop_back()
			"gist.github.com":
				return {"error": "Gists can't be read here. Paste a link to a repository instead."}
			_:
				return nope
	if parts.size() < 2:
		return nope
	var owner := String(parts[0])
	var repo := String(parts[1])
	if repo.to_lower().ends_with(".git"):
		repo = repo.left(repo.length() - 4)
	if not _plain(owner) or not _plain(repo):
		return nope
	var rest := _from(parts, 2)
	var out := {"owner": owner, "repo": repo, "mode": "repo", "rest": [], "tag": ""}
	if raw:
		# raw.githubusercontent.com/name/repo/<branch>/<path>
		if rest.size() >= 3 and String(rest[0]) == "refs" and String(rest[1]) in ["heads", "tags"]:
			rest = _from(rest, 2)
		if rest.size() >= 2 and is_map(String(rest[rest.size() - 1])):
			out.mode = "file"
			out.rest = rest
		elif rest.size() > 0:
			out.mode = "tree"
			out.rest = rest
	elif rest.size() > 0:
		match String(rest[0]):
			"tree":
				if rest.size() > 1:
					out.mode = "tree"
					out.rest = _from(rest, 1)
			"blob", "raw":
				var r2 := _from(rest, 1)
				if r2.size() >= 2 and is_map(String(r2[r2.size() - 1])):
					out.mode = "file"
					out.rest = r2
				elif r2.size() >= 2:
					# (some other file: the folder it is in)
					r2.pop_back()
					out.mode = "tree"
					out.rest = r2
			"releases":
				out.mode = "releases"
				if rest.size() >= 3 and String(rest[1]) == "tag":
					out.tag = _join(rest, 2)
				elif rest.size() >= 4 and String(rest[1]) == "download":
					out.tag = _join(rest, 2, rest.size() - 1)
	return out

# "feature/x/packs" could be branch "feature" and folder "x/packs", or branch
# "feature/x" and folder "packs": each is tried in turn -> [[branch, folder]]
static func _guesses(rest: Array) -> Array:
	var out := []
	for i in range(1, int(min(4, rest.size())) + 1):
		out.append([_join(rest, 0, i), _join(rest, i)])
	return out

# each part of a path made safe for a link (the slashes stay)
static func _enc(path: String) -> String:
	var out := PoolStringArray()
	for seg in path.split("/", false):
		out.append(String(seg).http_escape())
	return out.join("/")

# ------------------------------------------------------------------ building

func setup(browser):
	cb = browser
	add_constant_override("separation", 10)
	_load_save()
	var bar := HBoxContainer.new()
	bar.add_constant_override("separation", 8)
	add_child(bar)
	box = LineEdit.new()
	box.name = "Link"
	box.placeholder_text = "Paste a GitHub link, like github.com/name/maps"
	box.clear_button_enabled = true
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.rect_min_size = Vector2(0, 36)
	box.add_font_override("font", cb.f_reg)
	box.connect("text_entered", self, "_on_find")
	bar.add_child(box)
	var paste: Button = cb._button("Paste", "_on_paste", [], false, self)
	paste.hint_tooltip = "Put the link you copied in the box and look it up"
	bar.add_child(paste)
	find_btn = cb._button("Find maps", "_on_find", [], false, self)
	bar.add_child(find_btn)
	recent_row = HFlowContainer.new() # (wraps: six long links don't fit one line)
	recent_row.add_constant_override("hseparation", 6)
	recent_row.add_constant_override("vseparation", 4)
	add_child(recent_row)
	info = cb._label(HELP, cb.f_small, cb.DIM)
	info.autowrap = true
	add_child(info)
	tools = HBoxContainer.new()
	tools.add_constant_override("separation", 8)
	tools.visible = false
	add_child(tools)
	filter = LineEdit.new()
	filter.placeholder_text = "Filter by name or folder"
	filter.clear_button_enabled = true
	filter.size_flags_horizontal = SIZE_EXPAND_FILL
	filter.rect_min_size = Vector2(0, 36)
	filter.add_font_override("font", cb.f_reg)
	filter.connect("text_changed", self, "_on_filter")
	tools.add_child(filter)
	all_btn = cb._button("Download all", "_on_all", [], false, self)
	tools.add_child(all_btn)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	add_child(scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_constant_override("hseparation", 10)
	grid.add_constant_override("vseparation", 10)
	scroll.add_child(grid)
	pager = HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGN_CENTER
	pager.add_constant_override("separation", 12)
	pager.visible = false
	add_child(pager)
	prev_btn = cb._button("< Previous", "_go_page", [-1], false, self)
	pager.add_child(prev_btn)
	page_label = cb._label("", cb.f_bold, cb.DIM)
	pager.add_child(page_label)
	next_btn = cb._button("Next >", "_go_page", [1], false, self)
	pager.add_child(next_btn)
	connect("resized", self, "_relayout")
	_show_recent()

func _relayout():
	if grid == null:
		return
	var w: float = max(scroll.rect_size.x - 14, cb.CARD_W)
	grid.columns = int(max(1, floor((w + 10) / (cb.CARD_W + 10))))

# (the page came up)
func opened():
	call_deferred("_relayout")

func _exit_tree():
	for th in _threads:
		th.wait_to_finish()
	_threads.clear()

func _say(text: String):
	info.text = text

# ------------------------------------------------------------------ what's kept

func _load_save():
	var f := File.new()
	if f.open(Globals.p(SAVE), File.READ) != OK:
		return
	var p := JSON.parse(f.get_as_text())
	f.close()
	if p.error != OK or not (p.result is Dictionary):
		return
	if p.result.get("recent") is Array:
		for r in p.result.recent:
			if r is String and _save.recent.size() < MAX_RECENT:
				_save.recent.append(r)
	if p.result.get("got") is Dictionary:
		_save.got = p.result.got

func _write_save():
	var f := File.new()
	if f.open(Globals.p(SAVE), File.WRITE) == OK:
		f.store_string(to_json(_save))
		f.close()

# the link as it's kept in Recent ("" for one file)
func _address_text() -> String:
	var base := "%s/%s" % [addr.owner, addr.repo]
	match String(addr.mode):
		"tree":
			return base + "/tree/" + _join(addr.rest)
		"releases":
			return base + "/releases" + (("/tag/" + String(addr.tag)) if String(addr.tag) != "" else "")
		"file":
			return ""
	return base

func _remember():
	var t := _address_text()
	if t == "":
		return
	var list := [t]
	for r in _save.recent:
		if String(r).to_lower() != t.to_lower() and list.size() < MAX_RECENT:
			list.append(r)
	_save.recent = list
	_write_save()
	_show_recent()

func _show_recent():
	for c in recent_row.get_children():
		c.queue_free()
	recent_row.visible = not _save.recent.empty()
	if _save.recent.empty():
		return
	recent_row.add_child(cb._label("Recent", cb.f_small, cb.DIM))
	for r in _save.recent:
		var t := String(r)
		var b: Button = cb._button(t if t.length() <= 30 else t.left(29) + "…", "_on_recent", [t], false, self)
		b.add_font_override("font", cb.f_small)
		b.hint_tooltip = "github.com/" + t
		recent_row.add_child(b)
	var clear: Button = cb._button("Clear", "_on_clear_recent", [], false, self)
	clear.add_font_override("font", cb.f_small)
	clear.add_color_override("font_color", cb.DIM)
	recent_row.add_child(clear)

func _on_recent(t: String):
	box.text = "github.com/" + t
	find(box.text)

func _on_clear_recent():
	_save.recent = []
	_write_save()
	_show_recent()

# ------------------------------------------------------------------ looking up

func _on_paste():
	var t := String(OS.clipboard).strip_edges()
	if t == "":
		_say("There's nothing copied to paste. Copy a GitHub link first.")
		return
	box.text = t.split("\n")[0].left(400)
	find(box.text)

func _on_find(_t := ""):
	find(box.text)

func _repo_name() -> String:
	return "%s/%s" % [addr.owner, addr.repo]

func find(text: String):
	var a := parse_address(text)
	if a.has("error"):
		_say(String(a.error))
		return
	if box.text.strip_edges() != text.strip_edges():
		box.text = text.strip_edges()
	_q += 1
	addr = a
	_found = []
	_truncated = false
	_held = {}
	items = []
	shown = []
	page = 1
	_show_page()
	_say("Looking in %s…" % _repo_name())
	find_btn.disabled = true
	match String(a.mode):
		"file":
			_found.append({"raw": _join(a.rest), "path": _join(a.rest, 1), "size": 0, "sha": ""})
			_waiting = 0
			_finish()
		"releases":
			_waiting = 1
			_ask_releases()
		"tree":
			_waiting = 1
			_ask_tree(_guesses(a.rest), 0, true)
		_:
			_waiting = 2
			_ask_tree([["HEAD", ""]], 0, false)
			_ask_releases()

func _fail(text: String):
	_q += 1 # (anything still on its way is for nothing now)
	find_btn.disabled = false
	_say(text)

func _api(path: String, method: String, extra := []):
	var r := HTTPRequest.new()
	r.timeout = 40
	r.use_threads = OS.can_use_threads()
	add_child(r)
	r.connect("request_completed", self, method, [r, _q] + extra)
	var headers := PoolStringArray(["Accept: application/vnd.github+json", "X-GitHub-Api-Version: 2022-11-28"])
	if OS.get_name() != "HTML5":
		headers.append("User-Agent: Chromia") # (a browser sets its own)
	if r.request(GH_API + path, headers) != OK:
		r.queue_free()
		_fail("Couldn't reach GitHub. Check your connection and try again.")

static func _header(headers: PoolStringArray, name: String) -> String:
	for h in headers:
		var at := String(h).find(":")
		if at > 0 and String(h).left(at).strip_edges().to_lower() == name:
			return String(h).substr(at + 1).strip_edges()
	return ""

# what went wrong with an answer, in plain words ("" = it's a real answer;
# "not there" (404) is left to whoever asked)
func _trouble(result: int, code: int, headers: PoolStringArray) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return "Couldn't reach GitHub. Check your connection and try again."
	if code == 403 or code == 429:
		# without an account GitHub gives every connection a few lookups an hour
		if code == 429 or _header(headers, "x-ratelimit-remaining") == "0" or _header(headers, "retry-after") != "":
			var wait := int(_header(headers, "x-ratelimit-reset")) - OS.get_unix_time()
			if wait <= 0:
				wait = int(_header(headers, "retry-after"))
			if wait > 0:
				var mins := int(ceil(wait / 60.0))
				return "GitHub only allows a few lookups an hour, and they're used up. Try again in %d minute%s." % [mins, "" if mins == 1 else "s"]
			return "GitHub only allows a few lookups an hour, and they're used up. Try again a bit later."
		return "GitHub wouldn't show that repository (it may be private or blocked)."
	if code == 451:
		return "GitHub has taken that repository down."
	if code >= 500:
		return "GitHub is having trouble right now. Try again in a moment."
	return ""

func _ask_tree(cands: Array, i: int, asked_repo: bool):
	_api("/repos/%s/%s/git/trees/%s?recursive=1" % [addr.owner, addr.repo, _enc(String(cands[i][0]))], "_on_tree", [cands, i, asked_repo])

func _on_tree(result: int, code: int, headers: PoolStringArray, body: PoolByteArray, r: HTTPRequest, q: int, cands: Array, i: int, asked_repo: bool):
	r.queue_free()
	if q != _q:
		return
	var bad := _trouble(result, code, headers)
	if bad != "":
		_fail(bad)
		return
	if code == 404 or code == 422:
		if i + 1 < cands.size():
			_ask_tree(cands, i + 1, asked_repo)
		elif not asked_repo:
			# (no such repository, or its main branch has to be asked for by name)
			_api("/repos/%s/%s" % [addr.owner, addr.repo], "_on_repo")
		elif String(addr.mode) == "tree":
			_fail("Couldn't find that branch or folder on GitHub. Check the link (private repositories can't be read).")
		else:
			_fail("Couldn't read %s on GitHub." % _repo_name())
		return
	if code == 409: # (a repository with nothing in it yet)
		_part_done()
		return
	if code != 200:
		_fail("GitHub answered with an error (%d). Try again in a moment." % code)
		return
	_parse(body, "tree", {"ref": String(cands[i][0]), "path": String(cands[i][1])})

func _on_repo(result: int, code: int, headers: PoolStringArray, body: PoolByteArray, r: HTTPRequest, q: int):
	r.queue_free()
	if q != _q:
		return
	var bad := _trouble(result, code, headers)
	if bad != "":
		_fail(bad)
		return
	var p := JSON.parse(body.get_string_from_utf8())
	var branch := ""
	if code == 200 and p.error == OK and p.result is Dictionary:
		branch = String(p.result.get("default_branch", ""))
	if branch == "":
		_fail("There's no public repository at github.com/%s. Check the link (private ones can't be read)." % _repo_name())
		return
	_ask_tree([[branch, ""]], 0, true)

func _ask_releases():
	_api("/repos/%s/%s/releases?per_page=30" % [addr.owner, addr.repo], "_on_releases")

func _on_releases(result: int, code: int, headers: PoolStringArray, body: PoolByteArray, r: HTTPRequest, q: int):
	r.queue_free()
	if q != _q:
		return
	var only := String(addr.mode) == "releases"
	var bad := _trouble(result, code, headers)
	if bad != "" or code != 200:
		if not only:
			_part_done() # (the files are still listed)
		elif bad != "":
			_fail(bad)
		elif code == 404:
			_fail("There's no public repository at github.com/%s. Check the link (private ones can't be read)." % _repo_name())
		else:
			_fail("GitHub answered with an error (%d). Try again in a moment." % code)
		return
	_parse(body, "releases", {"tag": String(addr.tag), "web": GH_WEB})

# a long list is read off the main thread (a big repository's is megabytes)
func _parse(body: PoolByteArray, what: String, ctx: Dictionary):
	if OS.can_use_threads() and body.size() > 150000:
		var th := Thread.new()
		_threads.append(th)
		if th.start(self, "_parse_thread", [th, body, what, ctx, _q]) == OK:
			return
		_threads.erase(th)
	_parsed(_read(body, what, ctx), what, ctx, _q, null)

func _parse_thread(a: Array):
	var res := _read(a[1], a[2], a[3])
	call_deferred("_parsed", res, a[2], a[3], a[4], a[0])

# the maps in GitHub's answer -> {maps, truncated} or {error}
static func _read(body: PoolByteArray, what: String, ctx: Dictionary) -> Dictionary:
	var p := JSON.parse(body.get_string_from_utf8())
	if p.error != OK:
		return {"error": "GitHub sent something unreadable. Try again in a moment."}
	var maps := []
	if what == "tree":
		if not (p.result is Dictionary) or not (p.result.get("tree") is Array):
			return {"error": "GitHub sent something unreadable. Try again in a moment."}
		var ref := String(ctx.get("ref", "HEAD"))
		var folder := String(ctx.get("path", ""))
		var base := String(ctx.get("base", "")) # (the list is of this folder alone)
		for e in p.result.tree:
			if not (e is Dictionary) or String(e.get("type", "")) != "blob":
				continue
			var path := String(e.get("path", ""))
			if not is_map(path):
				continue
			if base != "":
				path = base + "/" + path
			elif folder != "" and not path.begins_with(folder + "/") and path != folder:
				continue
			maps.append({"raw": ref + "/" + path, "path": path, "size": int(e.get("size", 0)), "sha": String(e.get("sha", ""))})
		return {"maps": maps, "truncated": bool(p.result.get("truncated", false))}
	if not (p.result is Array):
		return {"error": "GitHub sent something unreadable. Try again in a moment."}
	var tag := String(ctx.get("tag", ""))
	for rel in p.result:
		if not (rel is Dictionary) or not (rel.get("assets") is Array):
			continue
		if tag != "" and String(rel.get("tag_name", "")) != tag:
			continue
		var title := String(rel.get("name", "")) if rel.get("name") is String else ""
		if title.strip_edges() == "":
			title = String(rel.get("tag_name", "release"))
		for a in rel.assets:
			if not (a is Dictionary) or not is_map(String(a.get("name", ""))):
				continue
			var url := String(a.get("browser_download_url", ""))
			if not url.begins_with(String(ctx.get("web", GH_WEB)) + "/"):
				continue
			maps.append({"url": url, "path": String(a.name), "size": int(a.get("size", 0)), "sha": "asset%d" % int(a.get("id", 0)), "release": title})
	return {"maps": maps, "truncated": false}

func _parsed(res: Dictionary, what: String, ctx: Dictionary, q: int, th):
	if th != null and th in _threads:
		th.wait_to_finish()
		_threads.erase(th)
	if q != _q:
		return
	if res.has("error"):
		if what == "releases" and String(addr.mode) != "releases":
			_part_done()
		else:
			_fail(String(res.error))
		return
	if what == "tree" and bool(res.truncated) and String(ctx.get("path", "")) != "" and not ctx.has("base"):
		# too big for GitHub to list whole: ask for the linked folder alone
		_held = res
		_api("/repos/%s/%s/git/trees/%s:%s?recursive=1" % [addr.owner, addr.repo, _enc(String(ctx.ref)), _enc(String(ctx.path))], "_on_folder", [ctx])
		return
	if bool(res.truncated):
		_truncated = true
	_found += res.maps
	_part_done()

func _on_folder(result: int, code: int, _headers, body: PoolByteArray, r: HTTPRequest, q: int, ctx: Dictionary):
	r.queue_free()
	if q != _q:
		return
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_parse(body, "tree", {"ref": String(ctx.ref), "path": String(ctx.path), "base": String(ctx.path)})
		return
	# (no luck: what the cut-off list had)
	_truncated = true
	_found += _held.get("maps", [])
	_part_done()

func _part_done():
	_waiting -= 1
	if _waiting <= 0:
		_finish()

static func _by_sort(a: Dictionary, b: Dictionary) -> bool:
	return String(a.sort) < String(b.sort)

func _finish():
	find_btn.disabled = false
	var repo := _repo_name()
	var seen := {}
	var from_releases := 0
	items = []
	for m in _found:
		var path := String(m.path)
		var it := {"repo": repo, "path": path, "size": int(m.size), "name": path.get_file().get_basename(), "ext": path.get_extension().to_lower()}
		if m.has("url"):
			it.url = String(m.url)
			it.where = "Release: " + String(m.release)
			it.key = "%s:%s" % [repo.to_lower(), m.sha]
			it.sort = "~" + String(m.release).to_lower() + "/" + path.to_lower() # (after the files)
			from_releases += 1
		else:
			it.raw = String(m.raw)
			var dir := path.get_base_dir()
			it.where = dir if dir != "" else repo
			it.key = "%s:%s@%s" % [repo.to_lower(), path, m.sha]
			it.sort = path.to_lower()
		if seen.has(it.key):
			continue
		seen[it.key] = true
		items.append(it)
	_found = []
	items.sort_custom(self, "_by_sort")
	filter.text = ""
	_filter_now()
	var n := items.size()
	var cut := " The repository is too big for GitHub to list whole, so some maps may be missing: paste a link to the folder with the maps instead." if _truncated else ""
	if n == 0:
		_say("No .sspm or .rhm maps found in %s.%s" % [repo, cut])
	elif String(addr.mode) == "file":
		_say("One map file in %s." % repo)
	else:
		var extra := ""
		if from_releases > 0 and from_releases < n:
			extra = " (%d of them in its releases)" % from_releases
		_say("%d map%s in %s%s.%s" % [n, "" if n == 1 else "s", repo, extra, cut])
	if n > 0 or not _truncated:
		_remember()

# ------------------------------------------------------------------ the list

func _on_filter(_t := ""):
	page = 1
	_filter_now()

func _filter_now():
	var words := []
	for w in filter.text.to_lower().split(" ", false):
		words.append(String(w))
	shown = []
	for it in items:
		var ok := true
		for w in words:
			if String(it.sort).find(w) == -1:
				ok = false
				break
		if ok:
			shown.append(it)
	_show_page()

func _pages() -> int:
	return int(max(1, ceil(shown.size() / float(PER_PAGE))))

func _go_page(d: int):
	page = int(clamp(page + d, 1, _pages()))
	_show_page()
	scroll.scroll_vertical = 0

func _show_page():
	for c in grid.get_children():
		c.queue_free()
	_btns = {}
	page = int(clamp(page, 1, _pages()))
	tools.visible = items.size() > 1
	pager.visible = _pages() > 1
	page_label.text = "Page %d of %d" % [page, _pages()]
	prev_btn.disabled = page <= 1
	next_btn.disabled = page >= _pages()
	_show_all_btn()
	for i in range((page - 1) * PER_PAGE, int(min(page * PER_PAGE, shown.size()))):
		grid.add_child(_card(shown[i]))
	call_deferred("_relayout")

func _card(it: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.rect_min_size = Vector2(cb.CARD_W, 0)
	var sb: StyleBoxFlat = cb._flat(cb.CARD_BG, 4, Color(1, 1, 1, 0.06), 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 4)
	card.add_child(v)
	var name_l: Label = cb._label(Globals.s(it.name), cb.f_bold)
	name_l.clip_text = true
	name_l.hint_tooltip = String(it.path)
	v.add_child(name_l)
	var where: Label = cb._label(Globals.s(it.where), cb.f_small, cb.LILAC)
	where.clip_text = true
	where.hint_tooltip = String(it.where)
	v.add_child(where)
	# (a file kept with Git LFS lists as a few bytes: its real size isn't known yet)
	var size: int = it.size
	v.add_child(cb._label((".%s" % it.ext) if size < 1024 else "%s · .%s" % [cb._size_text(size), it.ext], cb.f_small, cb.DIM))
	var b: Button = cb._button("", "_on_get", [it], false, self)
	b.name = "Get"
	v.add_child(b)
	_btns[it.key] = b
	_paint(it)
	return card

# the song a map from here became, if it's still in your list
func _song_of(it: Dictionary):
	var id := String(_save.got.get(it.key, ""))
	if id == "" or Rhythia.registry_song == null or not Rhythia.registry_song.idx_id.has(id):
		return null
	return Rhythia.registry_song.get_item(id)

func _paint(it: Dictionary):
	var b = _btns.get(it.key)
	if b == null or not is_instance_valid(b):
		return
	var st := String(_state.get(it.key, ""))
	var have: bool = st == "" and _song_of(it) != null
	b.disabled = st != ""
	b.text = "Waiting…" if st == "wait" else ("Downloading…" if st == "busy" else ("Downloaded" if have else "Download"))
	b.hint_tooltip = "It's in your map list. Press to download it again." if have else ""
	b.add_color_override("font_color", cb.ACCENT if have else cb.TEXT)

func _show_all_btn():
	if all_btn == null:
		return
	if not _batch.empty():
		all_btn.text = "Stop (%d to go)" % (_queue.size() + _active)
	else:
		all_btn.text = "Download all" if shown.size() == items.size() else "Download these %d" % shown.size()
	all_btn.disabled = shown.empty() and _batch.empty()

# ------------------------------------------------------------------ downloading

func _on_get(it: Dictionary):
	if _state.has(it.key):
		return
	_state[it.key] = "wait"
	_queue.append(it)
	_paint(it)
	_next()

func _on_all():
	if not _batch.empty():
		# stop: what hasn't started is dropped
		for it in _queue:
			_state.erase(it.key)
			_paint(it)
		_queue = []
		_batch_check()
		return
	var todo := []
	for it in shown:
		if not _state.has(it.key) and _song_of(it) == null:
			todo.append(it)
	if todo.empty():
		Globals.notify(Globals.NOTIFY_INFO, "You already have all of these maps.", "GitHub maps")
		return
	_batch = {"ok": 0, "bad": 0}
	for it in todo:
		_state[it.key] = "wait"
		_queue.append(it)
		_paint(it)
	_show_all_btn()
	_next()

func _link(it: Dictionary, lfs := false) -> String:
	if it.has("url"):
		return String(it.url)
	return "%s/%s/%s" % [GH_MEDIA if lfs else GH_RAW, it.repo, _enc(String(it.raw))]

func _next():
	while _active < MAX_DOWNLOADS and not _queue.empty():
		_fetch(_queue.pop_front(), false)
	_show_all_btn()

func _fetch(it: Dictionary, lfs: bool):
	_state[it.key] = "busy"
	_paint(it)
	var r := HTTPRequest.new()
	r.timeout = 600
	r.use_threads = OS.can_use_threads()
	add_child(r)
	r.connect("request_completed", self, "_on_file", [r, it, lfs])
	_active += 1
	var headers := PoolStringArray()
	if OS.get_name() != "HTML5":
		headers.append("User-Agent: Chromia")
	if r.request(_link(it, lfs), headers) != OK:
		r.queue_free()
		_active -= 1
		_took(it, null, "Couldn't start the download.")

func _on_file(result: int, code: int, _headers, body: PoolByteArray, r: HTTPRequest, it: Dictionary, lfs: bool):
	r.queue_free()
	_active -= 1
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.size() < 8:
		var why: String = "the connection stalled" if result == HTTPRequest.RESULT_TIMEOUT else ("it isn't there any more" if code == 404 else "error %d / %d" % [result, code])
		if OS.get_name() == "HTML5" and it.has("url") and code != 404:
			why = "the web version can't download from a release: use the game on your device" # (GitHub's release links don't allow it)
		_took(it, null, "Download failed (%s)." % why)
		return
	# a file kept with Git LFS: this is only a note saying where the real one is
	if not lfs and it.has("raw") and body.size() < 1024 and body.get_string_from_ascii().begins_with("version https://git-lfs.github.com/spec/"):
		_fetch(it, true)
		return
	_take(it, body)

func _take(it: Dictionary, body: PoolByteArray):
	# .rhm is a zip ("PK"); .sspm starts with "SS+m"
	if body[0] == 0x50 and body[1] == 0x4b:
		var importer = RhmImporter.new()
		add_child(importer)
		var res = yield(importer.import_rhm_bytes(body), "completed")
		importer.queue_free()
		_took(it, res.song, String(res.error) if res.song == null else "")
		return
	if not (body[0] == 0x53 and body[1] == 0x53 and body[2] == 0x2b and body[3] == 0x6d):
		_took(it, null, "That file isn't a map the game can read.")
		return
	var d := Directory.new()
	d.make_dir_recursive(Globals.p(DOWNLOAD_DIR))
	var path: String = Globals.p(DOWNLOAD_DIR).plus_file("github_%d.sspm" % abs(String(it.key).hash()))
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		_took(it, null, "Couldn't save the download.")
		return
	f.store_buffer(body)
	f.close()
	# (the same import as a dropped .sspm: it says itself what's wrong with a bad one)
	var song = null
	var run = Rhythia.menu_node("Main/Maps/Results/Results/RS/H1/Info/Run")
	if run and run.has_method("_import_sspm"):
		song = run._import_sspm(path)
	else:
		var tmp = load("res://scripts/ui/menu/buttons/RunMapButton.gd").new()
		song = tmp._import_sspm(path)
		tmp.free()
	d.remove(path)
	_took(it, song, "")

func _refresh_maps():
	var list = Rhythia.menu_node("Main/Maps/MapRegistry/S/VBoxContainer")
	if list and list.has_method("refresh_songs"):
		list.refresh_songs()

# one download is over (song = null: it didn't work, why says so unless it was said already)
func _took(it: Dictionary, song, why: String):
	_state.erase(it.key)
	if song != null:
		_save.got[it.key] = String(song.id)
		_write_save()
	elif why != "":
		Globals.notify(Globals.NOTIFY_WARN, why, Globals.s(it.name))
	if _batch.empty():
		if song != null:
			_refresh_maps()
			Globals.notify(Globals.NOTIFY_SUCCEED, "'%s' is in your map list now." % Globals.s(it.name), "Map Downloaded")
	else:
		_batch["ok" if song != null else "bad"] += 1
	_paint(it)
	_next()
	_batch_check()

func _batch_check():
	if _batch.empty() or _active > 0 or not _queue.empty():
		_show_all_btn()
		return
	var ok := int(_batch.ok)
	var bad := int(_batch.bad)
	_batch = {}
	_show_all_btn()
	if ok > 0:
		_refresh_maps()
	if ok > 0 or bad > 0:
		Globals.notify(Globals.NOTIFY_SUCCEED if ok > 0 else Globals.NOTIFY_WARN, "%d map%s added to your map list%s." % [ok, "" if ok == 1 else "s", (", %d didn't work" % bad) if bad > 0 else ""], "GitHub maps")
