extends SceneTree
## Drags across buttons inside TouchScroll lists (vertical list with a
## sideways strip nested in it) and checks they scroll without firing taps,
## and that a plain tap still fires.
##   godot --headless --path . -s res://tests/scroll_test.gd

var taps := 0
var fails := 0


func _initialize() -> void:
	_run()


func _btn(w: float, h: float) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, h)
	b.pressed.connect(func(): taps += 1)
	return b


func _run() -> void:
	var outer := TouchScroll.new()
	outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.position = Vector2.ZERO
	outer.size = Vector2(400, 600)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(v)
	var strip_sc := TouchScroll.new()
	strip_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_sc.custom_minimum_size = Vector2(0, 100)
	var strip := HBoxContainer.new()
	strip_sc.add_child(strip)
	for i in 10:
		strip.add_child(_btn(120, 90))
	v.add_child(strip_sc)
	for i in 20:
		if i % 2 == 0:
			v.add_child(_btn(380, 80))
		else:
			var tp := UI.tap_panel(UI.box(Color(0.2, 0.2, 0.3), 12, 10), func(): taps += 1)
			tp.custom_minimum_size = Vector2(380, 80)
			v.add_child(tp)
	root.add_child(outer)
	for i in 5:
		await process_frame

	# Vertical drag starting on a list button.
	await _drag(Vector2(200, 400), Vector2(0, -250))
	_check("vertical scrolls", outer.scroll_vertical > 150, "v=%d" % outer.scroll_vertical)
	_check("strip unmoved by vertical drag", strip_sc.scroll_horizontal == 0, "h=%d" % strip_sc.scroll_horizontal)
	_check("no tap after vertical drag", taps == 0, "taps=%d" % taps)

	outer.set("_vel", 0.0)
	outer.scroll_vertical = 0
	for i in 10:
		await process_frame
	var v_before := outer.scroll_vertical
	# Horizontal drag on the strip (inside the vertical list).
	await _drag(Vector2(300, 50), Vector2(-250, 0))
	_check("strip scrolls sideways", strip_sc.scroll_horizontal > 150, "h=%d" % strip_sc.scroll_horizontal)
	_check("outer unmoved by sideways drag", outer.scroll_vertical == v_before, "v=%d" % outer.scroll_vertical)
	_check("no tap after sideways drag", taps == 0, "taps=%d" % taps)

	# A plain tap still works, and the next tap after a drag too
	# (rows alternate Buttons and tap panels: y=300 and y=380 hit one of each).
	await _drag(Vector2(200, 300), Vector2(3, 2))
	_check("tap fires", taps == 1, "taps=%d" % taps)
	await _drag(Vector2(200, 380), Vector2.ZERO)
	_check("second tap fires (other row type)", taps == 2, "taps=%d" % taps)
	# Vertical drag starting on a tap panel: scrolls, no tap.
	await _drag(Vector2(200, 380), Vector2(0, -200))
	_check("drag over tap panel scrolls without tapping", taps == 2 and outer.scroll_vertical > 100, "taps=%d v=%d" % [taps, outer.scroll_vertical])

	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(0)


func _drag(from: Vector2, delta: Vector2) -> void:
	_mouse_move(from, false)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = _win(from)
	down.global_position = down.position
	root.push_input(down)
	await process_frame
	var steps := 10
	for i in range(1, steps + 1):
		_mouse_move(from + delta * float(i) / steps, true)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = _win(from + delta)
	up.global_position = up.position
	root.push_input(up)
	for i in 4:
		await process_frame


func _mouse_move(p: Vector2, held: bool) -> void:
	var m := InputEventMouseMotion.new()
	m.position = _win(p)
	m.global_position = m.position
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(m)


## Canvas -> window coordinates (headless windows are tiny and stretched).
func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _check(name: String, ok: bool, info: String) -> void:
	print(("ok   " if ok else "FAIL ") + name + "  (" + info + ")")
	if not ok:
		fails += 1
