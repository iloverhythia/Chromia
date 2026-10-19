extends Spatial

func _ready():
	var env = $WorldEnvironment.environment
	var pano = Globals.imageLoader.load_if_exists("user://panobg")
	if pano:
		var sky:PanoramaSky = env.background_sky
		sky.panorama = pano
	else:
		var img = Globals.imageLoader.load_if_exists("user://custombg")
		var col: Color = Rhythia.custombg_color
		if img: $V/R.material.set_shader_param("tex",img)
		elif col != Color(1, 1, 1):
			# no image + a color picked: a solid color background
			var white = Image.new()
			white.create(1, 1, false, Image.FORMAT_RGB8)
			white.fill(Color(1, 1, 1))
			var wt = ImageTexture.new()
			wt.create_from_image(white, 0)
			$V/R.material.set_shader_param("tex", wt)
		$V/R.material.set_shader_param("tint", col)
	# Shaders
	if Rhythia.glow > 0:
		env.glow_enabled = true
		env.glow_intensity = Rhythia.glow
		env.glow_strength = 1
		env.glow_bloom = Rhythia.bloom
		env.glow_blend_mode = 1
		env.glow_hdr_scale = 1.72
		env.glow_high_quality = true
		env.glow_bicubic_upscale = true
