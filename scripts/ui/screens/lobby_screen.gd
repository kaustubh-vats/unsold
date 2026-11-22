extends VBoxContainer
## Lobby: pick a franchise, host configures settings and starts the auction.

var body: VBoxContainer
var footer: VBoxContainer
var _dirty := true
var _sig := ""


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var top := UI.hbox()
	top.add_child(UI.button("◀", _back, "icon"))
	var tv := UI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.caption("Online room" if Game.store.is_online() else "Solo season", UI.GOLD))
	tv.add_child(UI.display("Choose your franchise", 34))
	top.add_child(tv)
	top.add_child(UI.theme_button())
	top.add_child(UI.sound_button())
	add_child(top)
	body = UI.vbox(14)
	add_child(UI.scroll(body))
	footer = UI.vbox(6)
	add_child(footer)
	Game.store.changed.connect(_on_changed)
	Game.store.error.connect(func(m): UI.toast(self, m))


## Only re-render when something visible changed (heartbeats arrive every few seconds).
func _on_changed() -> void:
	var s := Game.store
	var p := []
	var players: Dictionary = s.state.get("players", {})
	for uid in players:
		p.append([uid, players[uid].get("name", ""), players[uid].get("team", "")])
	p.sort()
	var sig := JSON.stringify([s.meta().get("settings", {}), s.meta().get("host", ""), p])
	if sig != _sig:
		_sig = sig
		_dirty = true


func _process(_dt: float) -> void:
	if _dirty:
		_dirty = false
		_render()


func _back() -> void:
	Game.leave_room()
	Game.goto("home")


func _render() -> void:
	var s := Game.store
	UI.clear(body)
	UI.clear(footer)
	if s.is_online():
		var codep := UI.panel(Color(UI.GOLD, 0.08), 18, 14, Color(UI.GOLD, 0.45))
		var ch := UI.hbox(12)
		codep.add_child(ch)
		var cv := UI.vbox(0)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(UI.caption("Room code — share with friends", UI.GOLD))
		cv.add_child(UI.display(s.room_code, 52, UI.GOLD))
		ch.add_child(cv)
		var copy := UI.button("COPY", func():
			DisplayServer.clipboard_set(s.room_code)
			UI.toast(self, "Code copied", UI.GREEN), "ghost", 14)
		copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ch.add_child(copy)
		body.add_child(codep)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for t in DB.teams():
		grid.add_child(_team_tile(t))
	body.add_child(grid)

	if s.is_online():
		body.add_child(UI.caption("Players in room  •  %d / 10" % s.state.get("players", {}).size()))
		var pl := UI.glass(14)
		var pv := UI.vbox(8)
		pl.add_child(pv)
		var players: Dictionary = s.state.get("players", {})
		for uid in players:
			var p: Dictionary = players[uid]
			var row := UI.hbox(10)
			var tid: String = p.get("team", "")
			row.add_child(UI.crest(tid, 30) if tid != "" else UI.label("•", 20, UI.DIM))
			var nm := UI.label(p.get("name", "?"), 16, UI.TEXT, true)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nm)
			if uid == s.meta().get("host", ""):
				row.add_child(UI.chip("HOST", Color(UI.GOLD, 0.2), UI.GOLD, 11))
			row.add_child(UI.label(DB.team_short(tid) if tid != "" else "choosing…", 14, UI.team_accent(tid) if tid != "" else UI.DIM, true))
			pv.add_child(row)
		body.add_child(pl)

	body.add_child(_wishlist_panel())
	body.add_child(UI.caption("Auction settings"))
	var sp := UI.glass(16)
	var sv := UI.vbox(14)
	sp.add_child(sv)
	var st := s.settings()
	var host := s.is_host()
	var diff: String = st.get("difficulty", "medium")
	sv.add_child(_setting("AI difficulty", UI.segmented(["Easy", "Medium", "Hard"], ["easy", "medium", "hard"],
		diff, func(v): s.set_setting("difficulty", v), host)))
	sv.add_child(UI.wrap(UI.label({
		"easy": "AI franchises bid cautiously and often misjudge players — bargains everywhere.",
		"medium": "AI franchises bid like a typical auction room.",
		"hard": "AI franchises bid hard for stars, rarely miss a good player and answer your bids fast.",
	}.get(diff, ""), 12, UI.DIM)))
	sv.add_child(_setting("Bid timer", UI.segmented(["8s", "10s", "15s", "20s"], [8, 10, 15, 20],
		int(st.get("timer", 10)), func(v): s.set_setting("timer", v), host)))
	sv.add_child(_setting("Winner decided by", UI.segmented(["Simulated season", "Team rating"], ["season", "score"],
		st.get("win_mode", "season"), func(v): s.set_setting("win_mode", v), host)))
	if s.is_online():
		var bots: bool = st.get("ai_fill", true)
		sv.add_child(_setting("Opponents", UI.segmented(["Players + bots", "Real players only"], [true, false],
			bots, func(v): s.set_setting("ai_fill", v), host)))
		sv.add_child(UI.wrap(UI.label(
			"2–10 real players. Franchises nobody picks are run by AI bots." if bots
			else "2–10 real players. Only the franchises players pick take part — no bots.", 12, UI.DIM)))
	if not host:
		sv.add_child(UI.label("Only the host can change settings.", 13, UI.DIM))
	body.add_child(sp)
	body.add_child(UI.spacer(4, 0))

	# Footer: start or wait.
	if host:
		var mine := s.my_team()
		var humans := 0
		for uid in s.state.get("players", {}):
			if s.state["players"][uid].get("team", "") != "":
				humans += 1
		var short := s.is_online() and humans < 2
		var label := "PICK A FRANCHISE" if mine == "" else ("WAITING FOR PLAYERS (%d/2)" % humans if short else "START AUCTION")
		var start := UI.button(label, func(): s.start_auction(), "primary", 20)
		start.custom_minimum_size.y = 60
		start.disabled = mine == "" or short
		footer.add_child(start)
	else:
		footer.add_child(UI.center(UI.label("Waiting for the host to start the auction…", 15, UI.MUTED)))


## "★ My wishlist": star players before the auction to get alerts when they're up.
func _wishlist_panel() -> Control:
	var p := Views.tap_panel(UI.box(Color(UI.GOLD, 0.08), 16, 14, Color(UI.GOLD, 0.45)), func():
		var sh := Sheet.open(self, "WISHLIST", Views.wishlist_page)
		sh.closed.connect(_render))
	var h := UI.hbox(12)
	h.add_child(UI.display("★", 38, UI.GOLD))
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := Game.wishlist.size()
	v.add_child(UI.display("MY WISHLIST" + (" (%d)" % n if n > 0 else ""), 22, UI.GOLD))
	v.add_child(UI.wrap(UI.label("Star the players you want. We'll alert you when they come up." if n == 0
		else "%d player%s starred. Tap to edit." % [n, "" if n == 1 else "s"], 12, UI.MUTED)))
	h.add_child(v)
	h.add_child(UI.caption("Edit ›", UI.GOLD, 11))
	return Views.fill_tap(p, h)


func _setting(title: String, control: Control) -> Control:
	var v := UI.vbox(8)
	v.add_child(UI.label(title, 15, UI.TEXT, true))
	v.add_child(control)
	return v


func _team_tile(t: Dictionary) -> Control:
	var s := Game.store
	var tid: String = t["id"]
	var owner := s.team_owner_name(tid)
	var mine := s.my_team() == tid
	var taken := owner != "" and not mine
	var col := UI.team_color(tid)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 86)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var base := UI.shade(col, 0.55, 0.78)
	if mine:
		b.add_theme_stylebox_override("normal", UI.glow(UI.box(UI.shade(col, 0.35, 0.9), 16, 8, UI.GOLD, 2), Color(UI.GOLD, 0.35), 12))
		b.add_theme_stylebox_override("hover", b.get_theme_stylebox("normal"))
	else:
		b.add_theme_stylebox_override("normal", UI.box(base, 16, 8, Color(col.lightened(0.2), 0.35)))
		b.add_theme_stylebox_override("hover", UI.box(UI.shade(col, 0.4, 0.9), 16, 8, Color(col.lightened(0.3), 0.8)))
	b.add_theme_stylebox_override("pressed", UI.box(UI.shade(col, 0.3, 0.95), 16, 8, UI.GOLD))
	b.add_theme_stylebox_override("disabled", UI.box(UI.ink(0.03), 16, 8, UI.LINE))
	b.disabled = taken
	b.pressed.connect(func():
		UI._click()
		s.choose_team(tid))
	var h := UI.hbox(8)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	var cr := UI.crest(tid, 64)
	if taken:
		cr.modulate = Color(1, 1, 1, 0.35)
	h.add_child(cr)
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var n := UI.label(t["name"], 14, UI.TEXT if not taken else UI.DIM, true)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 90
	v.add_child(n)
	var sub: String = "YOUR TEAM" if mine else (owner.to_upper() if taken else t["city"].to_upper())
	v.add_child(UI.caption(sub, UI.GOLD if mine else UI.MUTED, 10))
	h.add_child(v)
	UI.ignore_mouse(h)
	b.add_child(h)
	return b
