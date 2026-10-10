extends Control


signal panel_closed

onready var _mod_list_container: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/Buttons
onready var _config_container: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ConfigView
onready var _scroll_container: ScrollContainer = $Panel/VBoxContainer/ScrollContainer
onready var _back_button: Button = $Panel/VBoxContainer/Footer/BackButton
onready var _status_label: Label = $Panel/VBoxContainer/Footer/StatusLabel
onready var _title_label: Label = $Panel/VBoxContainer/Title

var _changes_made: bool = false
var _config_dirty: bool = false
var _confirm_request: String = ""
var _confirm_row: Control = null
var _current_view: String = "list"
var _selected_mod_id: String = ""
var _display_settings: Dictionary = {
	"show_version": true,
	"show_author": true,
	"ui_font_scale": 100,
	"mod_name_column_width": 180
}
var _base_body_font: Font = null
var _base_title_font: Font = null
var _body_font: Font = null
var _title_font: Font = null
var _title_base: String = ""

var _color_popup: PopupPanel = null
var _color_target: Button = null
var _color_pre_popup: Color = Color(1, 1, 1, 1)
var _color_r: HSlider = null
var _color_g: HSlider = null
var _color_b: HSlider = null
var _color_a: HSlider = null
var _color_hex: LineEdit = null
var _color_swatch: ColorRect = null
var _color_current: Color = Color(1, 1, 1, 1)


func _ready():
	_back_button.connect("pressed", self, "_on_back_pressed")
	var base_theme = load("res://gui/theme_pause-menu.tres")
	var new_theme = base_theme.duplicate()
	new_theme.set_font("font", "TooltipLabel", load("res://gui/font_pause-menu_author-name.tres"))
	self.theme = new_theme
	_base_body_font = new_theme.get_font("font", "Label")
	if _base_body_font == null:
		_base_body_font = new_theme.get_font("font", "Button")
	_base_title_font = load("res://gui/font_pause-menu_title.tres")
	_load_display_settings()
	_recalc_ui_fonts()
	_apply_ui_fonts(self)


func _unhandled_input(event: InputEvent):
	if visible and _confirm_row == null and event.is_action_pressed("ui_cancel"):
		get_tree().set_input_as_handled()
		close()


func open():
	visible = true
	_changes_made = false
	_config_dirty = false
	_confirm_request = ""
	_hide_confirm()
	_load_display_settings()
	_recalc_ui_fonts()
	_current_view = "list"
	_selected_mod_id = ""
	_populate_mod_list()
	_back_button.call_deferred("grab_focus")


func close():
	visible = false
	_hide_confirm()
	_confirm_request = ""
	if _color_popup and _color_popup.visible:
		_color_popup.hide()
	emit_signal("panel_closed")


func _show_list_view():
	_current_view = "list"
	if _config_container.get_parent() == _scroll_container:
		_scroll_container.remove_child(_config_container)
	if _mod_list_container.get_parent() != _scroll_container:
		_scroll_container.add_child(_mod_list_container)
	_mod_list_container.visible = true
	_config_container.visible = false


func _show_config_view():
	_current_view = "config"
	if _mod_list_container.get_parent() == _scroll_container:
		_scroll_container.remove_child(_mod_list_container)
	if _config_container.get_parent() != _scroll_container:
		_scroll_container.add_child(_config_container)
	_config_container.visible = true
	_mod_list_container.visible = false


func _populate_mod_list():
	for child in _mod_list_container.get_children():
		_mod_list_container.remove_child(child)
		child.free()

	_show_list_view()
	_config_dirty = false
	_title_base = "MOD MANAGER"
	_update_title()
	_update_status()

	var all_mods = ModLoaderMod.get_mod_data_all()
	var current_profile = ModLoaderUserProfile.get_current()
	var mod_ids = all_mods.keys()
	mod_ids.sort()

	if mod_ids.size() == 0:
		var empty_label = Label.new()
		empty_label.text = "No mods installed."
		empty_label.align = 1
		_mod_list_container.add_child(empty_label)
		return

	var first_focusable: Control = null

	for mod_id in mod_ids:
		var mod_data = all_mods[mod_id]
		var entry = _create_mod_entry(mod_id, mod_data, current_profile)
		_mod_list_container.add_child(entry)
		if first_focusable == null:
			first_focusable = _find_first_focusable(entry)

	_add_separator()

	if first_focusable:
		_back_button.focus_neighbor_bottom = first_focusable.get_path()
		first_focusable.focus_neighbor_top = _back_button.get_path()

	_apply_ui_fonts(_mod_list_container)


func _find_first_focusable(node: Control) -> Control:
	if node.focus_mode == Control.FOCUS_ALL:
		return node
	for child in node.get_children():
		if child is Control:
			var result = _find_first_focusable(child)
			if result:
				return result
	return null


func _create_mod_entry(mod_id: String, mod_data, profile) -> Control:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_text = mod_data.manifest.name if mod_data.manifest.name else mod_id
	# Optional: add mod info to entry
	if _display_settings.get("show_version", true) and mod_data.manifest.version_number != "":
		name_text += " v" + mod_data.manifest.version_number
	if _display_settings.get("show_author", true) and mod_data.manifest.authors.size() > 0:
		name_text += " by " + mod_data.manifest.authors[0]

	var name_label = Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap = true
	name_label.rect_min_size = Vector2(float(_display_settings.get("mod_name_column_width", 180)), 0)
	row.add_child(name_label)

	var info_btn = Button.new()
	info_btn.text = "Info"
	info_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	info_btn.focus_mode = Control.FOCUS_ALL
	info_btn.connect("pressed", self, "_on_info_pressed", [mod_id])
	row.add_child(info_btn)

	var is_active = profile.mod_list.has(mod_id) and profile.mod_list[mod_id].get("is_active", true)

	var toggle = CheckBox.new()
	toggle.pressed = true if mod_id == "josephwhite-mod_manager" else is_active
	toggle.disabled = mod_id == "josephwhite-mod_manager"
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.connect("toggled", self, "_on_mod_toggled", [mod_id])
	row.add_child(toggle)

	return row


func _on_mod_toggled(pressed: bool, mod_id: String):
	if pressed:
		ModLoaderUserProfile.enable_mod(mod_id)
	else:
		ModLoaderUserProfile.disable_mod(mod_id)
	_changes_made = true
	_update_status()


func _on_info_pressed(mod_id: String):
	_selected_mod_id = mod_id
	_current_view = "config"
	_config_dirty = false
	_confirm_request = ""
	_hide_confirm()
	_show_config_view()
	_title_base = "MOD INFO"
	_update_title()
	_populate_config(mod_id)
	_back_button.call_deferred("grab_focus")


func _populate_config(mod_id: String):
	for child in _config_container.get_children():
		_config_container.remove_child(child)
		child.free()

	var mod_data = ModLoaderMod.get_mod_data(mod_id)
	var manifest = mod_data.manifest

	var info_box = VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_config_container.add_child(info_box)

	var name_label = Label.new()
	name_label.text = manifest.name if manifest.name else mod_id
	name_label.align = 1
	info_box.add_child(name_label)

	var meta_parts = []
	if manifest.version_number != "":
		meta_parts.append("v" + manifest.version_number)
	if manifest.authors.size() > 0:
		meta_parts.append("by " + manifest.authors[0])
	if meta_parts.size() > 0:
		var meta_label = Label.new()
		meta_label.text = " ".join(meta_parts)
		meta_label.align = 1
		meta_label.add_color_override("font_color", Color(0.6, 0.6, 0.6))
		info_box.add_child(meta_label)

	if manifest.description != "":
		var desc_label = Label.new()
		desc_label.text = manifest.description
		desc_label.autowrap = true
		desc_label.add_color_override("font_color", Color(0.7, 0.7, 0.7))
		info_box.add_child(desc_label)

	var schema = ModLoaderConfig.get_config_schema(mod_id)
	var properties = schema.get("properties", {})

	if properties.size() > 0:
		_add_separator()

		var data = _load_config_data(mod_id, properties)

		var prop_keys = properties.keys()
		prop_keys.sort()

		for prop_name in prop_keys:
			var prop = properties[prop_name]
			if prop.get("hidden", false) == true:
				continue
			var prop_type = prop.get("type", "string")

			if prop.has("properties") or prop_type == "object":
				var warn = Label.new()
				warn.text = prop_name + ": Nested config options are not supported."
				warn.add_color_override("font_color", Color(0.9, 0.9, 0.5))
				warn.rect_min_size = Vector2(0, 16)
				_config_container.add_child(warn)
				continue

			var current_value = data.get(prop_name, prop.get("default", null))

			if prop_type == "string" and prop.get("format", "").to_lower() == "color":
				var row = _create_config_color(prop_name, prop, current_value if current_value != null else prop.get("default", "#ffffff"))
				_config_container.add_child(row)
			elif prop.has("enum"):
				var row = _create_config_enum(prop_name, prop, current_value if current_value != null else prop.get("default", ""))
				_config_container.add_child(row)
			else:
				match prop_type:
					"boolean":
						var row = _create_config_toggle(prop_name, prop, current_value if current_value != null else prop.get("default", false))
						_config_container.add_child(row)
					"number":
						var row = _create_config_slider(prop_name, prop, current_value if current_value != null else prop.get("default", 0.0))
						_config_container.add_child(row)
					"integer":
						var row = _create_config_slider(prop_name, prop, current_value if current_value != null else prop.get("default", 0), true)
						_config_container.add_child(row)
					_:
						var row = _create_config_text_input(prop_name, prop, str(current_value) if current_value != null else str(prop.get("default", "")))
						_config_container.add_child(row)

		_add_separator()

		var save_row = HBoxContainer.new()

		var save_btn = Button.new()
		save_btn.text = "Save Config"
		save_btn.connect("pressed", self, "_on_save_config", [mod_id])
		save_row.add_child(save_btn)

		var reset_btn = Button.new()
		reset_btn.text = "Reset to Defaults"
		reset_btn.focus_mode = Control.FOCUS_ALL
		reset_btn.connect("pressed", self, "_on_reset_config_pressed", [mod_id])
		save_row.add_child(reset_btn)

		save_row.add_child(HSeparator.new())

		_config_container.add_child(save_row)
	else:
		var no_config_label = Label.new()
		no_config_label.text = "No configuration options."
		no_config_label.add_color_override("font_color", Color(0.6, 0.6, 0.6))
		no_config_label.rect_min_size = Vector2(0, 16)
		_config_container.add_child(no_config_label)

	_apply_ui_fonts(_config_container)


func _create_config_toggle(prop_name: String, prop: Dictionary, current_value: bool) -> Control:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title = Label.new()
	title.text = prop.get("title", prop_name)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	row.add_child(title)

	var toggle = CheckBox.new()
	toggle.pressed = current_value
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.set_meta("prop_name", prop_name)
	toggle.set_meta("prop_type", "boolean")
	toggle.connect("toggled", self, "_on_config_toggle_changed")
	row.add_child(toggle)
	row.add_child(_make_reset_button(toggle, prop.get("default", false)))

	return row


func _create_config_slider(prop_name: String, prop: Dictionary, current_value, is_integer: bool = false) -> Control:
	var step = 0.01
	var max_value = 1.0
	if is_integer:
		step = 1.0
		max_value = 100
	if prop.has("multipleOf"):
		step = prop["multipleOf"]
	if prop.has("maximum"):
		max_value = prop["maximum"]
	var min_value = prop.get("minimum", 0)
	if prop.has("exclusiveMinimum"):
		min_value = max(float(min_value), float(prop["exclusiveMinimum"]) + step)
	if prop.has("exclusiveMaximum"):
		max_value = min(float(max_value), float(prop["exclusiveMaximum"]) - step)
	if min_value >= max_value:
		max_value = min_value + step
	var format_str = "%.0f" if is_integer else "%.2f"

	var row = VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title_row = HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_row)

	var title = Label.new()
	title.text = prop.get("title", prop_name)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title_row.add_child(title)

	var value_label = Label.new()
	value_label.text = format_str % current_value
	value_label.rect_min_size = Vector2(40, 0)
	value_label.align = 2
	title_row.add_child(value_label)

	var slider = HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = current_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	slider.set_meta("prop_name", prop_name)
	slider.set_meta("prop_type", "integer" if is_integer else "number")
	slider.set_meta("value_label", value_label)
	slider.connect("value_changed", self, "_on_slider_value_changed", [value_label, step, format_str])
	row.add_child(slider)

	title_row.add_child(_make_reset_button(slider, prop.get("default", 0.0)))

	return row


func _on_slider_value_changed(value: float, label: Label, step: float, format_str: String):
	label.text = format_str % stepify(value, step)
	_set_config_dirty(true)


func _create_config_color(prop_name: String, prop: Dictionary, current_value: String) -> Control:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title = Label.new()
	title.text = prop.get("title", prop_name)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	row.add_child(title)

	var col = _parse_hex_color(str(current_value))
	var btn = Button.new()
	btn.text = "#" + _color_to_hex(col)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.focus_mode = Control.FOCUS_ALL
	btn.set_meta("prop_name", prop_name)
	btn.set_meta("prop_type", "color")
	btn.set_meta("color_value", col)
	btn.connect("pressed", self, "_on_color_button_pressed", [btn])
	row.add_child(btn)
	row.add_child(_make_reset_button(btn, prop.get("default", "#ffffff")))

	return row


func _on_color_button_pressed(btn: Button):
	if _color_popup == null:
		_build_color_popup()
	_color_target = btn
	_color_current = btn.get_meta("color_value")
	_color_pre_popup = _color_current
	_color_r.value = _color_current.r * 255.0
	_color_g.value = _color_current.g * 255.0
	_color_b.value = _color_current.b * 255.0
	_color_a.value = _color_current.a * 100.0
	_color_hex.text = _color_to_hex(_color_current)
	_color_swatch.color = _color_current
	var ps = _color_popup.get_combined_minimum_size()
	ps.x = max(ps.x, 170)
	_color_popup.popup_centered(ps)


func _build_color_popup():
	_color_popup = PopupPanel.new()
	_color_popup.rect_min_size = Vector2(170, 150)
	add_child(_color_popup)

	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_popup.add_child(box)

	_color_swatch = ColorRect.new()
	_color_swatch.rect_min_size = Vector2(0, 18)
	_color_swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_color_swatch)

	_color_r = _make_color_slider(box, "R")
	_color_g = _make_color_slider(box, "G")
	_color_b = _make_color_slider(box, "B")
	_color_a = _make_color_slider(box, "A", 100)

	_color_hex = LineEdit.new()
	_color_hex.focus_mode = Control.FOCUS_ALL
	_color_hex.rect_min_size = Vector2(140, 0)
	_color_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_hex.connect("text_entered", self, "_on_color_hex_entered")
	_color_hex.connect("focus_exited", self, "_on_color_hex_entered")
	box.add_child(_color_hex)

	var done = Button.new()
	done.text = "Done"
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.connect("pressed", self, "_on_color_done_pressed")
	box.add_child(done)

	var cancel = Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.connect("pressed", self, "_on_color_cancel_pressed")
	box.add_child(cancel)

	_apply_ui_fonts(_color_popup)


func _make_color_slider(parent: Control, label_text: String, max_value: float = 255) -> HSlider:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	var label = Label.new()
	label.text = label_text
	label.rect_min_size = Vector2(14, 0)
	row.add_child(label)

	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = max_value
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	slider.connect("value_changed", self, "_on_color_slider_changed")
	row.add_child(slider)

	return slider


func _on_color_slider_changed(_value: float):
	_color_current = Color(_color_r.value / 255.0, _color_g.value / 255.0, _color_b.value / 255.0, _color_a.value / 100.0)
	_update_color_popup_ui()
	_set_config_dirty(true)


func _on_color_hex_entered(_text: String = ""):
	_color_current = _parse_hex_color(_color_hex.text)
	_color_r.value = _color_current.r * 255.0
	_color_g.value = _color_current.g * 255.0
	_color_b.value = _color_current.b * 255.0
	_color_a.value = _color_current.a * 100.0
	_update_color_popup_ui()
	_set_config_dirty(true)


func _update_color_popup_ui():
	_color_swatch.color = _color_current
	_color_hex.text = _color_to_hex(_color_current)
	if _color_target:
		_color_target.set_meta("color_value", _color_current)
		_color_target.text = "#" + _color_to_hex(_color_current)


func _on_color_done_pressed():
	_color_popup.hide()


func _on_color_cancel_pressed():
	_color_current = _color_pre_popup
	_update_color_popup_ui()
	_color_popup.hide()


func _color_to_hex(c: Color) -> String:
	var s = c.to_html(true)
	return s.substr(2, 6) + s.substr(0, 2)


func _parse_hex_color(raw: String) -> Color:
	var hex_str = raw.strip_edges()
	if hex_str.begins_with("#"):
		hex_str = hex_str.substr(1)
	if hex_str.length() == 6:
		return Color("#" + hex_str)
	if hex_str.length() == 8:
		return Color("#" + hex_str.substr(6, 2) + hex_str.substr(0, 6))
	return Color(1, 1, 1, 1)


func _create_config_enum(prop_name: String, prop: Dictionary, current_value: String) -> Control:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title = Label.new()
	title.text = prop.get("title", prop_name)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	row.add_child(title)

	var enum_values = prop.get("enum", [])
	var cycle_btn = Button.new()
	cycle_btn.text = current_value if current_value in enum_values else enum_values[0]
	cycle_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	cycle_btn.focus_mode = Control.FOCUS_ALL
	cycle_btn.set_meta("prop_name", prop_name)
	cycle_btn.set_meta("prop_type", "enum")
	cycle_btn.set_meta("enum_values", enum_values)
	cycle_btn.set_meta("current_index", enum_values.find(current_value) if current_value in enum_values else 0)
	cycle_btn.connect("pressed", self, "_on_enum_cycle", [cycle_btn])
	row.add_child(cycle_btn)
	row.add_child(_make_reset_button(cycle_btn, prop.get("default", enum_values[0] if enum_values.size() > 0 else "")))

	return row


func _create_config_text_input(prop_name: String, prop: Dictionary, current_value: String) -> Control:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title = Label.new()
	title.text = prop.get("title", prop_name)
	title.rect_min_size = Vector2(80, 0)
	row.add_child(title)

	var input = LineEdit.new()
	input.text = current_value
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.focus_mode = Control.FOCUS_ALL
	input.expand_to_text_length = true
	input.set_meta("prop_name", prop_name)
	input.set_meta("prop_type", "string")
	input.connect("text_changed", self, "_on_config_text_changed")
	row.add_child(input)
	row.add_child(_make_reset_button(input, prop.get("default", "")))

	return row


func _make_reset_button(control: Control, default_value) -> Button:
	var btn = Button.new()
	btn.text = "Reset"
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.focus_mode = Control.FOCUS_ALL
	btn.connect("pressed", self, "_on_control_reset_pressed", [control, default_value])
	return btn


func _on_control_reset_pressed(control: Control, default_value):
	if control is CheckBox:
		var value = default_value
		if value is String:
			value = value.to_lower() == "true"
		control.pressed = bool(value)
	elif control is HSlider:
		control.value = float(default_value)
	elif control is LineEdit:
		control.text = str(default_value)
	elif control.has_meta("prop_type"):
		var prop_type = control.get_meta("prop_type")
		if prop_type == "enum":
			var values = control.get_meta("enum_values")
			var idx = values.find(str(default_value))
			if idx == -1:
				idx = 0
			control.set_meta("current_index", idx)
			control.text = values[idx]
		elif prop_type == "color":
			var col = _parse_hex_color(str(default_value))
			control.set_meta("color_value", col)
			control.text = "#" + _color_to_hex(col)
	_set_config_dirty(true)
	_update_status()


func _on_config_toggle_changed(_pressed: bool):
	_set_config_dirty(true)


func _on_config_text_changed(_new_text: String):
	_set_config_dirty(true)


func _on_enum_cycle(btn: Button):
	var values = btn.get_meta("enum_values")
	var idx = btn.get_meta("current_index")
	idx = (idx + 1) % values.size()
	btn.set_meta("current_index", idx)
	btn.text = values[idx]
	_set_config_dirty(true)


func _on_save_config(mod_id: String):
	var new_data = {}

	for child in _get_all_config_controls():
		if child.has_meta("prop_name"):
			var prop_name = child.get_meta("prop_name")
			var prop_type = child.get_meta("prop_type")
			match prop_type:
				"boolean":
					new_data[prop_name] = child.pressed
				"number":
					new_data[prop_name] = child.value
				"integer":
					new_data[prop_name] = int(child.value)
				"color":
					new_data[prop_name] = _color_to_hex(child.get_meta("color_value"))
				"enum":
					var values = child.get_meta("enum_values")
					var idx = child.get_meta("current_index")
					new_data[prop_name] = values[idx]
				"string":
					new_data[prop_name] = child.text

	var schema = ModLoaderConfig.get_config_schema(mod_id)
	var properties = schema.get("properties", {})
	var current_data = _load_config_data(mod_id, properties)
	for prop_name in properties:
		if properties[prop_name].get("hidden", false) and not new_data.has(prop_name):
			new_data[prop_name] = current_data.get(prop_name, properties[prop_name].get("default", null))

	var save_path = _get_config_path(mod_id)
	var dir = Directory.new()
	var dir_path = save_path.get_base_dir()
	if not dir.dir_exists(dir_path):
		dir.make_dir_recursive(dir_path)

	var file = File.new()
	if file.open(save_path, File.WRITE) == OK:
		file.store_string(JSON.print(new_data, "\t"))
		file.close()
		_set_config_dirty(false)
		_hide_confirm()
		_confirm_request = ""
		_changes_made = true
		_status_label.text = "Config saved."


func _get_all_config_controls() -> Array:
	var controls = []
	for child in _config_container.get_children():
		if child is HBoxContainer or child is VBoxContainer:
			for sub in child.get_children():
				if sub is CheckBox or sub is HSlider or sub is Button or sub is LineEdit:
					if sub.has_meta("prop_name"):
						controls.append(sub)
	return controls


func _get_schema_defaults(properties: Dictionary) -> Dictionary:
	var defaults = {}
	for prop_name in properties:
		var prop = properties[prop_name]
		if prop.has("default"):
			defaults[prop_name] = prop["default"]
		elif prop.has("enum") and prop["enum"].size() > 0:
			defaults[prop_name] = prop["enum"][0]
	return defaults


func _on_reset_config_pressed(mod_id: String):
	var prompt = "Reset all config of %s to defaults?" % mod_id
	_show_confirm("Reset all config to defaults?", "Reset", "reset_all")


func _do_reset_config(mod_id: String):
	var schema = ModLoaderConfig.get_config_schema(mod_id)
	var properties = schema.get("properties", {})
	var defaults = _get_schema_defaults(properties)
	var save_path = _get_config_path(mod_id)
	var dir = Directory.new()
	var dir_path = save_path.get_base_dir()
	if not dir.dir_exists(dir_path):
		dir.make_dir_recursive(dir_path)

	var file = File.new()
	if file.open(save_path, File.WRITE) == OK:
		file.store_string(JSON.print(defaults, "\t"))
		file.close()
	_changes_made = true
	_set_config_dirty(false)
	_populate_config(mod_id)
	_status_label.text = "Config reset to defaults."


func _show_confirm(prompt_text: String, confirm_text: String, action: String, target: Control = null):
	_hide_confirm()
	_confirm_request = action
	_confirm_row = HBoxContainer.new()
	_confirm_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label = Label.new()
	label.text = prompt_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap = true
	_confirm_row.add_child(label)

	var confirm_btn = Button.new()
	confirm_btn.text = confirm_text
	confirm_btn.focus_mode = Control.FOCUS_ALL
	confirm_btn.connect("pressed", self, "_on_confirm_discard", [], Object.CONNECT_DEFERRED)
	_confirm_row.add_child(confirm_btn)

	var keep_btn = Button.new()
	keep_btn.text = "Cancel"
	keep_btn.focus_mode = Control.FOCUS_ALL
	keep_btn.connect("pressed", self, "_on_confirm_keep", [], Object.CONNECT_DEFERRED)
	_confirm_row.add_child(keep_btn)

	var container = target if target else _config_container
	container.add_child(_confirm_row)
	if confirm_btn.is_inside_tree():
		confirm_btn.call_deferred("grab_focus")


func _on_confirm_discard():
	var action = _confirm_request
	_hide_confirm()
	_confirm_request = ""
	if action == "back":
		_populate_mod_list()
	elif action == "reset_all":
		_do_reset_config(_selected_mod_id)


func _on_confirm_keep():
	_hide_confirm()
	_confirm_request = ""


func _hide_confirm():
	if _confirm_row and is_instance_valid(_confirm_row):
		var p = _confirm_row.get_parent()
		if p:
			p.remove_child(_confirm_row)
		_confirm_row.free()
		_confirm_row = null


func _on_back_pressed():
	if _color_popup and _color_popup.visible:
		_color_popup.hide()
	if _current_view == "config":
		if _config_dirty and _confirm_request == "":
			_show_confirm("Discard unsaved changes?", "Discard", "back")
			return
		_hide_confirm()
		_confirm_request = ""
		_populate_mod_list()
	else:
		close()


func _update_status():
	_status_label.text = ""


func _update_title():
	var suffix = " *" if _config_dirty else ""
	_title_label.text = _title_base + suffix


func _set_config_dirty(val: bool):
	_config_dirty = val
	_update_title()


func _add_separator():
	var sep = HSeparator.new()
	sep.rect_min_size = Vector2(0, 8)
	if _current_view == "config":
		_config_container.add_child(sep)
	else:
		_mod_list_container.add_child(sep)


func _load_display_settings():
	var schema = ModLoaderConfig.get_config_schema("josephwhite-mod_manager")
	var properties = schema.get("properties", {})
	var data = _load_config_data("josephwhite-mod_manager", properties)
	if data.size() > 0:
		_display_settings = data


func _recalc_ui_fonts():
	var scale = float(_display_settings.get("ui_font_scale", 100)) / 100.0
	_body_font = null
	if _base_body_font is DynamicFont:
		_body_font = _base_body_font.duplicate()
		_body_font.size = int(round(float(_base_body_font.size) * scale))
	_title_font = null
	if _base_title_font is DynamicFont:
		_title_font = _base_title_font.duplicate()
		_title_font.size = int(round(float(_base_title_font.size) * scale))


func _apply_ui_fonts(node: Control):
	for child in node.get_children():
		if child is Control:
			_apply_ui_fonts(child)
	if node is Label or node is Button or node is CheckBox or node is LineEdit:
		if node == _title_label and _title_font:
			node.add_font_override("font", _title_font)
		elif _body_font:
			node.add_font_override("font", _body_font)


func _get_config_path(mod_id: String) -> String:
	return "user://configs/" + mod_id + "/settings.json"


func _load_config_data(mod_id: String, properties: Dictionary) -> Dictionary:
	var path = _get_config_path(mod_id)
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

	var defaults = {}
	for prop_name in properties:
		defaults[prop_name] = properties[prop_name].get("default", null)
	return defaults
