extends Node
## Manager of traps

# Smile Trap(s)
var _speed_label: Label = null
var _smile_applied: Array = []
var _smile_saved_texts: Dictionary = {}
var _smile_material: ShaderMaterial = null
var _smile_saved_albedo: Texture = null
var _smile_tex: Texture = null
var _bounce_layer: CanvasLayer = null
var _bounce_rect: TextureRect = null
var _bounce_pos: Vector2 = Vector2.ZERO
var _bounce_vel: Vector2 = Vector2.ZERO

# Greyscale / Saturation Trap
var _screen_trap_active: bool = false
var _screen_trap_mode: String = ""
var _screen_trap_gen: int = 0
var _screen_layer: CanvasLayer = null
var _screen_rect: ColorRect = null
var _screen_material: ShaderMaterial = null

# Minimap Trap
var _minimap_trap_active: bool = false
var _minimap: Panel = null
var _minimap_zoom: Node = null
var _minimap_controls: Node = null
var _level_scene: Node = null
var _bg_container: Node = null
var _level_container: Node = null
var _saved_minimap_anchors: Array = []
var _saved_minimap_margins: Array = []
var _saved_minimap_style: StyleBox = null
var _saved_minimap_visible: bool = true
var _saved_bg_visible: bool = true
var _saved_level_visible: bool = true
var _minimap_goal_indicators: Array = []

# Moon Trap(s)
var _moon_trap_active: bool = false
var _moon_mesh: MeshInstance = null
var _moon_trap_material: SpatialMaterial = null
var _moon_color_time: float = 0.0
var _moon_trap_permanent: bool = false
var _moon_effect_type: int = 0
var _moon_saved_rotation: Vector3 = Vector3.ZERO

# Checker Scroll Trap
var _checker_trap_active: bool = false
var _checker_saved_velocities: Array = []
var _checker_scroll_speed: float = 0.3

# Taunt Trap
var _taunt_units: Array = []
var _taunt_font: DynamicFont = null
var _taunt_seed: int = 0
var _taunt_seeded: bool = false

const TAUNT_MESSAGES: Array = [
	"OOPS!", "SKILL ISSUE", "WOMP WOMP", "LOL",
	"HAVE FUN!", "NOPE!", "ERROR 404", "ACCESS DENIED",
	"DANGER!", "WARNING!", "SYSTEM ERROR", "MALFUNCTION",
	"NOTICE", "ALERT", "DENIED", "BLOCKED",
	"DONT CHOKE!", "DISTRACTION"
]

# Level-exit cleanup hook
var _exit_hooked_level: Node = null

# Trap HUD
var _trap_hud_layer: CanvasLayer = null
var _trap_hud_box: VBoxContainer = null
var _trap_huds: Dictionary = {}

var trap_config: Dictionary = {}

const traps_grouped_by_cat: Dictionary = {
	"World Distraction": [
		"moon_cycle", "moon_hide","moon_spin"
	],
	"Stage Distraction": [
		"checker_scroll"
	],
	"Screen Distraction": [
		"smile", "grayscale", "oversaturation","minimap"
	],
}

func _process(delta: float):
	# Handle HUD
	var expired: Array = []
	for id in _trap_huds:
		var hud = _trap_huds[id]
		if hud.permanent:
			continue
		hud.remaining -= delta
		if hud.remaining <= 0.0:
			expired.append(id)
		else:
			hud.label.text = "%s %.1fs" % [hud.display, hud.remaining]
	for id in expired:
		_unregister_trap_in_hud(id)
	# Handle traps that need tick logic
	if _moon_trap_active:
		_moon_color_time += delta
		# Color Shift
		if _moon_effect_type == 0 and _moon_trap_material:
			var col = Color.from_hsv(fmod(_moon_color_time * 0.5, 1.0), 1.0, 1.0)
			_moon_trap_material.albedo_color = col
		# Spin
		elif _moon_effect_type == 2 and _moon_mesh and is_instance_valid(_moon_mesh):
			_moon_mesh.rotation.y += delta * 3.0
			_moon_mesh.rotation.x += delta * 6.0
	if _bounce_rect and is_instance_valid(_bounce_rect):
		# DVD-logo screen bouncing for Smile Trap
		_bounce_pos += _bounce_vel * delta
		var bounds = get_viewport().get_visible_rect().size
		var bs = _bounce_rect.rect_size
		if _bounce_pos.x <= 0:
			_bounce_vel.x = abs(_bounce_vel.x)
		elif _bounce_pos.x + bs.x >= bounds.x:
			_bounce_vel.x = -abs(_bounce_vel.x)
		if _bounce_pos.y <= 0:
			_bounce_vel.y = abs(_bounce_vel.y)
		elif _bounce_pos.y + bs.y >= bounds.y:
			_bounce_vel.y = -abs(_bounce_vel.y)
		_bounce_rect.rect_position = _bounce_pos


#region Public API

## Returns whether a trap is enabled by config. "Follow YAML" / "Force on"
## count as enabled; only "Force off" disables. Missing keys default to
## "Follow YAML" (enabled).
func is_trap_enabled(trap_key: String) -> bool:
	return trap_config.get(trap_key, "Follow YAML") != "Force off"


## Returns the raw config tri-state string for a trap, "Follow YAML" if unset.
func get_trap_mode(trap_key: String) -> String:
	return trap_config.get(trap_key, "Follow YAML")


func set_speed_label(node: Label):
	_speed_label = node

func clear_speed_label():
	_speed_label = null
	_disable_screen_filter()
	_screen_trap_active = false
	clear_all_traps()

func deactivate_minimap():
	if _minimap_trap_active:
		_deactivate_minimap_trap()

func trigger_random_trap(duration: float):
	var level = _find_level_scene()
	if level:
		_ensure_exit_hook(level)
	var can_smile = not _smile_candidates().empty() and is_trap_enabled("smile")
	var can_screen_grayscale = is_trap_enabled("grayscale") and _screen_trap_mode != "grayscale"
	var can_screen_oversat = is_trap_enabled("oversaturation") and _screen_trap_mode != "oversaturation"
	var can_minimap = not _minimap_trap_active and _find_level_nodes() and is_trap_enabled("minimap")
	#var can_moon = not _moon_trap_active and _find_moon_mesh() and (
	#	is_trap_enabled("moon_cycle") or
	#	is_trap_enabled("moon_hide") or
	#	is_trap_enabled("moon_spin")
	#)
	#var can_checker = not _checker_trap_active and _find_checker_materials() and is_trap_enabled("checker_scroll")

	var options: Array = []
	if can_smile:
		options.append("smile")
	if can_screen_grayscale:
		options.append("grayscale")
	if can_screen_oversat:
		options.append("oversat")
	if can_minimap:
		options.append("minimap")
	#if can_moon:
	#	options.append("moon")
	#if can_checker:
	#	options.append("checker")

	if options.empty():
		return

	var choice = options[randi() % options.size()]
	if choice == "smile":
		_activate_smile_trap()
	elif choice == "grayscale":
		_activate_screen_trap(duration, "grayscale")
	elif choice == "oversat":
		_activate_screen_trap(duration, "oversaturation")
	elif choice == "minimap":
		_activate_minimap_trap()
	#elif choice == "checker":
	#	_activate_checker_trap(duration)
	#elif choice == "moon"
	#	_activate_moon_trap(randi() % 2 == 0)


func clear_all_traps():
	if _minimap_trap_active:
		_deactivate_minimap_trap()
	if _moon_trap_active:
		_deactivate_moon_trap()
	if _checker_trap_active:
		_deactivate_checker_trap()
	if _taunt_units.size() > 0:
		_clear_taunt_trap()
	_clear_smile_trap()
	_screen_trap_gen += 1
	_screen_trap_active = false
	_screen_trap_mode = ""
	_disable_screen_filter()
	for id in _trap_huds.keys():
		var hud = _trap_huds[id]
		if hud.label and is_instance_valid(hud.label):
			hud.label.queue_free()
	_trap_huds.clear()
	_destroy_trap_hud()
	_release_exit_hook()

## Hook the level scene's exit_level so all traps (incl. timed ones) clear on
## level exit, independent of the SpeedLabel tree_exiting indirection.
func _ensure_exit_hook(level: Node):
	if _exit_hooked_level == level:
		return
	_release_exit_hook()
	if level and level.has_signal("exit_level") and not level.is_connected("exit_level", self, "clear_all_traps"):
		level.connect("exit_level", self, "clear_all_traps")
		_exit_hooked_level = level


func _release_exit_hook():
	if _exit_hooked_level:
		if is_instance_valid(_exit_hooked_level) and _exit_hooked_level.is_connected("exit_level", self, "clear_all_traps"):
			_exit_hooked_level.disconnect("exit_level", self, "clear_all_traps")
		_exit_hooked_level = null

#endregion

#region Smile Trap

func _get_smiley_texture() -> Texture:
	if _smile_tex == null:
		var size := 64
		var img := Image.new()
		img.create(size, size, false, Image.FORMAT_RGBA8)
		img.lock()
		var cx := (size - 1) / 2.0
		var radius := size * 0.45
		var eye_r := size * 0.07
		var shade := Color(0.06, 0.06, 0.06)
		for y in range(size):
			for x in range(size):
				var dx := x - cx
				var dy := y - cx
				if dx * dx + dy * dy <= radius * radius:
					img.set_pixel(x, y, Color(1.0, 0.85, 0.15))
		var eye_x_l := size * 0.33
		var eye_x_r := size * 0.67
		for y in range(size):
			for x in range(size):
				var dx_l := x - eye_x_l
				var dx_r := x - eye_x_r
				var dy := y - size * 0.42
				if dx_l * dx_l + dy * dy <= eye_r * eye_r:
					img.set_pixel(x, y, shade)
				if dx_r * dx_r + dy * dy <= eye_r * eye_r:
					img.set_pixel(x, y, shade)
		for y in range(size):
			for x in range(size):
				var dx := x - cx
				var dy := y - size * 0.52
				var d := sqrt(dx * dx + dy * dy)
				if y >= size * 0.55 and d >= size * 0.28 and d <= size * 0.34:
					img.set_pixel(x, y, shade)
		img.unlock()
		_smile_tex = ImageTexture.new()
		_smile_tex.create_from_image(img)
		_smile_tex.flags = 0
	return _smile_tex


func _find_smile_label(node_name: String):
	var root = get_tree().get_current_scene()
	if not root:
		return null
	return root.find_node(node_name, true, false)


func _get_smile_player_material() -> ShaderMaterial:
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		var mi = p
		if not mi is MeshInstance:
			mi = p.find_node("MeshInstance", true, false)
		if mi == null or not mi is MeshInstance:
			continue
		var mesh = mi.get_mesh()
		if mesh == null:
			continue
		for i in range(mi.get_surface_material_count()):
			var mat = mi.get_surface_material(i)
			if mat is ShaderMaterial:
				return mat
	return null


## Get a list of potential targets to apply the Smile Trap to.
func _smile_candidates() -> Array:
	var out: Array = []
	if not _smile_applied.has("speed") and _speed_label != null and is_instance_valid(_speed_label):
		out.append("speed")
	if not _smile_applied.has("timer_header") and _find_smile_label("TimerHeader") is Label:
		out.append("timer_header")
	if not _smile_applied.has("speed_header") and _find_smile_label("SpeedHeader") is Label and _find_smile_label("Unit") is Label:
		out.append("speed_header")
	if not _smile_applied.has("marble") and _get_smile_player_material() != null:
		out.append("marble")
	if not _smile_applied.has("bouncing") and _find_level_scene() != null:
		out.append("bouncing")
	return out


func _activate_smile_trap():
	var opts = _smile_candidates()
	if opts.empty():
		return
	var pick = opts[randi() % opts.size()]
	_smile_apply_location(pick)
	_smile_applied.append(pick)
	_refresh_smile_hud()
	Log.info("Smile trap applied: %s (stack %d)" % [pick, _smile_applied.size()])


func _smile_apply_location(location: String):
	match location:
		"speed":
			_speed_label.trap_active = true
		"timer_header":
			var label = _find_smile_label("TimerHeader")
			_smile_saved_texts[label] = label.text
			label.text = ":)"
		"speed_header":
			for n in ["SpeedHeader", "Unit"]:
				var label = _find_smile_label(n)
				_smile_saved_texts[label] = label.text
				label.text = ":)"
		"marble":
			var mat = _get_smile_player_material()
			if mat:
				_smile_material = mat
				_smile_saved_albedo = mat.get_shader_param("albedoTex")
				mat.set_shader_param("albedoTex", _get_smiley_texture())
		"bouncing":
			_spawn_bounce_smiley()


func _refresh_smile_hud():
	var count = _smile_applied.size()
	if count <= 0:
		_unregister_trap_in_hud("smile")
		return
	if _trap_huds.has("smile"):
		var hud = _trap_huds["smile"]
		if hud and hud.label and is_instance_valid(hud.label):
			hud.label.text = "Smile x%d" % count
			return
	_register_trap_in_hud("smile", "Smile x%d" % count, 0, Color(1.0, 0.4, 0.7), true)


func _spawn_bounce_smiley():
	if _bounce_layer and is_instance_valid(_bounce_layer):
		return
	_bounce_layer = CanvasLayer.new()
	_bounce_layer.layer = 102
	var size := 64.0
	_bounce_rect = TextureRect.new()
	_bounce_rect.texture = _get_smiley_texture()
	_bounce_rect.rect_size = Vector2(size, size)
	_bounce_rect.rect_min_size = Vector2(size, size)
	var vp = get_viewport().get_visible_rect().size
	_bounce_pos = Vector2(vp.x * 0.25, vp.y * 0.25)
	_bounce_vel = Vector2(rand_range(60, 120), rand_range(60, 120))
	if randi() % 2 == 0:
		_bounce_vel.x = -_bounce_vel.x
	if randi() % 2 == 0:
		_bounce_vel.y = -_bounce_vel.y
	_bounce_rect.rect_position = _bounce_pos
	_bounce_layer.add_child(_bounce_rect)
	get_tree().root.add_child(_bounce_layer)


func _clear_smile_trap():
	_smile_applied.clear()
	if _speed_label and is_instance_valid(_speed_label):
		_speed_label.trap_active = false
	for label in _smile_saved_texts.keys():
		if label and is_instance_valid(label):
			label.text = _smile_saved_texts[label]
	_smile_saved_texts.clear()
	if _smile_material and _smile_saved_albedo:
		_smile_material.set_shader_param("albedoTex", _smile_saved_albedo)
	_smile_material = null
	_smile_saved_albedo = null
	if _bounce_layer and is_instance_valid(_bounce_layer):
		_bounce_layer.queue_free()
	_bounce_layer = null
	_bounce_rect = null
	_unregister_trap_in_hud("smile")

#endregion

#region Screen Filter Traps

func _activate_screen_trap(duration: float, mode: String):
	if _screen_trap_active:
		_unregister_trap_in_hud(_screen_trap_mode)
		_disable_screen_filter()
	_screen_trap_gen += 1
	var gen = _screen_trap_gen
	_screen_trap_active = true
	_screen_trap_mode = mode
	_enable_screen_filter(mode)
	var display = "Grayscale" if mode == "grayscale" else "Oversat"
	var color = Color.white if mode == "grayscale" else Color(1.0, 0.9, 0.2)
	if duration <= 0:
		_register_trap_in_hud(mode, display, 0, color, true)
		Log.info("%s trap activated (permanent)" % mode)
		return
	_register_trap_in_hud(mode, display, duration, color)
	Log.info("%s trap for %.1fs" % [mode, duration])
	yield(get_tree().create_timer(duration), "timeout")
	if gen != _screen_trap_gen:
		return
	_disable_screen_filter()
	_screen_trap_active = false
	_screen_trap_mode = ""
	_unregister_trap_in_hud(mode)
	Log.info("%s trap ended" % mode)


func _enable_screen_filter(mode: String):
	if _screen_layer != null:
		return
	_screen_layer = CanvasLayer.new()
	_screen_layer.layer = 100

	_screen_rect = ColorRect.new()
	_screen_rect.color = Color(0, 0, 0, 0)
	_screen_rect.anchor_right = 1.0
	_screen_rect.anchor_bottom = 1.0
	_screen_rect.margin_right = 0
	_screen_rect.margin_bottom = 0

	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform bool oversat;
uniform float grayscale_strength : hint_range(0.0, 1.0) = 1.0;
uniform float oversat_strength : hint_range(0.0, 5.0) = 3.0;

void fragment() {
	vec4 s = textureLod(SCREEN_TEXTURE, SCREEN_UV, 0.0);
	float l = dot(s.rgb, vec3(0.299, 0.587, 0.114));

	if (oversat) {
		vec3 diff = s.rgb - vec3(l);
		COLOR = vec4(clamp(s.rgb + diff * oversat_strength, 0.0, 1.0), s.a);
	} else {
		COLOR = vec4(mix(s.rgb, vec3(l), grayscale_strength), s.a);
	}
}
"""
	_screen_material = ShaderMaterial.new()
	_screen_material.shader = shader
	_screen_material.set_shader_param("oversat", mode == "oversaturation")
	_screen_material.set_shader_param("grayscale_strength", 1.0)
	_screen_material.set_shader_param("oversat_strength", 3.0)
	_screen_rect.material = _screen_material

	_screen_layer.add_child(_screen_rect)
	get_tree().root.add_child(_screen_layer)


func _disable_screen_filter():
	if _screen_layer == null:
		return
	_screen_layer.queue_free()
	_screen_layer = null
	_screen_rect = null
	_screen_material = null

#endregion

#region Minimap Trap

func _find_level_nodes() -> bool:
	var root = get_tree().get_current_scene()
	if root == null:
		return false
	_minimap = root.find_node("Minimap", true, false)
	_minimap_zoom = root.find_node("MinimapZoomLevel", true, false)
	_minimap_controls = root.find_node("MinimapControls", true, false)
	_bg_container = root.find_node("BackgroundContainer", true, false)
	_level_container = root.find_node("LevelContainer", true, false)
	if _bg_container:
		_level_scene = _bg_container.get_parent()
	return _minimap != null and _bg_container != null and _level_container != null and _level_scene != null


func _activate_minimap_trap():
	if not _find_level_nodes():
		return
	_minimap_trap_active = true
	# Save original minimap state
	_saved_minimap_visible = _minimap.visible
	_saved_minimap_anchors = [_minimap.anchor_left, _minimap.anchor_top, _minimap.anchor_right, _minimap.anchor_bottom]
	_saved_minimap_margins = [_minimap.margin_left, _minimap.margin_top, _minimap.margin_right, _minimap.margin_bottom]
	_saved_minimap_style = _minimap.get_stylebox("panel")
	# Force minimap visible
	_minimap.visible = true
	# Expand minimap to full screen
	_minimap.anchor_left = 0.0
	_minimap.anchor_top = 0.0
	_minimap.anchor_right = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.margin_left = 0
	_minimap.margin_top = 0
	_minimap.margin_right = 0
	_minimap.margin_bottom = 0
	# Clear panel style (transparent background)
	var clear_style = StyleBoxFlat.new()
	clear_style.bg_color = Color(0, 0, 0, 0)
	_minimap.add_stylebox_override("panel", clear_style)
	# Hide 3D viewports
	_saved_bg_visible = _bg_container.visible
	_saved_level_visible = _level_container.visible
	_bg_container.visible = false
	_level_container.visible = false
	# Hide zoom level indicator
	if _minimap_zoom:
		_minimap_zoom.visible = false
	# Block minimap toggle (disconnect signal, keep zoom working)
	if _minimap_controls and _level_scene:
		if _minimap_controls.is_connected("toggle_visible", _level_scene, "toggle_visible"):
			_minimap_controls.disconnect("toggle_visible", _level_scene, "toggle_visible")
	# Add goal indicator on layer 3 (visible to minimap camera)
	var goal = _level_scene.find_node("Goal", true, false)
	if goal:
		_spawn_goal_indicator_in_minimap(goal)
	# Register in HUD
	_register_trap_in_hud("minimap", "Minimap Cam", 0, Color(0.4, 0.8, 1.0), true)
	# Connect deactivation signals
	if goal:
		goal.connect("player_entered", self, "_deactivate_minimap_trap", [], CONNECT_ONESHOT)
	_level_scene.connect("exit_level", self, "_deactivate_minimap_trap", [], CONNECT_ONESHOT)
	Log.info("Minimap trap activated")


func _deactivate_minimap_trap():
	if not _minimap_trap_active:
		return
	_minimap_trap_active = false

	# Restore minimap
	if _minimap and is_instance_valid(_minimap):
		_minimap.anchor_left = _saved_minimap_anchors[0]
		_minimap.anchor_top = _saved_minimap_anchors[1]
		_minimap.anchor_right = _saved_minimap_anchors[2]
		_minimap.anchor_bottom = _saved_minimap_anchors[3]
		_minimap.margin_left = _saved_minimap_margins[0]
		_minimap.margin_top = _saved_minimap_margins[1]
		_minimap.margin_right = _saved_minimap_margins[2]
		_minimap.margin_bottom = _saved_minimap_margins[3]
		if _saved_minimap_style:
			_minimap.add_stylebox_override("panel", _saved_minimap_style)
		_minimap.visible = _saved_minimap_visible

	# Restore 3D viewports
	if _bg_container and is_instance_valid(_bg_container):
		_bg_container.visible = _saved_bg_visible
	if _level_container and is_instance_valid(_level_container):
		_level_container.visible = _saved_level_visible

	# Restore zoom indicator
	if _minimap_zoom and is_instance_valid(_minimap_zoom):
		_minimap_zoom.visible = true

	# Reconnect minimap toggle signal
	if _minimap_controls and is_instance_valid(_minimap_controls) and _level_scene and is_instance_valid(_level_scene):
		if not _minimap_controls.is_connected("toggle_visible", _level_scene, "toggle_visible"):
			_minimap_controls.connect("toggle_visible", _level_scene, "toggle_visible", [[_minimap, _minimap_zoom]])

	# Remove goal indicator
	_remove_goal_indicator_in_minimap()

	# Disconnect signals
	if _level_scene and is_instance_valid(_level_scene):
		if _level_scene.is_connected("exit_level", self, "_deactivate_minimap_trap"):
			_level_scene.disconnect("exit_level", self, "_deactivate_minimap_trap")

	_unregister_trap_in_hud("minimap")

	# Clear refs
	_minimap = null
	_minimap_zoom = null
	_minimap_controls = null
	_level_scene = null
	_bg_container = null
	_level_container = null

	Log.info("Minimap trap deactivated")

## Create a indicator for the goal in the minimap
func _spawn_goal_indicator_in_minimap(goal: Node):
	var col = Color(1.0, 0.0, 0.6)
	var mat = SpatialMaterial.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy = 4.0
	mat.flags_no_depth_test = true

	var half_w := 1.0
	var line_len := half_w * 2.0

	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0

	var dot_a = MeshInstance.new()
	dot_a.mesh = sphere
	dot_a.layers = 4
	dot_a.material_override = mat
	goal.add_child(dot_a)
	dot_a.translation = Vector3(half_w, 0, 0)
	_minimap_goal_indicators.append(dot_a)

	var dot_b = MeshInstance.new()
	dot_b.mesh = sphere
	dot_b.layers = 4
	dot_b.material_override = mat
	goal.add_child(dot_b)
	dot_b.translation = Vector3(-half_w, 0, 0)
	_minimap_goal_indicators.append(dot_b)

	var line_mesh = CubeMesh.new()
	line_mesh.size = Vector3(line_len, 0.15, 0.15)
	var line_inst = MeshInstance.new()
	line_inst.mesh = line_mesh
	line_inst.layers = 4
	line_inst.material_override = mat
	goal.add_child(line_inst)
	_minimap_goal_indicators.append(line_inst)


func _remove_goal_indicator_in_minimap():
	for m in _minimap_goal_indicators:
		if m and is_instance_valid(m):
			m.queue_free()
	_minimap_goal_indicators.clear()

#endregion

#region Moon Trap

## Searches for the existence of a moon object
func _find_moon_mesh() -> bool:
	if _moon_mesh and is_instance_valid(_moon_mesh):
		return true
	var root = get_tree().get_current_scene()
	if not root:
		return false
	var bg_container = root.find_node("BackgroundContainer", true, false)
	if not bg_container:
		return false
	var bg_vp = bg_container.find_node("BackgroundViewport", false, false)
	if not bg_vp:
		return false
	_moon_mesh = bg_vp.find_node("Moon", true, false)
	return _moon_mesh != null


func _activate_moon_trap(permanent: bool):
	if not _find_moon_mesh():
		return
	_moon_trap_active = true
	_moon_trap_permanent = permanent
	_moon_color_time = 0.0

	var enabled_effects: Array = []
	if is_trap_enabled("moon_cycle"):
		enabled_effects.append(0)
	if is_trap_enabled("moon_hide"):
		enabled_effects.append(1)
	if is_trap_enabled("moon_spin"):
		enabled_effects.append(2)
	if enabled_effects.empty():
		enabled_effects.append(0)
	_moon_effect_type = enabled_effects[randi() % enabled_effects.size()]

	match _moon_effect_type:
		0:  # color cycle
			_moon_trap_material = SpatialMaterial.new()
			_moon_trap_material.flags_unshaded = true
			_moon_trap_material.albedo_color = Color.white
			_moon_mesh.material_override = _moon_trap_material
		1:  # hide
			_moon_mesh.visible = false
		2:  # spin
			_moon_saved_rotation = _moon_mesh.rotation

	var display = ["Moon Cycle", "Moon Hide", "Moon Spin"][_moon_effect_type]
	var color = [Color(0.8, 0.3, 1.0), Color(0.4, 0.4, 0.4), Color(1.0, 0.6, 0.0)][_moon_effect_type]

	if permanent:
		_register_trap_in_hud("moon", display, 0, color, true)
		var goal = _find_goal_node()
		if goal:
			goal.connect("player_entered", self, "_on_moon_trap_end", [], CONNECT_ONESHOT)
		var level = _find_level_scene()
		if level:
			level.connect("exit_level", self, "_on_moon_trap_end", [], CONNECT_ONESHOT)
		Log.info("Moon %s trap activated (permanent)" % display)
	else:
		var dur = 10.0 + randf() * 5.0
		_register_trap_in_hud("moon", display, dur, color)
		Log.info("Moon %s trap for %.1fs" % [display, dur])
		yield(get_tree().create_timer(dur), "timeout")
		_deactivate_moon_trap()


func _on_moon_trap_end():
	_deactivate_moon_trap()


func _deactivate_moon_trap():
	if not _moon_trap_active:
		return
	_moon_trap_active = false

	if _moon_mesh and is_instance_valid(_moon_mesh):
		match _moon_effect_type:
			0:  # color cycle
				_moon_mesh.material_override = null
			1:  # hide
				_moon_mesh.visible = true
			2:  # spin
				_moon_mesh.rotation = _moon_saved_rotation
	_moon_mesh = null
	_moon_trap_material = null
	_moon_color_time = 0.0

	_unregister_trap_in_hud("moon")
	Log.info("Moon trap deactivated")

#endregion

#region Checker Scroll Trap

func _find_checker_materials() -> bool:
	if _checker_saved_velocities.size() > 0:
		return true
	var root = get_tree().get_current_scene()
	if not root:
		return false
	var level_vp = root.find_node("LevelViewport", true, false)
	if not level_vp:
		return false
	return _scan_for_checker_materials(level_vp)


func _scan_for_checker_materials(node: Node) -> bool:
	if node is MeshInstance:
		var mi = node as MeshInstance
		for i in mi.get_surface_material_count():
			var mat = mi.get_surface_material(i)
			if mat is ShaderMaterial:
				var tex = mat.get_shader_param("albedoTex")
				if tex != null and tex is Texture and "checker_marble" in tex.resource_path:
					_add_checker_material(mat)
	for child in node.get_children():
		_scan_for_checker_materials(child)
	return _checker_saved_velocities.size() > 0


func _add_checker_material(mat: ShaderMaterial):
	for entry in _checker_saved_velocities:
		if entry["material"] == mat:
			return
	_checker_saved_velocities.append({"material": mat, "velocity": mat.get_shader_param("uv_pan_velocity")})


func _activate_checker_trap(duration: float):
	_checker_trap_active = true
	for entry in _checker_saved_velocities:
		var mat = entry["material"]
		if is_instance_valid(mat):
			mat.set_shader_param("uv_pan_velocity", Vector2(_checker_scroll_speed, _checker_scroll_speed))
	_register_trap_in_hud("checker", "Floor Scroll", duration, Color(0.2, 0.9, 0.4))
	Log.info("Checker scroll trap for %.1fs" % duration)
	yield(get_tree().create_timer(duration), "timeout")
	_deactivate_checker_trap()
	Log.info("Checker scroll trap ended")


func _deactivate_checker_trap():
	if not _checker_trap_active:
		return
	_checker_trap_active = false
	for entry in _checker_saved_velocities:
		var mat = entry["material"]
		if is_instance_valid(mat):
			mat.set_shader_param("uv_pan_velocity", entry["velocity"])
	_checker_saved_velocities.clear()
	_unregister_trap_in_hud("checker")

#endregion

#region Trap HUD

## Creates Trap HUD if not on screen
func _ensure_trap_hud():
	if _trap_hud_layer != null:
		return
	_trap_hud_layer = CanvasLayer.new()
	_trap_hud_layer.layer = 101

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_content_margin_all(4)
	panel.add_stylebox_override("panel", style)
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.margin_left = 4
	panel.margin_top = 0

	_trap_hud_box = VBoxContainer.new()
	_trap_hud_box.rect_min_size = Vector2(80, 0)
	_trap_hud_box.set("custom_constants/separation", 1)

	var header = RichTextLabel.new()
	header.bbcode_enabled = true
	header.bbcode_text = "[center][b]Active Traps[/b][/center]"
	header.scroll_active = false
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_color_override("default_color", Color.white)
	header.rect_min_size = Vector2(0, 16)
	_trap_hud_box.add_child(header)

	panel.add_child(_trap_hud_box)

	_trap_hud_layer.add_child(panel)
	get_tree().root.add_child(_trap_hud_layer)


func _destroy_trap_hud():
	if _trap_hud_layer == null:
		return
	_trap_hud_layer.queue_free()
	_trap_hud_layer = null
	_trap_hud_box = null


## Adds item to Trap HUD.
func _register_trap_in_hud(id: String, display: String, duration: float, color: Color = Color(1, 1, 1), permanent: bool = false):
	_ensure_trap_hud()
	var label = Label.new()
	if permanent:
		label.text = display
	else:
		label.text = "%s %.1fs" % [display, duration]
	label.add_color_override("font_color", color)
	_trap_hud_box.add_child(label)
	_trap_huds[id] = {
		"label": label,
		"display": display,
		"remaining": duration,
		"color": color,
		"permanent": permanent
	}


## Removes item from Trap HUD.
func _unregister_trap_in_hud(id: String):
	if not _trap_huds.has(id):
		return
	var hud = _trap_huds[id]
	if hud.label and is_instance_valid(hud.label):
		hud.label.queue_free()
	_trap_huds.erase(id)
	if _trap_huds.empty():
		_destroy_trap_hud()

#endregion

#region Taunt Trap

func _get_taunt_font() -> DynamicFont:
	if _taunt_font == null:
		_taunt_font = DynamicFont.new()
		_taunt_font.font_data = load("res://gui/Goldman-Bold.ttf")
		_taunt_font.size = 40
		_taunt_font.outline_size = 4
		_taunt_font.outline_color = Color(0.329412, 0.0196078, 0.227451, 1)
		_taunt_font.extra_spacing_char = 10
	return _taunt_font


func _taunt_style_duration(style: int) -> float:
	match style:
		0:
			return 2.25
		_:
			return 2.0


func _activate_taunt_trap(cap: int = 3):
	if _taunt_units.size() >= cap:
		Log.info("Taunt stack full (cap %d), not spawned" % cap)
		return

	var layer = CanvasLayer.new()
	layer.layer = 103

	var label = Label.new()
	label.name = "TauntLabel"
	label.add_font_override("font", _get_taunt_font())
	label.add_color_override("font_color_shadow", Color(0.509804, 0.45098, 0.631373, 1))
	label.add_constant_override("shadow_offset_x", 2)
	label.add_constant_override("shadow_offset_y", 1)
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	if not _taunt_seeded:
		randomize()
		_taunt_seeded = true
	var slot = _taunt_pick_slot()
	label.anchor_left = slot.x
	label.anchor_top = slot.y
	label.anchor_right = slot.x
	label.anchor_bottom = slot.y
	label.visible = false
	layer.add_child(label)

	var player = AnimationPlayer.new()
	player.name = "TauntAnimPlayer"
	layer.add_child(player)

	get_tree().root.add_child(layer)

	var unit = {"layer": layer, "label": label, "player": player, "loop": null}
	_taunt_units.append(unit)
	unit["loop"] = _run_taunt_loop(unit)

	_refresh_taunt_hud()
	Log.info("Taunt spawned (%d active), cap %d" % [_taunt_units.size(), cap])


func _taunt_pick_message() -> String:
	_taunt_seed = (_taunt_seed + 1) % TAUNT_MESSAGES.size()
	return TAUNT_MESSAGES[_taunt_seed]


func _taunt_pick_slot():
	var best = Vector2(rand_range(0.15, 0.85), rand_range(0.1, 0.85))
	var best_dist = -1.0
	for attempt in range(10):
		var cand = Vector2(rand_range(0.15, 0.85), rand_range(0.1, 0.85))
		var min_d = 1e9
		for unit in _taunt_units:
			var l = unit["label"]
			if is_instance_valid(l):
				min_d = min(min_d, cand.distance_to(Vector2(l.anchor_left, l.anchor_top)))
		if min_d > best_dist:
			best_dist = min_d
			best = cand
	return best


func _run_taunt_loop(unit: Dictionary) -> GDScriptFunctionState:
	while true:
		if not is_instance_valid(unit["label"]):
			break
		if not _taunt_units.has(unit):
			break
		var msg = _taunt_pick_message()
		var style = randi() % 3
		_taunt_play_cycle(unit, style, msg)
		var dur = _taunt_style_duration(style)
		yield(get_tree().create_timer(dur + 0.4), "timeout")
	return null


func _taunt_play_cycle(unit: Dictionary, style: int, msg: String):
	var label = unit["label"]
	if label == null or not is_instance_valid(label):
		return
	label.text = msg
	var min_size = label.get_combined_minimum_size()
	label.rect_min_size = min_size
	label.rect_pivot_offset = min_size * 0.5

	var anim = Animation.new()
	anim.length = _taunt_style_duration(style)

	if style == 0:
		_build_taunt_fallout(anim)
	elif style == 1:
		_build_taunt_timeout(anim)
	else:
		_build_taunt_go(anim)

	var player = unit["player"]
	if player != null and is_instance_valid(player):
		player.stop()
		if player.has_animation("taunt"):
			player.remove_animation("taunt")
		player.add_animation("taunt", anim)
		player.play("taunt")
	Log.info("Taunt cycle (style %d): %s" % [style, msg])


## Animate taunt using "FALL OUT!" popup style.
func _build_taunt_fallout(anim: Animation):
	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(0, NodePath("TauntLabel:anchor_top"))
	anim.track_insert_key(0, 0.0, 0.1)
	anim.track_insert_key(0, 0.5, 0.35)

	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(1, NodePath("TauntLabel:anchor_bottom"))
	anim.track_insert_key(1, 0.0, -0.1)
	anim.track_insert_key(1, 0.5, 0.35)

	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(2, NodePath("TauntLabel:rect_rotation"))
	anim.track_insert_key(2, 0.0, 20.0)
	anim.track_insert_key(2, 0.5, -8.0)
	anim.track_insert_key(2, 0.6, 3.0)
	anim.track_insert_key(2, 0.8, -8.0)
	anim.track_insert_key(2, 0.9, -2.0)
	anim.track_insert_key(2, 1.1, -8.0)

	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(3, NodePath("TauntLabel:modulate"))
	anim.track_insert_key(3, 0.0, Color(1, 1, 1, 1))
	anim.track_insert_key(3, 1.75, Color(1, 1, 1, 1))
	anim.track_insert_key(3, 2.25, Color(1, 1, 1, 0))

	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(4, NodePath("TauntLabel:visible"))
	anim.track_set_update_mode(4, Animation.UPDATE_DISCRETE)
	anim.track_insert_key(4, 0.0, true)


## Animate taunt using "TIMEOUT" popup style.
func _build_taunt_timeout(anim: Animation):
	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(0, NodePath("TauntLabel:rect_scale"))
	anim.track_insert_key(0, 0.0, Vector2(0.1, 0.1))
	anim.track_insert_key(0, 0.3, Vector2(1.0, 1.0))

	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(1, NodePath("TauntLabel:rect_rotation"))
	anim.track_insert_key(1, 0.0, 0.0)
	anim.track_insert_key(1, 0.3, 8.0)
	anim.track_insert_key(1, 0.45, -6.0)
	anim.track_insert_key(1, 0.6, 0.0)

	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(2, NodePath("TauntLabel:modulate"))
	anim.track_insert_key(2, 0.0, Color(1, 1, 1, 1))
	anim.track_insert_key(2, 1.5, Color(1, 1, 1, 1))
	anim.track_insert_key(2, 2.0, Color(1, 1, 1, 0))

	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(3, NodePath("TauntLabel:visible"))
	anim.track_set_update_mode(3, Animation.UPDATE_DISCRETE)
	anim.track_insert_key(3, 0.0, true)


## Animate taunt using "GO" popup style.
func _build_taunt_go(anim: Animation):
	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(0, NodePath("TauntLabel:rect_scale"))
	anim.track_insert_key(0, 0.0, Vector2(0.5, 0.5))
	anim.track_insert_key(0, 0.3, Vector2(1.0, 1.0))

	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(1, NodePath("TauntLabel:modulate"))
	anim.track_insert_key(1, 0.0, Color(1, 1, 1, 0))
	anim.track_insert_key(1, 0.3, Color(1, 1, 1, 1))
	anim.track_insert_key(1, 1.7, Color(1, 1, 1, 1))
	anim.track_insert_key(1, 2.0, Color(1, 1, 1, 0))

	anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(2, NodePath("TauntLabel:visible"))
	anim.track_set_update_mode(2, Animation.UPDATE_DISCRETE)
	anim.track_insert_key(2, 0.0, true)


func _clear_taunt_trap():
	for unit in _taunt_units:
		if unit["player"] != null and is_instance_valid(unit["player"]):
			unit["player"].stop()
		if unit["layer"] != null and is_instance_valid(unit["layer"]):
			unit["layer"].queue_free()
	_taunt_units.clear()
	_unregister_trap_in_hud("taunt")
	Log.info("Taunt trap cleared")


func _refresh_taunt_hud():
	var count = _taunt_units.size()
	if count <= 0:
		_unregister_trap_in_hud("taunt")
		return
	if _trap_huds.has("taunt"):
		var hud = _trap_huds["taunt"]
		if hud and hud.label and is_instance_valid(hud.label):
			hud.label.text = "Taunt x%d" % count
			return
	_register_trap_in_hud("taunt", "Taunt x%d" % count, 0, Color(1.0, 0.8, 0.3), true)

#endregion

#region General

func _find_goal_node() -> Node:
	var level = _find_level_scene()
	if level:
		return level.find_node("Goal", true, false)
	return null

func _find_level_scene() -> Node:
	var root = get_tree().get_current_scene()
	if not root:
		return null
	var bg = root.find_node("BackgroundContainer", true, false)
	if bg:
		return bg.get_parent()
	return null

#endregion