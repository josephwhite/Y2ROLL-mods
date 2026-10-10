extends Node

var _options_menu: Control = null


func _ready():
	get_tree().connect("node_added", self, "_on_node_added")
	ModLoaderMod.install_script_extension("res://mods-unpacked/josephwhite-mod_manager/extensions/options_menu_fix.gd")


func _on_node_added(node: Node):
	if node.has_method("initialize") and node.get_parent() and node.get_parent().name == "MainMenu":
		call_deferred("_inject_mod_manager_button", node)


func _inject_mod_manager_button(node: Control):
	if not node.has_node("%Buttons"):
		return
	_options_menu = node
	var main_menu = node.get_parent()
	if main_menu == null or main_menu.has_node("ModManagerPanel"):
		return
	var buttons = node.get_node("%Buttons")

	var separator = Label.new()
	separator.text = "MODS"
	separator.align = 1
	separator.add_font_override("font", load("res://gui/font_pause-menu_title.tres"))
	separator.rect_min_size = Vector2(0, 30)
	buttons.add_child(separator)

	var btn = load("res://gui/options-menu/options_menu_item_toggle.tscn").instance()
	var title = btn.get_node("%Title")
	title.text = "Mod Manager"
	var toggle = btn.get_node("%Toggle")
	toggle.pressed = false

	var focus_target = _get_focus_target(btn)
	if focus_target == null:
		return

	buttons.add_child(btn)
	# index must be read AFTER add_child: before it, this pointed at the
	# separator Label one slot up, which the compiled nav walk then probed.
	var menu_index = buttons.get_child_count() - 1

	focus_target.connect("focus_entered", title, "set", ["custom_colors/font_color", Color("#ffdd00")])
	focus_target.connect("focus_entered", node, "set", ["focused_menu_index", menu_index])
	focus_target.connect("focus_exited", title, "set", ["custom_colors/font_color", Color.white])

	var sfx_player = node.get_node_or_null("MenuSFXPlayer")
	if sfx_player:
		focus_target.connect("focus_exited", sfx_player, "on_control_focus_exited", [focus_target])
		focus_target.connect("pressed", sfx_player, "on_button_pressed")

	var desc_ticker = node.get_node_or_null("%DescriptionTicker")
	if desc_ticker:
		focus_target.connect("focus_entered", desc_ticker, "update_text", ["Open the mod manager to enable/disable mods and configure settings."])

	var panel_scene_path = ModLoaderMod.get_unpacked_dir().plus_file("josephwhite-mod_manager/scenes/mod_manager_panel.tscn")
	var panel_scene = load(panel_scene_path)
	if not panel_scene:
		return

	var mod_panel = panel_scene.instance()
	main_menu.add_child(mod_panel)
	Log.info("Mod Manager injected into OptionsMenu.", {
		"buttons_count": buttons.get_child_count(),
		"separator_index": menu_index - 1,
		"menu_index": menu_index,
		"panel_parent": main_menu.name,
	})

	focus_target.connect("pressed", self, "_on_mod_manager_pressed", [mod_panel, toggle])
	node.connect("menu_closed", self, "_on_menu_closed", [mod_panel])
	node.connect("visibility_changed", self, "_on_options_visibility", [node])


func _on_options_visibility(options_menu: Control):
	if not options_menu or not options_menu.visible:
		return
	_clamp_focused_index(options_menu, "visibility_changed")


func _clamp_focused_index(options_menu: Control, source: String):
	if not options_menu or not options_menu.has_node("%Buttons"):
		return
	var buttons = options_menu.get_node("%Buttons")
	var count = buttons.get_child_count()
	if count <= 0:
		return
	var before = options_menu.get("focused_menu_index")
	var clamped = int(clamp(before, 0, count - 1))
	if clamped != before:
		options_menu.set("focused_menu_index", clamped)
		Log.info("Options focused index clamped.", {"source": source, "in": before, "count": count, "out": clamped})


func _on_mod_manager_pressed(panel: Control, toggle: CheckBox):
	if panel:
		panel.open()
		toggle.pressed = false


func _on_menu_closed(panel: Control):
	if panel:
		panel.close()


func _get_focus_target(item: Control) -> Control:
	for i in item.get_children():
		if i.focus_mode == Control.FOCUS_ALL:
			return i
	return null
