class_name TouchScroll
extends ScrollContainer
## A ScrollContainer that can be dragged from anywhere inside it, including
## on top of buttons and cards (the stock one only drags from empty space,
## because buttons swallow the touch). It watches the raw input, so nested
## lists work too: a sideways strip inside a vertical list claims horizontal
## drags and the outer list claims vertical ones. A drag that turns into a
## scroll never counts as a tap on the button it started on. Flings coast.

const SLOP := 12.0          # px of movement before a press becomes a drag
const FRICTION := 5.0       # how quickly a fling slows down (per second)

var _tracking := false
var _dragging := false
var _axis := -1             # 0 = horizontal, 1 = vertical
var _press_pos := Vector2.ZERO
var _start := Vector2.ZERO  # scroll offsets at press
var _last_pos := Vector2.ZERO
var _last_t := 0
var _vel := 0.0             # px/s along _axis, for the fling
var _cancel_queued := false


func _init() -> void:
	# Disable the built-in touch drag so it can't fight ours.
	scroll_deadzone = 100000


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _cancel_queued:
			return
		if event.pressed:
			_vel = 0.0
			_dragging = false
			_tracking = is_visible_in_tree() and get_global_rect().has_point(event.position) \
				and _covers(event.position)
			if _tracking:
				_press_pos = event.position
				_last_pos = event.position
				_last_t = Time.get_ticks_msec()
				_start = Vector2(scroll_horizontal, scroll_vertical)
		else:
			var was_dragging := _dragging
			if Time.get_ticks_msec() - _last_t > 80:
				_vel = 0.0   # finger had stopped before lifting: no fling
			_tracking = false
			_dragging = false
			if was_dragging:
				# Swallow the release and send one far off-screen instead, so the
				# button under the finger lets go without firing "pressed".
				get_viewport().set_input_as_handled()
				# The button first sees the finger leave it, then the release.
				var away := Vector2(-100000, -100000)
				var mv := InputEventMouseMotion.new()
				mv.position = away
				mv.global_position = away
				mv.button_mask = MOUSE_BUTTON_MASK_LEFT
				var up := event.duplicate() as InputEventMouseButton
				up.position = away
				up.global_position = away
				_cancel_queued = true
				Input.parse_input_event(mv)
				Input.parse_input_event(up)
				_clear_cancel.call_deferred()
	elif event is InputEventMouseMotion and _tracking:
		var d: Vector2 = event.position - _press_pos
		if not _dragging:
			if d.length() < SLOP:
				return
			var axis := 0 if absf(d.x) > absf(d.y) else 1
			if not _can_scroll(axis):
				_tracking = false   # not our direction: leave it to another list
				return
			_axis = axis
			_dragging = true
			_press_pos = event.position   # start moving from here, no jump
			_start = Vector2(scroll_horizontal, scroll_vertical)
			d = Vector2.ZERO
		var now := Time.get_ticks_msec()
		var dt := maxf(0.001, (now - _last_t) / 1000.0)
		var step: float = (event.position - _last_pos)[_axis]
		_vel = lerpf(_vel, -step / dt, 0.4)
		_last_pos = event.position
		_last_t = now
		if _axis == 0:
			scroll_horizontal = int(_start.x - d.x)
		else:
			scroll_vertical = int(_start.y - d.y)
		get_viewport().set_input_as_handled()


func _clear_cancel() -> void:
	# parse_input_event delivers on the next input flush; release the guard after.
	await get_tree().process_frame
	_cancel_queued = false


func _process(dt: float) -> void:
	if _dragging or _tracking or absf(_vel) < 20.0:
		return
	var move := _vel * dt
	if _axis == 0:
		var before := scroll_horizontal
		scroll_horizontal = int(scroll_horizontal + move)
		if scroll_horizontal == before and absf(move) >= 1.0:
			_vel = 0.0
	elif _axis == 1:
		var before := scroll_vertical
		scroll_vertical = int(scroll_vertical + move)
		if scroll_vertical == before and absf(move) >= 1.0:
			_vel = 0.0
	_vel *= maxf(0.0, 1.0 - FRICTION * dt)


func _can_scroll(axis: int) -> bool:
	if axis == 0:
		if horizontal_scroll_mode == SCROLL_MODE_DISABLED:
			return false
		var hb := get_h_scroll_bar()
		return hb.max_value - hb.page > 1.0
	if vertical_scroll_mode == SCROLL_MODE_DISABLED:
		return false
	var vb := get_v_scroll_bar()
	return vb.max_value - vb.page > 1.0


## True unless an overlay (a sheet drawn over this list, in group
## "ui_overlay") covers the point, so lists under an open sheet stay put.
func _covers(pos: Vector2) -> bool:
	for o in get_tree().get_nodes_in_group("ui_overlay"):
		var c := o as Control
		if c == null or not c.is_visible_in_tree() or c == self or c.is_ancestor_of(self):
			continue
		if c.get_global_rect().has_point(pos):
			return false
	return true
