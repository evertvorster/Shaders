extends Node3D
# lab.gd — ONE lab for every sky shader: pick one, fly it, tune it, reload it, bake it.
#
# It replaces the per-shader labs (starfield_lab, nebula_lab, ridged_lab,
# volumetric_starfield_lab, nebula_and_stars_lab, compositor_lab), which were six copies of
# the same script with one constant changed.
#
#   shader picker   choose any generated .gdshader; the panel REBUILDS from that shader's
#                   own hint_range annotations, and each shader keeps its own settings
#   R               rebuild from source (runs Tools/build_all.py in the repo), copy the
#                   generated files in, and swap the shader live -- so the loop is
#                   edit the .frag -> press R -> see it, with no relaunch
#   B               bake setup screen: name, resolution, destination, then bake a cubemap
#                   through vs-backgrounds' bake-sky.sh (split -> DXT1 -> assemble)
#
# Controls: drag (any button) looks, WASD flies, Q/E down/up, arrows look (fallback),
# I inverts the drag, P/L save/load the current shader's sliders, Esc quits.
#
# Headless:
#   --capture <png> [--yaw D] [--pitch D] [--cam x,y,z] [--shader res://...]
#   --bench N        [--param name=value ...]
#   --bake [--name N --res R --outdir D --shader res://...]

# Portable: this lab lives at <repo>/lab, so res:// IS <repo>/lab and the repo root is its
# which can be overridden with the VS_BACKGROUNDS environment variable.
# NOTE the rstrip: globalize_path("res://") ends in a slash, so without it get_base_dir()
# returns the LAB directory itself and every derived path is off by one level.
var LAB := ProjectSettings.globalize_path("res://").rstrip("/")
var REPO := LAB.get_base_dir()

# label, lab file, repo source, fly speed. The repo source is what R rebuilds.
# A volume you fly through wants a much higher speed than a distant dome.
const SHADERS := [
	{"label": "star field (dome)",        "dest": "starfield.gdshader",
	 "src": "Space/Starfield/starfield.frag",                        "speed":  8.0},
	{"label": "nebula (gyroid clouds)",   "dest": "gyroid-clouds.gdshader",
	 "src": "Space/Nebula/gyroid-clouds.frag",                       "speed": 20.0},
	{"label": "nebula (ridged filaments)","dest": "ridged-clouds.gdshader",
	 "src": "Space/Nebula/ridged-clouds.frag",                       "speed": 20.0},
	{"label": "star volume (fly through)","dest": "volumetric_starfield.gdshader",
	 "src": "Space/volumetric_starfield/volumetric_starfield.frag",  "speed": 30.0},
	{"label": "scene (nebula + stars)",   "dest": "nebula-and-stars.gdshader",
	 "src": "Space/Scenes/nebula-and-stars.frag",                    "speed": 20.0},
	{"label": "sky compositor",           "dest": "sky.gdshader",
	 "src": "Space/Sky/sky.frag",                                    "speed": 20.0},
	{"label": "milky way",                "dest": "milkyway.gdshader",
	 "src": "Space/MilkyWay/milkyway.frag",                          "speed": 20.0},
	{"label": "galaxy (parked)",          "dest": "analytic-galaxy.gdshader",
	 "src": "Space/Galaxy/analytic-galaxy.frag",                     "speed": 20.0},
]

const LOOK_SPEED := 1.6
const RES_CHOICES := [512, 1024, 2048, 4096]

# Host plumbing is a REAL uniform with a hint_range, so a naive "every hinted uniform is a
# knob" rule turns it into a slider -- one that fights the host every frame, and whose value
# then gets passed to the baker, overriding the baker's own uPxPerDir and failing its
# uniformity guard.
const PLUMBING := ["uPxPerDir", "uCamPos", "uBakePos", "uSteps"]

var _invert := true
var _current := 0
var _move_speed := 20.0

var mat: ShaderMaterial
var cam: Camera3D
var _sphere: MeshInstance3D

var _panel: Control
var _picker: OptionButton
var _name_edit: LineEdit
var _out_edit: LineEdit
var _res_picker: OptionButton
var _log: Label
var _sliders := {}
var _colours := {}
var _specs := []
var _px_label: Label
var _fps_label: Label

func _ready() -> void:
	_sphere = $Sphere
	mat = _sphere.mesh.material
	cam = $Camera3D
	_build_ui()

	# --shader res://... (or --shader <index>) picks the startup shader
	var args := OS.get_cmdline_user_args()
	var want := ""
	for i in args.size():
		if args[i] == "--shader" and i + 1 < args.size():
			want = String(args[i + 1])
	if want != "":
		for i in SHADERS.size():
			if SHADERS[i]["dest"] == want.get_file():
				_current = i
		# Any OTHER .gdshader loads too: the list is a convenience, not a whitelist. Without
		# this, naming an unknown shader silently bench/looked at whatever was current --
		# which produced a "baseline" measurement that was really the starfield again.
		if SHADERS[_current]["dest"] != want.get_file():
			SHADERS.append({"label": want.get_file(), "dest": want.get_file(),
			                "src": "", "speed": _move_speed})
			_current = SHADERS.size() - 1
	_select_shader(_current)

	get_viewport().size_changed.connect(_update_px_per_dir)
	_update_px_per_dir()
	_handle_cli()

# ------------------------------------------------------------------ shader switching

func _select_shader(idx: int, keep_values := false) -> void:
	_current = idx
	var spec: Dictionary = SHADERS[idx]
	_move_speed = float(spec["speed"])

	var sh: Shader = load("res://" + String(spec["dest"]))
	if sh == null:
		_push_log("could not load %s" % spec["dest"])
		return
	mat.shader = sh
	if _picker != null:
		_picker.selected = idx

	_read_shader_uniforms()          # from the .gdshader on disk -> the panel follows the shader
	_rebuild_panel()
	if not keep_values:
		_load_settings()
	_push_log("shader: %s   (%d knobs)" % [spec["label"], _sliders.size() + _colours.size()])

func _reload_shader() -> void:
	# Rebuild from source, copy the generated files in, and swap live.
	# build_all.py regenerates every host file AND writes this lab's copies of them, so there
	# is nothing to copy here and nothing to drift.
	var out := []
	var rc := OS.execute("bash", ["-c", "cd '%s' && python3 Tools/build_all.py" % REPO], out, true)
	if rc != 0:
		_push_log("REBUILD FAILED (rc %d):\n%s" % [rc, "\n".join(out).substr(0, 400)])
		return
	# CACHE_MODE_REPLACE is what makes the reload real: without it Godot hands back the
	# cached Shader and nothing changes on screen.
	var vals := _current_values()
	var spec: Dictionary = SHADERS[_current]
	mat.shader = ResourceLoader.load("res://" + String(spec["dest"]), "", ResourceLoader.CACHE_MODE_REPLACE)
	_read_shader_uniforms()
	_rebuild_panel()
	_apply_values(vals)
	_push_log("reloaded %s  (rebuilt from source)" % spec["dest"])

func _read_shader_uniforms() -> void:
	# Slider specs straight from the shader's own hint_range annotations, so the panel can
	# never hold a stale set: add a knob to a layer, press R, it appears.
	_specs = []
	var path := "res://" + String(SHADERS[_current]["dest"])
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_push_log("cannot read %s" % path)
		return
	var re := RegEx.new()
	re.compile("uniform\\s+float\\s+(\\w+)\\s*:\\s*hint_range\\(([^)]*)\\)\\s*=\\s*([-+0-9.eE]+)\\s*;")
	for m in re.search_all(f.get_as_text()):
		var nm := m.get_string(1)
		if nm in PLUMBING:
			continue        # host plumbing, not a knob: setting it from a slider fights the host
		var p := m.get_string(2).split(",")
		_specs.append([nm, p[0].to_float(), p[1].to_float(), p[2].to_float(), m.get_string(3).to_float()])

func _current_values() -> Dictionary:
	var d := {}
	for n in _sliders: d[n] = _sliders[n].value
	for n in _colours: d[n] = _colours[n].color
	return d

func _apply_values(d: Dictionary) -> void:
	for n in d:
		if _sliders.has(n):   _sliders[n].value = float(d[n])
		elif _colours.has(n): _colours[n].color = d[n]

# ------------------------------------------------------------------ baking

func _on_bake() -> void:
	var name := _name_edit.text.strip_edges()
	if name == "":
		_push_log("bake needs a name")
		return
	var res: int = RES_CHOICES[_res_picker.selected]
	var outdir := _out_edit.text.strip_edges()
	var bake_shader := "res://" + String(SHADERS[_current]["dest"]).replace(".gdshader", ".bake.gdshader")

	# The bake pipeline ships WITH this repo (Tools/), so a clone can bake.
	var args := ["Tools/bake-sky.sh", name, "--res", str(res),
	             "--shader", bake_shader, "--outdir", outdir]
	for n in _sliders:
		args.append("--param")
		args.append("%s=%s" % [n, str(_sliders[n].value)])
	for n in _colours:
		var c: Color = _colours[n].color
		args.append("--param")
		args.append("%s=%.4f,%.4f,%.4f" % [n, c.r, c.g, c.b])

	var cmd := "cd '%s' && ./%s" % [REPO, " ".join(args)]
	_push_log("baking %s at %d from %s\n$ %s" % [name, res, bake_shader, cmd])
	var out := []
	# bake-sky.sh drives Godot itself, so it needs xvfb when there is no display. The lab
	# sets it up already, so a nested call is fine here.
	var rc := OS.execute("bash", ["-c", cmd], out, true)
	var tail := "\n".join(out).substr(-600)
	if rc == 0:
		_push_log("BAKED -> %s/%s_light.cube\n%s" % [outdir, name, tail])
	else:
		_push_log("BAKE FAILED (rc %d)\n%s" % [rc, tail])

func _push_log(t: String) -> void:
	print(t)
	if _log != null:
		_log.text = t

# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	# Same shape as the labs this replaces (panel -> VBox, widgets directly), which is known
	# to lay out. A ScrollContainer here collapsed the whole panel to nothing.
	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = PanelContainer.new()
	_panel.position = Vector2(10, 10)
	layer.add_child(_panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "Sky shader lab"
	box.add_child(title)

	_picker = OptionButton.new()
	_picker.focus_mode = Control.FOCUS_NONE        # keep arrow keys for looking
	for i in SHADERS.size():
		_picker.add_item(String(SHADERS[i]["label"]), i)
	_picker.item_selected.connect(func(i: int) -> void: _select_shader(i))
	box.add_child(_picker)

	var reload := Button.new()
	reload.text = "Reload from source  (R)"
	reload.focus_mode = Control.FOCUS_NONE
	reload.pressed.connect(_reload_shader)
	box.add_child(reload)

	box.add_child(HSeparator.new())

	# ---- bake setup screen ----
	var bake_title := Label.new()
	bake_title.text = "Bake cubemap  (B)"
	box.add_child(bake_title)

	var name_row := HBoxContainer.new(); box.add_child(name_row)
	var nl := Label.new(); nl.text = "name"; nl.custom_minimum_size = Vector2(90, 0); name_row.add_child(nl)
	_name_edit = LineEdit.new(); _name_edit.text = "shader_test"
	_name_edit.custom_minimum_size = Vector2(300, 0); name_row.add_child(_name_edit)

	var out_row := HBoxContainer.new(); box.add_child(out_row)
	var ol := Label.new(); ol.text = "destination"; ol.custom_minimum_size = Vector2(90, 0); out_row.add_child(ol)
	_out_edit = LineEdit.new(); _out_edit.text = "/home/evert/bake"
	_out_edit.custom_minimum_size = Vector2(300, 0); out_row.add_child(_out_edit)

	var res_row := HBoxContainer.new(); box.add_child(res_row)
	var rl := Label.new(); rl.text = "face size"; rl.custom_minimum_size = Vector2(90, 0); res_row.add_child(rl)
	_res_picker = OptionButton.new(); _res_picker.focus_mode = Control.FOCUS_NONE
	for r in RES_CHOICES: _res_picker.add_item(str(r))
	_res_picker.selected = 1                              # 1024
	res_row.add_child(_res_picker)

	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.custom_minimum_size = Vector2(400, 40)
	box.add_child(_log)

	box.add_child(HSeparator.new())

	# ---- the knob panel itself (filled by _rebuild_panel) ----
	_knob_box = VBoxContainer.new()
	box.add_child(_knob_box)

	box.add_child(HSeparator.new())
	_px_label = Label.new(); box.add_child(_px_label)
	_fps_label = Label.new(); box.add_child(_fps_label)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(400, 0)
	hint.text = ("drag: look   WASD: fly   Q/E: down/up   arrows: look\n"
	             + "I: invert   P/L: save/load   R: reload from source\n"
	             + "B: bake   Esc: quit")
	box.add_child(hint)

var _knob_box: VBoxContainer

func panel_add(c: Control) -> void:
	_panel.add_child(c)

func _rebuild_panel() -> void:
	for c in _knob_box.get_children():
		c.queue_free()
	_sliders = {}
	_colours = {}

	for spec in _specs:
		var name: String = spec[0]
		var row := HBoxContainer.new()
		_knob_box.add_child(row)
		var lab := Label.new(); lab.text = name; lab.custom_minimum_size = Vector2(150, 0)
		row.add_child(lab)
		var s := HSlider.new(); s.min_value = spec[1]; s.max_value = spec[2]; s.step = spec[3]
		s.custom_minimum_size = Vector2(170, 0)
		s.value = _default_or(name, spec[4])   # the shader's DECLARED default, not the minimum
		row.add_child(s)
		var v := Label.new(); v.custom_minimum_size = Vector2(56, 0)
		v.text = "%.3f" % s.value
		row.add_child(v)
		s.value_changed.connect(func(x: float) -> void: mat.set_shader_parameter(name, x); v.text = "%.3f" % x)
		mat.set_shader_parameter(name, s.value)
		_sliders[name] = s

	for name in _colour_names():
		var row := HBoxContainer.new()
		_knob_box.add_child(row)
		var lab := Label.new(); lab.text = name; lab.custom_minimum_size = Vector2(150, 0)
		row.add_child(lab)
		var pick := ColorPickerButton.new(); pick.custom_minimum_size = Vector2(90, 0)
		var cur = mat.get_shader_parameter(name)
		if cur is Color: pick.color = cur
		elif cur is Vector3: pick.color = Color(cur.x, cur.y, cur.z)
		row.add_child(pick)
		pick.color_changed.connect(func(c: Color) -> void:
			mat.set_shader_parameter(name, Vector3(c.r, c.g, c.b)))
		_colours[name] = pick

func _colour_names() -> Array:
	var out: Array = []
	var f := FileAccess.open("res://" + String(SHADERS[_current]["dest"]), FileAccess.READ)
	if f == null: return out
	var re := RegEx.new()
	re.compile("uniform\\s+vec3\\s+(\\w+)\\s*:\\s*source_color")
	for m in re.search_all(f.get_as_text()):
		if not PLUMBING.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out

func _default_or(name: String, fallback: float) -> float:
	var cur = mat.get_shader_parameter(name)
	return float(cur) if cur != null else fallback

# ------------------------------------------------------------------ settings

func _settings_path() -> String:
	return "user://lab_%s_settings.json" % String(SHADERS[_current]["dest"]).replace(".gdshader", "")

func _save_settings() -> void:
	var data := {}
	for n in _sliders: data[n] = _sliders[n].value
	for n in _colours:
		var c: Color = _colours[n].color
		data[n] = [c.r, c.g, c.b]
	var f := FileAccess.open(_settings_path(), FileAccess.WRITE)
	if f == null:
		_push_log("could not write %s" % _settings_path()); return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	_push_log("saved %s" % ProjectSettings.globalize_path(_settings_path()))

func _load_settings() -> void:
	var p := _settings_path()
	if not FileAccess.file_exists(p):
		return
	var f := FileAccess.open(p, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	_apply_values(data)

# ------------------------------------------------------------------ per-frame + input

func _update_px_per_dir() -> void:
	var h: float = max(get_viewport().get_visible_rect().size.y, 1.0)
	var px: float = 2.0 * tan(deg_to_rad(cam.fov * 0.5)) / h
	mat.set_shader_parameter("uPxPerDir", px)
	if _px_label != null:
		_px_label.text = "uPxPerDir %.6f   viewport %d px" % [px, int(h)]

func _process(delta: float) -> void:
	var s := -1.0 if _invert else 1.0
	var yaw_in := 0.0
	var pitch_in := 0.0
	if Input.is_key_pressed(KEY_LEFT):  yaw_in   += 1.0
	if Input.is_key_pressed(KEY_RIGHT): yaw_in   -= 1.0
	if Input.is_key_pressed(KEY_UP):    pitch_in += 1.0
	if Input.is_key_pressed(KEY_DOWN):  pitch_in -= 1.0
	cam.rotation.y += s * yaw_in * LOOK_SPEED * delta
	cam.rotation.x = clamp(cam.rotation.x + s * pitch_in * LOOK_SPEED * delta, -PI / 2.0, PI / 2.0)

	var move := Vector3.ZERO
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_W): move += fwd
	if Input.is_key_pressed(KEY_S): move -= fwd
	if Input.is_key_pressed(KEY_D): move += right
	if Input.is_key_pressed(KEY_A): move -= right
	if Input.is_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move -= Vector3.UP
	if move.length_squared() > 0.0:
		cam.global_position += move.normalized() * _move_speed * delta   # unbounded volumes

	_sphere.global_position = cam.global_position
	mat.set_shader_parameter("uCamPos", cam.global_position)

	if _fps_label != null:
		var fps: int = Engine.get_frames_per_second()
		_fps_label.text = "%d fps (%.2f ms)  speed %.0f" % [fps, 1000.0 / float(max(fps, 1)), _move_speed]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: get_tree().quit()
			KEY_I: _invert = not _invert
			KEY_P: _save_settings()
			KEY_L: _load_settings()
			KEY_R: _reload_shader()
			KEY_B: _on_bake()
	if event is InputEventMouseMotion and (
			Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or
			Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or
			Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)):
		if _panel != null and _panel.get_global_rect().has_point(event.position):
			return
		var s := -1.0 if _invert else 1.0
		cam.rotation.y += s * event.relative.x * 0.004
		cam.rotation.x = clamp(cam.rotation.x + s * event.relative.y * 0.004, -PI / 2.0, PI / 2.0)

# ------------------------------------------------------------------ headless

func _handle_cli() -> void:
	var args := OS.get_cmdline_user_args()
	var capture := ""
	var bench := 0
	var do_bake := false
	var yaw := 0.0
	var pitch := 0.0
	var cam_pos := Vector3.ZERO
	var i := 0
	while i < args.size():
		match args[i]:
			"--capture": capture = args[i + 1]; i += 2
			"--bench":   bench = int(args[i + 1]); i += 2
			"--bake":    do_bake = true; i += 1
			"--name":    _name_edit.text = String(args[i + 1]); i += 2
			"--res":     _res_picker.selected = max(RES_CHOICES.find(int(args[i + 1])), 0); i += 2
			"--outdir":  _out_edit.text = String(args[i + 1]); i += 2
			"--yaw":     yaw = float(args[i + 1]); i += 2
			"--pitch":   pitch = float(args[i + 1]); i += 2
			"--cam":
				var c := String(args[i + 1]).split(",")
				if c.size() >= 3: cam_pos = Vector3(float(c[0]), float(c[1]), float(c[2]))
				i += 2
			"--param":
				var kv := String(args[i + 1]).split("=")
				if kv.size() == 2:
					if kv[1].contains(","):
						var cc := kv[1].split(",")
						mat.set_shader_parameter(kv[0], Vector3(cc[0].to_float(), cc[1].to_float(), cc[2].to_float()))
					else:
						mat.set_shader_parameter(kv[0], kv[1].to_float())
				i += 2
			_: i += 1

	cam.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
	if cam_pos != Vector3.ZERO:
		cam.global_position = cam_pos

	if do_bake:
		_on_bake()
		get_tree().quit()
		return

	if bench > 0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var t0 := Time.get_ticks_msec()
		for n in bench:
			RenderingServer.force_draw(false)
		var ms := maxi(Time.get_ticks_msec() - t0, 1)
		print("BENCH %d frames in %d ms -> %.1f fps (%.2f ms/frame)" % [
			bench, ms, 1000.0 * bench / ms, float(ms) / bench])
		get_tree().quit()
		return

	if capture != "":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(capture)
		if err != OK:
			printerr("save_png failed: ", err)
		print("captured -> ", capture)
		get_tree().quit()
