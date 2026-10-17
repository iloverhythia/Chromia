extends Reference

# Opens the real Windows file picker (Explorer dialog) through PowerShell on a
# background thread, so the game keeps running while it's open.
# Emits "done(ok, paths)": ok=false means the dialog couldn't be shown at all
# (caller should fall back to the in-game browser); ok=true with an empty
# array means the user cancelled.

signal done(ok, paths)

var _thread: Thread

static func available() -> bool:
	return OS.get_name() == "Windows"

func _ps_quote(s: String) -> String:
	return "'" + s.replace("'", "''") + "'"

# "*.png, *.jpg ; Image files" -> "Image files|*.png;*.jpg"
func _win_filter(filters: PoolStringArray) -> String:
	var parts := []
	for f in filters:
		var desc := ""
		var pats: String = f
		var semi: int = f.find(";")
		if semi != -1:
			pats = f.substr(0, semi)
			desc = f.substr(semi + 1).strip_edges()
		var list := []
		for p in pats.split(",", false):
			p = p.strip_edges()
			if p != "": list.append(p)
		if list.empty(): continue
		var joined := PoolStringArray(list).join(";")
		if desc == "": desc = joined
		parts.append("%s (%s)|%s" % [desc, joined.replace(";", ", "), joined])
	parts.append("All files (*.*)|*.*")
	return PoolStringArray(parts).join("|")

# PowerShell -EncodedCommand wants base64 of UTF-16LE text.
func _encode(script: String) -> String:
	var bytes := PoolByteArray()
	for i in script.length():
		var c: int = script.ord_at(i)
		if c > 0xFFFF:
			c -= 0x10000
			var hi := 0xD800 + (c >> 10)
			var lo := 0xDC00 + (c & 0x3FF)
			bytes.append(hi & 0xFF); bytes.append(hi >> 8)
			bytes.append(lo & 0xFF); bytes.append(lo >> 8)
		else:
			bytes.append(c & 0xFF); bytes.append(c >> 8)
	return Marshalls.raw_to_base64(bytes)

func _script(mode: String, filters: PoolStringArray, multiselect: bool, initial: String, title: String) -> String:
	var lines := [
		"$ErrorActionPreference = 'Stop'",
		"[Console]::OutputEncoding = [Text.Encoding]::UTF8",
		"Add-Type -AssemblyName System.Windows.Forms",
		"[System.Windows.Forms.Application]::EnableVisualStyles()",
		# An always-on-top owner keeps the dialog in front of the game window.
		"$owner = New-Object System.Windows.Forms.Form -Property @{TopMost = $true}",
	]
	var dir := initial.replace("/", "\\")
	if mode == "folder":
		lines.append("$d = New-Object System.Windows.Forms.FolderBrowserDialog")
		lines.append("$d.Description = " + _ps_quote(title))
		lines.append("if (Test-Path -LiteralPath %s) { $d.SelectedPath = %s }" % [_ps_quote(dir), _ps_quote(dir)])
		lines.append("if ($d.ShowDialog($owner) -eq 'OK') { $d.SelectedPath }")
	else:
		if mode == "save":
			lines.append("$d = New-Object System.Windows.Forms.SaveFileDialog")
		else:
			lines.append("$d = New-Object System.Windows.Forms.OpenFileDialog")
			lines.append("$d.Multiselect = $%s" % ("true" if multiselect else "false"))
		lines.append("$d.Title = " + _ps_quote(title))
		lines.append("$d.Filter = " + _ps_quote(_win_filter(filters)))
		var start_dir := dir
		if mode == "save" and dir.get_extension() != "":
			lines.append("$d.FileName = " + _ps_quote(dir.get_file()))
			start_dir = dir.get_base_dir()
		lines.append("if (Test-Path -LiteralPath %s) { $d.InitialDirectory = %s }" % [_ps_quote(start_dir), _ps_quote(start_dir)])
		lines.append("if ($d.ShowDialog($owner) -eq 'OK') { $d.FileNames | ForEach-Object { $_ } }")
	lines.append("$owner.Dispose()")
	# Proves the dialog really ran (vs. a PowerShell that silently did nothing).
	lines.append("'FURRIA_DIALOG_DONE'")
	return PoolStringArray(lines).join("\n")

func start(mode: String, filters: PoolStringArray, multiselect: bool, initial: String, title: String) -> bool:
	if not available(): return false
	var args := ["-NoProfile", "-NonInteractive", "-STA", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
		"-EncodedCommand", _encode(_script(mode, filters, multiselect, initial, title))]
	_thread = Thread.new()
	return _thread.start(self, "_run", args) == OK

func _run(args: Array):
	var out := []
	var code: int = OS.execute("powershell.exe", args, true, out, true)
	var text: String = PoolStringArray(out).join("")
	var paths := []
	for line in text.split("\n", false):
		line = line.strip_edges()
		if line != "" and (line.find(":\\") == 1 or line.begins_with("\\\\")):
			paths.append(line.replace("\\", "/"))
	var ok: bool = text.find("FURRIA_DIALOG_DONE") != -1 or not paths.empty()
	if not ok:
		print("[file dialog] PowerShell dialog failed (exit %d): %s" % [code, text.strip_edges()])
	call_deferred("_finish", ok, paths)

func _finish(ok: bool, paths: Array):
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	emit_signal("done", ok, paths)
