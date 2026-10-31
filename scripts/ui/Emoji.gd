extends Reference

# Emoji in chat. Godot 3's fonts can't draw colour emoji, so each emoji in a
# message is drawn as a small picture inside the RichTextLabel instead.
#
# The pictures are Twemoji (github.com/jdecked/twemoji, CC-BY 4.0: see
# assets/emoji/LICENSE-GRAPHICS.txt), 72x72 PNGs packed one after another in
# assets/emoji/twemoji.emojipack; twemoji_index.json says where each one is
# (by its codepoints in hex joined with "-", without the FE0F variation mark).
# A picture is read from the pack the first time it's needed, then kept.
#
#   Emoji.add_text(rich_text_label, text, size_px)   in place of add_text

const PACK := "res://assets/emoji/twemoji.emojipack"
const INDEX := "res://assets/emoji/twemoji_index.json"
const META := "chromia_emoji"

static func _data() -> Dictionary:
	if Engine.has_meta(META):
		return Engine.get_meta(META)
	var d := {"ok": false, "e": {}, "max": 1, "tex": {}}
	var f := File.new()
	if f.open(INDEX, File.READ) == OK:
		var r := JSON.parse(f.get_as_text())
		f.close()
		if r.error == OK and r.result is Dictionary and r.result.get("e") is Dictionary:
			d.e = r.result.e
			d.max = int(r.result.get("max_len", 8))
			d.ok = true
	Engine.set_meta(META, d)
	return d

static func _texture(key: String) -> Texture:
	var d := _data()
	if d.tex.has(key):
		return d.tex[key]
	var tex: ImageTexture = null
	var at = d.e.get(key)
	var f := File.new()
	if at is Array and at.size() == 2 and f.open(PACK, File.READ) == OK:
		f.seek(int(at[0]))
		var buf := f.get_buffer(int(at[1]))
		f.close()
		var img := Image.new()
		if img.load_png_from_buffer(buf) == OK:
			tex = ImageTexture.new()
			tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	d.tex[key] = tex
	return tex

# the text's characters as codepoints: [codepoint, start, end] (Windows keeps
# text as UTF-16, so most emoji come as two halves to join)
static func _codepoints(s: String) -> Array:
	var out := []
	var i := 0
	var n := s.length()
	while i < n:
		var c := ord(s[i])
		if c >= 0xD800 and c <= 0xDBFF and i + 1 < n:
			var lo := ord(s[i + 1])
			if lo >= 0xDC00 and lo <= 0xDFFF:
				out.append([0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00), i, i + 2])
				i += 2
				continue
		out.append([c, i, i + 1])
		i += 1
	return out

static func _maybe(s: String) -> bool:
	for i in range(s.length()):
		if ord(s[i]) >= 0x2000:
			return true
	return false

# Adds the text to the label, emoji as pictures (size_px tall).
static func add_text(rtl: RichTextLabel, text: String, size_px: int = 18):
	if text == "" or not _maybe(text):
		rtl.add_text(text)
		return
	var d := _data()
	if not d.ok:
		rtl.add_text(text)
		return
	var seq := []
	for c in _codepoints(text):
		if c[0] != 0xFE0F:
			seq.append(c)
	var from := 0 # (text up to here is added)
	var i := 0
	while i < seq.size():
		var found := 0
		var key := ""
		# the longest emoji starting here (plain text characters below U+00A9
		# never start one on their own: digits, # and * only with a keycap)
		var longest: int = min(d.max, seq.size() - i)
		for l in range(longest, 0, -1):
			if l == 1 and seq[i][0] < 0xA9:
				break
			var parts := []
			for k in range(l):
				parts.append("%x" % seq[i + k][0])
			key = PoolStringArray(parts).join("-")
			if d.e.has(key):
				found = l
				break
		if found == 0:
			i += 1
			continue
		var tex := _texture(key)
		if tex == null:
			i += found
			continue
		var start: int = seq[i][1]
		if start > from:
			rtl.add_text(text.substr(from, start - from))
		rtl.add_image(tex, size_px, size_px)
		from = seq[i + found - 1][2]
		while from < text.length() and ord(text[from]) == 0xFE0F:
			from += 1
		i += found
	if from < text.length():
		rtl.add_text(text.substr(from))
