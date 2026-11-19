extends VBoxContainer
## Final results: champion banner, your verdict, table, playoffs, ratings, scorecards.

var res: Dictionary
var mode := "season"


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var s := Game.store
	mode = s.settings().get("win_mode", "season")
	res = Game.results()
	var my := s.my_team()

	var winner := ""
	var my_pos := 0
	if mode == "season":
		winner = res["season"]["champion"]
		my_pos = _season_finish(my)
	else:
		winner = res["leaderboard"][0]["team"]
		for i in res["leaderboard"].size():
			if res["leaderboard"][i]["team"] == my:
				my_pos = i + 1
	var won := winner == my

	# Champion banner.
	var col := UI.team_color(winner)
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel",
		UI.glow(UI.box(Color(col.darkened(0.5), 0.9), 24, 18, UI.GOLD, 2), Color(UI.GOLD, 0.3), 18))
	var bh := UI.hbox(14)
	banner.add_child(bh)
	var cr := UI.crest(winner, 104)
	bh.add_child(cr)
	var bv := UI.vbox(-4)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_child(UI.caption("★ Champions ★" if mode == "season" else "★ Best squad ★", UI.GOLD, 12))
	var wn := UI.display(DB.team(winner).get("name", "").to_upper(), 36, UI.TEXT)
	wn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(wn)
	var who := s.team_owner_name(winner)
	if who != "" and not won:
		bv.add_child(UI.label("Managed by " + who, 14, UI.MUTED))
	bh.add_child(bv)
	add_child(banner)

	# Your verdict.
	var verdict := PanelContainer.new()
	var vcol := UI.GREEN if won else (UI.GOLD if my_pos <= 4 else UI.RED)
	verdict.add_theme_stylebox_override("panel", UI.box(Color(vcol, 0.12), 18, 14, Color(vcol, 0.5)))
	var vh := UI.hbox(12)
	verdict.add_child(vh)
	vh.add_child(UI.crest(my, 48))
	var vv := UI.vbox(-2)
	vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := "YOU WIN THE TITLE!" if won else ("FINISHED #%d" % my_pos)
	vv.add_child(UI.display(title, 30, vcol))
	vv.add_child(UI.label(_verdict_line(my, my_pos, won), 13, UI.MUTED))
	vh.add_child(vv)
	add_child(verdict)
	if won:
		Sfx.play("win")
		Sfx.duck(3.0)
		_confetti(banner)
	cr.pivot_offset = Vector2(52, 52)
	cr.scale = Vector2(0.6, 0.6)
	create_tween().tween_property(cr, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if mode == "season":
		_add_tab(tabs, "Table", _table())
		_add_tab(tabs, "Playoffs", _matches(res["season"]["playoffs"], false))
		_add_tab(tabs, "Ratings", _ratings())
		_add_tab(tabs, "Matches", _matches(res["season"]["matches"], true))
	else:
		_add_tab(tabs, "Ratings", _ratings())
		_add_tab(tabs, "Season", _table())
	_add_tab(tabs, "Squads", _squads())
	add_child(tabs)

	var row := UI.hbox()
	if s.is_host():
		row.add_child(UI.expand(UI.button("PLAY AGAIN", func(): s.reset_to_lobby(), "primary", 18)))
	row.add_child(UI.expand(UI.button("Home", func():
		Game.leave_room()
		Game.goto("home"))))
	add_child(row)


func _verdict_line(tid: String, pos: int, won: bool) -> String:
	if mode != "season":
		for r in res["leaderboard"]:
			if r["team"] == tid:
				return "Squad rating %.1f (%s)" % [r["total"], r["grade"]]
		return ""
	for r in res["season"]["table"]:
		if r["team"] == tid:
			var tail := "Lifted the trophy." if won else ("Reached the playoffs." if pos <= 4 else "Missed the playoffs.")
			return "League: %d W – %d L  •  NRR %+.2f  •  %s" % [r["w"], r["l"], r["nrr"], tail]
	return ""


func _season_finish(tid: String) -> int:
	var se: Dictionary = res["season"]
	if se["champion"] == tid:
		return 1
	if se["runner_up"] == tid:
		return 2
	var table: Array = se["table"]
	for i in table.size():
		if table[i]["team"] == tid:
			return i + 1
	return 0


func _add_tab(tabs: TabContainer, title: String, content: Control) -> void:
	var sc := UI.scroll(content)
	sc.name = title
	tabs.add_child(sc)


func _cell(text: String, w: int, color := UI.TEXT, display := false, align := HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var l := UI.display(text, 20, color) if display else UI.label(text, 14, color)
	l.custom_minimum_size.x = w
	l.horizontal_alignment = align
	return l


func _row_panel(highlight: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(UI.GOLD, 0.1) if highlight else Color(1, 1, 1, 0.03), 12, 8,
		Color(UI.GOLD, 0.5) if highlight else Color(0, 0, 0, 0)))
	return p


func _table() -> Control:
	var v := UI.vbox(5)
	var my := Game.store.my_team()
	var hdr := UI.hbox(4)
	hdr.add_child(_cell("", 64, UI.MUTED))
	var tn := UI.caption("Team", UI.DIM, 10)
	tn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(tn)
	for c in ["P", "W", "L", "PTS", "NRR"]:
		var l := UI.caption(c, UI.DIM, 10)
		l.custom_minimum_size.x = 34 if c != "NRR" else 58
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hdr.add_child(l)
	v.add_child(hdr)
	var rows: Array = res["season"]["table"]
	for i in rows.size():
		var r: Dictionary = rows[i]
		var p := _row_panel(r["team"] == my)
		var h := UI.hbox(4)
		p.add_child(h)
		h.add_child(_cell(str(i + 1), 22, UI.GREEN if i < 4 else UI.DIM, true, HORIZONTAL_ALIGNMENT_LEFT))
		h.add_child(UI.crest(r["team"], 32))
		var nm := UI.label(DB.team_short(r["team"]), 15, UI.TEXT, true)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(_cell(str(r["p"]), 34, UI.MUTED))
		h.add_child(_cell(str(r["w"]), 34))
		h.add_child(_cell(str(r["l"]), 34, UI.MUTED))
		h.add_child(_cell(str(r["pts"]), 34, UI.GOLD, true))
		h.add_child(_cell("%+.3f" % r["nrr"], 58, UI.MUTED))
		v.add_child(p)
	v.add_child(UI.caption("Top 4 qualify for the playoffs", UI.DIM, 10))
	return v


func _matches(list: Array, newest_first: bool) -> Control:
	var v := UI.vbox(8)
	var arr := list.duplicate()
	if newest_first:
		arr.reverse()
	var my := Game.store.my_team()
	for m in arr:
		var mine: bool = m["a"] == my or m["b"] == my
		var p := _row_panel(mine)
		var mv := UI.vbox(4)
		p.add_child(mv)
		mv.add_child(UI.caption(m["stage"], UI.GOLD if m["stage"] == "Final" else UI.MUTED, 10))
		mv.add_child(_score_line(m["first"], m["s1"], m["winner"] == m["first"]))
		mv.add_child(_score_line(m["second"], m["s2"], m["winner"] == m["second"]))
		mv.add_child(UI.label("%s won %s  •  Player of the match: %s" % [DB.team_short(m["winner"]), m["margin"], DB.player(m["pom"]).get("name", "-")], 12, UI.MUTED))
		var details := UI.vbox(2)
		details.visible = false
		var toggle := func():
			if details.get_child_count() == 0:
				_fill_scorecard(details, m)
			details.visible = not details.visible
		var btn := UI.button("Scorecard ▾", toggle, "ghost", 13)
		btn.custom_minimum_size.y = 34
		mv.add_child(btn)
		mv.add_child(details)
		v.add_child(p)
	if arr.is_empty():
		v.add_child(UI.label("No playoffs — not enough teams.", 14, UI.MUTED))
	return v


func _score_line(tid: String, score: String, won: bool) -> Control:
	var h := UI.hbox(8)
	h.add_child(UI.crest(tid, 30))
	var n := UI.label(DB.team(tid).get("name", tid), 14, UI.TEXT if won else UI.MUTED, won)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	h.add_child(n)
	h.add_child(UI.display(score, 22, UI.GOLD if won else UI.MUTED))
	return h


func _fill_scorecard(v: VBoxContainer, m: Dictionary) -> void:
	for pair in [[m["first"], m["i1"]], [m["second"], m["i2"]]]:
		v.add_child(UI.hline())
		v.add_child(UI.caption("%s innings  •  %s" % [DB.team_short(pair[0]), Sim.score_str(pair[1])], UI.GOLD, 11))
		for c in pair[1]["bat"]:
			var h := UI.hbox(4)
			var n := UI.label(DB.player(c["id"])["name"] + ("" if c["out"] else " *"), 13)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(n)
			h.add_child(_cell("%d (%d)" % [c["r"], c["b"]], 74, UI.TEXT if c["r"] >= 30 else UI.MUTED))
			v.add_child(h)
		for b in pair[1]["bowl"]:
			var h2 := UI.hbox(4)
			var n2 := UI.label("   " + DB.player(b["id"])["name"], 12, UI.MUTED)
			n2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h2.add_child(n2)
			h2.add_child(_cell("%s–%d–%d" % [Sim.overs_str(b["balls"]), b["r"], b["w"]], 80, UI.MUTED))
			v.add_child(h2)


func _ratings() -> Control:
	var v := UI.vbox(8)
	var my := Game.store.my_team()
	var rows: Array = res["leaderboard"]
	for i in rows.size():
		var r: Dictionary = rows[i]
		var p := _row_panel(r["team"] == my)
		var pv := UI.vbox(4)
		p.add_child(pv)
		var h := UI.hbox(8)
		h.add_child(UI.display("#%d" % (i + 1), 24, UI.DIM))
		h.add_child(UI.crest(r["team"], 34))
		var n := UI.label(DB.team(r["team"])["name"], 14, UI.TEXT, true)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		h.add_child(n)
		h.add_child(UI.display("%.1f" % r["total"], 28, UI.GOLD))
		h.add_child(UI.chip(r["grade"], Color(UI.GOLD, 0.2), UI.GOLD, 13))
		pv.add_child(h)
		pv.add_child(UI.caption("Bat %.0f  •  Bowl %.0f  •  Balance %+.0f  •  Depth %.0f  •  Value %.1f" % [
			r["batting"], r["bowling"], r["balance"], r["depth"], r["value"]], UI.MUTED, 10))
		if not r["notes"].is_empty():
			pv.add_child(UI.wrap(UI.label("⚠ " + ", ".join(r["notes"]), 12, UI.RED.lightened(0.25))))
		v.add_child(p)
	return v


func _squads() -> Control:
	var v := UI.vbox(8)
	var s := Game.store
	var teams: Dictionary = s.state.get("teams", {})
	var xis := Game._xis()
	for tid in DB.team_ids():
		if not teams.has(tid):
			continue
		var t: Dictionary = teams[tid]
		var p := _row_panel(tid == s.my_team())
		var pv := UI.vbox(4)
		p.add_child(pv)
		var h := UI.hbox(8)
		h.add_child(UI.crest(tid, 34))
		var who := s.team_owner_name(tid)
		var n := UI.label(DB.team(tid)["name"] + ("" if who == "" else "  (%s)" % who), 14, UI.TEXT, true)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		h.add_child(n)
		h.add_child(UI.caption("Left " + DB.fmt_price(int(t.get("purse", 0))), UI.GOLD, 10))
		pv.add_child(h)
		var names := []
		for pid in xis.get(tid, []):
			names.append(DB.player(pid)["name"])
		pv.add_child(UI.wrap(UI.label(", ".join(names), 12, UI.MUTED)))
		v.add_child(p)
	return v


func _confetti(parent: Control) -> void:
	var p := CPUParticles2D.new()
	p.amount = 120
	p.lifetime = 3.0
	p.one_shot = true
	p.explosiveness = 0.9
	p.direction = Vector2(0, -1)
	p.spread = 75
	p.initial_velocity_min = 260
	p.initial_velocity_max = 520
	p.gravity = Vector2(0, 520)
	p.scale_amount_min = 4
	p.scale_amount_max = 9
	var g := Gradient.new()
	g.set_color(0, UI.GOLD)
	g.set_color(1, UI.team_accent(Game.store.my_team()))
	p.color_initial_ramp = g
	parent.add_child(p)
	p.position = Vector2(get_viewport_rect().size.x / 2.0 - 16, 60)
	p.emitting = true
