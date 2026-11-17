extends Node

# The pictures of picture frames and cards (an admin's upload: savia_web
# src/customart.js, /savia-art/<file>.png): downloaded once each and kept,
# for FrameDraw.gd ("image" frames) and the card backgrounds. pic() returns
# the picture, or null while it's coming ("loaded(url)" when it's there).
#
# A moving frame's picture is a GIF (the server keeps one next to an animated
# upload: /savia-art/<file>.gif, the frame's image_gif_url). It is decoded on
# a thread (AnimPic.gd) into a picture that plays by itself, so whatever
# draws it shows it moving.

signal loaded(url)

const SITE := "https://chromia.lol"
var _tex := {} # url -> Texture
var _pending := {} # url -> true
var _queue := [] # asked for before this was in the tree

static func instance():
	var root = Engine.get_main_loop().root
	var n = root.get_node_or_null("FrameImages")
	if n == null:
		n = load("res://scripts/ui/FrameImages.gd").new()
		n.name = "FrameImages"
		root.call_deferred("add_child", n) # (asked from a _draw: added after it)
	return n

func pic(url: String):
	if url == "":
		return null
	if _tex.has(url):
		return _tex[url]
	if not _pending.has(url):
		_pending[url] = true
		if is_inside_tree():
			_fetch(url)
		else:
			_queue.append(url)
	return null

func _ready():
	for u in _queue:
		_fetch(u)
	_queue = []

func _fetch(url: String):
	var full := (SITE + url) if url.begins_with("/") else url
	if not full.begins_with("http"):
		return
	var r := HTTPRequest.new()
	r.timeout = 15
	add_child(r)
	r.connect("request_completed", self, "_on_done", [r, url])
	if r.request(full) != OK:
		r.queue_free()

func _on_done(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, url: String):
	r.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.empty():
		return
	var AnimPic = load("res://scripts/ui/AnimPic.gd")
	if AnimPic.is_gif(body):
		AnimPic.load_async(body, "frameart:" + url, 0, false, self, "_on_gif", [url])
		return
	var img := Image.new()
	if img.load_png_from_buffer(body) != OK and img.load_jpg_from_buffer(body) != OK and img.load_webp_from_buffer(body) != OK:
		return
	img.generate_mipmaps()
	var t := ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	_tex[url] = t
	emit_signal("loaded", url)

# a GIF, decoded (null: it couldn't be read; the still picture stays)
func _on_gif(tex, url: String):
	if tex == null:
		return
	_tex[url] = tex
	emit_signal("loaded", url)
