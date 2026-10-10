extends Node


const MOD_ID = "josephwhite-ArchipelagoRandomizer"

var _mod_path: String

# Current level tracking
var current_stage: int = 0
var current_level: int = 0
var gem_counter: int = 0
var _level_name: String = ""

# Overall game tracking
var completed_stages: Array = []
var _goal_sent: bool = false
var _chip_sig: String = ""

# Our custom nodes/classes
var trap_manager: Node
var check_feed: Node

# apworld data
var _slot_data: Dictionary = {}
var _level_mode: int = 0
var _include_gems: bool = false
var _include_gold: bool = false
var _deathlink: bool = false
var _traplink: bool = false
var _trap_weights: Dictionary = {}
var _trap_percentage: int = 0

## Mod config. Refreshed at boot and on CampaignMenu entry.
var _config_data: Dictionary = {}

var _suppress_deathlink: bool = true
var _level_timer_node: Node = null
var _dl_popup_layer: CanvasLayer = null
var _dl_popup_panel: PanelContainer = null
var _dl_popup_label: Label = null
var _dl_popup_gen: int = 0

## Item groups mirror the apworld.
## Note: Datapackage doesn't send item groups over the wire.
## "World Access" array order = world index 0-6, matches _world_access.
const ITEM_GROUPS = {
	"World Access": [
		"Purple Mountains Access",
		"Deep Sea Access",
		"Chilly Culdesac Access",
		"Downtown City Access",
		"Molten Crag Access",
		"Starry Space Access",
		"Empyrean Access"
	],
	"Traps": [
		"Saturation Trap",
		"Grayscale Trap",
		"Smile Trap",
		"Minimap Trap",
		"Taunt Trap"
	],
}

var _world_access: Array = [false, false, false, false, false, false, false]

## Level-unlock mode (slot level_unlocks == 1): all worlds open, levels gated.

## Unlocked level NAMES in level mode (rebuilt from obtained_items on each connect).
## Names are globally unique across all 105 levels (verified against apworld basegame.py).
var _unlocked_levels: Dictionary = {}
## Matches level-access items: "N-M: LEVEL NAME - Access"
var _level_access_re: RegEx = null

var _campaign_menu: Node = null


func _init():
	# Make Regex
	_level_access_re = RegEx.new()
	_level_access_re.compile("^([0-9]+)-([0-9]+): (.+) - Access$")
	# Make Trap Manager
	trap_manager = load(_get_trap_manager_path()).new()
	trap_manager.name = "TrapManager"
	add_child(trap_manager)
	# Make Check Feed
	check_feed = load(_get_check_feed_path()).new()
	check_feed.name = "CheckFeed"
	add_child(check_feed)
	# End with script extensions
	install_script_extensions()


func _ready():
	add_to_group("y2roll_ap_main")
	get_tree().connect("node_added", self, "_on_node_added")
	_refresh_config()
	call_deferred("_bootstrap_ap")


## Add our extensions
func install_script_extensions():
	_mod_path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_ID)
	var credits_path = _mod_path.plus_file("extensions/gui/credits-menu/credits_menu.gd")
	ModLoaderMod.install_script_extension(credits_path)
	var campaign_gate_path = _mod_path.plus_file("extensions/campaign_menu_extension.gd")
	ModLoaderMod.install_script_extension(campaign_gate_path)
	var main_switch_path = _mod_path.plus_file("extensions/main_switch_extension.gd")
	ModLoaderMod.install_script_extension(main_switch_path)


#region Hooks

## Detects game nodes and connects their signals / fields to our mod.
func _on_node_added(node: Node):
	if node is Label and node.name == "SpeedLabel":
		Log.info("node_added: SpeedLabel found")
		trap_manager.set_speed_label(node)
		node.connect("tree_exiting", self, "_on_speed_label_removed", [node])
		_apply_smile_script(node)
	elif node.is_in_group("gem"):
		Log.info("node_added: gem found, connecting signal")
		node.connect("player_entered", self, "_on_gem_collected")
	elif node.name == "Goal":
		Log.info("node_added: Goal found, connecting signal")
		node.connect("player_entered", self, "_on_goal_reached", [node])
	elif node is Label and node.name == "LevelIndexValue":
		Log.info("node_added: LevelIndexValue found")
		call_deferred("_read_level_index_text", node)
	elif node is Label and node.name in ["LevelNameValue", "LevelName"]:
		Log.info("node_added: level-name label found")
		call_deferred("_read_level_name", node)
	elif node.name == "CampaignMenu":
		Log.info("node_added: CampaignMenu found")
		# CampaignMenu persists across entrances (shown/hidden, not re-added) —
		# hook visibility_changed so config refresh + AP tag sync run on EVERY
		# campaign entry, not just the first discovery.
		if not node.is_connected("visibility_changed", self, "_on_campaign_visibility_changed"):
			node.connect("visibility_changed", self, "_on_campaign_visibility_changed")
		call_deferred("_refresh_config")
		call_deferred("_inject_ap_button", node)
		call_deferred("_setup_world_unlocks", node)
		# Debug: Unlock all worlds
		#call_deferred("_override_world_unlocks", node)
	elif node.name == "KillPlane":
		Log.info("node_added: KillPlane found, connecting player_fell_out")
		node.connect("player_fell_out", self, "_on_player_fell_out")
	elif node.name == "LevelTimer":
		Log.info("node_added: LevelTimer found, connecting timeout")
		_level_timer_node = node
		_suppress_deathlink = false
		node.connect("timeout", self, "_on_player_timeout")
		node.connect("tree_exiting", self, "_on_level_timer_removed", [node])
		if node.get_parent():
			node.get_parent().connect("reset_level_state", self, "_on_level_reset_state")


## Player collects a gem
func _on_gem_collected():
	gem_counter += 1
	if _level_name == "":
		Log.info("AP gem collected: %d-%d - Gem %d (UNMAPPED)" % [current_stage, current_level, gem_counter])
		return
	# Only send check if gems in slot data
	if _include_gems:
		var ap_name = "%d-%d: %s - Gem %d" % [current_stage, current_level, _level_name, gem_counter]
		Log.info("AP gem collected: " + ap_name)
		_send_location_check(ap_name)


## Reached the goal tape in a level
func _on_goal_reached(goal_node: Node = null):
	var stage_key = "%d-%d" % [current_stage, current_level]
	if not stage_key in completed_stages:
		completed_stages.append(stage_key)
	Log.info("Stage completed: %s (%d unique)" % [stage_key, completed_stages.size()])
	if _level_name == "":
		return
	# AP: Level clear check
	var clear_name = "%d-%d: %s - Clear" % [current_stage, current_level, _level_name]
	Log.info("AP goal: sending Clear " + clear_name)
	_send_location_check(clear_name)
	# AP: Gold Medal check
	var is_gold: bool = false
	if goal_node and is_instance_valid(goal_node) and goal_node.level_timer != null:
		if goal_node.level_timer.get_medal() == "gold":
				is_gold = true
	if is_gold and _include_gold:
		var gold_name = "%d-%d: %s - Gold Medal" % [current_stage, current_level, _level_name]
		Log.info("AP goal: sending Gold Medal " + gold_name)
		_send_location_check(gold_name)
	# AP: Game Goal
	# Level Unlocks: World/Level - final level clear
	if current_stage == 7 and current_level == 15:
		var ap = Util._get_ap()
		if ap and ap.conn and not _goal_sent:
			_goal_sent = true
			ap.set_client_status(ap.ClientStatus.CLIENT_GOAL)
			Log.info("AP GOAL sent: final level 7-15 reached")


func _on_player_fell_out():
	Log.info("Player fell out of level: stage=%d level=%d" % [current_stage, current_level])
	_send_deathlink("fell out of the level.")
	trap_manager.clear_all_traps()
	trap_manager.deactivate_minimap()


func _on_player_timeout():
	Log.info("Player timed out: stage=%d level=%d" % [current_stage, current_level])
	_send_deathlink("ran out of time.")
	trap_manager.clear_all_traps()
	trap_manager.deactivate_minimap()


func _on_level_timer_removed(node: Node):
	if _level_timer_node == node:
		_level_timer_node = null


## CampaignMenu visibility hook. `visibility_changed` is zero-arg in Godot 3 — read
## state from _campaign_menu. The menu RE-INSTANCES per entry (node_added fires
## each time), so world/level unlock UI is already re-applied by the discovery
## path plus the gui_input arrow-step re-apply. This hook only owns the cached
## config refresh and the AP tag resync, plus hiding the level-lock overlay.
func _on_campaign_visibility_changed():
	if _campaign_menu == null or not is_instance_valid(_campaign_menu):
		return
	if _campaign_menu.visible:
		call_deferred("_refresh_config")
		call_deferred("_sync_ap_tags")
	else:
		_hide_level_lock_overlay()


func _on_level_reset_state():
	_suppress_deathlink = false


func _on_ap_deathlink(source, cause, json):
	if not (_level_timer_node and is_instance_valid(_level_timer_node) and _level_timer_node.is_enabled):
		Log.info("AP DeathLink received but ignored (not mid-run): %s" % [json])
		return
	Log.info("AP DeathLink received: %s" % [cause])
	_show_deathlink_popup(cause if not str(cause).empty() else "%s died" % str(source))
	_suppress_deathlink = true
	_level_timer_node.emit_signal("timeout")
	# Optionally, set timer to 0 for visual
	#_level_timer_node.set_time_remaining(0.0)
	return

#endregion


#region Menus

## Add our Archipelago "menu entry".
## We can't easily add it to the menu and our gameplay is focused on campaign,
## so our AP menu is a small button that opens a connection menu.
func _inject_ap_button(campaign):
	if not is_instance_valid(campaign):
		Log.warn("AP inject: campaign invalid at defer time")
		return
	if campaign.has_node("APConnectPanel"):
		return
	var bottom_bar = campaign.get_node_or_null("Items/BottomBar")
	if bottom_bar == null:
		Log.warn("AP inject: Items/BottomBar not found under CampaignMenu")
		return
	var button = Button.new()
	button.name = "APConnectButton"
	button.text = "AP"
	button.focus_mode = Control.FOCUS_NONE
	button.rect_min_size = Vector2(34, 0)
	button.anchor_left = 0.0
	button.anchor_top = 0.0
	button.anchor_right = 0.0
	button.anchor_bottom = 0.0
	button.margin_left = 6
	button.margin_right = 48
	button.margin_top = 2
	button.margin_bottom = 22
	campaign.add_child(button)
	# Add AP Connection menu
	var panel_scene = load(_mod_path + "/menus/ap_connect_menu.tscn")
	var panel = panel_scene.instance()
	panel.name = "APConnectPanel"
	campaign.add_child(panel)
	panel.connect("state_changed", self, "_on_ap_state_changed", [button])
	button.connect("pressed", panel, "open")
	campaign.connect("visibility_changed", panel, "_on_campaign_visibility_changed")
	Log.info("AP connect button + panel injected into CampaignMenu")


func _on_ap_state_changed(status_text, button):
	button.text = status_text


## Recolor Top Bar in Campaign Menu.
## Chips indicate world/level access.
func _recolor_chips():
	if _campaign_menu == null or not is_instance_valid(_campaign_menu):
		return
	var top = _campaign_menu.get_node_or_null("%TopBar")
	if top == null or top.get_child_count() == 0:
		return
	var grey = Color("#998599")
	var black = Color("#000000")
	var medal_map = [
		"#d96638",
		"#e9fcff",
		"#fdd447"
	]
	var pan = "custom_styles/panel"
	if _campaign_menu._selecting_level:
		var wd = _campaign_menu.call("_get_current_world_data")
		var levels = wd["levels"]
		var i = 0
		for chip in top.get_children():
			var locked = false
			if _level_mode == 1 and i < levels.size():
				var title = str(_campaign_menu.call("_get_level_title", levels[i]))
				locked = not _unlocked_levels.has(title)
			var results = null
			if i < levels.size():
				results = _campaign_menu.save.get(_campaign_menu.call("_get_results_key", levels[i]))
			var base = grey
			if locked:
				base = grey.darkened(0.4)
			elif results:
				var m = results.get("medal")
				if m != null:
					base = Color(medal_map[int(m)])
			var greyed = black if locked else (base * grey.lightened(0.3))
			var style = chip.get(pan)
			chip.color_base = base
			chip.color_greyed = greyed
			if style:
				style.bg_color = base if i == _campaign_menu._level_step else greyed
			i += 1
	else:
		var i = 0
		for chip in top.get_children():
			var locked = false
			if _level_mode == 0 and i < _world_access.size():
				locked = not _world_access[i]
			var base = Color.white
			var greyed = grey
			if locked:
				base = grey.darkened(0.4)
				greyed = black
			var style = chip.get(pan)
			chip.color_base = base
			chip.color_greyed = greyed
			if style:
				style.bg_color = base if i == _campaign_menu._world_step else greyed
			i += 1


func _setup_world_unlocks(node):
	if not is_instance_valid(node):
		return
	_campaign_menu = node
	node.unlock_override = true
	if not node.is_connected("gui_input", self, "_on_campaign_gui_input"):
		node.connect("gui_input", self, "_on_campaign_gui_input", [node])
	if not node.is_connected("visibility_changed", self, "_on_campaign_visibility_changed"):
		node.connect("visibility_changed", self, "_on_campaign_visibility_changed")
	if _level_mode == 1:
		for w in range(_world_access.size()):
			_world_access[w] = true
		Log.info("Level mode: all worlds open, level gating active")
	_apply_world_unlocks()
	call_deferred("_apply_world_unlocks")
	Log.info("World unlocks: access-item gated (%d worlds obtained)" % _count_worlds_obtained())
	return


func _apply_world_unlocks():
	_chip_sig = ""
	if _campaign_menu == null or not is_instance_valid(_campaign_menu):
		return
	_campaign_menu._unlocked_worlds = _world_access.duplicate()
	_campaign_menu.call("_update_world_select_body")
	if _level_mode == 1:
		var wt = _campaign_menu.get_node_or_null("%WorldUnlockText")
		if wt and wt.text != "":
			wt.text = ""
		call_deferred("_refresh_level_lock_ui")
		return
	var ws = _campaign_menu._world_step
	var unlocked = ws >= 0 and ws < _world_access.size() and _world_access[ws]
	var msg = "" if unlocked else "Collect this world's access item to unlock this world."
	var wt = _campaign_menu.get_node_or_null("%WorldUnlockText")
	if wt and wt.text != msg:
		wt.text = msg
	return


func _process(_delta):
	if _campaign_menu and is_instance_valid(_campaign_menu) and _campaign_menu.visible:
		var top = _campaign_menu.get_node_or_null("%TopBar")
		if top:
			var sig = "%d|%d|%s|%d" % [_campaign_menu._world_step, _campaign_menu._level_step, str(_campaign_menu._selecting_level), top.get_child_count()]
			if sig != _chip_sig:
				_chip_sig = sig
				_recolor_chips()
	if _level_mode != 1:
		return
	if _campaign_menu == null or not is_instance_valid(_campaign_menu):
		return
	if not _campaign_menu.visible:
		if _level_lock_overlay_visible():
			_hide_level_lock_overlay()
		return
	var selected = _selected_level_name()
	var locked = selected != "" and not _unlocked_levels.has(selected)
	if _level_lock_overlay_visible() and not locked:
		_hide_level_lock_overlay()


func _on_campaign_gui_input(event, node):
	if _level_mode == 1:
		var level_select = node.get_node_or_null("%LevelSelect")
		if level_select and level_select.visible:
			if event is InputEventKey and event.pressed:
				if event.scancode == KEY_LEFT or event.scancode == KEY_RIGHT \
						or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
						or event.is_action_pressed("ui_cancel"):
					_hide_level_lock_overlay()
			else:
				call_deferred("_refresh_level_lock_ui")
	if event is InputEventKey and event.pressed and node.has_focus():
		if event.scancode == KEY_LEFT or event.scancode == KEY_RIGHT:
			call_deferred("_apply_world_unlocks")
	elif event is InputEventMouseButton and not event.pressed:
		call_deferred("_apply_world_unlocks")


func _refresh_level_lock_ui():
	_chip_sig = ""
	if not (_level_mode == 1):
		return
	if _campaign_menu == null or not is_instance_valid(_campaign_menu):
		return
	var selected = _selected_level_name()
	var locked = selected != "" and not _unlocked_levels.has(selected)
	if _level_lock_overlay_visible() and not locked:
		_hide_level_lock_overlay()


## Name of the currently selected level in the level-select view ("" when not on it).
func _selected_level_name() -> String:
	if _campaign_menu == null or not is_instance_valid(_campaign_menu):
		return ""
	var level_select = _campaign_menu.get_node_or_null("%LevelSelect")
	if level_select == null or not level_select.visible:
		return ""
	var item_title = _campaign_menu.get_node_or_null("%ItemTitle")
	if item_title == null:
		return ""
	return str(item_title.text).strip_edges()


## Used by campaign_menu_extension.gd: veto level start + show the lock overlay.
func is_campaign_level_locked(p_level_title: String) -> bool:
	if _level_mode != 1:
		return false
	if p_level_title == "":
		return false
	return not _unlocked_levels.has(p_level_title)


func show_lock_for_level(p_level_title: String):
	_show_level_lock_overlay(p_level_title)


func _get_level_lock_overlay() -> Control:
	if _campaign_menu == null or not is_instance_valid(_campaign_menu):
		return null
	var overlay = _campaign_menu.get_node_or_null("LevelLockOverlay")
	if overlay:
		return overlay
	overlay = ColorRect.new()
	overlay.name = "LevelLockOverlay"
	overlay.color = Color(0.05, 0.05, 0.1, 0.8)
	overlay.focus_mode = Control.FOCUS_NONE
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	_campaign_menu.add_child(overlay)
	overlay.rect_position = Vector2.ZERO
	overlay.rect_size = _campaign_menu.rect_size
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGN_CENTER
	overlay.add_child(vbox)
	# Add lock image
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.texture = load("res://gui/lock.webp")
	icon.expand = true
	icon.rect_size = Vector2(48, 48)
	icon.rect_min_size = Vector2(48, 48)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.focus_mode = Control.FOCUS_NONE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)
	var title = Label.new()
	title.name = "Title"
	title.text = "LOCKED"
	title.align = Label.ALIGN_CENTER
	title.focus_mode = Control.FOCUS_NONE
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	var body = Label.new()
	body.name = "Body"
	body.align = Label.ALIGN_CENTER
	body.autowrap = true
	body.custom_minimum_size = Vector2(200, 0)
	body.focus_mode = Control.FOCUS_NONE
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(body)
	var hint = Label.new()
	hint.name = "Hint"
	hint.text = "Press ESC to return"
	hint.align = Label.ALIGN_CENTER
	hint.focus_mode = Control.FOCUS_NONE
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint)
	Log.info("Level lock overlay created")
	return overlay


func _center_level_lock_content(overlay: Control):
	if overlay == null:
		return
	var vbox = overlay.get_node_or_null("VBox")
	if vbox == null:
		return
	var min_size = vbox.get_combined_minimum_size()
	vbox.rect_size = min_size
	vbox.rect_position = (overlay.rect_size - min_size) / 2.0


func _show_level_lock_overlay(level_name: String):
	if _campaign_menu == null or not is_instance_valid(_campaign_menu):
		return
	var overlay = _get_level_lock_overlay()
	if overlay == null:
		return
	var title = overlay.get_node_or_null("VBox/Title")
	if title:
		title.text = level_name
		title.text = ""
	var body = overlay.get_node_or_null("VBox/Body")
	if body:
		body.text = "Locked - collect this level's access item from the multiworld to play."
	_center_level_lock_content(overlay)
	overlay.visible = true
	return


func _hide_level_lock_overlay():
	if _campaign_menu == null or not is_instance_valid(_campaign_menu):
		return
	if _level_lock_overlay_visible():
		_campaign_menu.get_node("LevelLockOverlay").visible = false


func _level_lock_overlay_visible() -> bool:
	if _campaign_menu == null or not is_instance_valid(_campaign_menu):
		return false
	if _campaign_menu.has_node("LevelLockOverlay"):
		return _campaign_menu.get_node("LevelLockOverlay").visible
	return false


func _show_deathlink_popup(text: String):
	if _dl_popup_layer == null:
		_dl_popup_layer = CanvasLayer.new()
		_dl_popup_layer.layer = 102
		_dl_popup_panel = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
		style.set_content_margin_all(6)
		_dl_popup_panel.add_stylebox_override("panel", style)
		_dl_popup_panel.anchor_left = 0.0
		_dl_popup_panel.anchor_right = 0.0
		_dl_popup_panel.anchor_top = 1.0
		_dl_popup_panel.anchor_bottom = 1.0
		_dl_popup_panel.margin_left = 6.0
		_dl_popup_panel.margin_right = 286.0
		_dl_popup_panel.margin_top = -70.0
		_dl_popup_panel.margin_bottom = -6.0
		_dl_popup_label = Label.new()
		_dl_popup_label.text = text
		_dl_popup_label.autowrap = true
		_dl_popup_label.add_color_override("font_color", Color.white)
		_dl_popup_panel.add_child(_dl_popup_label)
		_dl_popup_layer.add_child(_dl_popup_panel)
		get_tree().root.add_child(_dl_popup_layer)
	else:
		_dl_popup_panel.visible = true
		_dl_popup_label.text = text
	_dl_popup_gen += 1
	var gen = _dl_popup_gen
	yield(get_tree().create_timer(5.0), "timeout")
	if _dl_popup_layer != null and gen == _dl_popup_gen:
		_dl_popup_panel.visible = false


func _hide_deathlink_popup():
	if _dl_popup_layer != null:
		_dl_popup_panel.visible = false

#endregion

#region AP


func _get_ap_scene_path() -> String:
	return ModLoaderMod.get_unpacked_dir().plus_file(MOD_ID + "/godot_ap/autoloads/archipelago.tscn")


func _bootstrap_ap():
	var ap_scene = load(_get_ap_scene_path())
	if not ap_scene:
		Log.error("Failed to load Archipelago scene at %s" % _get_ap_scene_path())
		return
	var ap_node = ap_scene.instance()
	ap_node.name = "Archipelago"
	ap_node.casus["DISABLE_BITWISE_OPERATIONS"] = true
	ap_node.deathlink_group = ""
	get_tree().root.add_child(ap_node)
	if ap_node.is_inside_tree():
		# Client config AFTER add_child: Version.val() routes through
		# Util._ap_load() -> _get_ap(), which needs /root/Archipelago to exist.
		ap_node.AP_GAME_NAME = "Y2ROLL"
		ap_node.AP_CLIENT_VERSION = Version.val(0, 1, 0)
		ap_node.AP_VERSION = Version.val(0, 6, 7)
		ap_node.AP_ITEM_HANDLING = ap_node.ItemHandling.ALL
		ap_node.TRAP_LINK_ALIASES = {
			"Literature Trap": "Taunt Trap",
		}
		ap_node.connect("connected", self, "_on_ap_connected")
		ap_node.connect("disconnected", self, "_on_ap_disconnected")
		_load_connection(ap_node)
		Log.info("Archipelago node bootstrapped at root (casus: DISABLE_BITWISE_OPERATIONS=true)")
	else:
		Log.error("Archipelago node failed to enter the tree")


func _load_connection(ap_node):
	var file = Util._file_open("user://ap/connection.dat", File.READ)
	if not file:
		return
	if not ap_node.creds.read(file):
		# Pre-T3 connection.dat had 3 lines (no password); reading the 4th line
		# hits EOF and read() fails. Fall back to the legacy 3-line format.
		file.seek(0)
		ap_node.creds.update(
			file.get_line(), file.get_line(),
			file.get_line(), "")
	file.close()
	Log.info("AP connection.dat loaded (slot '%s')" % ap_node.creds.slot)


func get_slot_data() -> Dictionary:
	return _slot_data


func is_deathlink_active() -> bool:
	return _deathlink


func is_traplink_active() -> bool:
	return _traplink


## Compare build to apworld's list of supported versions
func _build_supported() -> bool:
	var supported = _slot_data.get("supported_base_builds")
	if typeof(supported) != TYPE_ARRAY:
		return false
	var build = _get_game_build()
	if build == "":
		return false
	for entry in supported:
		var ver = str(entry).strip_edges()
		if ver.begins_with("v") or ver.begins_with("V"):
			ver = ver.substr(1)
		if ver == build:
			return true
	return false


func _on_ap_connected(conn, _json):
	# Get slot data
	_slot_data = conn.slot_data if conn.slot_data != null else {}
	# Disconnect if build is not supported
	if not _build_supported():
		var ap = Util._get_ap()
		var msg
		if typeof(_slot_data.get("supported_base_builds")) == TYPE_ARRAY:
			var parts = PoolStringArray()
			for entry in _slot_data.get("supported_base_builds"):
				parts.append(str(entry))
			msg = "Refused: ArchipelagoRandomizer does not support Y2ROLL v%s. Supports: %s" % [_get_game_build(), parts.join(", ")]
		else:
			msg = "Refused: server did not provide 'supported_base_builds'."
		Log.error(msg)
		ap.ap_disconnect()
		call_deferred("_show_build_rejection", msg)
		return
	# Show the activity feed only once connected
	check_feed.set_connected(true)
	# Set options from Slot Data
	# Slot Data - DeathLink/TrapLink
	var sd_dl = _slot_data.get("death_link", false)
	_deathlink = (sd_dl == true or sd_dl == 1)
	var sd_tl = _slot_data.get("trap_link", false)
	_traplink = (sd_tl == true or sd_tl == 1)
	# Slot Data - Trap Weights
	_trap_weights = _slot_data.get("trap_weights", {})
	if typeof(_trap_weights) != TYPE_DICTIONARY:
		_trap_weights = {}
	# Slot Data - Trap Weights
	_trap_percentage = int(_slot_data.get("trap_percentage", 0))
	# Slot Data - Trap Weights
	var sd_gems = _slot_data.get("include_gems", false)
	_include_gems = (sd_gems == true or sd_gems == 1)
	var sd_gold = _slot_data.get("include_gold", false)
	_include_gold = (sd_gold == true or sd_gold == 1)
	# Slot Data - Level Unlock Mode
	_level_mode = int(_slot_data.get("level_unlocks", 0))
	if _level_mode == 1:
		_unlocked_levels = {}
		for w in range(_world_access.size()):
			_world_access[w] = true
		_apply_world_unlocks()
	conn.connect("obtained_items", self, "_on_ap_items")
	conn.connect("deathlink", self, "_on_ap_deathlink")
	conn.connect("traplink", self, "_on_ap_traplink")
	conn.connect("bounce", self, "_on_ap_bounce")
	_goal_sent = false
	# Reconnect mid-level: no fresh LevelTimer add / reset_level_state to clear a
	# stale `_suppress_deathlink` (sim echo). Player is active -> allow outbound deaths.
	if _level_timer_node and is_instance_valid(_level_timer_node):
		_suppress_deathlink = false
	call_deferred("_sync_ap_tags")
	Log.info("AP slot data received (%d keys, DeathLink=%s, TrapLink=%s, level_unlocks=%s, trap_percentage=%d, trap_weights=%d)" % [_slot_data.size(), str(_deathlink), str(_traplink), str(_slot_data.get("level_unlocks")), _trap_percentage, _trap_weights.size()])


func _on_ap_disconnected():
	# Hide and clear the activity feed
	check_feed.set_connected(false)
	_slot_data = {}
	_goal_sent = false
	_deathlink = false
	_traplink = false
	_trap_weights = {}
	_trap_percentage = 0
	_world_access = [false, false, false, false, false, false, false]
	_level_mode = 0
	_unlocked_levels = {}
	_hide_deathlink_popup()
	_apply_world_unlocks()
	return


func _show_build_rejection(msg):
	var panel = _campaign_menu.get_node_or_null("APConnectPanel")
	if panel and is_instance_valid(panel):
		panel.show_build_rejection(msg)


## Set tags based on Slot Data and Client Settings.
func _sync_ap_tags():
	var ap = Util._get_ap()
	if not ap:
		return
	var cfg = _config_data
	var dl_cfg = str(cfg.get("deathlink_control", "Follow YAML"))
	var tl_cfg = str(cfg.get("traplink_control", "Follow YAML"))
	var want_dl = (_deathlink and dl_cfg=="Follow YAML") or (dl_cfg=="Force on")
	var want_tl = (_traplink and tl_cfg=="Follow YAML") or (tl_cfg=="Force on")
	ap.set_deathlink(want_dl)
	ap.set_traplink(want_tl)
	return


func _on_ap_items(items):
	var ap = Util._get_ap()
	for item in items:
		Log.info("obtained item id=%s loc=%s dest=%s flags=%s" % [str(item.id), str(item.loc_id), str(item.dest_player_id), str(item.flags)])
		var cls = ap.get_item_classification(item.flags)
		var name = item.get_name()
		var unresolved = name == str(item.id)
		# Add item to feed
		var text = ""
		if item.loc_id == -2:
			text = "Starting Inventory" if unresolved else "Starting Inventory: %s" % name
		elif item.loc_id == -1:
			text = "Server Grant" if unresolved else "Server Grant: %s" % name
		else:
			text = "%s - for you" % name
		if item.loc_id == -2 or item.loc_id == -1:
			check_feed.upsert_received_key("inv:" + name, text, cls)
		else:
			check_feed.upsert_received(item.loc_id, text, cls)
		# Apply item
		if _item_in_group(name, "Traps"):
			_on_ap_item_trap(name)
		if _item_in_group(name, "World Access"):
			_on_ap_item_access(name)
		if _level_mode:
			var m = _level_access_re.search(name)
			if m:
				_on_ap_item_level_access(m)


## A trap item was recieved
func _on_ap_item_trap(name: String):
	if not _item_in_group(name, "Traps"):
		return
	# We will rely on GodotAP to check TrapLink tag
	_send_traplink(name)
	if not _trap_allowed_by_config(name):
		Log.info("AP trap item '%s' received but config/weights block it (not deployed)" % name)
		return
	if not _trap_deployable(name):
		Log.info("AP trap item '%s' received but cannot deploy in current level (not deployed)" % name)
		return
	_activate_ap_trap(name, "item")
	return


## A trap from traplink was recieved
func _on_ap_traplink(source, trap_name: String, json):
	Log.info("AP traplink '%s' received" % json)
	if not _trap_allowed_by_config(trap_name):
		Log.info("AP traplink '%s' received but config/weights block it (not deployed)" % trap_name)
		return
	if not _trap_deployable(trap_name):
		Log.info("AP traplink '%s' received but cannot deploy in current level (not deployed)" % trap_name)
		return
	var ap = Util._get_ap()
	if not ap or not ap.conn:
		return
	var me = ap.conn.get_player_name(-1, false)
	if source == me:
		Log.info("AP traplink '%s' received from self (not deployed)" % trap_name)
		return
	_activate_ap_trap(trap_name, "item")
	return


## Generic handler for Bouce packets. Handles packets based on tags.
func _on_ap_bounce(json):
	var tags = json.get("tags", [])
	if tags.has("KnockbackLink"):
		var data = json.get("data", {})
		var source = data.get("source", "")
		var cause = data.get("cause", "")
		var value = data.get("value", {})
		var uuid = data.get("uuid", "")
		_on_ap_knockback(source, cause, value, uuid, json)
	return


## A KnockbackLink bounce was received.
## `value` is the SCALED delta-velocity; axes +x east / +y up / +z south.
func _on_ap_knockback(source, cause, value, uuid, json):
	var is_vector3 = _validate_knockback_to_vector3(value)
	if is_vector3 == false:
		Log.error("AP KnockbackLink received with unusable value (typeof=%s): %s" % [str(typeof(value)), str(json)])
		return
	var ap = Util._get_ap()
	if not ap or not ap.conn:
		return
	var me = ap.conn.get_player_name(-1, false)
	if source == me and ap.config.uuid == uuid:
		Log.info("AP KnockbackLink received by self (not deployed)")
		return
	var vec = _convert_knockback_to_vector3(value)
	Log.info("AP knockback received: source=%s cause=%s value=%s (x=%.3f y=%.3f z=%.3f)" % [
		str(source),
		str(cause),
		str(vec),
		vec.x,
		vec.y,
		vec.z,
	])
	return


## Converts a KnockbackLink `value` payload to Vector3.
func _convert_knockback_to_vector3(value):
	if typeof(value) != TYPE_DICTIONARY:
		return Vector3(0, 0, 0)
	var x = value.get("x", 0.0)
	var y = value.get("y", 0.0)
	var z = value.get("z", 0.0)
	return Vector3(float(x), float(y), float(z))

## Validate a KnockbackLink `value` payload for use as Vector3.
## Returns false unless `value` is a Dictionary with numeric x/y/z.
func _validate_knockback_to_vector3(value):
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var comps = [
		value.get("x", 0.0),
		value.get("y", 0.0),
		value.get("z", 0.0)
	]
	for c in comps:
		var t = typeof(c)
		if t != TYPE_INT and t != TYPE_REAL:
			return false
	return true


func _send_traplink(trap_name: String):
	var ap = Util._get_ap()
	if ap and ap.conn:
		ap.conn.send_traplink(trap_name)


## An item for World Access was recieved
func _on_ap_item_access(name: String):
	if not _item_in_group(name, "World Access"):
		return
	var idx = ITEM_GROUPS["World Access"].find(name)
	if idx < 0 or _world_access[idx]:
		return
	_world_access[idx] = true
	Log.info("World unlocked (access item): %s (world %d)" % [name, idx])
	_apply_world_unlocks()
	call_deferred("_apply_world_unlocks")
	return


## A level-access item was received.
func _on_ap_item_level_access(rm):
	var stage = int(rm.get_string(1))
	var level = int(rm.get_string(2))
	var lname = rm.get_string(3).strip_edges()
	var key = "%d-%d" % [stage, level]
	if _unlocked_levels.get(lname, false):
		return
	_unlocked_levels[lname] = true
	if key == "7-15":
		Log.info("Level unlocked (access item): %s (%s) - final level, goal on clear" % [key, lname])
	else:
		Log.info("Level unlocked (access item): %s (%s)" % [key, lname])
	call_deferred("_refresh_level_lock_ui")
	return


func _send_location_check(ap_name: String):
	if _level_name == "":
		Log.info("check not sent: level name unmapped: " + ap_name)
		return
	var ap = Util._get_ap()
	if not ap or not ap.conn:
		return
	var id = ap.conn.get_gamedata_for_player().get_loc_id(ap_name)
	if id < 0:
		Log.info("not sent: name not in datapack: " + ap_name)
	elif ap.location_checked(id):
		Log.info("not sent: already checked: " + ap_name)
	else:
		if not ap.collect_location(id):
			Log.info("not sent: not valid for slot (id=%d): %s" % [id, ap_name])
			return
		check_feed.push_pending(id)
		ap.conn.scout(id, false, funcref(self, "_on_scout_reply"))
		Log.info("sent LocationChecks (id=%d): %s" % [id, ap_name])
	return


func _on_scout_reply(item):
	var ap = Util._get_ap()
	var cls = ap.get_item_classification(item.flags)
	var text = "%s - for %s" % [item.get_name(), ap.conn.get_player_name(item.dest_player_id)]
	# Set text for item in feed
	check_feed.upsert_sent(item.loc_id, text, cls)


func _send_deathlink(cause: String):
	if _suppress_deathlink:
		Log.info("AP DeathLink suppressed (sim echo): %s" % [cause])
		return
	var ap = Util._get_ap()
	# We will rely on GodotAP to check DeathLink tag
	if ap and ap.conn:
		var me = ap.conn.get_player_name(-1, false)
		ap.conn.send_deathlink("%s %s" % [me, cause])
		Log.info("AP DeathLink sent: %s" % [cause])


#endregion

#region Traps


## Maps AP trap item name to trap_manager.trap_config key.
func _trap_config_key(display_name: String) -> String:
	match display_name:
		"Saturation Trap": return "oversaturation"
		"Grayscale Trap": return "grayscale"
		"Minimap Trap": return "minimap"
		"Smile Trap": return "smile"
		#"World Distraction Trap": return "moon_cycle"
		#"Level Distraction Trap": return "checker_scroll"
		"Taunt Trap": return "taunt"
	return ""


## Build the trap_config dict (internal key -> raw tri-state string) from config data.
func _build_trap_config(cfg: Dictionary) -> Dictionary:
	return {
		"smile": cfg.get("trap_smile", "Follow YAML"),
		"grayscale": cfg.get("trap_grayscale", "Follow YAML"),
		"oversaturation": cfg.get("trap_oversaturation", "Follow YAML"),
		"minimap": cfg.get("trap_minimap", "Follow YAML"),
		#"moon_cycle": cfg.get("trap_moon_cycle", "Follow YAML"),
		#"moon_hide": cfg.get("trap_moon_hide", "Follow YAML"),
		#"moon_spin": cfg.get("trap_moon_spin", "Follow YAML"),
		#"checker_scroll": cfg.get("trap_checker_scroll", "Follow YAML"),
		"taunt": cfg.get("trap_taunt", "Follow YAML"),
	}


## Cache mod config + rebuild the trap_config mirror. Called at boot and on
## every CampaignMenu entry (Mod Manager saves apply on the next entry).
func _refresh_config():
	_config_data = _load_custom_config()
	trap_manager.trap_config = _build_trap_config(_config_data)


## Check trap name against config settings (and weights).
func _trap_allowed_by_config(display_name: String) -> bool:
	var cfg_key = _trap_config_key(display_name)
	if cfg_key == "":
		return false
	var mode = trap_manager.trap_config.get(cfg_key, "Follow YAML")
	if mode == "Force on":
		return true
	if mode == "Force off":
		return false
	return int(_trap_weights.get(display_name, 0)) > 0


## Validate if a trap can be activated.
func _trap_deployable(display_name: String) -> bool:
	var tm = trap_manager
	var result = false
	if tm._find_level_scene() == null:
		result = false
	if display_name == "Saturation Trap" or display_name == "Grayscale Trap":
		# Screen filter traps can override each other
		var wanted = "oversaturation" if display_name == "Saturation Trap" else "grayscale"
		result = tm._screen_trap_mode != wanted
	elif display_name == "Minimap Trap":
		result = not tm._minimap_trap_active
	elif display_name == "Smile Trap":
		result = tm._smile_candidates().size() > 0
	#elif display_name == "World Distraction Trap":
	#	result = not tm._moon_trap_active
	#elif display_name == "Level Distraction Trap":
	#	result = not tm._checker_trap_active
	elif display_name == "Taunt Trap":
		result = tm._taunt_units.size() < _trap_taunt_max()
	return result


func _trap_taunt_max() -> int:
	var cap = int(_config_data.get("trap_taunt_max", 3))
	if cap < 1:
		cap = 1
	return cap


func _activate_ap_trap(name: String, source: String):
	var tm = trap_manager
	var level = tm._find_level_scene()
	if level:
		tm._ensure_exit_hook(level)
	if name == "Saturation Trap":
		tm._activate_screen_trap(-1, "oversaturation")
	elif name == "Grayscale Trap":
		tm._activate_screen_trap(-1, "grayscale")
	elif name == "Minimap Trap":
		tm._activate_minimap_trap()
	elif name == "Smile Trap":
		tm._activate_smile_trap()
	#elif name == "World Distraction Trap":
	#	tm._activate_moon_trap(true)
	#elif name == "Level Distraction Trap":
	#	tm._activate_checker_trap(-1)
	elif name == "Taunt Trap":
		tm._activate_taunt_trap(_trap_taunt_max())
	else:
		Log.info("AP trap deploy (%s): unknown trap '%s' (not deployed)" % [source, name])
		return
	Log.info("AP trap deployed (%s): %s" % [source, name])
	return

#endregion


#region Helpers

## Get Y2ROLL semver build
func _get_game_build() -> String:
	var f = File.new()
	if f.open("res://build-version.txt", File.READ) != OK:
		return ""
	var build = f.get_as_text().strip_edges()
	f.close()
	if build.begins_with("v") or build.begins_with("V"):
		build = build.substr(1)
	return build


func set_level_info_from_text(p_full_text: String):
	Log.info("Level header text: '%s'" % p_full_text)
	var tokens = p_full_text.split(" ")
	var index_str = tokens[tokens.size() - 1]
	if "-" in index_str:
		var parts = index_str.split("-")
		if parts.size() == 2 and parts[0].is_valid_integer() and parts[1].is_valid_integer():
			current_stage = int(parts[0])
			current_level = int(parts[1])
			gem_counter = 0
			Log.info("Level set: stage=%d level=%d" % [current_stage, current_level])
			return
	current_stage = 0
	current_level = 0
	gem_counter = 0
	_level_name = ""


func _read_level_index_text(node: Label):
	set_level_info_from_text(node.text)


## Get name of current level
func _read_level_name(node: Label):
	var text = node.text.strip_edges()
	if text != "":
		_level_name = text
		Log.info("Level name: '%s'" % _level_name)


func _apply_smile_script(node: Label):
	var ext_script = load(_mod_path + "/extensions/gui/smile_label.gd")
	if ext_script:
		node.set_script(ext_script)


func _on_speed_label_removed(_node: Node):
	trap_manager.clear_speed_label()


func _get_trap_manager_path() -> String:
	var path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_ID + "/extensions/trap_manager.gd")
	return path


func _get_check_feed_path() -> String:
	var path = ModLoaderMod.get_unpacked_dir().plus_file(MOD_ID + "/extensions/check_feed.gd")
	return path


func _load_custom_config() -> Dictionary:
	var path = "user://configs/" + MOD_ID + "/settings.json"
	var file = File.new()
	if file.file_exists(path) and file.open(path, File.READ) == OK:
		var text = file.get_as_text()
		file.close()
		var parsed = JSON.parse(text)
		if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
			return parsed.result
	return {}


## Helper for logging world access count
func _count_worlds_obtained() -> int:
	var c = 0
	for w in _world_access:
		if w:
			c += 1
	return c


## Helper for verifing names in ITEM_GROUPS
func _item_in_group(item_name: String, group: String) -> bool:
	return item_name in ITEM_GROUPS.get(group, [])

#endregion


#region Debug

## Unlocks all worlds. For debugging.
func _override_world_unlocks(node):
	return
	node.unlock_override = true
	node._total_levels_beaten = 10000
	node._unlocked_worlds = [true, true, true, true, true, true, true]
	Log.info("World unlocks: ALL worlds unlocked (debug override)")

#endregion
