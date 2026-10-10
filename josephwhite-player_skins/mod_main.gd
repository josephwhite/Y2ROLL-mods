extends Node


var _default_modulate := Color(1, 1, 1, 1)
var _default_metal_modulate := Color(1, 1, 1, 1)
var _default_texture = null
var _defaults_cached := false


func _ready():
	_get_cached_defaults()
	get_tree().connect("node_added", self, "_on_node_added")


func _get_cached_defaults():
	var default_mat = load("res://player/player_metal_mat.tres")
	if not default_mat or not default_mat is ShaderMaterial:
		return
	_default_modulate = default_mat.get_shader_param("modulate_color")
	_default_metal_modulate = default_mat.get_shader_param("metal_modulate_color")
	_default_texture = default_mat.get_shader_param("albedoTex")
	_defaults_cached = true


func _on_node_added(node: Node):
	if not _defaults_cached:
		return
	if node.is_in_group("player"):
		call_deferred("_apply_skin", node)


func _apply_skin(player: Node):
	var config = _load_custom_config()
	if config.empty():
		return
	var skin_type = config.get("skin_type", "Default")
	# Don't need player skin to hide it
	if skin_type == "Invisible":
		player.visible = false
		return
	player.visible = true
	# Get player material
	var mesh = player.get_mesh()
	if not mesh:
		return
	var material = mesh.get_surface_material(0)
	if not material or not material is ShaderMaterial:
		return
	match skin_type:
		"Default":
			material.set_shader_param("albedoTex", _default_texture)
			material.set_shader_param("modulate_color", _default_modulate)
			material.set_shader_param("metal_modulate_color", _default_metal_modulate)
			return
		"Solid Color":
			material.set_shader_param("albedoTex", _default_texture)
			var color = _parse_color_hex(str(config.get("color", "#ffffff")))
			material.set_shader_param("modulate_color", color)
			material.set_shader_param("metal_modulate_color", color)
			return
		"Custom Image":
			var path = config.get("custom_texture_path", "")
			# Fallback to default skin if custom img path is empty/invalid
			if path.strip_edges() == "":
				material.set_shader_param("albedoTex", _default_texture)
				material.set_shader_param("modulate_color", _default_modulate)
				return
			var img = Image.new()
			var err = img.load(path)
			if err != OK:
				material.set_shader_param("albedoTex", _default_texture)
				material.set_shader_param("modulate_color", _default_modulate)
				return
			# Filtering
			var use_filtering = config.get("use_filtering", false)
			var flags = Texture.FLAG_REPEAT | Texture.FLAG_MIPMAPS
			if use_filtering:
				flags |= Texture.FLAG_FILTER
			# Setting the player skin
			var tex = ImageTexture.new()
			tex.create_from_image(img, flags)
			material.set_shader_param("albedoTex", tex)
			material.set_shader_param("modulate_color", Color(1, 1, 1, 1))
			material.set_shader_param("metal_modulate_color", Color(1, 1, 1, 1))
			return


func _load_custom_config() -> Dictionary:
	var mod_id = "josephwhite-player_skins"
	var path = "user://configs/" + mod_id + "/settings.json"
	var file = File.new()
	if file.file_exists(path) and file.open(path, File.READ) == OK:
		var text = file.get_as_text()
		file.close()
		var parsed = JSON.parse(text)
		if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
			return parsed.result

	var default_config = ModLoaderConfig.get_default_config(mod_id)
	if default_config and default_config.data:
		return default_config.data.duplicate(true)

	var defaults = _build_defaults_from_schema(mod_id)
	if defaults.size() > 0:
		return defaults

	return {}


## Convert RGB/ARGB/RGBA hex to Color.
func _parse_color_hex(raw: String) -> Color:
	var hex_str = raw.strip_edges()
	if hex_str.begins_with("#"):
		hex_str = hex_str.substr(1)
	if hex_str.length() == 6:
		return Color("#" + hex_str)
	if hex_str.length() == 8:
		return Color("#" + hex_str.substr(6, 2) + hex_str.substr(0, 6))
	return Color(1, 1, 1, 1)


func _build_defaults_from_schema(mod_id: String) -> Dictionary:
	var mod_data = ModLoaderMod.get_mod_data(mod_id)
	if not mod_data or not mod_data.manifest:
		return {}
	var extra = mod_data.manifest.extra
	if not extra:
		return {}
	var schema = extra.get("godot", {}).get("config_schema", {})
	var properties = schema.get("properties", {})
	var defaults = {}
	for prop_name in properties:
		var prop = properties[prop_name]
		if prop.has("default"):
			defaults[prop_name] = prop["default"]
		elif prop.has("enum") and prop["enum"].size() > 0:
			defaults[prop_name] = prop["enum"][0]
	return defaults
