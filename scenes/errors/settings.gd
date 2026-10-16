extends ColorRect

func _ready():
	Engine.target_fps = 30
	$Info.text = \
	 \
	 \
		"-- settings load error --\nsavia version: %s\nplatform: %s\nerror code: %s" % [
		ProjectSettings.get_setting("application/config/version"),
		OS.get_name(),
		Rhythia.errornum,
	]
	if OS.has_feature("mobile"):
		$Info.get("custom_fonts/font").size = 28
	if ProjectSettings.get_setting("application/config/discord_rpc"):
		if OS.has_feature("HTML5"): return
		var activity = Discord.Activity.new()
		activity.set_type(Discord.ActivityType.Playing)
		activity.set_details("experiencing a cattr moment")
		activity.set_state("(settings error %s)" % Rhythia.errornum)

		var assets = activity.get_assets()
		assets.set_large_image("icon-bg")
		assets.set_small_image("error")

		var result = yield(Discord.activity_manager.update_activity(activity), "result").result
		if result != Discord.Result.Ok:
			push_error(str(result))
