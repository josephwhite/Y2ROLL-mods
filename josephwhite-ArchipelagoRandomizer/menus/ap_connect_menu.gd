extends Control


signal state_changed(status_text)


onready var _fields: VBoxContainer = get_node("%Fields")
onready var _server_box: LineEdit = get_node("%ServerBox")
onready var _port_box: LineEdit = get_node("%PortBox")
onready var _slot_box: LineEdit = get_node("%SlotBox")
onready var _pwd_box: LineEdit = get_node("%PwdBox")
onready var _status_label: Label = get_node("%StatusLabel")
onready var _error_label: Label = get_node("%ErrorLabel")
onready var _connect_btn: Button = get_node("%ConnectBtn")
onready var _disconnect_btn: Button = get_node("%DisconnectBtn")


var _connected: bool = false


func _get_main():
	var mains = get_tree().get_nodes_in_group("y2roll_ap_main")
	return mains[0] if mains.size() > 0 else null


func _get_world_version() -> String:
	var main = _get_main()
	if main != null:
		return str(main.get_slot_data().get("world_version", ""))
	return ""


func _ready():
	var ap = Util._get_ap()
	ap.connect("connect_step", self, "_on_connect_step")
	ap.connect("connected", self, "_on_ap_connected")
	ap.connect("connectionrefused", self, "_on_connection_refused")
	ap.connect("disconnected", self, "_on_ap_disconnected")
	_connect_btn.connect("pressed", self, "_on_connect_pressed")
	_disconnect_btn.connect("pressed", self, "_on_disconnect_pressed")
	for box in [_server_box, _port_box, _slot_box, _pwd_box]:
		box.connect("text_entered", self, "_on_text_entered")
		box.connect("gui_input", self, "_on_field_gui_input")
	connect("hide", self, "_on_hidden")


func open():
	var ap = Util._get_ap()
	_connected = ap.is_ap_connected()
	_refresh_prefill()
	_refresh_view()
	_error_label.text = ""
	visible = true
	if _connected:
		_disconnect_btn.grab_focus()
	else:
		_server_box.grab_focus()


func close():
	hide()


func _refresh_prefill():
	var creds = Util._get_ap().creds
	_server_box.text = creds.ip
	_port_box.text = creds.get_port()
	_slot_box.text = creds.slot
	_pwd_box.text = creds.pwd


func _refresh_view():
	_fields.visible = not _connected
	_connect_btn.disabled = _connected
	_disconnect_btn.disabled = not _connected
	if _connected:
		#_status_label.text = "Connected as %s@%s:%s" % [_slot_box.text, _server_box.text, _port_box.text]
		_status_label.text = "Connected as %s" % [_slot_box.text]
		var wv = _get_world_version()
		if wv != "":
			_status_label.text += "\napworld v%s" % wv
	else:
		_status_label.text = "Enter server details, then press CONNECT."


## Set AP Menu button
func _button_text() -> String:
	if not _connected:
		return "AP"
	return "AP!"


func _save_connection():
	Util._make_dir_recursive("user://ap/")
	var file = Util._file_open("user://ap/connection.dat", File.WRITE)
	if file == null:
		return
	Util._get_ap().creds.write(file)
	file.close()


func _on_campaign_visibility_changed():
	if not get_parent().is_visible_in_tree():
		visible = false


func _on_hidden():
	if get_parent() != null and get_parent().is_visible_in_tree():
		get_parent().grab_focus()


func _on_text_entered(_text):
	_on_connect_pressed()


const _SWALLOW_KEYS = [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]


func _on_field_gui_input(event):
	if event is InputEventKey and event.pressed and not event.echo \
			and event.scancode in _SWALLOW_KEYS:
		get_viewport().set_input_as_handled()


func _on_connect_pressed():
	var ap = Util._get_ap()
	if not ap.is_not_connected():
		return
	_error_label.text = ""
	var port = _port_box.text.strip_edges()
	if not port.is_valid_integer():
		port = "38281"
	ap.ap_connect(_server_box.text.strip_edges(), port, _slot_box.text.strip_edges(), _pwd_box.text)


func _on_disconnect_pressed():
	Util._get_ap().ap_disconnect()


func _on_connect_step(msg):
	if not _connected:
		_status_label.text = msg


func _on_ap_connected(_conn, _json):
	_connected = true
	_save_connection()
	_refresh_prefill()
	_refresh_view()
	emit_signal("state_changed", _button_text())


func _on_connection_refused(_conn, json):
	_error_label.text = "ERROR: " + ", ".join(json.get("errors", ["Unknown"]))


func _on_ap_disconnected():
	_connected = false
	if is_inside_tree():
		_refresh_view()
	emit_signal("state_changed", "AP")


func show_build_rejection(msg: String):
	_connected = false
	if is_inside_tree():
		_refresh_view()
	_status_label.text = msg
	_error_label.text = msg
	emit_signal("state_changed", "AP")
