class_name Sheet
extends Control
## A full-screen sheet that slides up over any screen, with a back stack.
## A page is a title plus a fill callback: fill(body: VBoxContainer, sheet: Sheet).
##   var sh := Sheet.open(self, "ALL FRANCHISES", func(body, sh): ...)
##   sh.push("MUMBAI", func(body, sh): ...)   # ◀ goes back, ✕ closes

signal closed

var body: VBoxContainer
var title_label: Label
var back_btn: Button
var scroll: ScrollContainer
var panel: PanelContainer
var stack := []


static func open(host: Control, title: String, fill: Callable) -> Sheet:
	var s := Sheet.new()
	s._build(host)
	s.push(title, fill)
	return s


func _build(host: Control) -> void:
	top_level = true
	z_index = 50
	add_to_group("ui_overlay")
	var vp := host.get_viewport_rect().size
	position = Vector2.ZERO
	size = vp
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)
	var w := minf(vp.x, 600.0)
	panel = PanelContainer.new()
	var st := UI.box(Color(UI.BG, 0.98), 24, 16, UI.LINE)
	st.corner_radius_bottom_left = 0
	st.corner_radius_bottom_right = 0
	panel.add_theme_stylebox_override("panel", st)
	panel.position = Vector2((vp.x - w) / 2.0, vp.y * 0.06)
	panel.size = Vector2(w, vp.y * 0.94)
	var v := UI.vbox(10)
	panel.add_child(v)
	var head := UI.hbox(8)
	back_btn = UI.button("◀", back, "icon")
	head.add_child(back_btn)
	title_label = UI.display("", 26, UI.TEXT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	head.add_child(title_label)
	head.add_child(UI.button("✕", close, "icon"))
	v.add_child(head)
	body = UI.vbox(8)
	scroll = UI.scroll(body)
	v.add_child(scroll)
	add_child(panel)
	host.add_child(self)
	panel.position.y += 40
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "position:y", vp.y * 0.06, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func push(title: String, fill: Callable) -> void:
	stack.append([title, fill])
	_render()
	scroll.scroll_vertical = 0


func back() -> void:
	if stack.size() > 1:
		stack.pop_back()
		_render()
		scroll.scroll_vertical = 0
	else:
		close()


## Re-runs the current page's fill (e.g. after live data changed).
func refresh() -> void:
	var keep := scroll.scroll_vertical
	_render()
	scroll.set_deferred("scroll_vertical", keep)


func top_title() -> String:
	return stack[-1][0] if not stack.is_empty() else ""


func _render() -> void:
	if stack.is_empty():
		return
	UI.clear(body)
	var page: Array = stack[-1]
	title_label.text = page[0]
	back_btn.visible = stack.size() > 1
	(page[1] as Callable).call(body, self)


func close() -> void:
	if is_queued_for_deletion():
		return
	remove_from_group("ui_overlay")
	closed.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)
