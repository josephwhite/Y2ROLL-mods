extends "res://gui/spedometer_label.gd"

var trap_active: bool = false

## Override Speedometer to handle smile trap
func update_speed(p_new_speed: float):
	.update_speed(p_new_speed)
	if trap_active:
		self.text = ":)"