extends "res://util/steam_wrapper.gd"
## While the Archipelago mod is enabled, suppress Steam achievements.

func unlock_achievement(p_key: String, p_commit: = true):
	if _ap_mod_enabled():
		return
	.unlock_achievement(p_key, p_commit)


func increment_stat(p_key: String, p_commit: = true):
	if _ap_mod_enabled():
		return
	.increment_stat(p_key, p_commit)


func _ap_mod_enabled() -> bool:
	return get_tree().get_nodes_in_group("y2roll_ap_main").size() > 0
