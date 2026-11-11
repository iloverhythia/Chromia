extends Reference

# Maps with hundreds of thousands of notes. Opening one goes through every
# note several times in script (reading it from the file, putting the notes in
# order, the chart's fingerprint), each step a few millionths of a second a
# note: seconds in all on a computer, several times that on a phone. (More
# processor cores don't help: making arrays and texts from several threads at
# once is slower in this engine than from one, measured.) So the per-note part
# is kept as small as it can be and the rest is handed to the engine in bulk:
#  - the file's bytes are turned into whole lists of numbers in one engine
#    call each (decode), and the script only picks them out;
#  - the notes' texts ("[x, y, ms]", for the fingerprint and for the order of
#    notes at the same time) are made a few dozen notes per engine call.
# What comes out is, note for note and letter for letter, what the plain
# loops give; those remain for small maps and for anything unusual.

const TEXT_CHUNK := 32 # notes per text call (a list's text is built by adding on, so short lists)

# --- the notes' texts ---------------------------------------------------------------

# String(n) of every note n = [x, y, ms] without its brackets ("x, y, ms"), in
# order. Two notes at the same time are in the same order by these as by
# their full texts.
static func inner_texts(arr: Array) -> PoolStringArray:
	var out := PoolStringArray()
	var n := arr.size()
	var a := 0
	while a < n:
		var b: int = int(min(n, a + TEXT_CHUNK))
		var s := String(arr.slice(a, b - 1)) # "[[x, y, ms], [x, y, ms]]"
		out.append_array(s.substr(2, s.length() - 4).split("], [", true))
		a = b
	return out

# every note's text, each followed by ";" (what the fingerprint is made of)
static func chart_text(arr: Array) -> String:
	var parts := PoolStringArray()
	var n := arr.size()
	var a := 0
	while a < n:
		var b: int = int(min(n, a + TEXT_CHUNK))
		var s := String(arr.slice(a, b - 1))
		parts.append(s.substr(1, s.length() - 2).replace("], [", "];["))
		a = b
	return parts.join(";") + ";" if n > 0 else ""

# The same text for notes whose x and y are whole numbers from 0 to 9 and whose
# time is a whole number (most maps): "[x, y, " is one of a hundred texts made
# once, so a note costs its time's text and nothing else. "" when some note
# isn't like that (chart_text does those).
static func chart_text_digits(arr: Array) -> String:
	var n := arr.size()
	if n == 0:
		return ""
	var open := []
	var next := []
	for x in range(10):
		for y in range(10):
			open.append("[%d, %d, " % [x, y])
			next.append("];[%d, %d, " % [x, y])
	var parts := PoolStringArray()
	parts.resize(n * 2 + 1)
	for i in range(n):
		var e: Array = arr[i]
		var x = e[0]
		var y = e[1]
		var v = e[2]
		# (whole, 0 to 9, and not the "-0" a decimal number can be)
		if e.size() != 3 or typeof(v) != TYPE_INT or x < 0 or x > 9 or y < 0 or y > 9 or x != floor(x) or y != floor(y) or (x == 0 and pow(float(x), -1.0) < 0.0) or (y == 0 and pow(float(y), -1.0) < 0.0):
			return ""
		parts[i * 2] = (next if i > 0 else open)[int(x) * 10 + int(y)]
		parts[i * 2 + 1] = String(v)
	parts[n * 2] = "];"
	return parts.join("")

# Notes already in time order: each group at the very same time put in the
# order of the notes' texts (what a comparer that says String(a) < String(b)
# for them gives). One text per note that shares its time with another,
# instead of two per comparison; notes alone at their time cost nothing.
# false: not notes of plain numbers, the caller's own loop does it.
static func order_ties_by_text(arr: Array, k: int) -> bool:
	var n := arr.size()
	if n < 2:
		return true
	var run_start := 0
	var prev_t = arr[0][k]
	for i in range(1, n + 1):
		if i < n and arr[i][k] == prev_t:
			continue
		var count: int = i - run_start
		if count == 2:
			if String(arr[run_start + 1]) < String(arr[run_start]):
				var first = arr[run_start]
				arr[run_start] = arr[run_start + 1]
				arr[run_start + 1] = first
		elif count > 2:
			var group: Array = arr.slice(run_start, i - 1)
			var texts: PoolStringArray = inner_texts(group)
			if texts.size() != count:
				return false
			var by := {}
			for j in range(count):
				var s: String = texts[j]
				if by.has(s):
					by[s].append(group[j])
				else:
					by[s] = [group[j]]
			var keys: Array = by.keys()
			keys.sort()
			var at := run_start
			for s in keys:
				for e in by[s]:
					arr[at] = e
					at += 1
		if i < n:
			run_start = i
			prev_t = arr[i][k]
	return true

# --- a .sspm's notes from its bytes ----------------------------------------------------

# the bytes from `from` on as whole 4-byte numbers (one engine call)
static func _ints(bytes: PoolByteArray, from: int) -> PoolIntArray:
	var count: int = (bytes.size() - from) / 4
	if count <= 0:
		return PoolIntArray()
	var head: PoolByteArray = var2bytes(PoolIntArray([0])).subarray(0, 7)
	var sp := StreamPeerBuffer.new()
	sp.data_array = head
	sp.seek(4)
	sp.put_u32(count)
	var all: PoolByteArray = sp.data_array
	all.append_array(bytes.subarray(from, from + count * 4 - 1))
	var v = bytes2var(all)
	return v if v is PoolIntArray else PoolIntArray()

# ...and as 4-byte decimal numbers
static func _reals(bytes: PoolByteArray, from: int) -> PoolRealArray:
	var count: int = (bytes.size() - from) / 4
	if count <= 0:
		return PoolRealArray()
	var head: PoolByteArray = var2bytes(PoolRealArray([0.0])).subarray(0, 7)
	var sp := StreamPeerBuffer.new()
	sp.data_array = head
	sp.seek(4)
	sp.put_u32(count)
	var all: PoolByteArray = sp.data_array
	all.append_array(bytes.subarray(from, from + count * 4 - 1))
	var v = bytes2var(all)
	return v if v is PoolRealArray else PoolRealArray()

# The notes of a marker block that is notes only, `count` of them, all stored
# the same way (8 bytes each: whole-number places; 14: decimal ones).
# -> [notes [x, y, ms] in the file's order, order] where order is 0 in time
#    order with no two at the same time, 1 in order with some at the same
#    time, 2 out of order, and -1 when the notes are already in their final
#    order (time, then text) although some share a time;
#    [] when the block isn't like that: the caller reads it the usual way.
const PLACE_BITS := 22
static func decode(bytes: PoolByteArray, count: int) -> Array:
	if count <= 0:
		return []
	var list := []
	list.resize(count)
	var st := 0
	var prev := -1
	if bytes.size() == count * 8:
		var ints: PoolIntArray = _ints(bytes, 0)
		if ints.size() != count * 2:
			return []
		var digits := true
		var final := true # in the order they end up in: by time, then x, then y
		var prev_key := -1
		for i in range(count):
			var w: int = ints[i * 2 + 1]
			if w & 0xFFFF != 0:
				return [] # (another kind of marker, or a place not stored as two whole numbers)
			var ms: int = ints[i * 2] & 0xFFFFFFFF
			if ms <= prev and st != 2:
				st = 2 if ms < prev else 1
			prev = ms
			var x: int = (w >> 16) & 255
			var y: int = (w >> 24) & 255
			if x > 9 or y > 9:
				digits = false
			var key: int = ms * 100 + x * 10 + y
			if key < prev_key:
				final = false
			prev_key = key
			list[i] = [float(x), float(y), ms]
		if st == 1 and digits and final:
			return [list, -1] # (a file written in order: nothing to sort)
		if st != 0 and digits and count <= 4194304:
			# out of order, or some at the same time: one number per note (its
			# time, x, y, then its place in the file), sorted by the engine. The
			# order Song.sort_timed gives such notes.
			var keys := []
			keys.resize(count)
			for i in range(count):
				var w: int = ints[i * 2 + 1]
				keys[i] = (((ints[i * 2] & 0xFFFFFFFF) * 100 + ((w >> 16) & 255) * 10 + ((w >> 24) & 255)) << PLACE_BITS) | i
			keys.sort()
			var out := []
			out.resize(count)
			for i in range(count):
				out[i] = list[keys[i] & 4194303]
			return [out, -1]
		return [list, st]
	if bytes.size() == count * 14:
		# a note is 14 bytes, so every other one starts 2 bytes off a 4-byte
		# step: the bytes read as numbers twice, from 0 and from 2
		var i0: PoolIntArray = _ints(bytes, 0)
		var i2: PoolIntArray = _ints(bytes, 2)
		var f0: PoolRealArray = _reals(bytes, 0)
		var f2: PoolRealArray = _reals(bytes, 2)
		if i0.size() != (count * 14) / 4 or i2.size() != (count * 14 - 2) / 4 or f0.size() != i0.size() or f2.size() != i2.size():
			return []
		for i in range(count):
			var o: int = i * 14
			var ms: int
			var w: int
			var x: float
			var y: float
			if i & 1 == 0:
				var j: int = o >> 2
				ms = i0[j] & 0xFFFFFFFF
				w = i0[j + 1]
				x = f2[j + 1]
				y = f2[j + 2]
			else:
				var j: int = (o - 2) >> 2
				ms = i2[j] & 0xFFFFFFFF
				w = i2[j + 1]
				x = f0[j + 2]
				y = f0[j + 3]
			if w & 0xFFFF != 0x0100:
				return []
			if ms <= prev and st != 2:
				st = 2 if ms < prev else 1
			prev = ms
			list[i] = [x, y, ms]
		return [list, st]
	return []

# --- a .sspm's notes to bytes ----------------------------------------------------------

# The marker block of a map whose markers are its notes only: every note
# [x, y, ms] as the map writer stores one (its time, the marker type, then its
# place as two whole numbers when both are whole, not negative and under 256,
# as two decimal numbers otherwise), in the order given.
static func encode(list: Array, type_id: int) -> PoolByteArray:
	var sp := StreamPeerBuffer.new()
	sp.resize(list.size() * 14)
	sp.seek(0)
	for e in list:
		# (as a Vector2, like the writer always took a place: single precision,
		# which is also what decides whether it counts as whole)
		var v := Vector2(e[0], e[1])
		sp.put_u32(int(floor(e[e.size() - 1])))
		sp.put_u8(type_id)
		if floor(abs(v.x)) == v.x and floor(abs(v.y)) == v.y and v.x < 256 and v.y < 256:
			sp.put_u8(0)
			sp.put_u8(int(v.x))
			sp.put_u8(int(v.y))
		else:
			sp.put_u8(1)
			sp.put_float(v.x)
			sp.put_float(v.y)
	var size: int = sp.get_position()
	return sp.data_array.subarray(0, size - 1) if size > 0 else PoolByteArray()
