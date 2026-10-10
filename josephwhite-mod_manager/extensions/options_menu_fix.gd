extends "res://gui/options_menu.gd"


func _get_button(p_menu_index: int) -> Control:
	# Out-of-bounds menu indexing fix for added buttons.
	var count = self._buttons.get_child_count()
	if count == 0:
		return null
	var idx = int(clamp(p_menu_index, 0, count - 1))
	var target = get_focus_target(self._buttons.get_child(idx))
	if target != null:
		return target
	for offset in range(1, count):
		# Probed a child with no FOCUS_ALL descendant (the "MODS" separator Label).
		var after = idx + offset
		if after < count:
			target = get_focus_target(self._buttons.get_child(after))
			if target != null:
				return target
		var before = idx - offset
		if before >= 0:
			target = get_focus_target(self._buttons.get_child(before))
			if target != null:
				return target
	return null