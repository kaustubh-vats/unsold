extends VBoxContainer
## After the auction: pick your playing XI, then confirm.

var list: VBoxContainer
var counters: HBoxContainer
var problems_label: Label
var confirm_btn: Button
var waiting: Label
var xi: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var s := Game.store
	var tid := s.my_team()
	var head := UI.hbox(12)
	head.add_child(UI.crest(tid, 58))
	var hv := UI.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UI.caption("Auction complete  •  " + DB.team(tid).get("name", ""), UI.GOLD))
	hv.add_child(UI.display("Pick your playing XI", 36))
	head.add_child(hv)
	head.add_child(UI.sound_button())
	add_child(head)
	counters = UI.hbox(6)
	add_child(counters)
	problems_label = UI.wrap(UI.label("", 13, UI.RED, true))
	add_child(problems_label)
	list = UI.vbox(6)
	add_child(UI.scroll(list))
	var row := UI.hbox()
	var auto := UI.button("Auto-pick best XI", _auto)
	row.add_child(UI.expand(auto))
	confirm_btn = UI.button("CONFIRM XI", _confirm, "primary", 18)
	row.add_child(UI.expand(confirm_btn))
	add_child(row)
	waiting = UI.center(UI.wrap(UI.label("", 14, UI.MUTED)))
	add_child(waiting)
	xi = s.team(tid).get("xi", [])
	if xi.is_empty():
		xi = XI.best_xi(s.team(tid).get("squad", {}).keys())
	_render()
	s.changed.connect(_on_changed)
	_on_changed()


func _on_changed() -> void:
	var s := Game.store
	if not is_instance_valid(s):
		return
	var players: Dictionary = s.state.get("players", {})
	var ready := 0
	for uid in players:
		if players[uid].get("ready", false):
			ready += 1
	var me_ready: bool = players.get(s.my_uid, {}).get("ready", false)
	if s.is_online():
		waiting.text = "%d / %d managers ready%s" % [ready, players.size(), " — waiting for the others…" if me_ready else ""]
	else:
		waiting.text = "Simulating the season…" if me_ready else ""


func _squad() -> Dictionary:
	var s := Game.store
	return s.team(s.my_team()).get("squad", {})


func _counter(text: String, ok: bool) -> Control:
	return UI.chip(text, Color(UI.GREEN, 0.16) if ok else Color(UI.RED, 0.16), UI.GREEN if ok else UI.RED.lightened(0.3), 12)


func _render() -> void:
	UI.clear(list)
	var squad := _squad()
	var ids: Array = squad.keys()
	var order := {"WK": 0, "BAT": 1, "AR": 2, "PACE": 3, "SPIN": 4}
	ids.sort_custom(func(a, b):
		var pa := DB.player(a)
		var pb := DB.player(b)
		if pa["role"] != pb["role"]:
			return order[pa["role"]] < order[pb["role"]]
		return pa["ovr"] > pb["ovr"])
	for pid in ids:
		list.add_child(_row(pid, int(squad[pid])))
	var os := xi.filter(func(id): return DB.player(id)["overseas"]).size()
	var need := mini(11, squad.size())
	UI.clear(counters)
	counters.add_child(_counter("XI %d/%d" % [xi.size(), need], xi.size() == need))
	var max_os := XI.allowed_overseas(squad.keys())
	counters.add_child(_counter("OVERSEAS %d/%d" % [os, max_os], os <= max_os))
	counters.add_child(_counter("BOWLERS %d" % XI.bowling_options(xi), XI.bowling_options(xi) >= mini(5, XI.bowling_options(squad.keys()))))
	var has_wk := xi.any(func(id): return DB.player(id)["role"] == "WK")
	counters.add_child(_counter("KEEPER", has_wk))
	var probs := XI.problems(xi, squad.keys())
	problems_label.text = "  •  ".join(probs)
	confirm_btn.disabled = not probs.is_empty()


func _row(pid: String, price: int) -> Control:
	var p := DB.player(pid)
	var on: bool = xi.has(pid)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.toggle_mode = true
	b.button_pressed = on
	b.custom_minimum_size.y = 58
	b.add_theme_stylebox_override("normal", UI.box(UI.GLASS, 14, 10, UI.LINE))
	b.add_theme_stylebox_override("hover", UI.box(UI.GLASS_HI, 14, 10, Color(1, 1, 1, 0.2)))
	b.add_theme_stylebox_override("pressed", UI.box(Color(0.07, 0.25, 0.18, 0.9), 14, 10, UI.GREEN))
	b.add_theme_stylebox_override("hover_pressed", UI.box(Color(0.08, 0.3, 0.2, 0.95), 14, 10, UI.GREEN))
	b.toggled.connect(func(v):
		UI._click()
		_toggle(pid, v))
	var h := UI.hbox(10)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	var mark := UI.display("✔" if on else "", 26, UI.GREEN)
	mark.custom_minimum_size.x = 22
	h.add_child(mark)
	h.add_child(UI.role_icon(p["role"], 36))
	var nv := UI.vbox(-2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := UI.label(p["name"] + ("  ✈" if p["overseas"] else ""), 15, UI.TEXT, true)
	n.clip_text = true
	nv.add_child(n)
	nv.add_child(UI.caption("%s  •  BAT %d  •  BOWL %d" % [p["role"], p["bat"], p["bowl"]], UI.MUTED, 10))
	h.add_child(nv)
	var ov := UI.display(str(p["ovr"]), 30, UI.GOLD if on else UI.MUTED)
	h.add_child(ov)
	UI.ignore_mouse(h)
	b.add_child(h)
	return b


func _toggle(pid: String, on: bool) -> void:
	if on and not xi.has(pid):
		if xi.size() >= 11:
			UI.toast(self, "XI is full — remove someone first")
		else:
			xi.append(pid)
	elif not on:
		xi.erase(pid)
	_render()


func _auto() -> void:
	xi = XI.best_xi(_squad().keys())
	_render()


func _confirm() -> void:
	var s := Game.store
	confirm_btn.disabled = true
	await s.set_xi(s.my_team(), XI.order_batting(xi))
	await s.set_ready(true)
