extends VBoxContainer
## The live auction, styled like a TV broadcast: player card, bid panel tinted in
## the leading team's colours, countdown ring, team purses, squad/log tabs.

const TimerRing := preload("res://scripts/ui/timer_ring.gd")
const TRAITS := {"op": "OPENER", "fin": "FINISHER", "pp": "POWERPLAY", "dth": "DEATH OVERS", "anc": "ANCHOR"}

var set_label: Label
var lot_label: Label
var head_purse: Label
var card: PanelContainer
var role_holder: HBoxContainer
var p_name: Label
var p_meta: Label
var p_chips: HBoxContainer
var p_ovr: Label
var p_bars: VBoxContainer
var p_base: Label
var stamp: PanelContainer
var stamp_box: VBoxContainer
var bid_panel: PanelContainer
var ring: Control
var bid_caption: Label
var bid_amount: Label
var bid_team_box: HBoxContainer
var call_label: Label
var bid_btn: Button
var pass_btn: Button
var stat_labels := {}
var status_label: Label
var strip: HBoxContainer
var tabs: TabContainer
var squad_list: VBoxContainer
var log_list: VBoxContainer
var teams_list: VBoxContainer

var _lot_key := ""
var _phase := ""
var _list_sig := ""
var _busy := false
var _last_n := -1
var _last_bidder := ""
var _last_tick := -1
var _going_said := ""
var _prompt := ""
var say_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build_header()
	_build_card()
	_build_bid_panel()
	_build_actions()
	_build_strip()
	_build_tabs()
	Game.store.changed.connect(_refresh)
	_refresh()


# ------------------------------------------------------------------ build

func _build_header() -> void:
	var s := Game.store
	var head := UI.hbox(10)
	head.add_child(UI.button("✕", _leave, "icon"))
	var hv := UI.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_label = UI.caption("", UI.GOLD, 12)
	lot_label = UI.display("", 22, UI.TEXT)
	hv.add_child(set_label)
	hv.add_child(lot_label)
	head.add_child(hv)
	var mine := UI.hbox(8)
	var mv := UI.vbox(0)
	mv.add_child(UI.caption("Your purse", UI.MUTED, 10))
	head_purse = UI.display("", 26, UI.GOLD)
	head_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mv.add_child(head_purse)
	mine.add_child(mv)
	mine.add_child(UI.crest(s.my_team(), 46))
	head.add_child(mine)
	head.add_child(UI.sound_button())
	add_child(head)


func _build_card() -> void:
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.glow(UI.box(UI.GLASS, 22, 16, Color(UI.GOLD, 0.25)), Color(0, 0, 0, 0.35), 16))
	var cv := UI.vbox(10)
	card.add_child(cv)
	var top := UI.hbox(14)
	role_holder = UI.hbox(0)
	top.add_child(role_holder)
	var nv := UI.vbox(2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_meta = UI.caption("", UI.MUTED, 11)
	nv.add_child(p_meta)
	p_name = UI.display("", 42, UI.TEXT)
	p_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(p_name)
	p_chips = UI.hbox(6)
	nv.add_child(p_chips)
	top.add_child(nv)
	var ov := UI.vbox(-6)
	p_ovr = UI.display("", 56, UI.GOLD)
	p_ovr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov.add_child(p_ovr)
	ov.add_child(UI.center(UI.caption("OVR", UI.GOLD, 11)))
	top.add_child(ov)
	cv.add_child(top)
	p_bars = UI.vbox(6)
	cv.add_child(p_bars)
	var base_row := UI.hbox(8)
	base_row.add_child(UI.caption("Base price", UI.MUTED, 11))
	p_base = UI.display("", 22, UI.TEXT)
	base_row.add_child(p_base)
	cv.add_child(base_row)
	# SOLD / UNSOLD overlay.
	stamp = PanelContainer.new()
	stamp.add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.04, 0.08, 0.86), 22, 10))
	stamp.visible = false
	stamp_box = UI.vbox(2)
	stamp_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stamp.add_child(stamp_box)
	card.add_child(stamp)
	add_child(card)


func _build_bid_panel() -> void:
	bid_panel = PanelContainer.new()
	var bh := UI.hbox(16)
	bid_panel.add_child(bh)
	ring = TimerRing.new()
	ring.custom_minimum_size = Vector2(100, 100)
	bh.add_child(ring)
	var bv := UI.vbox(0)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bid_caption = UI.caption("Current bid", UI.MUTED, 11)
	bv.add_child(bid_caption)
	bid_amount = UI.display("", 58, UI.GOLD)
	bv.add_child(bid_amount)
	bid_team_box = UI.hbox(8)
	bv.add_child(bid_team_box)
	say_label = UI.label("", 12, UI.MUTED)
	say_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(say_label)
	bh.add_child(bv)
	add_child(bid_panel)
	call_label = UI.center(UI.display("", 24, UI.GOLD))
	call_label.custom_minimum_size.y = 26
	add_child(call_label)


func _build_actions() -> void:
	var row := UI.hbox(10)
	bid_btn = UI.button("BID", _bid, "primary", 22)
	bid_btn.custom_minimum_size.y = 64
	bid_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bid_btn.size_flags_stretch_ratio = 2.2
	row.add_child(bid_btn)
	pass_btn = UI.button("PASS", _pass, "ghost", 18)
	pass_btn.custom_minimum_size.y = 64
	pass_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pass_btn)
	add_child(row)
	var stats := UI.hbox(6)
	for k in ["Squad", "Overseas", "Max bid"]:
		var c := UI.vbox(0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := UI.center(UI.display("", 22, UI.TEXT))
		c.add_child(val)
		c.add_child(UI.center(UI.caption(k, UI.DIM, 10)))
		stat_labels[k] = val
		stats.add_child(c)
	add_child(stats)
	status_label = UI.center(UI.label("", 13, UI.RED, true))
	add_child(status_label)


func _build_strip() -> void:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = 92
	strip = UI.hbox(8)
	sc.add_child(strip)
	add_child(sc)


func _build_tabs() -> void:
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size.y = 150
	squad_list = UI.vbox(6)
	log_list = UI.vbox(6)
	teams_list = UI.vbox(8)
	for pair in [["My Squad", squad_list], ["Sold Log", log_list], ["All Teams", teams_list]]:
		var sc := UI.scroll(pair[1])
		sc.name = pair[0]
		tabs.add_child(sc)
	add_child(tabs)


# ------------------------------------------------------------------ per frame

func _leave() -> void:
	Game.leave_room()
	Game.goto("home")


func _process(_dt: float) -> void:
	var s := Game.store
	if s == null or not is_instance_valid(s):
		return
	var a := s.auction()
	var left := maxi(0, int(a.get("ends", 0)) - s.now_ms())
	var total := float(Auction.timer_ms(s.state))
	if a.get("phase", "") != "bidding":
		ring.fraction = 0.0
		ring.text = ""
		call_label.text = ""
		return
	ring.fraction = clampf(left / total, 0.0, 1.0)
	var secs := ceili(left / 1000.0)
	ring.text = str(secs)
	if left <= 3000 and secs != _last_tick and secs > 0:
		_last_tick = secs
		Sfx.play("tick", -6.0)
	var bidder: String = a.get("bidder", "")
	if bidder != "" and left < 3700:
		call_label.text = "GOING TWICE…" if left < 1900 else "GOING ONCE…"
		var key := "%s|%s" % [_lot_key, str(a.get("n", 0))]
		if _going_said != key and left > 3000:
			_going_said = key
			Sfx.say("vo_going", true)
			say_label.text = "“Going once… going twice…”"
	else:
		call_label.text = _prompt


# ------------------------------------------------------------------ state → view

func _refresh() -> void:
	var s := Game.store
	if s == null or not is_instance_valid(s) or s.status() != "auction":
		return
	var a := s.auction()
	var pid: String = a.get("pid", "")
	var p := DB.player(pid)
	if p.is_empty():
		return
	var lots: Array = a.get("lots", [])
	set_label.text = Auction.set_label(Auction.lot_set(s.state)).to_upper()
	lot_label.text = "LOT %d / %d%s" % [int(a.get("idx", 0)) + 1, lots.size(),
		"  •  ROUND 2" if int(a.get("round", 1)) == 2 else ""]
	var key := "%s|%s|%s" % [pid, str(a.get("round", 1)), str(a.get("idx", 0))]
	if key != _lot_key:
		_lot_key = key
		_show_player(p)
		stamp.visible = false
		status_label.text = ""
		_last_n = -1
		_last_bidder = ""
		_announce_open(p)
		card.pivot_offset = card.size / 2.0
		card.modulate.a = 0.0
		card.position.x += 30
		var tw := create_tween().set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.25)

	var bidder: String = a.get("bidder", "")
	var amount := int(a.get("bid", 0))
	var n := int(a.get("n", 0))
	var my := s.my_team()
	if n != _last_n:
		if _last_n >= 0 and n > _last_n:
			if _last_bidder == my and bidder != my:
				Sfx.play("outbid")
			else:
				Sfx.play("bid", -3.0)
			UI.pop(bid_amount, 1.12)
			# A human paddle cuts the auctioneer off mid-sentence; he picks up the new bid.
			_announce_bid(amount, Auction.current_next(s.state), Auction.human_teams(s.state).has(bidder))
		_last_n = n
		_last_bidder = bidder
	bid_caption.text = "CURRENT BID" if bidder != "" else "OPENING AT BASE PRICE"
	bid_amount.text = DB.fmt_price(amount if bidder != "" else int(p["base"])).replace("₹", "₹ ")
	_style_bid_panel(bidder)
	UI.clear(bid_team_box)
	if bidder != "":
		bid_team_box.add_child(UI.crest(bidder, 30))
		var who := s.team_owner_name(bidder)
		var nm := UI.label(DB.team(bidder)["name"], 14, UI.TEXT, true)
		bid_team_box.add_child(nm)
		if who != "":
			bid_team_box.add_child(UI.chip(who.to_upper() if bidder != my else "YOU", Color(UI.GOLD, 0.18), UI.GOLD, 10))
	else:
		bid_team_box.add_child(UI.label("No bids yet", 14, UI.MUTED))

	var phase: String = a.get("phase", "")
	if phase != _phase:
		_phase = phase
		if phase == "sold":
			_show_stamp(true, bidder, amount)
		elif phase == "unsold":
			_show_stamp(false, "", 0)

	var t := s.team(my)
	var next := Auction.current_next(s.state)
	var err := Rules.bid_error(t, p, next)
	var leading := bidder == my
	bid_btn.text = "YOU LEAD" if leading else "BID  %s" % DB.fmt_price(next)
	bid_btn.disabled = phase != "bidding" or leading or err != "" or _busy
	var passed: bool = a.get("passes", {}).has(my)
	pass_btn.text = "PASSED" if passed else "PASS"
	pass_btn.disabled = phase != "bidding" or leading or passed
	status_label.text = err if (err != "" and phase == "bidding" and not leading) else ""
	# Whose turn is it? Spell it out like an auctioneer would.
	if phase != "bidding":
		_prompt = ""
	elif leading:
		_prompt = "YOU LEAD — ANY ADVANCE?"
	elif err != "":
		_prompt = ""
	elif passed:
		_prompt = "YOU PASSED — BID AGAIN TO RE-ENTER"
	elif bidder != "":
		_prompt = "%s BID — YOUR CALL: %s?" % [DB.team_short(bidder), DB.fmt_price(next)]
	else:
		_prompt = "WHO'LL OPEN AT %s?" % DB.fmt_price(next)
	head_purse.text = DB.fmt_price(int(t.get("purse", 0)))
	stat_labels["Squad"].text = "%d/%d" % [Rules.squad_count(t), Rules.MAX_SQUAD]
	stat_labels["Overseas"].text = "%d/%d" % [Rules.overseas_count(t), Rules.MAX_OVERSEAS]
	stat_labels["Max bid"].text = DB.fmt_price(maxi(0, Rules.max_affordable(t)))
	_refresh_strip(bidder)
	var sig := "%d|%d" % [s.state.get("log", {}).size(), Rules.squad_count(t)]
	if sig != _list_sig:
		_list_sig = sig
		_refresh_lists()


func _style_bid_panel(bidder: String) -> void:
	var col := UI.team_color(bidder) if bidder != "" else Color(0.2, 0.22, 0.35)
	var bg := Color(col.darkened(0.45), 0.88)
	var border := UI.team_accent(bidder) if bidder != "" else UI.LINE
	bid_panel.add_theme_stylebox_override("panel",
		UI.glow(UI.box(bg, 22, 16, Color(border, 0.7), 2), Color(border, 0.25 if bidder != "" else 0.0), 14))


func _show_player(p: Dictionary) -> void:
	UI.clear(role_holder)
	role_holder.add_child(UI.role_icon(p["role"], 84))
	p_name.text = p["name"].to_upper()
	p_meta.text = "%s  •  %s  •  %s" % [p["country"], DB.role_label(p["role"]), "Capped" if p["capped"] else "Uncapped"]
	p_ovr.text = str(p["ovr"])
	UI.clear(p_chips)
	if p["overseas"]:
		p_chips.add_child(UI.chip("✈ OVERSEAS", Color(UI.BLUE, 0.25), UI.BLUE.lightened(0.4), 11))
	if TRAITS.has(p["trait"]):
		p_chips.add_child(UI.chip(TRAITS[p["trait"]], Color(UI.GOLD, 0.15), UI.GOLD, 11))
	UI.clear(p_bars)
	p_bars.add_child(UI.rating_bar("BAT", p["bat"], UI.GREEN))
	p_bars.add_child(UI.rating_bar("BOWL", p["bowl"], UI.BLUE))
	p_base.text = DB.fmt_price(int(p["base"]))


# ------------------------------------------------------------------ auctioneer

func _announce_open(p: Dictionary) -> void:
	var base := int(p["base"])
	var line := "open_%d" % base
	var txt := Sfx.line_text(line)
	if txt == "":
		txt = "Next up, base price %s. Who'll open the bidding?" % DB.fmt_price(base)
	say_label.text = "“%s”" % txt
	# Let the SOLD call finish before the next lot is introduced.
	var key := _lot_key
	get_tree().create_timer(0.4).timeout.connect(func():
		# Skip the intro if someone already opened the bidding in the meantime.
		if is_instance_valid(self) and _lot_key == key and Game.store.auction().get("bidder", "") == "":
			Sfx.say(line))


func _announce_bid(amount: int, next: int, interrupt := false) -> void:
	var line := "bid_%d" % amount
	var txt := Sfx.line_text(line)
	if txt == "":
		txt = "%s! Anyone at %s?" % [DB.fmt_price(amount), DB.fmt_price(next)]
	say_label.text = "“%s”" % txt
	Sfx.say(line, interrupt)


func _show_stamp(sold: bool, team: String, price: int) -> void:
	UI.clear(stamp_box)
	if sold:
		stamp_box.add_child(UI.center(UI.caption("Sold to", UI.MUTED, 12)))
		var row := UI.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(UI.crest(team, 72))
		var rv := UI.vbox(-8)
		rv.add_child(UI.display("SOLD!", 76, UI.GREEN))
		rv.add_child(UI.display(DB.fmt_price(price), 34, UI.GOLD))
		row.add_child(rv)
		stamp_box.add_child(row)
		stamp_box.add_child(UI.center(UI.label(DB.team(team).get("name", ""), 15, UI.TEXT, true)))
		Sfx.play("sold")
		Sfx.duck(1.6)
		get_tree().create_timer(0.35).timeout.connect(func(): Sfx.say("vo_sold", true))
	else:
		stamp_box.add_child(UI.center(UI.display("UNSOLD", 80, UI.RED)))
		stamp_box.add_child(UI.center(UI.caption("No franchise made a bid", UI.MUTED, 11)))
		Sfx.play("unsold", -2.0)
		get_tree().create_timer(0.2).timeout.connect(func(): Sfx.say("vo_unsold", true))
	stamp.visible = true
	stamp.modulate.a = 0.0
	stamp_box.pivot_offset = card.size / 2.0
	stamp_box.scale = Vector2(1.5, 1.5)
	stamp_box.rotation_degrees = -6.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(stamp, "modulate:a", 1.0, 0.12)
	tw.tween_property(stamp_box, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(stamp_box, "rotation_degrees", -3.0, 0.28)


func _refresh_strip(leader: String) -> void:
	var s := Game.store
	UI.clear(strip)
	var teams: Dictionary = s.state.get("teams", {})
	for tid in DB.team_ids():
		if not teams.has(tid):
			continue
		var t: Dictionary = teams[tid]
		var is_leader: bool = tid == leader
		var is_me: bool = tid == s.my_team()
		var border := UI.GOLD if is_leader else (UI.GREEN if is_me else UI.LINE)
		var st := UI.box(Color(UI.team_color(tid).darkened(0.6), 0.75) if is_leader else UI.GLASS, 14, 8, border, 2 if (is_leader or is_me) else 1)
		if is_leader:
			UI.glow(st, Color(UI.GOLD, 0.3), 8)
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", st)
		p.custom_minimum_size.x = 74
		var v := UI.vbox(0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var c := UI.crest(tid, 36)
		c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(c)
		v.add_child(UI.center(UI.display(DB.fmt_price(int(t.get("purse", 0))).replace("₹", ""), 18, UI.GOLD if is_leader else UI.TEXT)))
		v.add_child(UI.center(UI.caption("%d • %d✈" % [Rules.squad_count(t), Rules.overseas_count(t)], UI.DIM, 9)))
		p.add_child(v)
		strip.add_child(p)


func _player_row(pid: String, price: int, tid := "") -> Control:
	var p := DB.player(pid)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UI.box(Color(1, 1, 1, 0.03), 12, 10))
	var h := UI.hbox(10)
	row.add_child(h)
	if tid != "":
		h.add_child(UI.crest(tid, 28))
	h.add_child(UI.role_icon(p["role"], 26))
	var n := UI.label(p["name"] + ("  ✈" if p["overseas"] else ""), 14, UI.TEXT, true)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	h.add_child(n)
	h.add_child(UI.label(str(p["ovr"]), 13, UI.MUTED))
	var pr := UI.display(DB.fmt_price(price) if price > 0 else "UNSOLD", 20, UI.GOLD if price > 0 else UI.RED)
	pr.custom_minimum_size.x = 80
	pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(pr)
	return row


func _refresh_lists() -> void:
	var s := Game.store
	UI.clear(squad_list)
	var team := s.team(s.my_team())
	var squad: Dictionary = team.get("squad", {})
	var counts := AI.role_counts(team)
	var need := UI.hbox(6)
	for r in ["BAT", "WK", "AR", "PACE", "SPIN"]:
		var target: int = AI.TARGET[r]
		var ok: bool = counts[r] >= target
		need.add_child(UI.chip("%s %d/%d" % [r, counts[r], target], Color(UI.GREEN, 0.15) if ok else Color(1, 1, 1, 0.05), UI.GREEN if ok else UI.MUTED, 11))
	squad_list.add_child(need)
	if squad.is_empty():
		squad_list.add_child(UI.label("No players yet — start bidding!", 14, UI.MUTED))
	for role in ["WK", "BAT", "AR", "PACE", "SPIN"]:
		for pid in squad:
			if DB.player(pid)["role"] == role:
				squad_list.add_child(_player_row(pid, int(squad[pid])))
	UI.clear(log_list)
	var log: Dictionary = s.state.get("log", {})
	var keys: Array = log.keys()
	keys.sort()
	keys.reverse()
	for k in keys.slice(0, 60):
		var e: Dictionary = log[k]
		log_list.add_child(_player_row(e["pid"], int(e.get("price", 0)), e.get("team", "")))
	if keys.is_empty():
		log_list.add_child(UI.label("Nothing sold yet.", 14, UI.MUTED))
	UI.clear(teams_list)
	var teams: Dictionary = s.state.get("teams", {})
	for tid in DB.team_ids():
		if not teams.has(tid):
			continue
		var t: Dictionary = teams[tid]
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", UI.box(Color(1, 1, 1, 0.03), 12, 10))
		var bv := UI.vbox(4)
		box.add_child(bv)
		var hdr := UI.hbox(8)
		hdr.add_child(UI.crest(tid, 32))
		var who := s.team_owner_name(tid)
		var nl := UI.label("%s%s" % [DB.team(tid)["name"], "" if who == "" else "  (%s)" % who], 14, UI.TEXT, true)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		hdr.add_child(nl)
		hdr.add_child(UI.display("%d  •  %s" % [Rules.squad_count(t), DB.fmt_price(int(t.get("purse", 0)))], 18, UI.GOLD))
		bv.add_child(hdr)
		var names := []
		var sq: Dictionary = t.get("squad", {})
		var ids: Array = sq.keys()
		ids.sort_custom(func(x, y): return int(sq[x]) > int(sq[y]))
		for pid in ids.slice(0, 5):
			names.append("%s %s" % [DB.player(pid)["name"], DB.fmt_price(int(sq[pid]))])
		if not names.is_empty():
			bv.add_child(UI.wrap(UI.label(", ".join(names), 12, UI.MUTED)))
		teams_list.add_child(box)


# ------------------------------------------------------------------ actions

func _bid() -> void:
	var s := Game.store
	if _busy:
		return
	_busy = true
	bid_btn.disabled = true
	UI.pop(bid_btn, 1.04)
	var err: String = await s.bid(s.my_team())
	_busy = false
	if not is_instance_valid(self):
		return
	if err != "":
		status_label.text = err
	_refresh()


func _pass() -> void:
	var s := Game.store
	await s.pass_lot(s.my_team())
