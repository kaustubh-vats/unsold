class_name Views
extends RefCounted
## Shared building blocks for squads, teams and scorecards, used by the
## auction, squad review and results screens (usually inside a Sheet).

const ROLE_TITLES := {"WK": "Wicket-keepers", "BAT": "Batters", "AR": "All-rounders", "PACE": "Pace bowlers", "SPIN": "Spinners"}
const ROLES := ["WK", "BAT", "AR", "PACE", "SPIN"]


# ------------------------------------------------------------------ basics

static func tap_panel(style: StyleBoxFlat, cb: Callable) -> PanelContainer:
	return UI.tap_panel(style, cb)


static func fill_tap(p: PanelContainer, content: Control) -> PanelContainer:
	return UI.fill_tap(p, content)


static func purse_bar(value: int) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = Rules.PURSE
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 6)
	pb.add_theme_stylebox_override("fill", UI.box(UI.GOLD, 3, 0))
	pb.add_theme_stylebox_override("background", UI.box(UI.ink(0.08), 3, 0))
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb


static func need_chip(role: String, have: int, want: int, size := 11) -> Control:
	var ok := have >= want
	return UI.chip("%s %d/%d" % [role, have, want], Color(UI.GREEN, 0.16) if ok else UI.ink(0.06),
		UI.GREEN if ok else UI.MUTED, size)


static func section(text: String, right := "") -> Control:
	var h := UI.hbox(6)
	var c := UI.caption(text, UI.GOLD, 11)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	if right != "":
		h.add_child(UI.caption(right, UI.MUTED, 10))
	return h


## One player: role icon, name, ratings, OVR, price. Optional team crest,
## an XI badge, and a stats line (e.g. season numbers).
static func player_row(pid: String, price: int, tid := "", opts := {}) -> Control:
	var p := DB.player(pid)
	var in_xi: bool = opts.get("xi", false)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UI.box(Color(UI.GREEN, 0.08) if in_xi else UI.ink(0.04), 12, 10,
		Color(UI.GREEN, 0.35) if in_xi else Color(0, 0, 0, 0)))
	var h := UI.hbox(10)
	row.add_child(h)
	if opts.has("num"):
		var nl := UI.display(str(opts["num"]), 20, UI.DIM)
		nl.custom_minimum_size.x = 20
		h.add_child(nl)
	if tid != "":
		h.add_child(UI.crest(tid, 28))
	h.add_child(UI.role_icon(p["role"], 28))
	var nv := UI.vbox(-2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := UI.label(p["name"] + ("  ✈" if p["overseas"] else ""), 14, UI.TEXT, true)
	n.clip_text = true
	nv.add_child(n)
	var sub: String = opts.get("line", "%s  •  BAT %d  •  BOWL %d" % [DB.role_label(p["role"]), p["bat"], p["bowl"]])
	var sl := UI.caption(sub, UI.DIM, 9)
	sl.clip_text = true
	nv.add_child(sl)
	h.add_child(nv)
	h.add_child(UI.display(str(p["ovr"]), 22, UI.GOLD if in_xi else UI.MUTED))
	if opts.has("tag"):
		var tg := UI.display(str(opts["tag"][0]), 20, opts["tag"][1])
		tg.custom_minimum_size.x = 80
		tg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(tg)
	elif price >= 0:
		var pr := UI.display(DB.fmt_price(price) if price > 0 else "UNSOLD", 20, UI.GOLD if price > 0 else UI.RED)
		pr.custom_minimum_size.x = 80
		pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(pr)
	return row


# ------------------------------------------------------------------ teams

## A team's page. opts: xi (Array, shows the playing XI first), xi_title,
## stats (season stats {pid: {...}}), rating (Score.rate dict).
static func team_page(body: VBoxContainer, tid: String, opts := {}) -> void:
	var s := Game.store
	var t := s.team(tid)
	var squad: Dictionary = t.get("squad", {})
	var purse := int(t.get("purse", 0))
	var hero := UI.panel(UI.shade(UI.team_color(tid), 0.55, 0.85), 18, 14, Color(UI.team_accent(tid), 0.5))
	var hv := UI.vbox(10)
	hero.add_child(hv)
	var top := UI.hbox(12)
	top.add_child(UI.crest(tid, 60))
	var nv := UI.vbox(0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(UI.wrap(UI.display(DB.team(tid).get("name", ""), 26, UI.TEXT)))
	var who := "You" if tid == s.my_team() else ("AI franchise" if t.get("ai", false) else s.team_owner_name(tid))
	nv.add_child(UI.caption(who, UI.GOLD, 10))
	top.add_child(nv)
	var rating: Dictionary = opts.get("rating", {})
	if not rating.is_empty():
		var rv := UI.vbox(-4)
		rv.add_child(UI.caption("Rating", UI.MUTED, 9))
		rv.add_child(UI.display("%.0f" % rating["total"], 30, UI.GOLD))
		rv.add_child(UI.chip(rating["grade"], Color(UI.GOLD, 0.2), UI.GOLD, 11))
		top.add_child(rv)
	hv.add_child(top)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	var xi: Array = opts.get("xi", [])
	var xi_src: Array = xi if not xi.is_empty() else (XI.best_xi(squad.keys()) if squad.size() >= 11 else [])
	var xi_txt := "—"
	if not xi_src.is_empty():
		var tot := 0
		for pid in xi_src:
			tot += int(DB.player(pid)["ovr"])
		xi_txt = str(roundi(float(tot) / xi_src.size()))
	for cell in [["Purse left", DB.fmt_price(purse), UI.GOLD], ["Spent", DB.fmt_price(Rules.PURSE - purse), UI.TEXT],
			["Max bid", DB.fmt_price(maxi(0, Rules.max_affordable(t))), UI.TEXT],
			["Squad", "%d/%d" % [squad.size(), Rules.MAX_SQUAD], UI.GREEN if squad.size() >= Rules.MIN_SQUAD else UI.TEXT],
			["Overseas", "%d/%d" % [Rules.overseas_count(t), Rules.MAX_OVERSEAS], UI.TEXT],
			["XI avg OVR", xi_txt, UI.TEXT]]:
		var cv := UI.vbox(-4)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(UI.caption(cell[0], UI.MUTED, 9))
		cv.add_child(UI.display(cell[1], 24, cell[2]))
		grid.add_child(cv)
	hv.add_child(grid)
	hv.add_child(purse_bar(purse))
	if not rating.is_empty():
		hv.add_child(UI.caption("Bat %.0f  •  Bowl %.0f  •  Balance %+.0f  •  Depth %.0f" % [
			rating["batting"], rating["bowling"], rating["balance"], rating["depth"]], UI.MUTED, 10))
		if not rating["notes"].is_empty():
			hv.add_child(UI.wrap(UI.label("⚠ " + ", ".join(rating["notes"]), 12, UI.soft(UI.RED, 0.25))))
	var short := Rules.MIN_SQUAD - squad.size()
	if short > 0 and xi.is_empty():
		hv.add_child(UI.label("Needs %d more player%s to reach the minimum of %d." % [short, "" if short == 1 else "s", Rules.MIN_SQUAD], 12, UI.MUTED))
	body.add_child(hero)
	body.add_child(UI.caption("Role balance (have / ideal)", UI.MUTED, 10))
	var counts := AI.role_counts(t)
	var needs := HFlowContainer.new()
	needs.add_theme_constant_override("h_separation", 6)
	needs.add_theme_constant_override("v_separation", 6)
	for r in ROLES:
		needs.add_child(need_chip(r, counts[r], AI.TARGET[r], 12))
	body.add_child(needs)
	if squad.is_empty():
		body.add_child(UI.spacer(10, 0))
		body.add_child(UI.center(UI.label("No players bought yet.", 15, UI.MUTED)))
		return
	var stats: Dictionary = opts.get("stats", {})
	var line_for := func(pid: String) -> String:
		if not stats.has(pid):
			var p := DB.player(pid)
			return "%s  •  BAT %d  •  BOWL %d" % [DB.role_label(p["role"]), p["bat"], p["bowl"]]
		return stat_line(stats[pid])
	# Playing XI in batting order, then the bench grouped by role.
	if not xi.is_empty():
		body.add_child(UI.spacer(4, 0))
		body.add_child(section(opts.get("xi_title", "PLAYING XI"), "batting order"))
		var n := 1
		for pid in xi:
			body.add_child(player_row(pid, int(squad.get(pid, 0)), "", {"xi": true, "num": n, "line": line_for.call(pid)}))
			n += 1
	for role in ROLES:
		var ids := []
		for pid in squad:
			if DB.player(pid)["role"] == role and not xi.has(pid):
				ids.append(pid)
		if ids.is_empty():
			continue
		ids.sort_custom(func(x, y): return int(squad[x]) > int(squad[y]))
		var sub := 0
		for pid in ids:
			sub += int(squad[pid])
		body.add_child(UI.spacer(4, 0))
		var title: String = ROLE_TITLES[role] if xi.is_empty() else "Bench • " + ROLE_TITLES[role]
		body.add_child(section("%s (%d)" % [title, ids.size()], DB.fmt_price(sub)))
		for pid in ids:
			body.add_child(player_row(pid, int(squad[pid]), "", {"line": line_for.call(pid)}))


## Compact season numbers for a player row.
static func stat_line(st: Dictionary) -> String:
	var parts := []
	if int(st["inn"]) > 0:
		var outs := int(st["inn"]) - int(st["no"])
		var avg := "%.1f" % (float(st["r"]) / outs) if outs > 0 else "-"
		parts.append("%d runs (avg %s, SR %.0f)" % [st["r"], avg, 100.0 * st["r"] / maxf(1.0, st["b"])])
	if int(st["bb"]) > 0:
		parts.append("%d wkts (econ %.1f)" % [st["wk"], float(st["rc"]) / (float(st["bb"]) / 6.0)])
	if parts.is_empty():
		return "%d match%s" % [st["m"], "" if int(st["m"]) == 1 else "es"]
	return "  •  ".join(parts)


## All franchises as tappable cards. sort: "purse" (richest first) or "rating".
static func teams_list(body: VBoxContainer, on_open: Callable, sort := "purse") -> void:
	var s := Game.store
	var teams: Dictionary = s.state.get("teams", {})
	var ids := []
	for tid in DB.team_ids():
		if teams.has(tid):
			ids.append(tid)
	var ratings := {}
	if sort == "rating":
		var xis := Game._xis()
		for tid in ids:
			ratings[tid] = Score.rate(teams[tid], xis.get(tid, []))
		ids.sort_custom(func(a, b): return ratings[a]["total"] > ratings[b]["total"])
	else:
		ids.sort_custom(func(a, b): return int(teams[a].get("purse", 0)) > int(teams[b].get("purse", 0)))
	for tid in ids:
		var t: Dictionary = teams[tid]
		var is_me: bool = tid == s.my_team()
		var st := UI.box(UI.shade(UI.team_color(tid), 0.6, 0.7), 16, 12, UI.GREEN if is_me else Color(UI.team_accent(tid), 0.35), 2 if is_me else 1)
		var card := tap_panel(st, func(): on_open.call(tid))
		var v := UI.vbox(6)
		var h := UI.hbox(10)
		h.add_child(UI.crest(tid, 40))
		var nv := UI.vbox(-2)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nl := UI.label(DB.team(tid)["name"], 15, UI.TEXT, true)
		nl.clip_text = true
		nv.add_child(nl)
		var who := "YOU" if is_me else ("AI" if t.get("ai", false) else s.team_owner_name(tid))
		var cnt := Rules.squad_count(t)
		nv.add_child(UI.caption("%s  •  %d player%s  •  %d/%d overseas" % [who, cnt, "" if cnt == 1 else "s", Rules.overseas_count(t), Rules.MAX_OVERSEAS], UI.MUTED, 9))
		h.add_child(nv)
		var pv := UI.vbox(-4)
		if sort == "rating":
			pv.add_child(UI.caption("Rating", UI.DIM, 9))
			pv.add_child(UI.display("%.0f %s" % [ratings[tid]["total"], ratings[tid]["grade"]], 24, UI.GOLD))
		else:
			pv.add_child(UI.caption("Purse", UI.DIM, 9))
			pv.add_child(UI.display(DB.fmt_price(int(t.get("purse", 0))), 24, UI.GOLD))
		h.add_child(pv)
		v.add_child(h)
		v.add_child(purse_bar(int(t.get("purse", 0))))
		var sq: Dictionary = t.get("squad", {})
		if not sq.is_empty():
			var top_ids: Array = sq.keys()
			top_ids.sort_custom(func(x, y): return int(sq[x]) > int(sq[y]))
			var names := []
			for pid in top_ids.slice(0, 3):
				names.append("%s %s" % [DB.player(pid)["name"], DB.fmt_price(int(sq[pid]))])
			v.add_child(UI.wrap(UI.label("Top buys: " + ", ".join(names), 12, UI.MUTED)))
		body.add_child(fill_tap(card, v))


# ------------------------------------------------------------------ matches

## A one-glance result card; tapping opens the scorecard.
static func match_card(m: Dictionary, my: String, on_open: Callable) -> Control:
	var mine: bool = m["a"] == my or m["b"] == my
	var won: bool = m["winner"] == my
	var border := (UI.GREEN if won else UI.soft(UI.RED, 0.2)) if mine else Color(0, 0, 0, 0)
	var st := UI.box(Color(UI.GOLD, 0.06) if mine else UI.ink(0.035), 14, 12, border)
	var card := tap_panel(st, func(): on_open.call(m))
	var v := UI.vbox(4)
	var top := UI.hbox(6)
	var stage := UI.caption(m["stage"], UI.GOLD if m["stage"] in ["Final", "Qualifier 1", "Qualifier 2", "Eliminator"] else UI.MUTED, 10)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(stage)
	top.add_child(UI.caption(DB.team(m["home"]).get("city", ""), UI.DIM, 9))
	v.add_child(top)
	v.add_child(_score_line(m["first"], m["s1"], m["winner"] == m["first"]))
	v.add_child(_score_line(m["second"], m["s2"], m["winner"] == m["second"]))
	var res := UI.label("%s won %s" % [DB.team_short(m["winner"]), m["margin"]], 12, UI.GOLD, true)
	res.clip_text = true
	v.add_child(res)
	var foot := UI.hbox(6)
	var pom := UI.caption("★ " + DB.player(m["pom"]).get("name", "-"), UI.MUTED, 9)
	pom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pom.clip_text = true
	foot.add_child(pom)
	foot.add_child(UI.caption("SCORECARD ›", UI.GOLD, 9))
	v.add_child(foot)
	return fill_tap(card, v)


static func _score_line(tid: String, score: String, won: bool) -> Control:
	var h := UI.hbox(8)
	h.add_child(UI.crest(tid, 28))
	var n := UI.label(DB.team(tid).get("name", tid), 14, UI.TEXT if won else UI.MUTED, won)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	h.add_child(n)
	h.add_child(UI.display(score, 22, UI.GOLD if won else UI.MUTED))
	return h


static func _cell(text: String, w: int, color := UI.TEXT, bold := false) -> Label:
	var l := UI.label(text, 13, color, bold)
	l.custom_minimum_size.x = w
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func _head_row(first: String, cols: Array, widths: Array) -> Control:
	var h := UI.hbox(2)
	var f := UI.caption(first, UI.DIM, 9)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(f)
	for i in cols.size():
		var c := UI.caption(cols[i], UI.DIM, 9)
		c.custom_minimum_size.x = widths[i]
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(c)
	return h


## Full scorecard: header, runs-per-over chart, both innings (batting with
## dismissals, extras, total, did not bat, fall of wickets, bowling), Super Overs.
static func scorecard(body: VBoxContainer, m: Dictionary) -> void:
	var head := UI.panel(UI.GLASS, 16, 14, UI.LINE)
	var hv := UI.vbox(6)
	head.add_child(hv)
	var venue := "%s  •  %s" % [DB.team(m["home"]).get("city", ""), Sim.PITCHES[m["pitch"]]["name"]]
	if m.get("dew", false):
		venue += "  •  dew"
	hv.add_child(UI.caption(m["stage"] + "  •  " + venue, UI.MUTED, 10))
	hv.add_child(_score_line(m["first"], m["s1"], m["winner"] == m["first"]))
	hv.add_child(_score_line(m["second"], m["s2"], m["winner"] == m["second"]))
	hv.add_child(UI.wrap(UI.label(Sim.result_str(m), 15, UI.GOLD, true)))
	hv.add_child(UI.caption(Sim.toss_str(m), UI.MUTED, 10))
	var pom := UI.hbox(6)
	pom.add_child(UI.chip("PLAYER OF THE MATCH", Color(UI.GOLD, 0.18), UI.GOLD, 9))
	var pn := UI.label(DB.player(m["pom"]).get("name", "-"), 13, UI.TEXT, true)
	pom.add_child(pn)
	hv.add_child(pom)
	body.add_child(head)
	# Runs per over.
	body.add_child(section("RUNS PER OVER", "● wicket"))
	var chart := OverChart.new().setup([
		{"runs": m["i1"]["overs"], "wkts": m["i1"]["over_wkts"], "color": UI.team_accent(m["first"])},
		{"runs": m["i2"]["overs"], "wkts": m["i2"]["over_wkts"], "color": Color(UI.team_accent(m["second"]), 0.75)},
	])
	body.add_child(chart)
	var legend := UI.hbox(12)
	for side in [[m["first"], m["i1"]], [m["second"], m["i2"]]]:
		legend.add_child(UI.chip("%s %s" % [DB.team_short(side[0]), Sim.score_str(side[1])], Color(UI.team_accent(side[0]), 0.25), UI.TEXT, 10))
	body.add_child(legend)
	innings_card(body, m["first"], m["second"], m["i1"], "1st innings")
	innings_card(body, m["second"], m["first"], m["i2"], "2nd innings  •  target %d" % (int(m["i1"]["runs"]) + 1))
	var k := 1
	for so in m.get("supers", []):
		body.add_child(UI.spacer(6, 0))
		body.add_child(section("SUPER OVER %s" % ("" if m["supers"].size() == 1 else str(k))))
		for side in [[so["first"], so["second"], so["i1"]], [so["second"], so["first"], so["i2"]]]:
			var inn: Dictionary = side[2]
			var line := UI.hbox(6)
			line.add_child(UI.crest(side[0], 24))
			var bats := []
			for c in inn["bat"]:
				bats.append("%s %d(%d)" % [DB.player(c["id"])["name"], c["r"], c["b"]])
			var bl := UI.wrap(UI.label("%s  —  %s" % [Sim.score_str(inn), ", ".join(bats)], 12, UI.TEXT))
			bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(bl)
			body.add_child(line)
			if not inn["bowl"].is_empty():
				var bw: Dictionary = inn["bowl"][0]
				body.add_child(UI.caption("    %s  %d-%d" % [DB.player(bw["id"])["name"], bw["r"], bw["w"]], UI.MUTED, 10))
		k += 1


static func innings_card(body: VBoxContainer, bat_t: String, bowl_t: String, inn: Dictionary, label: String) -> void:
	body.add_child(UI.spacer(6, 0))
	var bar := UI.panel(UI.shade(UI.team_color(bat_t), 0.5, 0.8), 12, 10, Color(UI.team_accent(bat_t), 0.4))
	var bh := UI.hbox(8)
	bar.add_child(bh)
	bh.add_child(UI.crest(bat_t, 30))
	var bv := UI.vbox(-2)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.add_child(UI.label(DB.team(bat_t).get("name", ""), 14, UI.TEXT, true))
	bv.add_child(UI.caption(label, UI.MUTED, 9))
	bh.add_child(bv)
	bh.add_child(UI.display(Sim.score_str(inn), 26, UI.GOLD))
	body.add_child(bar)
	# Batting.
	var bw := [34, 30, 26, 26, 44]
	body.add_child(_head_row("BATTER", ["R", "B", "4s", "6s", "SR"], bw))
	for c in inn["bat"]:
		var row := UI.hbox(2)
		var nv := UI.vbox(-3)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var big: bool = int(c["r"]) >= 50
		var nm := UI.label(DB.player(c["id"]).get("name", "?") + ("" if c["out"] else " *"), 13, UI.GOLD if big else UI.TEXT, true)
		nm.clip_text = true
		nv.add_child(nm)
		var how := UI.caption(Sim.how_str(c), UI.GREEN if not c["out"] else UI.DIM, 9)
		how.clip_text = true
		nv.add_child(how)
		row.add_child(nv)
		var sr: float = 100.0 * c["r"] / maxf(1.0, c["b"])
		row.add_child(_cell(str(c["r"]), bw[0], UI.GOLD if big else UI.TEXT, true))
		row.add_child(_cell(str(c["b"]), bw[1], UI.MUTED))
		row.add_child(_cell(str(c["4s"]), bw[2], UI.MUTED))
		row.add_child(_cell(str(c["6s"]), bw[3], UI.MUTED))
		row.add_child(_cell("%.1f" % sr if int(c["b"]) > 0 else "-", bw[4], UI.MUTED))
		body.add_child(row)
	var ex: Dictionary = inn["extras"]
	var ex_tot := int(ex["b"]) + int(ex["lb"]) + int(ex["w"]) + int(ex["nb"])
	var exr := UI.hbox(4)
	var el := UI.label("Extras  (b %d, lb %d, w %d, nb %d)" % [ex["b"], ex["lb"], ex["w"], ex["nb"]], 12, UI.MUTED)
	el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exr.add_child(el)
	exr.add_child(_cell(str(ex_tot), 40, UI.TEXT, true))
	body.add_child(exr)
	var tr := UI.hbox(4)
	var rr := float(inn["runs"]) / maxf(1.0, float(inn["balls"]) / 6.0)
	var tl := UI.label("TOTAL  (%s ov, RR %.2f)" % [Sim.overs_str(inn["balls"]), rr], 13, UI.TEXT, true)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(tl)
	var tot_txt := ("%d ALL OUT" % inn["runs"]) if inn["all_out"] else ("%d/%d" % [inn["runs"], inn["wkts"]])
	tr.add_child(UI.display(tot_txt, 22, UI.GOLD))
	body.add_child(tr)
	if not inn["dnb"].is_empty():
		var names := []
		for pid in inn["dnb"]:
			names.append(DB.player(pid).get("name", "?"))
		body.add_child(UI.wrap(UI.label("Did not bat: " + ", ".join(names), 12, UI.MUTED)))
	if not inn["fow"].is_empty():
		var f := []
		for w in inn["fow"]:
			f.append("%d-%d (%s, %s)" % [w["w"], w["r"], Sim._surname(w["id"]), w["o"]])
		body.add_child(UI.caption("Fall of wickets", UI.DIM, 9))
		body.add_child(UI.wrap(UI.label(", ".join(f), 12, UI.MUTED)))
	# Bowling.
	body.add_child(UI.spacer(2, 0))
	var ow := [34, 24, 30, 26, 44]
	body.add_child(_head_row("BOWLER  •  " + DB.team_short(bowl_t), ["O", "M", "R", "W", "ECON"], ow))
	for b in inn["bowl"]:
		var row2 := UI.hbox(2)
		var nv2 := UI.vbox(-3)
		nv2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var good: bool = int(b["w"]) >= 3
		var nm2 := UI.label(DB.player(b["id"]).get("name", "?"), 13, UI.GOLD if good else UI.TEXT, true)
		nm2.clip_text = true
		nv2.add_child(nm2)
		var extra_bits := []
		if int(b["wd"]) > 0:
			extra_bits.append("%d wd" % b["wd"])
		if int(b["nb"]) > 0:
			extra_bits.append("%d nb" % b["nb"])
		extra_bits.append("%d dots" % b["dots"])
		nv2.add_child(UI.caption(", ".join(extra_bits), UI.DIM, 9))
		row2.add_child(nv2)
		var econ := float(b["r"]) / maxf(0.1, float(b["balls"]) / 6.0)
		row2.add_child(_cell(Sim.overs_str(b["balls"]), ow[0], UI.MUTED))
		row2.add_child(_cell(str(b["m"]), ow[1], UI.MUTED))
		row2.add_child(_cell(str(b["r"]), ow[2], UI.TEXT))
		row2.add_child(_cell(str(b["w"]), ow[3], UI.GOLD if good else UI.TEXT, true))
		row2.add_child(_cell("%.2f" % econ, ow[4], UI.MUTED))
		body.add_child(row2)


# ------------------------------------------------------------------ season leaders

## Orange/purple cap, MVP, sixes, best innings and figures. on_match(idx) opens a match.
static func season_leaders(body: VBoxContainer, stats: Dictionary, on_match: Callable) -> void:
	var P: Dictionary = stats["players"]
	var board := func(title: String, color: Color, ids: Array, value: Callable, sub: Callable) -> void:
		body.add_child(UI.spacer(4, 0))
		body.add_child(section(title))
		var i := 0
		for pid in ids:
			var s: Dictionary = P[pid]
			var row := PanelContainer.new()
			row.add_theme_stylebox_override("panel", UI.box(Color(color, 0.14) if i == 0 else UI.ink(0.04), 12, 10,
				Color(color, 0.6) if i == 0 else Color(0, 0, 0, 0)))
			var h := UI.hbox(10)
			row.add_child(h)
			h.add_child(UI.display(str(i + 1), 20, color if i == 0 else UI.DIM))
			h.add_child(UI.crest(s["team"], 28))
			var nv := UI.vbox(-2)
			nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var nl := UI.label(DB.player(pid).get("name", "?"), 14, UI.TEXT, true)
			nl.clip_text = true
			nv.add_child(nl)
			var sl := UI.caption(sub.call(s), UI.DIM, 9)
			sl.clip_text = true
			nv.add_child(sl)
			h.add_child(nv)
			h.add_child(UI.display(value.call(s), 26, color if i == 0 else UI.TEXT))
			body.add_child(row)
			i += 1
	board.call("ORANGE CAP  •  MOST RUNS", Color("ff8a1f"), stats["orange"],
		func(s): return str(s["r"]),
		func(s):
			var outs: int = int(s["inn"]) - int(s["no"])
			return "%d inns  •  avg %s  •  SR %.1f  •  HS %d%s" % [s["inn"], ("%.1f" % (float(s["r"]) / outs)) if outs > 0 else "-",
				100.0 * s["r"] / maxf(1.0, s["b"]), s["hs"], "*" if s["hs_no"] else ""])
	board.call("PURPLE CAP  •  MOST WICKETS", Color("a46bff"), stats["purple"],
		func(s): return str(s["wk"]),
		func(s): return "%s overs  •  econ %.2f  •  best %d/%d" % [Sim.overs_str(s["bb"]), float(s["rc"]) / maxf(0.1, float(s["bb"]) / 6.0), s["best_w"], s["best_r"]])
	board.call("MOST VALUABLE PLAYER", UI.GOLD, stats["mvp"],
		func(s): return "%.1f" % s["mvp"],
		func(s): return "%d runs  •  %d wkts  •  %d catches" % [s["r"], s["wk"], s["ct"]])
	board.call("MOST SIXES", UI.BLUE, stats["sixes"],
		func(s): return str(s["6s"]),
		func(s): return "%d runs  •  %d fours" % [s["r"], s["4s"]])
	body.add_child(UI.spacer(4, 0))
	body.add_child(section("BEST INNINGS", "tap for scorecard"))
	for e in stats["best_inns"]:
		body.add_child(_feat_row(e["team"], DB.player(e["id"]).get("name", "?"), "vs %s" % DB.team_short(e["vs"]),
			"%d%s (%d)" % [e["r"], "" if e["out"] else "*", e["b"]], func(): on_match.call(int(e["m"]))))
	body.add_child(UI.spacer(4, 0))
	body.add_child(section("BEST BOWLING", "tap for scorecard"))
	for e in stats["best_figs"]:
		body.add_child(_feat_row(e["team"], DB.player(e["id"]).get("name", "?"), "vs %s  •  %s ov" % [DB.team_short(e["vs"]), Sim.overs_str(e["balls"])],
			"%d/%d" % [e["w"], e["r"]], func(): on_match.call(int(e["m"]))))


static func _feat_row(tid: String, name: String, sub: String, value: String, cb: Callable) -> Control:
	var card := tap_panel(UI.box(UI.ink(0.04), 12, 10), cb)
	var h := UI.hbox(10)
	h.add_child(UI.crest(tid, 28))
	var nv := UI.vbox(-2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nl := UI.label(name, 14, UI.TEXT, true)
	nl.clip_text = true
	nv.add_child(nl)
	nv.add_child(UI.caption(sub, UI.DIM, 9))
	h.add_child(nv)
	h.add_child(UI.display(value, 24, UI.GOLD))
	return fill_tap(card, h)
