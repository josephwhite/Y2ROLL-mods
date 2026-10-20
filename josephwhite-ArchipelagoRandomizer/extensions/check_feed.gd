extends Node
## Menu showing Archipelago items being sent and recieved.

const MAX_ENTRIES = 8

const COLOR_PENDING = Color(0.7, 0.7, 0.7)
const COLOR_TRAP = Color(1.0, 0.4, 0.35)
const COLOR_PROGRESSION = Color(0.5, 1.0, 0.5)
const COLOR_USEFUL = Color(0.55, 0.85, 1.0)
const COLOR_FILLER = Color(0.8, 0.8, 0.8)

const STATE_PENDING = 0
const STATE_SENT = 1
const STATE_RECEIVED = 2

var _feed_layer: CanvasLayer = null
var _feed_panel: PanelContainer = null
var _feed_box: VBoxContainer = null
var _rows: Array = []
var _pending: Array = []
var _flush_scheduled: bool = false
var _booted: bool = false
var _connected: bool = false


## Build the feed layer once at boot, well before any AP connect/catchup frame.
func _ready():
	call_deferred("_boot_layer")


func _boot_layer():
	if _booted:
		return
	var layer = get_node_or_null("/root/Y2ROOT/check_feed_layer")
	if layer and is_instance_valid(layer):
		_booted = true
		return
	# A CanvasLayer must live under the root (it renders above the whole game);
	# create it on a quiet frame so we never mutate the scene tree mid-connect.
	yield(get_tree(), "idle_frame")
	_ensure_layer()
	_booted = true


func push_pending(loc_id):
	_defer("push_pending", loc_id, "", "")


## Show/hide the feed based on the AP connection state. Disconnecting also
## clears every row so a reconnect starts with a fresh feed.
func set_connected(enabled: bool):
	_connected = enabled
	if _feed_layer == null:
		return
	if enabled:
		_feed_layer.visible = true
		_reflow()
	else:
		_feed_layer.visible = false
		_clear_rows()


func upsert_sent(loc_id, text, cls):
	_defer("upsert_sent", loc_id, text, cls)


func upsert_received(loc_id, text, cls):
	_defer("upsert_received", loc_id, text, cls)


func upsert_received_key(p_key, text, cls):
	_defer("upsert_received_key", p_key, text, cls)


func _defer(kind, loc_id, text, cls):
	_pending.append({
		"kind": kind,
		"loc_id": loc_id,
		"text": text,
		"cls": cls
	})
	if _flush_scheduled:
		return
	_flush_scheduled = true
	call_deferred("_flush")


func _flush():
	_flush_scheduled = false
	if _pending.size() == 0:
		return
	if not is_inside_tree():
		_flush_scheduled = true
		call_deferred("_flush")
		return
	Log.info("check_feed flush (%d ops)" % _pending.size())
	var ops = _pending
	_pending = []
	for op in ops:
		match op.kind:
			"push_pending":
				_ensure_layer()
				_add_row(_key(op.loc_id), "[S] ...", COLOR_PENDING, STATE_PENDING)
			"upsert_sent":
				var idx = _find_index(_key(op.loc_id))
				if idx >= 0 and _rows[idx].state != STATE_RECEIVED:
					_set_row(idx, op.text, _color_for_class(op.cls), STATE_SENT)
			"upsert_received":
				var key = _key(op.loc_id)
				var idx = _find_index(key)
				if idx >= 0:
					_set_row(idx, op.text, _color_for_class(op.cls), STATE_RECEIVED)
				else:
					_ensure_layer()
					_add_row(key, op.text, _color_for_class(op.cls), STATE_RECEIVED)
			"upsert_received_key":
				var idx2 = _find_index(str(op.loc_id))
				if idx2 >= 0:
					_set_row(idx2, op.text, _color_for_class(op.cls), STATE_RECEIVED)
				else:
					_ensure_layer()
					_add_row(str(op.loc_id), op.text, _color_for_class(op.cls), STATE_RECEIVED)


func _key(loc_id) -> String:
	return "loc:%d" % loc_id


## Drop all rows (labels) but keep the "AP Activity" header.
func _clear_rows():
	for row in _rows:
		if row.label and is_instance_valid(row.label):
			_feed_box.remove_child(row.label)
			row.label.queue_free()
	_rows = []
	_reflow()


func _find_index(key) -> int:
	for i in range(_rows.size()):
		if _rows[i].key == key:
			return i
	return -1


func _add_row(key, text, color, state):
	var label = Label.new()
	label.text = text
	label.add_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed_box.add_child(label)
	var row = {"label": label, "key": key, "state": state}
	_rows.append(row)
	Log.info("check_feed add %s: %s (state=%d)" % [key, text, state])
	while _rows.size() > MAX_ENTRIES:
		var oldest = _rows.pop_front()
		if oldest.label and is_instance_valid(oldest.label):
			_feed_box.remove_child(oldest.label)
			oldest.label.queue_free()
	_reflow()


func _set_row(idx, text, color, state):
	var row = _rows[idx]
	row.label.text = text
	row.label.add_color_override("font_color", color)
	row.state = state
	Log.info("check_feed row %s: %s (state=%d)" % [row.key, text, state])
	_reflow()


## Get color based on item classification
func _color_for_class(cls) -> Color:
	match str(cls):
		"Progression":
			return COLOR_PROGRESSION
		"Useful":
			return COLOR_USEFUL
		"Trap":
			return COLOR_TRAP
		_:
			return COLOR_FILLER


func _ensure_layer():
	if _feed_layer != null:
		return
	if not is_inside_tree():
		return
	_feed_layer = CanvasLayer.new()
	_feed_layer.layer = 102

	_feed_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_content_margin_all(4)
	_feed_panel.add_stylebox_override("panel", style)

	_feed_box = VBoxContainer.new()
	_feed_box.rect_min_size = Vector2(80, 0)
	_feed_box.set("custom_constants/separation", 1)

	var header = RichTextLabel.new()
	header.bbcode_enabled = true
	header.bbcode_text = "[center][b]AP Activity[/b][/center]"
	header.scroll_active = false
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_color_override("default_color", Color.white)
	header.rect_min_size = Vector2(0, 16)
	_feed_box.add_child(header)

	_feed_panel.add_child(_feed_box)
	_feed_layer.add_child(_feed_panel)
	_feed_layer.visible = _connected
	get_tree().root.add_child(_feed_layer)
	Log.info("check_feed layer: vp=%s" % str(get_viewport().get_visible_rect().size))
	_reflow()


func _reflow():
	var vp = get_viewport().get_visible_rect().size
	var min_size = _feed_panel.get_combined_minimum_size()
	_feed_panel.set_size(Vector2(max(min_size.x, 90), min_size.y))
	_feed_panel.set_position(Vector2(vp.x - _feed_panel.rect_size.x - 4, vp.y * 0.75 - _feed_panel.rect_size.y * 0.5))
