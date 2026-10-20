extends "res://main_switch.gd"

## Vanilla save with hook for our overrides.
func get_save() -> Dictionary:
	var data = .get_save()
	data = _apply_save_overrides(data)
	return data

## Make our own changes to save data
func _apply_save_overrides(data: Dictionary) -> Dictionary:
	# Insert changes to data
	return data

## If we want to mimic a fresh save, return an empty dict.
func _get_empty_save() -> Dictionary:
	return {}