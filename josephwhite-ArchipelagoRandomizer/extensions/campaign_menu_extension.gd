extends "res://gui/campaign_menu.gd"

## If we did not unlock level yet, make Lock Screen instead
func _start_level(p_level_key: String, p_world_step: int, p_level_step: int):
	var nodes = get_tree().get_nodes_in_group("y2roll_ap_main")
	if nodes.size() > 0:
		var ap_mod = nodes[0]
		var title = _get_level_title(p_level_key)
		if ap_mod.is_campaign_level_locked(title):
			ap_mod.show_lock_for_level(title)
			_sfx_player.on_cancel_pressed()
			return
	._start_level(p_level_key, p_world_step, p_level_step)