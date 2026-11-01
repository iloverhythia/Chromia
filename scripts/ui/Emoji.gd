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

# --- emoji while typing (in a LineEdit) ---------------------------------------
# A LineEdit can only draw its font, so it gets a BitmapFont that holds the
# emoji typed so far as pictures (the same ones), with its own font as the
# fallback for everything else. The pictures are added as they're typed.
# If this Godot can't (checked once), the field keeps its font.
#
#   Emoji.field(line_edit)    once its font is set
static func field(le: LineEdit):
	if le == null or le.has_node("EmojiField"):
		return
	var f := Field.new()
	f.name = "EmojiField"
	le.add_child(f)

class Field extends Node:
	var le: LineEdit
	var base: Font = null
	var bf: BitmapFont = null
	var px := 0
	var have := {} # codepoint -> true (in bf)

	func _ready():
		le = get_parent()
		le.connect("text_changed", self, "_on_text")
		le.connect("resized", self, "_on_text", [""])
		_on_text(le.text)

	func _on_text(_t):
		if Engine.has_meta("chromia_emoji_field_bad"):
			return
		var E = load("res://scripts/ui/Emoji.gd")
		var text := le.text
		if bf == null and not E._maybe(text):
			return # (nothing to draw yet: the field keeps its own font)
		var cur := le.get_font("font")
		if cur != bf:
			base = cur # (its font, or one set since)
			bf = null
		if base == null:
			return
		var h := int(base.get_height())
		if bf == null or px != h:
			_build(h)
		var d: Dictionary = E._data()
		if not d.ok:
			return
		var added := false
		var check := ""
		for c in E._codepoints(text):
			var cp: int = c[0]
			if cp < 0xA9 or have.has(cp):
				continue
			var key := "%x" % cp
			if not d.e.has(key):
				continue
			var tex: Texture = E._texture(key)
			if tex == null:
				continue
			_add(cp, tex)
			added = true
			if check == "" and cp >= 0x10000:
				check = text.substr(c[1], c[2] - c[1])
		if check != "" and not Engine.has_meta("chromia_emoji_field_ok"):
			# does this Godot draw a BitmapFont's emoji (two UTF-16 halves on Windows)?
			if abs(bf.get_string_size(check).x - _advance()) > 0.5:
				Engine.set_meta("chromia_emoji_field_bad", true)
				le.add_font_override("font", base)
				bf = null
				return
			Engine.set_meta("chromia_emoji_field_ok", true)
		if added:
			le.update()

	func _size() -> int:
		return int(max(8, round(px * 0.85)))

	func _advance() -> float:
		return float(_size() + 2)

	func _build(h: int):
		px = h
		have = {}
		bf = BitmapFont.new()
		bf.height = base.get_height()
		bf.ascent = base.get_ascent()
		bf.fallback = base
		# the joiner, the variation mark and skin tones: nothing on their own
		for cp in [0x200D, 0xFE0F, 0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]:
			bf.add_char(cp, -1, Rect2(), Vector2(), 0)
			have[cp] = true
		le.add_font_override("font", bf)

	func _add(cp: int, tex: Texture):
		var s := _size()
		var img: Image = tex.get_data()
		if img == null:
			return
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.resize(s, s, Image.INTERPOLATE_LANCZOS)
		var t := ImageTexture.new()
		t.create_from_image(img, Texture.FLAG_FILTER)
		bf.add_texture(t)
		bf.add_char(cp, bf.get_texture_count() - 1, Rect2(0, 0, s, s), Vector2(1, round((px - s) / 2.0)), _advance())
		have[cp] = true

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
