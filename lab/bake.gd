extends Node
# bake.gd — render a sky shader into a 6-face strip (one image, left to right:
# +X, -X, +Y, -Y, +Z, -Z), ready to split, DXT1-compress and assemble into a
# Vega Strike `<name>_light.cube`.
#
# Usage (offscreen, no display needed):
#   xvfb-run -a godot-mono --path <lab> res://bake.tscn -- \
#       --shader res://bake_dir.gdshader --res 512 --out /tmp/bake.png

func _ready() -> void:
	var res := 512
	var out := "user://bake.png"
	var shader_path := "res://bake_dir.gdshader"

	var args := OS.get_cmdline_user_args()
	var params := {}
	var i := 0
	while i < args.size():
		match args[i]:
			"--res":
				res = int(args[i + 1]); i += 2
			"--out":
				out = args[i + 1]; i += 2
			"--shader":
				shader_path = args[i + 1]; i += 2
			"--param":
				# --param uStarDensity=0.8 (float) or --param uNebulaColorA=0.18,0.42,0.30 (colour)
				var kv := String(args[i + 1]).split("=")
				if kv.size() == 2:
					var v := String(kv[1])
					if v.contains(","):
						var c := v.split(",")
						if c.size() >= 3:
							params[kv[0]] = Color(float(c[0]), float(c[1]), float(c[2]), 1.0)
					else:
						params[kv[0]] = float(v)
				i += 2
			_:
				i += 1

	var vp := SubViewport.new()
	vp.size = Vector2i(res * 6, res)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var rect := ColorRect.new()
	rect.size = Vector2(res * 6, res)
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	# tell the shader its pixel footprint: a face spans -1..1 over `res` pixels
	mat.set_shader_parameter("uPxPerDir", 2.0 / float(res))
	for k in params:
		mat.set_shader_parameter(k, params[k])
	rect.material = mat
	vp.add_child(rect)

	# let the viewport render a couple of frames before reading it back
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := vp.get_texture().get_image()
	var err := img.save_png(out)
	if err != OK:
		printerr("save_png failed: ", err)
	print("baked %dx%d -> %s (%s)" % [res * 6, res, out, shader_path])
	get_tree().quit()
