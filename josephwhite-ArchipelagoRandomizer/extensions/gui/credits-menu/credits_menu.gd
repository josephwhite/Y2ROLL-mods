extends "res://gui/credits-menu/credits_menu.gd"


const AP_CREDITS = """\n\n\n
Archipelago Implementation:\n
josephwhite\n
\n
Original GodotAP (Godot 4.x) library:\n
EmilyV99 + the rest of the contributors\n
(https://github.com/EmilyV99/GodotAP/contributors)\n
"""

func set_is_menu_open(p_is_open: bool):
	.set_is_menu_open(p_is_open)
	if p_is_open:
		var credits = get_node("%CreditsText")
		# Override Credits to add AP Credits
		if not credits.bbcode_text.begins_with(AP_CREDITS):
			var new_text = AP_CREDITS + credits.text
			credits.bbcode_text = new_text
			credits.text = new_text
