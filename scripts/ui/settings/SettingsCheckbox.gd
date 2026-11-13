extends CheckBox

export(String) var target

func upd():
#	print('scb "%s"' % name)
	pressed = Rhythia.get(target)
	if target == "xp_boost":
		visible = String(Rhythia.discord_user.get("id", "")) == Rhythia.XP_BOOST_DISCORD_ID
	
func _pressed():
	# var a = OS.get_ticks_usec()
#	print('scb "%s" press' % name)
	if pressed != Rhythia.get(target):
		Rhythia.set(target,pressed)
#	print('scb "%s" press done, took %s usec' % [name,Globals.comma_sep(OS.get_ticks_usec() - a)])

func _ready():
	upd()
	if target == "absolute_mode" and Rhythia.device("mobile"):
		call_deferred("_add_touch_toggle")
	if target == "wave_menu":
		call_deferred("_add_xp_boost_toggle")
		call_deferred("_add_map_grid")
		call_deferred("_add_show_map_rp")
		call_deferred("_add_new_settings_ui")
		call_deferred("_add_frame_smoothing")
		call_deferred("_add_stream_mode")
	if target == "map_grid":
		Rhythia.connect("map_grid_changed", self, "upd")
	if target == "realistic_autoplay":
		call_deferred("_add_legacy_mouse")
	if target == "allow_spectators":
		call_deferred("_add_lobby_invites")
	if target == "xp_boost":
		Rhythia.connect("discord_login_changed", self, "upd") # (Discord can sign in after the settings were built)

# Settings > Online: Allow Lobby Invites, under Allow Spectators
func _add_lobby_invites():
	var parent = get_parent()
	if parent == null or parent.has_node("AllowLobbyInvites"):
		return
	var cb = duplicate()
	cb.name = "AllowLobbyInvites"
	cb.target = "allow_lobby_invites"
	cb.text = "Allow Lobby Invites"
	cb.hint_tooltip = "On: people can invite you into their multiplayer lobby (you choose to join or not). Off: nobody can invite you"
	parent.add_child(cb)
	parent.move_child(cb, get_index() + 1)
	# (test builds only) where your passes go
	if Online.build_channel() == "test" and not parent.has_node("PassesToMain"):
		var pm = duplicate()
		pm.name = "PassesToMain"
		pm.target = "passes_to_main"
		pm.text = "Send Passes to the Main Server"
		pm.hint_tooltip = "On: your passes on this test build go to the main server and count on the real leaderboards (SP, XP, your profile). Off: they go to the test server."
		parent.add_child(pm)
		parent.move_child(pm, cb.get_index() + 1)

# Experimental: Legacy Mouse Movement (Cursor.gd), under Realistic Autoplay
func _add_legacy_mouse():
	var parent = get_parent()
	if parent == null or parent.has_node("LegacyMouse") or Rhythia.device("mobile"):
		return
	var cb = duplicate()
	cb.name = "LegacyMouse"
	cb.target = "legacy_mouse"
	cb.text = "Legacy Mouse Movement"
	cb.hint_tooltip = "The cursor moves with the mouse exactly the way it did in Chromia's very first update (its original mouse code, with your sensitivity). Turns No Delay off while it's on."
	parent.add_child(cb)
	parent.move_child(cb, get_index() + 1)
	# Experimental: the Modern UI (scripts/ui/modern/ModernUI.gd)
	if not parent.has_node("ModernUI"):
		var mu = duplicate()
		mu.name = "ModernUI"
		mu.target = "modern_ui"
		mu.text = "Modern UI"
		mu.hint_tooltip = "A new look for the main screen: your maps as a grid of covers, the picked map with its leaderboard on the left, and a top bar with the pages. Turn it off to go back to the classic menu."
		parent.add_child(mu)
		parent.move_child(mu, cb.get_index() + 1)
		# (only staff, an Owner / Administrator tag, see it)
		mu.visible = Rhythia.is_staff
		Rhythia.connect("modern_ui_changed", self, "_staff_shown", [mu])

func _staff_shown(mu):
	if is_instance_valid(mu):
		mu.visible = Rhythia.is_staff

# "Grid Map List" under Wave Menu: the maps as a grid of tiles (MapGrid.gd),
# switched right away
func _add_map_grid():
	var parent = get_parent()
	if parent == null or parent.has_node("MapGrid"):
		return
	var cb = duplicate()
	cb.name = "MapGrid"
	cb.target = "map_grid"
	cb.text = "Grid Map List"
	cb.hint_tooltip = "Shows your maps as a grid of square covers (like Sound Space Plus's grid menu) instead of a list. Works right away, no restart."
	parent.add_child(cb)
	parent.move_child(cb, get_index() + 1)

# Experimental: "Streaming Mode" (scripts/StreamMode.gd), computers only
func _add_stream_mode():
	var parent = get_parent()
	if parent == null or parent.has_node("StreamMode") or Rhythia.device("mobile") or OS.has_feature("JavaScript") or OS.has_feature("quest"):
		return
	var cb = duplicate()
	cb.name = "StreamMode"
	cb.target = "stream_mode"
	cb.text = "Streaming Mode (Discord / OBS)"
	cb.hint_tooltip = "For when you share your screen or record. The game draws at three quarters of the frame rate your computer manages and leaves the rest of the graphics card free, so the stream and the game stop stuttering each other. It works the limit out by itself (never above your own Max FPS) and lowers it if the stream needs more. Nothing about the game changes, it's only a frame limit. Does nothing with VSync on or in VR."
	parent.add_child(cb)
	var at: Node = parent.get_node_or_null("FrameSmoothingInfo")
	if at == null:
		at = parent.get_node_or_null("FrameSmoothing")
	if at == null:
		at = parent.get_node_or_null("NewSettingsUI")
	parent.move_child(cb, (at.get_index() if at != null else get_index()) + 1)

# Experimental: "Frame Smoothing" (NoteManager._update_draw_clock)
func _add_frame_smoothing():
	var parent = get_parent()
	if parent == null or parent.has_node("FrameSmoothing"):
		return
	var cb = duplicate()
	cb.name = "FrameSmoothing"
	cb.target = "frame_smoothing"
	cb.text = "Frame Smoothing"
	cb.hint_tooltip = "Makes the game look steadier, mostly on phones and headsets. Notes move in even steps matched to the screen's frames instead of following the small differences in when each frame is worked out. And in VR, when a song keeps dropping frames at a high refresh rate (120 or 90 Hz), the next songs run one rate lower, which looks smoother than a high rate that stutters; the higher rate is tried again after a few clean songs. Visual only: hits, misses and the cursor are exactly as before."
	parent.add_child(cb)
	var at: Node = parent.get_node_or_null("NewSettingsUI")
	if at == null:
		at = parent.get_node_or_null("ShowMapRP")
	parent.move_child(cb, (at.get_index() if at != null else get_index()) + 1)
	# how the last song went here (frames a second, late frames, the rate held)
	var info := Label.new()
	info.name = "FrameSmoothingInfo"
	info.autowrap = true
	info.rect_min_size = Vector2(rect_size.x, 0)
	info.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(info)
	parent.move_child(info, cb.get_index() + 1)
	var tm := Timer.new()
	tm.wait_time = 1.0
	tm.autostart = true
	info.add_child(tm)
	tm.connect("timeout", self, "_frame_smoothing_info", [info])
	_frame_smoothing_info(info)

func _frame_smoothing_info(info: Label):
	if not is_instance_valid(info) or (info.text != "" and not info.is_visible_in_tree()):
		return
	var t: String = load("res://scripts/game/SteadyRate.gd").summary()
	info.text = t
	info.visible = t != ""

# Experimental: "New Settings UI" (on by default): SettingsNewUI.gd
func _add_new_settings_ui():
	var parent = get_parent()
	if parent == null or parent.has_node("NewSettingsUI"):
		return
	var cb = duplicate()
	cb.name = "NewSettingsUI"
	cb.target = "new_settings_ui"
	cb.text = "New Settings UI"
	cb.hint_tooltip = "Settings in the look of the Online and Profile pages, on the whole screen: the categories in a list on the left, each group of settings in its own card, and a search box that finds a setting in any category (Ctrl+F). Turn it off for the old settings page. Changing it loads the menu again."
	parent.add_child(cb)
	var at: Node = parent.get_node_or_null("ShowMapRP")
	if at == null:
		at = parent.get_node_or_null("MapGrid")
	parent.move_child(cb, (at.get_index() if at != null else get_index()) + 1)

# Experimental: "Show RP on Maps" (off by default). RP is earned either way
func _add_show_map_rp():
	var parent = get_parent()
	if parent == null or parent.has_node("ShowMapRP"):
		return
	var cb = duplicate()
	cb.name = "ShowMapRP"
	cb.target = "show_map_rp"
	cb.text = "Show RP on Maps"
	cb.hint_tooltip = "Shows on each map how much RP a perfect pass gives at your speed, and your best RP on it. Off: maps only show RP while the servers can't be reached. You earn RP either way, and your total and top plays stay in the Profile tab."
	parent.add_child(cb)
	var at: Node = parent.get_node_or_null("MapGrid")
	parent.move_child(cb, (at.get_index() if at != null else get_index()) + 1)

# Experimental: "10x EXP" (your level), only there for one Discord account (Savia.gd XP_BOOST_DISCORD_ID)
func _add_xp_boost_toggle():
	var parent = get_parent()
	if parent == null or parent.has_node("XpBoost"):
		return
	var cb = duplicate()
	cb.name = "XpBoost"
	cb.target = "xp_boost"
	cb.text = "10x EXP"
	cb.hint_tooltip = "10 times the EXP for your plays (your level; ranked XP stays the same)."
	parent.add_child(cb)

# Phones: "Touch Indicator" (rings under the fingers) goes under this one.
func _add_touch_toggle():
	var parent = get_parent()
	if parent == null or parent.has_node("TouchIndicator"):
		return
	var cb = duplicate()
	cb.name = "TouchIndicator"
	cb.target = "show_touch_indicator"
	cb.text = "Touch Indicator"
	cb.hint_tooltip = "Shows a ring where your fingers touch the screen."
	parent.add_child(cb)
	parent.move_child(cb, get_index() + 1)
	var b := Button.new()
	b.name = "CustomizeTouchIndicator"
	b.text = "Customize Touch Indicator..."
	b.theme = theme
	b.add_font_override("font", get_font("font"))
	b.rect_min_size = Vector2(rect_size.x, 40)
	b.hint_tooltip = "Shape, colors, size, trail, ripple, rainbow and more."
	b.connect("pressed", self, "_open_touch_editor")
	parent.add_child(b)
	parent.move_child(b, cb.get_index() + 1)
	var after: Node = b
	for opt in [
		["mobile_no_delay", "No Touch Delay", "The cursor reacts to your finger right away: every movement is used as it comes, and on iPhone the short hold Chromia's engine puts on each new touch is removed."],
		["mobile_high_hz", "120 Hz", "Draws at your screen's highest refresh rate (120 Hz on ProMotion iPhones and iPads) for smoother movement and less delay. Uses more battery."],
		["mobile_old_cursor", "Old Cursor Movement", "Moves the cursor the way it did before the smoother prediction: led from each touch as it's handled, back on your finger the moment a frame has no new touch, and only with Absolute Mode. Needs No Touch Delay on (off, the cursor simply sits on your finger, as it always did). Takes effect in the next song."],
	]:
		if parent.has_node(opt[0]):
			continue
		var t = duplicate()
		t.name = opt[0]
		t.target = opt[0]
		t.text = opt[1]
		t.hint_tooltip = opt[2]
		parent.add_child(t)
		parent.move_child(t, after.get_index() + 1)
		t.connect("pressed", self, "_mobile_tuning_pressed", [t, opt[0]])
		after = t
	_add_predict_slider(parent)

# A small "Prediction" slider under No Touch Delay: how far ahead of the finger
# the cursor is placed (ms). 0 turns the leading off. Saved on close like the rest.
func _add_predict_slider(parent: Node):
	if parent == null or not parent.has_node("mobile_no_delay") or parent.has_node("TouchPredict"):
		return
	var nd: Node = parent.get_node("mobile_no_delay")
	var row := HBoxContainer.new()
	row.name = "TouchPredict"
	row.rect_min_size = Vector2(rect_size.x, 36)
	row.hint_tooltip = "With No Touch Delay on: how far ahead of your finger the cursor is placed. Higher feels snappier but can overshoot. 0 turns leading off."
	var lbl := Label.new()
	lbl.text = "    Prediction"
	lbl.add_font_override("font", get_font("font"))
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	lbl.valign = Label.VALIGN_CENTER
	row.add_child(lbl)
	var sld := HSlider.new()
	sld.min_value = 0
	sld.max_value = 45
	sld.step = 1
	sld.value = Rhythia.mobile_predict_ms
	sld.rect_min_size = Vector2(150, 0)
	sld.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(sld)
	var val := Label.new()
	val.add_font_override("font", get_font("font"))
	val.valign = Label.VALIGN_CENTER
	val.align = Label.ALIGN_RIGHT
	val.rect_min_size = Vector2(60, 0)
	val.text = "%d ms" % int(Rhythia.mobile_predict_ms)
	row.add_child(val)
	sld.connect("value_changed", self, "_on_predict_changed", [val])
	parent.add_child(row)
	parent.move_child(row, nd.get_index() + 1)

func _on_predict_changed(v: float, val: Label):
	Rhythia.mobile_predict_ms = v
	val.text = "%d ms" % int(v)

# iPhone: say when the app needs reinstalling for these
func _mobile_tuning_pressed(box: CheckBox, key: String):
	if key == "mobile_high_hz":
		# (picked by hand: Frame Smoothing starts over from it)
		load("res://scripts/game/SteadyRate.gd").let_go()
	if not box.pressed or not OS.has_feature("iOS") or key == "mobile_old_cursor":
		return
	yield(get_tree().create_timer(0.3), "timeout")
	if Rhythia.mobile_tuning_status == "":
		Globals.notify(Globals.NOTIFY_WARN, "This needs the latest chromia-ios.ipa installed once (in-app updates can't add it). Until then only part of it works.", "Reinstall needed")
	elif key == "mobile_high_hz" and Rhythia.mobile_tuning_status.find("max 60") != -1:
		Globals.notify(Globals.NOTIFY_INFO, "This screen goes up to 60 Hz.", "120 Hz")

func _open_touch_editor():
	var root := get_tree().root
	if root.has_node("TouchIndicatorEditor"):
		return
	var ed = load("res://scripts/ui/TouchIndicatorEditor.gd").new()
	root.add_child(ed)
