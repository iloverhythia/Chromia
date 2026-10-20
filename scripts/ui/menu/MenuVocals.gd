extends Node

# Settings > Video & Audio > "Menu Music Lyrics": turns the vocals of the menu
# music (song previews and the menu song) down, down to an instrumental at 0%.
#
# Vocals are almost always mixed in the centre, so the centre of the stereo
# mix is turned down and the sides (instruments panned left/right) stay:
#   out = side + lyrics * centre
# done on the "MenuVocals" bus with Godot's stereo enhance (it scales the side
# by 1/lyrics) followed by an amplify by lyrics. The bass is in the centre too,
# so a second player plays the same music through "MenuBass" (mono, low-pass)
# at (1 - lyrics), which puts the low end back.
#
# Songs mixed in mono have no sides, so at 0% only their bass is left.

const VOCAL_BUS := "MenuVocals"
const BASS_BUS := "MenuBass"
const BASS_CUTOFF_HZ := 170.0

var _players: Array = [] # [main AudioStreamPlayer, twin AudioStreamPlayer]

static func _bus(name: String) -> int:
	return AudioServer.get_bus_index(name)

static func ensure_buses():
	if _bus(VOCAL_BUS) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, VOCAL_BUS)
		AudioServer.set_bus_send(i, "Music")
		AudioServer.add_bus_effect(i, AudioEffectStereoEnhance.new())
		AudioServer.add_bus_effect(i, AudioEffectAmplify.new())
	if _bus(BASS_BUS) == -1:
		AudioServer.add_bus()
		var j := AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, BASS_BUS)
		AudioServer.set_bus_send(j, "Music")
		var mono := AudioEffectStereoEnhance.new()
		mono.pan_pullout = 0.0 # left = right = centre
		AudioServer.add_bus_effect(j, mono)
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = BASS_CUTOFF_HZ
		lp.resonance = 0.5
		AudioServer.add_bus_effect(j, lp)
	apply(Rhythia.menu_lyric_volume)

static func apply(lyrics: float):
	var vb := _bus(VOCAL_BUS)
	var bb := _bus(BASS_BUS)
	if vb == -1 or bb == -1:
		return
	lyrics = clamp(lyrics, 0.0, 1.0)
	var on := lyrics < 0.995
	AudioServer.set_bus_effect_enabled(vb, 0, on)
	AudioServer.set_bus_effect_enabled(vb, 1, on)
	if on:
		var v: float = max(lyrics, 0.02)
		var enhance: AudioEffectStereoEnhance = AudioServer.get_bus_effect(vb, 0)
		enhance.pan_pullout = 1.0 / v
		var amp: AudioEffectAmplify = AudioServer.get_bus_effect(vb, 1)
		amp.volume_db = linear2db(v)
	AudioServer.set_bus_volume_db(bb, linear2db(1.0 - lyrics) if on else -80.0)
	AudioServer.set_bus_mute(bb, not on)

# Routes `player` through the vocal filter and gives it a bass twin.
func add_player(player: AudioStreamPlayer):
	if player == null:
		return
	ensure_buses()
	player.bus = VOCAL_BUS
	var twin := AudioStreamPlayer.new()
	twin.bus = BASS_BUS
	twin.pause_mode = player.pause_mode
	add_child(twin)
	_players.append([player, twin])

func _ready():
	pause_mode = PAUSE_MODE_PROCESS

func _process(_d):
	var on: bool = Rhythia.menu_lyric_volume < 0.995
	for pair in _players:
		var main: AudioStreamPlayer = pair[0]
		var twin: AudioStreamPlayer = pair[1]
		if not is_instance_valid(main):
			continue
		if not on or not main.playing or main.stream == null:
			if twin.playing:
				twin.stop()
			continue
		twin.volume_db = main.volume_db
		twin.pitch_scale = main.pitch_scale
		if twin.stream != main.stream:
			twin.stream = main.stream
			twin.play(main.get_playback_position())
		elif not twin.playing:
			twin.play(main.get_playback_position())
		elif abs(twin.get_playback_position() - main.get_playback_position()) > 0.15:
			twin.seek(main.get_playback_position()) # main was seeked
