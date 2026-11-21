extends VBoxContainer
## The live auction, styled like a TV broadcast.
##
## Layout (top to bottom): header · "my team" dashboard (purse, squad, overseas,
## max bid; tap for the full squad) · player card · bid panel with the
## auctioneer's call · BID / PASS / FAST-FORWARD · franchise strip (tap any team
## to see its squad) · bottom bar opening the My Squad / All Teams / Sold Log sheets.

const TimerRing := preload("res://scripts/ui/timer_ring.gd")
const TRAITS := {"op": "OPENER", "fin": "FINISHER", "pp": "POWERPLAY", "dth": "DEATH OVERS", "anc": "ANCHOR"}

var set_label: Label
var lot_label: Label
# My-team dashboard
var my_purse: Label
var my_bar: ProgressBar
var my_stats := {}
var my_needs: HBoxContainer
# Player card
var card: PanelContainer
var role_holder: HBoxContainer
var p_name: Label
var p_meta: Label
var p_chips: HBoxContainer
var p_ovr: Label
var p_bars: VBoxContainer
var p_base: Label
var stamp: Control
var stamp_box: VBoxContainer
var banner: Control
var banner_box: VBoxContainer
# Bidding
var bid_panel: PanelContainer
var ring: Control
var bid_caption: Label
var bid_amount: Label
var bid_team_box: HBoxContainer
var say_label: Label
var call_label: Label
var bid_btn: Button
var pass_btn: Button
var ff_btn: Button
var status_label: Label
var strip: HBoxContainer
var nav_btns := {}
# Sheet (full-screen overlay for squads, teams and the log)
var sheet: Sheet

var _lot_key := ""
var _phase := ""
var _list_sig := ""
var _busy := false
var _last_n := -1
var _last_bidder := ""
var _last_tick := -1
var _going_said := ""
var _prompt := ""
var _banner_key := ""


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build_header()
	_build_my_team()
	_build_card()
	_build_bid_panel()
	_build_actions()
	_build_strip()
	Game.store.changed.connect(_refresh)
	_refresh()


# ------------------------------------------------------------------ build

func _build_header() -> void:
	var head := UI.hbox(10)
	head.add_child(UI.button("✕", _leave, "icon"))
	var hv := UI.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_label = UI.caption("", UI.GOLD, 12)
	lot_label = UI.display("", 22, UI.TEXT)
	hv.add_child(set_label)
	hv.add_child(lot_label)
	# Tap the set name to see every player in this set.
	hv.mouse_filter = Control.MOUSE_FILTER_STOP
	hv.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			_open_sheet("set"))
	head.add_child(hv)
	head.add_child(UI.theme_button())
	head.add_child(UI.sound_button())
	add_child(head)


## Your franchise at a glance. The whole panel is a button that opens your squad.
func _build_my_team() -> void:
	var s := Game.store
	var my := s.my_team()
	var b := _tap_panel(UI.box(UI.shade(UI.team_color(my), 0.6, 0.82), 18, 12, Color(UI.team_accent(my), 0.55), 1),
		func(): _open_sheet("team:" + Game.store.my_team()))
	var h := UI.hbox(12)
	b.add_child(h)
	h.add_child(UI.crest(my, 52))
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := UI.hbox(6)
	var nm := UI.caption(DB.team(my).get("name", "Your team"), UI.MUTED, 10)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	top.add_child(nm)
	top.add_child(UI.caption("Squad ›", UI.GOLD, 10))
	v.add_child(top)
	var row := UI.hbox(10)
	var pv := UI.vbox(-4)
	pv.add_child(UI.caption("Purse left", UI.DIM, 9))
	my_purse = UI.display("", 30, UI.GOLD)
	pv.add_child(my_purse)
	row.add_child(pv)
	for k in ["Squad", "Overseas", "Max bid"]:
		var sv := UI.vbox(-4)
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_child(UI.center(UI.caption(k, UI.DIM, 9)))
		var val := UI.center(UI.display("", 22, UI.TEXT))
		sv.add_child(val)
		my_stats[k] = val
		row.add_child(sv)
	v.add_child(row)
	my_bar = _purse_bar()
	v.add_child(my_bar)
	my_needs = UI.hbox(4)
	v.add_child(my_needs)
	h.add_child(v)
	UI.ignore_mouse(h)
	add_child(b)


func _build_card() -> void:
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.glow(UI.box(UI.GLASS, 20, 14, Color(UI.GOLD, 0.25)), Color(0, 0, 0, 0.12 if UI.light else 0.35), 14))
	var cv := UI.vbox(8)
	card.add_child(cv)
	var top := UI.hbox(12)
	role_holder = UI.hbox(0)
	top.add_child(role_holder)
	var nv := UI.vbox(2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_meta = UI.caption("", UI.MUTED, 10)
	nv.add_child(p_meta)
	p_name = UI.display("", 36, UI.TEXT)
	p_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(p_name)
	p_chips = UI.hbox(6)
	nv.add_child(p_chips)
	top.add_child(nv)
	var ov := UI.vbox(-8)
	p_ovr = UI.display("", 50, UI.GOLD)
	p_ovr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov.add_child(p_ovr)
	ov.add_child(UI.center(UI.caption("OVR", UI.GOLD, 10)))
	top.add_child(ov)
	cv.add_child(top)
	var bottom := UI.hbox(14)
	p_bars = UI.vbox(4)
	p_bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(p_bars)
	var bv := UI.vbox(-4)
	bv.add_child(UI.caption("Base", UI.MUTED, 9))
	p_base = UI.display("", 22, UI.TEXT)
	bv.add_child(p_base)
	bottom.add_child(bv)
	cv.add_child(bottom)
	# SOLD / UNSOLD overlay.
	# A plain Control has no minimum size, so the stamp overlays the card
	# without making it taller.
	stamp = Control.new()
	stamp.visible = false
	var sbg := Panel.new()
	sbg.add_theme_stylebox_override("panel", UI.box(Color(UI.BG, 0.92), 20, 10))
	sbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stamp.add_child(sbg)
	stamp_box = UI.vbox(0)
	stamp_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stamp_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	stamp.add_child(stamp_box)
	card.add_child(stamp)
	# "Now we have the ... set" banner, shown on the first lot of each set.
	banner = Control.new()
	banner.visible = false
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bbg := Panel.new()
	bbg.add_theme_stylebox_override("panel", UI.glow(UI.box(UI.BG, 20, 10, UI.GOLD, 2), Color(UI.GOLD, 0.3), 12))
	bbg.add_child(_full(UI.box(Color(UI.GOLD, 0.1), 20, 10)))
	bbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(bbg)
	banner_box = UI.vbox(2)
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner.add_child(banner_box)
	card.add_child(banner)
	add_child(card)


func _build_bid_panel() -> void:
	bid_panel = PanelContainer.new()
	var bh := UI.hbox(14)
	bid_panel.add_child(bh)
	ring = TimerRing.new()
	ring.custom_minimum_size = Vector2(80, 80)
	bh.add_child(ring)
	var bv := UI.vbox(0)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bid_caption = UI.caption("Current bid", UI.MUTED, 10)
	bv.add_child(bid_caption)
	bid_amount = UI.display("", 46, UI.GOLD)
	bv.add_child(bid_amount)
	bid_team_box = UI.hbox(8)
	bv.add_child(bid_team_box)
	say_label = UI.label("", 12, UI.MUTED)
	say_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(say_label)
	bh.add_child(bv)
	add_child(bid_panel)
	call_label = UI.center(UI.display("", 22, UI.GOLD))
	call_label.custom_minimum_size.y = 24
	add_child(call_label)


func _build_actions() -> void:
	var row := UI.hbox(8)
	bid_btn = UI.button("BID", _bid, "primary", 22)
	bid_btn.custom_minimum_size.y = 62
	bid_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bid_btn.size_flags_stretch_ratio = 2.4
	row.add_child(bid_btn)
	pass_btn = UI.button("PASS", _pass, "ghost", 17)
	pass_btn.custom_minimum_size.y = 62
	pass_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pass_btn)
	if not Game.store.is_online():
		# Single player only: skip straight to the final bid for this player.
		ff_btn = UI.button("▶▶", _fast_forward, "ghost", 15)
		ff_btn.tooltip_text = "Fast-forward to the final bid"
		ff_btn.custom_minimum_size = Vector2(70, 62)
		row.add_child(ff_btn)
	add_child(row)
	status_label = UI.center(UI.label("", 13, UI.RED, true))
	status_label.custom_minimum_size.y = 16
	add_child(status_label)


func _build_strip() -> void:
	var cap := UI.hbox(6)
	var cv := UI.vbox(-2)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_child(UI.caption("Franchises", UI.MUTED, 10))
	cv.add_child(UI.caption("Tap a team to see its squad", UI.DIM, 9))
	cap.add_child(cv)
	for pair in [["set", "THIS SET"], ["teams", "ALL TEAMS"], ["log", "SOLD LOG"]]:
		var key: String = pair[0]
		var b := UI.small_button(pair[1], func(): _open_sheet(key))
		b.custom_minimum_size = Vector2(0, 32)
		nav_btns[key] = b
		cap.add_child(b)
	add_child(cap)
	var sc := TouchScroll.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = 94
	strip = UI.hbox(8)
	sc.add_child(strip)
	add_child(sc)


## A flat panel-shaped button that holds arbitrary content.
func _tap_panel(style: StyleBoxFlat, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.border_color = UI.GOLD
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(func():
		UI._click()
		cb.call())
	return b


func _purse_bar() -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = Rules.PURSE
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 6)
	pb.add_theme_stylebox_override("fill", UI.box(UI.GOLD, 3, 0))
	pb.add_theme_stylebox_override("background", UI.box(UI.ink(0.08), 3, 0))
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb


# ------------------------------------------------------------------ per frame

func _leave() -> void:
	Game.leave_room()
	Game.goto("home")


func _process(_dt: float) -> void:
	var s := Game.store
	if s == null or not is_instance_valid(s):
		return
	_fit_tap_panels()
	var a := s.auction()
	var left := maxi(0, int(a.get("ends", 0)) - s.now_ms())
	var total := float(Auction.timer_ms(s.state) + (int(a.get("intro", 0)) if int(a.get("n", 0)) == 0 else 0))
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


## Buttons don't size to their children; keep the dashboard panel tall enough.
func _fit_tap_panels() -> void:
	for b in get_children():
		if b is Button and b.get_child_count() > 0:
			var inner: Control = b.get_child(0)
			var st: StyleBox = b.get_theme_stylebox("normal")
			var want: float = inner.get_combined_minimum_size().y + st.get_margin(SIDE_TOP) + st.get_margin(SIDE_BOTTOM)
			if absf(b.custom_minimum_size.y - want) > 0.5:
				b.custom_minimum_size.y = want
			inner.position = Vector2(st.get_margin(SIDE_LEFT), st.get_margin(SIDE_TOP))
			inner.size = Vector2(b.size.x - st.get_margin(SIDE_LEFT) - st.get_margin(SIDE_RIGHT), want - st.get_margin(SIDE_TOP) - st.get_margin(SIDE_BOTTOM))


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
	var in_set := Auction.set_players(s.state)
	var done := 0
	for e in in_set:
		if e["status"] == "sold" or e["status"] == "unsold":
			done += 1
	set_label.text = "%s  •  %d/%d  ›" % [Auction.set_label(Auction.lot_set(s.state)).to_upper(), mini(done + 1, in_set.size()), in_set.size()]
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
		var new_set := Auction.set_starts(s.state) and int(a.get("n", 0)) == 0 and not s.fast_forwarding()
		if new_set:
			_show_banner(Auction.lot_set(s.state), in_set.size())
		_announce_open(p, Auction.lot_set(s.state) if new_set else "")
		card.pivot_offset = card.size / 2.0
		card.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(card, "modulate:a", 1.0, 0.25)

	var bidder: String = a.get("bidder", "")
	if (bidder != "" or key != _banner_key) and banner.visible:
		_hide_banner(_banner_key)
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
			if not s.fast_forwarding():
				_announce_bid(amount, Auction.current_next(s.state), Auction.human_teams(s.state).has(bidder))
		_last_n = n
		_last_bidder = bidder
	bid_caption.text = "CURRENT BID" if bidder != "" else "OPENING AT BASE PRICE"
	bid_amount.text = DB.fmt_price(amount if bidder != "" else int(p["base"])).replace("₹", "₹ ")
	_style_bid_panel(bidder)
	UI.clear(bid_team_box)
	if bidder != "":
		bid_team_box.add_child(UI.crest(bidder, 28))
		var who := s.team_owner_name(bidder)
		var nm := UI.label(DB.team(bidder)["name"], 14, UI.TEXT, true)
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var ff := s.fast_forwarding()
	bid_btn.text = "YOU LEAD" if leading else "BID  %s" % DB.fmt_price(next)
	bid_btn.disabled = phase != "bidding" or leading or err != "" or _busy or ff
	var passed: bool = a.get("passes", {}).has(my)
	pass_btn.text = "PASSED" if passed else "PASS"
	pass_btn.disabled = phase != "bidding" or leading or passed or ff
	if ff_btn:
		ff_btn.disabled = phase != "bidding" or ff
	status_label.text = err if (err != "" and phase == "bidding" and not leading) else ""
	# Whose turn is it? Spell it out like an auctioneer would.
	if phase != "bidding":
		_prompt = ""
	elif ff:
		_prompt = "FAST-FORWARDING…"
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
	_refresh_my_team(t)
	_refresh_strip(bidder)
	var open := sheet != null and is_instance_valid(sheet)
	var sig := "%d|%d|%s|%s" % [s.state.get("log", {}).size(), Rules.squad_count(t), sheet.top_title() if open else "", _lot_key + phase]
	if sig != _list_sig:
		_list_sig = sig
		nav_btns["log"].text = "SOLD LOG (%d)" % s.state.get("log", {}).size()
		if open:
			sheet.refresh()


func _refresh_my_team(t: Dictionary) -> void:
	var purse := int(t.get("purse", 0))
	my_purse.text = DB.fmt_price(purse)
	my_bar.value = purse
	my_stats["Squad"].text = "%d/%d" % [Rules.squad_count(t), Rules.MAX_SQUAD]
	my_stats["Overseas"].text = "%d/%d" % [Rules.overseas_count(t), Rules.MAX_OVERSEAS]
	my_stats["Max bid"].text = DB.fmt_price(maxi(0, Rules.max_affordable(t)))
	var counts := AI.role_counts(t)
	var sig := str(counts)
	if my_needs.get_meta("sig", "") == sig:
		return
	my_needs.set_meta("sig", sig)
	UI.clear(my_needs)
	for r in ["WK", "BAT", "AR", "PACE", "SPIN"]:
		my_needs.add_child(_need_chip(r, counts[r], AI.TARGET[r], 9))
	UI.ignore_mouse(my_needs)


func _need_chip(role: String, have: int, want: int, size := 11) -> Control:
	var ok := have >= want
	return UI.chip("%s %d/%d" % [role, have, want], Color(UI.GREEN, 0.16) if ok else UI.ink(0.06),
		UI.GREEN if ok else UI.MUTED, size)


func _style_bid_panel(bidder: String) -> void:
	var col := UI.team_color(bidder) if bidder != "" else UI.MUTED
	var bg := UI.shade(col, 0.45, 0.88) if bidder != "" else UI.GLASS
	var border := UI.team_accent(bidder) if bidder != "" else UI.LINE
	bid_panel.add_theme_stylebox_override("panel",
		UI.glow(UI.box(bg, 20, 14, Color(border, 0.7), 2), Color(border, 0.25 if bidder != "" else 0.0), 12))


func _show_player(p: Dictionary) -> void:
	UI.clear(role_holder)
	role_holder.add_child(UI.role_icon(p["role"], 66))
	p_name.text = p["name"].to_upper()
	p_meta.text = "%s  •  %s  •  %s" % [p["country"], DB.role_label(p["role"]), "Capped" if p["capped"] else "Uncapped"]
	p_ovr.text = str(p["ovr"])
	UI.clear(p_chips)
	if p["overseas"]:
		p_chips.add_child(UI.chip("✈ OVERSEAS", Color(UI.BLUE, 0.2), UI.soft(UI.BLUE, 0.4), 10))
	if TRAITS.has(p["trait"]):
		p_chips.add_child(UI.chip(TRAITS[p["trait"]], Color(UI.GOLD, 0.15), UI.GOLD, 10))
	UI.clear(p_bars)
	p_bars.add_child(UI.rating_bar("BAT", p["bat"], UI.GREEN))
	p_bars.add_child(UI.rating_bar("BOWL", p["bowl"], UI.BLUE))
	p_base.text = DB.fmt_price(int(p["base"]))


# ------------------------------------------------------------------ auctioneer

func _announce_open(p: Dictionary, new_set := "") -> void:
	var base := int(p["base"])
	var line := "open_%d" % base
	var txt := Sfx.line_text(line)
	if txt == "":
		txt = "Next up, base price %s. Who'll open the bidding?" % DB.fmt_price(base)
	var key := _lot_key
	if new_set != "":
		# A new set: "Now we have the capped batters!", then the first lot.
		var sl := "set_" + new_set.to_lower()
		var stxt := Sfx.line_text(sl)
		if stxt == "":
			stxt = "Now we have the %s!" % Auction.set_label(new_set).to_lower()
		say_label.text = "“%s”" % stxt
		# Let the previous SOLD call finish first (up to ~1.5 s).
		var waited := 0.0
		while Sfx.talking() and waited < 1.5:
			await get_tree().create_timer(0.1).timeout
			waited += 0.1
			if not is_instance_valid(self) or _lot_key != key:
				return
		Sfx.say(sl, true)
		await get_tree().create_timer(maxf(0.4, Sfx.line_ms(sl) / 1000.0 - 0.3)).timeout
		if not is_instance_valid(self) or _lot_key != key:
			return
		if Game.store.auction().get("bidder", "") == "":
			say_label.text = "“%s”" % txt
			Sfx.say(line)
		return
	say_label.text = "“%s”" % txt
	# Let the SOLD call finish before the next lot is introduced.
	get_tree().create_timer(0.4).timeout.connect(func():
		# Skip the intro if someone already opened the bidding in the meantime.
		if is_instance_valid(self) and _lot_key == key and Game.store.auction().get("bidder", "") == "":
			Sfx.say(line))


## Big "NOW WE HAVE THE CAPPED BATTERS" card over the player while the set is announced.
func _show_banner(set_id: String, count: int) -> void:
	UI.clear(banner_box)
	var is_accel := set_id == "ACCEL"
	var top := "End of round one" if is_accel else ("Let the auction begin" if set_id == "MARQUEE" else "Now we have the")
	banner_box.add_child(UI.center(UI.caption(top, UI.TEXT, 12)))
	var t := UI.display(Auction.set_label(set_id).to_upper(), 40, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(t)
	var sub := ("%d unsold players get one more chance" % count) if is_accel else ("%d players in this set" % count)
	banner_box.add_child(UI.center(UI.label(sub, 14, UI.TEXT, true)))
	banner_box.add_child(UI.center(UI.caption("Tap the set name above to see them all", UI.MUTED, 9)))
	var key := _lot_key
	_banner_key = key
	banner.visible = true
	banner.modulate.a = 0.0
	banner_box.pivot_offset = card.size / 2.0
	banner_box.scale = Vector2(0.85, 0.85)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.2)
	tw.tween_property(banner_box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var hold := clampi(Sfx.line_ms("set_" + set_id.to_lower()), 2500, 8000) / 1000.0
	get_tree().create_timer(hold).timeout.connect(func(): _hide_banner(key))


func _full(st: StyleBox) -> Panel:
	var pn := Panel.new()
	pn.add_theme_stylebox_override("panel", st)
	pn.set_anchors_preset(Control.PRESET_FULL_RECT)
	pn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pn


func _hide_banner(key: String) -> void:
	if not is_instance_valid(self) or _banner_key != key or not banner.visible:
		return
	_banner_key = ""
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func(): banner.visible = false)


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
		row.add_child(UI.crest(team, 56))
		var rv := UI.vbox(-8)
		rv.add_child(UI.display("SOLD!", 58, UI.GREEN))
		rv.add_child(UI.display(DB.fmt_price(price), 28, UI.GOLD))
		row.add_child(rv)
		stamp_box.add_child(row)
		var tname: String = DB.team(team).get("name", "")
		stamp_box.add_child(UI.center(UI.label(tname, 14, UI.TEXT, true)))
		say_label.text = "“Sold! To the %s, for %s!”" % [tname, DB.fmt_price(price)]
		Sfx.play("sold")
		Sfx.duck(1.6)
		get_tree().create_timer(0.35).timeout.connect(func(): Sfx.say_sold(team))
	else:
		stamp_box.add_child(UI.center(UI.display("UNSOLD", 64, UI.RED)))
		stamp_box.add_child(UI.center(UI.caption("No franchise made a bid", UI.MUTED, 11)))
		say_label.text = "“Unsold!”"
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
	var teams: Dictionary = s.state.get("teams", {})
	var sig := leader
	for tid in teams:
		sig += "|%s%d%d" % [tid, int(teams[tid].get("purse", 0)), Rules.squad_count(teams[tid])]
	if strip.get_meta("sig", "") == sig:
		return
	strip.set_meta("sig", sig)
	UI.clear(strip)
	for tid in DB.team_ids():
		if not teams.has(tid):
			continue
		var t: Dictionary = teams[tid]
		var is_leader: bool = tid == leader
		var is_me: bool = tid == s.my_team()
		var border := UI.GOLD if is_leader else (UI.GREEN if is_me else UI.LINE)
		var st := UI.box(UI.shade(UI.team_color(tid), 0.6, 0.75) if is_leader else UI.GLASS, 14, 8, border, 2 if (is_leader or is_me) else 1)
		if is_leader:
			UI.glow(st, Color(UI.GOLD, 0.3), 8)
		var b := _tap_panel(st, func(): _open_sheet("team:" + tid))
		b.custom_minimum_size = Vector2(78, 92)
		var v := UI.vbox(0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var c := UI.crest(tid, 34)
		c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(c)
		v.add_child(UI.center(UI.display(DB.fmt_price(int(t.get("purse", 0))).replace("₹", ""), 18, UI.GOLD if is_leader else UI.TEXT)))
		var who := "YOU" if is_me else ("AI" if t.get("ai", false) else s.team_owner_name(tid).to_upper().left(6))
		v.add_child(UI.center(UI.caption("%d • %s" % [Rules.squad_count(t), who], UI.GREEN if is_me else UI.DIM, 9)))
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_top = 6
		v.offset_bottom = -6
		UI.ignore_mouse(v)
		b.add_child(v)
		strip.add_child(b)


# ------------------------------------------------------------------ sheets

## Opens a full-screen sheet: "team:<id>", "teams" or "log".
func _open_sheet(kind: String) -> void:
	if sheet != null and is_instance_valid(sheet):
		sheet.close()
	_list_sig = ""
	if kind.begins_with("team:"):
		var tid := kind.substr(5)
		sheet = Sheet.open(self, _team_title(tid), func(body, _sh): Views.team_page(body, tid))
	elif kind == "teams":
		sheet = Sheet.open(self, "ALL FRANCHISES", _fill_teams)
	elif kind == "set":
		sheet = Sheet.open(self, "THIS SET", _fill_set)
	else:
		sheet = Sheet.open(self, "SOLD LOG", _fill_log)


func _team_title(tid: String) -> String:
	return "YOUR SQUAD" if tid == Game.store.my_team() else DB.team(tid).get("name", "").to_upper()


func _fill_teams(body: VBoxContainer, sh: Sheet) -> void:
	Views.teams_list(body, func(tid): sh.push(_team_title(tid), func(b, _s): Views.team_page(b, tid)))


## Every player in the current set: on the block, still to come, sold, unsold.
func _fill_set(body: VBoxContainer, _sh: Sheet) -> void:
	var s := Game.store
	var set_id := Auction.lot_set(s.state)
	var all := Auction.set_players(s.state)
	var groups := {"live": [], "next": [], "sold": [], "unsold": []}
	for e in all:
		groups[e["status"]].append(e)
	var hero := UI.panel(Color(UI.GOLD, 0.1), 16, 12, Color(UI.GOLD, 0.5))
	var hv := UI.vbox(6)
	hero.add_child(hv)
	hv.add_child(UI.display(Auction.set_label(set_id).to_upper(), 28, UI.GOLD))
	var stats := UI.hbox(8)
	for pair in [["PLAYERS", all.size(), UI.TEXT], ["SOLD", groups["sold"].size(), UI.GREEN],
			["UNSOLD", groups["unsold"].size(), UI.RED], ["TO COME", groups["next"].size() + groups["live"].size(), UI.TEXT]]:
		var sv := UI.vbox(-4)
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_child(UI.center(UI.caption(pair[0], UI.DIM, 9)))
		sv.add_child(UI.center(UI.display(str(pair[1]), 24, pair[2])))
		stats.add_child(sv)
	hv.add_child(stats)
	var spent := 0
	for e in groups["sold"]:
		spent += int(e["price"])
	if spent > 0:
		hv.add_child(UI.caption("Spent in this set: %s" % DB.fmt_price(spent), UI.MUTED, 10))
	body.add_child(hero)
	if not groups["live"].is_empty():
		body.add_child(Views.section("ON THE BLOCK"))
		for e in groups["live"]:
			body.add_child(Views.player_row(e["pid"], -1, "", {"tag": ["LIVE", UI.GOLD]}))
	if not groups["next"].is_empty():
		body.add_child(Views.section("COMING UP", "in auction order"))
		var i := 1
		for e in groups["next"]:
			var p := DB.player(e["pid"])
			body.add_child(Views.player_row(e["pid"], -1, "", {"num": i, "tag": [DB.fmt_price(int(p["base"])), UI.MUTED],
				"line": "%s  •  BAT %d  •  BOWL %d  •  base price" % [DB.role_label(p["role"]), p["bat"], p["bowl"]]}))
			i += 1
	if not groups["sold"].is_empty():
		body.add_child(Views.section("SOLD", str(groups["sold"].size())))
		var sold: Array = groups["sold"].duplicate()
		sold.reverse()
		for e in sold:
			body.add_child(Views.player_row(e["pid"], int(e["price"]), e["team"]))
	if not groups["unsold"].is_empty():
		body.add_child(Views.section("UNSOLD", str(groups["unsold"].size())))
		for e in groups["unsold"]:
			body.add_child(Views.player_row(e["pid"], 0))


func _fill_log(body: VBoxContainer, _sh: Sheet) -> void:
	var log: Dictionary = Game.store.state.get("log", {})
	var keys: Array = log.keys()
	keys.sort()
	keys.reverse()
	if keys.is_empty():
		body.add_child(UI.center(UI.label("Nothing sold yet.", 15, UI.MUTED)))
		return
	for k in keys.slice(0, 120):
		var e: Dictionary = log[k]
		body.add_child(Views.player_row(e["pid"], int(e.get("price", 0)), e.get("team", "")))


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


func _fast_forward() -> void:
	Sfx.hush()
	say_label.text = "“Fast-forwarding to the final bid…”"
	Game.store.fast_forward()
	_refresh()
